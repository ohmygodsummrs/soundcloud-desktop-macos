import AppKit
import SwiftUI

/// Thin line with a dot, drawn by AppKit so position updates don't rebuild
/// SwiftUI views. Click or drag to seek.
struct SeekBar: NSViewRepresentable {
    var fraction: Double
    /// Sends the value continuously while dragging (volume) or only on release (seek).
    var live = false
    /// Drawn bottom-to-top (volume popup).
    var vertical = false
    /// Timeline mode: polled for (position, duration) and draws both times.
    var timeline: (() -> (Double, Double))? = nil
    var onChange: (Double) -> Void

    func makeNSView(context: Context) -> SeekBarView {
        SeekBarView()
    }

    func updateNSView(_ view: SeekBarView, context: Context) {
        view.live = live
        view.vertical = vertical
        view.onChange = onChange
        view.timeline = timeline
        if timeline == nil { view.setFraction(fraction) }
        view.needsDisplay = true
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SeekBarView, context: Context) -> CGSize? {
        vertical
            ? CGSize(width: 20, height: proposal.height ?? 100)
            : CGSize(width: proposal.width ?? 200, height: 20)
    }
}

final class SeekBarView: NSView {
    // Colors come from the theme at draw time; SwiftUI doesn't always
    // call updateNSView when only the theme changed.
    private var fill: NSColor { Theme.current.barHighlight.ns }
    private var track: NSColor { Theme.current.barText.ns.withAlphaComponent(0.25) }
    private var timeColor: NSColor { Theme.current.barText.ns }
    private var drawnTheme = ""
    var live = false
    var vertical = false
    var onChange: (Double) -> Void = { _ in }
    var timeline: (() -> (Double, Double))? {
        didSet { timeline == nil ? stopPolling() : startPolling() }
    }

    private var fraction = 0.0
    private var position = 0.0
    private var duration = 0.0
    private var timer: Timer?
    private var showsTimes: Bool { timeline != nil }
    private let timeWidth: CGFloat = 48
    private var dragFraction: Double?
    private var hovering = false

    override var isFlipped: Bool { true }

    private func startPolling() {
        guard timer == nil, window != nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        poll()
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        guard let (pos, dur) = timeline?() else { return }
        guard pos != position || dur != duration || drawnTheme != Theme.current.name else { return }
        position = pos
        duration = dur
        fraction = dur > 0 ? min(max(pos / dur, 0), 1) : 0
        needsDisplay = true
    }

    /// Extent of the line along its axis.
    private var lineRect: (x: CGFloat, width: CGFloat) {
        let inset: CGFloat = 6 + (showsTimes ? timeWidth + 8 : 0)
        let length = vertical ? bounds.height : bounds.width
        return (inset, max(length - inset * 2, 1))
    }

    /// Rect along the line's axis; flipped to run bottom-to-top when vertical.
    private func axisRect(start: CGFloat, length: CGFloat, thickness: CGFloat) -> NSRect {
        guard vertical else {
            return NSRect(x: start, y: bounds.midY - thickness / 2, width: length, height: thickness)
        }
        return NSRect(x: bounds.midX - thickness / 2, y: bounds.height - start - length, width: thickness, height: length)
    }

    func setFraction(_ value: Double) {
        let clamped = min(max(value.isFinite ? value : 0, 0), 1)
        guard clamped != fraction else { return }
        fraction = clamped
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        drawnTheme = Theme.current.name
        let f = dragFraction ?? fraction
        let (inset, width) = lineRect
        if showsTimes { drawTimes(f) }
        let lineHeight: CGFloat = hovering || dragFraction != nil ? 4 : 2

        track.setFill()
        NSBezierPath(
            roundedRect: axisRect(start: inset, length: width, thickness: lineHeight),
            xRadius: lineHeight / 2, yRadius: lineHeight / 2
        ).fill()

        fill.setFill()
        let filled = width * f
        NSBezierPath(
            roundedRect: axisRect(start: inset, length: filled, thickness: lineHeight),
            xRadius: lineHeight / 2, yRadius: lineHeight / 2
        ).fill()

        let dot: CGFloat = hovering || dragFraction != nil ? 12 : 9
        let knob = axisRect(start: inset + filled - dot / 2, length: dot, thickness: dot)
        NSBezierPath(ovalIn: knob).fill()
    }

    private func drawTimes(_ f: Double) {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        let shown = dragFraction != nil ? f * duration : position
        let left = NSAttributedString(
            string: Format.duration(shown), attributes: [.font: font, .foregroundColor: fill]
        )
        let right = NSAttributedString(
            string: Format.duration(duration), attributes: [.font: font, .foregroundColor: timeColor]
        )
        let y = bounds.midY - left.size().height / 2
        left.draw(at: NSPoint(x: timeWidth - left.size().width, y: y))
        right.draw(at: NSPoint(x: bounds.width - timeWidth, y: y))
    }

    private func value(for event: NSEvent) -> Double {
        let p = convert(event.locationInWindow, from: nil)
        let (inset, width) = lineRect
        // Flipped view: y grows downward, so measure vertical from the bottom.
        let along = vertical ? bounds.height - p.y : p.x
        return min(max(Double((along - inset) / width), 0), 1)
    }

    override func mouseDown(with event: NSEvent) {
        dragFraction = value(for: event)
        if live { onChange(dragFraction!) }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        dragFraction = value(for: event)
        if live { onChange(dragFraction!) }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let v = value(for: event)
        fraction = v
        dragFraction = nil
        onChange(v)
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, timeline != nil { startPolling() } else { stopPolling() }
    }

    override func removeFromSuperview() {
        stopPolling()
        super.removeFromSuperview()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // The window is movable by its background; without this, dragging the
    // (transparent) bar drags the whole window.
    override var mouseDownCanMoveWindow: Bool { false }
}
