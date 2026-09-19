import SwiftUI

/// Swap the index to stream a different file; the list lives in SMBTestConfig.swift.
private let smbTestFile = SMBTestConfig.files[1]

/// Opens an SMB connection, streams a file through mpv's custom stream protocol, and closes the
/// connection on the way out.
struct SMBPlayerTestView: View {
    private enum Phase {
        case connecting(String)
        case playing
        case failed(String)
    }

    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .connecting("starting")
    @State private var session: SMBSession?
    @State private var coordinator: MPVPlayerView.Coordinator?
    @State private var shares: [String] = []

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch phase {
            case .connecting(let step):
                statusPanel {
                    ProgressView()
                    Text(step).font(.headline)
                }

            case .playing:
                if let coordinator {
                    MPVPlayerView(coordinator: coordinator)
                        .ignoresSafeArea()
                    PlayerControlsOverlay(coordinator: coordinator, onClose: close)
                }

            case .failed(let message):
                statusPanel {
                    Text("SMB failed").font(.title3)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                    if !shares.isEmpty {
                        Text("shares seen: \(shares.joined(separator: ", "))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Button("Close", action: close)
                }
            }
        }
        .task { await start() }
        .onPlayPauseCommand { coordinator?.togglePause() }
        .onExitCommand(perform: close)
    }

    @ViewBuilder
    private func statusPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 16) {
            content()
            Text("\(SMBTestConfig.host)/\(SMBTestConfig.share) · \(smbTestFile.title)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(40)
    }

    private func start() async {
        var step = "starting"
        do {
            step = "connecting to \(SMBTestConfig.host)"
            phase = .connecting(step)
            let session = try SMBSession()
            self.session = session
            try await session.connect()
            shares = session.discoveredShares

            step = "opening \(smbTestFile.title)"
            phase = .connecting(step)
            let token = try await session.prepare(path: smbTestFile.path)

            let coordinator = MPVPlayerView.Coordinator(
                playUrl: SMBStreamProtocol.url(forToken: token)
            )
            coordinator.smbSession = session
            self.coordinator = coordinator
            phase = .playing
        } catch {
            print("[SMB] failed while \(step): \(error)")
            phase = .failed("while \(step):\n\(error)")
        }
    }

    private func close() {
        // Order matters: mpv must be fully destroyed before the SMB session goes away, or in-flight
        // stream callbacks touch a dead session. shutdown() returns once every stream is closed.
        coordinator?.player?.shutdown()
        coordinator = nil

        let session = self.session
        self.session = nil
        Task.detached { await session?.disconnect() }

        dismiss()
    }
}
