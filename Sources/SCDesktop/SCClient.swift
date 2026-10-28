import Foundation

struct SCError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

/// Client for SoundCloud's private web api (api-v2), authenticated with the
/// `oauth_token` cookie from soundcloud.com.
final class SCClient: @unchecked Sendable {
    /// When set, GETs return any cached copy (even old) without the network.
    @TaskLocal static var cacheOnly = false

    static let defaultHost = "api-v2.soundcloud.com"
    /// API host in use; Settings → Network can switch it.
    var host = defaultHost
    var base: String { "https://\(host)" }
    private static let clientIDKey = "scClientID"
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    var token: String?
    private var clientID: String? = UserDefaults.standard.string(forKey: clientIDKey)
    private let session = URLSession(configuration: .default)
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    // MARK: client_id

    /// Scrapes the public web client_id from soundcloud.com's js bundles.
    func refreshClientID() async throws -> String {
        let html = try await fetchText("https://soundcloud.com/")
        let scripts = matches(#"<script crossorigin src="(https://a-v2\.sndcdn\.com/assets/[^"]+\.js)""#, in: html)
        // The id usually lives in one of the last bundles.
        for script in scripts.reversed() {
            guard let js = try? await fetchText(script) else { continue }
            if let id = matches(#"client_id\s*[:=]\s*"([a-zA-Z0-9]{32})""#, in: js).first {
                clientID = id
                UserDefaults.standard.set(id, forKey: Self.clientIDKey)
                return id
            }
        }
        throw SCError(message: "Could not find SoundCloud client_id")
    }

    private func ensureClientID() async throws -> String {
        if let clientID { return clientID }
        return try await refreshClientID()
    }

    private func fetchText(_ url: String) async throws -> String {
        var req = URLRequest(url: URL(string: url)!)
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, _) = try await session.data(for: req)
        return String(decoding: data, as: UTF8.self)
    }

