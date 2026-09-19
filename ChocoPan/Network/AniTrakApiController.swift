import SwiftData
import Foundation



struct AnimeSearchResult: Identifiable, Hashable, Sendable {
    let id: Int
    let apiId: Int
    let malId: Int
    let title: String
    let titleShort: String?
    let titleRomanized: String?
    let year: Int
    let episodeCount: Int
    let poster: String?
    let mediaTypeName: String?
    let seasonName: String?
    let onAir: Date?
    let synopsis: String?
    var displayTitle: String {
        titleShort ?? title
    }


    static func == (lhs: AnimeSearchResult, rhs: AnimeSearchResult) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct APISeason: Decodable {
    let seasonId: Int
    let name: String
}

struct APIMediaType: Decodable {
    let mediaTypeId: Int
    let name: String
}

struct APIAirDay: Decodable {
    let airDayId: Int?
    let name: String
}

struct APIOriginalSource: Decodable {
    let originalSourceId: Int
    let name: String
}

struct APINSFW: Decodable {
    let nsfwId: Int
    let name: String
}

struct APIAnime: Decodable {
    let animeId: Int
    let malId: Int
    let title: String
    let titleShort: String?
    let titleRomanized: String?
    let titleKana: String?
    let year: Int
    let episodeCount: Int
    let airTime: String?
    let onAir: Date?
    let offAir: Date?
    let synopsis: String?
    let reception: String?
    let malScore: Float
    let malRank: Int
    let malWatching: Int
    let malCompleted: Int
    let malOnHold: Int
    let malDropped: Int
    let malPlanToWatch: Int
    let poster: String?
    let episodeLength: Int
    let lastSynced: Date?
    let lastModified: Date?
    let season: APISeason?
    let airDay: APIAirDay?
    let mediaType: APIMediaType?
    let originalSource: APIOriginalSource?
    let nsfw: APINSFW?
    let studios: [String]?
    let tags: [String]?
}



struct AnimeRecommendation: Identifiable, Hashable, Sendable, Decodable {
    let malId: Int
    let title: String
    let poster: String?

    var id: Int { malId }
}

struct AnimeRelated: Identifiable, Hashable, Sendable, Decodable {
    let malId: Int
    let title: String
    let poster: String?
    let relationType: String

