import SwiftUI

struct PlayerOptionsMenu: View {
    enum Section: String, CaseIterable, Identifiable {
        case audio
        case subtitles
        case shaders

        var id: String { rawValue }

        var title: String {
            switch self {
            case .audio: "Audio Track"
            case .subtitles: "Subtitle Track"
            case .shaders: "Anime4K"
            }
        }

        var systemImage: String {
            switch self {
            case .audio: "speaker.wave.2"
            case .subtitles: "captions.bubble"
            case .shaders: "arrow.up.and.down.and.sparkles"
            }
        }
    }

    @ObservedObject var coordinator: MPVPlayerView.Coordinator
    let session: PlaybackSession
    let section: Section
    var onDismiss: () -> Void

    @FocusState private var focusedRow: String?

    private static let width: CGFloat = 620
    private static let rowHeight: CGFloat = 62
    private static let headerHeight: CGFloat = 62
    private static let maxHeight: CGFloat = 620
    private static let offRowID = "off"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(section.title)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.55))
                .padding(.horizontal, 34)
                .frame(height: Self.headerHeight, alignment: .bottom)
                .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    rows
                }
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(width: Self.width)
        .frame(height: min(Self.headerHeight + 24 + CGFloat(rowCount) * Self.rowHeight, Self.maxHeight))
        .background(.black.opacity(0.55), in: .rect(cornerRadius: 22))
        .background(.ultraThinMaterial, in: .rect(cornerRadius: 22))
        .environment(\.colorScheme, .dark)
        .focusSection()
        .focusEffectDisabled()
        .defaultFocus($focusedRow, defaultRowID)
        .onAppear { focusedRow = defaultRowID }
        .onExitCommand(perform: onDismiss)
    }


    @ViewBuilder
    private var rows: some View {
        switch section {
        case .audio:
            if coordinator.audioTracks.isEmpty {
                Text("No audio tracks")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.horizontal, 34)
                    .frame(height: Self.rowHeight, alignment: .center)
            } else {
                ForEach(coordinator.audioTracks) { track in
                    row(id: "audio-\(track.id)", title: track.menuLabel, isSelected: track.isSelected) {
                        session.select(track, kind: .audio)
                    }
                }
            }

        case .subtitles:
            row(id: Self.offRowID, title: "Off", isSelected: selectedSubtitle == nil) {
                session.select(nil, kind: .subtitle)
            }
            ForEach(coordinator.subtitleTracks) { track in
                row(id: "sub-\(track.id)", title: track.menuLabel, isSelected: track.isSelected) {
                    session.select(track, kind: .subtitle)
                }
            }

        case .shaders:
            ForEach(Anime4KPreset.all) { preset in
                row(
                    id: "shader-\(preset.name)",
                    title: preset.name,
                    isSelected: preset == coordinator.preset
                ) {
                    session.select(preset: preset)
                }
            }
        }
    }

    private func row(
        id: String,
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            onDismiss()
        } label: {
            RowLabel(title: title, isSelected: isSelected, height: Self.rowHeight)
        }
        .buttonStyle(.playerControl)
        .focused($focusedRow, equals: id)
    }


    private var selectedSubtitle: MPVTrack? { coordinator.selectedTrack(kind: .subtitle) }

    private var rowCount: Int {
        switch section {
        case .audio: max(coordinator.audioTracks.count, 1)
        case .subtitles: coordinator.subtitleTracks.count + 1
        case .shaders: Anime4KPreset.all.count
        }
    }

    private var defaultRowID: String {
        switch section {
        case .audio: coordinator.selectedTrack(kind: .audio).map { "audio-\($0.id)" } ?? "audio-none"
        case .subtitles: selectedSubtitle.map { "sub-\($0.id)" } ?? Self.offRowID
        case .shaders: "shader-\(coordinator.preset.name)"
        }
    }
}

private struct RowLabel: View {
    let title: String
    let isSelected: Bool
    let height: CGFloat

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            Image(systemName: "checkmark")
                .opacity(isSelected ? 1 : 0)
        }
        .font(.title3)
        .foregroundStyle(isFocused ? Color.black : Color.white)
        .padding(.horizontal, 22)
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.white)
                .opacity(isFocused ? 1 : 0)
        )
        .padding(.horizontal, 12)
        .animation(.easeOut(duration: 0.12), value: isFocused)
    }
}
