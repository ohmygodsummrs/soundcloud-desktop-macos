import Foundation
import SwiftUI

/// Root page for each sidebar item.
struct SidebarScreen: View {
    var model: AppModel
    var item: SidebarItem

    var body: some View {
        switch item {
            case .feed: FeedScreen(model: model)
            case .discover: DiscoverScreen(model: model)
            case .search: SearchScreen(model: model)
            case .notifications: NotificationsScreen(model: model)
            case .messages: MessagesScreen(model: model)
            case .charts: ChartsScreen(model: model)
            case .likes: LikesScreen(model: model)
            case .playlists: LibraryPlaylistsScreen(model: model, albums: false)
            case .albums: LibraryPlaylistsScreen(model: model, albums: true)
            case .following: UsersScreen(model: model, title: "Following", path: "followings")
            case .followers: UsersScreen(model: model, title: "Followers", path: "followers")
            case .history: HistoryScreen(model: model)
            case .myTracks: MyTracksScreen(model: model)
            case .queue: QueueScreen(model: model)
            case .settings: SettingsScreen(model: model)
        }
    }
}

struct FeedScreen: View {
    var model: AppModel

    /// SoundCloud's personalized selections ("Mixed for you"…), shown above the feed like the web home.
    @State var selections: [Selection] = []

    var body: some View {
        let _ = Perf.body("FeedScreen")
        LazyVStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Feed")
            Text(L("Hear the latest posts and reposts from the people you follow."))
                .foregroundColor(Theme.secondary)
            // Each carousel is its own lazy row: scrolling back up builds one per frame, not three.
            // String ids: the feed rows below already use 0, 1, 2… in this same stack.
            ForEach(selections.prefix(3).enumerated().map { ("selection-\($0.offset)", $0.element) }, id: \.0) { _, s in
                PlaylistCarousel(model: model, title: s.title ?? "", playlists: s.items?.collection ?? [])
                    .padding(.vertical, 9)
            }
            PagedList(key: "feed-\(model.refreshCounter)") { href in
                try await model.client.page(StreamItem.self, href ?? "/stream", limit: 30)
            } row: { i, items in
                FeedPost(model: model, item: items[i]) {
                    playTracks(items, at: i)
                }
            }
        }
        .task(id: model.refreshCounter) {
            // Paint the last copy at once, then refresh.
            if let cached = try? await SCClient.$cacheOnly.withValue(true, operation: { try await loadSelections() }) {
                selections = cached
            }
            // Same playlists again would rebuild every card for nothing.
            if let fresh = try? await loadSelections(), signature(fresh) != signature(selections) { selections = fresh }
        }
    }

    func loadSelections() async throws -> [Selection] {
        try await model.client.page(Selection.self, "/mixed-selections", limit: 10).collection
            .filter { !($0.items?.collection.isEmpty ?? true) }
    }

    func signature(_ s: [Selection]) -> [String] {
        s.prefix(3).flatMap { [$0.title ?? ""] + ($0.items?.collection ?? []).map { "\($0.id)|\($0.artwork ?? "")" } }
    }

    /// Plays the feed as a queue, skipping playlist entries.
    func playTracks(_ items: [StreamItem], at i: Int) {
        let tracks = items.compactMap(\.track)
        guard let id = items[i].track?.id, let start = tracks.firstIndex(where: { $0.id == id }) else { return }
        model.player.play(tracks, startAt: start)
    }
}

struct DiscoverScreen: View {
    var model: AppModel

    @State var selections: [Selection] = []
    @State var error: String?

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 36) {
            SectionTitle(text: "Discover")
            if let error { Text(error).foregroundColor(.red) }
            if selections.isEmpty && error == nil { Loader() }
            ForEach(Array(selections.indices), id: \.self) { i in
                PlaylistCarousel(
                    model: model, title: selections[i].title ?? "",
                    playlists: selections[i].items?.collection ?? []
                )
            }
        }
        .task(id: model.refreshCounter) {
            error = nil
            // Paint the last copy at once, then refresh.
            if let cached = try? await SCClient.$cacheOnly.withValue(true, operation: {
                try await model.client.page(Selection.self, "/mixed-selections", limit: 20)
            }) {
                selections = cached.collection.filter { !($0.items?.collection.isEmpty ?? true) }
            }
            do {
                selections = try await model.client.page(Selection.self, "/mixed-selections", limit: 20).collection
                    .filter { !($0.items?.collection.isEmpty ?? true) }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

enum SearchKind: String, Hashable {
    case tracks, users, playlists = "playlists_without_albums", albums
}

struct SearchScreen: View {
    var model: AppModel

    var query: String { model.searchQuery }
    @State var kind = SearchKind.tracks

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Search")
            Tabs(
                options: [(.tracks, "Tracks"), (.users, "People"), (.playlists, "Playlists"), (.albums, "Albums")],
                selection: $kind
            )
            if !query.isEmpty { results }
        }
    }

    var path: String { "/search/\(kind.rawValue)" }

    func load(_ href: String?) -> String {
        if let href { return href }
        let q = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? query
        return "\(path)?q=\(q)"
    }

    @ViewBuilder var results: some View {
        let key = "\(kind.rawValue)-\(query)"
        switch kind {
            case .tracks:
                PagedList(key: key) { href in
                    try await model.client.page(SCTrack.self, load(href))
                } row: { i, items in
                    TrackRow(model: model, track: items[i]) { model.player.play(items, startAt: i) }
                }
            case .users:
                PagedList(key: key) { href in
                    try await model.client.page(SCUser.self, load(href))
                } row: { i, items in
                    UserRow(model: model, user: items[i])
                }
            case .playlists, .albums:
                PagedList(key: key) { href in
                    try await model.client.page(SCPlaylist.self, load(href))
                } row: { i, items in
                    PlaylistRow(model: model, playlist: items[i])
                }
        }
    }
}

