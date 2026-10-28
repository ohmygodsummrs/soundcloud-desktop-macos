import Foundation
import SwiftUI

@main
struct SCDesktopApp: App {
    @State var model = AppModel()

    init() { Perf.enableHUD() }

    var body: some Scene {
        WindowGroup("SoundCloud") {
            ThemedRoot(model: model)
                .task {
                    Glass.install()
                    Shortcuts.install(model)
                    Perf.install(model)
                    Theme.apply(Palette.named(model.themeName))
                    await model.restore()
                }
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandMenu("Playback") {
                Button("Play / Pause") { model.player.toggle() }
                Button("Next") { model.player.next() }
                Button("Previous") { model.player.previous() }
                Divider()
                Button("Toggle shuffle") { model.player.shuffle.toggle() }
                Button("Cycle repeat") { model.player.repeatMode = model.player.repeatMode.next }
            }
            CommandMenu("Go") {
                ForEach(SidebarItem.allCases) { item in
                    Button(item.rawValue) { model.select(item) }
                }
                Divider()
                Button("Back") { model.back() }
                Button(L("Refresh")) { Task { await model.refresh() } }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}

/// Applies the palette. Lives in a View, not the Scene, because SwiftUI
/// doesn't re-run scene bodies when the theme changes.
struct ThemedRoot: View {
    var model: AppModel

    var body: some View {
        // Theme.current is a plain static; reading themeName subscribes to changes.
        let key = "\(model.themeName)|\(model.language.rawValue)"
        let p = Theme.current
        RootView(model: model)
            .id(key)
            .foregroundColor(p.text.color)
            .tint(p.accent.color)
            .environment(\.colorScheme, p.isDark ? .dark : .light)
            .background(p.glass ? Color.clear : p.background.color)
    }
}
