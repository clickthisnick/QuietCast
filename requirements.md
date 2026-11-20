# QuietCast — Requirements & Feature Specification

A calm, sleep-focused podcast player for iOS. Designed to help users fall asleep to podcasts with minimal blue light, volume safety, and time-gated features that discourage late-night phone engagement.

---

## Platform & Architecture

- **Platform**: iOS 17+
- **Language**: Swift, SwiftUI
- **State Management**: `@Observable` macro (no Combine, no ObservableObject)
- **Persistence**: JSON files in an App Group shared container (no Core Data / SwiftData). App Group ID: `group.com.quietcast.shared`
- **Audio**: `AVPlayer` with `AVAudioSession` category `.playback`, mode `.spokenAudio`
- **Downloads**: Background `URLSession` for offline episode downloads
- **App Name**: Centralized in `AppSettings.appName`. All user-facing strings reference this constant. `Info.plist` `CFBundleDisplayName` is set separately. To rename the app, change both `AppSettings.appName` and `CFBundleDisplayName`.
- **Color Scheme**: Always dark mode (`.preferredColorScheme(.dark)`)
- **Accent Colors**: Warm amber (`Color.warmAccent`), muted green for download status (`Color.warmGreen`), dim amber for sleep timer (`Color.warmDim`)
- **Provisioning**: Free Apple Developer accounts require re-signing every 7 days. Check expiration in Xcode under **Signing & Capabilities** for the current team and profile status — it will show warnings if a profile is about to expire. On-device, go to **Settings → General → VPN & Device Management** to see the certificate expiration date.

---

## App Structure

### Files

| File | Purpose |
|------|---------|
| `QuietCastApp.swift` | App entry point. Sets up audio session, dims screen at night, enforces volume bounds on app open, flushes saves on background. |
| `ContentView.swift` | Root view — renders `LibraryView`. |
| `LibraryView.swift` | Main podcast list. Swipe-to-delete, reorder sheet, feed URL entry, search access. Resume card for last-played episode. |
| `EpisodeListView.swift` | Episode list for a podcast. Play/pause, download, shuffle button, per-podcast intro skip setting. |
| `NowPlayingBar.swift` | Persistent transport bar with scrubber, sleep timer, skip, speed controls, noise cancellation toggle. |
| `SearchView.swift` | iTunes podcast search (time-gated). |
| `SettingsView.swift` | All settings: playback, volume controls, random episode config, data management. |
| `AudioPlayer.swift` | Singleton audio engine. Playback, fade-in, sleep timer, position persistence, now playing info. Tracks `currentFeedURL` for podcast-specific settings (intro skip, position saving). |
| `VolumeEnforcer.swift` | System volume cap/floor enforcement via hidden `MPVolumeView`, KVO observation, rapid polling. Reads mode-aware cap/floor from `AppSettings`. |
| `SpeechAnnouncer.swift` | Spoken announcements via `AVSpeechSynthesizer` with best-voice selection. |
| `RemoteCommandHandler.swift` | `MPRemoteCommandCenter` setup, crown action mutex, random episode and speak-time logic. |
| `AppSettings.swift` | Centralized `UserDefaults` access. All keys and defaults in one place. |
| `silence.wav` | 0.1-second silent audio clip used to claim Now Playing session on launch. |
| `DownloadManager.swift` | Background download management with progress tracking. |
| `PersistenceManager.swift` | JSON-based persistence for library, episode cache, playback positions, played status, last-played episode, per-podcast skip durations. |
| `RSSParser.swift` | XML parser for podcast RSS feeds. Computes `pubDateTimestamp` at parse time. |
| `iTunesSearchService.swift` | iTunes Search API client. |
| `HTMLCleaner.swift` | Strips HTML tags, URLs, and entities from episode descriptions. |
| `Models.swift` | `Podcast` and `Episode` data models. |
| `TimeGate.swift` | Time-based feature gating (search hours, nighttime detection). |
| `BuildInfo.swift` | Build timestamp derived from executable modification date. |

---

## Features

### 1. Podcast Library

