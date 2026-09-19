import SwiftData
import Foundation


@Model
class LibrarySource {
    @Attribute(.unique) var librarySourceId: UUID
    var name: String
    var host: String?
    var rootPath: String
    var keychainAccount: String
    var dateAdded: Date
    
    @Relationship(deleteRule: .cascade, inverse: \Anime.source)
    var anime: [Anime] = []

    init(
        librarySourceId: UUID = UUID(),
        name: String,
        host: String? = nil,
        rootPath: String,
        keychainAccount: String,
        dateAdded: Date = .now,
        anime: [Anime] = []
    ) {
        self.librarySourceId = librarySourceId
        self.name = name
        self.host = host
        self.rootPath = rootPath
        self.keychainAccount = keychainAccount
        self.dateAdded = dateAdded
        self.anime = anime
    }
}

