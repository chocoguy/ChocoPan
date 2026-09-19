import SwiftUI




// Server - smb://192.168.1.153/anime
// Username - chocoguy


//Lucky Star
// anime/Lucky Star/Moe LuckyStar 04 BD 1080p FLAC.mp4

//Needy Girl Overdose
// anime/Needy Girl Overdose/[SubsPlease] NEEDY GIRL OVERDOSE - 07 (1080p) [A91DF9F8].mkv


/// Swap the index to play a different file; the list lives in TestMedia.swift.
private let testMedia = TestMedia.all[0]


struct PlayerTestView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var coordinator = MPVPlayerView.Coordinator(
        playUrl: testMedia.url
    )

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            MPVPlayerView(coordinator: coordinator)
                .ignoresSafeArea()

            PlayerControlsOverlay(coordinator: coordinator) { dismiss() }
        }
        .onPlayPauseCommand { coordinator.togglePause() }
        .onExitCommand { dismiss() }
    }
}
