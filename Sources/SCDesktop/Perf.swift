import AppKit
import os

/// Frame-drop diagnostics, on only with SC_PERF=1.
/// Logs each slow frame with the page and which view bodies ran since the last frame.
@MainActor
enum Perf {
    static let on = ProcessInfo.processInfo.environment["SC_PERF"] != nil
    static let log = Logger(subsystem: "SCDesktop", category: "perf")
    private static var bodies: [String: Int] = [:]
    private static var ticker: Ticker?

    /// Must run before the first window: Metal reads this at startup.
    nonisolated static func enableHUD() {
        guard ProcessInfo.processInfo.environment["SC_PERF"] != nil else { return }
        setenv("MTL_HUD_ENABLED", "1", 1)
    }

    static func install(_ model: AppModel) {
        guard on, ticker == nil, let view = NSApp.windows.first?.contentView else { return }
        ticker = Ticker(model: model, view: view)
    }

    /// Call as `let _ = Perf.body("Name")` at the top of a view's body.
    static func body(_ name: String) {
        if on { bodies[name, default: 0] += 1 }
    }

    fileprivate static func frame(_ ms: Double, budget: Double, page: String) {
        // Only report frames that missed their slot by half a frame or more.
        // Over a second is the link pausing (window hidden), not a hitch.
        if ms > budget * 1.5, ms < 1000 {
            let dropped = Int((ms / budget).rounded()) - 1
            let views = bodies.sorted { $0.value > $1.value }.map { "\($0.key)×\($0.value)" }.joined(separator: " ")
            let line = String(format: "hitch %.1fms (%d dropped) page=%@ bodies: %@", ms, dropped, page, views.isEmpty ? "none" : views)
            log.warning("\(line, privacy: .public)")
            FileHandle.standardError.write(Data((line + "\n").utf8))
        }
        bodies.removeAll(keepingCapacity: true)
    }
}

private final class Ticker: NSObject {
    let model: AppModel
    var link: CADisplayLink?
    var last: CFTimeInterval = 0
    var lastTarget: CFTimeInterval = 0

    @MainActor init(model: AppModel, view: NSView) {
        self.model = model
        super.init()
        link = view.displayLink(target: self, selector: #selector(tick))
        link?.add(to: .main, forMode: .common)
    }

    @MainActor @objc func tick(_ link: CADisplayLink) {
        defer { last = link.timestamp; lastTarget = link.targetTimestamp }
        guard last > 0 else { return }
        let page = model.stack.last.map { "\($0)" } ?? model.sidebar?.rawValue ?? "-"
        // ProMotion slows the rate when idle; judge each frame by the slot it was given, not 120 Hz.
        let budget = max(lastTarget - last, link.duration, 1.0 / 120)
        Perf.frame((link.timestamp - last) * 1000, budget: budget * 1000, page: page)
    }
}
