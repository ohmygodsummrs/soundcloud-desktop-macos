import AVFoundation
import AppKit
import Foundation
import MediaPlayer
import SwiftUI

enum RepeatMode: String {
    case off, all, one

    var next: RepeatMode {
        switch self {
            case .off: .all
            case .all: .one
            case .one: .off
        }
    }

    var label: String {
        switch self {
            case .off: L("Repeat: off")
            case .all: L("Repeat: all")
            case .one: L("Repeat: one")
        }
    }
}

/// AVPlayer-backed queue player with media keys and Now Playing support.
@MainActor
@Observable
final class Player {
    var queue: [SCTrack] = []
    var index: Int?
    var isPlaying = false
    var isLoading = false
    // Not published: the seek bar polls these, so ticks don't rebuild views.
    @ObservationIgnored var position: Double = 0
    @ObservationIgnored var duration: Double = 0
    var volume: Double = UserDefaults.standard.object(forKey: "volume") as? Double ?? 0.8 {
        didSet {
            avPlayer.volume = Float(volume)
            UserDefaults.standard.set(volume, forKey: "volume")
        }
    }
    var shuffle = false
    var repeatMode = RepeatMode.off
    var error: String?

    var client: SCClient
    var autoplayRelated = true
    var logPlays = true
    @ObservationIgnored private let avPlayer = AVPlayer()
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var loadToken = 0
    /// Stream urls resolved ahead of time for the next track.
    @ObservationIgnored private var prefetched: [Int: (url: URL, at: Date)] = [:]
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?

    var current: SCTrack? {
        guard let index, queue.indices.contains(index) else { return nil }
        return queue[index]
    }

