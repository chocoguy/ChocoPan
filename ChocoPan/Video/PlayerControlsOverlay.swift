import SwiftUI

/// Transport, track and shader controls shared by the local-file and SMB test players.
///
/// On-screen buttons rather than remote-only gestures, so everything can be driven without a
/// Siri Remote.
struct PlayerControlsOverlay: View {
    @ObservedObject var coordinator: MPVPlayerView.Coordinator
    var onClose: () -> Void

    var body: some View {
        VStack {
            Spacer()

            VStack(spacing: 4) {
                Text(status)
                    .font(.headline)
                Text(renderStats)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(12)
            .background(.black.opacity(0.65), in: .rect(cornerRadius: 8))

            HStack(spacing: 20) {
                Button("-10s") { coordinator.seek(-10) }
                Button(coordinator.isPaused ? "Play" : "Pause") { coordinator.togglePause() }
                Button("+90s") { coordinator.seek(90) }
                Button("Close", action: onClose)
            }

            HStack(spacing: 20) {
                Button("Audio: \(coordinator.audioLabel)") { coordinator.cycleAudioTrack() }
                    .disabled(coordinator.audioTracks.isEmpty)
                Button("Subs: \(coordinator.subtitleLabel)") { coordinator.cycleSubtitleTrack() }
                    .disabled(coordinator.subtitleTracks.isEmpty)
                Button("Anime4K: \(coordinator.preset.name)") { coordinator.cycleShaderPreset() }
            }
            .padding(.bottom, 40)
        }
    }

    private var status: String {
        let state = if coordinator.isBuffering {
            "buffering"
        } else if coordinator.isPaused {
            "paused"
        } else {
            "playing"
        }
        return "\(timecode(coordinator.timePos)) / \(timecode(coordinator.duration))  •  \(state)"
    }

    /// The point of the shader work: cost has to be visible to be judged.
    private var renderStats: String {
        let fps = coordinator.fps > 0 ? String(format: "%.1f fps", coordinator.fps) : "-- fps"
        return "\(fps) · \(coordinator.droppedFrames) dropped · "
            + String(format: "avsync %+.3f", coordinator.avsync)
            + " · \(coordinator.audioTracks.count)a/\(coordinator.subtitleTracks.count)s"
    }

    private func timecode(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--:--" }
        let total = Int(seconds)
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}
