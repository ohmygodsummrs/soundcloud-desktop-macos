import AppKit
import Foundation
import SwiftUI

struct RootView: View {
    var model: AppModel // observed by SCDesktopApp
    @State private var sidebarOpen = true
    /// Content inset changes without animation; resizing the page every frame is what lagged.
    @State private var contentInset = true
    private let sidebarCurve = Animation.timingCurve(0.22, 0.8, 0.2, 1, duration: 0.32)

    var body: some View {
        if model.restoring {
            SplashView()
        } else if model.me == nil {
            LoginView(model: model)
        } else {
            main
        }
    }

    var main: some View {
        let _ = Perf.body("RootView")
        return VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 0) {
                    SidebarSearchField(model: model)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                    if let me = model.me {
                        HStack {
                            RemoteImage(url: me.avatarUrl, size: 32, radius: 16)
                            Text(me.name).lineLimit(1)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)
                        .contentShape(Rectangle())
                        .onTapGesture { model.push(.user(me.id)) }
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(SidebarItem.main) { item in
                                SidebarRow(item: item, selected: model.sidebar == item && model.stack.isEmpty) {
                                    model.select(item)
                                }
                            }
                            let lists = model.ownPlaylists + model.likedPlaylistList
                            if model.showSidebarPlaylists && !lists.isEmpty {
                                Text(L("PLAYLISTS"))
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(Theme.current.sidebarText.color(0.55))
                                    .padding(.top, 14)
                                    .padding(.leading, 16)
                                    .padding(.bottom, 4)
                                ForEach(lists) { playlist in
                                    SidebarPlaylistRow(
                                        playlist: playlist, selected: model.openPlaylistID == playlist.id
                                    ) { model.openPlaylist(playlist.id) }
                                }
                            }
                        }
                    }
                    Spacer()
                    SidebarRow(item: .settings, selected: model.sidebar == .settings && model.stack.isEmpty) {
                        model.select(.settings)
                    }
                }
                // No side padding: rows run edge to edge and carry their own insets.
                .padding(.bottom, 10)
                .frame(width: 240)
                .frame(maxHeight: .infinity, alignment: .top)
                .foregroundColor(Theme.current.sidebarText.color)
                // Fill up under the titlebar too, or the color stops in a hard line
                // below the window buttons.
                .background((Theme.current.glass ? Color.clear : Theme.current.sidebar.color).ignoresSafeArea())
                // Slide only (cheap); the page underneath keeps its size during the animation.
                .offset(x: sidebarOpen ? 0 : -240)
                .allowsHitTesting(sidebarOpen)
                .accessibilityHidden(!sidebarOpen)
                .zIndex(1)
                ScrollView {
                    // The screen's LazyVStack must be the scroll content itself, not inside a VStack.
                    PageContent(model: model)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                // New page starts at the top; Back restores via the view's own state.
                .id(pageKey)
                // Pages scroll under a blurred bar instead of being cut off below the titlebar buttons.
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        if let toast = model.toast {
                            HStack {
                                Text(toast)
                                Spacer()
                                TButton(L("✕")) { model.toast = nil }
                            }
                            .padding(8)
                            .background(Theme.current.surface.color)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        // Playlists opened from the sidebar are a root, so no Back.
                        if model.stack.count > (model.sidebar == nil ? 1 : 0) {
                            HStack {
                                TButton(L("Back"), icon: "chevron.left") { model.back() }
                                Spacer()
                            }
                            .padding([.leading, .trailing, .bottom], 12)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        // Blur and theme tint fade out downward, past the bar, so rows dissolve instead of
                        // meeting a hard edge.
                        Rectangle().fill(.ultraThinMaterial)
                            .overlay(Theme.current.background.color(Theme.current.glass ? 0.4 : 0.85))
                            .mask(LinearGradient(
                                stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.45), .init(color: .clear, location: 1)],
                                startPoint: .top, endPoint: .bottom
                            ))
                            .padding(.bottom, -32)
                            .ignoresSafeArea()
                            .allowsHitTesting(false)
                    }
                    .animation(.easeOut(duration: 0.2), value: model.toast)
                }
                // Width snaps only at the trailing edge; the visible move is a cheap offset.
                .padding(.trailing, contentInset ? 240 : 0)
                .offset(x: sidebarOpen ? 240 : 0)
            }
            .environment(\.pageRefreshVersion, model.refreshCounter)

            if !model.player.queue.isEmpty {
                PlayerBar(model: model, player: model.player)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.25), value: model.player.queue.isEmpty)
        .frame(minWidth: 720, minHeight: 480)
        .modifier(PlainToolbar())
        .toolbar {
            ToolbarItem(placement: .navigation) {
                SidebarToolbarButton(symbol: "sidebar.left", label: L("Toggle sidebar"), color: toolbarColor) {
                    toggleSidebar()
                }
            }
            ToolbarItem(placement: .navigation) {
                RefreshButton(model: model, color: toolbarColor)
            }
        }
    }

    private func toggleSidebar() {
        if sidebarOpen {
            withAnimation(sidebarCurve) { sidebarOpen = false } completion: { contentInset = false }
        } else {
            contentInset = true
            withAnimation(sidebarCurve) { sidebarOpen = true }
        }
    }

    private var toolbarColor: Color {
        sidebarOpen ? Theme.current.sidebarText.color : Theme.current.text.color
    }

    // Refresh starts at the top, where each list's load anchor lives.
    var pageKey: String { (model.stack.last.map { "\($0)" } ?? model.sidebar?.rawValue ?? "") + "-\(model.refreshCounter)" }
}

