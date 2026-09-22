import Libmpv

nonisolated enum MPVEndReason: Sendable, Equatable {
    case eof
    case stop
    case quit
    case error(String)
    case redirect
    case unknown

    var didFinish: Bool { self == .eof }

    var failure: String? {
        if case .error(let message) = self { return message }
        return nil
    }

    init(_ event: mpv_event_end_file) {
        switch event.reason {
        case MPV_END_FILE_REASON_EOF:
            self = .eof
        case MPV_END_FILE_REASON_STOP:
            self = .stop
        case MPV_END_FILE_REASON_QUIT:
            self = .quit
        case MPV_END_FILE_REASON_REDIRECT:
            self = .redirect
        case MPV_END_FILE_REASON_ERROR:
            self = .error(String(cString: mpv_error_string(event.error)))
        default:
            self = .unknown
        }
    }
}