struct LikesScreen: View {
    var model: AppModel

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Liked Tracks")
            if let me = model.me {
                PagedList(key: "likes-\(model.refreshCounter)-\(model.likesVersion)") { href in
                    try await model.client.page(LikeItem.self, href ?? "/users/\(me.id)/track_likes", limit: 50)
                } row: { i, items in
                    if let track = items[i].track {
                        TrackRow(model: model, track: track) {
                            let tracks = items.compactMap(\.track)
                            model.player.play(tracks, startAt: tracks.firstIndex { $0.id == track.id } ?? 0)
                        }
                    }
                }
            }
        }
    }
}

struct LibraryPlaylistsScreen: View {
    var model: AppModel
    var albums: Bool

    @State var newTitle = ""
    @State var newPrivate = true

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: albums ? L("Albums") : L("Playlists"))
            if !albums {
                HStack {
                    TextField(L("New playlist title"), text: $newTitle)
                    ThemedToggle(label: L("Private"), isOn: newPrivate) { newPrivate.toggle() }
                        .frame(width: 130)
                    TButton(L("Create")) {
                        let title = newTitle.trimmingCharacters(in: .whitespaces)
                        guard !title.isEmpty else { return }
                        model.createPlaylist(title: title, isPrivate: newPrivate)
                        newTitle = ""
                    }
                }
            }
            if let me = model.me {
                Text(albums ? L("Your albums") : L("Your playlists")).font(.system(size: 16, weight: .semibold))
                let own = "/users/\(me.id)/\(albums ? L("albums") : L("playlists_without_albums"))"
                PagedList(key: "own-\(albums)-\(model.refreshCounter)") { href in
                    try await model.client.page(SCPlaylist.self, href ?? own, limit: 50)
                } row: { i, items in
                    PlaylistRow(model: model, playlist: items[i])
                }
                Divider()
                Text(L("Liked")).font(.system(size: 16, weight: .semibold))
                // /users/{id}/likes mixes tracks and playlists, newest first.
                PagedList(key: "liked-\(albums)-\(model.refreshCounter)") { href in
                    let page = try await model.client.page(LikeItem.self, href ?? "/users/\(me.id)/likes", limit: 100)
                    let lists = page.collection.filter { ($0.playlist?.isAlbum == true) == albums && $0.playlist != nil }
                    return Page(collection: lists, nextHref: page.nextHref)
                } row: { i, items in
                    if let p = items[i].playlist {
                        PlaylistRow(model: model, playlist: p, caption: L("Liked"))
                    }
                }
            }
        }
    }
}

struct UsersScreen: View {
    var model: AppModel
    var title: String
    var path: String

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: title)
            if let me = model.me {
                PagedList(key: path) { href in
                    try await model.client.page(SCUser.self, href ?? "/users/\(me.id)/\(path)", limit: 50)
                } row: { i, items in
                    UserRow(model: model, user: items[i])
                }
            }
        }
    }
}

struct HistoryScreen: View {
    var model: AppModel

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Listening History")
            PagedList(key: "history-\(model.refreshCounter)") { href in
                try await model.client.page(HistoryItem.self, href ?? "/me/play-history/tracks", limit: 50)
            } row: { i, items in
                if let track = items[i].track {
                    TrackRow(model: model, track: track) {
                        let tracks = items.compactMap(\.track)
                        model.player.play(tracks, startAt: tracks.firstIndex { $0.id == track.id } ?? 0)
                    }
                }
            }
        }
    }
}

struct MyTracksScreen: View {
    var model: AppModel

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Your Tracks")
            if let me = model.me {
                PagedList(key: "mine") { href in
                    try await model.client.page(SCTrack.self, href ?? "/users/\(me.id)/tracks", limit: 50)
                } row: { i, items in
                    TrackRow(model: model, track: items[i]) { model.player.play(items, startAt: i) }
                }
            }
        }
    }
}

struct QueueScreen: View {
    var model: AppModel

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(text: "Queue")
                Spacer()
                TButton(L("Clear")) { model.player.queue = []; model.player.stop() }
            }
            if model.player.queue.isEmpty {
                Text(L("Queue is empty.")).foregroundColor(Theme.secondary)
            }
            ForEach(Array(model.player.queue.indices), id: \.self) { i in
                TrackRow(
                    model: model, track: model.player.queue[i], number: i + 1,
                    onPlay: { model.player.load(index: i) },
                    onRemove: { model.player.remove(at: i) }
                )
            }
        }
    }
}
