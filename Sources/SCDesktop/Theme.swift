import AppKit
import SwiftUI

/// 0xRRGGBB color usable from both SwiftUI and AppKit.
struct RGB: Hashable {
    var hex: UInt32

    init(_ hex: UInt32) { self.hex = hex }

    private var r: Double { Double((hex >> 16) & 0xFF) / 255 }
    private var g: Double { Double((hex >> 8) & 0xFF) / 255 }
    private var b: Double { Double(hex & 0xFF) / 255 }

    var color: Color { Color(red: r, green: g, blue: b) }
    func color(_ opacity: Double) -> Color { Color(red: r, green: g, blue: b, opacity: opacity) }
    var ns: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: 1) }
}

struct Palette: Identifiable {
    var name: String
    var isDark: Bool
    /// Show the Liquid Glass window background instead of a solid fill.
    var glass = false
    var background: RGB
    var sidebar: RGB
    var sidebarText: RGB
    /// Buttons, cards, toasts.
    var surface: RGB
    var bar: RGB
    var barText: RGB
    var text: RGB
    var secondary: RGB
    var accent: RGB
    /// Text drawn on top of `accent`.
    var onAccent: RGB
    var border: RGB
    var play: RGB
    var playIcon: RGB
    /// Accent used on the player bar, when `accent` would blend into it.
    var barAccent: RGB? = nil

    var id: String { name }
    var barHighlight: RGB { barAccent ?? accent }
}

extension Palette {
    static let all: [Palette] = [
        Palette(
            name: "SoundCloud Glass", isDark: true, glass: true,
            background: RGB(0x121212), sidebar: RGB(0x121212), sidebarText: RGB(0xF2F2F2),
            surface: RGB(0x333333), bar: RGB(0x1F1F1F), barText: RGB(0xF2F2F2),
            text: RGB(0xF2F2F2), secondary: RGB(0x999999), accent: RGB(0xFF5500), onAccent: RGB(0xFFFFFF),
            border: RGB(0x3A3A3A), play: RGB(0xFFFFFF), playIcon: RGB(0x111111)
        ),
        Palette(
            name: "SoundCloud Dark", isDark: true,
            background: RGB(0x121212), sidebar: RGB(0x181818), sidebarText: RGB(0xF2F2F2),
            surface: RGB(0x2A2A2A), bar: RGB(0x303030), barText: RGB(0xF2F2F2),
            text: RGB(0xF2F2F2), secondary: RGB(0x999999), accent: RGB(0xFF5500), onAccent: RGB(0xFFFFFF),
            border: RGB(0x3A3A3A), play: RGB(0xFFFFFF), playIcon: RGB(0x111111)
        ),
        Palette(
            name: "SoundCloud Light", isDark: false,
            background: RGB(0xFFFFFF), sidebar: RGB(0xF2F2F2), sidebarText: RGB(0x333333),
            surface: RGB(0xE5E5E5), bar: RGB(0xF2F2F2), barText: RGB(0x333333),
            text: RGB(0x333333), secondary: RGB(0x999999), accent: RGB(0xFF5500), onAccent: RGB(0xFFFFFF),
            border: RGB(0xE5E5E5), play: RGB(0xFF5500), playIcon: RGB(0xFFFFFF)
        ),
        Palette(
            name: "Windows XP", isDark: false,
            background: RGB(0xECE9D8), sidebar: RGB(0x6D8FE0), sidebarText: RGB(0xFFFFFF),
            surface: RGB(0xF4F3EE), bar: RGB(0x245EDC), barText: RGB(0xFFFFFF),
            text: RGB(0x000000), secondary: RGB(0x5A5A5A), accent: RGB(0x316AC5), onAccent: RGB(0xFFFFFF),
            border: RGB(0x003C74), play: RGB(0x3C9B32), playIcon: RGB(0xFFFFFF),
            barAccent: RGB(0x7CE36C)
        ),
        Palette(
            name: "Catppuccin Mocha", isDark: true,
            background: RGB(0x1E1E2E), sidebar: RGB(0x181825), sidebarText: RGB(0xCDD6F4),
            surface: RGB(0x313244), bar: RGB(0x11111B), barText: RGB(0xCDD6F4),
            text: RGB(0xCDD6F4), secondary: RGB(0xA6ADC8), accent: RGB(0xCBA6F7), onAccent: RGB(0x1E1E2E),
            border: RGB(0x45475A), play: RGB(0xCBA6F7), playIcon: RGB(0x1E1E2E)
        ),
        Palette(
            name: "Catppuccin Latte", isDark: false,
            background: RGB(0xEFF1F5), sidebar: RGB(0xE6E9EF), sidebarText: RGB(0x4C4F69),
            surface: RGB(0xCCD0DA), bar: RGB(0xDCE0E8), barText: RGB(0x4C4F69),
            text: RGB(0x4C4F69), secondary: RGB(0x6C6F85), accent: RGB(0x8839EF), onAccent: RGB(0xEFF1F5),
            border: RGB(0xBCC0CC), play: RGB(0x8839EF), playIcon: RGB(0xEFF1F5)
        ),
        Palette(
            name: "GitHub Dark", isDark: true,
            background: RGB(0x0D1117), sidebar: RGB(0x010409), sidebarText: RGB(0xE6EDF3),
            surface: RGB(0x21262D), bar: RGB(0x161B22), barText: RGB(0xE6EDF3),
            text: RGB(0xE6EDF3), secondary: RGB(0x8B949E), accent: RGB(0x2F81F7), onAccent: RGB(0xFFFFFF),
            border: RGB(0x30363D), play: RGB(0x238636), playIcon: RGB(0xFFFFFF)
        ),
        Palette(
            name: "Dracula", isDark: true,
            background: RGB(0x282A36), sidebar: RGB(0x21222C), sidebarText: RGB(0xF8F8F2),
            surface: RGB(0x44475A), bar: RGB(0x191A21), barText: RGB(0xF8F8F2),
            text: RGB(0xF8F8F2), secondary: RGB(0x6272A4), accent: RGB(0xFF79C6), onAccent: RGB(0x282A36),
            border: RGB(0x44475A), play: RGB(0xBD93F9), playIcon: RGB(0x282A36)
        ),
        Palette(
            name: "Nord", isDark: true,
            background: RGB(0x2E3440), sidebar: RGB(0x3B4252), sidebarText: RGB(0xECEFF4),
            surface: RGB(0x434C5E), bar: RGB(0x242933), barText: RGB(0xECEFF4),
            text: RGB(0xECEFF4), secondary: RGB(0x9AA5B8), accent: RGB(0x88C0D0), onAccent: RGB(0x2E3440),
            border: RGB(0x4C566A), play: RGB(0x88C0D0), playIcon: RGB(0x2E3440)
        ),
        Palette(
            name: "Gruvbox Dark", isDark: true,
            background: RGB(0x282828), sidebar: RGB(0x1D2021), sidebarText: RGB(0xEBDBB2),
            surface: RGB(0x3C3836), bar: RGB(0x1D2021), barText: RGB(0xEBDBB2),
            text: RGB(0xEBDBB2), secondary: RGB(0xA89984), accent: RGB(0xFE8019), onAccent: RGB(0x282828),
            border: RGB(0x504945), play: RGB(0xFABD2F), playIcon: RGB(0x282828)
        ),
        Palette(
            name: "Tokyo Night", isDark: true,
            background: RGB(0x1A1B26), sidebar: RGB(0x16161E), sidebarText: RGB(0xC0CAF5),
            surface: RGB(0x292E42), bar: RGB(0x16161E), barText: RGB(0xC0CAF5),
            text: RGB(0xC0CAF5), secondary: RGB(0x565F89), accent: RGB(0x7AA2F7), onAccent: RGB(0x1A1B26),
            border: RGB(0x3B4261), play: RGB(0x7AA2F7), playIcon: RGB(0x1A1B26)
        ),
        Palette(
            name: "Solarized Light", isDark: false,
            background: RGB(0xFDF6E3), sidebar: RGB(0xEEE8D5), sidebarText: RGB(0x586E75),
            surface: RGB(0xE4DDC8), bar: RGB(0xEEE8D5), barText: RGB(0x586E75),
            text: RGB(0x586E75), secondary: RGB(0x93A1A1), accent: RGB(0x268BD2), onAccent: RGB(0xFDF6E3),
            border: RGB(0xD9D2BC), play: RGB(0x268BD2), playIcon: RGB(0xFDF6E3)
        ),
    ]

