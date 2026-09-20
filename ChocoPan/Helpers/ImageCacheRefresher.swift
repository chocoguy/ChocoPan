import Foundation
import Observation

@MainActor
@Observable
final class ImageCacheRefresher {
    enum Phase: Equatable {
        case idle
        case running(completed: Int, total: Int)
        case finished(String)
    }

    private(set) var phase: Phase = .idle

    /// How many posters to pull at once — enough to hide the latency, few enough to stay polite.
    private static let batchSize = 4

    var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    func rebuild(posterURLs: [URL]) async {
        guard !isRunning else { return }

        phase = .running(completed: 0, total: posterURLs.count)
        await ImageCacher.shared.clear()

        guard !posterURLs.isEmpty else {
            phase = .finished("Cache cleared. No posters to rebuild.")
            return
        }

        var completed = 0
        var failed = 0
        var index = 0

        while index < posterURLs.count {
            let batch = Array(posterURLs[index..<min(index + Self.batchSize, posterURLs.count)])

            failed += await withTaskGroup(of: Bool.self) { group -> Int in
                for url in batch {
                    group.addTask { await Self.warm(url) }
                }
                var failures = 0
                for await succeeded in group where !succeeded {
                    failures += 1
                }
                return failures
            }

            index += batch.count
            completed += batch.count
            phase = .running(completed: completed, total: posterURLs.count)
        }

        let rebuilt = completed - failed
        phase = .finished(
            failed == 0
                ? "Rebuilt \(rebuilt) poster\(rebuilt == 1 ? "" : "s")."
                : "Rebuilt \(rebuilt) of \(completed) posters · \(failed) failed."
        )
    }

    private nonisolated static func warm(_ url: URL) async -> Bool {
        do {
            _ = try await ImageCacher.shared.poster(at: url)
            return true
        } catch {
            print("ImageCacher: poster refresh failed for \(url.absoluteString): \(error)")
            return false
        }
    }
}
