import Foundation

/// Centralized access to all UserDefaults keys and app constants.
enum AppSettings {
    /// The user-facing app name. Change this single value to rename the app everywhere.
    static let appName = "QuietCast"

    private static let defaults = UserDefaults(suiteName: PersistenceManager.appGroupID) ?? .standard

    // MARK: - Keys

    private enum Key {
        static let autoPlayNext = "autoPlayNext"
        static let maxVolume = "maxVolume"
        static let systemVolumeCapNC = "systemVolumeCapNC"
        static let systemVolumeFloorNC = "systemVolumeFloorNC"
        static let systemVolumeCapNoNC = "systemVolumeCapNoNC"
        static let systemVolumeFloorNoNC = "systemVolumeFloorNoNC"
        static let noiseCancellationOn = "noiseCancellationOn"
        static let systemVolumeCapEnabled = "systemVolumeCapEnabled"
        static let randomEpisodeAgeDays = "randomEpisodeAgeDays"
        static let randomExcludedFeedURLs = "randomExcludedFeedURLs"
        static let playbackRate = "playbackRate"
        static let volumeRangeAlwaysOn = "volumeRangeAlwaysOn"
        static let volumeRangeAutoReenableMinutes = "volumeRangeAutoReenableMinutes"
        static let volumeRangeReenableAt = "volumeRangeReenableAt"
        static let defaultSkipIntroSeconds = "defaultSkipIntroSeconds"
        static let autoPauseMinutes = "autoPauseMinutes"
    }

    // MARK: - Playback

    static var autoPlayNext: Bool {
        get { defaults.object(forKey: Key.autoPlayNext) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.autoPlayNext) }
    }

    static var maxVolume: Float {
        get { defaults.object(forKey: Key.maxVolume) as? Float ?? 1.0 }
        set { defaults.set(newValue, forKey: Key.maxVolume) }
    }

    // MARK: - Auto-Pause

    /// Automatically pause playback after this many minutes (0 = off). Default: 2 hours.
    static var autoPauseMinutes: Int {
        get { defaults.object(forKey: Key.autoPauseMinutes) as? Int ?? 120 }
        set { defaults.set(newValue, forKey: Key.autoPauseMinutes) }
    }

    // MARK: - System Volume

    static var noiseCancellationOn: Bool {
        get { defaults.bool(forKey: Key.noiseCancellationOn) }
        set { defaults.set(newValue, forKey: Key.noiseCancellationOn) }
    }

    static var systemVolumeCapNC: Float {
        get { defaults.object(forKey: Key.systemVolumeCapNC) as? Float ?? 0.20 }
        set { defaults.set(newValue, forKey: Key.systemVolumeCapNC) }
    }

    static var systemVolumeFloorNC: Float {
        get { defaults.object(forKey: Key.systemVolumeFloorNC) as? Float ?? 0.10 }
        set { defaults.set(newValue, forKey: Key.systemVolumeFloorNC) }
    }

    static var systemVolumeCapNoNC: Float {
        get { defaults.object(forKey: Key.systemVolumeCapNoNC) as? Float ?? 0.14 }
        set { defaults.set(newValue, forKey: Key.systemVolumeCapNoNC) }
    }

    static var systemVolumeFloorNoNC: Float {
        get { defaults.object(forKey: Key.systemVolumeFloorNoNC) as? Float ?? 0.09 }
        set { defaults.set(newValue, forKey: Key.systemVolumeFloorNoNC) }
    }

    /// Returns the active cap based on current NC mode.
    static var systemVolumeCap: Float {
        noiseCancellationOn ? systemVolumeCapNC : systemVolumeCapNoNC
    }

    /// Returns the active floor based on current NC mode.
    static var systemVolumeFloor: Float {
        noiseCancellationOn ? systemVolumeFloorNC : systemVolumeFloorNoNC
    }

    static var systemVolumeCapEnabled: Bool {
        get { defaults.object(forKey: Key.systemVolumeCapEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.systemVolumeCapEnabled) }
    }

    // MARK: - Random Episode

    static var randomEpisodeAgeDays: Int {
        get { defaults.object(forKey: Key.randomEpisodeAgeDays) as? Int ?? 60 }
        set { defaults.set(newValue, forKey: Key.randomEpisodeAgeDays) }
    }

    static var randomExcludedFeedURLs: [String] {
        get { defaults.stringArray(forKey: Key.randomExcludedFeedURLs) ?? [] }
        set { defaults.set(newValue, forKey: Key.randomExcludedFeedURLs) }
    }

    // MARK: - Playback Rate

    static var playbackRate: Float {
        get { defaults.object(forKey: Key.playbackRate) as? Float ?? 1.0 }
        set { defaults.set(newValue, forKey: Key.playbackRate) }
    }

    // MARK: - Intro Skip

    /// Default number of seconds to skip at the start of each episode (0 = off).
    static var defaultSkipIntroSeconds: Int {
        get { defaults.object(forKey: Key.defaultSkipIntroSeconds) as? Int ?? 0 }
        set { defaults.set(newValue, forKey: Key.defaultSkipIntroSeconds) }
    }

    // MARK: - Volume Range Override

    static var volumeRangeAlwaysOn: Bool {
        get { defaults.object(forKey: Key.volumeRangeAlwaysOn) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.volumeRangeAlwaysOn) }
    }

    /// Minutes after disabling Lock Volume Range before it re-enables automatically (0 = off). Default: 2 hours.
    static var volumeRangeAutoReenableMinutes: Int {
        get { defaults.object(forKey: Key.volumeRangeAutoReenableMinutes) as? Int ?? 120 }
        set { defaults.set(newValue, forKey: Key.volumeRangeAutoReenableMinutes) }
    }

    /// When Lock Volume Range is disabled, the date it should automatically re-enable.
    static var volumeRangeReenableAt: Date? {
        get { defaults.object(forKey: Key.volumeRangeReenableAt) as? Date }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Key.volumeRangeReenableAt)
            } else {
                defaults.removeObject(forKey: Key.volumeRangeReenableAt)
            }
        }
    }
}
