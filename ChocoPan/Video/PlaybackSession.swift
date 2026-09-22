import SwiftData
import SwiftUI


@MainActor
@Observable
final class PlaybackSession {
    enum Phase: Equatable {
        case connecting(String)
        case playing
        case failed(String)
        case finished
    }

    private(set) var phase: Phase = .connecting("Starting")
    private(set) var coordinator: MPVPlayerView.Coordinator?
    private(set) var episode: AnimeEpisode
    /// Set only while the auto-play card is up.
    private(set) var upNext: AnimeEpisode?
    private(set) var secondsUntilNext: Int?

    let settings: ChocoPanSettings

    private let context: ModelContext
    private let nowPlaying = NowPlayingController()
    private var session: SMBSession?
    /// Once the viewer picks a preset by hand, stop imposing the resolution default on them.
    private var hasOverriddenPreset = false
    private var hasCountedAsWatched = false
    private var progressTask: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?
    private var isStopped = false

    init(episode: AnimeEpisode, settings: ChocoPanSettings, context: ModelContext) {
        self.episode = episode
        self.settings = settings
        self.context = context
    }


    var anime: Anime? { episode.anime }

    var seasonLine: String {
        guard let anime else { return "" }
        let season = anime.seasonName.lowercased() == "unknown" ? nil : anime.seasonName.capitalized
        let year = anime.year > 0 ? FormatYear(year: anime.year) : nil
        return [season, year].compactMap { $0 }.joined(separator: " - ")
    }

    var episodeLine: String {
        let label = episode.displayLabel
        guard let title = anime?.shownTitle, !title.isEmpty else { return label }
        return "\(label) - \(title)"
    }


    func start() async {
        guard let source = episode.anime?.source else {
            phase = .failed("This episode is not attached to a library source. Re-run setup in Settings.")
            return
        }

        var step = "Starting"
        do {
            step = "Connecting to \(source.host ?? source.name)"
            phase = .connecting(step)
            let session = try SMBSession.make(for: source)
            try await session.connect(share: source.share)
            self.session = session

            step = "Opening \(episode.fileName)"
            phase = .connecting(step)
            let token = try await session.prepare(path: episode.relativeFilePath)

            let coordinator = MPVPlayerView.Coordinator(
                playUrl: SMBStreamProtocol.url(forToken: token)
            )
            coordinator.smbSession = session
            coordinator.configuration = PlayerConfiguration(settings: settings)
            coordinator.startAtSeconds = resumePosition(for: episode)
            attach(to: coordinator)

            self.coordinator = coordinator
            phase = .playing
            activateNowPlaying()
            startProgressTicker()
        } catch {
            print("[player] failed while \(step.lowercased()): \(error)")
            phase = .failed("\(step):\n\(error)")
        }
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true

        countdownTask?.cancel()
        progressTask?.cancel()
        countdownTask = nil
        progressTask = nil

        persistProgress()
        nowPlaying.deactivate()

        coordinator?.player?.resetDisplayCriteria()

        coordinator?.player?.shutdown()
        coordinator = nil

        let session = self.session
        self.session = nil
        Task.detached { await session?.disconnect() }
    }

    private func attach(to coordinator: MPVPlayerView.Coordinator) {
        coordinator.onFileLoaded = { [weak self] in self?.handleFileLoaded() }
        coordinator.onEndFile = { [weak self] reason in self?.handleEndFile(reason) }
        coordinator.onVideoHeight = { [weak self] height in self?.applyAutomaticPreset(height: height) }
    }


    private func handleFileLoaded() {
        guard let coordinator else { return }
        backfillDuration()
        applyPreferredTracks(using: coordinator)
        nowPlaying.loadArtwork(posterURL: anime?.posterSource)
        updateNowPlaying()
    }


    private func activateNowPlaying() {
        nowPlaying.activate(
            handlers: NowPlayingController.Handlers(
                play: { [weak self] in self?.coordinator?.play(); self?.updateNowPlaying() },
                pause: { [weak self] in self?.coordinator?.pause(); self?.persistProgress() },
                togglePlayPause: { [weak self] in self?.togglePause() },
                skip: { [weak self] delta in self?.seek(delta) },
                seek: { [weak self] position in self?.seek(to: position) },
                next: { [weak self] in self?.skipToNextEpisode() }
            ),
            shortSkip: settings.seekSmallSeconds,
            longSkip: settings.seekLargeSeconds
        )
    }

    private func updateNowPlaying() {
        guard let coordinator else { return }
        nowPlaying.update(
            title: episode.displayLabel,
            subtitle: anime?.shownTitle,
            duration: coordinator.duration,
            elapsed: coordinator.timePos,
            rate: coordinator.isPaused ? 0 : 1
        )
    }

    private func applyPreferredTracks(using coordinator: MPVPlayerView.Coordinator) {
        guard let anime else { return }
        apply(TrackPreference(descriptor: anime.preferredAudioTrack), kind: .audio, using: coordinator)
        apply(TrackPreference(descriptor: anime.preferredSubTrack), kind: .subtitle, using: coordinator)
    }

