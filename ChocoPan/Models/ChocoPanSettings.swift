import SwiftData
import Foundation

@Model
final class ChocoPanSettings {
    static let singletonId = UUID(uuidString: "C4000000-0000-4000-A000-000000000001")!

    @Attribute(.unique) var settingsId: UUID
    var autoPlayNextEpisode: Bool
    var autoPlayNextDelaySeconds: Double
    var matchContentFrameRate: Bool
    var skipOpeningSeconds: Double
    var skipEndingSeconds: Double
    var seekSmallSeconds: Double
    var seekLargeSeconds: Double
    var resumeMinimumSeconds: Double
    var watchedThresholdFraction: Double
    var defaultPlaybackSpeed: Double


    var anime4KEnabled: Bool
    var anime4KPresetSDName: String
    var anime4KPresetHDName: String
    var anime4KPresetUHDName: String


    var showStatsOverlay: Bool
    var hardwareDecodingEnabled: Bool
    var mpvLogLevel: MPVLogLevel
    var extraMpvOptions: String


    var autoScanOnLaunch: Bool
    var lastScanDate: Date?
    var generateThumbnailsOnScan: Bool
    var thumbnailMaxWidth: Int
    var thumbnailCacheLimitMB: Int
    var hideWatchedEpisodes: Bool
    var defaultSource: LibrarySource?

    init(
        settingsId: UUID = ChocoPanSettings.singletonId,
        autoPlayNextEpisode: Bool = true,
        autoPlayNextDelaySeconds: Double = 8,
        matchContentFrameRate: Bool = true,
        skipOpeningSeconds: Double = 90,
        skipEndingSeconds: Double = 90,
        seekSmallSeconds: Double = 10,
        seekLargeSeconds: Double = 60,
        resumeMinimumSeconds: Double = 30,
        watchedThresholdFraction: Double = 0.9,
        defaultPlaybackSpeed: Double = 1.0,
        anime4KEnabled: Bool = true,
        anime4KPresetSDName: String = "A (HQ)",
        anime4KPresetHDName: String = "A (HQ)",
        anime4KPresetUHDName: String = "Off",
        showStatsOverlay: Bool = false,
        hardwareDecodingEnabled: Bool = true,
        mpvLogLevel: MPVLogLevel = .none,
        extraMpvOptions: String = "",
        autoScanOnLaunch: Bool = true,
        lastScanDate: Date? = nil,
        generateThumbnailsOnScan: Bool = true,
        thumbnailMaxWidth: Int = 640,
        thumbnailCacheLimitMB: Int = 256,
        hideWatchedEpisodes: Bool = false,
        defaultSource: LibrarySource? = nil
    ) {
        self.settingsId = settingsId
        self.autoPlayNextEpisode = autoPlayNextEpisode
        self.autoPlayNextDelaySeconds = autoPlayNextDelaySeconds
        self.matchContentFrameRate = matchContentFrameRate
        self.skipOpeningSeconds = skipOpeningSeconds
        self.skipEndingSeconds = skipEndingSeconds
        self.seekSmallSeconds = seekSmallSeconds
        self.seekLargeSeconds = seekLargeSeconds
        self.resumeMinimumSeconds = resumeMinimumSeconds
        self.watchedThresholdFraction = watchedThresholdFraction
        self.defaultPlaybackSpeed = defaultPlaybackSpeed
        self.anime4KEnabled = anime4KEnabled
        self.anime4KPresetSDName = anime4KPresetSDName
        self.anime4KPresetHDName = anime4KPresetHDName
        self.anime4KPresetUHDName = anime4KPresetUHDName
        self.showStatsOverlay = showStatsOverlay
        self.hardwareDecodingEnabled = hardwareDecodingEnabled
        self.mpvLogLevel = mpvLogLevel
        self.extraMpvOptions = extraMpvOptions
        self.autoScanOnLaunch = autoScanOnLaunch
        self.lastScanDate = lastScanDate
        self.generateThumbnailsOnScan = generateThumbnailsOnScan
        self.thumbnailMaxWidth = thumbnailMaxWidth
        self.thumbnailCacheLimitMB = thumbnailCacheLimitMB
        self.hideWatchedEpisodes = hideWatchedEpisodes
        self.defaultSource = defaultSource
    }
}


extension ChocoPanSettings {
    static func shared(in context: ModelContext) -> ChocoPanSettings {
        let id = singletonId
        var descriptor = FetchDescriptor<ChocoPanSettings>(
            predicate: #Predicate { $0.settingsId == id }
        )
        descriptor.fetchLimit = 1

        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let created = ChocoPanSettings()
        context.insert(created)
        return created
    }
}


extension ChocoPanSettings {
    enum ResolutionBucket {
        case sd   // up to 720p
        case hd   // up to 1080p
        case uhd  // above 1080p

        init(videoHeight: Int) {
            switch videoHeight {
            case ..<721: self = .sd
            case ..<1081: self = .hd
            default: self = .uhd
            }
        }
    }

    func presetName(for bucket: ResolutionBucket) -> String {
        switch bucket {
        case .sd: anime4KPresetSDName
        case .hd: anime4KPresetHDName
        case .uhd: anime4KPresetUHDName
        }
    }

    func anime4KPreset(forVideoHeight height: Int) -> Anime4KPreset {
        guard anime4KEnabled else { return .off }
        let name = presetName(for: ResolutionBucket(videoHeight: height))
        return Anime4KPreset.all.first { $0.name == name } ?? .off
    }
}


extension ChocoPanSettings {
    func isWatched(position: Double, duration: Double) -> Bool {
        guard duration > 0 else { return false }
        return position / duration >= watchedThresholdFraction
    }

    /// Whether to offer resume rather than starting over.
    func shouldResume(from position: Double, duration: Double) -> Bool {
        position >= resumeMinimumSeconds && !isWatched(position: position, duration: duration)
    }
}


enum MPVLogLevel: String, Codable, CaseIterable, Identifiable {
    case none
    case error
    case warn
    case info
    case debug

    var id: String { rawValue }

    /// The string `mpv_request_log_messages` expects.
    var mpvValue: String { self == .none ? "no" : rawValue }

    var title: String {
        switch self {
        case .none: "Off"
        case .error: "Errors"
        case .warn: "Warnings"
        case .info: "Info"
        case .debug: "Debug"
        }
    }
}
