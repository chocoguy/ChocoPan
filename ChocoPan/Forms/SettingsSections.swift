import SwiftUI

// MARK: - Building blocks

/// The card every settings group sits in.
struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)

            content()
        }
        .padding(32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
    }
}

/// A label-and-control pair for everything that is not a toggle.
struct SettingsRow<Control: View>: View {
    let title: String
    var detail: String? = nil
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(spacing: 40) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            control()
                .labelsHidden()
                .frame(maxWidth: 820)
        }
    }
}

/// A toggle that carries its own explanation.
struct SettingsToggle: View {
    let title: String
    var detail: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// tvOS has no `Stepper` or `Slider`, so every number is chosen from a fixed set.
private func secondsLabel(_ value: Double) -> String {
    value == 0 ? "Off" : "\(Int(value))s"
}

// MARK: - Playback

struct PlaybackSettingsSection: View {
    @Bindable var settings: ChocoPanSettings

    private let delays: [Double] = [0, 3, 5, 8, 15]
    private let speeds: [Double] = [0.75, 1.0, 1.25, 1.5, 2.0]
    private let resumeMinimums: [Double] = [10, 30, 60, 120]
    private let watchedThresholds: [Double] = [0.75, 0.8, 0.85, 0.9, 0.95]
    private let skips: [Double] = [0, 30, 60, 90, 120]
    private let smallSeeks: [Double] = [5, 10, 15, 30]
    private let largeSeeks: [Double] = [30, 60, 90, 120]

