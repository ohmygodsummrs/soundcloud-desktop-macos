import AppKit

/// soundcloud.com's single-key shortcuts. Ignored while typing in a field
/// and when ⌘/⌃/⌥ is held, so menu shortcuts and text editing still work.
@MainActor
enum Shortcuts {
    private static var monitor: Any?
    /// "G" was pressed; the next key picks a page (G then L → Likes).
    private static var goPending = false

    static func install(_ model: AppModel) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event, model) ? nil : event
        }
    }

    /// Returns true when the key was used.
    private static func handle(_ event: NSEvent, _ model: AppModel) -> Bool {
        if NSApp.keyWindow?.firstResponder is NSText { return false }
        let mods = event.modifierFlags.intersection([.command, .control, .option])
        guard mods.isEmpty, model.me != nil else { return false }
        let shift = event.modifierFlags.contains(.shift)
        let player = model.player
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if goPending {
            goPending = false
            let pages: [String: SidebarItem] = [
                "s": .feed, "l": .likes, "p": .playlists, "h": .history, "f": .following, "q": .queue,
            ]
            if let page = pages[key] {
                model.select(page)
                return true
            }
        }

        switch (event.keyCode, shift) {
            case (49, _): player.toggle() // space
            case (124, true): player.next()
            case (123, true): player.previous()
            case (124, false): player.seek(to: min(player.position + 5, player.duration))
            case (123, false): player.seek(to: max(player.position - 5, 0))
            case (126, true): player.volume = min(player.volume + 0.1, 1)
            case (125, true): player.volume = max(player.volume - 0.1, 0)
            default:
                switch key {
                    case "m": model.toggleMute()
                    case "l": if let t = player.current { model.toggleLike(t) }
                    case "r": if let t = player.current { model.toggleRepost(t) }
                    case "s": player.shuffle.toggle()
                    case "q": model.select(.queue)
                    case "/": model.searchFocusRequests += 1
                    case "g": goPending = true
                    case let d where d.count == 1 && Int(d) != nil:
                        // 0–9 jump to 0%–90% of the track.
                        player.seek(to: player.duration * Double(Int(d)!) / 10)
                    default: return false
                }
        }
        return true
    }
}
