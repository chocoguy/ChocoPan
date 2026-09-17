import SwiftUI

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
}
