import SwiftUI

struct PlayerProgressBar: View {
    let position: Double
    let duration: Double
    var isFocused = false
    var pending: Double?

    private static let labelWidth: CGFloat = 140

    private var shown: Double { pending ?? position }

    private var fraction: Double {
        guard duration > 0, shown.isFinite else { return 0 }
        return min(max(shown / duration, 0), 1)
    }

    private var trackHeight: CGFloat { isFocused ? 10 : 6 }
    private var tickHeight: CGFloat { isFocused ? 30 : 18 }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let playhead = width * fraction

            VStack(spacing: 10) {
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.28))
                        .frame(height: trackHeight)

                    Capsule()
                        .fill(.white)
                        .frame(width: playhead, height: trackHeight)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white)
                        .frame(width: 4, height: tickHeight)
                        .offset(x: playhead - 2)
                        .shadow(color: .black.opacity(0.5), radius: 3)
                }
                .frame(height: tickHeight)

                ZStack(alignment: .topLeading) {
                    Text(FormatDuration(seconds: shown))
                        .frame(width: Self.labelWidth)
                        .offset(x: min(max(playhead - Self.labelWidth / 2, 0), max(0, width - Self.labelWidth)))

                    Text(FormatDuration(seconds: duration))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .frame(height: 26)
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .frame(height: 72)
        .font(.callout)
        .monospacedDigit()
        .foregroundStyle(.white)
        .opacity(isFocused ? 1 : 0.75)
        .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
        .animation(.easeOut(duration: 0.18), value: isFocused)
    }
}
