import Foundation
import Network


nonisolated enum NetworkReachability {
    static let smbPort: NWEndpoint.Port = 445

    static func canReach(
        host: String,
        port: NWEndpoint.Port = smbPort,
        timeout: TimeInterval = 3
    ) async -> Bool {
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: port,
            using: .tcp
        )

        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    let resumed = ResumeGuard()

                    connection.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            if resumed.claim() { continuation.resume(returning: true) }
                        case .failed, .cancelled:
                            if resumed.claim() { continuation.resume(returning: false) }
                        default:
                            break
                        }
                    }
                    connection.start(queue: .global(qos: .userInitiated))
                }
            }

            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
                return false
            }

            let result = await group.next() ?? false
            group.cancelAll()
            connection.cancel()
            return result
        }
    }
}


nonisolated private final class ResumeGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false

    func claim() -> Bool {
        lock.withLock {
            guard !used else { return false }
            used = true
            return true
        }
    }
}