- **List display**: Plain list of podcast titles with chevron indicators.
- **Add by search**: iTunes Search API via magnifying glass icon (time-gated to 8 AM – 8 PM).
- **Add by URL**: Link button opens an alert to paste an RSS feed URL. Validates URL, checks for duplicates (by URL and by title), shows loading overlay.
- **Swipe-to-delete**: Swipe left on any podcast row to reveal a delete button. Confirmation alert reads "Delete Podcast & Data" and explains what will be removed.
- **Reorder**: Arrow up/down button in toolbar (only visible with 2+ podcasts) opens a dedicated `ReorderPodcastsView` sheet with permanent edit mode for drag-to-reorder.
- **Hints**: Bottom of list shows:
  - "Double-press headphone crown for a random episode"
  - "Triple-press headphone crown to hear the time"
  - "Swipe left to delete a podcast"
  - Build timestamp (e.g., "Built Jun 5, 2026 at 3:42 PM")
- **Search hours notice**: When search is unavailable (8 PM – 8 AM), a caption reads "Search is available between 8 AM and 8 PM."
- **Resume last played**: When no episode is currently playing and a last-played episode exists on disk, a resume card appears above the podcast list showing the episode title, podcast name, saved position (e.g. "1h 23m in"), and a play button. Tapping it resumes from the saved position. The card disappears once playback starts.
- **Storage diagnostics**: When the podcast list is empty, the empty state shows debug info (App Group availability, container ID, path, and library.json existence) in a quaternary caption to aid troubleshooting.
- **Data cleared listener**: Resets podcast list when `QuietCastDataCleared` notification fires.
- **Search availability polling**: Re-checks `TimeGate.searchAllowed()` every 30 seconds.

### 2. Episode List

- **Loading states**: Shows progress view while loading, error messages for failures, empty state for no episodes.
- **Episode rows**: Each row shows:
  - "Now Playing" indicator (if currently playing)
  - Episode title (amber if currently playing)
  - Playback status: "New" (amber), "Xm in" or "Xh Xm in" (amber, with resume position), or "Played" (dim)
  - Publication date and duration
  - Description (3-line limit, HTML-cleaned)
  - Play/Pause button with buffering indicator
  - Download controls: "Save Offline" / progress bar with cancel / "Available Offline" with remove option
- **Pull-to-refresh**: Fetches fresh episodes from the RSS feed.
- **Cached episodes**: Loads cached episodes instantly, then fetches updates in the background.
- **Shuffle button**: Toolbar button picks a random episode older than the configured minimum age (from this podcast only).
- **Skip intro**: Toolbar icon opens a menu to set a per-podcast intro skip (0/10/15/30/45/60/90/120 seconds) or use the global default. When an episode is played fresh (no saved position), playback starts at the configured offset. Stored in `LibraryData.podcastSkipSeconds`.
- **Error handling**: Specific messages for no internet, timeouts, HTML responses (not RSS), and generic failures. Cached episodes are shown even when the network fails.

### 3. Now Playing Bar

- **Persistent bar**: Appears at bottom of Library and Episode views when an episode is loaded.
- **Episode title**: Single-line, left-aligned.
- **Scrubber**: Full-width slider. Supports drag-to-scrub without audio jumping during drag.
- **Time labels**: Current time (left) and remaining time (right), monospaced digits.
- **Transport controls**:
  - **Noise cancellation toggle**: Ear icon (only visible when Lock Volume Range is enabled). Filled amber ear icon when NC is on, outline secondary when off. Switches between NC and non-NC volume profiles instantly.
  - **Sleep timer**: Moon icon opens a menu with 15/30/45/60 minute options. Active timer shows countdown in an amber capsule. Cancel option when active.
  - **Skip back 30s**
  - **Play/Pause**
  - **Skip forward 30s**
  - **Playback speed**: Menu with 1x, 1.25x, 1.5x, 1.75x, 2x options. Current speed shown in capsule badge.
- **Material background**: `.ultraThinMaterial` for subtle transparency.

### 4. Audio Playback (AudioPlayer)

