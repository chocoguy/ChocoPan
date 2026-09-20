import Foundation

//so basically
//Takes a folder name like: [Judas] Sousou no Frieren (Frieren Beyond Journey`s End) (Season 01) [BD 1080p][HEVC x265 10bit][Dual-Audio][Eng-Subs] 😕
//Converts it to: Sousou no Frieren Season 1 😊
nonisolated enum FolderTitleCleaner {
    /// Tags that are never part of a title, matched as whole words, case-insensitively.
    private static let noiseTokens: Set<String> = [
        "1080p", "720p", "480p", "2160p", "4k", "8bit", "10bit", "hi10p",
        "bd", "bdrip", "bluray", "blu-ray", "dvd", "dvdrip", "web", "webrip", "web-dl",
        "hdtv", "remux", "uncensored", "dual-audio", "dualaudio", "multi",
        "x264", "x265", "h264", "h265", "hevc", "avc", "aac", "flac", "opus", "ac3", "eac3",
        "repack", "batch", "complete", "dual", "audio",
    ]

    static func searchTitle(from folderName: String) -> String {
        var text = folderName
        text = removeGroups(in: text, open: "[", close: "]") { _ in true }
        text = removeGroups(in: text, open: "(", close: ")") { _ in true }
        text = text.replacingOccurrences(of: "_", with: " ")
        if separatorIsDot(text) {
            text = text.replacingOccurrences(of: ".", with: " ")
        }

        let tokens = stripEpisodeMarkers(
            in: text.split(whereSeparator: { $0 == " " || $0 == "\t" })
        )
        var kept: [String] = []
        var droppedPrevious = false

        for (offset, token) in tokens.enumerated() {
            if isNoise(token) || isBareYear(token) || isVersionTag(token) || isEpisodeRange(token) {
                droppedPrevious = true
                continue
            }

            if droppedPrevious, offset > 0, isStrayNumber(token) || isConnector(token) {
                continue
            }

            if let season = expandedSeasonMarker(token) {
                kept.append(season)
            } else {
                kept.append(String(token))
            }
            droppedPrevious = false
        }

        let cleaned = kept
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " -–—~&+"))
        return cleaned.isEmpty ? folderName : cleaned
    }

    private static func separatorIsDot(_ text: String) -> Bool {
        let dots = text.count(where: { $0 == "." })
        return dots >= 2 && dots > text.count(where: { $0 == " " })
    }
    private static func isNoise(_ token: Substring) -> Bool {
        let lower = token.lowercased()
        if noiseTokens.contains(lower) { return true }

        if let dash = lower.lastIndex(of: "-"), dash != lower.startIndex,
           noiseTokens.contains(String(lower[lower.startIndex..<dash])) {
            return true
        }

        let stem = String(lower.reversed().drop(while: \.isNumber).reversed())
        return stem.count != lower.count && !stem.isEmpty && noiseTokens.contains(stem)
    }

    private static func expandedSeasonMarker(_ token: Substring) -> String? {
        var rest = Substring(token)
        guard rest.first == "S" || rest.first == "s" else { return nil }
        rest = rest.dropFirst()

        let digits = rest.prefix(while: \.isNumber)
        guard (1...2).contains(digits.count), let season = Int(digits) else { return nil }

        let trailing = rest.dropFirst(digits.count)
        if !trailing.isEmpty {
            guard trailing.first == "E" || trailing.first == "e",
                  trailing.dropFirst().allSatisfy(\.isNumber),
                  !trailing.dropFirst().isEmpty else { return nil }
        }

        return "Season \(season)"
    }

    private static func isVersionTag(_ token: Substring) -> Bool {
        guard token.first == "v" || token.first == "V" else { return false }
        let digits = token.dropFirst()
        return !digits.isEmpty && digits.count <= 2 && digits.allSatisfy(\.isNumber)
    }

    private static func isEpisodeRange(_ token: Substring) -> Bool {
        guard let dash = token.firstIndex(of: "-") else { return false }
        let start = token[token.startIndex..<dash]
        let end = token[token.index(after: dash)...]
        return !start.isEmpty && start.count <= 4 && start.allSatisfy(\.isNumber)
            && !end.isEmpty && end.count <= 4 && end.allSatisfy(\.isNumber)
    }

    private static func isStrayNumber(_ token: Substring) -> Bool {
        !token.isEmpty && token.allSatisfy(\.isNumber)
    }

    private static func isConnector(_ token: Substring) -> Bool {
        !token.isEmpty && token.allSatisfy { "&+-–—~".contains($0) }
    }
    private static func stripEpisodeMarkers(in tokens: [Substring]) -> [Substring] {
        var tokens = tokens

        if tokens.count > 2, isStrayNumber(tokens[0]), tokens[0].count <= 3, isConnector(tokens[1]) {
            tokens.removeFirst(2)
        }

        if tokens.count > 2, let last = tokens.last, isStrayNumber(last), last.count <= 3,
           isConnector(tokens[tokens.count - 2]) {
            tokens.removeLast(2)
        }

        return tokens
    }

    private static func isBareYear(_ token: Substring) -> Bool {
        guard token.count == 4, let value = Int(token) else { return false }
        return (1900...2099).contains(value)
    }

    private static func removeGroups(
        in text: String,
        open: Character,
        close: Character,
        shouldRemove: (Substring) -> Bool
    ) -> String {
        var result = ""
        var index = text.startIndex

        while index < text.endIndex {
            guard text[index] == open,
                  let closeIndex = text[index...].firstIndex(of: close) else {
                result.append(text[index])
                index = text.index(after: index)
                continue
            }

            let inner = text[text.index(after: index)..<closeIndex]
            if !shouldRemove(inner) {
                result.append(contentsOf: text[index...closeIndex])
            }
            index = text.index(after: closeIndex)
        }

        return result
    }
}
