import SwiftUI


struct AnimeCard: View {
    let anime: Anime
    var onPlay: (AnimeEpisode) -> Void = { _ in }
    var onOpenShow: () -> Void = {}

    static let posterWidth: CGFloat = 260
    private var posterHeight: CGFloat { Self.posterWidth * 3 / 2 }

    var body: some View {
        VStack(spacing: 12) {
            Text(anime.shownTitle)
                .font(.callout)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
                .truncationMode(.tail)

            poster
                .frame(width: Self.posterWidth, height: posterHeight)
                .clipShape(.rect(cornerRadius: 12))
                .overlay(alignment: .topTrailing) { badge }

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            actions
        }
        .frame(width: Self.posterWidth)
    }

    private var actions: some View {
        HStack(spacing: 12) {
            if let episode = anime.nextEpisode {
                Button {
                    onPlay(episode)
                } label: {
                    Label(playTitle(for: episode), systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
            }

            Button(action: onOpenShow) {
                Label("Show", systemImage: "arrow.up.forward.app")
                    .frame(maxWidth: .infinity)
            }
        }
        .font(.caption)
        .lineLimit(1)
    }

    @ViewBuilder
    private var poster: some View {
        if let url = anime.posterSource {
            CachedImage(posterURL: url) {
                placeholder
            }
            .aspectRatio(contentMode: .fill)
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            Image(systemName: anime.metadataState.needsAttention ? "questionmark.folder" : "film.stack")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var badge: some View {
        if anime.metadataState.needsAttention {
            Text("Review")
                .font(.caption2)
                .fontWeight(.semibold)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.orange, in: .capsule)
                .foregroundStyle(.white)
                .padding(10)
        }
    }

    private func playTitle(for episode: AnimeEpisode) -> String {
        episode.isOva ? "OVA \(episode.episodeNumber)" : "Ep \(episode.episodeNumber)"
    }

    private var subtitle: String {
        if anime.metadataState.needsAttention {
            return anime.folderName
        }
        let episodes = anime.episodes.count
        let year = anime.year > 0 ? FormatYear(year: anime.year) : nil
        return [year, "\(episodes) ep"].compactMap { $0 }.joined(separator: " · ")
    }
}
