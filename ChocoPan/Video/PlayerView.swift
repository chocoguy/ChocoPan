import SwiftData
import SwiftUI

struct PlayerView: View {
    let episode: AnimeEpisode

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var session: PlaybackSession?
    @State private var openSection: PlayerOptionsMenu.Section?
    @State private var attempt = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let session {
                content(for: session)
            } else {
                ProgressView()
            }
        }
        .task(id: attempt) {
            let settings = ChocoPanSettings.shared(in: context)
            let created = PlaybackSession(episode: episode, settings: settings, context: context)
            session = created
            await created.start()
        }
        .onDisappear { session?.stop() }
    }

    @ViewBuilder
    private func content(for session: PlaybackSession) -> some View {
        switch session.phase {
        case .connecting(let step):
            statusPanel {
                ProgressView()
                Text(step)
                    .font(.title3)
                    .multilineTextAlignment(.center)
            }
            .onExitCommand(perform: close)

        case .failed(let message):
            statusPanel {
                Text("Could not play this episode")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 900)

                HStack(spacing: 20) {
                    Button("Try Again", action: retry)
                    Button("Close", action: close)
                }
                .padding(.top, 12)
            }
            .onExitCommand(perform: close)

        case .playing, .finished:
            playback(for: session)
        }
    }

    @ViewBuilder
    private func playback(for session: PlaybackSession) -> some View {
        if let coordinator = session.coordinator {
            ZStack {
                MPVPlayerView(coordinator: coordinator)
                    .ignoresSafeArea()

                if coordinator.isBuffering {
                    ProgressView()
                        .controlSize(.large)
                        .padding(30)
                        .background(.black.opacity(0.5), in: .circle)
                }

                PlayerOverlay(
                    coordinator: coordinator,
                    session: session,
                    openSection: $openSection,
                    onClose: close
                )

                if let section = openSection {
                    PlayerOptionsMenu(
                        coordinator: coordinator,
                        session: session,
                        section: section
                    ) {
                        openSection = nil
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 80)
                    .padding(.bottom, 250)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }

                if let next = session.upNext {
                    autoPlayCard(next: next, session: session)
                }
            }
            .animation(.easeOut(duration: 0.2), value: openSection)
            .onChange(of: session.phase) { _, phase in
                if phase == .finished { close() }
            }
        }
    }


    private func autoPlayCard(next: AnimeEpisode, session: PlaybackSession) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Up Next")
                .font(.callout)
                .foregroundStyle(.secondary)

            Text(next.displayLabel)
                .font(.title2)
                .fontWeight(.semibold)

            HStack(spacing: 20) {
                Button(playNowTitle(session)) { session.playNow() }
                Button("Stop", role: .cancel) { session.cancelAutoPlay() }
            }
            .padding(.top, 8)
        }
        .padding(36)
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 20))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(.trailing, 60)
        .padding(.bottom, 200)
        .focusSection()
    }

    private func playNowTitle(_ session: PlaybackSession) -> String {
        guard let seconds = session.secondsUntilNext else { return "Play Now" }
        return "Play Now (\(seconds))"
    }


    @ViewBuilder
    private func statusPanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 16) {
            content()

            Text(episode.fileName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 900)
        }
        .padding(40)
    }


    private func close() {
        session?.stop()
        dismiss()
    }

    private func retry() {
        session?.stop()
        session = nil
        openSection = nil
        attempt += 1
    }
}
