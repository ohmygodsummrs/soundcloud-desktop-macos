import Foundation
import SwiftUI

/// Feed entry styled after Nuage: who posted it, then a large card with
/// artwork, title, stats and description.
struct FeedPost: View {
    var model: AppModel
    var item: StreamItem
    var onPlay: () -> Void

    var body: some View {
        let _ = Perf.body("FeedPost")
        let p = Theme.current
        VStack(alignment: .leading, spacing: 10) {
            if let user = item.user {
                HStack(spacing: 8) {
                    RemoteImage(url: user.avatarUrl, size: 26, radius: 13)
                    Text(user.name).font(.system(size: 13, weight: .semibold))
                    Text(L(item.isRepost ? "reposted" : "posted"))
                        .font(.system(size: 13))
                        .foregroundColor(Theme.secondary)
                    if let date = item.createdAt.flatMap(Format.relative) {
                        Text("· \(date)").font(.system(size: 12)).foregroundColor(Theme.secondary)
                    }
                }
                .onTapGesture { model.push(.user(user.id)) }
            }
            if let track = item.track {
                FeedTrackCard(model: model, track: track, onPlay: onPlay)
            } else if let playlist = item.playlist {
                PlaylistRow(model: model, playlist: playlist)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        // A rounded fill, not .cornerRadius: clipping the card made every frame mask the artwork offscreen.
        .background(RoundedRectangle(cornerRadius: 12).fill(p.surface.color(p.glass ? 0.25 : 0.35)))
        .padding(.bottom, 6)
    }
}

struct FeedTrackCard: View {
    var model: AppModel
    var track: SCTrack
    var onPlay: () -> Void

    var body: some View {
        let _ = Perf.body("FeedTrackCard")
        let p = Theme.current
        let isCurrent = model.player.current?.id == track.id
        let liked = model.likedTracks.contains(track.id)
        let reposted = model.repostedTracks.contains(track.id)
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                PlayableArtwork(
                    url: track.artwork, size: 110, radius: 6,
                    isCurrent: isCurrent, isPlaying: model.player.isPlaying
                ) {
                    if isCurrent { model.player.toggle() } else { onPlay() }
                }
                HStack(spacing: 0) {
                    IconButton(
                        name: "heart.fill", size: 14, color: liked ? p.accent.ns : p.secondary.ns, help: L("Like")
                    ) { model.toggleLike(track) }
                    IconButton(
                        name: "arrow.2.squarepath", size: 14, color: reposted ? p.accent.ns : p.secondary.ns,
                        help: L("Repost")
                    ) { model.toggleRepost(track) }
                    TrackMenu(model: model, track: track)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                LinkText(
                    track.displayTitle, size: 17, weight: .bold, color: isCurrent ? Theme.accent : Theme.text
                ) { model.open(track) }
                LinkText(track.artist, size: 13) {
                    if let id = track.user?.id { model.push(.user(id)) }
                }
                HStack(spacing: 10) {
                    StatsRow(track: track)
                    Text(Format.duration(track.seconds)).font(.system(size: 11)).foregroundColor(Theme.secondary)
                    if track.isPreview { PreviewBadge() }
                    if let genre = track.genre, !genre.isEmpty {
                        Text("#\(genre)").font(.system(size: 11)).foregroundColor(Theme.secondary).lineLimit(1)
                    }
                }
                if let d = track.description?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty {
                    Text(d.replacingOccurrences(of: "\n", with: " "))
                        .font(.system(size: 12))
                        .foregroundColor(Theme.secondary)
                        .lineLimit(3)
                        .padding(.top, 6)
                }
            }
            Spacer()
        }
    }
}
