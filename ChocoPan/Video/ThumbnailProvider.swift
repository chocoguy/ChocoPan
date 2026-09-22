import CoreGraphics
import Foundation

nonisolated struct ThumbnailSource: Sendable, Hashable {
    let id: UUID
    let host: String
    let share: String
    let username: String
    let keychainAccount: String

    /// `nil` when the source has no server address — nothing to connect to.
    @MainActor
    init?(_ source: LibrarySource) {
        guard let host = source.host, !host.isEmpty else { return nil }
        self.id = source.librarySourceId
        self.host = host
        self.share = source.share
        self.username = source.username
        self.keychainAccount = source.keychainAccount
    }
}

actor ThumbnailProvider {
    static let shared = ThumbnailProvider()
    private static let idleTimeout: Duration = .seconds(60)
    private var connection: Task<SMBSession, Error>?
    private var connectedSource: ThumbnailSource?
    private var idleTask: Task<Void, Never>?

    func thumbnail(source: ThumbnailSource, path: String, maxWidth: Int) async throws -> CGImage {
        let session = try await session(for: source)
        scheduleIdleDisconnect()

        let size = try await session.fileSize(path: path)
        let thumbnail = try await VideoThumbnailer.thumbnail(
            session: session,
            path: path,
            size: size,
            maxWidth: maxWidth
        )
        return thumbnail.image
    }

    private func session(for source: ThumbnailSource) async throws -> SMBSession {
        if connectedSource == source, let connection {
            do {
                return try await connection.value
            } catch {
                if connectedSource == source { self.connection = nil; connectedSource = nil }
                throw error
            }
        }

        let previous = connection
        let task = Task<SMBSession, Error> {
            if let previous, let stale = try? await previous.value {
                await stale.disconnect()
            }
            guard let password = SMBCredentialStore.password(for: source.keychainAccount) else {
                throw SMBSessionError.missingCredential(source.share)
            }
            let session = try SMBSession(
                host: source.host,
                username: source.username,
                password: password,
                timeout: SMBSession.streamTimeout
            )
            try await session.connect(share: source.share)
            return session
        }

        connection = task
        connectedSource = source
        return try await task.value
    }

    private func scheduleIdleDisconnect() {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: Self.idleTimeout)
            guard !Task.isCancelled else { return }
            await self?.disconnect()
        }
    }

    func disconnect() async {
        idleTask?.cancel()
        idleTask = nil

        let task = connection
        connection = nil
        connectedSource = nil
        if let task, let session = try? await task.value {
            await session.disconnect()
        }
    }
}
