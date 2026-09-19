import SwiftUI

struct ContentView: View {
    //CLI stuff
    @State private var isPlayerPresented = ProcessInfo.processInfo.arguments.contains("-playTestMedia")

    var body: some View {
        TvNav()
            .fullScreenCover(isPresented: $isPlayerPresented) {
                PlayerTestView()
            }
    }
}

#Preview {
    ContentView()
}
