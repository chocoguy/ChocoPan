import SwiftData
import SwiftUI

struct SetupWizardView: View {
    let onCancel: () -> Void
    let onFinish: (_ wantsReview: Bool) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    @State private var coordinator = LibrarySetupCoordinator()

    var body: some View {
        ZStack {
            switch coordinator.step {
            case .instructions:
                SetupInstructionsStep {
                    coordinator.advance(to: .credentials)
                }

            case .credentials:
                SetupCredentialsStep(coordinator: coordinator) {
                    coordinator.back()
                }

            case .selectShare:
                SetupShareStep(coordinator: coordinator) {
                    coordinator.back()
                } onScan: {
                    coordinator.startScan(context: context)
                }

            case .scanning:
                SetupScanProgressStep(phase: coordinator.scanPhase)

            case .summary:
                SetupSummaryStep(summary: coordinator.summary) {
                    finish(wantsReview: false)
                } onReview: {
                    finish(wantsReview: true)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onExitCommand(perform: handleExit)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                coordinator.cancelScan()
            }
        }
    }

    private func handleExit() {
        switch coordinator.step {
        case .instructions:
            onCancel()
        case .credentials, .selectShare:
            coordinator.back()
        case .scanning:
            coordinator.cancelScan()
        case .summary:
            finish(wantsReview: false)
        }
    }

    private func finish(wantsReview: Bool) {
        let hasPending = coordinator.summary.retrying > 0
        // onFinish tears this view down, so hold the context the retry needs.
        let context = context
        onFinish(wantsReview)
        guard hasPending else { return }
        Task { await LibrarySetupCoordinator.retryPending(context: context) }
    }
}

#Preview {
    SetupWizardView(onCancel: {}, onFinish: { _ in })
        .modelContainer(ChocoPanModelContainer.preview)
}
