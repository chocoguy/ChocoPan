import SwiftUI

struct SetupScanProgressStep: View {
    let phase: LibrarySetupCoordinator.ScanPhase

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            if let fraction = phase.fraction {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 700)
            } else {
                ProgressView()
                    .controlSize(.large)
            }

            VStack(spacing: 10) {
                Text(phase.message)
                    .font(.title2)

                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(80)
    }

    private var detail: String {
        switch phase {
        case .connecting, .listing:
            "This will take a bit..."
        case .savingFolders:
            "Reading episode files...."
        case .matching:
            "Looking up titles and artwork..."
        case .finishing:
            "Almost done..."
        }
    }
}

#Preview {
    SetupScanProgressStep(phase: .matching(done: 43, total: 120))
}
