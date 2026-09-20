import SwiftData
import Foundation

nonisolated enum AnimeMetadataState: String, Codable, CaseIterable, Identifiable {
    case pending
    case matched
    case needsReview
    case notFound

    var id: String { rawValue }

    var needsAttention: Bool { self == .needsReview || self == .notFound }
}

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
    var episodeCount: Int
    var IsLinkedToMal: Bool
    
    var seasonName: String
    var mediaTypeName: String
    var tags: [String] = []
    var studios: [String] = []
    
    var synopsis: String?
    
    var posterWebURL: URL?
    var posterURL: String?
    
    var preferredAudioTrack: String?
    var preferredSubTrack: String?
    
    var dateAdded: Date


    var metadataState: AnimeMetadataState
    var unresolvedNumber: Int?
    var folderModifiedDate: Date?
    var missingSince: Date?

    var source: LibrarySource?

    @Relationship(deleteRule: .cascade, inverse: \AnimeEpisode.anime)
    var episodes: [AnimeEpisode] = []

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
        episodeCount: Int,
        IsLinkedToMal: Bool = false,
        seasonName: String,
        mediaTypeName: String,
        tags: [String] = [],
        studios: [String] = [],
        synopsis: String? = nil,
        posterWebURL: URL? = nil,
        posterURL: String? = nil,
        preferredAudioTrack: String? = nil,
        preferredSubTrack: String? = nil,
        dateAdded: Date = .now,
        metadataState: AnimeMetadataState = .pending,
        unresolvedNumber: Int? = nil,
        folderModifiedDate: Date? = nil,
        missingSince: Date? = nil,
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
        self.episodeCount = episodeCount
        self.IsLinkedToMal = IsLinkedToMal
        self.seasonName = seasonName
        self.mediaTypeName = mediaTypeName
        self.tags = tags
        self.studios = studios
        self.synopsis = synopsis
        self.posterWebURL = posterWebURL
        self.posterURL = posterURL
        self.preferredAudioTrack = preferredAudioTrack
        self.preferredSubTrack = preferredSubTrack
        self.dateAdded = dateAdded
        self.metadataState = metadataState
        self.unresolvedNumber = unresolvedNumber
        self.folderModifiedDate = folderModifiedDate
        self.missingSince = missingSince
        self.source = source
    }
}

extension Anime {
    static func unresolved(
        folderPath: String,
        folderName: String,
        number: Int,
        state: AnimeMetadataState,
        folderModifiedDate: Date?,
        episodeCount: Int,
        source: LibrarySource?
    ) -> Anime {
        Anime(
            folderPath: folderPath,
            folderName: folderName,
            title: folderName,
            shownTitle: "Unknown Anime #\(number)",
            year: 0,
            episodeCount: episodeCount,
            seasonName: "unknown",
            mediaTypeName: "unknown",
            metadataState: state,
            unresolvedNumber: number,
            folderModifiedDate: folderModifiedDate,
            source: source
        )
    }

    /// Reverts a record to the unresolved placeholder presentation.
    func markUnresolved(number: Int, state: AnimeMetadataState) {
        metadataState = state
        unresolvedNumber = number
        shownTitle = "Unknown Anime #\(number)"
        title = folderName
    }

    /// Where the poster is fetched from. Prefers the typed URL, falling back to the string field
    /// for rows imported before `posterWebURL` existed — those only fill in on the next scan.
    var posterSource: URL? {
        posterWebURL ?? posterURL.flatMap { URL(string: $0) }
    }

    /// Regular episodes first, then OVAs, each ascending by number.
    var orderedEpisodes: [AnimeEpisode] {
        episodes.sorted {
            ($0.isOva ? 1 : 0, $0.episodeNumber) < ($1.isOva ? 1 : 0, $1.episodeNumber)
        }
    }

    /// What the play button offers: the episode left partway through, otherwise the first
    /// unwatched one, otherwise the start of the show again.
    var nextEpisode: AnimeEpisode? {
        let ordered = orderedEpisodes
        let inProgress = ordered
            .filter { !$0.watched && $0.playbackPositionSeconds > 0 }
            .max { $0.lastPlayedDate < $1.lastPlayedDate }
        return inProgress ?? ordered.first { !$0.watched } ?? ordered.first
    }
}
