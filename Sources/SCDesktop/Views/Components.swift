import AppKit
import Foundation
import SwiftUI

/// Button drawn with theme colors (native buttons ignore the theme).
struct TButton: View {
    @Environment(\.isEnabled) var isEnabled

    var label: String
    var icon: String?
    var prominent = false
    var action: () -> Void

    init(_ label: String, icon: String? = nil, prominent: Bool = false, action: @escaping () -> Void) {
        self.label = label
        self.icon = icon
        self.prominent = prominent
        self.action = action
    }

    @State var hovering = false

    var body: some View {
        let p = Theme.current
        let fg = prominent ? p.onAccent : p.text
        Button(action: action) {
            HStack(spacing: 5) {
            if let icon {
                Icon(name: icon, size: 12, color: fg.ns.withAlphaComponent(isEnabled ? 1 : 0.4))
            }
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(fg.color(isEnabled ? 1 : 0.4))
                .lineLimit(1)
                .fixedSize()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background((prominent ? p.accent : p.surface).color(hovering && isEnabled ? 0.8 : 1))
            .cornerRadius(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.easeOut(duration: 0.15), value: prominent)
    }
}

/// Shrinks slightly while pressed; the one press feedback used app-wide.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Artwork that shows a play/pause overlay on hover or while playing.
struct PlayableArtwork: View {
    var url: String?
    var size: Int
    var radius: Int = 4
    var isCurrent = false
    var isPlaying = false
    var onTap: () -> Void

    @State var hovering = false

    var body: some View {
        ZStack {
            RemoteImage(url: url, size: size, radius: radius)
            if hovering || isCurrent {
                Color(white: 0, opacity: 0.35).frame(width: CGFloat(size), height: CGFloat(size)).cornerRadius(CGFloat(radius))
                Icon(
                    name: isCurrent && isPlaying ? "pause.fill" : "play.fill",
                    size: max(14, size / 4), color: .white
                )
            }
        }
        // No hover scale: rows sliding under the cursor while scrolling would
        // each start an animation.
        .onHover { hovering = $0 }
        .onTapGesture(perform: onTap)
    }
}

/// Plays · likes · reposts · comments with SF Symbols.
/// Marks tracks SoundCloud only plays as a 30s snippet without Go+.
struct PreviewBadge: View {
    var size: CGFloat = 11
    var color = Theme.accent

    var body: some View {
        Text(L("Go+ · 30s preview"))
            .font(.system(size: size, weight: .medium))
            .foregroundColor(color)
            .lineLimit(1)
            .help(L("The full track needs a SoundCloud Go+ subscription"))
    }
}

struct StatsRow: View {
    var track: SCTrack
    var size = 11

    var body: some View {
        let c = Theme.current.secondary
        // Drop stats from the end rather than wrapping numbers in narrow windows.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                stat("play.fill", track.playbackCount, c)
                stat("heart.fill", track.likesCount, c)
                stat("arrow.2.squarepath", track.repostsCount, c)
                stat("text.bubble.fill", track.commentCount, c)
            }
            HStack(spacing: 10) {
                stat("play.fill", track.playbackCount, c)
                stat("heart.fill", track.likesCount, c)
            }
            stat("play.fill", track.playbackCount, c)
        }
    }

    func stat(_ icon: String, _ n: Int?, _ c: RGB) -> some View {
        HStack(spacing: 3) {
            Icon(name: icon, size: size - 1, color: c.ns)
            Text(Format.count(n)).font(.system(size: Double(size))).foregroundColor(c.color).fixedSize()
        }
    }
}

/// Clickable text styled like a link.
struct LinkText: View {
    var text: String
    var size: Double = 13
    var weight: Font.Weight? = nil
    var color: Color? = Theme.secondary
    var action: () -> Void

    init(
        _ text: String, size: Double = 13, weight: Font.Weight? = nil, color: Color? = Theme.secondary,
        action: @escaping () -> Void
    ) {
        self.text = text
        self.size = size
        self.weight = weight
        self.color = color
        self.action = action
    }

    var body: some View {
        Group {
            if let color {
                Text(text).foregroundColor(color)
            } else {
                Text(text)
            }
        }
        .font(.system(size: size, weight: weight ?? .regular))
        .lineLimit(1)
        .onTapGesture(perform: action)
    }
}

