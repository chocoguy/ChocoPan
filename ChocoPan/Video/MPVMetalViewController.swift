import AVFoundation
import AVKit
import CoreMedia
import Libmpv
import UIKit

final class MPVMetalViewController: UIViewController {
    nonisolated(unsafe) private var mpv: OpaquePointer?
    nonisolated private let queue = DispatchQueue(label: "com.vanillacoffeesoft.ChocoPan.mpv", qos: .userInitiated)

    private let metalLayer = MetalLayer()

    weak var playDelegate: MPVPlayerDelegate?
    var playUrl: URL?
    var smbSession: SMBSession?
    var configuration: PlayerConfiguration = .standard
    var startAtSeconds: Double = 0

    nonisolated(unsafe) private var smbUserData: UnsafeMutableRawPointer?

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black
        metalLayer.frame = view.bounds
        metalLayer.framebufferOnly = true
        metalLayer.backgroundColor = UIColor.black.cgColor
        view.layer.addSublayer(metalLayer)

        activateAudioSession()
        setupMpv()

        if let playUrl {
            loadFile(playUrl, startAt: startAtSeconds)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        metalLayer.frame = view.bounds
        metalLayer.contentsScale = view.window?.windowScene?.screen.nativeScale
            ?? view.traitCollection.displayScale
        CATransaction.commit()
    }

    deinit {
        shutdown()
    }

    nonisolated func shutdown() {
        guard let handle = mpv else { return }
        mpv = nil
        mpv_set_wakeup_callback(handle, nil, nil)
        mpv_terminate_destroy(handle)

        if let smbUserData {
            Unmanaged<SMBSession>.fromOpaque(smbUserData).release()
            self.smbUserData = nil
        }
    }