    private func matches(_ pattern: String, in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return re.matches(in: text, range: range).compactMap { m in
            Range(m.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    // MARK: Requests

    /// Sends a request. `path` may be a path ("/me") or a full url (next_href).
    @discardableResult
    func send(
        _ path: String,
        method: String = "GET",
        query: [String: String] = [:],
        body: Any? = nil,
        retried: Bool = false
    ) async throws -> Data {
        let clientID = try await ensureClientID()
        let full = path.hasPrefix("http") ? path : base + path
        guard var comps = URLComponents(string: full) else {
            throw SCError(message: "Bad url \(full)")
        }
        var items = comps.queryItems ?? []
        items.removeAll { $0.name == "client_id" }
        items.append(URLQueryItem(name: "client_id", value: clientID))
        items.append(contentsOf: query.map { URLQueryItem(name: $0.key, value: $0.value) })
        comps.queryItems = items

        var req = URLRequest(url: comps.url!, cachePolicy: .reloadIgnoringLocalCacheData)
        req.httpMethod = method
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("https://soundcloud.com", forHTTPHeaderField: "Origin")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            req.setValue("OAuth \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        if method != "GET" { await ResponseCache.shared.invalidate() }
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        // A stale client_id shows up as 401/403 even with a good token.
        if (status == 401 || status == 403) && !retried {
            _ = try await refreshClientID()
            return try await send(path, method: method, query: query, body: body, retried: true)
        }
        guard (200..<300).contains(status) else {
            debugLog("HTTP \(status) \(method) \(comps.path): \(String(decoding: data.prefix(300), as: UTF8.self))")
            if status == 401 { throw SCError(message: "Not authorized. Token expired?") }
            throw SCError(message: "HTTP \(status) for \(comps.path)")
        }
        return data
    }

    func get<T: Decodable>(_ type: T.Type, _ path: String, query: [String: String] = [:]) async throws -> T {
        let key = cacheKey(path, query)
        let data: Data
        if Self.cacheOnly {
            guard let cached = await ResponseCache.shared.stale(key) else { throw SCError(message: "Not cached") }
            data = cached
        } else if let cached = await ResponseCache.shared.fresh(key) {
            data = cached
        } else {
            do {
                data = try await send(path, query: query)
                if cacheable(path) { await ResponseCache.shared.store(key, data) }
            } catch {
                // Offline: fall back to whatever we saw last.
                guard let cached = await ResponseCache.shared.stale(key) else { throw error }
                data = cached
            }
        }
        debugLog("GET \(path) -> \(data.count) bytes: \(String(decoding: data.prefix(600), as: UTF8.self))")
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw SCError(message: "Decode \(T.self) failed: \(error)")
        }
    }

    /// Cache key without the rotating client_id.
    private func cacheKey(_ path: String, _ query: [String: String]) -> String {
        var comps = URLComponents(string: path.hasPrefix("http") ? path : Self.defaultHost.withScheme + path)
        comps?.host = Self.defaultHost
        var items = (comps?.queryItems ?? []).filter { $0.name != "client_id" }
        items += query.map { URLQueryItem(name: $0.key, value: $0.value) }
        comps?.queryItems = items.sorted { $0.name < $1.name }
        return (token.map { String($0.suffix(6)) } ?? "") + (comps?.string ?? path)
    }

    /// Signed stream urls expire, so never cache them.
    private func cacheable(_ path: String) -> Bool {
        !path.contains("/media/")
    }

    func page<T: Decodable>(_ type: T.Type, _ path: String, limit: Int = 30) async throws -> Page<T> {
        // next_href already carries limit/offset.
        let query = path.hasPrefix("http") ? [:] : ["limit": "\(limit)", "linked_partitioning": "1"]
        return try await get(Page<T>.self, path, query: query)
    }

    // MARK: Endpoints

    func me() async throws -> SCUser { try await get(SCUser.self, "/me") }
    func user(_ id: Int) async throws -> SCUser { try await get(SCUser.self, "/users/\(id)") }
    func track(_ id: Int) async throws -> SCTrack { try await get(SCTrack.self, "/tracks/\(id)") }

    func playlist(_ id: String) async throws -> SCPlaylist {
        let path = id.contains("system-playlists") ? "/system-playlists/\(id)" : "/playlists/\(id)"
        var playlist = try await get(SCPlaylist.self, path, query: ["representation": "full"])
        if let tracks = playlist.tracks {
            playlist.tracks = try await hydrate(tracks)
        }
        return playlist
    }

    /// Fills in stub tracks with full objects, 50 at a time.
    func hydrate(_ tracks: [SCTrack]) async throws -> [SCTrack] {
        let stubIDs = tracks.filter(\.isStub).map(\.id)
        guard !stubIDs.isEmpty else { return tracks }
        var full: [Int: SCTrack] = [:]
        for start in stride(from: 0, to: stubIDs.count, by: 50) {
            let chunk = stubIDs[start..<min(start + 50, stubIDs.count)]
            let ids = chunk.map(String.init).joined(separator: ",")
            let got = try await get([Lossy<SCTrack>].self, "/tracks", query: ["ids": ids])
            for t in got.compactMap(\.value) { full[t.id] = t }
        }
        return tracks.map { $0.isStub ? (full[$0.id] ?? $0) : $0 }
    }

    /// Collects an id list, following next_href.
    func ids(_ path: String, limit: Int = 5000) async -> Set<Int> {
        var out = Set<Int>()
        var next: String? = path
        var first = true
        while let href = next, out.count < 20_000 {
            guard let page = try? await get(IDList.self, href, query: first ? ["limit": "\(limit)"] : [:]) else { break }
            out.formUnion(page.collection)
            next = page.collection.isEmpty ? nil : page.nextHref
            first = false
        }
        return out
    }

    /// Resolves a playable stream url. Prefers progressive mp3, then
    /// non-encrypted HLS (AVPlayer can't do SoundCloud's DRM streams).
    func streamURL(for track: SCTrack) async throws -> URL {
        var track = track
        if track.media == nil || track.trackAuthorization == nil {
            track = try await self.track(track.id)
        }
        debugLog("transcodings \(track.id): " + (track.media?.transcodings ?? []).map {
            "\($0.preset ?? "?") \($0.format.protocol) \($0.format.mimeType) snipped=\($0.snipped ?? false)"
        }.joined(separator: " | "))
        let usable = (track.media?.transcodings ?? []).filter {
            !$0.format.protocol.contains("encrypted") && !($0.preset ?? "").contains("encrypted")
        }
        // Some listed transcodings 404, so try each in order of preference.
        func rank(_ t: SCTranscoding) -> Int {
            switch (t.format.protocol, t.format.mimeType) {
                case ("progressive", _): 0
                // "audio/mpegurl" is the abr_sq master playlist, which 404s.
                case ("hls", let m) where m.hasPrefix("audio/mpeg") && !m.contains("mpegurl"): 1
                case ("hls", let m) where m.contains("mp4"): 2
                case ("hls", _): 3
                default: 9
            }
        }
        let candidates = usable.sorted { rank($0) < rank($1) }
        guard !candidates.isEmpty else {
            throw SCError(message: "No playable stream (track may be DRM or Go+ only)")
        }
        struct StreamResponse: Decodable { var url: String }
        var query: [String: String] = [:]
        if let auth = track.trackAuthorization { query["track_authorization"] = auth }
        var lastError: Error = SCError(message: "No playable stream")
        for pick in candidates {
            do {
                let res = try await get(StreamResponse.self, pick.url, query: query)
                if let url = URL(string: res.url) { return url }
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    // MARK: Actions

    func setTrackLike(_ id: Int, me: Int, on: Bool) async throws {
        try await send("/users/\(me)/track_likes/\(id)", method: on ? "PUT" : "DELETE")
    }

    func setTrackRepost(_ id: Int, on: Bool) async throws {
        try await send("/me/track_reposts/\(id)", method: on ? "PUT" : "DELETE")
    }

    func setPlaylistLike(_ id: String, me: Int, on: Bool) async throws {
        try await send("/users/\(me)/playlist_likes/\(id)", method: on ? "PUT" : "DELETE")
    }

    func setPlaylistRepost(_ id: String, on: Bool) async throws {
        try await send("/me/playlist_reposts/\(id)", method: on ? "PUT" : "DELETE")
    }

    func setFollow(_ id: Int, on: Bool) async throws {
        try await send("/me/followings/\(id)", method: on ? "POST" : "DELETE")
    }

    func postComment(track: Int, body: String, atMs: Int) async throws {
        try await send(
            "/tracks/\(track)/comments", method: "POST",
            body: ["comment": ["body": body, "timestamp": atMs]]
        )
    }

    func createPlaylist(title: String, isPrivate: Bool, trackIDs: [Int]) async throws -> SCPlaylist {
        let data = try await send(
            "/playlists", method: "POST",
            body: ["playlist": ["title": title, "sharing": isPrivate ? "private" : "public", "tracks": trackIDs]]
        )
        return try decoder.decode(SCPlaylist.self, from: data)
    }

    func setPlaylistTracks(_ id: String, trackIDs: [Int]) async throws {
        try await send("/playlists/\(id)", method: "PUT", body: ["playlist": ["tracks": trackIDs]])
    }

    func deletePlaylist(_ id: String) async throws {
        try await send("/playlists/\(id)", method: "DELETE")
    }

    func logPlay(_ id: Int) async {
        _ = try? await send("/me/play-history", method: "POST", body: ["track_urn": "soundcloud:tracks:\(id)"])
    }
}

/// Writes to stderr when the app runs with SC_DEBUG=1.
func debugLog(_ message: String) {
    guard ProcessInfo.processInfo.environment["SC_DEBUG"] != nil else { return }
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

extension String {
    var withScheme: String { "https://" + self }
}

enum ServerChoice: String, CaseIterable, Identifiable {
    case auto, web = "api-v2.soundcloud.com", mobile = "api-mobi.soundcloud.com"

    var id: String { rawValue }
    var host: String { self == .auto ? SCClient.defaultHost : rawValue }
    var label: String {
        switch self {
            case .auto: L("Auto (fastest)")
            case .web: "api-v2"
            case .mobile: "api-mobi"
        }
    }
}

/// Round trip to one API host and the CDN edge that answered.
struct ServerProbe: Identifiable {
    var host: String
    var latency: Double
    var edge: String?
    var ok: Bool

    var id: String { host }

    static func measureAll() async -> [ServerProbe] {
        await withTaskGroup(of: ServerProbe.self) { group in
            for choice in ServerChoice.allCases where choice != .auto {
                group.addTask { await measure(choice.host) }
            }
            var out: [ServerProbe] = []
            for await probe in group { out.append(probe) }
            return out.sorted { $0.host < $1.host }
        }
    }

    /// Best of three requests, so one slow handshake doesn't decide.
    static func measure(_ host: String) async -> ServerProbe {
        var best = Double.infinity
        var edge: String?
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4
        let session = URLSession(configuration: config)
        for _ in 0..<3 {
            var req = URLRequest(url: URL(string: "https://\(host)/")!)
            req.httpMethod = "HEAD"
            let start = Date()
            guard let (_, resp) = try? await session.data(for: req) else { continue }
            best = min(best, Date().timeIntervalSince(start))
            edge = (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "x-amz-cf-pop")
        }
        return ServerProbe(host: host, latency: best, edge: edge, ok: best.isFinite)
    }

    /// CloudFront edge code like "ARN56-P1" → "Stockholm".
    var edgeCity: String? {
        guard let code = edge?.prefix(3) else { return nil }
        let cities = [
            "ARN": "Stockholm", "AMS": "Amsterdam", "FRA": "Frankfurt", "LHR": "London", "CDG": "Paris",
            "WAW": "Warsaw", "HEL": "Helsinki", "OSL": "Oslo", "CPH": "Copenhagen", "VIE": "Vienna",
            "MXP": "Milan", "MAD": "Madrid", "DUB": "Dublin", "PRG": "Prague", "BUD": "Budapest",
            "OTP": "Bucharest", "SOF": "Sofia", "IST": "Istanbul", "TLV": "Tel Aviv", "DXB": "Dubai",
            "IAD": "Washington", "JFK": "New York", "EWR": "Newark", "ORD": "Chicago", "ATL": "Atlanta",
            "DFW": "Dallas", "LAX": "Los Angeles", "SFO": "San Francisco", "SEA": "Seattle",
            "YYZ": "Toronto", "GRU": "São Paulo", "NRT": "Tokyo", "ICN": "Seoul", "SIN": "Singapore",
            "HKG": "Hong Kong", "BOM": "Mumbai", "SYD": "Sydney", "TPE": "Taipei",
        ]
        return cities[String(code)] ?? String(code)
    }
}