struct SectionTitle: View {
    var text: String
    var body: some View {
        Text(L(text)).font(.system(size: 22, weight: .bold))
    }
}

private struct PageRefreshVersionKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    var pageRefreshVersion: Int {
        get { self[PageRefreshVersionKey.self] }
        set { self[PageRefreshVersionKey.self] = newValue }
    }
}

/// Generic paged list with a "Load more" button. Reloads when `key` changes.
struct PagedList<Item: Decodable, Row: View>: View {
    @Environment(\.pageRefreshVersion) private var refreshVersion
    var key: String
    var load: (String?) async throws -> Page<Item>
    var row: (Int, [Item]) -> Row

    @State var items: [Item] = []
    @State var next: String?
    @State var loading = false
    @State var error: String?
    /// Key the shown items were loaded for; they stay on screen during a reload.
    @State var itemsKey: String?
    @State private var requestID = UUID()

    init(
        key: String,
        load: @escaping (String?) async throws -> Page<Item>,
        @ViewBuilder row: @escaping (Int, [Item]) -> Row
    ) {
        self.key = key
        self.load = load
        self.row = row
    }

    // No stack of its own: rows join the page's single LazyVStack. A lazy stack nested
    // in another stack gets its whole height re-estimated on every scroll frame.
    var body: some View {
        // Group spreads modifiers over every child, so the load task sits on one anchor.
        Color.clear.frame(height: 0)
            .task(id: "\(key)|\(refreshVersion)") { await reload() }
        Group {
            if let error {
                Text(error).foregroundColor(.red)
                TButton(L("Retry")) { Task { await reload() } }
            }
            ForEach(items.indices, id: \.self) { i in
                // A single child keeps conditional rows from forcing eager list measurement.
                VStack(alignment: .leading, spacing: 0) { row(i, items) }
            }
            if loading {
                Loader()
            } else if next != nil {
                // Infinite scroll like the web: fetch the next page as the end comes into view.
                Loader().onAppear { Task { await more() } }
            } else if items.isEmpty && error == nil {
                Text(L("Nothing here yet.")).foregroundColor(Theme.secondary)
            }
        }
    }

    func reload() async {
        requestID = UUID()
        loading = false
        error = nil
        // Going back to a list shows it at once instead of refetching.
        if let cached = PageCache.shared.get(key) as? ([Item], String?) {
            items = cached.0
            next = cached.1
            itemsKey = key
            error = nil
            return
        }
        // Keep the current rows until fresh ones land: clearing and repainting
        // every row on Refresh made the list stutter.
        // Paint the last copy from disk at once, then refresh from the network.
        let startKey = key
        if items.isEmpty,
            let cached = try? await SCClient.$cacheOnly.withValue(true, operation: { try await load(nil) }),
            startKey == key
        {
            items = cached.collection
            next = cached.nextHref
            itemsKey = key
        }
        guard !Task.isCancelled else { return }
        await fetch(nil, replace: true)
    }

    func more() async {
        guard let next, !loading else { return }
        await fetch(next)
    }

    func fetch(_ href: String?, replace: Bool = false) async {
        let request = UUID()
        requestID = request
        defer { if requestID == request { loading = false } }
        let startKey = key
        loading = items.isEmpty || href != nil
        error = nil
        do {
            var page = try await load(href)
            var fresh = page.collection
            // Filtered pages (e.g. only albums) can come back empty; keep going.
            var hops = 0
            while fresh.isEmpty, let more = page.nextHref, hops < 8 {
                page = try await load(more)
                fresh = page.collection
                hops += 1
            }
            try Task.checkCancellation()
            guard startKey == key, requestID == request else { return }
            items = replace ? fresh : items + fresh
            next = page.nextHref
            itemsKey = key
            PageCache.shared.set(key, (items, next))
        } catch {
            guard !Task.isCancelled, requestID == request else { return }
            // Rows from another list (e.g. the previous search) must not stand in for this one.
            if itemsKey != key {
                items = []
                next = nil
            }
            if items.isEmpty { self.error = error.localizedDescription }
        }
    }
}