- **Singleton**: `AudioPlayer.shared`, `@Observable`, `@MainActor`.
- **Playback**: Streams from URL or plays local downloaded file. Prioritizes local file if available.
- **Resume position**: Saves playback position every ~3 seconds and on pause/episode end. Resumes from saved position when replaying. Also persists the last-played episode GUID and feed URL so the resume card can restore it after app relaunch.
- **Fade-in**: 1.5-second gentle volume fade-in on play/resume (15 steps).
- **Auto-play next**: When enabled, automatically plays the next episode in the current list when one finishes. Configurable in Settings (default: on).
- **Episode completion**: Marks episode as "Played", resets position to 0, updates Now Playing info.
- **Buffering detection**: KVO on `AVPlayer.timeControlStatus` to show/hide buffering indicator.
- **Audio interruptions**: Pauses on interruption begin, resumes (if appropriate) on interruption end.
- **Playback speed**: Persisted across app launches via `AppSettings.playbackRate`. Restored on init.
- **Now Playing info**: Updates `MPNowPlayingInfoCenter` with title, artist (podcast name), elapsed time, duration, and playback rate.
- **Intro skip**: When playing an episode with no saved position, playback starts at the podcast's configured intro skip offset (per-podcast or global default). Uses `introSkipSeconds(for:)` to resolve the value. Default is 0 (off).

### 5. Remote Commands (Lock Screen & Headphones)

- **Play/Pause**: Standard play, pause, and toggle commands.
- **Skip forward/back**: 30-second skip in both directions.
- **Next track (double-press crown)**: Pauses current audio, speaks the podcast name and episode title, then plays the random episode. Uses `nextTrackCommand`. Only draws from podcasts selected in Settings.
- **Previous track (triple-press crown)**: Pauses current audio, speaks the current time aloud (e.g., "The time is 11:42 PM"), then resumes playback at the current playback rate. Uses `previousTrackCommand`.
- **Mutex**: Only one crown action can run at a time. If a double-press is in progress (speaking + loading), a triple-press is ignored, and vice versa. The lock clears when speech finishes.
- **Session claiming**: On launch, a 0.1-second silent WAV (`silence.wav`) plays at zero volume to claim the Now Playing session, so crown commands work immediately without needing to play a podcast first.
- **Spoken announcements**: Uses `AVSpeechSynthesizer` with the best available voice on the device (Premium > Enhanced > Default). Voice quality can be improved by downloading Premium voices in iOS Settings > Accessibility > Spoken Content > Voices.

### 6. Volume Control System

Three layers of volume control, each serving a different purpose:

#### 6a. In-App Volume Limit
- **What it controls**: `AVPlayer.volume` — the app's own audio output level relative to the system volume.
- **Range**: 10% – 100% (default: 100%).
- **Behavior**: Caps `player.volume` on all play paths (play, resume, toggle, fade-in, sleep timer fade-out, sleep timer cancel). Applied immediately when changed during playback.
- **Settings UI**: Slider + tappable percentage pill in Playback section.
- **Description**: "Caps in-app volume. Useful for sleep — keeps audio quiet even if your phone volume is high."

#### 6b. System Volume Cap & Floor (Noise Cancellation Profiles)
- **What it controls**: iOS system volume via a hidden `MPVolumeView` installed in the key window.
- **Two profiles**: Separate max (cap) and min (floor) values for Noise Cancellation On vs Off. The active profile is determined by a manual NC toggle.
  - **NC On**: `systemVolumeCapNC` / `systemVolumeFloorNC` (defaults: 20% / 10%)
  - **NC Off**: `systemVolumeCapNoNC` / `systemVolumeFloorNoNC` (defaults: 14% / 9%)
- **Mode switching**: Toggling NC mode in the Now Playing bar instantly swaps the active cap/floor and re-enforces. The NC toggle state is persisted across launches.
- **Range**: 0% – 100% (1% steps) for all four values.
- **When active**: During nighttime hours (8 PM – 8 AM) when "Lock Volume Range" toggle is on, OR at any time when "Always Enforce" is also enabled.
- **Enforcement**:
  - KVO observer on `AVAudioSession.outputVolume` detects changes in real-time.
  - If volume exceeds cap, immediately sets it back via the hidden `MPVolumeView` slider.
  - If volume drops below floor, pushes it back up.
  - Rapid enforcement: After a violation, polls every 50ms for 3 seconds to catch repeated button presses (e.g., holding volume–up on headphones while sleeping).
  - Enforced on app open (with 0.3s delay for volume view attachment).
  - Enforced on every play action.
  - `AppSettings.systemVolumeCap` and `AppSettings.systemVolumeFloor` are computed properties that return the correct NC or non-NC value based on the current `noiseCancellationOn` state. This keeps VolumeEnforcer logic unchanged.
