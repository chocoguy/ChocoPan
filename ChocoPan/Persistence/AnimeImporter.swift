import SwiftData
import Foundation

@MainActor
enum AnimeImporter {
    @discardableResult
    static func upsert(
        _ apiAnime: APIAnime,
        into context: ModelContext,
        folderPath: String = "",
        folderName: String = "",
        folderModifiedDate: Date? = nil,
        episodeFileCount: Int? = nil,
        source: LibrarySource? = nil
    ) -> Anime {
        let malAnimeId: Int? = apiAnime.malId != 0 ? apiAnime.malId : nil

        if let malAnimeId {
            var descriptor = FetchDescriptor<Anime>(
                predicate: #Predicate { $0.malId == malAnimeId }
            )
            descriptor.fetchLimit = 1

            if let existing = try? context.fetch(descriptor).first {
                // Refresh the API-owned fields and leave everything local alone — poster cache,
                // track preferences, watch state and dateAdded all survive a re-sync.
                apply(apiAnime, to: existing)
                if !folderPath.isEmpty { existing.folderPath = folderPath }
                if !folderName.isEmpty { existing.folderName = folderName }
                if let folderModifiedDate { existing.folderModifiedDate = folderModifiedDate }
                if let source { existing.source = source }
                existing.missingSince = nil
                return existing
            }
        }

        let anime = Anime(
            folderPath: folderPath,
            folderName: folderName,
            malId: malAnimeId,
            title: apiAnime.title,
            titleShort: apiAnime.titleShort,
            titleRomanized: apiAnime.titleRomanized,
            titleKana: apiAnime.titleKana,
            shownTitle: apiAnime.titleShort ?? apiAnime.title,
            year: apiAnime.year,
            episodeCount: apiAnime.episodeCount,
            IsLinkedToMal: malAnimeId != nil,
            seasonName: apiAnime.season?.name ?? "unknown",
            mediaTypeName: apiAnime.mediaType?.name ?? "unknown",
            tags: apiAnime.tags ?? [],
            studios: apiAnime.studios ?? [],
            synopsis: apiAnime.synopsis,
            posterURL: apiAnime.poster,
            metadataState: .matched,
            folderModifiedDate: folderModifiedDate,
            source: source
        )

        context.insert(anime)
        return anime
    }

    /// Copies the fields the API owns onto an existing record and marks it resolved.
    static func apply(_ apiAnime: APIAnime, to anime: Anime) {
        let malAnimeId: Int? = apiAnime.malId != 0 ? apiAnime.malId : nil

        anime.malId = malAnimeId
        anime.IsLinkedToMal = malAnimeId != nil
        anime.title = apiAnime.title
        anime.titleShort = apiAnime.titleShort
        anime.titleRomanized = apiAnime.titleRomanized
        anime.titleKana = apiAnime.titleKana
        anime.shownTitle = apiAnime.titleShort ?? apiAnime.title
        anime.year = apiAnime.year
        anime.episodeCount = apiAnime.episodeCount
        anime.seasonName = apiAnime.season?.name ?? "unknown"
        anime.mediaTypeName = apiAnime.mediaType?.name ?? "unknown"
        anime.tags = apiAnime.tags ?? []
        anime.studios = apiAnime.studios ?? []
        anime.synopsis = apiAnime.synopsis
        anime.posterURL = apiAnime.poster

        anime.metadataState = .matched
        anime.unresolvedNumber = nil
    }
}
