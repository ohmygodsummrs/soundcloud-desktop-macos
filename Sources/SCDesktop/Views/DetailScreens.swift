import Foundation
import SwiftUI

struct RouteScreen: View {
    var model: AppModel
    var route: Route

    var body: some View {
        switch route {
            case .user(let id): UserScreen(model: model, userID: id)
            case .playlist(let id): PlaylistScreen(model: model, playlistID: id)
            case .track(let id): TrackScreen(model: model, trackID: id)
            case .conversation(let id): ConversationScreen(model: model, conversationID: id)
        }
    }
}

struct PlaylistScreen: View {
    var model: AppModel
    var playlistID: String

    @State var playlist: SCPlaylist?
    @State var error: String?
    @State var narrow = false

    var tracks: [SCTrack] { playlist?.tracks ?? [] }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            if let error { Text(error).foregroundColor(.red) }
            if let playlist {
                header(playlist)
                Divider()
                ForEach(Array(tracks.indices), id: \.self) { i in
                    TrackRow(
                        model: model, track: tracks[i], number: i + 1,
                        onPlay: { model.player.play(tracks, startAt: i) },
                        onRemove: model.isOwn(playlist) ? { model.remove(tracks[i], from: playlist) } : nil
                    )
                }
            } else if error == nil {
                Loader()
            }
        }
        .onGeometryChange(for: Bool.self) { $0.size.width < 640 } action: { narrow = $0 }
        .task(id: "\(playlistID)-\(model.refreshCounter)") {
            if playlist?.id != playlistID {
                playlist = try? await SCClient.$cacheOnly.withValue(true) { try await model.client.playlist(playlistID) }
            }
            do {
                playlist = try await model.client.playlist(playlistID)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func header(_ p: SCPlaylist) -> some View {
        HStack(alignment: .top, spacing: 16) {
            RemoteImage(url: p.artwork, size: narrow ? 110 : 180, radius: 6)
            VStack(alignment: .leading, spacing: 6) {
                Text(p.isAlbum == true ? L("ALBUM") : p.isSystem ? L("STATION / MIX") : L("PLAYLIST"))
                    .font(.system(size: 11)).foregroundColor(Theme.secondary)
                Text(p.displayTitle).font(.system(size: 24, weight: .bold))
                if let user = p.user {
                    LinkText(user.name, size: 14) { model.push(.user(user.id)) }
                }
                // System mixes have no duration or like counts.
                let seconds = p.duration.map { Double($0) / 1000 } ?? tracks.reduce(0) { $0 + $1.seconds }
                Text(p.isSystem
                    ? "\(tracksCount(tracks.count)) · \(Format.duration(seconds))"
                    : "\(tracksCount(tracks.count)) · \(Format.duration(seconds)) · ♥ \(Format.count(p.likesCount)) · ↻ \(Format.count(p.repostsCount))")
                    .foregroundColor(Theme.secondary)
                if let d = p.description, !d.isEmpty {
                    Text(d).font(.system(size: 12)).lineLimit(4)
                }
                HStack {
                    TButton(L("▶ Play")) { model.player.play(tracks, startAt: 0) }
                        .disabled(tracks.isEmpty)
                    TButton(L("Shuffle")) {
                        model.player.shuffle = true
                        model.player.play(tracks, startAt: Int.random(in: 0..<max(tracks.count, 1)))
                    }
                    .disabled(tracks.isEmpty)
                    if !p.isSystem {
                        TButton(model.likedPlaylists.contains(p.id) ? L("♥ Liked") : L("♡ Like")) { model.toggleLike(p) }
                        if !model.isOwn(p) {
                            TButton(model.repostedPlaylists.contains(p.id) ? L("↻ Reposted") : L("↻ Repost")) {
                                model.toggleRepost(p)
                            }
                        }
                    }
                    if let link = p.permalinkUrl {
                        TButton(L("Copy link"), icon: "link") {
                            copyToPasteboard(link)
                            model.toast = L("Link copied")
                        }
                    }
                    if model.isOwn(p) {
                        TButton(L("Delete playlist")) { model.deletePlaylist(p) }
                    }
                }
            }
        }
    }
}

enum UserTab: Hashable {
    case tracks, popular, playlists, albums, reposts, likes, following, followers
}

struct UserScreen: View {
    var model: AppModel
    var userID: Int

    @State var user: SCUser?
    @State var tab = UserTab.tracks
    @State var error: String?
    @State var narrow = false

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            if let error { Text(error).foregroundColor(.red) }
            if let user {
                header(user)
                ScrollView(.horizontal, showsIndicators: false) {
                Tabs(
                    options: [
                        (.tracks, "Tracks"), (.popular, "Popular"), (.playlists, "Playlists"),
                        (.albums, "Albums"), (.reposts, "Reposts"), (.likes, "Likes"),
                        (.following, "Following"), (.followers, "Followers"),
                    ],
                    selection: $tab
                )
                }
                Divider()
                content
            } else if error == nil {
                Loader()
            }
        }
        .onGeometryChange(for: Bool.self) { $0.size.width < 640 } action: { narrow = $0 }
        .task(id: "\(userID)-\(model.refreshCounter)") {
            error = nil
            // Same view struct is reused when jumping between users.
            if user?.id != userID {
                tab = .tracks
                user = try? await SCClient.$cacheOnly.withValue(true) { try await model.client.user(userID) }
            }
            do {
                user = try await model.client.user(userID)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func header(_ u: SCUser) -> some View {
        HStack(alignment: .top, spacing: 16) {
            RemoteImage(url: u.avatarUrl, size: narrow ? 90 : 140, radius: narrow ? 45 : 70)
            VStack(alignment: .leading, spacing: 6) {
                Text(u.name + (u.verified == true ? L(" ✓") : L(""))).font(.system(size: 24, weight: .bold))
                if let full = u.fullName, !full.isEmpty { Text(full) }
                if let city = u.city, !city.isEmpty { Text(city).foregroundColor(Theme.secondary) }
                Text("\(followersCount(u.followersCount)) · \(Format.count(u.followingsCount)) \(L("following")) · \(tracksCount(u.trackCount ?? 0))")
                    .foregroundColor(Theme.secondary)
                if let d = u.description, !d.isEmpty {
                    Text(d).font(.system(size: 12)).lineLimit(5)
                }
                HStack(spacing: 8) {
                    if u.id != model.me?.id {
                        TButton(model.following.contains(u.id) ? L("Following") + " ✓" : L("Follow")) { model.toggleFollow(u) }
                    }
                    // Artist stations 404 for accounts without tracks.
                    if (u.trackCount ?? 0) > 0 {
                        TButton(L("Station"), icon: "dot.radiowaves.left.and.right") { model.startStation(artist: u.id) }
                    }
                    if let link = u.permalinkUrl, let url = URL(string: link) {
                        ShareLink(item: url) {
                            // Same look as TButton; ShareLink can't wrap a Button.
                            HStack(spacing: 5) {
                                Icon(name: "square.and.arrow.up", size: 12)
                                Text(L("Share")).font(.system(size: 12, weight: .medium))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Theme.current.surface.color)
                            .cornerRadius(6)
                        }
                        .buttonStyle(PressStyle())
                        TButton(L("Copy link"), icon: "link") {
                            copyToPasteboard(link)
                            model.toast = L("Link copied")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder var content: some View {
        let base = "/users/\(userID)"
        switch tab {
            case .tracks: tracks("\(base)/tracks")
            case .popular: tracks("\(base)/toptracks")
            case .playlists: playlists("\(base)/playlists_without_albums")
            case .albums: playlists("\(base)/albums")
            case .reposts:
                PagedList(key: "reposts-\(userID)") { href in
                    try await model.client.page(StreamItem.self, href ?? "/stream/users/\(userID)/reposts")
                } row: { i, items in
                    StreamRow(model: model, item: items[i]) {
                        let tracks = items.compactMap(\.track)
                        let id = items[i].track?.id
                        model.player.play(tracks, startAt: tracks.firstIndex { $0.id == id } ?? 0)
                    }
                }
            case .likes:
                PagedList(key: "ulikes-\(userID)") { href in
                    try await model.client.page(LikeItem.self, href ?? "\(base)/likes")
                } row: { i, items in
                    if let track = items[i].track {
                        TrackRow(model: model, track: track) {
                            let tracks = items.compactMap(\.track)
                            model.player.play(tracks, startAt: tracks.firstIndex { $0.id == track.id } ?? 0)
                        }
                    } else if let p = items[i].playlist {
                        PlaylistRow(model: model, playlist: p)
                    }
                }
            case .following: users("\(base)/followings")
            case .followers: users("\(base)/followers")
        }
    }

    func tracks(_ path: String) -> some View {
        PagedList(key: path) { href in
            try await model.client.page(SCTrack.self, href ?? path)
        } row: { i, items in
            TrackRow(model: model, track: items[i]) { model.player.play(items, startAt: i) }
        }
    }

    func playlists(_ path: String) -> some View {
        PagedList(key: path) { href in
            try await model.client.page(SCPlaylist.self, href ?? path)
        } row: { i, items in
            PlaylistRow(model: model, playlist: items[i])
        }
    }

    func users(_ path: String) -> some View {
        PagedList(key: path) { href in
            try await model.client.page(SCUser.self, href ?? path)
        } row: { i, items in
            UserRow(model: model, user: items[i])
        }
    }
}

struct TrackScreen: View {
    var model: AppModel
    var trackID: Int

    @State var track: SCTrack?
    @State var error: String?
    @State var comment = ""
    @State var showRelated = false
    @State var narrow = false

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            if let error { Text(error).foregroundColor(.red) }
            if let track {
                header(track)
                Divider()
                Tabs(options: [(false, "Comments"), (true, "Related tracks")], selection: $showRelated)
                if showRelated {
                    PagedList(key: "related-\(trackID)") { href in
                        try await model.client.page(SCTrack.self, href ?? "/tracks/\(trackID)/related")
                    } row: { i, items in
                        TrackRow(model: model, track: items[i]) { model.player.play(items, startAt: i) }
                    }
                } else {
                    comments(track)
                }
            } else if error == nil {
                Loader()
            }
        }
        .onGeometryChange(for: Bool.self) { $0.size.width < 700 } action: { narrow = $0 }
        .task(id: "\(trackID)-\(model.refreshCounter)") {
            error = nil
            if track?.id != trackID {
                comment = ""
                showRelated = false
                track = model.knownTracks[trackID]
                if track == nil {
                    track = try? await SCClient.$cacheOnly.withValue(true) { try await model.client.track(trackID) }
                }
            }
            do {
                track = try await model.client.track(trackID)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func header(_ t: SCTrack) -> some View {
        let p = Theme.current
        let isCurrent = model.player.current?.id == t.id
        let liked = model.likedTracks.contains(t.id)
        let reposted = model.repostedTracks.contains(t.id)
        return HStack(alignment: .top, spacing: 20) {
            PlayableArtwork(
                url: t.artwork, size: narrow ? 130 : 220, radius: 8, isCurrent: isCurrent, isPlaying: model.player.isPlaying
            ) { playOrToggle(t) }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(p.accent.color).frame(width: 56, height: 56)
                        Icon(
                            name: isCurrent && model.player.isPlaying ? "pause.fill" : "play.fill",
                            size: 22, color: p.onAccent.ns
                        )
                    }
                    .onTapGesture { playOrToggle(t) }
                    VStack(alignment: .leading, spacing: 4) {
                        if let user = t.user {
                            LinkText(user.name, size: 15) { model.push(.user(user.id)) }
                        }
                        Text(t.displayTitle).font(.system(size: 26, weight: .bold)).lineLimit(2)
                    }
                }
                HStack(spacing: 12) {
                    StatsRow(track: t, size: 12)
                    Text(Format.duration(t.seconds)).font(.system(size: 12)).foregroundColor(Theme.secondary)
                    if let genre = t.genre, !genre.isEmpty {
                        Text("#\(genre)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(p.onAccent.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(p.accent.color(0.85))
                            .cornerRadius(10)
                    }
                }
                Waveform(
                    url: t.waveformUrl,
                    progress: { [model] in
                        let pl = model.player
                        guard pl.current?.id == t.id, pl.duration > 0 else { return nil }
                        return pl.position / pl.duration
                    },
                    onSeek: { f in
                        if model.player.current?.id == t.id {
                            model.player.seek(to: f * model.player.duration)
                        } else {
                            model.player.play([t], startAt: 0)
                        }
                    }
                )
                .frame(maxWidth: .infinity)
                HStack(spacing: 8) {
                    TButton(liked ? L("Liked") : L("Like"), icon: "heart.fill", prominent: liked) { model.toggleLike(t) }
                    TButton(reposted ? L("Reposted") : L("Repost"), icon: "arrow.2.squarepath", prominent: reposted) {
                        model.toggleRepost(t)
                    }
                    if let link = model.shareLink(t, atCurrentTime: true) {
                        TButton(L("Copy link"), icon: "link") {
                            copyToPasteboard(link)
                            model.toast = L("Link copied")
                        }
                    }
                    TButton(L("Station"), icon: "dot.radiowaves.left.and.right") { model.startStation(track: t.id) }
                    TButton(L("Add to queue"), icon: "text.badge.plus") { model.player.enqueue(t) }
                    TrackMenu(model: model, track: t)
                }
                if let d = t.description, !d.isEmpty {
                    Text(d).font(.system(size: 12)).foregroundColor(Theme.secondary).lineLimit(8)
                }
            }
        }
    }

    func playOrToggle(_ t: SCTrack) {
        if model.player.current?.id == t.id { model.player.toggle() } else { model.player.play([t], startAt: 0) }
    }

    func comments(_ t: SCTrack) -> some View {
        Group {
            HStack {
                TextField(L("Write a comment"), text: $comment)
                    .onSubmit { post(t) }
                TButton(L("Post")) { post(t) }
            }
            Text(L("Comments post at the current playback time if this track is playing."))
                .font(.system(size: 11)).foregroundColor(Theme.secondary)
            PagedList(key: "comments-\(trackID)-\(model.refreshCounter)") { href in
                try await model.client.page(SCComment.self, href ?? "/tracks/\(trackID)/comments?threaded=0&filter_replies=0&sort=newest")
            } row: { i, items in
                CommentRow(model: model, comment: items[i])
            }
        }
    }

    func post(_ t: SCTrack) {
        let body = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        let at = model.player.current?.id == t.id ? Int(model.player.position * 1000) : 0
        comment = ""
        model.run("Comment") {
            try await model.client.postComment(track: t.id, body: body, atMs: at)
            model.refreshCounter += 1
        }
    }
}

struct CommentRow: View {
    var model: AppModel
    var comment: SCComment

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RemoteImage(url: comment.user?.avatarUrl, size: 32, radius: 16)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    LinkText(comment.user?.name ?? "", size: 12) {
                        if let id = comment.user?.id { model.push(.user(id)) }
                    }
                    if let ts = comment.timestamp {
                        Text("\(L("at")) \(Format.duration(Double(ts) / 1000))")
                            .font(.system(size: 11)).foregroundColor(Theme.secondary)
                    }
                }
                Text(comment.body ?? "")
            }
        }
    }
}