- **Settings UI**: Two labeled groups when Lock Volume Range is on:
  - "Noise Cancellation On" (ear.fill icon, amber): Max Volume and Min Volume sliders with tappable percentage pills.
  - "Noise Cancellation Off" (ear icon, secondary): Max Volume and Min Volume sliders with tappable percentage pills.
  - Description: "Toggle noise cancellation mode from the now playing bar. Volume is enforced 8 PM – 8 AM, or always if enabled above."

#### System Volume Slider
- **Direct control**: `SystemVolumeSlider` (`UIViewRepresentable` wrapping `MPVolumeView`) in Settings for manual system volume adjustment.
- **Live percentage**: Shows current system volume as a percentage, updated via KVO observer.

#### Hidden MPVolumeView
- **Installation**: A hidden `MPVolumeView` is installed in the app's key window (offscreen, nearly transparent) at audio session setup. Its `UISlider` subview is cached for programmatic volume changes.
- **Why**: `MPVolumeView` must be in the view hierarchy for its slider to control system volume.

### 7. Sleep Timer

- **Options**: 15, 30, 45, or 60 minutes.
- **Volume fade-out**: In the last 30 seconds, volume linearly fades from the current `maxVolume` down to zero.
- **On completion**: Pauses playback, clears timer, restores volume to `maxVolume`.
- **Cancel**: Restores volume to `maxVolume` immediately.
- **UI**: Moon icon in Now Playing bar. Active timer shows countdown (mm:ss) in warm dim capsule.

### 8. Random Episode

- **Minimum age**: Configurable in Settings, 7 – 365 days (default: 60 days, 7-day steps).
- **Per-podcast shuffle**: Shuffle button in EpisodeListView toolbar picks a random episode older than the minimum age from the current podcast.
- **Global shuffle (headphone crown)**: Double-pressing the headphone crown (`nextTrackCommand`) picks a random episode older than the minimum age using a fair podcast rotation. Pauses current audio, speaks the podcast name and episode title, then plays.
- **Fair podcast rotation**: The crown random feature maintains a shuffled rotation queue of included podcast feed URLs (`crownPodcastRotation` in `LibraryData`). Each crown press picks the next podcast in the queue and selects a random eligible episode from it. When all podcasts have been used, the queue reshuffles for a new round. Podcasts with no eligible episodes are skipped without consuming a rotation slot. The rotation persists across app restarts.
- **Podcast selection**: In Settings under "Include in Random", users can toggle which podcasts are included in the crown's random episode pool. All podcasts are included by default. Excluded podcast feed URLs are stored via `AppSettings.randomExcludedFeedURLs`. Changes to exclusions are reflected in the rotation queue on next crown press.
- **Date filtering**: Uses pre-computed `pubDateTimestamp` (stored as `TimeInterval` on `Episode` at RSS parse time) for fast comparison against the age cutoff. Episodes with no timestamp are included (assumed old).

### 9. Podcast Search

- **Source**: iTunes Search API (`https://itunes.apple.com/search?media=podcast&term=...`).
- **Time-gated**: Only available 8 AM – 8 PM (controlled by `TimeGate.searchAllowed()`).
- **Search results**: Show artwork (56x56, rounded), title, artist, episode count, genre, content rating.
- **Add button**: Plus icon to add; checkmark shown if already in library.
- **Duplicate detection**: Checks by feed URL.
- **Error handling**: Specific UI for no internet vs generic search failure.

### 10. Add Feed by URL

- **Validation**: Checks for valid URL with scheme.
- **Duplicate detection**: Checks by normalized URL (lowercased, trailing slash stripped) and by podcast title.
- **Loading overlay**: Semi-transparent overlay with progress spinner and "Loading feed..." text.
- **RSS parsing**: Fetches feed, parses with `RSSParser`, extracts title and artwork from first episode.
- **Error handling**: Specific message for no internet, generic message for parse failures.

### 11. Time Gate

