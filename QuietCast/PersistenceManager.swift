import Foundation
import os

struct LibraryData: Codable {
    var podcasts: [Podcast]
    var downloadedEpisodeGUIDs: Set<String>
    var playbackPositions: [String: Double]
    var playedEpisodeGUIDs: Set<String>
    var lastPlayedEpisodeGUID: String?
    var lastPlayedFeedURL: String?
    var crownPodcastRotation: [String]
    var podcastSkipSeconds: [String: Int] // feedURL -> custom skip duration in seconds

    init(podcasts: [Podcast] = [],
         downloadedEpisodeGUIDs: Set<String> = [],
         playbackPositions: [String: Double] = [:],
         playedEpisodeGUIDs: Set<String> = [],
         lastPlayedEpisodeGUID: String? = nil,
         lastPlayedFeedURL: String? = nil,
         crownPodcastRotation: [String] = [],
         podcastSkipSeconds: [String: Int] = [:]) {
        self.podcasts = podcasts
        self.downloadedEpisodeGUIDs = downloadedEpisodeGUIDs
        self.playbackPositions = playbackPositions
        self.playedEpisodeGUIDs = playedEpisodeGUIDs
        self.lastPlayedEpisodeGUID = lastPlayedEpisodeGUID
        self.lastPlayedFeedURL = lastPlayedFeedURL
        self.crownPodcastRotation = crownPodcastRotation
        self.podcastSkipSeconds = podcastSkipSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        podcasts = try container.decode([Podcast].self, forKey: .podcasts)
        downloadedEpisodeGUIDs = try container.decode(Set<String>.self, forKey: .downloadedEpisodeGUIDs)
        playbackPositions = try container.decodeIfPresent([String: Double].self, forKey: .playbackPositions) ?? [:]
        playedEpisodeGUIDs = try container.decodeIfPresent(Set<String>.self, forKey: .playedEpisodeGUIDs) ?? []
        lastPlayedEpisodeGUID = try container.decodeIfPresent(String.self, forKey: .lastPlayedEpisodeGUID)
        lastPlayedFeedURL = try container.decodeIfPresent(String.self, forKey: .lastPlayedFeedURL)
        crownPodcastRotation = try container.decodeIfPresent([String].self, forKey: .crownPodcastRotation) ?? []
        podcastSkipSeconds = try container.decodeIfPresent([String: Int].self, forKey: .podcastSkipSeconds) ?? [:]
    }
}

final class PersistenceManager {
    static let shared = PersistenceManager()
    static let appGroupID = "group.com.quietcast.shared"

    private let fileManager = FileManager.default
    private let logger = Logger(subsystem: "com.quietcast", category: "PersistenceManager")

    /// In-memory cache — avoids repeated disk reads
    private var cachedLibrary: LibraryData?
    private var saveTask: Task<Void, Never>?

    private var libraryFileURL: URL {
        documentsDirectory().appendingPathComponent("library.json")
    }

    func loadLibrary() -> LibraryData {
        if let cached = cachedLibrary {
            return cached
        }
        let url = libraryFileURL
        guard let data = try? Data(contentsOf: url) else {
            logger.info("No library file found at \(url.path) — starting fresh.")
            let empty = LibraryData(podcasts: [], downloadedEpisodeGUIDs: [])
            cachedLibrary = empty
            return empty
        }
        do {
            let library = try JSONDecoder().decode(LibraryData.self, from: data)
            logger.info("Loaded library with \(library.podcasts.count) podcasts from \(url.path)")
            cachedLibrary = library
            return library
        } catch {
            logger.error("Failed to decode library.json: \(error.localizedDescription)")
            let empty = LibraryData(podcasts: [], downloadedEpisodeGUIDs: [])
            cachedLibrary = empty
            return empty
        }
    }

    func saveLibrary(_ library: LibraryData) {
        cachedLibrary = library
        scheduleSave()
    }

