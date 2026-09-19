import SwiftUI

enum NavSection: String, CaseIterable, Identifiable {
    case lastWatched
    case library
    case settings
    
    var id: NavSection { self }

    var title: String {
        switch self {
        case .lastWatched: "Last Watched"
        case .library: "Library"
        case .settings: "Settings"
        }
    }
    
    var systemImage: String {
        switch self {
        case .lastWatched: "play,house"
        case .library: "books.vertical"
        case .settings: "gearshape.2"
        }
    }
    
    @ViewBuilder
    var destination: some View {
        switch self {
        case .lastWatched: LastWatchedForm()
        case .library: LibraryForm()
        case .settings: SettingsForm()
        }
    }
    
}

