import SwiftData
import SwiftUI

struct LibraryAnimeForm: View {
    let anime: Anime
    var onPlay: (AnimeEpisode) -> Void = { _ in }

    private static let posterWidth: CGFloat = 300
    private var posterHeight: CGFloat { Self.posterWidth * 3 / 2 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 44) {
                header
                episodeGrid
                animeSettings
            }
            .padding(60)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 36) {
            poster
                .frame(width: Self.posterWidth, height: posterHeight)
                .clipShape(.rect(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 8) {
                Text(anime.shownTitle)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)

                ForEach(metaLines, id: \.self) { line in
                    Text(line)
                        .font(.title3)
                }

                if let synopsis = anime.synopsis?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !synopsis.isEmpty {
                    Text(synopsis)
                        .font(.body)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.regularMaterial, in: .rect(cornerRadius: 12))
                        .padding(.top, 8)
                }
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var poster: some View {
        if let url = anime.posterSource {
            CachedImage(posterURL: url) { posterPlaceholder }
                .aspectRatio(contentMode: .fill)
        } else {
            posterPlaceholder
        }
    }

    private var posterPlaceholder: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            Image(systemName: "film.stack")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
        }
    }

    /// The stacked facts under the title, skipping anything the scan could not resolve.
    private var metaLines: [String] {
        var lines: [String] = []

        let season = anime.seasonName.lowercased() == "unknown" ? nil : anime.seasonName.capitalized
        let year = anime.year > 0 ? FormatYear(year: anime.year) : nil
        let released = [season, year].compactMap { $0 }.joined(separator: " - ")
        if !released.isEmpty { lines.append(released) }

        let count = anime.episodeCount > 0 ? anime.episodeCount : anime.episodes.count
        if count > 0 { lines.append("\(count) Episode\(count == 1 ? "" : "s")") }

        if !anime.studios.isEmpty {
            lines.append("Studios: \(anime.studios.joined(separator: ", "))")
        }
        if !anime.tags.isEmpty {
            lines.append("Tags: \(anime.tags.joined(separator: " | "))")
        }

        return lines
    }

    // MARK: - Episodes

    @ViewBuilder
    private var episodeGrid: some View {
        let episodes = anime.orderedEpisodes

        if episodes.isEmpty {
            Label("No episode files in this folder", systemImage: "film.stack")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 36) {
                ForEach(episodes) { episode in
                    EpisodeCard(episode: episode) { onPlay(episode) }
                }
            }
        }
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: EpisodeCard.width), spacing: 28, alignment: .top)]
    }

    // MARK: - Anime settings

    private var animeSettings: some View {
        HStack {
            Spacer()
            // TODO: per-show preferences (audio and subtitle track, MAL link) live here.
            Button("Anime Settings") {}
            Spacer()
        }
        .padding(.top, 20)
    }
}

// MARK: - Episode card

struct EpisodeCard: View {
    let episode: AnimeEpisode
    let onPlay: () -> Void

    static let width: CGFloat = 420
    private var height: CGFloat { Self.width * 9 / 16 }

    var body: some View {
        VStack(spacing: 10) {
            Button(action: onPlay) {
                thumbnail
                    .frame(width: Self.width, height: height)
                    .clipShape(.rect(cornerRadius: 10))
                    .overlay(alignment: .bottom) { progress }
            }
            .buttonStyle(.card)

            HStack(spacing: 8) {
                Text(caption)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if episode.watched {
                    Image(systemName: "checkmark.square.fill")
                        .foregroundStyle(.green)
                }
            }
        }
        .frame(width: Self.width)
    }

    /// Thumbnails cannot be generated yet: `VideoThumbnailer` opens a path with FFmpeg directly and
    /// these files only exist behind SMB. Swap the placeholder for `CachedImage(episodeId:…)` once
    /// there is a URL FFmpeg can read.
    private var thumbnail: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            Image(systemName: "play.rectangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var progress: some View {
        if !episode.watched, episode.playbackPositionSeconds > 0, episode.episodeLengthSeconds > 0 {
            GeometryReader { proxy in
                let fraction = min(1, episode.playbackPositionSeconds / episode.episodeLengthSeconds)
                Rectangle()
                    .fill(.tint)
                    .frame(width: proxy.size.width * fraction)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .frame(height: 6)
        }
    }

    private var caption: String {
        let label = episode.isOva ? "OVA \(episode.episodeNumber)" : "Episode \(episode.episodeNumber)"
        guard episode.episodeLengthSeconds > 0 else { return label }
        return "\(label) | \(FormatDuration(seconds: episode.episodeLengthSeconds))"
    }
}

#Preview {
    LibraryAnimeForm(
        anime: Anime(
            folderPath: "Anime/Madoka",
            folderName: "Madoka",
            title: "Mahou Shoujo Madoka★Magica",
            year: 2011,
            episodeCount: 12,
            seasonName: "winter",
            mediaTypeName: "tv",
            tags: ["Award Winning", "Drama", "Mahou Shoujo"],
            studios: ["Shaft"],
            synopsis: "Madoka Kaname and Sayaka Miki are regular middle school girls with regular "
                + "lives, but all that changes when they encounter Kyuubey."
        )
    )
    .modelContainer(ChocoPanModelContainer.preview)
}
