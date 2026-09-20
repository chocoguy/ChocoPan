import SwiftUI

/// Explains the folder layout the scanner expects before asking for any credentials.
struct SetupInstructionsStep: View {
    let onContinue: () -> Void

    private struct Rule: Identifiable {
        let symbol: String
        let title: String
        let detail: String
        var id: String { title }
    }

    private let rules: [Rule] = [
        Rule(
            symbol: "externaldrive.connected.to.line.below",
            title: "One shared folder",
            detail: "Have 1 master folder that will hold all of your anime"
        ),
        Rule(
            symbol: "folder",
            title: "One folder per show",
            detail: "Each show gets it's own folder. Multi season anime get split into unique folders for each season"
        ),
        Rule(
            symbol: "textformat",
            title: "The folder name is the title",
            detail: "The folder name will be used to get metadata, name it accordingly. (You may add an 'ignore' folder for items you don't want scanned)"
        ),
        Rule(
            symbol: "film",
            title: "Episodes only",
            detail: "Only keep episodes inside the folders, nothing extra."
        ),
    ]

    var body: some View {
        SetupStepScaffold(
            title: "How to organize your library",
            subtitle: "Your collection comes straight off the SMB share"
        ) {
            HStack(alignment: .top, spacing: 60) {
                VStack(alignment: .leading, spacing: 28) {
                    ForEach(rules) { rule in
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(rule.title).font(.headline)
                                Text(rule.detail)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } icon: {
                            Image(systemName: rule.symbol)
                                .font(.title3)
                                .foregroundStyle(.tint)
                                .frame(width: 44)
                        }
                    }
                }
                .frame(maxWidth: 700, alignment: .leading)
            }
        } actions: {
            Button("Continue", action: onContinue)
                .buttonStyle(.borderedProminent)
        }
    }
}


    private func row(
        _ name: String,
        symbol: String,
        indent: Int,
        emphasized: Bool = false,
        muted: Bool = false
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(emphasized ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 22)
            Text(name)
                .font(.callout)
                .fontWeight(emphasized ? .semibold : .regular)
                .foregroundStyle(muted ? .secondary : .primary)
        }
        .padding(.leading, CGFloat(indent) * 28)
    }


#Preview {
    SetupInstructionsStep(onContinue: {})
}
