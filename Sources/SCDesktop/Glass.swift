import AppKit

/// Puts app windows on a Liquid Glass background (macOS 26+), falling back
/// to a vibrancy material on older systems.
@MainActor
enum Glass {
    private static let tag = 0x6C61_7373 // marks our background view
    private static var observer: NSObjectProtocol?
    private static var enabled = true

    /// Themes with solid backgrounds hide the glass layer and make the window
    /// opaque: a transparent window is re-blended over the desktop on every
    /// scroll frame, which made touchpad scrolling stutter.
    static func setEnabled(_ on: Bool) {
        enabled = on
        for window in NSApp.windows where !(window is NSPanel) {
            window.contentView?.superview?.viewWithTag(tag)?.isHidden = !on
            setOpacity(window)
        }
    }

    private static func setOpacity(_ window: NSWindow) {
        window.isOpaque = !enabled
        window.backgroundColor = enabled ? .clear : Theme.current.background.ns
    }

    static func install() {
        NSApp.windows.forEach(apply)
        guard observer == nil else { return }
        // Not didUpdate: that fires on every event, including each touchpad
        // scroll step, and the work it triggered made scrolling lag.
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { note in
            MainActor.assumeIsolated {
                if let window = note.object as? NSWindow { apply(window) }
            }
        }
    }

    static func apply(_ window: NSWindow) {
        guard let content = window.contentView, !(window is NSPanel) else { return }
        // Sit beside the content view, not inside it, so the hosting view
        // keeps its own subviews.
        guard let frame = content.superview, frame.viewWithTag(tag) == nil else { return }

        // Inserting fullSizeContentView keeps the content size, which would
        // shrink the frame by the titlebar height; keep the frame instead.
        let frameBefore = window.frame
        window.styleMask.insert(.fullSizeContentView)
        window.setFrame(frameBefore, display: true)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        setOpacity(window)
        window.isMovableByWindowBackground = true

        let background = makeBackground()
        background.frame = frame.bounds
        background.autoresizingMask = [.width, .height]
        background.isHidden = !enabled
        frame.addSubview(background, positioned: .below, relativeTo: content)
    }

    private static func makeBackground() -> NSView {
        #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                let glass = TaggedGlassView()
                glass.style = .regular
                glass.cornerRadius = 0
                return glass
            }
        #endif
        let effect = TaggedEffectView()
        effect.material = .underWindowBackground
        effect.blendingMode = .behindWindow
        effect.state = .active
        return effect
    }

    #if compiler(>=6.2)
        @available(macOS 26.0, *)
        private final class TaggedGlassView: NSGlassEffectView {
            override var tag: Int { Glass.tag }
        }
    #endif

    private final class TaggedEffectView: NSVisualEffectView {
        override var tag: Int { Glass.tag }
    }
}
