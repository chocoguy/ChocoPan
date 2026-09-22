import AMSMB2
import Foundation

enum SMBSessionError: Error, CustomStringConvertible {
    case managerCreationFailed
    case missingFileSize(String)
    case unknownToken(Int)
    case noShareSelected
    case missingHost(String)
    case missingCredential(String)

    var description: String {
        switch self {
        case .managerCreationFailed: "could not create SMB client"
        case .missingFileSize(let path): "no file size for \(path)"
        case .unknownToken(let token): "unknown stream token \(token)"
        case .noShareSelected: "no share selected"
        case .missingHost(let name): "\(name) has no server address"
        case .missingCredential(let name): "no saved password for \(name)"
        }
    }
}

nonisolated final class SMBSession: @unchecked Sendable {
    struct Entry {
        let path: String
        let size: Int64
    }
    static let browseTimeout: TimeInterval = 15
    static let streamTimeout: TimeInterval = 30

    private let client: SMB2Manager
    private let lock = NSLock()
    private var entries: [Int: Entry] = [:]
    private var nextToken = 1
    private var connectedShare: String?

    let host: String

    init(host: String, credential: URLCredential, timeout: TimeInterval = SMBSession.browseTimeout) throws {
        guard let url = URL(string: "smb://\(host)"),
              let client = SMB2Manager(url: url, credential: credential) else {
            throw SMBSessionError.managerCreationFailed
        }
        client.timeout = timeout
        self.client = client
        self.host = host
    }

    convenience init(
        host: String,
        username: String,
        password: String,
        timeout: TimeInterval = SMBSession.browseTimeout
    ) throws {
        try self.init(
            host: host,
            credential: URLCredential(user: username, password: password, persistence: .forSession),
            timeout: timeout
        )
    }

    func listShares() async throws -> [String] {
        try await client.listShares().map(\.name)
    }

    func connect(share: String) async throws {
        try await client.connectShare(name: share)
        lock.withLock { connectedShare = share }
    }

    func ensureConnected() async throws {
        guard let share = lock.withLock({ connectedShare }) else {
            throw SMBSessionError.noShareSelected
        }
        try await client.connectShare(name: share)
    }

    func disconnect() async {
        let wasConnected = lock.withLock {
            let was = connectedShare != nil
            connectedShare = nil
            return was
        }
        guard wasConnected else { return }
        try? await client.disconnectShare(gracefully: true)
    }

    func listDirectory(path: String, recursive: Bool = false) async throws -> [[URLResourceKey: Any]] {
        try await ensureConnected()
        return try await client.contentsOfDirectory(atPath: path, recursive: recursive)
    }


    func fileSize(path: String) async throws -> Int64 {
        try await ensureConnected()

        let attributes = try await client.attributesOfItem(atPath: path)
        let raw = attributes[.fileSizeKey]
        if let number = raw as? NSNumber {
            return number.int64Value
        }
        if let value = raw as? Int {
            return Int64(value)
        }
        throw SMBSessionError.missingFileSize(path)
    }

    func prepare(path: String) async throws -> Int {
        let size = try await fileSize(path: path)

        return lock.withLock {
            let token = nextToken
            nextToken += 1
            entries[token] = Entry(path: path, size: size)
            return token
        }
    }

    func entry(for token: Int) -> Entry? {
        lock.withLock { entries[token] }
    }

    func readSync(
        path: String,
        offset: Int64,
        length: Int,
        shouldContinue: () -> Bool = { true }
    ) -> Data? {
        guard length > 0 else { return Data() }

        let backoff: [UInt32] = [0, 500_000, 1_500_000]  // microseconds before each attempt

        for (attempt, delay) in backoff.enumerated() {
            guard shouldContinue() else { return nil }
            if delay > 0 {
                usleep(delay)
                guard shouldContinue() else { return nil }
                reconnectSync()
            }

            if let data = attemptRead(path: path, offset: offset, length: length), !data.isEmpty {
                return data
            }

            if attempt == backoff.count - 1 {
                print("[SMB] read failed after \(backoff.count) attempts: \(path) @\(offset)")
            }
        }

        return nil
    }

    private func attemptRead(path: String, offset: Int64, length: Int) -> Data? {
        let semaphore = DispatchSemaphore(value: 0)
        let box = ReadBox()

        client.contents(
            atPath: path,
            range: offset..<(offset + Int64(length)),
            progress: nil
        ) { result in
            if case .success(let data) = result {
                box.data = data
            }
            semaphore.signal()
        }

        semaphore.wait()
        return box.data
    }

    private func reconnectSync() {
        guard let share = lock.withLock({ connectedShare }) else { return }

        let semaphore = DispatchSemaphore(value: 0)
        client.connectShare(name: share) { _ in semaphore.signal() }
        semaphore.wait()
    }
}

nonisolated private final class ReadBox: @unchecked Sendable {
    var data: Data?
}


extension SMBSession {
    @MainActor
    static func make(
        for source: LibrarySource,
        timeout: TimeInterval = SMBSession.streamTimeout
    ) throws -> SMBSession {
        guard let host = source.host, !host.isEmpty else {
            throw SMBSessionError.missingHost(source.name)
        }
        guard let password = SMBCredentialStore.password(for: source.keychainAccount) else {
            throw SMBSessionError.missingCredential(source.name)
        }
        return try SMBSession(
            host: host,
            username: source.username,
            password: password,
            timeout: timeout
        )
    }
}
