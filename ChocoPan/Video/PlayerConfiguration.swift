import Foundation

nonisolated struct MPVOption: Sendable, Hashable {
    let name: String
    let value: String
}

nonisolated struct PlayerConfiguration: Sendable {
    var hardwareDecoding = true
    var logLevel: String
    var playbackSpeed: Double = 1
    var matchesContentFrameRate = false
    var extraOptions: [MPVOption] = []

    init(
        hardwareDecoding: Bool = true,
        logLevel: String = PlayerConfiguration.developmentLogLevel,
        playbackSpeed: Double = 1,
        matchesContentFrameRate: Bool = false,
        extraOptions: [MPVOption] = []
    ) {
        self.hardwareDecoding = hardwareDecoding
        self.logLevel = logLevel
        self.playbackSpeed = playbackSpeed
        self.matchesContentFrameRate = matchesContentFrameRate
        self.extraOptions = extraOptions
    }

    static var developmentLogLevel: String {
#if DEBUG
        "debug"
#else
        "no"
#endif
    }

    static let standard = PlayerConfiguration()
}

extension PlayerConfiguration {
    @MainActor
    init(settings: ChocoPanSettings) {
        self.init(
            hardwareDecoding: settings.hardwareDecodingEnabled,
            logLevel: settings.mpvLogLevel.mpvValue,
            playbackSpeed: settings.defaultPlaybackSpeed,
            matchesContentFrameRate: settings.matchContentFrameRate,
            extraOptions: Self.parseOptions(settings.extraMpvOptions)
        )
    }

    static func parseOptions(_ text: String) -> [MPVOption] {
        text.split(whereSeparator: \.isNewline).compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { return nil }

            guard let split = line.firstIndex(of: "=") else {
                print("[mpv] ignoring option without '=': \(line)")
                return nil
            }

            let name = line[..<split].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: split)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return nil }
            return MPVOption(
                name: String(name.drop(while: { $0 == "-" })),
                value: value
            )
        }
    }
}
