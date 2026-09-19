import CoreGraphics
import Foundation
import Libavcodec
import Libavformat
import Libavutil
import Libswscale

struct VideoThumbnail: @unchecked Sendable {
    let image: CGImage
    /// The timestamp actually decoded, in seconds — not the requested one, which lands mid-GOP.
    let timestamp: Double
}

enum ThumbnailError: Error, CustomStringConvertible {
    case open(Int32)
    case streamInfo(Int32)
    case noVideoStream
    case decoderUnavailable
    case decoderOpen(Int32)
    case seek(Int32)
    case noFrame
    case scalerUnavailable
    case imageCreationFailed

    var description: String {
        switch self {
        case .open(let code): "open failed: \(ThumbnailError.message(code))"
        case .streamInfo(let code): "stream info failed: \(ThumbnailError.message(code))"
        case .noVideoStream: "no video stream"
        case .decoderUnavailable: "no decoder for this codec"
        case .decoderOpen(let code): "decoder open failed: \(ThumbnailError.message(code))"
        case .seek(let code): "seek failed: \(ThumbnailError.message(code))"
        case .noFrame: "no frame decoded"
        case .scalerUnavailable: "could not create scaler"
        case .imageCreationFailed: "could not build CGImage"
        }
    }

    /// `av_err2str` is a C macro, so the buffer dance has to happen on this side.
    static func message(_ code: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        av_strerror(code, &buffer, buffer.count)
        return String(cString: buffer)
    }
}

