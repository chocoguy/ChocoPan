import SwiftUI

struct ReviewNeededBanner: View {
    let count: Int
    @Binding var isFiltering: Bool
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 20) {
            Image(systemName: "questionmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(count) show\(count == 1 ? "" : "s") need\(count == 1 ? "s" : "") review")
                    .font(.headline)
                Text("Some anime could not be found, on these folder names.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(isFiltering ? "Show All" : "Show Them") {
                isFiltering.toggle()
            }

            Button("Dismiss", action: onDismiss)
        }
        .padding(24)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
    }
}
