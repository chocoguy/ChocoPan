/// Names of the mpv properties this player observes or reads.
/// Full list: https://mpv.io/manual/stable/#property-list
enum MPVProperty {
    static let pause = "pause"
    static let pausedForCache = "paused-for-cache"
    static let timePos = "time-pos"
    static let duration = "duration"
    static let estimatedVfFps = "estimated-vf-fps"
    static let frameDropCount = "frame-drop-count"
    static let avsync = "avsync"
}