/// Pulsing dots in the accent color; the native spinner is invisible on
/// some themes.
struct Loader: View {
    @State var phase = 0

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(0..<3), id: \.self) { i in
                Circle()
                    .fill(Theme.current.accent.color(i == phase ? 1 : 0.3))
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.vertical, 12)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000)
                phase = (phase + 1) % 3
            }
        }
    }
}

/// Recently loaded list pages, keyed by PagedList key.
@MainActor
final class PageCache {
    static let shared = PageCache()

    private var entries: [String: Any] = [:]
    private var order: [String] = []

    func get(_ key: String) -> Any? { entries[key] }

    func set(_ key: String, _ value: Any) {
        if entries[key] == nil { order.append(key) }
        entries[key] = value
        if order.count > 30 { entries[order.removeFirst()] = nil }
    }

    func clear() {
        entries = [:]
        order = []
    }
}

/// One track in a list.
struct TrackRow: View {
    var model: AppModel
    var track: SCTrack
    var number: Int? = nil
    var caption: String? = nil
    var onPlay: () -> Void
    var onRemove: (() -> Void)? = nil

    var isCurrent: Bool { model.player.current?.id == track.id }

    var body: some View {
        let _ = Perf.body("TrackRow")
        HStack(spacing: 12) {
            if let number {
                Text("\(number)").foregroundColor(Theme.secondary).frame(width: 24)
            }
            PlayableArtwork(
                url: track.artwork, size: 52, isCurrent: isCurrent, isPlaying: model.player.isPlaying
            ) {
                if isCurrent { model.player.toggle() } else { onPlay() }
            }

            VStack(alignment: .leading, spacing: 3) {
                if let caption {
                    Text(caption).font(.system(size: 11)).foregroundColor(Theme.secondary)
                }
                LinkText(
                    track.displayTitle, size: 14, weight: .semibold,
                    color: isCurrent ? Theme.accent : Theme.text
                ) {
                    model.open(track)
                }
                LinkText(track.artist, size: 12) {
                    if let id = track.user?.id { model.push(.user(id)) }
                }
                HStack(spacing: 10) {
                    StatsRow(track: track)
                    if let genre = track.genre, !genre.isEmpty {
                        Text("#\(genre)").font(.system(size: 11)).foregroundColor(Theme.secondary).lineLimit(1)
                    }
                    if track.isPreview { PreviewBadge() }
                }
            }

            Spacer()

            Text(Format.duration(track.seconds))
                .font(.system(size: 12))
                .foregroundColor(Theme.secondary)
            TrackActions(model: model, track: track, onPlay: onPlay, onRemove: onRemove)
        }
        .padding(.vertical, 5)
    }
}

struct TrackActions: View {
    var model: AppModel
    var track: SCTrack
    var onPlay: () -> Void
    var onRemove: (() -> Void)? = nil

    var body: some View {
        let p = Theme.current
        let current = model.player.current?.id == track.id
        HStack(spacing: 2) {
            IconButton(
                name: current && model.player.isPlaying ? "pause.fill" : "play.fill", size: 15,
                color: current ? p.accent.ns : p.text.ns, help: L("Play")
            ) {
                if current { model.player.toggle() } else { onPlay() }
            }
            IconButton(
                name: "heart.fill", size: 15,
                color: model.likedTracks.contains(track.id) ? p.accent.ns : p.secondary.ns, help: L("Like")
            ) { model.toggleLike(track) }
            IconButton(
                name: "arrow.2.squarepath", size: 15,
                color: model.repostedTracks.contains(track.id) ? p.accent.ns : p.secondary.ns, help: L("Repost")
            ) { model.toggleRepost(track) }
            TrackMenu(model: model, track: track, onRemove: onRemove)
        }
    }
}

struct TrackMenu: View {
    var model: AppModel
    var track: SCTrack
    var onRemove: (() -> Void)? = nil

    /// The real Menu is an AppKit pop-up built with all its items; creating one per row
    /// as rows scroll in cost ~35ms per card. Rows get a look-alike until the pointer arrives.
    @State private var armed = false

    var body: some View {
        if armed {
            menu
        } else {
            label
                .frame(width: 44)
                .contentShape(Rectangle())
                .onHover { if $0 { armed = true } }
                .onTapGesture { armed = true }
                .accessibilityElement()
                .accessibilityLabel(L("More"))
                .accessibilityAddTraits(.isButton)
        }
    }

