import SwiftUI
//
struct NoLibrarySourceView: View {
    var body: some View {
        ContentUnavailableView {
            Label("No Library Source", systemImage: "externaldrive.badge.questionmark")
        } description: {
            Text("Go to the settings page to set up your libray.")
        }
    }
}

#Preview {
    NoLibrarySourceView()
}
