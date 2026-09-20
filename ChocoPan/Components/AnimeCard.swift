import SwiftUI


struct AnimeCard: View {
    let anime: Anime

    static let posterWidth: CGFloat = 260
    private var posterHeight: CGFloat { Self.posterWidth * 3 / 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            poster
                .frame(width: Self.posterWidth, height: posterHeight)
                .clipShape(.rect(cornerRadius: 12))
                .overlay(alignment: .topTrailing) { badge }

            VStack(alignment: .leading, spacing: 4) {
                Text(anime.shownTitle)
                    .font(.callout)
                    .lineLimit(2)
                    .truncationMode(.tail)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: Self.posterWidth, alignment: .leading)
        }
    }

    @ViewBuilder
    private var poster: some View {
        if let urlString = anime.posterURL, let url = URL(string: urlString) {
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

    private var subtitle: String {
        if anime.metadataState.needsAttention {
            return anime.folderName
        }
        let episodes = anime.episodes.count
        let year = anime.year > 0 ? FormatYear(year: anime.year) : nil
        return [year, "\(episodes) ep"].compactMap { $0 }.joined(separator: " · ")
    }
}
