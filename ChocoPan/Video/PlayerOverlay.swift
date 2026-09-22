import SwiftUI

struct PlayerOverlay: View {
    @ObservedObject var coordinator: MPVPlayerView.Coordinator
    let session: PlaybackSession
    @Binding var openSection: PlayerOptionsMenu.Section?
    var onClose: () -> Void

    private enum Focus: Hashable {
        case progress
        case option(PlayerOptionsMenu.Section)
        case skip
    }

    @FocusState private var focus: Focus?
    @State private var isVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var scrubTarget: Double?
    @State private var scrubTask: Task<Void, Never>?
    @State private var lastMove = Date.distantPast

    private static let idleTimeout: Duration = .seconds(8)
    private static let titleSafeBottom: CGFloat = 60
    private static let titleSafeHorizontal: CGFloat = 80

    var body: some View {
        chrome
            .opacity(isVisible ? 1 : 0)
            .onPlayPauseCommand {
                bumpActivity()
                session.togglePause()
            }
            .onChange(of: coordinator.isPaused) { _, _ in bumpActivity() }
            .onChange(of: openSection) { previous, section in
                guard section == nil, let previous else { return }
                bumpActivity()
                focus = .option(previous)
            }
            .onAppear { bumpActivity() }
            .onDisappear {
                hideTask?.cancel()
                scrubTask?.cancel()
            }
            .animation(.easeInOut(duration: 0.22), value: isVisible)
            .focusEffectDisabled()
    }


    private var chrome: some View {
        VStack(spacing: 0) {
            if session.settings.showStatsOverlay {
                Text(renderStats)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(14)
                    .background(.black.opacity(0.5), in: .rect(cornerRadius: 8))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 40)
            }

            Spacer(minLength: 0)

            HStack(alignment: .bottom, spacing: 40) {
                titleBlock
                Spacer(minLength: 20)
                buttonRow
            }

            progressBar
                .padding(.top, 26)
        }
        .padding(.horizontal, Self.titleSafeHorizontal)
        .padding(.bottom, Self.titleSafeBottom)
        .background(alignment: .bottom) {
            LinearGradient(
                colors: [.clear, .black.opacity(0.8)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 520)
            .allowsHitTesting(false)
        }
        .ignoresSafeArea(edges: [.horizontal, .bottom])
        .defaultFocus($focus, .progress)
        .onExitCommand(perform: onClose)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !session.seasonLine.isEmpty {
                Text(session.seasonLine)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.75))
            }

            Text(session.episodeLine)
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    private var buttonRow: some View {
        HStack(spacing: 34) {
            if let skip = skipAction {
                Button {
                    guard acceptsInput() else { return }
                    session.seek(skip.seconds)
                } label: {
                    PillLabel(title: skip.title)
                }
                .buttonStyle(.playerControl)
                .focused($focus, equals: .skip)
            }

            ForEach(PlayerOptionsMenu.Section.allCases) { section in
                Button {
                    guard acceptsInput() else { return }
                    session.persistProgress()
                    openSection = section
                } label: {
                    IconLabel(systemImage: section.systemImage)
                }
                .buttonStyle(.playerControl)
                .accessibilityLabel(section.title)
                .focused($focus, equals: .option(section))
            }
        }
    }

    private var progressBar: some View {
        Button {
            guard acceptsInput() else { return }
            session.togglePause()
        } label: {
            PlayerProgressBar(
                position: coordinator.timePos,
                duration: coordinator.duration,
                isFocused: focus == .progress,
                pending: scrubTarget
            )
        }
        .buttonStyle(.playerControl)
        .focused($focus, equals: .progress)
        .onMoveCommand(perform: move)
    }


    private func move(_ direction: MoveCommandDirection) {
        guard direction == .left || direction == .right else { return }
        guard acceptsInput() else { return }

        let now = Date()
        let step = now.timeIntervalSince(lastMove) < 0.4
            ? session.settings.seekLargeSeconds
            : session.settings.seekSmallSeconds
        lastMove = now

        let base = scrubTarget ?? coordinator.timePos
        let limit = coordinator.duration > 0 ? coordinator.duration : base + step
        scrubTarget = min(max(0, base + (direction == .left ? -step : step)), limit)

        scrubTask?.cancel()
        scrubTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let target = scrubTarget else { return }
            session.seek(to: target)
            scrubTarget = nil
        }
    }


    private func bumpActivity() {
        isVisible = true
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: Self.idleTimeout)
            guard !Task.isCancelled, canHide else { return }
            isVisible = false
        }
    }

    private func acceptsInput() -> Bool {
        let wasVisible = isVisible
        bumpActivity()
        return wasVisible
    }

    private var canHide: Bool {
        !coordinator.isPaused
            && !coordinator.isBuffering
            && openSection == nil
            && session.upNext == nil
    }

    private var skipAction: (title: String, seconds: Double)? {
        let settings = session.settings
        let position = coordinator.timePos
        let duration = coordinator.duration

        if settings.skipOpeningSeconds > 0, position < 300 {
            return ("Skip Intro", settings.skipOpeningSeconds)
        }
        if settings.skipEndingSeconds > 0,
           duration > 0,
           duration - position < settings.skipEndingSeconds + 60 {
            return ("Skip Ending", settings.skipEndingSeconds)
        }
        return nil
    }

    private var renderStats: String {
        let fps = coordinator.fps > 0 ? String(format: "%.1f fps", coordinator.fps) : "-- fps"
        return "\(fps) · \(coordinator.droppedFrames) dropped · "
            + String(format: "avsync %+.3f", coordinator.avsync)
            + String(format: " · cache %.1fs", coordinator.cacheSeconds)
            + " · \(coordinator.videoHeight)p · \(coordinator.preset.name)"
    }
}


private struct IconLabel: View {
    let systemImage: String

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Image(systemName: systemImage)
            .font(.title2)
            .frame(width: 78, height: 78)
            .foregroundStyle(isFocused ? Color.black : Color.white)
            .background(.white.opacity(isFocused ? 1 : 0.2), in: .circle)
            .scaleEffect(isFocused ? 1.12 : 1)
            .animation(.easeOut(duration: 0.14), value: isFocused)
    }
}

private struct PillLabel: View {
    let title: String

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Text(title)
            .font(.callout)
            .fontWeight(.semibold)
            .padding(.horizontal, 32)
            .frame(height: 78)
            .foregroundStyle(isFocused ? Color.black : Color.white)
            .background(.white.opacity(isFocused ? 1 : 0.2), in: .capsule)
            .scaleEffect(isFocused ? 1.08 : 1)
            .animation(.easeOut(duration: 0.14), value: isFocused)
    }
}


struct PlayerControlButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

extension ButtonStyle where Self == PlayerControlButtonStyle {
    static var playerControl: PlayerControlButtonStyle { PlayerControlButtonStyle() }
}
