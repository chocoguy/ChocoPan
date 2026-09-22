import Foundation
import Libavformat
import Libavutil

nonisolated final class SMBAVInput {
    private static let bufferSize = 1 << 20  // 1 MiB
    let format: UnsafeMutablePointer<AVFormatContext>

    private var formatRef: UnsafeMutablePointer<AVFormatContext>?
    private var io: UnsafeMutablePointer<AVIOContext>?
    private var cursor: Unmanaged<SMBReadCursor>?

    init(session: SMBSession, path: String, size: Int64) throws {
        let cursor = Unmanaged.passRetained(SMBReadCursor(session: session, path: path, size: size))

        guard let buffer = av_malloc(Self.bufferSize) else {
            cursor.release()
            throw ThumbnailError.ioSetupFailed
        }

        guard let io = avio_alloc_context(
            buffer.assumingMemoryBound(to: UInt8.self),
            Int32(Self.bufferSize),
            0,  // read-only
            cursor.toOpaque(),
            smbReadPacket,
            nil,
            smbSeek
        ) else {
            av_free(buffer)
            cursor.release()
            throw ThumbnailError.ioSetupFailed
        }

        guard let allocated = avformat_alloc_context() else {
            Self.releaseIO(io)
            cursor.release()
            throw ThumbnailError.ioSetupFailed
        }
        allocated.pointee.pb = io
        allocated.pointee.flags |= AVFMT_FLAG_CUSTOM_IO

        var ref: UnsafeMutablePointer<AVFormatContext>? = allocated
        let status = avformat_open_input(&ref, nil, nil, nil)
        guard status >= 0, let opened = ref else {
            Self.releaseIO(io)
            cursor.release()
            throw ThumbnailError.open(status)
        }

        self.format = opened
        self.formatRef = ref
        self.io = io
        self.cursor = cursor
    }

    deinit {
        close()
    }

    func close() {
        if formatRef != nil {
            avformat_close_input(&formatRef)
        }
        if let io {
            Self.releaseIO(io)
            self.io = nil
        }
        cursor?.release()
        cursor = nil
    }

    private static func releaseIO(_ io: UnsafeMutablePointer<AVIOContext>) {
        var ref: UnsafeMutablePointer<AVIOContext>? = io
        withUnsafeMutablePointer(to: &io.pointee.buffer) { av_freep($0) }
        avio_context_free(&ref)
    }
}



nonisolated private final class SMBReadCursor: @unchecked Sendable {
    static let eof: Int32 = -541_478_725

    private let session: SMBSession
    private let path: String
    private let size: Int64
    private var offset: Int64 = 0

    init(session: SMBSession, path: String, size: Int64) {
        self.session = session
        self.path = path
        self.size = size
    }

    func read(into buffer: UnsafeMutablePointer<UInt8>, count: Int) -> Int32 {
        guard count > 0, offset < size else { return Self.eof }

        let wanted = Int(min(Int64(count), size - offset))
        guard let data = session.readSync(path: path, offset: offset, length: wanted),
              !data.isEmpty else {
            return Self.eof
        }

        data.copyBytes(to: buffer, count: data.count)
        offset += Int64(data.count)
        return Int32(data.count)
    }

    func seek(to requested: Int64, whence: Int32) -> Int64 {
        if whence & AVSEEK_SIZE != 0 { return size }

        let base: Int64
        switch whence & ~AVSEEK_FORCE {
        case SEEK_SET: base = 0
        case SEEK_CUR: base = offset
        case SEEK_END: base = size
        default: return -1
        }

        let target = base + requested
        guard target >= 0, target <= size else { return -1 }
        offset = target
        return target
    }
}


nonisolated private let smbReadPacket: @convention(c) (
    UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt8>?, Int32
) -> Int32 = { opaque, buffer, count in
    guard let opaque, let buffer else { return SMBReadCursor.eof }
    return Unmanaged<SMBReadCursor>.fromOpaque(opaque)
        .takeUnretainedValue()
        .read(into: buffer, count: Int(count))
}

nonisolated private let smbSeek: @convention(c) (
    UnsafeMutableRawPointer?, Int64, Int32
) -> Int64 = { opaque, offset, whence in
    guard let opaque else { return -1 }
    return Unmanaged<SMBReadCursor>.fromOpaque(opaque)
        .takeUnretainedValue()
        .seek(to: offset, whence: whence)
}
