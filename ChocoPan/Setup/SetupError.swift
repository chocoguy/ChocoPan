import Foundation

nonisolated enum SetupError: Error, CustomStringConvertible, Equatable {
    case unreachable(String)
    case authenticationFailed
    case shareUnavailable(String)
    case timedOut
    case noFoldersFound
    case metadata(String)
    case underlying(String)

    var title: String {
        switch self {
        case .unreachable: "Unable to reach server!"
        case .authenticationFailed: "Wrong login credentials!"
        case .shareUnavailable: "Can't open file share!"
        case .timedOut: "Server unresponsive!"
        case .noFoldersFound: "Nothing to import!"
        case .metadata: "Can't load metadata!"
        case .underlying: "Setup failed!"
        }
    }

    var description: String {
        switch self {
        case .unreachable(let host):
            "Nothing answered at \(host) on port 445. check IP address."
        case .authenticationFailed:
            "Username and passord are incorrect, try again."
        case .shareUnavailable(let share):
            "Logged in, but this folder is blocked: \"\(share)\"."
        case .timedOut:
            "Logged in, but the server stopped responding."
        case .noFoldersFound:
            "No folders found in the share, add folders with anime episodes to the share."
        case .metadata(let detail):
            "Imported successfully, unable to get titles: \(detail)"
        case .underlying(let detail):
            detail
        }
    }

    /// Maps a POSIX error out of libsmb2 into something a person can act on.
    static func from(_ error: any Error, host: String, share: String?) -> SetupError {
        if let setupError = error as? SetupError { return setupError }

        if let posix = error as? POSIXError {
            switch posix.code {
            case .EACCES, .EPERM, .EAUTH, .ENOTSUP:
                return .authenticationFailed
            case .ETIMEDOUT:
                return .timedOut
            case .ECONNREFUSED, .EHOSTUNREACH, .ENETUNREACH, .EHOSTDOWN, .ECONNRESET, .ENOTCONN:
                return .unreachable(host)
            case .ENOENT, .ENODEV:
                if let share { return .shareUnavailable(share) }
            default:
                break
            }
        }

        if let apiError = error as? AniTrakApiError {
            return .metadata(apiError.description)
        }

        return .underlying(String(describing: error))
    }
}
