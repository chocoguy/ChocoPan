import AVFoundation
import Libmpv
import UIKit

/// Hosts a `MetalLayer` and drives it with an embedded mpv instance.
///
/// mpv renders straight into the layer via `--wid`, so there is no per-frame work on our side.
/// Events arrive on mpv's own thread through `mpv_set_wakeup_callback`, get drained on `queue`,
/// and are forwarded to `playDelegate` on the main actor.
final class MPVMetalViewController: UIViewController {
    nonisolated(unsafe) private var mpv: OpaquePointer?
    nonisolated private let queue = DispatchQueue(label: "com.vanillacoffeesoft.ChocoPan.mpv", qos: .userInitiated)

    private let metalLayer = MetalLayer()

    weak var playDelegate: MPVPlayerDelegate?
    var playUrl: URL?
    /// Set before the view loads to serve playback over the custom SMB protocol.
    var smbSession: SMBSession?

    /// Retained reference handed to mpv's protocol registration; released only after teardown.
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
            loadFile(playUrl)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Layer geometry is not view geometry: without this the resize animates and mpv sees
        // intermediate drawable sizes.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        metalLayer.frame = view.bounds
        // Resolved here rather than in viewDidLoad: the screen is only reachable once we have a window.
        metalLayer.contentsScale = view.window?.windowScene?.screen.nativeScale
            ?? view.traitCollection.displayScale
        CATransaction.commit()
    }

    deinit {
        shutdown()
    }

    /// Tears mpv down and releases the SMB registration.
    ///
    /// Callers streaming over SMB must call this *before* disconnecting the session: mpv guarantees
    /// every stream is closed once `mpv_terminate_destroy` returns, and in-flight stream callbacks
    /// would otherwise touch a dead session. Safe to call more than once.
    nonisolated func shutdown() {
        guard let handle = mpv else { return }
        // Cleared first so the event loop stops entering with a handle that is going away.
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

        // Options must be set between mpv_create() and mpv_initialize().
        // https://mpv.io/manual/stable/#options
#if DEBUG
        checkError(mpv_request_log_messages(handle, "debug"))
#else
        checkError(mpv_request_log_messages(handle, "no"))
#endif

        // Hand mpv the Metal layer to render into.
        var wid = Int64(Int(bitPattern: Unmanaged.passUnretained(metalLayer).toOpaque()))
        checkError(mpv_set_option(handle, "wid", MPV_FORMAT_INT64, &wid))

        checkError(mpv_set_option_string(handle, "subs-match-os-language", "yes"))
        checkError(mpv_set_option_string(handle, "subs-fallback", "yes"))
        checkError(mpv_set_option_string(handle, "vo", "gpu-next"))
        checkError(mpv_set_option_string(handle, "gpu-api", "vulkan"))
        checkError(mpv_set_option_string(handle, "gpu-context", "moltenvk"))
        checkError(mpv_set_option_string(handle, "video-rotate", "no"))

        // VideoToolbox is not dependable in the simulator; software decode is fine there.
#if targetEnvironment(simulator)
        checkError(mpv_set_option_string(handle, "hwdec", "no"))
#else
        checkError(mpv_set_option_string(handle, "hwdec", "videotoolbox"))
#endif

        // Matters only for network sources, harmless for local files.
        checkError(mpv_set_option_string(handle, "cache", "yes"))
        checkError(mpv_set_option_string(handle, "demuxer-max-bytes", "64MiB"))
        checkError(mpv_set_option_string(handle, "demuxer-readahead-secs", "20"))

        // Must happen before initialize: protocols cannot be added to a running core.
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

        // Must stay non-capturing: this is a C function pointer.
        mpv_set_wakeup_callback(handle, { ctx in
            guard let ctx else { return }
            Unmanaged<MPVMetalViewController>.fromOpaque(ctx).takeUnretainedValue().readEvents()
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    // MARK: - Playback control

    func loadFile(_ url: URL) {
        // A plain POSIX path avoids percent-encoding entirely. It is passed as a single argv
        // element, so spaces and brackets need no escaping.
        let target = url.isFileURL ? url.path : url.absoluteString
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

    // MARK: - Tracks

    /// Reads `track-list` and hands it to the delegate.
    ///
    /// Selection state lives in the list's own `selected` flags, so re-reading after a change is both
    /// simpler and more reliable than separately observing `aid`/`sid`.
    func refreshTracks() {
        guard let json = getString("track-list"),
              let data = json.data(using: .utf8),
              let tracks = try? JSONDecoder().decode([MPVTrack].self, from: data) else {
            print("[tracks] could not read track-list")
            return
        }
        playDelegate?.playerDidChange(.tracks(tracks))
    }

    /// `nil` disables the track ("no" to mpv).
    func selectTrack(id: Int?, kind: MPVTrackKind) {
        setString(kind.property, id.map(String.init) ?? "no")
        refreshTracks()
    }

    /// Swaps the active Anime4K chain. Takes effect on the next rendered frame, so it can be used to
    /// A/B the same paused image.
    func apply(preset: Anime4KPreset) {
        let (paths, missing) = preset.resolve()
        if !missing.isEmpty {
            print("[Anime4K] \(preset.name): could not resolve \(missing)")
        }

        // One append per path rather than a single joined string: glsl-shaders is a colon-separated
        // list and these paths come from the simulator, so joining invites an escaping bug.
        command("change-list", args: ["glsl-shaders", "clr", ""])
        for path in paths {
            command("change-list", args: ["glsl-shaders", "append", path])
        }
        print("[Anime4K] \(preset.name): \(paths.count) shader(s) active")
    }

    // MARK: - Property access

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

    private func setFlag(_ name: String, _ flag: Bool) {
        guard let mpv else { return }
        var data: Int32 = flag ? 1 : 0
        mpv_set_property(mpv, name, MPV_FORMAT_FLAG, &data)
    }

    /// mpv takes a NULL-terminated argv; the terminator is appended here, callers pass plain strings.
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

    // MARK: - Event loop

    /// Called from mpv's thread; hops onto `queue` to drain the event queue.
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

            // MPV_FORMAT_FLAG is a C int, MPV_FORMAT_DOUBLE a double.
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
            default:
                break
            }

        case MPV_EVENT_FILE_LOADED:
            emit(.fileLoaded)

        case MPV_EVENT_END_FILE:
            emit(.endFile)

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
