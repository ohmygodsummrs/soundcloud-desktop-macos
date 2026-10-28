import Foundation
import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case feed = "Feed"
    case discover = "Discover"
    case search = "Search"
    case notifications = "Notifications"
    case messages = "Messages"
    case charts = "Charts"
    case likes = "Liked Tracks"
    case playlists = "Playlists"
    case albums = "Albums"
    case following = "Following"
    case followers = "Followers"
    case history = "History"
    case myTracks = "Your Tracks"
    case queue = "Queue"
    case settings = "Settings"

    var id: Self { self }

    /// Items in the main sidebar list; Settings sits at the bottom.
    static let main = allCases.filter { $0 != .settings && $0 != .search }
}

enum Route: Hashable {
    case user(Int)
    case playlist(String)
    case track(Int)
    case conversation(String)
}

@MainActor
@Observable
final class AppModel {
    let client = SCClient()
    // Published so player changes re-render views observing the model.
    var player: Player
    /// Set by the sidebar search field; SearchScreen shows its results.
    var searchQuery = ""
    /// Bumped by the "/" shortcut; the sidebar field takes focus on change.
    var searchFocusRequests = 0

    var me: SCUser?
    var restoring = true
    var loginError: String?

    var sidebar: SidebarItem? = .feed
    var stack: [Route] = []
    var toast: String? {
        didSet {
            guard let toast else { return }
            Task {
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                if self.toast == toast { self.toast = nil }
            }
        }
    }

    // What the signed-in user has liked / reposted / followed.
    var likedTracks: Set<Int> = []
    var repostedTracks: Set<Int> = []
    var likedPlaylists: Set<String> = []
    var repostedPlaylists: Set<String> = []
    var following: Set<Int> = []
    /// The user's own playlists, for "Add to playlist".
    var ownPlaylists: [SCPlaylist] = []
    /// Liked playlists and albums, listed in the sidebar.
    var likedPlaylistList: [SCPlaylist] = []

    var themeName = UserDefaults.standard.string(forKey: "theme") ?? Palette.all[0].name {
        didSet { UserDefaults.standard.set(themeName, forKey: "theme") }
    }

    /// Snapshot and palette switch happen before the observed write: taking the
    /// crossfade snapshot during the write forces a redraw with the old value,
    /// which SwiftUI then treats as the update.
    func setTheme(_ name: String) {
        Theme.apply(Palette.named(name), animated: animateThemes)
        themeName = name
    }

