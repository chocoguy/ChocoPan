import Foundation
import SwiftData
import SwiftUI

@MainActor
@Observable
final class LibrarySetupCoordinator {
    enum Step: Equatable {
        case instructions
        case credentials
        case selectShare
        case scanning
        case summary
    }

    enum ScanPhase: Equatable {
        case connecting
        case listing
        case savingFolders(count: Int)
        case matching(done: Int, total: Int)
        case finishing

        var message: String {
            switch self {
            case .connecting: "Connecting…"
            case .listing: "Looking through your share…"
            case .savingFolders(let count): "Found \(count) show\(count == 1 ? "" : "s")…"
            case .matching(let done, let total): "Matching \(done) of \(total) shows…"
            case .finishing: "Wrapping up…"
            }
        }

        var fraction: Double? {
            guard case .matching(let done, let total) = self, total > 0 else { return nil }
            return Double(done) / Double(total)
        }
    }

    struct Summary: Equatable {
        var matched = 0
        var needsReview = 0
        var notFound = 0
        var retrying = 0
        var unresolvedFolders: [String] = []
        var episodeCount = 0

        var hasUnresolved: Bool { needsReview + notFound > 0 }
    }


    var host = ""
    var username = ""
    var password = ""


    private(set) var step: Step = .instructions
    private(set) var scanPhase: ScanPhase = .connecting
    private(set) var availableShares: [String] = []
    private(set) var summary = Summary()
    private(set) var isTestingConnection = false

    var selectedShare = ""
    var error: SetupError?

    private var scanTask: Task<Void, Never>?
    private var session: SMBSession?
    private var createdSource: LibrarySource?
    private var pendingKeychainAccount: String?

