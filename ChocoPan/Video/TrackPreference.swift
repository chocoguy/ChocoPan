import Foundation

nonisolated enum TrackPreference: Equatable {
    case off
    case named(lang: String?, title: String?)
    enum Resolution: Equatable {
        case select(MPVTrack)
        case turnOff
        case leaveAlone
    }

    init(track: MPVTrack?) {
        guard let track else {
            self = .off
            return
        }
        self = .named(lang: track.lang, title: track.title)
    }

    init?(descriptor: String?) {
        guard let descriptor else { return nil }
        guard !descriptor.isEmpty else {
            self = .off
            return
        }
        guard let split = descriptor.firstIndex(of: "|") else {
            self = .named(lang: descriptor, title: nil)
            return
        }
        let lang = String(descriptor[..<split])
        let title = String(descriptor[descriptor.index(after: split)...])
        self = .named(lang: lang.isEmpty ? nil : lang, title: title.isEmpty ? nil : title)
    }

    var descriptor: String {
        switch self {
        case .off: ""
        case .named(let lang, let title): "\(lang ?? "")|\(title ?? "")"
        }
    }

    func resolve(in tracks: [MPVTrack]) -> Resolution {
        guard case .named(let lang, let title) = self else { return .turnOff }

        let sameLang = { (track: MPVTrack) in
            lang != nil && track.lang?.caseInsensitiveCompare(lang!) == .orderedSame
        }
        let sameTitle = { (track: MPVTrack) in
            title != nil && track.title?.caseInsensitiveCompare(title!) == .orderedSame
        }

        let match = tracks.first { sameLang($0) && sameTitle($0) }
            ?? tracks.first(where: sameLang)
            ?? tracks.first(where: sameTitle)

        return match.map(Resolution.select) ?? .leaveAlone
    }
}
