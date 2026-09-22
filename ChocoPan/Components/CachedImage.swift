import CoreGraphics
import SwiftUI

struct CachedImage<Placeholder: View>: View {
    private let key: ImageKey
    private let produce: @Sendable () async throws -> CGImage
    private let placeholder: () -> Placeholder
    private var onFailure: (@MainActor (Error) -> Void)?

    @State private var image: CGImage?

    init(
        key: ImageKey,
        produce: @escaping @Sendable () async throws -> CGImage,
        onFailure: (@MainActor (Error) -> Void)? = nil,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.key = key
        self.produce = produce
        self.onFailure = onFailure
        self.placeholder = placeholder
    }

    var body: some View {
        content
            .task(id: key) {
                image = nil
                do {
                    image = try await ImageCacher.shared.image(for: key, produce: produce)
                } catch {
                    // Scrolling away cancels the task; that is not a failure to record.
                    guard !Task.isCancelled else { return }
                    onFailure?(error)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let image {
            Image(decorative: image, scale: 1)
                .resizable()
        } else {
            placeholder()
        }
    }
}

extension CachedImage {
    init(
        episodeId: UUID,
        fileModified: Date,
        videoURL: URL,
        tier: ImageTier,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.init(
            key: .thumbnail(episodeId: episodeId, fileModified: fileModified, tier: tier),
            produce: {
                try await VideoThumbnailer.thumbnail(for: videoURL, maxWidth: tier.maxPixelSize).image
            },
            placeholder: placeholder
        )
    }

    init(
        episode: AnimeEpisode,
        source: ThumbnailSource,
        maxWidth: Int,
        onFailure: (@MainActor (Error) -> Void)? = nil,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        // Read off the model here: the closure runs off the main actor and must not touch it.
        let path = episode.relativeFilePath
        self.init(
            key: .thumbnail(
                episodeId: episode.animeEpisodeId,
                fileModified: episode.fileModified,
                maxWidth: maxWidth
            ),
            produce: {
                try await ThumbnailProvider.shared.thumbnail(
                    source: source,
                    path: path,
                    maxWidth: maxWidth
                )
            },
            onFailure: onFailure,
            placeholder: placeholder
        )
    }

    init(
        posterURL: URL,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.init(
            key: .poster(urlString: posterURL.absoluteString),
            produce: { try await ImageCacher.fetchPoster(at: posterURL) },
            placeholder: placeholder
        )
    }
}
