import Combine
import SwiftUI

/// What the player reports back. `Sendable` because these cross from mpv's thread to the main actor.
enum MPVPlayerEvent: Sendable {
    case pause(Bool)
    case buffering(Bool)
    case timePos(Double)
    case duration(Double)
    case fileLoaded
    case endFile
    case fps(Double)
    case droppedFrames(Int64)
    case avsync(Double)
    case tracks([MPVTrack])
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

    /// mpv's `track-list` type string.
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
        coordinator.player = controller
        return controller
    }

    func updateUIViewController(_ controller: MPVMetalViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { coordinator }

    /// Owns the player's observable state and relays control calls to the view controller.
    @MainActor
    final class Coordinator: MPVPlayerDelegate, ObservableObject {
        weak var player: MPVMetalViewController?
        let playUrl: URL
        /// Set before the view is made; forwarded to the controller for SMB-backed playback.
        var smbSession: SMBSession?

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
                // Tracks only exist once the file is open.
                player?.refreshTracks()
            case .tracks(let all):
                audioTracks = all.filter { $0.type == MPVTrackKind.audio.listType }
                subtitleTracks = all.filter { $0.type == MPVTrackKind.subtitle.listType }
            case .endFile: break
            case .fps(let value): fps = value
            case .droppedFrames(let value): droppedFrames = value
            case .avsync(let value): avsync = value
            }
        }

        func togglePause() {
            player?.togglePause()
        }

        func seek(_ seconds: Double) {
            player?.seek(seconds)
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
            // Subtitles cycle through "off" as well; audio deliberately does not.
            let ids: [Int?] = subtitleTracks.map(\.id) + [nil]
            let currentID = subtitleTracks.first(where: \.isSelected)?.id
            let index = ids.firstIndex(where: { $0 == currentID }) ?? ids.count - 1
            player?.selectTrack(id: ids[(index + 1) % ids.count], kind: .subtitle)
        }

        func cycleShaderPreset() {
            let presets = Anime4KPreset.all
            let index = presets.firstIndex(of: preset) ?? 0
            let next = presets[(index + 1) % presets.count]
            preset = next
            player?.apply(preset: next)
        }
    }
}
