import Foundation
import ImageIO
import Security

/// Stores the oauth token in a file only this user can read.
///
/// The keychain asked for a password on every rebuild, because ad-hoc
/// signed builds get a new code signature each time. The old keychain item
/// is migrated once and then deleted.
enum TokenStore {
    private static var file: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("SCDesktop/token")
    }

    static func load() -> String? {
        if let data = try? Data(contentsOf: file), let token = String(data: data, encoding: .utf8),
            !token.isEmpty
        {
            return token
        }
        guard let legacy = LegacyKeychain.load() else { return nil }
        save(legacy)
        LegacyKeychain.delete()
        return legacy
    }

    static func save(_ token: String) {
        let dir = file.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        FileManager.default.createFile(
            atPath: file.path, contents: Data(token.utf8), attributes: [.posixPermissions: 0o600]
        )
    }

    static func delete() {
        try? FileManager.default.removeItem(at: file)
        LegacyKeychain.delete()
    }
}

private enum LegacyKeychain {
    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "SCDesktop",
            kSecAttrAccount as String: "oauth_token",
        ]
    }

    static func load() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
            let data = out as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

/// Downloads remote images to disk.
actor ImageCache {
    static let shared = ImageCache()

    private let dir: URL
    private var inflight: [String: Task<URL?, Never>] = [:]

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        dir = caches.appendingPathComponent("SCDesktop/images")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func clear() async {
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        await ArtworkCache.shared.clear()
    }

    /// Bytes used on disk.
    func size() -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.fileSizeKey]
        )) ?? []
        return files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
    }

    func file(for remote: String) async -> URL? {
        guard let url = URL(string: remote) else { return nil }
        let name = (url.host ?? "img") + "-" + url.lastPathComponent
        let local = dir.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: local.path) { return local }
        if let task = inflight[remote] { return await task.value }
        let task = Task<URL?, Never> {
            guard let (data, resp) = try? await URLSession.shared.data(from: url),
                (resp as? HTTPURLResponse)?.statusCode == 200,
                (try? data.write(to: local)) != nil
            else { return nil }
            return local
        }
        inflight[remote] = task
        let result = await task.value
        inflight[remote] = nil
        return result
    }
}


/// Cache for GET responses. Memory entries are fresh for `ttl`; disk
/// entries let lists paint instantly on launch while fresh data loads.
actor ResponseCache {
    static let shared = ResponseCache()

    private let ttl: TimeInterval = 300
    private var memory: [String: (date: Date, data: Data)] = [:]
    private let dir: URL

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        dir = caches.appendingPathComponent("SCDesktop/api")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func fresh(_ key: String) -> Data? {
        guard let entry = memory[key], Date().timeIntervalSince(entry.date) < ttl else { return nil }
        return entry.data
    }

    /// Any stored copy, however old.
    func stale(_ key: String) -> Data? {
        if let entry = memory[key] { return entry.data }
        return try? Data(contentsOf: file(key))
    }

    func store(_ key: String, _ data: Data) {
        memory[key] = (Date(), data)
        try? data.write(to: file(key))
    }

    /// Writes change server state, so cached reads may be wrong now.
    func invalidate() {
        memory = [:]
    }

    func clear() {
        memory = [:]
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func file(_ key: String) -> URL {
        // FNV-1a keeps file names short and stable across launches.
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in key.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return dir.appendingPathComponent(String(hash, radix: 16) + ".json")
    }
}