- **Search hours**: 8:00 AM – 7:59 PM local time.
- **Nighttime hours**: 8:00 PM – 7:59 AM local time (inverse of search hours).
- **Used by**: Search visibility, screen dimming, system volume enforcement.

### 12. Screen Dimming

- **When**: Active phase during nighttime hours.
- **Level**: Reduces screen brightness to 30% of current level (minimum 5%).
- **Restore**: Restores previous brightness when app goes to background/inactive.
- **Saved state**: Stores previous brightness to avoid compounding dimming.

### 13. Downloads

- **Background session**: `URLSessionConfiguration.background` with identifier `com.quietcast.downloads`.
- **Progress tracking**: Per-episode progress (0–1) in `activeDownloads` dictionary.
- **File storage**: Downloaded episodes saved as `download_{sanitized_guid}.mp3` in Documents.
- **Download states**: Not downloaded → Downloading (with progress) → Downloaded.
- **Cancel**: Cancels active task, removes partial file, cleans up tracking state.
- **Remove**: Deletes local file, removes from `downloadedGUIDs`, saves state.
- **Cancel all for podcast**: `cancelAllDownloads(for:)` — uses cached episode data (no network call) to find and cancel all active downloads for a podcast.
- **Cancel all active**: `cancelAllActiveDownloads()` — cancels every in-flight download task and clears all tracking state. Used by Clear All Data.
- **Thread safety**: Download delegate copies file to temp location synchronously, then moves to final destination on MainActor.

### 14. Persistence

- **App Group shared container**: All file storage uses the App Group container (`group.com.quietcast.shared`) so multiple app targets can share data. Falls back to the app's Documents directory if the App Group is not configured.
- **Shared UserDefaults**: `AppSettings` uses `UserDefaults(suiteName: "group.com.quietcast.shared")` instead of `.standard`, so preferences are shared across app targets.
- **Library file**: `library.json` in the shared container. Contains podcasts array, downloaded GUIDs, playback positions, played episode GUIDs, last-played episode GUID and feed URL.
- **Episode cache**: Per-feed cache files (`cache_{sanitized_url}.json`) in the shared container.
- **In-memory cache**: Avoids repeated disk reads; `cachedLibrary` is updated in memory and periodically flushed.
- **Debounced saves**: 500ms debounce window for rapid updates. Playback position saves flush immediately to disk to survive force-quits. Disk write failures are logged via `os.Logger`.
- **Flush on background**: `flushToDisk()` called when app enters `.inactive` or `.background` to prevent data loss.
- **Remove all data for podcast**: `removeAllData(for:)` deletes downloaded files, episode cache, playback positions, and played markers — all locally, no network call required.
- **Clear all data**: Pauses playback, deletes library JSON, all download files, and all cache files. Cancels all active download tasks via `DownloadManager.cancelAllActiveDownloads()`.
- **Episode cache logging**: Episode cache write failures are logged via `os.Logger`.

### 15. RSS Parsing

- **Encoding**: Tries UTF-8, falls back to Latin-1, then lossy UTF-8.
- **XML cleaning**: Strips invalid XML 1.0 control characters. Forces UTF-8 encoding declaration.
- **Parsed fields**: guid, title, description (HTML-cleaned), pubDate (formatted to medium date), pubDateTimestamp (TimeInterval, computed at parse time), duration, audio URL (from `<enclosure>`), podcast title, artwork URL.
- **Error tolerance**: Returns whatever episodes were parsed before any error.
- **Date formatting**: Converts RFC 2822 dates (`EEE, dd MMM yyyy HH:mm:ss Z`) to localized medium format using `en_US_POSIX` locale for parsing. Also stores the parsed `Date` as a `TimeInterval` (`pubDateTimestamp`) for efficient age-based filtering.

### 16. HTML Cleaning

- Strips HTML tags.
- Removes URLs (`http://`, `https://`, `www.`).
- Decodes named HTML entities (`&amp;`, `&lt;`, `&gt;`, `&quot;`, `&apos;`, `&nbsp;`, etc.).
- Decodes numeric HTML entities (`&#NNN;`).
- Collapses whitespace.

### 17. Settings

Organized into sections:

