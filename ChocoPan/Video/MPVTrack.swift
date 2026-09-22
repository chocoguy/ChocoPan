import Foundation

nonisolated struct MPVTrack: Decodable, Sendable, Hashable, Identifiable {
    let id: Int
    /// "audio", "sub" or "video".
    let type: String
    let title: String?
    let lang: String?
    let codec: String?
    let external: Bool?
    private let selected: Bool?

    var isSelected: Bool { selected == true }

    var menuLabel: String {
        if let title, !title.isEmpty { return title }
        if let lang, !lang.isEmpty { return "\(id) - \(lang.uppercased())" }
        if let codec, !codec.isEmpty { return "\(id) - \(codec)" }
        return "Track \(id)"
    }

    var label: String {
        let detail: String? = (title ?? codec).map { text in
            text.count <= 22 ? text : String(text.prefix(21)) + "…"
        }
        let parts = [lang?.uppercased(), detail].compactMap { $0 }
        return parts.isEmpty ? "Track \(id)" : parts.joined(separator: " · ")
    }
}
