import SwiftUI

struct SetupSummaryStep: View {
    let summary: LibrarySetupCoordinator.Summary
    let onFinish: () -> Void
    let onReview: () -> Void

    @State private var showingMismatches = false

    var body: some View {
        SetupStepScaffold(
            title: "Your library is ready",
            subtitle: subtitle
        ) {
            VStack(alignment: .leading, spacing: 32) {
                HStack(spacing: 20) {
                    Tally(
                        value: summary.matched,
                        label: "matched",
                        symbol: "checkmark.circle.fill",
                        tint: .green
                    )
                    if summary.needsReview > 0 {
                        Tally(
                            value: summary.needsReview,
                            label: "need review",
                            symbol: "questionmark.circle.fill",
                            tint: .orange
                        )
                    }
                    if summary.notFound > 0 {
                        Tally(
                            value: summary.notFound,
                            label: "not found",
                            symbol: "xmark.circle.fill",
                            tint: .secondary
                        )
                    }
                    if summary.retrying > 0 {
                        Tally(
                            value: summary.retrying,
                            label: "still looking",
                            symbol: "arrow.clockwise.circle.fill",
                            tint: .blue
                        )
                    }
                }

                if summary.retrying > 0 {
                    Label(
                        "Remaining titles will be looked at in the background.",
                        systemImage: "info.circle"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
        } actions: {
            Button("Finish", action: onFinish)
                .buttonStyle(.borderedProminent)

            if summary.hasUnresolved {
                Button("Review \(summary.needsReview + summary.notFound) Shows", action: onReview)
            }
        }
        .onAppear { showingMismatches = summary.hasUnresolved }
        .alert("Some shows need a closer look", isPresented: $showingMismatches) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(mismatchMessage)
        }
    }

    private var subtitle: String {
        let shows = summary.matched + summary.needsReview + summary.notFound + summary.retrying
        return "\(shows) show\(shows == 1 ? "" : "s") · \(summary.episodeCount) episode\(summary.episodeCount == 1 ? "" : "s")"
    }

    private var mismatchMessage: String {
        let names = summary.unresolvedFolders.prefix(8).joined(separator: "\n")
        let extra = summary.unresolvedFolders.count - 8

        var message = "Cannot identify these folders: \n\n\(names)"
        if extra > 0 {
            message += "\n…and \(extra) more"
        }
        message += "\n\nSet the right title in the Library page."
        return message
    }
}

private struct Tally: View {
    let value: Int
    let label: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.title)
                .foregroundStyle(tint)
            Text("\(value)")
                .font(.largeTitle)
                .fontWeight(.semibold)
                .monospacedDigit()
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(minWidth: 200, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
    }
}

#Preview {
    SetupSummaryStep(
        summary: .init(
            matched: 118,
            needsReview: 2,
            notFound: 1,
            retrying: 0,
            unresolvedFolders: ["Some Weird Folder", "another.one.2019", "raws"],
            episodeCount: 1483
        ),
        onFinish: {},
        onReview: {}
    )
}
