import SwiftData
import SwiftUI

struct SettingsForm: View {
    @Environment(\.modelContext) private var context
    @Query private var librarySources: [LibrarySource]

    @State private var isConfirmingRemoval = false

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

                VStack(alignment: .leading, spacing: 20) {
                    Text("Library Source")
                        .font(.title3)
                        .fontWeight(.semibold)

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
                .padding(32)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: .rect(cornerRadius: 16))

                Text("Playback and scanning settings will appear here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(80)
        }
        .alert("Remove this library?", isPresented: $isConfirmingRemoval) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) { remove(source) }
        } message: {
            Text("This removes \(source.anime.count) shows from the app. Data in the share will not be touched")
        }
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