struct PageContent: View {
    var model: AppModel

    var body: some View {
        if let route = model.stack.last {
            RouteScreen(model: model, route: route)
        } else if let item = model.sidebar {
            SidebarScreen(model: model, item: item)
        }
    }
}

/// Capsule search field at the top of the sidebar, macOS 26 style.
struct SidebarSearchField: View {
    var model: AppModel
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        let p = Theme.current
        HStack(spacing: 6) {
            Icon(name: "magnifyingglass", size: 12, color: p.sidebarText.ns.withAlphaComponent(0.6))
            TextField(L("Search"), text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused)
                .onChange(of: model.searchFocusRequests) { focused = true }
                .onSubmit {
                    model.searchQuery = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    model.select(.search)
                }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(Capsule().fill(p.sidebarText.color(0.1)))
        .overlay(Capsule().strokeBorder(p.sidebarText.color(0.12)))
    }
}

/// Startup screen in the selected theme.
struct SplashView: View {
    var body: some View {
        let p = Theme.current
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(p.accent.color).frame(width: 84, height: 84)
                Icon(name: "cloud.fill", size: 40, color: p.onAccent.ns)
            }
            Text("SoundCloud").font(.system(size: 22, weight: .bold))
            Text(L("Signing in…")).font(.system(size: 12)).foregroundColor(Theme.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct LoginView: View {
    var model: AppModel

    @State var token = ""
    @State var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SoundCloud").font(.system(size: 28, weight: .bold)).foregroundColor(Theme.accent)
            Text(L("Sign in with your web session token."))
            VStack(alignment: .leading, spacing: 4) {
                Text(L("1. Sign in at soundcloud.com in your browser."))
                Text(L("2. Open DevTools → Application/Storage → Cookies → soundcloud.com."))
                Text(L("3. Copy the value of the oauth_token cookie and paste it below."))
            }
            .font(.system(size: 12))
            .foregroundColor(Theme.secondary)
            SecureField("oauth_token", text: $token)
                .frame(width: 420)
            HStack {
                TButton(busy ? L("Signing in…") : L("Sign in")) {
                    busy = true
                    Task {
                        await model.signIn(token: token)
                        busy = false
                    }
                }
                .disabled(busy)
            }
            if let error = model.loginError {
                Text(error).foregroundColor(.red)
            }
            Text(L("The token is stored only on this Mac and is only sent to soundcloud.com."))
                .font(.system(size: 11))
                .foregroundColor(Theme.secondary)
        }
        .padding(32)
        .frame(maxWidth: 520)
        .background(Theme.current.surface.color(0.35))
        .cornerRadius(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SidebarRow: View {
    var item: SidebarItem
    var selected: Bool
    var action: () -> Void

    @State var hovering = false

    static let icons: [SidebarItem: String] = [
        .feed: "dot.radiowaves.left.and.right", .discover: "safari", .search: "magnifyingglass",
        .notifications: "bell", .messages: "envelope", .charts: "chart.bar",
        .likes: "heart", .playlists: "music.note.list", .albums: "square.stack",
        .following: "person.2", .followers: "person.3", .history: "clock.arrow.circlepath",
        .myTracks: "waveform", .queue: "list.bullet", .settings: "gearshape",
    ]

    var body: some View {
        let p = Theme.current
        let fg = selected ? p.onAccent : p.sidebarText
        HStack(spacing: 8) {
            Icon(name: Self.icons[item] ?? "circle", size: 14, color: fg.ns)
                // Wide symbols (person.3) overflow their frame; a fixed slot keeps labels aligned.
                .frame(width: 24)
            Text(L(item.rawValue)).foregroundColor(fg.color)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(selected ? p.accent.color : hovering ? p.sidebarText.color(0.1) : Color.clear)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.easeOut(duration: 0.18), value: selected)
        .onHover { hovering = $0 }
        // Selected row: full-width fill plus a bar on the leading edge.
        .overlay(alignment: .leading) {
            if selected {
                p.onAccent.color(0.9).frame(width: 3).transition(.opacity)
            }
        }
        // Spacer areas aren't hit-testable by default; make the whole row clickable.
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}

struct SidebarPlaylistRow: View {
    var playlist: SCPlaylist
    var selected: Bool
    var action: () -> Void

    @State var hovering = false

    var body: some View {
        let p = Theme.current
        HStack(spacing: 8) {
            RemoteImage(url: playlist.artwork, size: 20, radius: 3)
            Text(playlist.displayTitle)
                .font(.system(size: 12))
                .foregroundColor((selected ? p.onAccent : p.sidebarText).color)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(selected ? p.accent.color : hovering ? p.sidebarText.color(0.1) : Color.clear)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.easeOut(duration: 0.18), value: selected)
        .onHover { hovering = $0 }
        // Selected row: full-width fill plus a bar on the leading edge.
        .overlay(alignment: .leading) {
            if selected {
                p.onAccent.color(0.9).frame(width: 3).transition(.opacity)
            }
        }
        // Spacer areas aren't hit-testable by default; make the whole row clickable.
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}

/// Bottom player bar, laid out like soundcloud.com's.
struct PlayerBar: View {
    var model: AppModel
    var player: Player

    @State var showVolume = false
    @State var volumeHovers = 0
    @State var comments: [SCComment] = []

    /// Narrow windows drop secondary controls instead of squeezing the waveform.
    @State var compact = false

    var body: some View {
        let p = Theme.current
        HStack(spacing: compact ? 10 : 14) {
            transport(p)
            timeline(p)
            volume(p)
            nowPlaying(p).frame(width: compact ? 200 : 360, alignment: .leading)
        }
        .padding(.horizontal, compact ? 12 : 20)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: Bool.self) { $0.size.width < 980 } action: { compact = $0 }
        .animation(.easeOut(duration: 0.2), value: compact)
        .foregroundColor(p.barText.color)
        .background(p.glass ? Color.clear : p.bar.color)
    }

    /// Waveform with timed comments, like the web player; plain bar while it loads.
    func timeline(_ p: Palette) -> some View {
        HStack(spacing: 8) {
            // Position isn't observed (it ticks constantly), so poll it here only.
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                Text(Format.duration(player.position))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundColor(p.barHighlight.color)
            }
            .frame(width: 44, alignment: .trailing)
            if let track = player.current, track.waveformUrl != nil {
                Waveform(
                    url: track.waveformUrl,
                    progress: { [player] in player.duration > 0 ? player.position / player.duration : nil },
                    onSeek: { player.seek(to: $0 * player.duration) },
                    comments: comments,
                    duration: track.seconds,
                    onBar: true
                )
                .frame(height: 34)
            } else {
                SeekBar(fraction: 0, timeline: { [player] in (player.position, player.duration) }) { f in
                    player.seek(to: f * player.duration)
                }
            }
            Text(Format.duration(player.current?.seconds ?? 0))
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .frame(width: 44, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .task(id: player.current?.id) {
            comments = []
            guard let id = player.current?.id else { return }
            let page = try? await model.client.page(SCComment.self, "/tracks/\(id)/comments?threaded=0", limit: 200)
            comments = page?.collection ?? []
        }
    }

    func transport(_ p: Palette) -> some View {
        let dim = p.barText.ns
        return HStack(spacing: 10) {
            IconButton(name: "backward.end.fill", size: 20, color: dim, help: L("Previous")) { player.previous() }
            // A Button, not a tap gesture, so clicks don't drag the movable window.
            Button { player.toggle() } label: {
                ZStack {
                    Circle().fill(p.accent.color).frame(width: 40, height: 40)
                    Icon(name: player.isLoading ? "ellipsis" : player.isPlaying ? "pause.fill" : "play.fill", size: 18, color: p.onAccent.ns)
                }
                .contentShape(Circle())
            }
            .buttonStyle(PressStyle())
            .help(L("Play / Pause"))
            .accessibilityLabel(L("Play / Pause"))
            IconButton(name: "forward.end.fill", size: 20, color: dim, help: L("Next")) { player.next() }
            if !compact {
            IconButton(
                name: "shuffle", size: 17, color: player.shuffle ? p.barHighlight.ns : dim, help: L("Shuffle")
            ) { player.shuffle.toggle() }
            IconButton(
                name: player.repeatMode == .one ? "repeat.1" : L("repeat"), size: 17,
                color: player.repeatMode == .off ? dim : p.barHighlight.ns, help: player.repeatMode.label
            ) { player.repeatMode = player.repeatMode.next }
            }
        }
    }

    func volume(_ p: Palette) -> some View {
        IconButton(
            name: player.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill",
            size: 18, color: p.barText.ns, help: L("Mute")
        ) { model.toggleMute() }
        .onHover { hoverVolume($0) }
        // Vertical slider popping up above the speaker, like soundcloud.com.
        .overlay(alignment: .bottom) {
            if showVolume {
                SeekBar(fraction: player.volume, live: true, vertical: true) { player.volume = $0 }
                    .frame(width: 30, height: 110)
                    .padding(.vertical, 6)
                    .background(p.bar.color)
                    .cornerRadius(8)
                    .shadow(radius: 6)
                    .offset(y: -34)
                    .onHover { hoverVolume($0) }
                    .transition(.scale(scale: 0.85, anchor: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.15), value: showVolume)
    }

    /// Moving from the icon to the popup crosses a gap, so hide after a delay.
    func hoverVolume(_ inside: Bool) {
        volumeHovers += inside ? 1 : -1
        if inside {
            showVolume = true
        } else {
            Task {
                try? await Task.sleep(nanoseconds: 300_000_000)
                if volumeHovers <= 0 {
                    volumeHovers = 0
                    showVolume = false
                }
            }
        }
    }

    @ViewBuilder func nowPlaying(_ p: Palette) -> some View {
        if let track = player.current {
            HStack(spacing: 10) {
                RemoteImage(url: track.artwork, size: 40, radius: 2)
                    .onTapGesture { model.open(track) }
                VStack(alignment: .leading, spacing: 2) {
                    LinkText(track.artist, size: 12, color: p.barText.color(0.6)) {
                        if let id = track.user?.id { model.push(.user(id)) }
                    }
                    LinkText(track.displayTitle, size: 13, color: p.barText.color) { model.open(track) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                IconButton(
                    name: "heart.fill", size: 18,
                    color: model.likedTracks.contains(track.id) ? p.barHighlight.ns : p.barText.ns, help: L("Like")
                ) { model.toggleLike(track) }
                if !compact, let user = track.user {
                    let following = model.following.contains(user.id)
                    IconButton(
                        name: following ? "person.fill.checkmark" : "person.fill.badge.plus", size: 18,
                        color: following ? p.barHighlight.ns : p.barText.ns, help: following ? L("Unfollow") : L("Follow")
                    ) { model.toggleFollow(user) }
                }
                if !compact {
                    IconButton(name: "list.bullet", size: 18, color: p.barText.ns, help: L("Next up")) {
                        model.select(.queue)
                    }
                }
            }
        } else {
            Text(L("Nothing playing")).foregroundColor(p.barText.color(0.6))
        }
    }
}

/// Toolbar strip without the "SoundCloud" title. It's see-through so each
/// column's own color (sidebar, page) runs up to the top edge unbroken.
struct PlainToolbar: ViewModifier {
    func body(content: Content) -> some View {
        let styled = content.toolbarBackground(.hidden, for: .windowToolbar)
        if #available(macOS 15.0, *) {
            // Keeps the window's name for the Window menu and Mission Control.
            styled.toolbar(removing: .title)
        } else {
            styled.navigationTitle("")
        }
    }
}

/// Bare refresh icon for the sidebar's top bar.
struct RefreshButton: View {
    var model: AppModel
    var color: Color? = nil

    var body: some View {
        SidebarToolbarButton(symbol: "arrow.clockwise", label: L("Refresh"), color: color) { Task { await model.refresh() } }
    }
}

/// A shared icon slot keeps both titlebar controls centered and theme-tinted.
struct SidebarToolbarButton: View {
    var symbol: String
    var label: String
    var color: Color? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
                .foregroundStyle(color ?? Theme.current.sidebarText.color)
                .frame(width: 28, height: 28, alignment: .center)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .help(label)
        .accessibilityLabel(label)
    }
}
