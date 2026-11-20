import Foundation
import Observation
import os

@Observable
@MainActor
final class DownloadManager {
    static let shared = DownloadManager()

    var activeDownloads: [String: Double] = [:] // guid -> progress 0..1
    var downloadedGUIDs: Set<String> = []

    /// Maps URLSessionTask identifiers to episode GUIDs
    var taskToGUID: [Int: String] = [:]
    /// Maps episode GUIDs to destination file URLs
    var guidToDestURL: [String: URL] = [:]
    /// Maps episode GUIDs to their download tasks (for cancellation)
    private var guidToTask: [String: URLSessionDownloadTask] = [:]

    static let logger = Logger(subsystem: "com.quietcast", category: "DownloadManager")
    private var sessionDelegate: DownloadSessionDelegate!
    private var backgroundSession: URLSession!

    private init() {
        let library = PersistenceManager.shared.loadLibrary()
        downloadedGUIDs = library.downloadedEpisodeGUIDs

        sessionDelegate = DownloadSessionDelegate(manager: self)
        let config = URLSessionConfiguration.background(withIdentifier: "com.quietcast.downloads")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = false
        backgroundSession = URLSession(configuration: config, delegate: sessionDelegate, delegateQueue: nil)
    }

    func isDownloaded(_ episode: Episode) -> Bool {
        downloadedGUIDs.contains(episode.guid) && PersistenceManager.shared.isDownloaded(episode)
    }

    func isDownloading(_ episode: Episode) -> Bool {
        activeDownloads[episode.guid] != nil
    }

    func progress(for episode: Episode) -> Double {
        activeDownloads[episode.guid] ?? 0
    }

    func download(episode: Episode) {
        guard !isDownloaded(episode), !isDownloading(episode) else { return }
        guard let url = URL(string: episode.audioURL) else { return }

        activeDownloads[episode.guid] = 0
        let destURL = PersistenceManager.shared.localFileURL(for: episode)
        guidToDestURL[episode.guid] = destURL

        let task = backgroundSession.downloadTask(with: url)
        taskToGUID[task.taskIdentifier] = episode.guid
        guidToTask[episode.guid] = task
        task.resume()
    }

    func cancelDownload(for episode: Episode) {
        let guid = episode.guid
        // Cancel the active task
        if let task = guidToTask[guid] {
            task.cancel()
        }
        // Clean up tracking state
        activeDownloads.removeValue(forKey: guid)
        guidToDestURL.removeValue(forKey: guid)
        guidToTask.removeValue(forKey: guid)
        // Remove any partially written file
        let fileURL = PersistenceManager.shared.localFileURL(for: episode)
        try? FileManager.default.removeItem(at: fileURL)
    }

    func removeDownload(for episode: Episode) {
        let fileURL = PersistenceManager.shared.localFileURL(for: episode)
        try? FileManager.default.removeItem(at: fileURL)
        downloadedGUIDs.remove(episode.guid)
        saveDownloadState()
    }

    /// Cancel any active downloads belonging to a podcast and update in-memory state
    func cancelAllDownloads(for podcast: Podcast) {
        let cachedEpisodes = PersistenceManager.shared.cachedEpisodes(for: podcast.feedURL) ?? []
        let guids = Set(cachedEpisodes.map { $0.guid })

        for guid in guids {
            if let task = guidToTask[guid] {
                task.cancel()
            }
            activeDownloads.removeValue(forKey: guid)
            guidToDestURL.removeValue(forKey: guid)
            guidToTask.removeValue(forKey: guid)
        }

        // Also remove GUIDs from the in-memory downloaded set (files are deleted by PersistenceManager)
        downloadedGUIDs.subtract(guids)
    }

    func cleanupTask(for guid: String, taskId: Int) {
        taskToGUID.removeValue(forKey: taskId)
        guidToDestURL.removeValue(forKey: guid)
        guidToTask.removeValue(forKey: guid)
    }

    /// Cancel all active download tasks and clear tracking state.
    func cancelAllActiveDownloads() {
        for (_, task) in guidToTask {
            task.cancel()
        }
        activeDownloads.removeAll()
        guidToTask.removeAll()
        guidToDestURL.removeAll()
        taskToGUID.removeAll()
    }

    func saveDownloadState() {
        var library = PersistenceManager.shared.loadLibrary()
        library.downloadedEpisodeGUIDs = downloadedGUIDs
        PersistenceManager.shared.saveLibrary(library)
    }
}

// MARK: - URLSession Delegate (separate class to avoid @Observable + NSObject conflict)

private class DownloadSessionDelegate: NSObject, URLSessionDownloadDelegate {
    private nonisolated let logger = Logger(subsystem: "com.quietcast", category: "DownloadManager")
    weak var manager: DownloadManager?

    init(manager: DownloadManager) {
        self.manager = manager
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let taskId = downloadTask.taskIdentifier

        // Must move file synchronously — system deletes it when this method returns
        let fm = FileManager.default

        // We need to read from the manager, but it's MainActor-isolated.
        // Copy the file to a safe temp location first, then update state on MainActor.
        let tempDir = fm.temporaryDirectory
        let tempCopy = tempDir.appendingPathComponent(UUID().uuidString + ".tmp")
        do {
            try fm.moveItem(at: location, to: tempCopy)
        } catch {
            logger.error("Failed to save downloaded file: \(error.localizedDescription)")
            return
        }

        Task { @MainActor in
            guard let manager = self.manager else { return }
            guard let guid = manager.taskToGUID[taskId] else { return }
            guard let destURL = manager.guidToDestURL[guid] else { return }

            let fm = FileManager.default
            try? fm.removeItem(at: destURL)
            do {
                try fm.moveItem(at: tempCopy, to: destURL)
                manager.activeDownloads.removeValue(forKey: guid)
                manager.downloadedGUIDs.insert(guid)
                manager.saveDownloadState()
            } catch {
                manager.activeDownloads.removeValue(forKey: guid)
                try? fm.removeItem(at: tempCopy)
                self.logger.error("Failed to move download for \(guid): \(error.localizedDescription)")
            }
            manager.cleanupTask(for: guid, taskId: taskId)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let taskId = downloadTask.taskIdentifier
        Task { @MainActor in
            guard let manager = self.manager,
                  let guid = manager.taskToGUID[taskId] else { return }
            if totalBytesExpectedToWrite > 0 {
                let pct = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
                manager.activeDownloads[guid] = min(pct, 1.0)
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard error != nil else { return }
        let taskId = task.taskIdentifier
        Task { @MainActor in
            guard let manager = self.manager else { return }
            if let guid = manager.taskToGUID[taskId] {
                manager.activeDownloads.removeValue(forKey: guid)
                manager.cleanupTask(for: guid, taskId: taskId)
            }
        }
    }
}
