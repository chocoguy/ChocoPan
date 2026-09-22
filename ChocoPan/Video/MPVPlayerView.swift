import Combine
import SwiftUI

enum MPVPlayerEvent: Sendable {
    case pause(Bool)
    case buffering(Bool)
    case timePos(Double)
    case duration(Double)
    case fileLoaded
    case endFile(MPVEndReason)
    case fps(Double)
    case droppedFrames(Int64)
    case avsync(Double)
    case tracks([MPVTrack])
    case videoHeight(Int)
    case cacheSeconds(Double)
}

enum MPVTrackKind: Sendable {
    case audio
    case subtitle

    var property: String {
        switch self {
        case .audio: "aid"
        case .subtitle: "sid"
        }
    }

    var listType: String {
        switch self {
        case .audio: "audio"
        case .subtitle: "sub"
        }
    }
}

@MainActor
protocol MPVPlayerDelegate: AnyObject {
    func playerDidChange(_ event: MPVPlayerEvent)
}

struct MPVPlayerView: UIViewControllerRepresentable {
    @ObservedObject var coordinator: Coordinator

    func makeUIViewController(context: Context) -> MPVMetalViewController {
        let controller = MPVMetalViewController()
        controller.playDelegate = coordinator
        controller.playUrl = coordinator.playUrl
        controller.smbSession = coordinator.smbSession
        controller.configuration = coordinator.configuration
        controller.startAtSeconds = coordinator.startAtSeconds
        coordinator.player = controller
        return controller
    }

    func updateUIViewController(_ controller: MPVMetalViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { coordinator }

    @MainActor
    final class Coordinator: MPVPlayerDelegate, ObservableObject {
        weak var player: MPVMetalViewController?
        private(set) var playUrl: URL
        var smbSession: SMBSession?
        var configuration: PlayerConfiguration = .standard
        var startAtSeconds: Double = 0
        var onFileLoaded: (() -> Void)?
        var onEndFile: ((MPVEndReason) -> Void)?
        var onVideoHeight: ((Int) -> Void)?

        @Published private(set) var timePos: Double = 0
        @Published private(set) var duration: Double = 0
        @Published private(set) var isPaused = false
        @Published private(set) var isBuffering = false
        @Published private(set) var isLoaded = false
        @Published private(set) var fps: Double = 0
        @Published private(set) var droppedFrames: Int64 = 0
        @Published private(set) var avsync: Double = 0
        @Published private(set) var preset: Anime4KPreset = .off
        @Published private(set) var audioTracks: [MPVTrack] = []
        @Published private(set) var subtitleTracks: [MPVTrack] = []
        @Published private(set) var videoHeight = 0
        @Published private(set) var cacheSeconds: Double = 0

        init(playUrl: URL) {
            self.playUrl = playUrl
        }

        func playerDidChange(_ event: MPVPlayerEvent) {
            switch event {
            case .pause(let value): isPaused = value
            case .buffering(let value): isBuffering = value
            case .timePos(let value): timePos = value
            case .duration(let value): duration = value
            case .fileLoaded:
                isLoaded = true
                player?.refreshTracks()
                onFileLoaded?()
            case .tracks(let all):
                audioTracks = all.filter { $0.type == MPVTrackKind.audio.listType }
                subtitleTracks = all.filter { $0.type == MPVTrackKind.subtitle.listType }
            case .endFile(let reason): onEndFile?(reason)
            case .fps(let value): fps = value
            case .droppedFrames(let value): droppedFrames = value
            case .avsync(let value): avsync = value
            case .videoHeight(let value):
                let isNew = value > 0 && value != videoHeight
                videoHeight = value
                if isNew { onVideoHeight?(value) }
            case .cacheSeconds(let value): cacheSeconds = value
            }
        }

        func load(url: URL, startAt seconds: Double = 0) {
            playUrl = url
            resetPerFileState()
            player?.loadFile(url, startAt: seconds)
        }

        private func resetPerFileState() {
            isLoaded = false
            timePos = 0
            duration = 0
            videoHeight = 0
            audioTracks = []
            subtitleTracks = []
        }

        func play() { player?.play() }

        func pause() { player?.pause() }

        func togglePause() {
            player?.togglePause()
        }

        func seek(_ seconds: Double) {
            player?.seek(seconds)
        }

        func seek(to seconds: Double) {
            player?.seek(to: min(max(0, seconds), duration > 0 ? duration : seconds))
        }

        func setSpeed(_ speed: Double) {
            player?.setSpeed(speed)
        }

        func select(_ track: MPVTrack?, kind: MPVTrackKind) {
            player?.selectTrack(id: track?.id, kind: kind)
        }

        func selectedTrack(kind: MPVTrackKind) -> MPVTrack? {
            tracks(kind: kind).first(where: \.isSelected)
        }

        func tracks(kind: MPVTrackKind) -> [MPVTrack] {
            switch kind {
            case .audio: audioTracks
            case .subtitle: subtitleTracks
            }
        }

        func apply(preset: Anime4KPreset) {
            self.preset = preset
            player?.apply(preset: preset)
        }

        var audioLabel: String {
            audioTracks.first(where: \.isSelected)?.label ?? (audioTracks.isEmpty ? "none" : "off")
        }

        var subtitleLabel: String {
            subtitleTracks.first(where: \.isSelected)?.label ?? "off"
        }

        func cycleAudioTrack() {
            guard !audioTracks.isEmpty else { return }
            let current = audioTracks.firstIndex(where: \.isSelected) ?? -1
            let next = audioTracks[(current + 1) % audioTracks.count]
            player?.selectTrack(id: next.id, kind: .audio)
        }

        func cycleSubtitleTrack() {
            guard !subtitleTracks.isEmpty else { return }
            let ids: [Int?] = subtitleTracks.map(\.id) + [nil]
            let currentID = subtitleTracks.first(where: \.isSelected)?.id
            let index = ids.firstIndex(where: { $0 == currentID }) ?? ids.count - 1
            player?.selectTrack(id: ids[(index + 1) % ids.count], kind: .subtitle)
        }

        func cycleShaderPreset() {
            let presets = Anime4KPreset.all
            let index = presets.firstIndex(of: preset) ?? 0
            apply(preset: presets[(index + 1) % presets.count])
        }
    }
}
