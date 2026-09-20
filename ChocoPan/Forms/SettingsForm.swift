import SwiftData
import SwiftUI

struct SettingsForm: View {
    @Environment(\.modelContext) private var context
    @Query private var librarySources: [LibrarySource]
    @Query private var anime: [Anime]
    @Query private var settingsRecords: [ChocoPanSettings]

    @State private var isConfirmingRemoval = false
    @State private var refresher = ImageCacheRefresher()
    @State private var cacheStatistics = CacheStatistics(fileCount: 0, byteCount: 0)

    private let navigation = LibraryNavigation.shared

    var body: some View {
        if let source = librarySources.first {
            configured(source)
        } else {
            unconfigured
        }
    }

    private var unconfigured: some View {
        VStack(spacing: 28) {
            Image(systemName: "externaldrive.badge.plus")
                .font(.system(size: 80))
                .foregroundStyle(.tint)

            VStack(spacing: 10) {
                Text("Set Up")
                    .font(.title)
                    .fontWeight(.semibold)
                Text("Connect to your anime SMB share")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Button("Start") { navigation.isShowingSetup = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(80)
    }

    private func configured(_ source: LibrarySource) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                Text("Settings")
                    .font(.largeTitle)
                    .fontWeight(.semibold)

                SettingsCard(title: "Library Source") {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(
                            "\(source.host ?? "unknown") · \(source.share)",
                            systemImage: "externaldrive.connected.to.line.below"
                        )
                        .font(.headline)

                        Text(detail(for: source))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 20) {
                        Button("Reconfigure") { navigation.isShowingSetup = true }
                        Button("Remove Library", role: .destructive) {
                            isConfirmingRemoval = true
                        }
                    }
                }

                if let settings {
                    PlaybackSettingsSection(settings: settings)
                    VideoSettingsSection(settings: settings)
                    LibrarySettingsSection(settings: settings)
                }

                imageCache

                if let settings {
                    AdvancedSettingsSection(settings: settings)
                }
            }
            .padding(80)
        }
        .task {
            // Creates the singleton on first run; @Query picks it up from there.
            _ = ChocoPanSettings.shared(in: context)
            cacheStatistics = await ImageCacher.shared.statistics()
        }
        .alert("Remove this library?", isPresented: $isConfirmingRemoval) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) { remove(source) }
        } message: {
            Text("This removes \(source.anime.count) shows from the app. Data in the share will not be touched")
        }
    }

    private var settings: ChocoPanSettings? { settingsRecords.first }

    private var imageCache: some View {
        SettingsCard(title: "Image Cache") {
            VStack(alignment: .leading, spacing: 8) {
                Label(cacheStatistics.description, systemImage: "photo.stack")
                    .font(.headline)

                Text(cacheStatus)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await rebuildCache() }
            } label: {
                Label("Re-cache Images", systemImage: "arrow.clockwise")
            }
            .disabled(refresher.isRunning || posterURLs.isEmpty)
        }
    }

    private var cacheStatus: String {
        switch refresher.phase {
        case .idle:
            return "Clears every cached poster and thumbnail, then downloads "
                + "\(posterURLs.count) poster\(posterURLs.count == 1 ? "" : "s") again. "
                + "Thumbnails rebuild themselves as episodes are shown."
        case .running(let completed, let total):
            return "Rebuilding… \(completed) of \(total)"
        case .finished(let summary):
            return summary
        }
    }

    private var posterURLs: [URL] {
        anime.compactMap(\.posterSource)
    }

    private func rebuildCache() async {
        await refresher.rebuild(posterURLs: posterURLs)
        if let settings {
            await ImageCacher.shared.evictIfNeeded(limitMB: settings.thumbnailCacheLimitMB)
        }
        cacheStatistics = await ImageCacher.shared.statistics()
    }

    private func detail(for source: LibrarySource) -> String {
        let shows = "\(source.anime.count) show\(source.anime.count == 1 ? "" : "s")"
        guard let scanned = source.lastScanDate else { return shows }
        return "\(shows) · last scanned \(scanned.formatted(date: .abbreviated, time: .shortened))"
    }

    private func remove(_ source: LibrarySource) {
        SMBCredentialStore.delete(account: source.keychainAccount)
        context.delete(source)
        try? context.save()
    }
}

#Preview {
    SettingsForm()
        .modelContainer(ChocoPanModelContainer.preview)
}
