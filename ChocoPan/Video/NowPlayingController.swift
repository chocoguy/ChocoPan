import MediaPlayer
import UIKit


@MainActor
final class NowPlayingController {
    struct Handlers {
        var play: () -> Void
        var pause: () -> Void
        var togglePlayPause: () -> Void
        var skip: (Double) -> Void
        var seek: (Double) -> Void
        var next: () -> Void
    }

    private var targets: [(command: MPRemoteCommand, token: Any)] = []
    private var artworkTask: Task<Void, Never>?
    private var info: [String: Any] = [:]


    func activate(handlers: Handlers, shortSkip: Double, longSkip: Double) {
        deactivate()

        let center = MPRemoteCommandCenter.shared()

        add(center.playCommand) { _ in handlers.play(); return .success }
        add(center.pauseCommand) { _ in handlers.pause(); return .success }
        add(center.togglePlayPauseCommand) { _ in handlers.togglePlayPause(); return .success }

        center.skipForwardCommand.preferredIntervals = [NSNumber(value: shortSkip)]
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: shortSkip)]

        add(center.skipForwardCommand) { event in
            handlers.skip((event as? MPSkipIntervalCommandEvent)?.interval ?? shortSkip)
            return .success
        }
        add(center.skipBackwardCommand) { event in
            handlers.skip(-((event as? MPSkipIntervalCommandEvent)?.interval ?? shortSkip))
            return .success
        }

        add(center.seekForwardCommand) { event in
            guard let seek = event as? MPSeekCommandEvent else { return .commandFailed }
            if seek.type == .beginSeeking { handlers.skip(longSkip) }
            return .success
        }
        add(center.seekBackwardCommand) { event in
            guard let seek = event as? MPSeekCommandEvent else { return .commandFailed }
            if seek.type == .beginSeeking { handlers.skip(-longSkip) }
            return .success
        }

        add(center.changePlaybackPositionCommand) { event in
            guard let change = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            handlers.seek(change.positionTime)
            return .success
        }

        add(center.nextTrackCommand) { _ in handlers.next(); return .success }

        for command in [
            center.previousTrackCommand,
            center.changePlaybackRateCommand,
            center.changeShuffleModeCommand,
            center.changeRepeatModeCommand,
            center.ratingCommand,
            center.likeCommand,
            center.dislikeCommand,
            center.bookmarkCommand,
        ] {
            command.isEnabled = false
        }

        UIApplication.shared.isIdleTimerDisabled = true
    }

    func deactivate() {
        artworkTask?.cancel()
        artworkTask = nil

        for target in targets {
            target.command.removeTarget(target.token)
        }
        targets.removeAll()

        info = [:]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }


    func update(title: String, subtitle: String?, duration: Double, elapsed: Double, rate: Double) {
        info[MPMediaItemPropertyTitle] = title
        info[MPMediaItemPropertyAlbumTitle] = subtitle
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.video.rawValue
        info[MPNowPlayingInfoPropertyIsLiveStream] = false
        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = max(0, elapsed)
        info[MPNowPlayingInfoPropertyPlaybackRate] = rate
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func loadArtwork(posterURL: URL?) {
        artworkTask?.cancel()
        guard let posterURL else {
            info[MPMediaItemPropertyArtwork] = nil
            return
        }

        artworkTask = Task { [weak self] in
            guard let image = try? await ImageCacher.shared.poster(at: posterURL) else { return }
            guard let self, !Task.isCancelled else { return }

            let poster = UIImage(cgImage: image)
            self.info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: poster.size) { _ in
                poster
            }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = self.info
        }
    }


    private func add(
        _ command: MPRemoteCommand,
        _ handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus
    ) {
        command.isEnabled = true
        targets.append((command, command.addTarget(handler: handler)))
    }
}