    /// Debounced disk write — coalesces rapid saves (e.g. position updates) into one write
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second debounce
            guard !Task.isCancelled else { return }
            self.writeToDisk()
        }
    }

    /// Immediately write to disk (used by clearAllData and for critical saves)
    func flushToDisk() {
        saveTask?.cancel()
        writeToDisk()
    }

    private func writeToDisk() {
        guard let library = cachedLibrary else { return }
        do {
            let data = try JSONEncoder().encode(library)
            try data.write(to: libraryFileURL, options: .atomic)
        } catch {
            logger.error("Failed to write library to disk: \(error.localizedDescription)")
        }
    }

    func documentsDirectory() -> URL {
        if let groupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID) {
            return groupURL
        }
        logger.warning("App Group container not available for '\(Self.appGroupID)' — falling back to Documents directory. Data will not persist across reinstalls.")
        return fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    func localFileURL(for episode: Episode) -> URL {
        let safeName = episode.guid
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return documentsDirectory().appendingPathComponent("download_\(safeName).mp3")
    }

    func isDownloaded(_ episode: Episode) -> Bool {
        fileManager.fileExists(atPath: localFileURL(for: episode).path)
    }

    func savePlaybackPosition(_ seconds: Double, for guid: String) {
        var library = loadLibrary()
        library.playbackPositions[guid] = seconds
        cachedLibrary = library
        flushToDisk()
    }

    func playbackPosition(for guid: String) -> Double {
        loadLibrary().playbackPositions[guid] ?? 0
    }

    func markPlayed(_ guid: String) {
        var library = loadLibrary()
        library.playedEpisodeGUIDs.insert(guid)
        saveLibrary(library)
    }

    func isPlayed(_ guid: String) -> Bool {
        loadLibrary().playedEpisodeGUIDs.contains(guid)
    }

    // MARK: - Last Played Episode

    func saveLastPlayedEpisode(guid: String, feedURL: String) {
        var library = loadLibrary()
        library.lastPlayedEpisodeGUID = guid
        library.lastPlayedFeedURL = feedURL
        cachedLibrary = library
        scheduleSave()
    }

    /// Loads the last played episode from the episode cache, if available.
    func loadLastPlayedEpisode() -> Episode? {
        let library = loadLibrary()
        guard let guid = library.lastPlayedEpisodeGUID,
              let feedURL = library.lastPlayedFeedURL,
              let episodes = cachedEpisodes(for: feedURL) else {
            return nil
        }
        return episodes.first { $0.guid == guid }
    }

    // MARK: - Per-Podcast Skip Duration

    func skipSeconds(for feedURL: String) -> Int? {
        loadLibrary().podcastSkipSeconds[feedURL]
    }

    func setSkipSeconds(_ seconds: Int?, for feedURL: String) {
        var library = loadLibrary()
        library.podcastSkipSeconds[feedURL] = seconds
        saveLibrary(library)
    }

    // MARK: - Episode Cache

    private func episodeCacheURL(for feedURL: String) -> URL {
        let safeName = feedURL
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return documentsDirectory().appendingPathComponent("cache_\(safeName).json")
    }

    func cachedEpisodes(for feedURL: String) -> [Episode]? {
        let url = episodeCacheURL(for: feedURL)
        guard let data = try? Data(contentsOf: url),
              let episodes = try? JSONDecoder().decode([Episode].self, from: data) else {
            return nil
        }
        return episodes
    }

    func cacheEpisodes(_ episodes: [Episode], for feedURL: String) {
        let url = episodeCacheURL(for: feedURL)
        do {
            let data = try JSONEncoder().encode(episodes)
            try data.write(to: url, options: .atomic)
        } catch {
            logger.error("Failed to cache episodes for \(feedURL): \(error.localizedDescription)")
        }
    }

    /// Remove all local data associated with a podcast: cached episodes, downloaded audio, and playback state.
    func removeAllData(for podcast: Podcast) {
        let feedURL = podcast.feedURL

        // Find episode GUIDs from the local cache so we can clean up without a network call
        let cachedEpisodes = cachedEpisodes(for: feedURL) ?? []
        let guids = Set(cachedEpisodes.map { $0.guid })

        var library = loadLibrary()

        // Remove downloaded files and tracked GUIDs
        for episode in cachedEpisodes {
            let fileURL = localFileURL(for: episode)
            try? fileManager.removeItem(at: fileURL)
        }
        library.downloadedEpisodeGUIDs.subtract(guids)

        // Remove playback positions and played markers for these episodes
        for guid in guids {
            library.playbackPositions.removeValue(forKey: guid)
            library.playedEpisodeGUIDs.remove(guid)
        }

        // Remove the episode cache file
        let cacheURL = episodeCacheURL(for: feedURL)
        try? fileManager.removeItem(at: cacheURL)

        saveLibrary(library)
    }

    func clearAllData() {
        cachedLibrary = nil
        saveTask?.cancel()

        // Delete library JSON
        try? fileManager.removeItem(at: libraryFileURL)

        // Delete all downloaded episode files and cached episodes
        let docs = documentsDirectory()
        if let files = try? fileManager.contentsOfDirectory(atPath: docs.path) {
            for file in files where file.hasPrefix("download_") || file.hasPrefix("cache_") {
                try? fileManager.removeItem(at: docs.appendingPathComponent(file))
            }
        }
    }
}
