import MediaPlayer

/// Configures MPRemoteCommandCenter handlers and manages crown action state.
@MainActor
final class RemoteCommandHandler {
    static let shared = RemoteCommandHandler()

    /// Prevents concurrent crown actions (double-press and triple-press).
    private(set) var isCrownActionActive = false

    /// Release the crown mutex without running the speech completion.
    /// Used when speech is stopped and that completion is discarded.
    func cancelCrownAction() {
        isCrownActionActive = false
    }

    private init() {}

    func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { _ in
            Task { @MainActor in
                AudioPlayer.shared.togglePlayPause()
            }
            return .success
        }

        center.pauseCommand.addTarget { _ in
            Task { @MainActor in
                AudioPlayer.shared.pause()
            }
            return .success
        }

        center.togglePlayPauseCommand.addTarget { _ in
            Task { @MainActor in
                AudioPlayer.shared.togglePlayPause()
            }
            return .success
        }

        let skipInterval = NSNumber(value: AppSettings.skipIntervalSeconds)
        center.skipForwardCommand.preferredIntervals = [skipInterval]
        center.skipForwardCommand.addTarget { _ in
            Task { @MainActor in
                AudioPlayer.shared.skipForward()
            }
            return .success
        }

        center.skipBackwardCommand.preferredIntervals = [skipInterval]
        center.skipBackwardCommand.addTarget { _ in
            Task { @MainActor in
                AudioPlayer.shared.skipBackward()
            }
            return .success
        }

        // Double-press crown/AirPods plays a random old episode
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.playRandomOldEpisode()
            }
            return .success
        }

        // Triple-press crown/AirPods speaks the current time
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.speakCurrentTime()
            }
            return .success
        }
    }

    /// Speak the current time aloud, pausing audio during speech.
    func speakCurrentTime() {
        guard !isCrownActionActive else { return }
        isCrownActionActive = true
        let wasPlaying = AudioPlayer.shared.isPlaying
        if wasPlaying { AudioPlayer.shared.pausePlayback() }

        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        let timeString = formatter.string(from: Date())
        SpeechAnnouncer.shared.speak("The time is \(timeString)") { [weak self] in
            Task { @MainActor [weak self] in
                self?.isCrownActionActive = false
                if wasPlaying { AudioPlayer.shared.resumePlayback() }
            }
        }
    }

    /// Pick a random episode using fair podcast rotation, then play it.
    func playRandomOldEpisode() {
        guard !isCrownActionActive else { return }
        isCrownActionActive = true
        let ageDays = AppSettings.randomEpisodeAgeDays
        let cutoff = Calendar.current.date(byAdding: .day, value: -ageDays, to: Date()) ?? Date()
        let cutoffTimestamp = cutoff.timeIntervalSince1970
        let excludedFeedURLs = Set(AppSettings.randomExcludedFeedURLs)

        let persistence = PersistenceManager.shared
        var library = persistence.loadLibrary()

        // Get included podcast feed URLs
        let includedFeedURLs = Set(library.podcasts
            .map(\.feedURL)
            .filter { !excludedFeedURLs.contains($0) })

        // Clean rotation: remove feed URLs no longer in the included set
        var rotation = library.crownPodcastRotation.filter { includedFeedURLs.contains($0) }

        // If rotation is empty, start a new shuffled round
        if rotation.isEmpty {
            rotation = Array(includedFeedURLs).shuffled()
        }

        // Walk the rotation to find a podcast with eligible episodes
        var selectedEpisode: Episode?
        var selectedFeedURL: String?
        while !rotation.isEmpty {
            let feedURL = rotation.removeFirst()
            guard let episodes = persistence.cachedEpisodes(for: feedURL) else { continue }
            let eligible = episodes.filter { episode in
                guard let timestamp = episode.pubDateTimestamp else { return true }
                return timestamp < cutoffTimestamp
            }
            if let episode = eligible.randomElement() {
                selectedEpisode = episode
                selectedFeedURL = feedURL
                break
            }
        }

        // Save updated rotation
        library.crownPodcastRotation = rotation
        persistence.saveLibrary(library)

        guard let random = selectedEpisode else {
            isCrownActionActive = false
            return
        }
        let wasPlaying = AudioPlayer.shared.isPlaying
        if wasPlaying { AudioPlayer.shared.pausePlayback() }
        SpeechAnnouncer.shared.speak("\(random.podcastTitle). \(random.title)") { [weak self] in
            Task { @MainActor [weak self] in
                self?.isCrownActionActive = false
                AudioPlayer.shared.currentFeedURL = selectedFeedURL
                AudioPlayer.shared.play(episode: random)
            }
        }
    }
}
