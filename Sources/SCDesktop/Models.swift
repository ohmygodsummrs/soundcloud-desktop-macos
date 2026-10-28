import Foundation

// SoundCloud api-v2 models. Almost every field is optional: the API often
// returns stub objects (e.g. playlist tracks with only an id).

struct SCUser: Decodable, Identifiable {
    let id: Int
    var username: String?
    var fullName: String?
    var avatarUrl: String?
    var city: String?
    var countryCode: String?
    var description: String?
    var followersCount: Int?
    var followingsCount: Int?
    var trackCount: Int?
    var playlistCount: Int?
    var permalinkUrl: String?
    var verified: Bool?

    var name: String { username ?? "Unknown" }
}

struct SCTranscoding: Decodable {
    struct Format: Decodable {
        var `protocol`: String
        var mimeType: String
    }

    var url: String
    var preset: String?
    var snipped: Bool?
    var format: Format
}

struct SCMedia: Decodable {
    var transcodings: [SCTranscoding]
}

struct SCTrack: Decodable, Identifiable {
    let id: Int
    var title: String?
    var user: SCUser?
    var artworkUrl: String?
    var duration: Int?
    var fullDuration: Int?
    var playbackCount: Int?
    var likesCount: Int?
    var repostsCount: Int?
    var commentCount: Int?
    var genre: String?
    var description: String?
    var createdAt: String?
    var permalinkUrl: String?
    var media: SCMedia?
    var trackAuthorization: String?
    var waveformUrl: String?
    var policy: String?
    var streamable: Bool?

    /// Stub tracks (from playlists) lack everything except the id.
    var isStub: Bool { title == nil }
    /// SoundCloud only serves a 30s snippet without Go+.
    var isPreview: Bool { policy == "SNIP" }

    var displayTitle: String { title ?? "Track \(id)" }
    var artist: String { user?.name ?? "" }
    var artwork: String? { artworkUrl ?? user?.avatarUrl }
    var seconds: Double { Double(duration ?? 0) / 1000 }
}

struct SCPlaylist: Decodable, Identifiable {
    /// Numeric id for normal playlists, urn for system playlists.
    let id: String
    var urn: String?
    var title: String?
    var user: SCUser?
    var artworkUrl: String?
    var calculatedArtworkUrl: String?
    var tracks: [SCTrack]?
    var trackCount: Int?
    var duration: Int?
    var isAlbum: Bool?
    var likesCount: Int?
    var repostsCount: Int?
    var description: String?
    var setType: String?
    var sharing: String?
    var permalinkUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, urn, title, user, artworkUrl, calculatedArtworkUrl, tracks, trackCount
        case duration, isAlbum, likesCount, repostsCount, description, setType, sharing
        case permalinkUrl
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let int = try? c.decode(Int.self, forKey: .id) {
            id = String(int)
        } else {
            id = try c.decode(String.self, forKey: .id)
        }
        urn = try? c.decode(String.self, forKey: .urn)
        title = try? c.decode(String.self, forKey: .title)
        user = try? c.decode(SCUser.self, forKey: .user)
        artworkUrl = try? c.decode(String.self, forKey: .artworkUrl)
        calculatedArtworkUrl = try? c.decode(String.self, forKey: .calculatedArtworkUrl)
        tracks = (try? c.decode([Lossy<SCTrack>].self, forKey: .tracks))?.compactMap(\.value)
        trackCount = try? c.decode(Int.self, forKey: .trackCount)
        duration = try? c.decode(Int.self, forKey: .duration)
        isAlbum = try? c.decode(Bool.self, forKey: .isAlbum)
        likesCount = try? c.decode(Int.self, forKey: .likesCount)
        repostsCount = try? c.decode(Int.self, forKey: .repostsCount)
        description = try? c.decode(String.self, forKey: .description)
        setType = try? c.decode(String.self, forKey: .setType)
        sharing = try? c.decode(String.self, forKey: .sharing)
        permalinkUrl = try? c.decode(String.self, forKey: .permalinkUrl)
    }

    var isSystem: Bool { id.contains("system-playlists") }
    var numericID: Int? { Int(id) }
    var displayTitle: String { title ?? "Playlist" }
    var artwork: String? {
        artworkUrl ?? calculatedArtworkUrl ?? tracks?.first(where: { $0.artworkUrl != nil })?.artworkUrl
            ?? user?.avatarUrl
    }
}

struct SCComment: Decodable, Identifiable {
    let id: Int
    var body: String?
    var timestamp: Int?
    var createdAt: String?
    var user: SCUser?
}

