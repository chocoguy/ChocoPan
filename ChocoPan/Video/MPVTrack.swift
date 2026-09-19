import Foundation

/// One entry from mpv's `track-list`.
///
/// Decoded from JSON rather than walked as an `mpv_node`: asking for a node property in string form
/// gives back JSON, which is far less C interop for the same result.
struct MPVTrack: Decodable, Sendable, Hashable, Identifiable {
    let id: Int
    /// "audio", "sub" or "video".
    let type: String
    let title: String?
    let lang: String?
    let codec: String?
    let external: Bool?
    private let selected: Bool?

    var isSelected: Bool { selected == true }

    /// Something short enough for a button face. Release-group titles run long
    /// ("[Judas] JAP Stereo (Opus 112Kbps)"), so the detail half gets truncated.
    var label: String {
        let detail: String? = (title ?? codec).map { text in
            text.count <= 22 ? text : String(text.prefix(21)) + "…"
        }
        let parts = [lang?.uppercased(), detail].compactMap { $0 }
        return parts.isEmpty ? "Track \(id)" : parts.joined(separator: " · ")
    }
}
