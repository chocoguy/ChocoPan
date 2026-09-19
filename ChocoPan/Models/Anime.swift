import SwiftData
import Foundation

@Model
class Anime {
    @Attribute(.unique) var animeId: UUID
    var folderPath: String
    var folderName: String
    var malId: Int?
    
    var title: String
    var titleShort: String?
    var titleRomanized: String?
    var titleKana: String?
    var shownTitle: String
    var year: Int
    var episodes: Int
    var IsLinkedToMal: Bool
    
    var seasonName: String
    var mediaTypeName: String
    var tags: [String] = []
    var studios: [String] = []
    
    var synopsis: String?
    
    var posterURL: String?
    
    var preferredAudioTrack: String?
    var preferredSubTrack: String?
    
    var dateAdded: Date
    
    var source: LibrarySource?

    init(
        animeId: UUID = UUID(),
        folderPath: String,
        folderName: String,
        malId: Int? = nil,
        title: String,
        titleShort: String? = nil,
        titleRomanized: String? = nil,
        titleKana: String? = nil,
        shownTitle: String? = nil,
        year: Int,
        episodes: Int,
        IsLinkedToMal: Bool = false,
        seasonName: String,
        mediaTypeName: String,
        tags: [String] = [],
        studios: [String] = [],
        synopsis: String? = nil,
        posterURL: String? = nil,
        preferredAudioTrack: String? = nil,
        preferredSubTrack: String? = nil,
        dateAdded: Date = .now,
        source: LibrarySource? = nil
    ) {
        self.animeId = animeId
        self.folderPath = folderPath
        self.folderName = folderName
        self.malId = malId
        self.title = title
        self.titleShort = titleShort
        self.titleRomanized = titleRomanized
        self.titleKana = titleKana
        self.shownTitle = shownTitle ?? title
        self.year = year
        self.episodes = episodes
        self.IsLinkedToMal = IsLinkedToMal
        self.seasonName = seasonName
        self.mediaTypeName = mediaTypeName
        self.tags = tags
        self.studios = studios
        self.synopsis = synopsis
        self.posterURL = posterURL
        self.preferredAudioTrack = preferredAudioTrack
        self.preferredSubTrack = preferredSubTrack
        self.dateAdded = dateAdded
        self.source = source
    }
}