    private func activateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[ChocoPan] audio session setup failed: \(error)")
        }
    }

    private func setupMpv() {
        guard let handle = mpv_create() else {
            fatalError("failed creating mpv context")
        }
        mpv = handle


        // https://mpv.io/manual/stable/#options
        checkError(mpv_request_log_messages(handle, configuration.logLevel))

        var wid = Int64(Int(bitPattern: Unmanaged.passUnretained(metalLayer).toOpaque()))
        checkError(mpv_set_option(handle, "wid", MPV_FORMAT_INT64, &wid))

        checkError(mpv_set_option_string(handle, "subs-match-os-language", "yes"))
        checkError(mpv_set_option_string(handle, "subs-fallback", "yes"))
        checkError(mpv_set_option_string(handle, "vo", "gpu-next"))
        checkError(mpv_set_option_string(handle, "gpu-api", "vulkan"))
        checkError(mpv_set_option_string(handle, "gpu-context", "moltenvk"))
        checkError(mpv_set_option_string(handle, "video-rotate", "no"))

#if targetEnvironment(simulator)
        checkError(mpv_set_option_string(handle, "hwdec", "no"))
#else
        checkError(mpv_set_option_string(handle, "hwdec", configuration.hardwareDecoding ? "videotoolbox" : "no"))
#endif

        checkError(mpv_set_option_string(handle, MPVProperty.speed, String(configuration.playbackSpeed)))

        checkError(mpv_set_option_string(handle, "cache", "yes"))
        checkError(mpv_set_option_string(handle, "demuxer-max-bytes", "64MiB"))
        checkError(mpv_set_option_string(handle, "demuxer-readahead-secs", "20"))

        for option in configuration.extraOptions {
            checkError(mpv_set_option_string(handle, option.name, option.value))
        }

        if let smbSession {
            smbUserData = SMBStreamProtocol.register(on: handle, session: smbSession)
        }

        checkError(mpv_initialize(handle))

        mpv_observe_property(handle, 0, MPVProperty.pause, MPV_FORMAT_FLAG)
        mpv_observe_property(handle, 0, MPVProperty.pausedForCache, MPV_FORMAT_FLAG)
        mpv_observe_property(handle, 0, MPVProperty.timePos, MPV_FORMAT_DOUBLE)
        mpv_observe_property(handle, 0, MPVProperty.duration, MPV_FORMAT_DOUBLE)
        mpv_observe_property(handle, 0, MPVProperty.estimatedVfFps, MPV_FORMAT_DOUBLE)
        mpv_observe_property(handle, 0, MPVProperty.frameDropCount, MPV_FORMAT_INT64)
        mpv_observe_property(handle, 0, MPVProperty.avsync, MPV_FORMAT_DOUBLE)
        mpv_observe_property(handle, 0, MPVProperty.videoHeight, MPV_FORMAT_INT64)
        mpv_observe_property(handle, 0, MPVProperty.demuxerCacheTime, MPV_FORMAT_DOUBLE)

        mpv_set_wakeup_callback(handle, { ctx in
            guard let ctx else { return }
            Unmanaged<MPVMetalViewController>.fromOpaque(ctx).takeUnretainedValue().readEvents()
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    func loadFile(_ url: URL, startAt seconds: Double = 0) {
        let target = url.isFileURL ? url.path : url.absoluteString

        setString(MPVProperty.start, seconds > 0 ? String(seconds) : "0")
        command("loadfile", args: [target, "replace"])
    }

    func play() {
        setFlag(MPVProperty.pause, false)
    }

    func pause() {
        setFlag(MPVProperty.pause, true)
    }

    func togglePause() {
        getFlag(MPVProperty.pause) ? play() : pause()
    }

    func seek(_ seconds: Double) {
        command("seek", args: [String(seconds), "relative"])
    }

    func seek(to seconds: Double) {
        command("seek", args: [String(max(0, seconds)), "absolute"])
    }

    func setSpeed(_ speed: Double) {
        setDouble(MPVProperty.speed, speed)
    }


    func applyDisplayCriteria() {
        guard configuration.matchesContentFrameRate,
              let manager = displayManager,
              manager.isDisplayCriteriaMatchingEnabled,
              !manager.isDisplayModeSwitchInProgress,
              let fps = getString("container-fps").flatMap(Double.init), fps > 0,
              let format = videoFormatDescription() else {
            return
        }
        manager.preferredDisplayCriteria = AVDisplayCriteria(
            refreshRate: Float(fps),
            formatDescription: format
        )
    }

    func resetDisplayCriteria() {
        displayManager?.preferredDisplayCriteria = nil
    }

    private var displayManager: AVDisplayManager? {
        guard let window = view.window,
              window.responds(to: NSSelectorFromString("avDisplayManager")) else {
            return nil
        }
        return window.avDisplayManager
    }

    private func videoFormatDescription() -> CMFormatDescription? {
        guard let width = getString("video-params/w").flatMap(Int32.init),
              let height = getString("video-params/h").flatMap(Int32.init),
              width > 0, height > 0 else {
            return nil
        }

        let gamma = getString("video-params/gamma")
        let isHDR = gamma == "pq" || gamma == "hlg"
        let transfer: CFString = switch gamma {
        case "pq": kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ
        case "hlg": kCVImageBufferTransferFunction_ITU_R_2100_HLG
        default: kCVImageBufferTransferFunction_ITU_R_709_2
        }

        let extensions: [CFString: Any] = [
            kCVImageBufferColorPrimariesKey: isHDR
                ? kCVImageBufferColorPrimaries_ITU_R_2020
                : kCVImageBufferColorPrimaries_ITU_R_709_2,
            kCVImageBufferTransferFunctionKey: transfer,
            kCVImageBufferYCbCrMatrixKey: isHDR
                ? kCVImageBufferYCbCrMatrix_ITU_R_2020
                : kCVImageBufferYCbCrMatrix_ITU_R_709_2,
        ]

        var description: CMFormatDescription?
        let status = CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: isHDR ? kCMVideoCodecType_HEVC : kCMVideoCodecType_H264,
            width: width,
            height: height,
            extensions: extensions as CFDictionary,
            formatDescriptionOut: &description
        )
        guard status == noErr else {
            print("[player] could not describe the video format: \(status)")
            return nil
        }
        return description
    }

    func refreshTracks() {
        guard let json = getString(MPVProperty.trackList),
              let data = json.data(using: .utf8),
              let tracks = try? JSONDecoder().decode([MPVTrack].self, from: data) else {
            print("[tracks] could not read track-list")
            return
        }
        playDelegate?.playerDidChange(.tracks(tracks))
    }

    func selectTrack(id: Int?, kind: MPVTrackKind) {
        setString(kind.property, id.map(String.init) ?? "no")
        refreshTracks()
    }

    func apply(preset: Anime4KPreset) {
        let (paths, missing) = preset.resolve()
        if !missing.isEmpty {
            print("[Anime4K] \(preset.name): could not resolve \(missing)")
        }

        command("change-list", args: ["glsl-shaders", "clr", ""])
        for path in paths {
            command("change-list", args: ["glsl-shaders", "append", path])
        }
        print("[Anime4K] \(preset.name): \(paths.count) shader(s) active")
    }


    private func getString(_ name: String) -> String? {
        guard let mpv, let value = mpv_get_property_string(mpv, name) else { return nil }
        defer { mpv_free(value) }
        return String(cString: value)
    }

    private func setString(_ name: String, _ value: String) {
        guard let mpv else { return }
        checkError(mpv_set_property_string(mpv, name, value))
    }

    private func getFlag(_ name: String) -> Bool {
        guard let mpv else { return false }
        var data = Int32()
        mpv_get_property(mpv, name, MPV_FORMAT_FLAG, &data)
        return data != 0
    }

    private func setDouble(_ name: String, _ value: Double) {
        guard let mpv else { return }
        var data = value
        checkError(mpv_set_property(mpv, name, MPV_FORMAT_DOUBLE, &data))
    }

    private func setFlag(_ name: String, _ flag: Bool) {
        guard let mpv else { return }
        var data: Int32 = flag ? 1 : 0
        mpv_set_property(mpv, name, MPV_FORMAT_FLAG, &data)
    }

    private func command(_ command: String, args: [String] = []) {
        guard let mpv else { return }

        var cargs: [UnsafePointer<CChar>?] = ([command] + args).map { UnsafePointer(strdup($0)) }
        cargs.append(nil)
        defer {
            for ptr in cargs where ptr != nil {
                free(UnsafeMutablePointer(mutating: ptr!))
            }
        }
        checkError(mpv_command(mpv, &cargs))
    }

    nonisolated private func readEvents() {
        queue.async { [weak self] in
            guard let self else { return }
            while let mpv = self.mpv {
                guard let event = mpv_wait_event(mpv, 0),
                      event.pointee.event_id != MPV_EVENT_NONE else { break }
                self.handle(event: event)
            }
        }
    }

    nonisolated private func handle(event: UnsafePointer<mpv_event>) {
        switch event.pointee.event_id {
        case MPV_EVENT_PROPERTY_CHANGE:
            guard let raw = event.pointee.data else { return }
            let property = raw.assumingMemoryBound(to: mpv_event_property.self).pointee
            guard let value = property.data else { return }

            switch String(cString: property.name) {
            case MPVProperty.pause:
                emit(.pause(value.assumingMemoryBound(to: Int32.self).pointee != 0))
            case MPVProperty.pausedForCache:
                emit(.buffering(value.assumingMemoryBound(to: Int32.self).pointee != 0))
            case MPVProperty.timePos:
                emit(.timePos(value.assumingMemoryBound(to: Double.self).pointee))
            case MPVProperty.duration:
                emit(.duration(value.assumingMemoryBound(to: Double.self).pointee))
            case MPVProperty.estimatedVfFps:
                emit(.fps(value.assumingMemoryBound(to: Double.self).pointee))
            case MPVProperty.frameDropCount:
                emit(.droppedFrames(value.assumingMemoryBound(to: Int64.self).pointee))
            case MPVProperty.avsync:
                emit(.avsync(value.assumingMemoryBound(to: Double.self).pointee))
            case MPVProperty.videoHeight:
                emit(.videoHeight(Int(value.assumingMemoryBound(to: Int64.self).pointee)))
            case MPVProperty.demuxerCacheTime:
                emit(.cacheSeconds(value.assumingMemoryBound(to: Double.self).pointee))
            default:
                break
            }

        case MPV_EVENT_FILE_LOADED:
            emit(.fileLoaded)

        case MPV_EVENT_END_FILE:
            guard let raw = event.pointee.data else {
                emit(.endFile(.unknown))
                return
            }
            let end = raw.assumingMemoryBound(to: mpv_event_end_file.self).pointee
            emit(.endFile(MPVEndReason(end)))

        case MPV_EVENT_LOG_MESSAGE:
            guard let raw = event.pointee.data else { return }
            let message = raw.assumingMemoryBound(to: mpv_event_log_message.self).pointee
            print("[mpv/\(String(cString: message.prefix))] \(String(cString: message.level)): "
                  + "\(String(cString: message.text))", terminator: "")

        case MPV_EVENT_SHUTDOWN:
            print("[mpv] shutdown")
            if let mpv {
                mpv_terminate_destroy(mpv)
                self.mpv = nil
            }

        default:
            if let name = mpv_event_name(event.pointee.event_id) {
                print("[mpv] event: \(String(cString: name))")
            }
        }
    }

    nonisolated private func emit(_ event: MPVPlayerEvent) {
        Task { @MainActor [weak self] in
            self?.playDelegate?.playerDidChange(event)
        }
    }

    nonisolated private func checkError(_ status: CInt) {
        if status < 0 {
            print("[mpv] API error: \(String(cString: mpv_error_string(status)))")
        }
    }
}