/// Feed / reposts entry.
struct StreamItem: Decodable {
    var type: String
    var track: SCTrack?
    var playlist: SCPlaylist?
    var user: SCUser?
    var createdAt: String?

    var isRepost: Bool { type.hasSuffix("repost") }
}

/// Likes entry (track or playlist).
struct LikeItem: Decodable {
    var track: SCTrack?
    var playlist: SCPlaylist?
    var createdAt: String?
}

/// /me/library/all entry.
struct LibraryItem: Decodable {
    var type: String
    var playlist: SCPlaylist?
    var systemPlaylist: SCPlaylist?

    var item: SCPlaylist? { playlist ?? systemPlaylist }
    var isAlbum: Bool { type.hasPrefix("album") || item?.isAlbum == true }
}

/// Notification: someone liked, reposted, followed or commented.
struct Activity: Decodable {
    var type: String?
    var createdAt: String?
    var user: SCUser?
    var track: SCTrack?
    var playlist: SCPlaylist?
    var comment: SCComment?

    var verb: String {
        let t = type ?? ""
        if t.contains("follow") { return L("followed you") }
        if t.contains("comment") { return L("commented on") }
        if t.contains("repost") { return L("reposted") }
        if t.contains("like") { return L("liked") }
        return t.replacingOccurrences(of: "-", with: " ")
    }
}

struct SCMessage: Decodable {
    var content: String?
    var sentAt: String?
    var sender: SCUser?
}

/// DM thread. Ids look like "123:456", so keep them as strings.
struct Conversation: Decodable, Identifiable {
    let id: String
    var lastMessage: SCMessage?
    var users: [SCUser]?
    var read: Bool?

    enum CodingKeys: String, CodingKey { case id, lastMessage, users, read }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let int = try? c.decode(Int.self, forKey: .id) { id = String(int) } else { id = try c.decode(String.self, forKey: .id) }
        lastMessage = try? c.decode(SCMessage.self, forKey: .lastMessage)
        users = (try? c.decode([Lossy<SCUser>].self, forKey: .users))?.compactMap(\.value)
        read = try? c.decode(Bool.self, forKey: .read)
    }

    func other(than me: Int?) -> SCUser? { users?.first { $0.id != me } ?? lastMessage?.sender }
}

struct ChartItem: Decodable {
    var track: SCTrack?
}

struct HistoryItem: Decodable {
    var track: SCTrack?
    var playedAt: Int?
}

struct Selection: Decodable {
    var title: String?
    var description: String?
    var items: Page<SCPlaylist>?
}

/// Paged collection. Items that fail to decode are dropped.
struct Page<T: Decodable>: Decodable {
    var collection: [T]
    var nextHref: String?

    enum CodingKeys: String, CodingKey { case collection, nextHref }

    init(collection: [T], nextHref: String?) {
        self.collection = collection
        self.nextHref = nextHref
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        collection = (try c.decode([Lossy<T>].self, forKey: .collection)).compactMap(\.value)
        nextHref = try? c.decode(String.self, forKey: .nextHref)
    }
}

struct Lossy<T: Decodable>: Decodable {
    var value: T?
    init(from decoder: Decoder) throws {
        do {
            value = try T(from: decoder)
        } catch {
            value = nil
            if ProcessInfo.processInfo.environment["SC_DEBUG"] != nil {
                FileHandle.standardError.write(Data("dropped \(T.self): \(error)\n".utf8))
            }
        }
    }
}

struct IDList: Decodable {
    var collection: [Int]
    var nextHref: String?
}

enum Format {
    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let s = Int(seconds)
        if s >= 3600 {
            return String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
        }
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    static func count(_ n: Int?) -> String {
        guard let n else { return "0" }
        switch n {
            case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
            case 1_000...: return String(format: "%.1fK", Double(n) / 1_000)
            default: return "\(n)"
        }
    }

    /// "3h", "2d", "5w" style age for ISO dates.
    private static let iso = ISO8601DateFormatter()
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    static func relative(_ iso: String) -> String? {
        guard let date = Self.iso.date(from: iso) else { return nil }
        relativeFormatter.locale = Locale(identifier: Language.current == .russian ? "ru" : "en")
        return relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    /// Bumps SoundCloud artwork urls up from 100px to 300px.
    static func artwork(_ url: String?, size: String = "t300x300") -> String? {
        url?.replacingOccurrences(of: "-large.", with: "-\(size).")
    }
}
