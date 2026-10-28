import AppKit
import SwiftUI

/// SoundCloud-style waveform. Shows progress while the track is playing;
/// clicking seeks (or starts the track if it isn't the current one).
struct Waveform: NSViewRepresentable {
    var url: String?
    /// Returns progress 0...1 when this track is current, else nil.
    var progress: () -> Double?
    var onSeek: (Double) -> Void
    /// Timed comments drawn as ticks; hovering one shows its text.
    var comments: [SCComment] = []
    var duration: Double = 0
    /// Use the player bar's colors instead of the page's.
    var onBar = false

    func makeNSView(context: Context) -> WaveformView {
        WaveformView()
    }

    func updateNSView(_ view: WaveformView, context: Context) {
        view.progress = progress
        view.onSeek = onSeek
        view.onBar = onBar
        view.setComments(comments, duration: duration)
        view.load(url)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: WaveformView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 400, height: proposal.height ?? 64)
    }

    static func dismantleNSView(_ view: WaveformView, coordinator: ()) {
        view.cancelLoad()
    }
}

final class WaveformView: NSView {
    var progress: () -> Double? = { nil }
    var onSeek: (Double) -> Void = { _ in }

    private var url: String?
    private var samples: [Double] = []
    private var bars = NSBezierPath()
    private var markers = NSBezierPath()
    private var drawnSize = NSSize.zero
    private var loadTask: Task<Void, Never>?
    private var shown: Double = 0
    private var hoverX: CGFloat?
    private var timer: Timer?
    var onBar = false
    /// (fraction along the track, "user: text").
    private var marks: [(Double, String)] = []

    override var isFlipped: Bool { true }

    func setComments(_ comments: [SCComment], duration: Double) {
        guard duration > 0 else {
            if !marks.isEmpty { marks = []; drawnSize = .zero; needsDisplay = true }
            return
        }
        let new = comments.compactMap { c -> (Double, String)? in
            guard let ts = c.timestamp, let body = c.body else { return nil }
            return (min(Double(ts) / 1000 / duration, 1), "\(c.user?.name ?? ""): \(body)")
        }
        guard !new.elementsEqual(marks, by: { $0.0 == $1.0 && $0.1 == $1.1 }) else { return }
        marks = new
        drawnSize = .zero
        needsDisplay = true
    }

    func load(_ url: String?) {
        guard url != self.url else { return }
        cancelLoad()
        self.url = url
        samples = []
        drawnSize = .zero
        shown = progress() ?? 0
        needsDisplay = true
        // waveform_url sometimes points at a png; the json sits next to it.
        guard let url, let json = URL(string: url.replacingOccurrences(of: ".png", with: ".json")) else { return }
        loadTask = Task { [weak self] in
            guard let samples = await Self.loadSamples(from: json), !Task.isCancelled,
                let self, self.url == url else { return }
            self.samples = samples
            self.drawnSize = .zero
            self.needsDisplay = true
        }
    }

    nonisolated private static func loadSamples(from url: URL) async -> [Double]? {
        struct Wave: Decodable { var samples: [Double] }
        guard let (data, _) = try? await URLSession.shared.data(from: url), !Task.isCancelled,
            let wave = try? JSONDecoder().decode(Wave.self, from: data) else { return nil }
        let lo = wave.samples.min() ?? 0, hi = wave.samples.max() ?? 1
        let span = max(hi - lo, 1)
        return wave.samples.map { 0.2 + 0.8 * ($0 - lo) / span }
    }

    func cancelLoad() {
        loadTask?.cancel()
        loadTask = nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        timer?.invalidate()
        guard window != nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isHiddenOrHasHiddenAncestor, !self.visibleRect.isEmpty else { return }
                let p = self.progress() ?? 0
                if abs(p - self.shown) > 0.0005 {
                    self.shown = p
                    self.needsDisplay = true
                }
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let p = Theme.current
        let bar: CGFloat = 2, gap: CGFloat = 1
        let count = Int(bounds.width / (bar + gap))
        guard count > 0 else { return }
        // Cache the geometry; progress changes need only three batched fills.
        if drawnSize != bounds.size {
            bars.removeAllPoints()
            markers.removeAllPoints()
            for i in 0..<count {
                let lo = i * samples.count / count
                let hi = min(max(lo + 1, (i + 1) * samples.count / count), samples.count)
                let v = samples.isEmpty ? 0.08 : samples[lo..<hi].reduce(0, +) / Double(hi - lo)
                let h = max(2, CGFloat(v) * bounds.height)
                bars.appendRect(NSRect(x: CGFloat(i) * (bar + gap), y: bounds.height - h, width: bar, height: h))
            }
            for (f, _) in marks {
                markers.appendOval(in: NSRect(x: CGFloat(f) * bounds.width - 1.5, y: 0, width: 3, height: 3))
            }
            drawnSize = bounds.size
        }
        let played = CGFloat(shown) * bounds.width
        let accent = onBar ? p.barHighlight.ns : p.accent.ns
        let rest = onBar ? p.barText.ns.withAlphaComponent(0.35) : p.secondary.ns.withAlphaComponent(0.55)
        rest.setFill()
        bars.fill()
        if let hoverX, hoverX > played {
            NSGraphicsContext.saveGraphicsState()
            NSRect(x: played, y: 0, width: hoverX - played, height: bounds.height).clip()
            accent.withAlphaComponent(0.45).setFill()
            bars.fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        NSGraphicsContext.saveGraphicsState()
        NSRect(x: 0, y: 0, width: played, height: bounds.height).clip()
        accent.setFill()
        bars.fill()
        NSGraphicsContext.restoreGraphicsState()
        (onBar ? p.barText : p.text).ns.withAlphaComponent(0.7).setFill()
        markers.fill()
    }

    override func mouseUp(with event: NSEvent) {
        let x = convert(event.locationInWindow, from: nil).x
        onSeek(min(max(Double(x / bounds.width), 0), 1))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        let x = convert(event.locationInWindow, from: nil).x
        hoverX = x
        toolTip = marks.first { abs(CGFloat($0.0) * bounds.width - x) < 4 }?.1
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hoverX = nil
        needsDisplay = true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var mouseDownCanMoveWindow: Bool { false }

    override func removeFromSuperview() {
        timer?.invalidate()
        super.removeFromSuperview()
    }
}
