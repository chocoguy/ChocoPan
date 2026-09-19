import CoreGraphics
import SwiftUI

struct CachedImage<Placeholder: View>: View {
    private let key: ImageKey
    private let produce: @Sendable () async throws -> CGImage
    private let placeholder: () -> Placeholder

    @State private var image: CGImage?

    init(
        key: ImageKey,
        produce: @escaping @Sendable () async throws -> CGImage,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.key = key
        self.produce = produce
        self.placeholder = placeholder
    }

    var body: some View {
        content
            .task(id: key) {
                image = nil
                image = try? await ImageCacher.shared.image(for: key, produce: produce)
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

    /// An anime poster.
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