    private func apply(
        _ preference: TrackPreference?,
        kind: MPVTrackKind,
        using coordinator: MPVPlayerView.Coordinator
    ) {
        guard let preference else { return }
        switch preference.resolve(in: coordinator.tracks(kind: kind)) {
        case .select(let track): coordinator.select(track, kind: kind)
        case .turnOff: coordinator.select(nil, kind: kind)
        case .leaveAlone: break
        }
    }

    private func applyAutomaticPreset(height: Int) {
        guard let coordinator else { return }
        coordinator.player?.applyDisplayCriteria()
        guard !hasOverriddenPreset else { return }
        coordinator.apply(preset: settings.anime4KPreset(forVideoHeight: height))
    }


    func select(_ track: MPVTrack?, kind: MPVTrackKind) {
        guard let coordinator else { return }
        coordinator.select(track, kind: kind)

        let descriptor = TrackPreference(track: track).descriptor
        switch kind {
        case .audio: anime?.preferredAudioTrack = descriptor
        case .subtitle: anime?.preferredSubTrack = descriptor
        }
        save()
    }

    func select(preset: Anime4KPreset) {
        hasOverriddenPreset = true
        coordinator?.apply(preset: preset)
    }

    func togglePause() {
        coordinator?.togglePause()
        persistProgress()
        updateNowPlaying()
    }

    func seek(_ seconds: Double) {
        coordinator?.seek(seconds)
    }

    func seek(to seconds: Double) {
        coordinator?.seek(to: seconds)
    }


    private func startProgressTicker() {
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self, !Task.isCancelled else { return }
                self.persistProgress()
                self.updateNowPlaying()
            }
        }
    }

    private func backfillDuration() {
        guard let duration = coordinator?.duration, duration > 0 else { return }
        guard abs(episode.episodeLengthSeconds - duration) > 0.5 else { return }
        episode.episodeLengthSeconds = duration
    }

    func persistProgress() {
        guard let coordinator, coordinator.isLoaded else { return }
        backfillDuration()

        let position = coordinator.timePos
        if settings.isWatched(position: position, duration: coordinator.duration) {
            markWatched()
        } else {
            episode.playbackPositionSeconds = position
        }
        episode.lastPlayedDate = .now
        save()
    }

    private func markWatched() {
        episode.playbackPositionSeconds = 0
        guard !hasCountedAsWatched else { return }
        hasCountedAsWatched = true
        episode.watched = true
        episode.playCount += 1
    }

    private func save() {
        do {
            try context.save()
        } catch {
            print("[player] could not save playback progress: \(error)")
        }
    }

    private func resumePosition(for episode: AnimeEpisode) -> Double {
        settings.shouldResume(
            from: episode.playbackPositionSeconds,
            duration: episode.episodeLengthSeconds
        ) ? episode.playbackPositionSeconds : 0
    }


    private func handleEndFile(_ reason: MPVEndReason) {
        if let failure = reason.failure {
            persistProgress()
            phase = .failed("Playback stopped:\n\(failure)")
            return
        }
        guard reason.didFinish else { return }

        markWatched()
        episode.lastPlayedDate = .now
        save()

        guard settings.autoPlayNextEpisode, let next = nextEpisode() else {
            phase = .finished
            return
        }
        beginCountdown(to: next)
    }

    private func nextEpisode() -> AnimeEpisode? {
        guard let ordered = anime?.orderedEpisodes,
              let index = ordered.firstIndex(where: { $0.animeEpisodeId == episode.animeEpisodeId }),
              ordered.indices.contains(index + 1) else {
            return nil
        }
        return ordered[index + 1]
    }

    private func beginCountdown(to next: AnimeEpisode) {
        upNext = next
        let delay = Int(settings.autoPlayNextDelaySeconds.rounded())
        guard delay > 0 else {
            playNow()
            return
        }

        secondsUntilNext = delay
        countdownTask = Task { [weak self] in
            for remaining in stride(from: delay - 1, through: 0, by: -1) {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                self.secondsUntilNext = remaining
            }
            guard let self, !Task.isCancelled else { return }
            self.playNow()
        }
    }

    func cancelAutoPlay() {
        countdownTask?.cancel()
        countdownTask = nil
        upNext = nil
        secondsUntilNext = nil
        phase = .finished
    }

    func skipToNextEpisode() {
        guard let next = nextEpisode() else { return }
        persistProgress()
        countdownTask?.cancel()
        countdownTask = nil
        upNext = nil
        secondsUntilNext = nil
        Task { await load(next) }
    }

    func playNow() {
        countdownTask?.cancel()
        countdownTask = nil
        guard let next = upNext else { return }
        upNext = nil
        secondsUntilNext = nil
        Task { await load(next) }
    }

    private func load(_ next: AnimeEpisode) async {
        guard let session, let coordinator else { return }
        do {
            let token = try await session.prepare(path: next.relativeFilePath)
            episode = next
            hasCountedAsWatched = false
            hasOverriddenPreset = false
            coordinator.load(
                url: SMBStreamProtocol.url(forToken: token),
                startAt: resumePosition(for: next)
            )
            phase = .playing
            updateNowPlaying()
        } catch {
            print("[player] could not open the next episode: \(error)")
            phase = .failed("Could not open \(next.fileName):\n\(error)")
        }
    }
}
