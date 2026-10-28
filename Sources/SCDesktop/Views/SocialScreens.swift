import SwiftUI

struct NotificationsScreen: View {
    var model: AppModel

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Notifications")
            PagedList(key: "activities-\(model.refreshCounter)") { href in
                try await model.client.page(Activity.self, href ?? "/activities", limit: 50)
            } row: { i, items in
                ActivityRow(model: model, activity: items[i])
            }
        }
    }
}

struct ActivityRow: View {
    var model: AppModel
    var activity: Activity

    var body: some View {
        HStack(spacing: 10) {
            RemoteImage(url: activity.user?.avatarUrl, size: 40, radius: 20)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    if let user = activity.user {
                        LinkText(user.name, size: 13, weight: .semibold, color: Theme.text) { model.push(.user(user.id)) }
                    }
                    Text(activity.verb).font(.system(size: 13)).foregroundColor(Theme.secondary)
                    if let track = activity.track {
                        LinkText(track.displayTitle, size: 13, color: Theme.text) { model.open(track) }
                    } else if let playlist = activity.playlist {
                        LinkText(playlist.displayTitle, size: 13, color: Theme.text) { model.push(.playlist(playlist.id)) }
                    }
                }
                if let body = activity.comment?.body {
                    Text(body).font(.system(size: 12)).lineLimit(2)
                }
                if let date = activity.createdAt.flatMap(Format.relative) {
                    Text(date).font(.system(size: 11)).foregroundColor(Theme.secondary)
                }
            }
            Spacer()
            if let user = activity.user, activity.verb == L("followed you"), !model.following.contains(user.id) {
                TButton(L("Follow back")) { model.toggleFollow(user) }
            }
        }
        .padding(.vertical, 4)
    }
}

struct MessagesScreen: View {
    var model: AppModel

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Messages")
            if let me = model.me {
                PagedList(key: "conversations-\(model.refreshCounter)") { href in
                    try await model.client.page(Conversation.self, href ?? "/users/\(me.id)/conversations?force=1", limit: 30)
                } row: { i, items in
                    ConversationRow(model: model, conversation: items[i])
                }
            }
        }
    }
}

struct ConversationRow: View {
    var model: AppModel
    var conversation: Conversation

    var body: some View {
        let other = conversation.other(than: model.me?.id)
        HStack(spacing: 10) {
            RemoteImage(url: other?.avatarUrl, size: 44, radius: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(other?.name ?? L("Conversation"))
                    .font(.system(size: 14, weight: conversation.read == false ? .bold : .semibold))
                Text(conversation.lastMessage?.content ?? "")
                    .font(.system(size: 12)).foregroundColor(Theme.secondary).lineLimit(1)
            }
            Spacer()
            if let date = conversation.lastMessage?.sentAt.flatMap(Format.relative) {
                Text(date).font(.system(size: 11)).foregroundColor(Theme.secondary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { model.push(.conversation(conversation.id)) }
    }
}

/// Read-only thread. Sending isn't wired up: the send endpoint couldn't be
/// verified, so replies open soundcloud.com instead.
struct ConversationScreen: View {
    var model: AppModel
    var conversationID: String

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionTitle(text: "Messages")
                Spacer()
                TButton(L("Reply on soundcloud.com"), icon: "arrow.up.right.square") {
                    if let url = URL(string: "https://soundcloud.com/messages") { NSWorkspace.shared.open(url) }
                }
            }
            if let me = model.me {
                PagedList(key: "messages-\(conversationID)-\(model.refreshCounter)") { href in
                    try await model.client.page(
                        SCMessage.self, href ?? "/users/\(me.id)/conversations/\(conversationID)/messages", limit: 50
                    )
                } row: { i, items in
                    MessageBubble(message: items[i], mine: items[i].sender?.id == me.id)
                }
            }
        }
    }
}

struct MessageBubble: View {
    var message: SCMessage
    var mine: Bool

    var body: some View {
        let p = Theme.current
        HStack {
            if mine { Spacer(minLength: 60) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
                Text(message.content ?? "")
                    .font(.system(size: 13))
                    .foregroundColor(mine ? p.onAccent.color : p.text.color)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(mine ? p.accent.color : p.surface.color)
                    .cornerRadius(14)
                if let date = message.sentAt.flatMap(Format.relative) {
                    Text(date).font(.system(size: 10)).foregroundColor(Theme.secondary)
                }
            }
            if !mine { Spacer(minLength: 60) }
        }
    }
}

struct ChartsScreen: View {
    var model: AppModel

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: "Charts")
            Text(L("Trending on SoundCloud")).foregroundColor(Theme.secondary)
            // Only the all-music trending chart still exists: kind=top is empty
            // and per-genre charts 404.
            PagedList(key: "charts-\(model.refreshCounter)") { href in
                try await model.client.page(
                    ChartItem.self, href ?? "/charts?kind=trending&genre=soundcloud%3Agenres%3Aall-music", limit: 50
                )
            } row: { i, items in
                if let track = items[i].track {
                    TrackRow(model: model, track: track, number: i + 1) {
                        let tracks = items.compactMap(\.track)
                        model.player.play(tracks, startAt: tracks.firstIndex { $0.id == track.id } ?? 0)
                    }
                }
            }
        }
    }
}
