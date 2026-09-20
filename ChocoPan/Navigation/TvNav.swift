import SwiftUI
import SwiftData

struct TvNav: View {
    var body: some View {
        TabView {
            ForEach(NavSection.allCases) { section in
                Tab(section.title, systemImage: section.systemImage) {
                    section.destination
                }
            }
        }
    }
}

#Preview {
    TvNav()
        .modelContainer(ChocoPanModelContainer.preview)
}