    var label: some View {
        Text("•••").font(.system(size: 13)).foregroundColor(Theme.secondary)
    }

    var menu: some View {
            Menu {
                Button(L("Play next")) { model.player.playNext(track) }
                Button(L("Add to queue")) { model.player.enqueue(track) }
                ForEach(model.ownPlaylists) { p in
                    Button("\(L("Add to:")) \(p.displayTitle)") { model.add(track, to: p) }
                }
                Button(L("New playlist with this track")) {
                    model.createPlaylist(title: track.displayTitle, isPrivate: true, with: track)
                }
                if let user = track.user {
                    Button("\(L("Go to")) \(user.name)") { model.push(.user(user.id)) }
                }
                Button(L("Start station")) { model.startStation(track: track.id) }
                if let link = track.permalinkUrl, let url = URL(string: link) {
                    Divider()
                    ShareLink(L("Share…"), item: url)
                    Button(L("Copy link")) { copyToPasteboard(link) }
                    if model.player.current?.id == track.id, let timed = model.shareLink(track, atCurrentTime: true) {
                        Button(L("Copy link at current time")) { copyToPasteboard(timed) }
                    }
                    Button(L("Copy embed code")) { copyToPasteboard(embedCode(link)) }
                    Button(L("Open on soundcloud.com")) { NSWorkspace.shared.open(url) }
                }
                if let onRemove {
                    Button(L("Remove from playlist"), action: onRemove)
                }
            } label: {
                label
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .frame(width: 44)
    }
}

/// The iframe soundcloud.com's Share → Embed gives.
func embedCode(_ link: String) -> String {
    let encoded = link.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? link
    return "<iframe width=\"100%\" height=\"166\" scrolling=\"no\" frameborder=\"no\" allow=\"autoplay\" "
        + "src=\"https://w.soundcloud.com/player/?url=\(encoded)&color=%23ff5500\"></iframe>"
}

func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

struct PlaylistRow: View {
    var model: AppModel
    var playlist: SCPlaylist
    var caption: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            RemoteImage(url: playlist.artwork, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                if let caption {
                    Text(caption).font(.system(size: 11)).foregroundColor(Theme.secondary)
                }
                if let user = playlist.user {
                    LinkText(user.name, size: 12) { model.push(.user(user.id)) }
                }
                Text(playlist.displayTitle).font(.system(size: 14))
                Text("\(playlist.isAlbum == true ? L("Album") : L("Playlist")) · \(tracksCount(playlist.trackCount ?? playlist.tracks?.count ?? 0))")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.secondary)
            }
            Spacer()
            if !playlist.isSystem {
                TButton(model.likedPlaylists.contains(playlist.id) ? L("♥") : L("♡")) { model.toggleLike(playlist) }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { model.push(.playlist(playlist.id)) }
    }
}

struct UserRow: View {
    var model: AppModel
    var user: SCUser

    var body: some View {
        HStack(spacing: 10) {
            RemoteImage(url: user.avatarUrl, size: 48, radius: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(user.name).font(.system(size: 14))
                Text("\(followersCount(user.followersCount)) · \(tracksCount(user.trackCount ?? 0))")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.secondary)
            }
            Spacer()
            if user.id != model.me?.id {
                TButton(model.following.contains(user.id) ? L("Following") : L("Follow")) { model.toggleFollow(user) }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { model.push(.user(user.id)) }
    }
}

/// Feed / repost entry: either a track or a playlist.
struct StreamRow: View {
    var model: AppModel
    var item: StreamItem
    var onPlay: () -> Void

    var caption: String? {
        guard item.isRepost, let who = item.user?.name else { return nil }
        return "↻ \(who) \(L("reposted"))"
    }

    var body: some View {
        if let track = item.track {
            TrackRow(model: model, track: track, caption: caption, onPlay: onPlay)
        } else if let playlist = item.playlist {
            PlaylistRow(model: model, playlist: playlist, caption: caption)
        }
    }
}

/// Simple tab strip of buttons.
struct Tabs<T: Hashable>: View {
    var options: [(T, String)]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(options.indices), id: \.self) { i in
                let (value, label) = options[i]
                TButton(L(label), prominent: value == selection) { selection = value }
            }
        }
    }
}
