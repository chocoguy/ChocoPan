import SwiftUI

struct VideoThumbnailCardTEST: View {
    let media: TestMedia

    @State private var thumbnail: VideoThumbnail?
    @State private var failure: String?

    private static let cardWidth: CGFloat = 420

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Color.black

                if let thumbnail {
                    //4:3 pillar box
                    Image(decorative: thumbnail.image, scale: 1)
                        .resizable()
                        .scaledToFit()
                } else if let failure {
                    Text(failure)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(8)
                } else {
                    ProgressView()
                }
            }
            .frame(width: Self.cardWidth, height: Self.cardWidth * 9 / 16)
            .clipShape(.rect(cornerRadius: 12))

            Text(media.title)
                .font(.caption)
                .lineLimit(2)

            Text(detail)
                .font(.caption2)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(width: Self.cardWidth)
        .task {
            do {
                thumbnail = try await VideoThumbnailer.thumbnail(for: media.url)
            } catch {
                failure = "\(error)"
            }
        }
    }

    private var detail: String {
        guard let thumbnail else { return failure == nil ? "extracting…" : "failed" }
        return "\(timecode(thumbnail.timestamp)) · "
            + "\(thumbnail.image.width)×\(thumbnail.image.height)"
    }

    private func timecode(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

#Preview {
    VideoThumbnailCardTEST(media: TestMedia.all[0])
}
