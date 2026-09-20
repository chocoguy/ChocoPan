import SwiftUI
import SwiftData

struct LastWatchedForm: View {
    @Query private var librarySources: [LibrarySource]

    var body: some View {
        if librarySources.isEmpty {
            NoLibrarySourceView()
        } else {
            Text("Last Watched Form")
        }
    }
}

#Preview {
    LastWatchedForm()
        .modelContainer(ChocoPanModelContainer.preview)
}