#### Playback
- Auto-Play Next Episode toggle (default: on)
- Volume Limit slider (10% – 100%) with tappable percentage pill
- Skip Intro menu (0/10/15/30/45/60/90/120 seconds, default: Off). Sets the global default intro skip. Per-podcast overrides are set from the episode list toolbar.

#### System Volume Cap
- Lock Volume Range toggle
- Always Enforce toggle — shown when Lock Volume Range is on. Enforces volume range even outside nighttime hours. On by default.
- **Noise Cancellation On** group (ear.fill icon, amber) — shown when toggle is on:
  - Max Volume slider (0% – 100%, 1% steps) with tappable percentage pill
  - Min Volume slider (0% — 100%, 1% steps) with tappable percentage pill
- **Noise Cancellation Off** group (ear icon, secondary) — shown when toggle is on:
  - Max Volume slider (0% – 100%, 1% steps) with tappable percentage pill
  - Min Volume slider (0% – 100%, 1% steps) with tappable percentage pill
- System Volume slider (native `MPVolumeView`) with live percentage display

#### Random Episode
- Minimum Age slider (7 – 365 days, 7-day steps)
- Include in Random: Multi-select list of all subscribed podcasts with checkmark toggles for crown random episode pool
- Description includes headphone crown double-press instruction

#### How QuietCast Works
- Info items for Search Hours, Sleep Timer, Warm Display, Fade-In, and Voice Quality
- Voice Quality item explains how to download Premium voices for better spoken announcements

#### Data
- Clear All Data button with destructive confirmation. Pauses playback, clears persistence, snapshots active download GUIDs before cancellation (avoids dictionary mutation during iteration), resets download tracking state.

#### About
- App version number
- "QuietCast — a calm podcast player for bedtime." footer

### 18. Tappable Percentage Pills

- **Appearance**: Amber text in a capsule-shaped badge with amber tint background. "tap to edit" hint text to the left.
- **Tap behavior**: Flips to an inline text field with number pad keyboard and a "Done" button.
- **Validation**: Parses integer input, clamps to the valid range, commits on Done or Submit.
- **Used on**: Volume Limit, NC On Max/Min Volume, NC Off Max/Min Volume sliders.

### 19. Build Info

- **Source**: Executable file's modification date (`FileManager.attributesOfItem`).
- **Format**: Medium date + short time (e.g., "Jun 5, 2026 at 3:42 PM").
- **Display**: Bottom of the library list, quaternary foreground style.

### 20. Spoken Announcements

- **Engine**: `AVSpeechSynthesizer` with `AVSpeechSynthesizerDelegate` for completion callbacks.
- **Voice selection**: Automatically selects the highest quality voice available for the user's language (Premium > Enhanced > Default). Users can improve voice quality by downloading Premium voices in iOS Settings > Accessibility > Spoken Content > Voices.
- **Volume**: Speech volume capped at 80% or the in-app volume limit, whichever is lower.
- **Used by**:
  - Double-press crown: Speaks podcast name and episode title before playing.
  - Triple-press crown: Speaks current time (e.g., "The time is 11:42 PM").
- **Audio coordination**: Pauses current playback before speaking, resumes (or starts new episode) after speech finishes via delegate callback.
- **Mutex**: `isCrownActionActive` flag prevents concurrent crown actions. Set on entry, cleared when speech finishes.
- **Callback safety**: If `speak()` is called while a previous announcement is still pending, the previous callback is fired before being replaced, preventing the crown mutex from getting stuck.

### 21. Now Playing Session Claiming

- **Purpose**: Ensures headphone crown commands work immediately on app launch without needing to play a podcast first.
- **Mechanism**: A 0.1-second silent WAV file (`silence.wav`) plays at full volume (the file contains silence, so nothing is audible) during `setupAudioSession()`. Now Playing info is also set explicitly (`MPNowPlayingInfoCenter`) with a non-zero playback rate so iOS registers the app as the active Now Playing app.
- **Cleanup**: Silent player reference is released after 2 seconds.
- **Side effect**: QuietCast briefly appears in the lock screen Now Playing widget before any real audio plays.

---

## Data Models

