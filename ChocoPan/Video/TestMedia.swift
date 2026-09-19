import Foundation

struct TestMedia: Identifiable, Hashable {
    let title: String
    let path: String

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }
}

extension TestMedia {
    static let all: [TestMedia] = [
        TestMedia(
            title: "Madoka Magica S01E01 · MKV · 16:9",
            path: "/Users/chocoguy/Downloads/"
                + "[YURI] Puella Magi Madoka Magica S01E01 [BD 1080p x264 10bit FLAC].mkv"
        ),
        TestMedia(
            title: "K-On! 02 · MP4 · 16:9",
            path: "/Users/chocoguy/Downloads/"
                + "-Tsundere- K-On - 02 -BDRip h264 1920x1080 FLAC--E2122F83-.mp4"
        ),
        TestMedia(
            title: "Initial D S01E05 · MKV · 4:3 · HEVC 10-bit",
            path: "/Users/chocoguy/Downloads/[Judas] Initial D - S01E05.mkv"
        ),
    ]
}
