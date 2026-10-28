import SwiftUI

/// A titled row of playlist tiles with round paging arrows, measured off
/// soundcloud.com: 22pt title, 160pt tiles 32pt apart, 32pt arrows.
struct PlaylistCarousel: View {
    var model: AppModel
    var title: String
    var playlists: [SCPlaylist]

    @State var first: String?
    @State var hovering = false

    var body: some View {
        let _ = Perf.body("PlaylistCarousel")
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 22, weight: .semibold))
            // Sized by a plain spacer, with the scroller as an overlay: otherwise the page's
            // LazyVStack re-measures every card in every carousel on each scroll frame.
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: PlaylistCard.height)
                .overlay {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 32) {
                            ForEach(playlists) { p in
                                PlaylistCard(model: model, playlist: p).id(p.id)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.viewAligned)
                    .scrollPosition(id: $first, anchor: .leading)
                    .overlay(alignment: .leading) { arrow(-1) }
                    .overlay(alignment: .trailing) { arrow(1) }
                    .onHover { hovering = $0 }
                }
        }
    }

    /// Pages by four tiles, like the web's slider buttons.
    @ViewBuilder func arrow(_ dir: Int) -> some View {
        let index = playlists.firstIndex { $0.id == first } ?? 0
        let target = min(max(index + dir * 4, 0), max(playlists.count - 1, 0))
        let visible = dir < 0 ? index > 0 : index + 4 < playlists.count
        if hovering && visible {
            Button {
                withAnimation(.easeInOut(duration: 0.35)) { first = playlists[target].id }
            } label: {
                Image(systemName: dir < 0 ? "chevron.left" : "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color(red: 48 / 255, green: 48 / 255, blue: 48 / 255)))
                    .shadow(color: .black.opacity(0.3), radius: 4)
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel(L(dir < 0 ? "Previous" : "Next"))
            // Sit over the artwork's vertical middle.
            .padding(.bottom, 48)
            .padding(.horizontal, 4)
            .transition(.opacity)
        }
    }
}

/// soundcloud.com's playable tile: 160pt artwork with a 3% radius and a faint
/// outline; on hover it dims and shows a 64pt play button and like/more icons.
struct PlaylistCard: View {
    var model: AppModel
    var playlist: SCPlaylist

    @State var hovering = false

    static let size: CGFloat = 160
    static let height: CGFloat = 216

    var body: some View {
        let _ = Perf.body("PlaylistCard")
        let p = Theme.current
        let liked = model.likedPlaylists.contains(playlist.id)
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                RemoteImage(url: playlist.artwork, size: Int(Self.size), radius: Int(Self.size * 0.03))
                RoundedRectangle(cornerRadius: Self.size * 0.03)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                if hovering {
                    Color.black.opacity(0.35)
                        .clipShape(RoundedRectangle(cornerRadius: Self.size * 0.03))
                    Button { model.playPlaylist(playlist.id) } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(p.onAccent.color)
                            .offset(x: 2)
                            .frame(width: 64, height: 64)
                            .background(Circle().fill(p.accent.color))
                    }
                    .buttonStyle(PressStyle())
                    .help(L("Play"))
                    .accessibilityLabel(L("Play"))
                    VStack {
                        Spacer()
                        HStack(spacing: 2) {
                            Spacer()
                            if !playlist.isSystem {
                                IconButton(name: "heart.fill", size: 14, color: liked ? p.accent.ns : .white, help: L("Like")) {
                                    model.toggleLike(playlist)
                                }
                            }
                            if let link = playlist.permalinkUrl {
                                IconButton(name: "link", size: 14, color: .white, help: L("Copy link")) {
                                    copyToPasteboard(link)
                                    model.toast = L("Link copied")
                                }
                            }
                        }
                        .padding(4)
                    }
                }
            }
            .frame(width: Self.size, height: Self.size)
            .animation(.easeOut(duration: 0.15), value: hovering)
            Text(playlist.displayTitle)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .padding(.top, 4)
            if let user = playlist.user {
                Text(user.name).font(.system(size: 14)).foregroundColor(Theme.secondary).lineLimit(1)
            }
        }
        .frame(width: Self.size, height: Self.height, alignment: .topLeading)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { model.push(.playlist(playlist.id)) }
    }
}