/// Pulls a single frame out of a video file using FFmpeg directly.
///
/// `nonisolated` because the project defaults to MainActor isolation and every step here is blocking
/// C code that must stay off the main thread.
nonisolated enum VideoThumbnailer {
    /// Frames are grabbed from this window: past the cold open, before anything worth spoiling.
    private static let previewWindow: ClosedRange<Double> = 240...360

    private static let queue = DispatchQueue(
        label: "com.vanillacoffeesoft.ChocoPan.thumbnailer",
        qos: .utility,
        attributes: .concurrent
    )

    /// A random point in the 4–6 minute window, falling back proportionally for short videos so they
    /// still produce something rather than failing.
    static func randomPreviewTime(duration: Double) -> Double {
        guard duration > 0 else { return 0 }
        if duration > previewWindow.upperBound {
            return Double.random(in: previewWindow)
        }
        return Double.random(in: (duration * 0.2)...(duration * 0.4))
    }

    static func thumbnail(for url: URL, maxWidth: Int = 640) async throws -> VideoThumbnail {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try extractFrame(from: url, maxWidth: maxWidth))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Extraction

    static func extractFrame(from url: URL, maxWidth: Int) throws -> VideoThumbnail {
        var formatContext: UnsafeMutablePointer<AVFormatContext>?
        var status = avformat_open_input(&formatContext, url.path, nil, nil)
        guard status >= 0, let format = formatContext else { throw ThumbnailError.open(status) }
        defer { avformat_close_input(&formatContext) }

        status = avformat_find_stream_info(format, nil)
        guard status >= 0 else { throw ThumbnailError.streamInfo(status) }

        var decoder: UnsafePointer<AVCodec>?
        let streamIndex = av_find_best_stream(format, AVMEDIA_TYPE_VIDEO, -1, -1, &decoder, 0)
        guard streamIndex >= 0, let stream = format.pointee.streams[Int(streamIndex)] else {
            throw ThumbnailError.noVideoStream
        }
        guard let decoder else { throw ThumbnailError.decoderUnavailable }

        guard let codecContext = avcodec_alloc_context3(decoder) else {
            throw ThumbnailError.decoderUnavailable
        }
        var mutableCodecContext: UnsafeMutablePointer<AVCodecContext>? = codecContext
        defer { avcodec_free_context(&mutableCodecContext) }

        avcodec_parameters_to_context(codecContext, stream.pointee.codecpar)
        codecContext.pointee.thread_count = 0  // auto

        status = avcodec_open2(codecContext, decoder, nil)
        guard status >= 0 else { throw ThumbnailError.decoderOpen(status) }

        let timeBase = stream.pointee.time_base
        let secondsPerTick = Double(timeBase.num) / Double(timeBase.den)
        let target = randomPreviewTime(duration: duration(of: format, stream: stream))

        // AV_TIME_BASE_Q is a compound-literal macro and does not import into Swift.
        let microsecondBase = AVRational(num: 1, den: AV_TIME_BASE)
        let seekTarget = av_rescale_q(Int64(target * Double(AV_TIME_BASE)), microsecondBase, timeBase)

        status = av_seek_frame(format, streamIndex, seekTarget, AVSEEK_FLAG_BACKWARD)
        guard status >= 0 else { throw ThumbnailError.seek(status) }
        // Required: without it, frames buffered from before the seek come back first.
        avcodec_flush_buffers(codecContext)

        // These must stay optional-typed: av_frame_free/av_packet_free take a pointer-to-optional.
        var frameRef: UnsafeMutablePointer<AVFrame>? = av_frame_alloc()
        var packetRef: UnsafeMutablePointer<AVPacket>? = av_packet_alloc()
        defer {
            av_frame_free(&frameRef)
            av_packet_free(&packetRef)
        }
        guard let frame = frameRef, let packet = packetRef else { throw ThumbnailError.noFrame }

        var decodedSeconds = target
        var reachedTarget = false

        readLoop: while av_read_frame(format, packet) >= 0 {
            defer { av_packet_unref(packet) }
            guard packet.pointee.stream_index == streamIndex else { continue }
            guard avcodec_send_packet(codecContext, packet) >= 0 else { continue }

            while avcodec_receive_frame(codecContext, frame) >= 0 {
                let stamp = frame.pointee.best_effort_timestamp
                if stamp != Int64.min {  // AV_NOPTS_VALUE
                    decodedSeconds = Double(stamp) * secondsPerTick
                }
                // No av_frame_unref here on purpose: avcodec_receive_frame unrefs before filling,
                // so after the loop `frame` still holds the last frame decoded — the fallback if
                // the stream ends before the target.
                if decodedSeconds >= target {
                    reachedTarget = true
                    break readLoop
                }
            }
        }

        guard reachedTarget || frame.pointee.width > 0 else { throw ThumbnailError.noFrame }

        let image = try render(frame: frame, format: format, stream: stream, maxWidth: maxWidth)
        return VideoThumbnail(image: image, timestamp: decodedSeconds)
    }

    /// Container duration, in seconds, falling back to the stream's own when the container has none.
    private static func duration(
        of format: UnsafeMutablePointer<AVFormatContext>,
        stream: UnsafeMutablePointer<AVStream>
    ) -> Double {
        if format.pointee.duration > 0 {
            return Double(format.pointee.duration) / Double(AV_TIME_BASE)
        }
        if stream.pointee.duration > 0 {
            let timeBase = stream.pointee.time_base
            return Double(stream.pointee.duration) * Double(timeBase.num) / Double(timeBase.den)
        }
        return 0
    }

    // MARK: - Scaling and image creation

    private static func render(
        frame: UnsafeMutablePointer<AVFrame>,
        format: UnsafeMutablePointer<AVFormatContext>,
        stream: UnsafeMutablePointer<AVStream>,
        maxWidth: Int
    ) throws -> CGImage {
        let sourceWidth = Int(frame.pointee.width)
        let sourceHeight = Int(frame.pointee.height)
        guard sourceWidth > 0, sourceHeight > 0 else { throw ThumbnailError.noFrame }

        // Honour anamorphic content: pixel dimensions are not always display dimensions.
        let aspect = av_guess_sample_aspect_ratio(format, stream, frame)
        var displayWidth = sourceWidth
        if aspect.num > 0, aspect.den > 0 {
            displayWidth = sourceWidth * Int(aspect.num) / Int(aspect.den)
        }

        let scale = min(1.0, Double(maxWidth) / Double(displayWidth))
        // Even dimensions keep swscale on its fast paths.
        let targetWidth = max(2, Int((Double(displayWidth) * scale).rounded()) & ~1)
        let targetHeight = max(2, Int((Double(sourceHeight) * scale).rounded()) & ~1)

        let sourceFormat = AVPixelFormat(rawValue: frame.pointee.format)
        guard let scaler = sws_getContext(
            Int32(sourceWidth), Int32(sourceHeight), sourceFormat,
            Int32(targetWidth), Int32(targetHeight), AV_PIX_FMT_RGBA,
            Int32(SWS_BILINEAR.rawValue), nil, nil, nil
        ) else {
            throw ThumbnailError.scalerUnavailable
        }
        defer { sws_freeContext(scaler) }

        var destinationRef: UnsafeMutablePointer<AVFrame>? = av_frame_alloc()
        defer { av_frame_free(&destinationRef) }
        guard let destination = destinationRef else { throw ThumbnailError.noFrame }

        destination.pointee.format = AV_PIX_FMT_RGBA.rawValue
        destination.pointee.width = Int32(targetWidth)
        destination.pointee.height = Int32(targetHeight)
        guard av_frame_get_buffer(destination, 0) >= 0 else { throw ThumbnailError.noFrame }
        guard sws_scale_frame(scaler, destination, frame) >= 0 else {
            throw ThumbnailError.scalerUnavailable
        }

        let bytesPerRow = Int(destination.pointee.linesize.0)
        guard let pixels = destination.pointee.data.0 else { throw ThumbnailError.imageCreationFailed }

        let data = Data(bytes: pixels, count: bytesPerRow * targetHeight)
        guard let provider = CGDataProvider(data: data as CFData) else {
            throw ThumbnailError.imageCreationFailed
        }

        // RGBA in memory order: big-endian words with the alpha byte last and ignored.
        let bitmapInfo = CGBitmapInfo(
            rawValue: CGImageAlphaInfo.noneSkipLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        )
        guard let image = CGImage(
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else {
            throw ThumbnailError.imageCreationFailed
        }
        return image
    }
}
