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

    /// Called once the system has delivered background-session events after relaunch.
    var backgroundEventsCompletionHandler: (() -> Void)?

    static let logger = Logger(subsystem: "com.quietcast", category: "DownloadManager")
    private var sessionDelegate: DownloadSessionDelegate!
    private var backgroundSession: URLSession!

    /// Set before `shared` is created when iOS relaunches the app for a background transfer.
    private static var pendingBackgroundCompletion: (() -> Void)?
    private static weak var existing: DownloadManager?

    /// Store the system's completion handler, then make sure the background session exists.
    static func connectBackgroundSession(_ completion: @escaping () -> Void) {
        if let existing {
            existing.backgroundEventsCompletionHandler = completion
        } else {
            pendingBackgroundCompletion = completion
            _ = shared
        }
    }

    private init() {
        let library = PersistenceManager.shared.loadLibrary()
        downloadedGUIDs = library.downloadedEpisodeGUIDs
        Self.sweepIncomingDirectory()

        backgroundEventsCompletionHandler = Self.pendingBackgroundCompletion
        Self.pendingBackgroundCompletion = nil
        Self.existing = self

        sessionDelegate = DownloadSessionDelegate(manager: self)
        let config = URLSessionConfiguration.background(withIdentifier: "com.quietcast.downloads")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        backgroundSession = URLSession(configuration: config, delegate: sessionDelegate, delegateQueue: nil)
        restoreTasksFromSession()
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
        // Persisted by the background session and still available after relaunch,
        // when the in-memory task maps are empty.
        task.taskDescription = episode.guid
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

    /// Rebuild in-memory maps from tasks the system kept across relaunch.
    private func restoreTasksFromSession() {
        backgroundSession.getAllTasks { [weak self] tasks in
            Task { @MainActor in
                guard let self else { return }
                for task in tasks {
                    guard let guid = Self.normalizedGUID(task.taskDescription) else { continue }
                    self.taskToGUID[task.taskIdentifier] = guid
                    if let downloadTask = task as? URLSessionDownloadTask {
                        self.guidToTask[guid] = downloadTask
                    }
                    if self.guidToDestURL[guid] == nil {
                        self.guidToDestURL[guid] = PersistenceManager.shared.localFileURL(forEpisodeGUID: guid)
                    }
                    if self.activeDownloads[guid] == nil {
                        self.activeDownloads[guid] = 0
                    }
                }
            }
        }
    }

    nonisolated fileprivate static func normalizedGUID(_ raw: String?) -> String? {
        let guid = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return guid.isEmpty ? nil : guid
    }

    /// Files moved out of the system download location before we know their destination.
    nonisolated fileprivate static func incomingDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quietcast-incoming", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Drop leftovers from a previous launch. A finished download is moved to its
    /// final path before the delegate returns, so anything still here is unusable.
    private static func sweepIncomingDirectory() {
        let directory = incomingDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
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
        let describedGUID = DownloadManager.normalizedGUID(downloadTask.taskDescription)
        let fm = FileManager.default

        // The system deletes `location` when this method returns. If we know the
        // episode, move it to the final path now so a relaunch with empty maps
        // still keeps the file. Otherwise park it in our incoming directory.
        if let guid = describedGUID {
            let destURL = PersistenceManager.shared.localFileURL(forEpisodeGUID: guid)
            do {
                try? fm.removeItem(at: destURL)
                try fm.moveItem(at: location, to: destURL)
            } catch {
                logger.error("Failed to save downloaded file for \(guid): \(error.localizedDescription)")
                Task { @MainActor in
                    self.finishTracking(guid: guid, taskId: taskId, saved: false)
                }
                return
            }
            Task { @MainActor in
                self.finishTracking(guid: guid, taskId: taskId, saved: true)
            }
            return
        }

        let tempCopy = DownloadManager.incomingDirectory().appendingPathComponent(UUID().uuidString + ".tmp")
        do {
            try fm.moveItem(at: location, to: tempCopy)
        } catch {
            logger.error("Failed to save downloaded file: \(error.localizedDescription)")
            return
        }

        Task { @MainActor in
            let removeTemp = {
                try? FileManager.default.removeItem(at: tempCopy)
            }
            guard let manager = self.manager,
                  let guid = manager.taskToGUID[taskId] else {
                removeTemp()
                self.logger.error("Download finished with no episode id; deleted temp file")
                return
            }
            let destURL = manager.guidToDestURL[guid]
                ?? PersistenceManager.shared.localFileURL(forEpisodeGUID: guid)
            do {
                try? FileManager.default.removeItem(at: destURL)
                try FileManager.default.moveItem(at: tempCopy, to: destURL)
                self.finishTracking(guid: guid, taskId: taskId, saved: true)
            } catch {
                removeTemp()
                self.finishTracking(guid: guid, taskId: taskId, saved: false)
                self.logger.error("Failed to move download for \(guid): \(error.localizedDescription)")
            }
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
        let describedGUID = DownloadManager.normalizedGUID(downloadTask.taskDescription)
        Task { @MainActor in
            guard let manager = self.manager else { return }
            let guid = manager.taskToGUID[taskId] ?? describedGUID
            guard let guid else { return }
            if manager.taskToGUID[taskId] == nil {
                manager.taskToGUID[taskId] = guid
            }
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
        let describedGUID = DownloadManager.normalizedGUID(task.taskDescription)
        Task { @MainActor in
            guard let manager = self.manager else { return }
            let guid = manager.taskToGUID[taskId] ?? describedGUID
            guard let guid else { return }
            manager.activeDownloads.removeValue(forKey: guid)
            manager.cleanupTask(for: guid, taskId: taskId)
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            // Task scheduled from didFinishDownloadingTo runs first and flushes.
            PersistenceManager.shared.flushToDisk()
            guard let manager = self.manager else { return }
            let handler = manager.backgroundEventsCompletionHandler
            manager.backgroundEventsCompletionHandler = nil
            handler?()
        }
    }

    @MainActor
    private func finishTracking(guid: String, taskId: Int, saved: Bool) {
        guard let manager else { return }
        manager.activeDownloads.removeValue(forKey: guid)
        if saved {
            manager.downloadedGUIDs.insert(guid)
            manager.saveDownloadState()
            PersistenceManager.shared.flushToDisk()
        }
        manager.cleanupTask(for: guid, taskId: taskId)
    }
}