    var canSubmitCredentials: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty
            && !username.trimmingCharacters(in: .whitespaces).isEmpty
            && !isTestingConnection
    }



    func advance(to step: Step) {
        self.step = step
    }

    func back() {
        switch step {
        case .instructions, .scanning, .summary: break
        case .credentials: step = .instructions
        case .selectShare: step = .credentials
        }
    }

    func testConnection() async {
        guard !isTestingConnection else { return }
        isTestingConnection = true
        error = nil
        defer { isTestingConnection = false }

        let trimmedHost = host.trimmingCharacters(in: .whitespaces)

        guard await NetworkReachability.canReach(host: trimmedHost) else {
            error = .unreachable(trimmedHost)
            return
        }

        do {
            let session = try SMBSession(
                host: trimmedHost,
                username: username.trimmingCharacters(in: .whitespaces),
                password: password
            )
            let shares = try await session.listShares()

            self.session = session
            availableShares = shares.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            selectedShare = availableShares.first ?? ""
            step = .selectShare
        } catch {
            self.error = SetupError.from(error, host: trimmedHost, share: nil)
        }
    }

    func startScan(context: ModelContext) {
        guard scanTask == nil else { return }

        step = .scanning
        scanPhase = .connecting
        error = nil
        summary = Summary()

        scanTask = Task { [weak self] in
            await self?.runScan(context: context)
            self?.scanTask = nil
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        let session = self.session
        self.session = nil
        Task.detached { await session?.disconnect() }
    }

    private func runScan(context: ModelContext) async {
        let trimmedHost = host.trimmingCharacters(in: .whitespaces)
        let share = selectedShare

        do {
            let session = try activeSession(host: trimmedHost)
            try await session.connect(share: share)
            try Task.checkCancellation()

            scanPhase = .listing
            let folders = try await SMBLibraryScanner.scanAll(session: session, rootPath: "")
            try Task.checkCancellation()

            guard !folders.isEmpty else {
                throw SetupError.noFoldersFound
            }

            scanPhase = .savingFolders(count: folders.count)
            let source = try persistSource(host: trimmedHost, share: share, context: context)
            let records = persistFolders(folders, source: source, context: context)
            try context.save()
            try Task.checkCancellation()

            await resolveMetadata(for: records, context: context)

            scanPhase = .finishing
            source.lastScanDate = .now
            ChocoPanSettings.shared(in: context).lastScanDate = .now
            try context.save()

            summary.episodeCount = folders.reduce(0) { $0 + $1.files.count }
            createdSource = nil
            pendingKeychainAccount = nil
            step = .summary
        } catch is CancellationError {
            rollback(context: context)
        } catch {
            self.error = SetupError.from(error, host: trimmedHost, share: share)
            rollback(context: context)
            step = .selectShare
        }
    }

    private func activeSession(host: String) throws -> SMBSession {
        if let session { return session }
        let session = try SMBSession(
            host: host,
            username: username.trimmingCharacters(in: .whitespaces),
            password: password
        )
        self.session = session
        return session
    }


    private func persistSource(host: String, share: String, context: ModelContext) throws -> LibrarySource {
        let account = UUID().uuidString
        try SMBCredentialStore.save(password: password, account: account)

        let source = LibrarySource(
            name: share,
            host: host,
            share: share,
            username: username.trimmingCharacters(in: .whitespaces),
            keychainAccount: account
        )
        context.insert(source)
        createdSource = source
        pendingKeychainAccount = account
        return source
    }

    private func persistFolders(
        _ folders: [ScannedFolder],
        source: LibrarySource,
        context: ModelContext
    ) -> [ScannedFolder: Anime] {
        var records: [ScannedFolder: Anime] = [:]

        for (index, folder) in folders.enumerated() {
            let anime = Anime.unresolved(
                folderPath: folder.path,
                folderName: folder.name,
                number: index + 1,
                state: .pending,
                folderModifiedDate: folder.modified,
                episodeCount: folder.files.count,
                source: source
            )
            context.insert(anime)

            for file in folder.files {
                let episode = AnimeEpisode(
                    fileName: file.name,
                    relativeFilePath: file.relativePath,
                    fileSize: file.size,
                    fileModified: file.modified,
                    episodeNumber: file.episodeNumber,
                    anime: anime
                )
                context.insert(episode)
            }

            records[folder] = anime
        }

        return records
    }

    private func rollback(context: ModelContext) {
        if let createdSource {
            context.delete(createdSource)
            self.createdSource = nil
            try? context.save()
        } else {
            context.rollback()
        }

        if let account = pendingKeychainAccount {
            SMBCredentialStore.delete(account: account)
            pendingKeychainAccount = nil
        }

        cancelScan()
    }


    private func resolveMetadata(for records: [ScannedFolder: Anime], context: ModelContext) async {
        let ordered = records.keys.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let total = ordered.count
        var done = 0
        var unresolvedCounter = 0

        scanPhase = .matching(done: 0, total: total)

        for chunk in ordered.chunked(into: AniTrakApiController.batchLimit) {
            if Task.isCancelled { return }

            let titles = chunk.map { FolderTitleCleaner.searchTitle(from: $0.name) }

            let response: BatchAnimeSearchResponse
            do {
                response = try await AniTrakApiController.shared.searchBatch(titles: titles)
            } catch {
                for folder in chunk {
                    guard let anime = records[folder] else { continue }
                    unresolvedCounter += 1
                    anime.markUnresolved(number: unresolvedCounter, state: .pending)
                    summary.retrying += 1
                }
                done += chunk.count
                scanPhase = .matching(done: done, total: total)
                continue
            }

            for (folder, result) in zip(chunk, response.results) {
                guard let anime = records[folder] else { continue }
                apply(result, to: anime, unresolvedCounter: &unresolvedCounter)
            }

            done += chunk.count
            scanPhase = .matching(done: done, total: total)
        }

        try? context.save()
    }

    private func apply(
        _ result: BatchAnimeSearchResult,
        to anime: Anime,
        unresolvedCounter: inout Int
    ) {
        if let payload = result.anime, result.confidence.isTrustworthy {
            AnimeImporter.apply(payload, to: anime)
            summary.matched += 1
            return
        }

        unresolvedCounter += 1

        switch result.source {
        case .unavailable:
            anime.markUnresolved(number: unresolvedCounter, state: .pending)
            summary.retrying += 1

        case .notFound:
            anime.markUnresolved(number: unresolvedCounter, state: .notFound)
            summary.notFound += 1
            summary.unresolvedFolders.append(anime.folderName)

        default:
            anime.markUnresolved(number: unresolvedCounter, state: .needsReview)
            summary.needsReview += 1
            summary.unresolvedFolders.append(anime.folderName)
        }
    }

    static func retryPending(context: ModelContext) async {
        guard let all = try? context.fetch(FetchDescriptor<Anime>()) else { return }
        let pending = all.filter { $0.metadataState == .pending }
        guard !pending.isEmpty else { return }

        for chunk in pending.chunked(into: AniTrakApiController.batchLimit) {
            let titles = chunk.map { FolderTitleCleaner.searchTitle(from: $0.folderName) }
            guard let response = try? await AniTrakApiController.shared.searchBatch(titles: titles) else {
                return
            }

            for (anime, result) in zip(chunk, response.results) {
                if let payload = result.anime, result.confidence.isTrustworthy {
                    AnimeImporter.apply(payload, to: anime)
                    continue
                }

                switch result.source {
                case .unavailable: continue
                case .notFound: anime.metadataState = .notFound
                default: anime.metadataState = .needsReview
                }
            }

            try? context.save()


            if !response.malBudgetExhausted { continue }
            try? await Task.sleep(for: .seconds(5))
        }
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

extension ScannedFolder: Hashable {
    static func == (lhs: ScannedFolder, rhs: ScannedFolder) -> Bool { lhs.path == rhs.path }
    func hash(into hasher: inout Hasher) { hasher.combine(path) }
}
