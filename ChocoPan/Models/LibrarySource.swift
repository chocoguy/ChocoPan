import SwiftData
import Foundation


@Model
class LibrarySource {
    @Attribute(.unique) var librarySourceId: UUID
    var name: String
    var host: String?
    var share: String
    var rootPath: String
    var username: String
    var keychainAccount: String
    var dateAdded: Date
    var lastScanDate: Date?
    
    @Relationship(deleteRule: .cascade, inverse: \Anime.source)
    var anime: [Anime] = []

    init(
        librarySourceId: UUID = UUID(),
        name: String,
        host: String? = nil,
        share: String,
        rootPath: String = "",
        username: String = "",
        keychainAccount: String = UUID().uuidString,
        dateAdded: Date = .now,
        lastScanDate: Date? = nil,
        anime: [Anime] = []
    ) {
        self.librarySourceId = librarySourceId
        self.name = name
        self.host = host
        self.share = share
        self.rootPath = rootPath
        self.username = username
        self.keychainAccount = keychainAccount
        self.dateAdded = dateAdded
        self.lastScanDate = lastScanDate
        self.anime = anime
    }
}

extension LibrarySource {
    /// Joins `rootPath` to a folder name, tolerating an empty or slash-padded root.
    func path(forFolder folderName: String) -> String {
        let root = rootPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return root.isEmpty ? folderName : "\(root)/\(folderName)"
    }
}
