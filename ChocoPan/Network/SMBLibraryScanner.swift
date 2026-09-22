import AMSMB2
import Foundation


nonisolated struct ScannedFolder: Sendable, Identifiable {
    let name: String
    let path: String
    let modified: Date?
    var files: [ScannedFile] = []

    var id: String { path }
}


nonisolated struct ScannedFile: Sendable {
    let name: String
    let relativePath: String
    let size: Int64
    let modified: Date
    let episodeNumber: Int
}

nonisolated enum SMBLibraryScanner {
    static let videoExtensions: Set<String> = [
        "mkv", "mp4", "avi", "m4v", "mov", "ts", "m2ts", "webm", "wmv", "flv", "ogm",
    ]

    private static let ignoredDirectories: Set<String> = [
        "@eadir", "#recycle", "#snapshot", ".ds_store", "lost+found", "$recycle.bin",
        "system volume information", "ignore",
    ]

    private static let ignoredFiles: Set<String> = [
        ".ds_store", "thumbs.db", "desktop.ini",
    ]

    private static let inProgressExtensions: Set<String> = [
        "part", "!ut", "downloading", "crdownload", "tmp", "filepart",
    ]

    private static let settleInterval: TimeInterval = 60

    //Full Scan
    static func scanAll(session: SMBSession, rootPath: String) async throws -> [ScannedFolder] {
        let entries = try await session.listDirectory(path: rootPath, recursive: true)
        return assemble(entries: entries, rootPath: rootPath)
    }

    //Increment Scan
    static func scanFolders(session: SMBSession, rootPath: String) async throws -> [ScannedFolder] {
        let entries = try await session.listDirectory(path: rootPath, recursive: false)

        return entries.compactMap { entry -> ScannedFolder? in
            guard entry.isDirectory, let name = entry.name, isUsableDirectory(name) else {
                return nil
            }
            return ScannedFolder(
                name: name,
                path: join(rootPath, name),
                modified: entry.contentModificationDate
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func scanEpisodes(session: SMBSession, folder: ScannedFolder) async throws -> [ScannedFile] {
        let entries = try await session.listDirectory(path: folder.path, recursive: false)
        return files(from: entries, folderPath: folder.path)
    }

    // MARK: - Assembly

    private static func assemble(entries: [[URLResourceKey: Any]], rootPath: String) -> [ScannedFolder] {
        let prefix = normalized(rootPath)

        var folders: [String: ScannedFolder] = [:]
        var pendingFiles: [String: [ScannedFile]] = [:]

        for entry in entries {
            guard let name = entry.name else { continue }
            let full = normalized(entry.path ?? join(rootPath, name))
            guard let relative = strip(prefix: prefix, from: full) else { continue }

            let components = relative.split(separator: "/").map(String.init)
            guard let top = components.first, isUsableDirectory(top) else { continue }

            if entry.isDirectory {
                guard components.count == 1 else { continue }
                folders[top] = ScannedFolder(
                    name: top,
                    path: join(rootPath, top),
                    modified: entry.contentModificationDate
                )
            } else {
                guard components.count == 2,
                      let file = makeFile(entry: entry, name: name, relativePath: full) else {
                    continue
                }
                pendingFiles[top, default: []].append(file)
            }
        }

        return folders.values
            .map { folder in
                var folder = folder
                folder.files = numbered(pendingFiles[folder.name] ?? [])
                return folder
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func files(from entries: [[URLResourceKey: Any]], folderPath: String) -> [ScannedFile] {
        let prefix = normalized(folderPath)
        let collected = entries.compactMap { entry -> ScannedFile? in
            guard !entry.isDirectory, let name = entry.name else { return nil }
            let full = normalized(entry.path ?? join(folderPath, name))
            guard let relative = strip(prefix: prefix, from: full),
                  !relative.contains("/") else { return nil }
            return makeFile(entry: entry, name: name, relativePath: full)
        }
        return numbered(collected)
    }

    private static func makeFile(
        entry: [URLResourceKey: Any],
        name: String,
        relativePath: String
    ) -> ScannedFile? {
        guard isUsableFile(name) else { return nil }

        let modified = entry.contentModificationDate ?? .distantPast
        guard Date().timeIntervalSince(modified) > settleInterval else { return nil }

        return ScannedFile(
            name: name,
            relativePath: relativePath,
            size: entry.fileSize ?? 0,
            modified: modified,
            episodeNumber: 0
        )
    }

    private static func numbered(_ files: [ScannedFile]) -> [ScannedFile] {
        let sorted = files.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let parsed = sorted.map { parseEpisodeNumber(from: $0.name) }

        var taken = Set<Int>()
        var numbers = [Int?](repeating: nil, count: sorted.count)

        for (index, value) in parsed.enumerated() {
            guard let value, !taken.contains(value) else { continue }
            taken.insert(value)
            numbers[index] = value
        }

        var next = (taken.max() ?? 0) + 1
        for index in numbers.indices where numbers[index] == nil {
            while taken.contains(next) { next += 1 }
            taken.insert(next)
            numbers[index] = next
        }

        return zip(sorted, numbers).map { file, number in
            ScannedFile(
                name: file.name,
                relativePath: file.relativePath,
                size: file.size,
                modified: file.modified,
                episodeNumber: number ?? 0
            )
        }
    }

    private static func isUsableDirectory(_ name: String) -> Bool {
        !name.hasPrefix(".") && !ignoredDirectories.contains(name.lowercased())
    }

    private static func isUsableFile(_ name: String) -> Bool {
        guard !name.hasPrefix("."), !ignoredFiles.contains(name.lowercased()) else { return false }

        let ext = (name as NSString).pathExtension.lowercased()
        guard !inProgressExtensions.contains(ext) else { return false }
        return videoExtensions.contains(ext)
    }

    //`S01E07`, `Ep07`, `- 07`, `[07]`, and finally a bare `07`. MAY NEED ADJUSTING
    static func parseEpisodeNumber(from fileName: String) -> Int? {
        let stem = (fileName as NSString).deletingPathExtension

        let explicit = [
            #"[Ss](\d{1,2})[Ee](\d{1,3})"#,
            #"(?:^|[\s._-])[Ee][Pp]?[\s._-]?(\d{1,3})(?:[\s._-]|$)"#,
            #"[\s._]-[\s._](\d{1,3})(?:[\s._v]|$)"#,
            #"[\[\(](\d{1,3})[\]\)]"#,
        ]
        for pattern in explicit {
            if let value = firstNumber(in: stem, pattern: pattern) { return value }
        }

        return firstNumber(
            in: withoutMetadata(stem),
            pattern: #"(?:^|[\s._])(\d{1,3})(?:[\s._]|$)"#
        )
    }

    private static func withoutMetadata(_ stem: String) -> String {
        stem.replacingOccurrences(
            of: #"[\[\(][^\]\)]*[\]\)]"#,
            with: " ",
            options: .regularExpression
        )
    }

    private static func firstNumber(in text: String, pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: text,
                  range: NSRange(text.startIndex..., in: text)
              ) else { return nil }
        let group = match.numberOfRanges - 1
        guard let range = Range(match.range(at: group), in: text) else { return nil }
        return Int(text[range])
    }


    private static func normalized(_ path: String) -> String {
        path
            .replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func join(_ base: String, _ component: String) -> String {
        let base = normalized(base)
        return base.isEmpty ? component : "\(base)/\(component)"
    }

    private static func strip(prefix: String, from path: String) -> String? {
        guard !prefix.isEmpty else { return path.isEmpty ? nil : path }
        guard path.hasPrefix(prefix) else { return nil }
        let remainder = normalized(String(path.dropFirst(prefix.count)))
        return remainder.isEmpty ? nil : remainder
    }
}
