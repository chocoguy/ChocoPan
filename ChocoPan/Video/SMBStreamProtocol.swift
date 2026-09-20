import Foundation
import Libmpv

private final class SMBStreamCookie: @unchecked Sendable {
    static let chunkSize = 4 << 20  // 4 MiB

    private let session: SMBSession
    private let path: String
    let size: Int64

    private let lock = NSLock()
    private var offset: Int64 = 0
    private var buffer = Data()
    private var bufferStart: Int64 = 0
    private var isCancelled = false

    init(session: SMBSession, path: String, size: Int64) {
        self.session = session
        self.path = path
        self.size = size
    }

    func cancel() {
        lock.withLock { isCancelled = true }
    }

    private var cancelled: Bool {
        lock.withLock { isCancelled }
    }

    /// Returns bytes read, 0 at EOF, or -1 on error — mpv's contract for `read_fn`.
    func read(into destination: UnsafeMutablePointer<CChar>, maxBytes: Int) -> Int64 {
        lock.lock()
        if isCancelled {
            lock.unlock()
            return -1
        }
        guard offset < size, maxBytes > 0 else {
            lock.unlock()
            return 0
        }

        let needsFetch = buffer.isEmpty
            || offset < bufferStart
            || offset >= bufferStart + Int64(buffer.count)
        let fetchOffset = offset
        let fetchLength = Int(min(Int64(max(maxBytes, Self.chunkSize)), size - offset))
        lock.unlock()

        if needsFetch {
            // Network IO stays outside the lock; cancel must remain responsive during a fetch.
            guard let data = session.readSync(
                path: path,
                offset: fetchOffset,
                length: fetchLength,
                shouldContinue: { [weak self] in self?.cancelled == false }
            ), !data.isEmpty else {
                return -1
            }
            lock.withLock {
                buffer = data
                bufferStart = fetchOffset
            }
        }

        return lock.withLock {
            if isCancelled { return -1 }
            let start = Int(offset - bufferStart)
            guard start >= 0, start < buffer.count else { return -1 }

            let available = buffer.count - start
            let count = min(maxBytes, available, Int(size - offset))
            guard count > 0 else { return 0 }

            buffer.withUnsafeBytes { raw in
                let source = raw.baseAddress!.advanced(by: start)
                destination.withMemoryRebound(to: UInt8.self, capacity: count) { out in
                    out.update(from: source.assumingMemoryBound(to: UInt8.self), count: count)
                }
            }
            offset += Int64(count)
            return Int64(count)
        }
    }

    /// Returns the new position, or -1. The buffer is kept: short backward seeks often land inside it.
    func seek(to newOffset: Int64) -> Int64 {
        lock.withLock {
            guard !isCancelled, newOffset >= 0, newOffset <= size else { return -1 }
            offset = newOffset
            return newOffset
        }
    }
}

// MARK: - C callbacks
//
// All of these must stay non-capturing: they are passed as C function pointers. They also must never
// call back into libmpv, which the stream_cb header warns will deadlock.

private let smbOpenCallback: mpv_stream_cb_open_ro_fn = { userData, uri, info in
    guard let userData, let uri, let info else { return MPV_ERROR_LOADING_FAILED.rawValue }

    let session = Unmanaged<SMBSession>.fromOpaque(userData).takeUnretainedValue()
    let prefix = SMBStreamProtocol.scheme + "://"
    let text = String(cString: uri)

    guard text.hasPrefix(prefix),
          let token = Int(text.dropFirst(prefix.count)),
          let entry = session.entry(for: token) else {
        return MPV_ERROR_LOADING_FAILED.rawValue
    }

    let cookie = SMBStreamCookie(session: session, path: entry.path, size: entry.size)
    info.pointee.cookie = Unmanaged.passRetained(cookie).toOpaque()
    info.pointee.read_fn = { cookie, buffer, nbytes in
        guard let cookie, let buffer else { return -1 }
        return Unmanaged<SMBStreamCookie>.fromOpaque(cookie).takeUnretainedValue()
            .read(into: buffer, maxBytes: Int(nbytes))
    }
    info.pointee.seek_fn = { cookie, offset in
        guard let cookie else { return -1 }
        return Unmanaged<SMBStreamCookie>.fromOpaque(cookie).takeUnretainedValue().seek(to: offset)
    }
    info.pointee.size_fn = { cookie in
        guard let cookie else { return -1 }
        return Unmanaged<SMBStreamCookie>.fromOpaque(cookie).takeUnretainedValue().size
    }
    info.pointee.close_fn = { cookie in
        guard let cookie else { return }
        Unmanaged<SMBStreamCookie>.fromOpaque(cookie).release()
    }
    info.pointee.cancel_fn = { cookie in
        guard let cookie else { return }
        Unmanaged<SMBStreamCookie>.fromOpaque(cookie).takeUnretainedValue().cancel()
    }
    return 0
}

/// Registers an SMB-backed protocol with an mpv instance.
enum SMBStreamProtocol {
    static let scheme = "chocosmb"

    /// Files are addressed by token rather than by path. The paths contain spaces, brackets and
    /// parentheses, and mpv's escaping contract for custom-protocol URIs is unclear — a token has no
    /// escaping question to get wrong.
    static func url(forToken token: Int) -> URL {
        URL(string: "\(scheme)://\(token)")!
    }

    /// Call between `mpv_create()` and `mpv_initialize()`.
    ///
    /// Returns a retained pointer to `session` that the caller must release *after*
    /// `mpv_terminate_destroy()` returns — protocols cannot be unregistered from a live core.
    static func register(on handle: OpaquePointer, session: SMBSession) -> UnsafeMutableRawPointer {
        let userData = Unmanaged.passRetained(session).toOpaque()
        mpv_stream_cb_add_ro(handle, scheme, userData, smbOpenCallback)
        return userData
    }
}