    static func named(_ name: String?) -> Palette {
        all.first { $0.name == name } ?? all[0]
    }
}

/// The active palette. Views read it while rendering; AppModel re-renders
/// the whole tree when it changes.
enum Theme {
    static var current = Palette.all[0]

    static var accent: Color { current.accent.color }
    static var secondary: Color { current.secondary.color }
    static var placeholder: Color { current.surface.color }
    static var text: Color { current.text.color }

    /// Applies the AppKit side: native controls follow light/dark.
    @MainActor
    static func apply(_ palette: Palette, animated: Bool = false) {
        if animated { crossfade() }
        current = palette
        let appearance = NSAppearance(named: palette.isDark ? .darkAqua : .aqua)
        NSApp.appearance = appearance
        // Windows keep their own appearance once set; text fields follow it.
        NSApp.windows.forEach { $0.appearance = appearance }
        Glass.setEnabled(palette.glass)
    }
}

extension Theme {
    /// Snapshots each window and fades the snapshot out over the re-themed UI.
    @MainActor
    static func crossfade(duration: TimeInterval = 0.3) {
        for window in NSApp.windows where window.isVisible {
            guard let content = window.contentView, let frame = content.superview,
                let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds)
            else { continue }
            content.cacheDisplay(in: content.bounds, to: rep)
            let image = NSImage(size: content.bounds.size)
            image.addRepresentation(rep)

            let overlay = PassthroughImageView(frame: content.frame)
            overlay.image = image
            overlay.imageScaling = .scaleNone
            overlay.autoresizingMask = [.width, .height]
            frame.addSubview(overlay, positioned: .above, relativeTo: content)

            overlay.wantsLayer = true
            // Wait a tick so the new theme has rendered under the snapshot.
            DispatchQueue.main.async {
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 1
                fade.toValue = 0
                fade.duration = duration
                fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                overlay.layer?.add(fade, forKey: "fade")
                overlay.layer?.opacity = 0
            }
            // Remove on a timer, not on animation completion: that callback never
            // fired when the window was inactive, leaving the snapshot stuck on top.
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.1) {
                overlay.removeFromSuperview()
            }
        }
    }
}

/// Snapshot overlay that lets clicks through to the live UI underneath.
private final class PassthroughImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