    var id: Int { malId }
}



actor AniTrakApiController {
    static let shared = AniTrakApiController()
    private let baseURL = URL(string: "https://vanillacoffeesoft.net/api/AniTrak/")!
    private let decoder: JSONDecoder
    
    private init() {
        self.decoder = Self.makeAPIDecoder()
    }
    
    //-----------------------------
    // Date Formatters, what a Mess
    //-----------------------------

    // lastSynced: "2026-07-06T23:26:16.511261Z" (UTC with fractional seconds)
    private nonisolated(unsafe) static let isoFractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    // "2026-07-06T23:26:16Z" (UTC, no fractional seconds)
    private nonisolated(unsafe) static let isoFormatter = ISO8601DateFormatter()

    // onAir/offAir/lastModified: "2018-01-07T00:00:00" (no timezone — treated as UTC)
    private nonisolated(unsafe) static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()

    // "2018-01-07"
    private nonisolated(unsafe) static let dateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func parseAPIDate(_ dateStr: String) -> Date? {
        if let date = attemptFormats(dateStr) { return date }

        if let stripped = strippingFractionalSeconds(dateStr) {
            return attemptFormats(stripped)
        }
        return nil
    }

    private static func attemptFormats(_ dateStr: String) -> Date? {
        if let date = isoFractionalFormatter.date(from: dateStr) { return date }
        if let date = isoFormatter.date(from: dateStr) { return date }
        if let date = dateTimeFormatter.date(from: dateStr) { return date }
        if let date = dateOnlyFormatter.date(from: dateStr) { return date }
        return nil
    }

    // "2026-07-07T01:16:41.307319Z" -> "2026-07-07T01:16:41Z"
    private static func strippingFractionalSeconds(_ dateStr: String) -> String? {
        guard let dotIndex = dateStr.firstIndex(of: ".") else { return nil }
        let afterDot = dateStr.index(after: dotIndex)
        let suffixStart = dateStr[afterDot...].firstIndex { !$0.isNumber } ?? dateStr.endIndex
        return String(dateStr[..<dotIndex]) + String(dateStr[suffixStart...])
    }

    private static func makeAPIDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateStr = try container.decode(String.self)

            guard let date = parseAPIDate(dateStr) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unable to parse date string: \(dateStr)"
                )
            }
            return date
        }
        return decoder
    }
    
    //-----------------------------
    // End Date Formatters
    //-----------------------------
    
    
    // MARK: - Mapping Helpers

    // The API sends "0001-01-01T00:00:00"  instead of
    // null for missing dates. Treat anything before 1900 as "no date".
    private func realDate(_ date: Date?) -> Date? {
        date.flatMap { Calendar.current.component(.year, from: $0) > 1900 ? $0 : nil }
    }

    private func mapToSearchResult(_ api: APIAnime) -> AnimeSearchResult {
        let stableId = api.malId != 0 ? api.malId : api.animeId
        
        return AnimeSearchResult(
            id: stableId,
            apiId: api.animeId,
            malId: api.malId,
            title: api.title,
            titleShort: api.titleShort,
            titleRomanized: api.titleRomanized,
            year: api.year,
            episodeCount: api.episodeCount,
            poster: api.poster,
            mediaTypeName: api.mediaType?.name,
            seasonName: api.season?.name,
            onAir: api.onAir,
            synopsis: api.synopsis
        )
    }
    

    func search(query: String) async throws -> [AnimeSearchResult] {
        guard var components = URLComponents(url: baseURL.appendingPathComponent("anime/search"), resolvingAgainstBaseURL: true) else {
            throw URLError(.badURL)
        }
        components.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "password", value: "supersecretlacroixrangersixseven")]
        
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }
        
        let apiResults = try decoder.decode([APIAnime].self, from: data)
        return apiResults.map { mapToSearchResult($0) }
    }
    
    
    func searchForceMal(query: String) async throws -> [AnimeSearchResult] {
        guard var components = URLComponents(url: baseURL.appendingPathComponent("anime/search/forcemal"), resolvingAgainstBaseURL: true) else {
            throw URLError(.badURL)
        }
        components.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "password", value: "supersecretlacroixrangersixseven")]
        
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }
        
        let apiResults = try decoder.decode([APIAnime].self, from: data)
        return apiResults.map { mapToSearchResult($0) }
    }
    
    

    func getPicturesMal(malId: Int) async throws -> [String] {
        let url = baseURL.appendingPathComponent("anime/\(malId)/pictures")

        let (data, response) = try await URLSession.shared.data(from: url)

        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }

        return try decoder.decode([String].self, from: data)
    }



    func fetchAnime(by apiId: Int) async throws -> APIAnime {
        let url = baseURL.appendingPathComponent("anime/\(apiId)")
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }
        
        return try decoder.decode(APIAnime.self, from: data)
    }
    

    
    //This runs second, now that the server has synced the records, we take the ApiAnime record and convert it to a SwiftData Anime Record
    /// `folderPath`/`folderName` are local concerns the API knows nothing about. A caller that has
    /// already matched this anime to a folder on disk passes them; a plain metadata import leaves
    /// them empty for the scanner to fill in later.
    func importAnime(
        from apiAnime: APIAnime,
        into context: ModelContext,
        folderPath: String = "",
        folderName: String = ""
    ) throws -> Anime {

        // Upsert on malId: it is the only stable API-side key the local model carries. A malId of 0
        // means the server has no MAL match, so there is nothing to match on and this is always new.
        let malAnimeId: Int? = apiAnime.malId != 0 ? apiAnime.malId : nil

        if let malAnimeId {
            var existingDescriptor = FetchDescriptor<Anime>(
                predicate: #Predicate { $0.malId == malAnimeId }
            )
            existingDescriptor.fetchLimit = 1

            if let existing = try? context.fetch(existingDescriptor).first {
                // Refresh the API-owned fields and leave everything local alone — folder, poster
                // cache, track preferences, source and dateAdded all survive a re-sync.
                apply(apiAnime, to: existing)
                return existing
            }
        }

        let localAnime = Anime(
            folderPath: folderPath,
            folderName: folderName,
            malId: malAnimeId,
            title: apiAnime.title,
            titleShort: apiAnime.titleShort,
            titleRomanized: apiAnime.titleRomanized,
            titleKana: apiAnime.titleKana,
            shownTitle: apiAnime.titleShort ?? apiAnime.title,
            year: apiAnime.year,
            episodes: apiAnime.episodeCount,
            IsLinkedToMal: malAnimeId != nil,
            seasonName: apiAnime.season?.name ?? "unknown",
            mediaTypeName: apiAnime.mediaType?.name ?? "unknown",
            tags: apiAnime.tags ?? [],
            studios: apiAnime.studios ?? [],
            synopsis: apiAnime.synopsis,
            posterURL: apiAnime.poster
        )

        context.insert(localAnime)
        return localAnime
    }

    /// Copies the fields the API owns onto an existing record.
    private func apply(_ apiAnime: APIAnime, to anime: Anime) {
        let malAnimeId: Int? = apiAnime.malId != 0 ? apiAnime.malId : nil

        anime.malId = malAnimeId
        anime.IsLinkedToMal = malAnimeId != nil
        anime.title = apiAnime.title
        anime.titleShort = apiAnime.titleShort
        anime.titleRomanized = apiAnime.titleRomanized
        anime.titleKana = apiAnime.titleKana
        anime.year = apiAnime.year
        anime.episodes = apiAnime.episodeCount
        anime.seasonName = apiAnime.season?.name ?? "unknown"
        anime.mediaTypeName = apiAnime.mediaType?.name ?? "unknown"
        anime.tags = apiAnime.tags ?? []
        anime.studios = apiAnime.studios ?? []
        anime.synopsis = apiAnime.synopsis
        anime.posterURL = apiAnime.poster
    }
    

    
    //This runs first, From the list of the "search" and "searchForceMal" we take the id of the desired record and feed it to this method
    func importAnime(by apiId: Int, into context: ModelContext) async throws -> Anime {
        
        
        guard var components = URLComponents(url: baseURL.appendingPathComponent("anime/\(apiId)/sync"), resolvingAgainstBaseURL: true) else {
            throw URLError(.badURL)
        }
        components.queryItems = [URLQueryItem(name: "password", value: "supersecretlacroixrangersixseven")]
        
        guard let url = components.url else {
            throw URLError(.badURL)
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }

        // The /sync route just returns the synced anime's id as an integer.
        let syncedId = try JSONDecoder().decode(Int.self, from: data)
        let apiAnime = try await fetchAnime(by: syncedId)
        


        let local = try importAnime(from: apiAnime, into: context)
        try context.save()
        return local
    }
}

