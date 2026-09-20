import SwiftUI

/// Picks from the shares the server advertised, rather than making someone type one with a
/// TV remote.
struct SetupShareStep: View {
    @Bindable var coordinator: LibrarySetupCoordinator
    let onBack: () -> Void
    let onScan: () -> Void

    var body: some View {
        SetupStepScaffold(
            title: "Choose your library share",
            subtitle: "Pick the share that holds one folder per show."
        ) {
            VStack(alignment: .leading, spacing: 24) {
                if coordinator.availableShares.isEmpty {
                    Text("No shares announced")
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(coordinator.availableShares, id: \.self) { share in
                                ShareRow(
                                    name: share,
                                    isSelected: coordinator.selectedShare == share
                                ) {
                                    coordinator.selectedShare = share
                                }
                            }
                        }
                    }
                    .frame(maxWidth: 800, maxHeight: 460)
                }

                if let error = coordinator.error {
                    SetupErrorBanner(error: error)
                }
            }
        } actions: {
            Button("Back", action: onBack)

            Button("Scan Library", action: onScan)
                .buttonStyle(.borderedProminent)
                .disabled(coordinator.selectedShare.isEmpty)
        }
    }
}

private struct ShareRow: View {
    let name: String
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 20) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.tint)
                Text(name)
                    .font(.title3)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