    var body: some View {
        SettingsCard(title: "Playback") {
            SettingsToggle(
                title: "Auto-play Next Episode",
                detail: "Roll straight into the next episode when one finishes.",
                isOn: $settings.autoPlayNextEpisode
            )

            SettingsRow(title: "Auto-play Countdown") {
                Picker("Auto-play Countdown", selection: $settings.autoPlayNextDelaySeconds) {
                    ForEach(delays, id: \.self) { Text(secondsLabel($0)).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            .disabled(!settings.autoPlayNextEpisode)

            SettingsRow(title: "Default Speed") {
                Picker("Default Speed", selection: $settings.defaultPlaybackSpeed) {
                    ForEach(speeds, id: \.self) { speed in
                        Text(speed == 1 ? "1×" : "\(speed.formatted())×").tag(speed)
                    }
                }
                .pickerStyle(.segmented)
            }

            SettingsToggle(
                title: "Match Content Frame Rate",
                detail: "Switch the display to the video's own frame rate.",
                isOn: $settings.matchContentFrameRate
            )

            SettingsRow(
                title: "Skip Opening",
                detail: "How far the skip-intro control jumps."
            ) {
                Picker("Skip Opening", selection: $settings.skipOpeningSeconds) {
                    ForEach(skips, id: \.self) { Text(secondsLabel($0)).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            SettingsRow(title: "Skip Ending") {
                Picker("Skip Ending", selection: $settings.skipEndingSeconds) {
                    ForEach(skips, id: \.self) { Text(secondsLabel($0)).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            SettingsRow(
                title: "Short Seek",
                detail: "Left and right on the remote."
            ) {
                Picker("Short Seek", selection: $settings.seekSmallSeconds) {
                    ForEach(smallSeeks, id: \.self) { Text(secondsLabel($0)).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            SettingsRow(title: "Long Seek") {
                Picker("Long Seek", selection: $settings.seekLargeSeconds) {
                    ForEach(largeSeeks, id: \.self) { Text(secondsLabel($0)).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            SettingsRow(
                title: "Offer Resume After",
                detail: "Below this, an episode starts over instead of resuming."
            ) {
                Picker("Offer Resume After", selection: $settings.resumeMinimumSeconds) {
                    ForEach(resumeMinimums, id: \.self) { Text(secondsLabel($0)).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            SettingsRow(
                title: "Count as Watched At",
                detail: "How much of an episode counts as finished."
            ) {
                Picker("Count as Watched At", selection: $settings.watchedThresholdFraction) {
                    ForEach(watchedThresholds, id: \.self) { fraction in
                        Text(fraction.formatted(.percent.precision(.fractionLength(0)))).tag(fraction)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }
}

// MARK: - Video

struct VideoSettingsSection: View {
    @Bindable var settings: ChocoPanSettings

    var body: some View {
        SettingsCard(title: "Video") {
            SettingsToggle(
                title: "Anime4K",
                detail: "GPU upscaling shaders tuned for animation.",
                isOn: $settings.anime4KEnabled
            )

            Group {
                SettingsRow(title: "Preset · Up to 720p") {
                    presetPicker(title: "Preset · Up to 720p", selection: $settings.anime4KPresetSDName)
                }

                SettingsRow(title: "Preset · Up to 1080p") {
                    presetPicker(title: "Preset · Up to 1080p", selection: $settings.anime4KPresetHDName)
                }

                SettingsRow(
                    title: "Preset · Above 1080p",
                    detail: "Already-large frames rarely need it."
                ) {
                    presetPicker(title: "Preset · Above 1080p", selection: $settings.anime4KPresetUHDName)
                }
            }
            .disabled(!settings.anime4KEnabled)

            SettingsToggle(
                title: "Hardware Decoding",
                detail: "Turn off only when a file plays back wrong.",
                isOn: $settings.hardwareDecodingEnabled
            )
        }
    }
}

private func presetPicker(title: String, selection: Binding<String>) -> some View {
    Picker(title, selection: selection) {
        ForEach(Anime4KPreset.all) { preset in
            Text(preset.name).tag(preset.name)
        }
    }
    .pickerStyle(.segmented)
}

// MARK: - Library

struct LibrarySettingsSection: View {
    @Bindable var settings: ChocoPanSettings

    private let thumbnailWidths: [Int] = [320, 480, 640, 960]
    private let cacheLimits: [Int] = [128, 256, 512, 1024]

    var body: some View {
        SettingsCard(title: "Library") {
            SettingsToggle(
                title: "Scan on Launch",
                detail: "Look for new folders and episodes when ChocoPan opens.",
                isOn: $settings.autoScanOnLaunch
            )

            SettingsToggle(
                title: "Hide Watched Episodes",
                isOn: $settings.hideWatchedEpisodes
            )

            SettingsToggle(
                title: "Thumbnails on Scan",
                detail: "Pull a still from each episode while scanning.",
                isOn: $settings.generateThumbnailsOnScan
            )

            SettingsRow(title: "Thumbnail Width") {
                Picker("Thumbnail Width", selection: $settings.thumbnailMaxWidth) {
                    ForEach(thumbnailWidths, id: \.self) { Text("\($0) px").tag($0) }
                }
                .pickerStyle(.segmented)
            }
            .disabled(!settings.generateThumbnailsOnScan)

            SettingsRow(
                title: "Image Cache Limit",
                detail: "Oldest images are dropped once the cache passes this."
            ) {
                Picker("Image Cache Limit", selection: $settings.thumbnailCacheLimitMB) {
                    ForEach(cacheLimits, id: \.self) { limit in
                        Text(limit >= 1024 ? "\(limit / 1024) GB" : "\(limit) MB").tag(limit)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }
}

// MARK: - Advanced

struct AdvancedSettingsSection: View {
    @Bindable var settings: ChocoPanSettings

    var body: some View {
        SettingsCard(title: "Advanced") {
            SettingsToggle(
                title: "Stats Overlay",
                detail: "Show decoder, frame rate and cache state during playback.",
                isOn: $settings.showStatsOverlay
            )

            SettingsRow(
                title: "mpv Logging",
                detail: "Written to the Xcode console."
            ) {
                Picker("mpv Logging", selection: $settings.mpvLogLevel) {
                    ForEach(MPVLogLevel.allCases) { level in
                        Text(level.title).tag(level)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Extra mpv Options")
                    .font(.headline)
                Text("One `key=value` per line. Wrong values can stop playback entirely.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("cache-secs=30", text: $settings.extraMpvOptions, axis: .vertical)
                    .lineLimit(1...4)
            }
        }
    }
}
