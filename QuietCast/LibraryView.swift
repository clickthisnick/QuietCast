import SwiftUI

struct LibraryView: View {
    var audioPlayer: AudioPlayer { AudioPlayer.shared }
    @State private var podcasts: [Podcast] = []
    @State private var showSearch = false
    @State private var searchAllowed = TimeGate.searchAllowed()
    @State private var podcastToDelete: Podcast?
    @State private var showDeleteConfirmation = false
    @State private var showAddURL = false
    @State private var feedURLText = ""
    @State private var addURLError: String?
    @State private var showSettings = false
    @State private var isAddingFeed = false
    @State private var selectedPodcast: Podcast?
    @State private var showReorder = false
    @State private var lastPlayedEpisode: Episode?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Group {
                    if podcasts.isEmpty {
                        emptyState
                    } else {
                        podcastList
                    }
                }
                .frame(maxHeight: .infinity)

                if audioPlayer.currentEpisode != nil {
                    NowPlayingBar()
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 16) {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        Button {
                            feedURLText = ""
                            addURLError = nil
                            showAddURL = true
                        } label: {
                            Image(systemName: "link.badge.plus")
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        if podcasts.count > 1 {
                            Button {
                                showReorder = true
                            } label: {
                                Image(systemName: "arrow.up.arrow.down")
                            }
                        }
                        if searchAllowed {
                            Button {
                                showSearch = true
                            } label: {
                                Image(systemName: "magnifyingglass")
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showSearch, onDismiss: {
                searchAllowed = TimeGate.searchAllowed()
            }) {
                SearchView(podcasts: $podcasts)
            }
            .alert("Add Feed URL", isPresented: $showAddURL) {
                TextField("https://feeds.example.com/podcast", text: $feedURLText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Add") {
                    addPodcastByURL()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let addURLError {
                    Text(addURLError)
                } else {
                    Text("Paste a podcast RSS feed URL.")
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showReorder) {
                ReorderPodcastsView(podcasts: $podcasts)
            }
            .overlay {
                if isAddingFeed {
                    ZStack {
                        Color.black.opacity(0.3).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Loading feed…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(24)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .onAppear {
                loadLibrary()
                searchAllowed = TimeGate.searchAllowed()
                if audioPlayer.currentEpisode == nil {
                    lastPlayedEpisode = PersistenceManager.shared.loadLastPlayedEpisode()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("QuietCastDataCleared"))) { _ in
                podcasts = []
            }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 30_000_000_000)
                    searchAllowed = TimeGate.searchAllowed()
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("No podcasts yet")
                .font(.title2)
                .foregroundStyle(.secondary)
            if searchAllowed {
                Text("Tap the search icon to find shows,\nor add a feed URL with the link button.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Search is off for the night.\nYou can still add a feed URL\nwith the link button.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()

            // Debug: storage diagnostics
            VStack(alignment: .leading, spacing: 4) {
                let pm = PersistenceManager.shared
                let dir = pm.documentsDirectory()
                let groupAvailable = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: PersistenceManager.appGroupID) != nil
                Text("App Group: \(groupAvailable ? "✓" : "✗ NOT AVAILABLE")")
                Text("ID: \(PersistenceManager.appGroupID)")
                Text("Path: \(dir.path)")
                let fileExists = FileManager.default.fileExists(atPath: dir.appendingPathComponent("library.json").path)
                Text("library.json: \(fileExists ? "exists" : "not found")")
            }
            .font(.caption2)
            .foregroundStyle(.quaternary)
            .padding()
        }
        .padding()
    }

    private var podcastList: some View {
        List {
            // Resume last played episode
            if audioPlayer.currentEpisode == nil, let episode = lastPlayedEpisode {
                resumeCard(for: episode)
            }

            ForEach(podcasts) { podcast in
                HStack {
                    Text(podcast.title)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedPodcast = podcast
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        podcastToDelete = podcast
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }

            Label("Double-press headphone crown for a random episode", systemImage: "shuffle")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            Label("Triple-press headphone crown to hear the time", systemImage: "clock")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            Label("Swipe left to delete a podcast", systemImage: "arrow.left")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            Text("Built \(BuildInfo.timestamp)")
                .font(.caption2)
                .foregroundStyle(.quaternary)
                .frame(maxWidth: .infinity)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            if !searchAllowed {
                Section {
                    Text("Search is available between 8 AM and 8 PM.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }

            // Spacer for Now Playing bar
            if audioPlayer.currentEpisode != nil {
                Color.clear
                    .frame(height: 80)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .navigationDestination(item: $selectedPodcast) { podcast in
            EpisodeListView(podcast: podcast)
        }
        .alert("Delete Podcast?",
               isPresented: $showDeleteConfirmation) {
            Button("Delete Podcast & Data", role: .destructive) {
                if let podcast = podcastToDelete {
                    deletePodcast(podcast)
                }
                podcastToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                podcastToDelete = nil
            }
        } message: {
            Text("This will remove \"\(podcastToDelete?.title ?? "")\" from your library and delete all its downloaded episodes and data.")
        }
    }

    private func resumeCard(for episode: Episode) -> some View {
        Button {
            // Set feedURL so AudioPlayer can look up podcast-specific settings
            let library = PersistenceManager.shared.loadLibrary()
            audioPlayer.currentFeedURL = library.lastPlayedFeedURL
            audioPlayer.play(episode: episode)
            lastPlayedEpisode = nil
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(Color.warmAccent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(episode.title)
                        .font(.subheadline)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(episode.podcastTitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        let saved = PersistenceManager.shared.playbackPosition(for: episode.guid)
                        if saved > 0 {
                            Text("·")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text("\(formatResumeTime(saved)) in")
                                .font(.caption2)
                                .foregroundStyle(Color.warmAccent)
                        }
                    }
                }

                Spacer()
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func formatResumeTime(_ seconds: Double) -> String {
        let total = max(Int(seconds), 0)
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 {
            return "\(h)h \(m)m"
        }
        return "\(m)m"
    }

    private func loadLibrary() {
        let library = PersistenceManager.shared.loadLibrary()
        podcasts = library.podcasts
    }

    private func addPodcastByURL() {
        let trimmed = feedURLText.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: trimmed), url.scheme != nil else {
            addURLError = "Invalid URL. Please enter a full feed URL."
            showAddURL = true
            return
        }

        // Check if already saved by normalized URL
        let normalized = trimmed.lowercased()
        if podcasts.contains(where: { $0.feedURL.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/")) == normalized }) {
            addURLError = "This podcast is already in your library."
            showAddURL = true
            return
        }

        isAddingFeed = true
        Task {
            defer { isAddingFeed = false }
            do {
                var request = URLRequest(url: url)
                request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
                request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
                request.timeoutInterval = 15
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    addURLError = "Could not load feed. The server returned an error."
                    showAddURL = true
                    return
                }
                let parser = RSSParser(feedURL: trimmed)
                let episodes = parser.parse(data: data)
                if parser.parseFailed {
                    addURLError = "Could not read this feed. Check the URL and try again."
                    showAddURL = true
                    return
                }
                if episodes.isEmpty {
                    addURLError = "No episodes found. The feed may be empty or in an unsupported format."
                    showAddURL = true
                    return
                }

                let rawTitle = episodes.first?.podcastTitle
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let title = rawTitle.isEmpty ? (url.host ?? "Unknown Podcast") : rawTitle
                let artwork = episodes.first?.artworkURL ?? ""

                // Check by title too — same podcast might have a different feed URL
                if podcasts.contains(where: { $0.title.lowercased() == title.lowercased() }) {
                    addURLError = "\"\(title)\" is already in your library."
                    showAddURL = true
                    return
                }

                let podcast = Podcast(
                    title: title,
                    author: "",
                    artworkURL: artwork,
                    feedURL: trimmed
                )

                podcasts.append(podcast)
                var library = PersistenceManager.shared.loadLibrary()
                library.podcasts = podcasts
                PersistenceManager.shared.saveLibrary(library)
            } catch let error as URLError where error.code == .notConnectedToInternet || error.code == .networkConnectionLost {
                addURLError = "No internet connection. Check your network and try again."
                showAddURL = true
            } catch {
                addURLError = "Could not load feed. Check the URL and try again."
                showAddURL = true
            }
        }
    }

    private func deletePodcast(_ podcast: Podcast) {
        // Cancel any active downloads for this podcast's episodes
        DownloadManager.shared.cancelAllDownloads(for: podcast)

        // Remove all local data: downloads, cache, playback positions
        PersistenceManager.shared.removeAllData(for: podcast)

        podcasts.removeAll { $0.feedURL == podcast.feedURL }
        var library = PersistenceManager.shared.loadLibrary()
        library.podcasts = podcasts
        PersistenceManager.shared.saveLibrary(library)
    }
}

private struct ReorderPodcastsView: View {
    @Binding var podcasts: [Podcast]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(podcasts) { podcast in
                    Text(podcast.title)
                }
                .onMove { from, to in
                    podcasts.move(fromOffsets: from, toOffset: to)
                    var library = PersistenceManager.shared.loadLibrary()
                    library.podcasts = podcasts
                    PersistenceManager.shared.saveLibrary(library)
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Reorder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
