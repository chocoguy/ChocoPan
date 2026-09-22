/// Names of the mpv properties this player observes, reads or writes.
/// Full list: https://mpv.io/manual/stable/#property-list
enum MPVProperty {
    static let pause = "pause"
    static let pausedForCache = "paused-for-cache"
    static let timePos = "time-pos"
    static let duration = "duration"
    static let estimatedVfFps = "estimated-vf-fps"
    static let frameDropCount = "frame-drop-count"
    static let avsync = "avsync"
    static let videoHeight = "video-params/h"
    static let demuxerCacheTime = "demuxer-cache-time"
    static let containerFps = "container-fps"
    static let speed = "speed"
    static let start = "start"
    static let trackList = "track-list"
}