    var language = Language(rawValue: UserDefaults.standard.string(forKey: "language") ?? "") ?? .english {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "language") }
    }

    func setLanguage(_ lang: Language) {
        if animateThemes { Theme.crossfade() }
        Language.current = lang
        language = lang
    }
    var animateThemes = Setting.bool("animateThemes", default: true) {
        didSet { Setting.set("animateThemes", animateThemes) }
    }
    var showSidebarPlaylists = Setting.bool("showSidebarPlaylists", default: true) {
        didSet { Setting.set("showSidebarPlaylists", showSidebarPlaylists) }
    }
    var autoplayRelated = Setting.bool("autoplayRelated", default: true) {
        didSet {
            Setting.set("autoplayRelated", autoplayRelated)
            player.autoplayRelated = autoplayRelated
        }
    }
    var logPlays = Setting.bool("logPlays", default: true) {
        didSet {
            Setting.set("logPlays", logPlays)
            player.logPlays = logPlays
        }
    }

    var serverChoice = ServerChoice(rawValue: UserDefaults.standard.string(forKey: "server") ?? "") ?? .auto {
        didSet {
            UserDefaults.standard.set(serverChoice.rawValue, forKey: "server")
            Task { await applyServer() }
        }
    }
    var serverProbes: [ServerProbe] = []
    var probing = false

    /// Measures every API host through this connection and uses the fastest
    /// (Auto) or the one picked in Settings.
    func applyServer() async {
        probing = true
        let probes = await ServerProbe.measureAll()
        serverProbes = probes
        probing = false
        switch serverChoice {
            case .auto:
                if let best = probes.filter({ $0.ok }).min(by: { $0.latency < $1.latency }) {
                    client.host = best.host
                }
            default:
                client.host = serverChoice.host
        }
    }

    /// Bumped to make list views reload.
    var refreshCounter = 0
    /// Bumped after likes change, so only Liked Tracks reloads.
    var likesVersion = 0

    init() {
        player = Player(client: client)
        Theme.current = Palette.named(themeName)
        Language.current = language
        player.autoplayRelated = autoplayRelated
        player.logPlays = logPlays
    }

    // MARK: Session

    func restore() async {
        Task { await applyServer() }
        guard let token = TokenStore.load() else {
            restoring = false
            return
        }
        client.token = token
        // Show the app at once with the last known profile, then refresh.
        if let cached = try? await SCClient.$cacheOnly.withValue(true, operation: { try await client.me() }) {
            me = cached
            restoring = false
            await signIn(token: token, save: false)
        } else {
            await signIn(token: token, save: false)
            restoring = false
        }
    }

    func signIn(token raw: String, save: Bool = true) async {
        var token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.hasPrefix("OAuth ") { token = String(token.dropFirst(6)) }
        guard !token.isEmpty else {
            loginError = "Paste a token first."
            return
        }
        client.token = token
        do {
            let fresh = try await client.me()
            if me?.id != fresh.id || me?.avatarUrl != fresh.avatarUrl || me?.username != fresh.username {
                me = fresh
            }
            loginError = nil
            if save { TokenStore.save(token) }
            await loadUserState()
        } catch {
            client.token = nil
            loginError = "Sign in failed: \(error.localizedDescription)"
        }
    }

    func signOut() {
        PageCache.shared.clear()
        TokenStore.delete()
        client.token = nil
        player.stop()
        player.queue = []
        likedTracks = []
        repostedTracks = []
        likedPlaylists = []
        repostedPlaylists = []
        following = []
        ownPlaylists = []
        likedPlaylistList = []
        Task { await ResponseCache.shared.clear() }
        me = nil
        stack = []
        sidebar = .feed
    }

    func loadUserState() async {
        guard let me else { return }
        async let lt = client.ids("/me/track_likes/ids")
        async let rt = client.ids("/me/track_reposts/ids", limit: 200)
        async let lp = client.ids("/me/playlist_likes/ids")
        async let rp = client.ids("/me/playlist_reposts/ids", limit: 200)
        async let fo = client.ids("/users/\(me.id)/followings/ids", limit: 200)
        likedTracks = await lt
        repostedTracks = await rt
        likedPlaylists = Set(await lp.map(String.init))
        repostedPlaylists = Set(await rp.map(String.init))
        following = await fo
        await reloadOwnPlaylists(me: me.id)
        let likes = try? await client.page(LikeItem.self, "/users/\(me.id)/likes", limit: 200)
        likedPlaylistList = likes?.collection.compactMap(\.playlist) ?? []
    }

    var openPlaylistID: String? {
        if case .playlist(let id) = stack.first, stack.count == 1 { return id }
        return nil
    }

    func openPlaylist(_ id: String) {
        sidebar = nil
        stack = [.playlist(id)]
    }

    func reloadOwnPlaylists(me: Int) async {
        let page = try? await client.page(SCPlaylist.self, "/users/\(me)/playlists_without_albums", limit: 200)
        ownPlaylists = page?.collection ?? []
    }

    // MARK: Navigation

    func select(_ item: SidebarItem?) {
        // Each published write re-renders, so skip no-op writes.
        if !stack.isEmpty { stack = [] }
        if sidebar != item { sidebar = item }
    }

    func push(_ route: Route) { stack.append(route) }

    /// Tracks already on screen, so a track page can paint before its fetch.
    @ObservationIgnored var knownTracks: [Int: SCTrack] = [:]

    func open(_ track: SCTrack) {
        knownTracks[track.id] = track
        push(.track(track.id))
    }
    func back() { if !stack.isEmpty { stack.removeLast() } }

    // MARK: Actions

    /// Runs an action, showing failures as a toast.
    func run(_ what: String, _ action: @escaping () async throws -> Void) {
        Task {
            do {
                try await action()
            } catch {
                toast = "\(what) failed: \(error.localizedDescription)"
            }
        }
    }

    func toggleLike(_ track: SCTrack) {
        guard let me else { return }
        let on = !likedTracks.contains(track.id)
        if on { likedTracks.insert(track.id) } else { likedTracks.remove(track.id) }
        run("Like") {
            try await self.client.setTrackLike(track.id, me: me.id, on: on)
            // Liked Tracks is cached; let it pick up the change.
            self.likesVersion += 1
        }
    }

    func toggleRepost(_ track: SCTrack) {
        let on = !repostedTracks.contains(track.id)
        if on { repostedTracks.insert(track.id) } else { repostedTracks.remove(track.id) }
        run("Repost") { try await self.client.setTrackRepost(track.id, on: on) }
    }

    func toggleLike(_ playlist: SCPlaylist) {
        guard let me else { return }
        let on = !likedPlaylists.contains(playlist.id)
        if on { likedPlaylists.insert(playlist.id) } else { likedPlaylists.remove(playlist.id) }
        run("Like") { try await self.client.setPlaylistLike(playlist.id, me: me.id, on: on) }
    }

    func toggleRepost(_ playlist: SCPlaylist) {
        let on = !repostedPlaylists.contains(playlist.id)
        if on { repostedPlaylists.insert(playlist.id) } else { repostedPlaylists.remove(playlist.id) }
        run("Repost") { try await self.client.setPlaylistRepost(playlist.id, on: on) }
    }

    func toggleFollow(_ user: SCUser) {
        let on = !following.contains(user.id)
        if on { following.insert(user.id) } else { following.remove(user.id) }
        run("Follow") { try await self.client.setFollow(user.id, on: on) }
    }

    func add(_ track: SCTrack, to playlist: SCPlaylist) {
        run("Add to playlist") {
            let full = try await self.client.playlist(playlist.id)
            let ids = (full.tracks ?? []).map(\.id) + [track.id]
            try await self.client.setPlaylistTracks(playlist.id, trackIDs: ids)
            self.toast = "Added to \(playlist.displayTitle)"
            self.refreshCounter += 1
        }
    }

    func remove(_ track: SCTrack, from playlist: SCPlaylist) {
        run("Remove from playlist") {
            let full = try await self.client.playlist(playlist.id)
            let ids = (full.tracks ?? []).map(\.id).filter { $0 != track.id }
            try await self.client.setPlaylistTracks(playlist.id, trackIDs: ids)
            self.refreshCounter += 1
        }
    }

    func createPlaylist(title: String, isPrivate: Bool, with track: SCTrack? = nil) {
        guard let me else { return }
        run("Create playlist") {
            _ = try await self.client.createPlaylist(
                title: title, isPrivate: isPrivate, trackIDs: track.map { [$0.id] } ?? []
            )
            await self.reloadOwnPlaylists(me: me.id)
            self.toast = "Created \(title)"
            self.refreshCounter += 1
        }
    }

    func deletePlaylist(_ playlist: SCPlaylist) {
        guard let me else { return }
        run("Delete playlist") {
            try await self.client.deletePlaylist(playlist.id)
            await self.reloadOwnPlaylists(me: me.id)
            self.back()
            self.refreshCounter += 1
        }
    }

    /// Volume to restore when unmuting.
    @ObservationIgnored private var unmutedVolume = 0.8

    func toggleMute() {
        if player.volume > 0 {
            unmutedVolume = player.volume
            player.volume = 0
        } else {
            player.volume = unmutedVolume
        }
    }

    /// Reloads the current page. Skips the 5-minute memory cache, or it would
    /// show the same data again.
    func refresh() async {
        await ResponseCache.shared.invalidate()
        PageCache.shared.clear()
        refreshCounter += 1
    }

    /// Plays a playlist from its tile without opening it.
    func playPlaylist(_ id: String) {
        run("Play") {
            let tracks = try await self.client.playlist(id).tracks ?? []
            guard !tracks.isEmpty else { return }
            self.player.play(tracks, startAt: 0)
        }
    }

    /// soundcloud.com station: an endless mix built from one track or artist.
    func startStation(track id: Int) { push(.playlist("soundcloud:system-playlists:track-stations:\(id)")) }
    func startStation(artist id: Int) { push(.playlist("soundcloud:system-playlists:artist-stations:\(id)")) }

    /// Link that opens at the current playback position, like the web's "at 1:23" share option.
    func shareLink(_ track: SCTrack, atCurrentTime: Bool) -> String? {
        guard let link = track.permalinkUrl else { return nil }
        guard atCurrentTime, player.current?.id == track.id, player.position >= 1 else { return link }
        return "\(link)#t=\(Format.duration(player.position))"
    }

    func isOwn(_ playlist: SCPlaylist) -> Bool {
        playlist.user?.id != nil && playlist.user?.id == me?.id
    }
}

/// Bool preferences in UserDefaults with defaults.
enum Setting {
    static func bool(_ key: String, default value: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? value
    }

    static func set(_ key: String, _ value: Bool) {
        UserDefaults.standard.set(value, forKey: key)
    }
}