    init(client: SCClient) {
        self.client = client
        avPlayer.volume = Float(volume)
        timeObserver = avPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.position = time.seconds.isFinite ? time.seconds : 0
                if let d = self.avPlayer.currentItem?.duration.seconds, d.isFinite, d > 0 {
                    self.duration = d
                }
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.trackEnded() }
        }
        setupRemoteCommands()
    }

    // MARK: Queue control

    /// Replaces the queue with `tracks` and starts at `start`.
    func play(_ tracks: [SCTrack], startAt start: Int) {
        let playable = tracks
        guard playable.indices.contains(start) else { return }
        queue = playable
        load(index: start)
    }

    func enqueue(_ track: SCTrack) {
        queue.append(track)
        if index == nil { load(index: queue.count - 1) }
    }

    func playNext(_ track: SCTrack) {
        let at = (index ?? -1) + 1
        queue.insert(track, at: min(at, queue.count))
        if index == nil { load(index: at) }
    }

    func toggle() {
        guard current != nil else { return }
        if isPlaying { pause() } else { resume() }
    }

    func pause() {
        avPlayer.pause()
        isPlaying = false
        updateNowPlaying()
    }

    func resume() {
        guard current != nil else { return }
        avPlayer.play()
        isPlaying = true
        updateNowPlaying()
    }

    func next() {
        guard let index, !queue.isEmpty else { return }
        if shuffle && queue.count > 1 {
            var n = index
            while n == index { n = Int.random(in: 0..<queue.count) }
            load(index: n)
        } else if index + 1 < queue.count {
            load(index: index + 1)
        } else if repeatMode == .all {
            load(index: 0)
        } else if autoplayRelated, let last = current {
            appendRelated(to: last)
        } else {
            pause()
            seek(to: 0)
        }
    }

    func previous() {
        guard let index else { return }
        if position > 3 || index == 0 {
            seek(to: 0)
        } else {
            load(index: index - 1)
        }
    }

    /// Resolves the next track's stream so skipping starts instantly.
    private func prefetchNext() {
        guard let index, queue.indices.contains(index + 1), !shuffle else { return }
        let next = queue[index + 1]
        guard prefetched[next.id] == nil else { return }
        Task {
            if let url = try? await client.streamURL(for: next) {
                prefetched[next.id] = (url, Date())
            }
        }
    }

    /// Keeps the music going with tracks related to the last one.
    private func appendRelated(to track: SCTrack) {
        let token = loadToken
        Task {
            let page = try? await client.page(SCTrack.self, "/tracks/\(track.id)/related", limit: 20)
            guard token == loadToken, current?.id == track.id else { return }
            let known = Set(queue.map(\.id))
            let fresh = (page?.collection ?? []).filter { !known.contains($0.id) }
            guard !fresh.isEmpty else {
                pause()
                seek(to: 0)
                return
            }
            queue += fresh
            load(index: (index ?? 0) + 1)
        }
    }

    func seek(to seconds: Double) {
        position = seconds
        avPlayer.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        updateNowPlaying()
    }

    func remove(at i: Int) {
        guard queue.indices.contains(i) else { return }
        queue.remove(at: i)
        if let index {
            if i < index { self.index = index - 1 }
            else if i == index {
                if queue.isEmpty { stop() } else { load(index: min(index, queue.count - 1)) }
            }
        }
    }

    func stop() {
        // Invalidate pending streams before they can restart playback.
        loadToken += 1
        statusObservation = nil
        prefetched.removeAll()
        isLoading = false
        error = nil
        avPlayer.replaceCurrentItem(with: nil)
        index = nil
        isPlaying = false
        position = 0
        duration = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func trackEnded() {
        if repeatMode == .one {
            seek(to: 0)
            resume()
        } else {
            next()
        }
    }

    func load(index i: Int) {
        guard queue.indices.contains(i) else { return }
        index = i
        position = 0
        duration = queue[i].seconds
        isLoading = true
        error = nil
        loadToken += 1
        let token = loadToken
        let track = queue[i]
        // Drop the old item now, or its time observer keeps reporting the
        // previous track's position while the new stream resolves.
        avPlayer.replaceCurrentItem(with: nil)
        Task {
            do {
                let url: URL
                if let hit = prefetched[track.id], Date().timeIntervalSince(hit.at) < 240 {
                    url = hit.url
                } else {
                    url = try await client.streamURL(for: track)
                }
                prefetched[track.id] = nil
                guard token == loadToken else { return }
                debugLog("stream \(track.id): \(url.host ?? "") \(url.path)")
                let item = AVPlayerItem(url: url)
                watch(item, track: track)
                avPlayer.replaceCurrentItem(with: item)
                avPlayer.play()
                isPlaying = true
                isLoading = false
                updateNowPlaying()
                prefetchNext()
                if logPlays { await client.logPlay(track.id) }
            } catch {
                guard token == loadToken else { return }
                debugLog("stream error \(track.id): \(error)")
                isLoading = false
                isPlaying = false
                self.error = "\(track.displayTitle): \(error.localizedDescription)"
            }
        }
    }

    /// AVPlayer fails silently unless the item's status is watched.
    private func watch(_ item: AVPlayerItem, track: SCTrack) {
        statusObservation = item.observe(\.status) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let message = item.error?.localizedDescription ?? "unknown error"
            debugLog("playback failed \(track.id): \(String(describing: item.error))")
            Task { @MainActor in
                guard let self, self.current?.id == track.id else { return }
                self.isPlaying = false
                self.error = "\(track.displayTitle): \(message)"
            }
        }
    }

    // MARK: System integration

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.toggle() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            MainActor.assumeIsolated { self?.seek(to: e.positionTime) }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let track = current else { return }
        let info: [String: Any] = [
            MPMediaItemPropertyTitle: track.displayTitle,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused

        guard let art = Format.artwork(track.artwork) else { return }
        let id = track.id
        Task {
            guard let decoded = await ArtworkCache.shared.image(art, pixels: 300),
                current?.id == id
            else { return }
            let image = NSImage(cgImage: decoded, size: NSSize(width: decoded.width, height: decoded.height))
            var latest = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? info
            latest[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            MPNowPlayingInfoCenter.default().nowPlayingInfo = latest
        }
    }
}