### Podcast
```swift
struct Podcast: Codable, Identifiable, Equatable, Hashable {
    var id: String { feedURL }
    let title: String
    let author: String
    let artworkURL: String
    let feedURL: String
}
```
- Identity based on `feedURL`.
- `Hashable` conformance for `navigationDestination(item:)`.

### Episode
```swift
struct Episode: Codable, Identifiable, Equatable {
    var id: String { guid }
    let guid: String
    let title: String
    let descriptionText: String
    let pubDate: String
    let pubDateTimestamp: Double?
    let duration: String
    let audioURL: String
    let podcastTitle: String
    let artworkURL: String
}
```
- Identity based on `guid`. Falls back to `audioURL` if guid is empty.

### LibraryData
```swift
struct LibraryData: Codable {
    var podcasts: [Podcast]
    var downloadedEpisodeGUIDs: Set<String>
    var playbackPositions: [String: Double]
    var playedEpisodeGUIDs: Set<String>
    var lastPlayedEpisodeGUID: String?
    var lastPlayedFeedURL: String?
    var crownPodcastRotation: [String]
    var podcastSkipSeconds: [String: Int] // feedURL -> custom skip seconds
}
```

---

## UserDefaults Keys (via `AppSettings`)

All `UserDefaults` access is centralized through the `AppSettings` enum using the shared App Group suite (`group.com.quietcast.shared`). No other file reads or writes `UserDefaults` directly.

| Key | Type | Default | Purpose |
|-----|------|---------|---------|
| `autoPlayNext` | Bool | `true` | Auto-play next episode |
| `maxVolume` | Float | `1.0` | In-app volume limit |
| `noiseCancellationOn` | Bool | `false` | Current noise cancellation mode |
| `systemVolumeCapNC` | Float | `0.20` | Max system volume when NC is on (20%) |
| `systemVolumeFloorNC` | Float | `0.10` | Min system volume when NC is on (10%) |
| `systemVolumeCapNoNC` | Float | `0.14` | Max system volume when NC is off (14%) |
| `systemVolumeFloorNoNC` | Float | `0.09` | Min system volume when NC is off (9%) |
| `systemVolumeCapEnabled` | Bool | `true` | Lock Volume Range toggle |
| `randomEpisodeAgeDays` | Int | `60` | Minimum age for random episode |
| `randomExcludedFeedURLs` | [String] | `[]` | Feed URLs excluded from crown random episode |
| `playbackRate` | Float | `1.0` | Playback speed (persisted across launches) |
| `volumeRangeAlwaysOn` | Bool | `true` | Enforce volume range at all times (not just nighttime) |
| `defaultSkipIntroSeconds` | Int | `0` | Default intro skip in seconds (0 = off). Per-podcast overrides stored in `LibraryData.podcastSkipSeconds`. |

---

## App Lifecycle

1. **Launch**: `AudioPlayer.shared.setupAudioSession()` — configures `AVAudioSession`, delegates to `RemoteCommandHandler` for remote commands, `VolumeEnforcer` for hidden `MPVolumeView` and KVO observation, plays silent clip to claim Now Playing session.
2. **Active (nighttime)**: Dims screen to 30%. Enforces system volume bounds (cap and floor) with 0.3s delay. Volume enforcement also runs during daytime if "Always Enforce" is on.
3. **Inactive/Background**: Flushes pending persistence saves to disk. Restores screen brightness.
4. **Playback start**: Enforces system volume cap (nighttime only). Fades in audio over 1.5 seconds.
5. **Every ~3 seconds during playback**: Saves current position and last-played episode info.
6. **Episode end**: Marks played, resets position, auto-plays next (if enabled).
7. **App relaunch (no active playback)**: Resume card in library shows last-played episode from disk cache with saved position.

---

## Design Principles

1. **Sleep-first**: Every feature considers the sleeping user. Volume can't spike. Screen stays dim. No bright colors.
2. **Minimal engagement**: Time-gated search discourages late-night browsing. No social features, no recommendations beyond what's subscribed.
3. **Offline-ready**: Episodes can be downloaded for offline playback. Cached episode lists load instantly.
4. **Fail gracefully**: Network errors show cached content. Parse errors return partial results. Invalid dates are included rather than excluded.
5. **No data loss**: Debounced saves with flush-on-background prevent position loss on app suspension.
