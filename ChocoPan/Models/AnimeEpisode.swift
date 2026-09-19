import SwiftData
import Foundation

@Model
class AnimeEpisode {
    @Attribute(.unique) var animeEpisodeId: UUID
    var fileName: String
    var relativeFilePath: String
    var fileSize: Int64
    var fileModified: Date
    var episodeNumber: Int
    var isOva: Bool
    var episodeLengthSeconds: Double
    var thumbnailUnavailable: Bool
    var playbackPositionSeconds: Double
    var watched: Bool //If playback position at 20 minutes or greater, consider watched
    var lastPlayedDate: Date
    var playCount: Int
    var dateAdded: Date
    
    var anime: Anime

    init(
        animeEpisodeId: UUID = UUID(),
        fileName: String,
        relativeFilePath: String,
        fileSize: Int64,
        fileModified: Date,
        episodeNumber: Int,
        isOva: Bool = false,
        episodeLengthSeconds: Double = 0,
        thumbnailUnavailable: Bool = false,
        playbackPositionSeconds: Double = 0,
        watched: Bool = false,
        lastPlayedDate: Date = .distantPast,
        playCount: Int = 0,
        dateAdded: Date = .now,
        anime: Anime
    ) {
        self.animeEpisodeId = animeEpisodeId
        self.fileName = fileName
        self.relativeFilePath = relativeFilePath
        self.fileSize = fileSize
        self.fileModified = fileModified
        self.episodeNumber = episodeNumber
        self.isOva = isOva
        self.episodeLengthSeconds = episodeLengthSeconds
        self.thumbnailUnavailable = thumbnailUnavailable
        self.playbackPositionSeconds = playbackPositionSeconds
        self.watched = watched
        self.lastPlayedDate = lastPlayedDate
        self.playCount = playCount
        self.dateAdded = dateAdded
        self.anime = anime
    }
}
