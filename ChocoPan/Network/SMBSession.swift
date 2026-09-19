import AMSMB2
import Foundation

enum SMBSessionError: Error, CustomStringConvertible {
    case managerCreationFailed
    case missingFileSize(String)
    case unknownToken(Int)

    var description: String {
        switch self {
        case .managerCreationFailed: "could not create SMB client"
        case .missingFileSize(let path): "no file size for \(path)"
        case .unknownToken(let token): "unknown stream token \(token)"
        }
    }
}

final class SMBSession: @unchecked Sendable {
    struct Entry {
        let path: String
        let size: Int64
    }

    private let client: SMB2Manager
    private let lock = NSLock()
    private var entries: [Int: Entry] = [:]
    private var nextToken = 1
    private var isConnected = false

    /// Shares seen during `connect()`. Diagnostic only.
    private(set) var discoveredShares: [String] = []

    init() throws {
        guard let client = SMB2Manager(
            url: SMBTestConfig.serverURL,
            credential: SMBTestConfig.credential
        ) else {
            throw SMBSessionError.managerCreationFailed
        }
        self.client = client
    }

    func connect() async throws {
        //load-bearing 😭
        discoveredShares = (try? await client.listShares().map(\.name)) ?? []
        print("[SMB] shares: \(discoveredShares)")

        print("[SMB] connecting to share \(SMBTestConfig.share)")
        try await client.connectShare(name: SMBTestConfig.share)
        lock.withLock { isConnected = true }
        print("[SMB] connected")
    }

    func disconnect() async {
        let wasConnected = lock.withLock {
            let was = isConnected
            isConnected = false
            return was
        }
        guard wasConnected else { return }
        try? await client.disconnectShare(gracefully: true)
    }


    
    
    
    func prepare(path: String) async throws -> Int {
        print("[SMB] stat \(path)")
        let attributes = try await client.attributesOfItem(atPath: path)
        let raw = attributes[.fileSizeKey]
        let size: Int64
        if let number = raw as? NSNumber {
            size = number.int64Value
        } else if let value = raw as? Int {
            size = Int64(value)
        } else {
            throw SMBSessionError.missingFileSize(path)
        }

        print("[SMB] \(path) is \(size) bytes")
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


    func readSync(path: String, offset: Int64, length: Int) -> Data? {
        guard length > 0 else { return Data() }

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
}

nonisolated private final class ReadBox: @unchecked Sendable {
    var data: Data?
}
