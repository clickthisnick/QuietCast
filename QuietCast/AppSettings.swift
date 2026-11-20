import Foundation
import Observation

/// The only store for preferences. Memory is what the app reads; `didSet` writes the same
/// UserDefaults keys as before so values saved by older builds still load.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    /// The user-facing app name. Change this single value to rename the app everywhere.
    static let appName = "QuietCast"

    /// Per-podcast and global Skip Intro menu. `0` is off.
    static let skipIntroOptions = [0, 10, 15, 30, 45, 60, 90, 120]

    /// Skip forward and back, in seconds. Also the remote-command interval.
    static let skipIntervalSeconds = 30

    /// "1h 23m" or "5m". Truncates seconds. Under a minute is "0m".
    static func hoursMinutes(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0m" }
        let bounded = min(max(seconds, 0.0), Double(Int.max / 4))
        let total = Int(bounded)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private static let defaults = UserDefaults(suiteName: PersistenceManager.appGroupID) ?? .standard

    /// False while `init` is copying stored values in. `didSet` must not write or enforce yet.
    private var isReady = false

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

    private init() {
        autoPlayNext = Self.storedBool(Key.autoPlayNext, default: true)
        maxVolume = Self.storedFloat(Key.maxVolume, default: 1.0)
        autoPauseMinutes = Self.storedInt(Key.autoPauseMinutes, default: 120)
        noiseCancellationOn = Self.defaults.bool(forKey: Key.noiseCancellationOn)
        systemVolumeCapNC = Self.storedFloat(Key.systemVolumeCapNC, default: 0.20)
        systemVolumeFloorNC = Self.storedFloat(Key.systemVolumeFloorNC, default: 0.10)
        systemVolumeCapNoNC = Self.storedFloat(Key.systemVolumeCapNoNC, default: 0.14)
        systemVolumeFloorNoNC = Self.storedFloat(Key.systemVolumeFloorNoNC, default: 0.09)
        systemVolumeCapEnabled = Self.storedBool(Key.systemVolumeCapEnabled, default: true)
        randomEpisodeAgeDays = Self.storedInt(Key.randomEpisodeAgeDays, default: 60)
        randomExcludedFeedURLs = Self.defaults.stringArray(forKey: Key.randomExcludedFeedURLs) ?? []
        playbackRate = Self.storedFloat(Key.playbackRate, default: 1.0)
        defaultSkipIntroSeconds = Self.storedInt(Key.defaultSkipIntroSeconds, default: 0)
        volumeRangeAlwaysOn = Self.storedBool(Key.volumeRangeAlwaysOn, default: true)
        volumeRangeAutoReenableMinutes = Self.storedInt(Key.volumeRangeAutoReenableMinutes, default: 120)
        volumeRangeReenableAt = Self.defaults.object(forKey: Key.volumeRangeReenableAt) as? Date
        isReady = true
    }

    // MARK: - Playback

    var autoPlayNext: Bool = true {
        didSet { store(autoPlayNext, key: Key.autoPlayNext) }
    }

    var maxVolume: Float = 1.0 {
        didSet {
            guard store(maxVolume, key: Key.maxVolume) else { return }
            onMain { AudioPlayer.shared.clampOutputToMaxVolume() }
        }
    }

    /// Automatically pause playback after this many minutes (0 = off). Default: 2 hours.
    var autoPauseMinutes: Int = 120 {
        didSet { store(autoPauseMinutes, key: Key.autoPauseMinutes) }
    }

    var playbackRate: Float = 1.0 {
        didSet {
            guard store(playbackRate, key: Key.playbackRate) else { return }
            onMain { AudioPlayer.shared.applyPlaybackRate() }
        }
    }

    /// Default number of seconds to skip at the start of each episode (0 = off).
    var defaultSkipIntroSeconds: Int = 0 {
        didSet { store(defaultSkipIntroSeconds, key: Key.defaultSkipIntroSeconds) }
    }

    // MARK: - System Volume

    var noiseCancellationOn: Bool = false {
        didSet {
            guard store(noiseCancellationOn, key: Key.noiseCancellationOn) else { return }
            guard systemVolumeCapEnabled else { return }
            onMain {
                VolumeEnforcer.shared.enforceSystemVolumeCap()
                VolumeEnforcer.shared.enforceSystemVolumeFloor()
            }
        }
    }

    var systemVolumeCapNC: Float = 0.20 {
        didSet {
            guard store(systemVolumeCapNC, key: Key.systemVolumeCapNC) else { return }
            guard noiseCancellationOn && systemVolumeCapEnabled else { return }
            onMain { VolumeEnforcer.shared.enforceSystemVolumeCap() }
        }
    }

    var systemVolumeFloorNC: Float = 0.10 {
        didSet {
            guard store(systemVolumeFloorNC, key: Key.systemVolumeFloorNC) else { return }
            guard noiseCancellationOn && systemVolumeCapEnabled else { return }
            onMain { VolumeEnforcer.shared.enforceSystemVolumeFloor() }
        }
    }

    var systemVolumeCapNoNC: Float = 0.14 {
        didSet {
            guard store(systemVolumeCapNoNC, key: Key.systemVolumeCapNoNC) else { return }
            guard !noiseCancellationOn && systemVolumeCapEnabled else { return }
            onMain { VolumeEnforcer.shared.enforceSystemVolumeCap() }
        }
    }

    var systemVolumeFloorNoNC: Float = 0.09 {
        didSet {
            guard store(systemVolumeFloorNoNC, key: Key.systemVolumeFloorNoNC) else { return }
            guard !noiseCancellationOn && systemVolumeCapEnabled else { return }
            onMain { VolumeEnforcer.shared.enforceSystemVolumeFloor() }
        }
    }

    /// Active cap for the current noise-cancellation mode.
    var systemVolumeCap: Float {
        noiseCancellationOn ? systemVolumeCapNC : systemVolumeCapNoNC
    }

    /// Active floor for the current noise-cancellation mode.
    var systemVolumeFloor: Float {
        noiseCancellationOn ? systemVolumeFloorNC : systemVolumeFloorNoNC
    }

    var systemVolumeCapEnabled: Bool = true {
        didSet {
            guard store(systemVolumeCapEnabled, key: Key.systemVolumeCapEnabled) else { return }
            onMain { AudioPlayer.shared.systemVolumeLockChanged() }
        }
    }

    var volumeRangeAlwaysOn: Bool = true {
        didSet {
            guard store(volumeRangeAlwaysOn, key: Key.volumeRangeAlwaysOn) else { return }
            guard volumeRangeAlwaysOn && systemVolumeCapEnabled else { return }
            onMain {
                VolumeEnforcer.shared.enforceSystemVolumeCap()
                VolumeEnforcer.shared.enforceSystemVolumeFloor()
            }
        }
    }

    /// Minutes after disabling Lock Volume Range before it re-enables automatically (0 = off). Default: 2 hours.
    var volumeRangeAutoReenableMinutes: Int = 120 {
        didSet {
            guard store(volumeRangeAutoReenableMinutes, key: Key.volumeRangeAutoReenableMinutes) else { return }
            guard !systemVolumeCapEnabled else { return }
            onMain { AudioPlayer.shared.scheduleVolumeRangeReenableIfNeeded() }
        }
    }

    /// When Lock Volume Range is disabled, the date it should automatically re-enable.
    var volumeRangeReenableAt: Date? = nil {
        didSet {
            guard isReady else { return }
            if let volumeRangeReenableAt {
                Self.defaults.set(volumeRangeReenableAt, forKey: Key.volumeRangeReenableAt)
            } else {
                Self.defaults.removeObject(forKey: Key.volumeRangeReenableAt)
            }
        }
    }

    // MARK: - Random Episode

    var randomEpisodeAgeDays: Int = 60 {
        didSet { store(randomEpisodeAgeDays, key: Key.randomEpisodeAgeDays) }
    }

    var randomExcludedFeedURLs: [String] = [] {
        didSet { store(randomExcludedFeedURLs, key: Key.randomExcludedFeedURLs) }
    }

    // MARK: - Static access

    static var autoPlayNext: Bool {
        get { shared.autoPlayNext }
        set { shared.autoPlayNext = newValue }
    }
    static var maxVolume: Float {
        get { shared.maxVolume }
        set { shared.maxVolume = newValue }
    }
    static var autoPauseMinutes: Int {
        get { shared.autoPauseMinutes }
        set { shared.autoPauseMinutes = newValue }
    }
    static var playbackRate: Float {
        get { shared.playbackRate }
        set { shared.playbackRate = newValue }
    }
    static var defaultSkipIntroSeconds: Int {
        get { shared.defaultSkipIntroSeconds }
        set { shared.defaultSkipIntroSeconds = newValue }
    }
    static var noiseCancellationOn: Bool {
        get { shared.noiseCancellationOn }
        set { shared.noiseCancellationOn = newValue }
    }
    static var systemVolumeCapNC: Float {
        get { shared.systemVolumeCapNC }
        set { shared.systemVolumeCapNC = newValue }
    }
    static var systemVolumeFloorNC: Float {
        get { shared.systemVolumeFloorNC }
        set { shared.systemVolumeFloorNC = newValue }
    }
    static var systemVolumeCapNoNC: Float {
        get { shared.systemVolumeCapNoNC }
        set { shared.systemVolumeCapNoNC = newValue }
    }
    static var systemVolumeFloorNoNC: Float {
        get { shared.systemVolumeFloorNoNC }
        set { shared.systemVolumeFloorNoNC = newValue }
    }
    static var systemVolumeCap: Float { shared.systemVolumeCap }
    static var systemVolumeFloor: Float { shared.systemVolumeFloor }
    static var systemVolumeCapEnabled: Bool {
        get { shared.systemVolumeCapEnabled }
        set { shared.systemVolumeCapEnabled = newValue }
    }
    static var volumeRangeAlwaysOn: Bool {
        get { shared.volumeRangeAlwaysOn }
        set { shared.volumeRangeAlwaysOn = newValue }
    }
    static var volumeRangeAutoReenableMinutes: Int {
        get { shared.volumeRangeAutoReenableMinutes }
        set { shared.volumeRangeAutoReenableMinutes = newValue }
    }
    static var volumeRangeReenableAt: Date? {
        get { shared.volumeRangeReenableAt }
        set { shared.volumeRangeReenableAt = newValue }
    }
    static var randomEpisodeAgeDays: Int {
        get { shared.randomEpisodeAgeDays }
        set { shared.randomEpisodeAgeDays = newValue }
    }
    static var randomExcludedFeedURLs: [String] {
        get { shared.randomExcludedFeedURLs }
        set { shared.randomExcludedFeedURLs = newValue }
    }

    // MARK: - Persistence

    private static func storedBool(_ key: String, default defaultValue: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? defaultValue
    }

    private static func storedFloat(_ key: String, default defaultValue: Float) -> Float {
        defaults.object(forKey: key) as? Float ?? defaultValue
    }

    private static func storedInt(_ key: String, default defaultValue: Int) -> Int {
        defaults.object(forKey: key) as? Int ?? defaultValue
    }

    @discardableResult
    private func store(_ value: Bool, key: String) -> Bool {
        guard isReady else { return false }
        Self.defaults.set(value, forKey: key)
        return true
    }

    @discardableResult
    private func store(_ value: Float, key: String) -> Bool {
        guard isReady else { return false }
        Self.defaults.set(value, forKey: key)
        return true
    }

    @discardableResult
    private func store(_ value: Int, key: String) -> Bool {
        guard isReady else { return false }
        Self.defaults.set(value, forKey: key)
        return true
    }

    @discardableResult
    private func store(_ value: [String], key: String) -> Bool {
        guard isReady else { return false }
        Self.defaults.set(value, forKey: key)
        return true
    }

    /// Settings are changed on the main thread. Hop if a write ever arrives elsewhere.
    private func onMain(_ body: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(body)
        } else {
            Task { @MainActor in
                body()
            }
        }
    }
}
