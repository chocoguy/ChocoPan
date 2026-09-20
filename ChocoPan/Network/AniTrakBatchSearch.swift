import Foundation

/// `POST /api/AniTrak/Anime/search/batch` request body.
nonisolated struct BatchAnimeSearchRequest: Encodable {
    let titles: [String]
}

nonisolated enum BatchSource: String, Decodable, Sendable {
    case local = "Local"
    case mal = "Mal"
    case unconfirmed = "Unconfirmed"
    case notFound = "NotFound"
    case unavailable = "Unavailable"
}

nonisolated enum BatchResolvedVia: String, Decodable, Sendable {
    case none = "None"
    case local = "Local"
    case aniList = "AniList"
    case malSearch = "MalSearch"
}

nonisolated enum BatchConfidence: String, Decodable, Sendable {
    case none = "None"
    case weak = "Weak"
    case strong = "Strong"
    case exact = "Exact"

    var isTrustworthy: Bool { self == .strong || self == .exact }
}

nonisolated struct BatchAnimeSearchResult: Decodable {
    let query: String
    let anime: APIAnime?
    let source: BatchSource
    let resolvedVia: BatchResolvedVia
    let confidence: BatchConfidence
    let stored: Bool
    var shouldRetry: Bool { source == .unavailable }
}

nonisolated struct BatchAnimeSearchResponse: Decodable {
    let results: [BatchAnimeSearchResult]
    let localHits: Int
    let malHits: Int
    let unconfirmed: Int
    let notFound: Int
    let unavailable: Int
    let aniListRequestsMade: Int
    let malCallsMade: Int
    let malBudgetExhausted: Bool
}
