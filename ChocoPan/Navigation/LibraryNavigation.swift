import SwiftUI

@MainActor
@Observable
final class LibraryNavigation {
    static let shared = LibraryNavigation()

    /// Setup runs as a root-level mode rather than a modal: on tvOS a
    /// `fullScreenCover` renders without a background and blocks the keyboard
    /// screen its text fields need.
    var isShowingSetup = false
    var wantsReviewFilter = false

    private init() {}
}
