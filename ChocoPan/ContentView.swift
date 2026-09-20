import SwiftUI
import SwiftData

struct ContentView: View {
    //CLI stuff
    @State private var isPlayerPresented = ProcessInfo.processInfo.arguments.contains("-playTestMedia")

    private let navigation = LibraryNavigation.shared

    var body: some View {
        Group {
            if navigation.isShowingSetup {
                SetupWizardView {
                    navigation.isShowingSetup = false
                } onFinish: { wantsReview in
                    navigation.wantsReviewFilter = wantsReview
                    navigation.isShowingSetup = false
                }
            } else {
                TvNav()
            }
        }
        .fullScreenCover(isPresented: $isPlayerPresented) {
            PlayerTestView()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(ChocoPanModelContainer.preview)
}
