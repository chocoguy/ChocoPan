import SwiftUI

struct LibraryForm: View {
    @State private var isPlayerPresented = false
    @State private var isSMBPlayerPresented = false

    var body: some View {
        VStack(spacing: 40) {
            Text("Library Form")

            HStack(alignment: .top, spacing: 30) {
                ForEach(TestMedia.all) { media in
                    VideoThumbnailCardTEST(media: media)
                }
            }

            HStack(spacing: 30) {
                Button("Play test file") {
                    isPlayerPresented = true
                }

                Button("Play SMB test file") {
                    isSMBPlayerPresented = true
                }
            }
        }
        .fullScreenCover(isPresented: $isPlayerPresented) {
            PlayerTestView()
        }
        .fullScreenCover(isPresented: $isSMBPlayerPresented) {
            SMBPlayerTestView()
        }
    }
}

#Preview {
    LibraryForm()
}
