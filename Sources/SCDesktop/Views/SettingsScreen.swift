import Foundation
import SwiftUI

struct SettingsScreen: View {
    var model: AppModel

    @State var cacheBytes: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SectionTitle(text: "Settings")

            section("Appearance") {
                Text(L("Theme")).font(.system(size: 13, weight: .semibold))
                ThemeGallery(model: model)
                ThemedToggle(label: L("Animate theme changes"), isOn: model.animateThemes) {
                    model.animateThemes.toggle()
                }
                ThemedToggle(label: L("Show playlists in sidebar"), isOn: model.showSidebarPlaylists) {
                    model.showSidebarPlaylists.toggle()
                }
            }

            section("Language") {
                HStack(spacing: 8) {
                    ForEach(Language.allCases) { lang in
                        TButton(lang.name, prominent: model.language == lang) { model.setLanguage(lang) }
                    }
                }
            }

            section("Playback") {
                ThemedToggle(label: L("Autoplay related tracks when the queue ends"), isOn: model.autoplayRelated) {
                    model.autoplayRelated.toggle()
                }
                ThemedToggle(label: L("Add played tracks to listening history"), isOn: model.logPlays) {
                    model.logPlays.toggle()
                }
            }

            section("Network") {
                Text(L("Server")).font(.system(size: 13, weight: .semibold))
                HStack(spacing: 8) {
                    ForEach(ServerChoice.allCases) { choice in
                        TButton(choice.label, prominent: model.serverChoice == choice) { model.serverChoice = choice }
                    }
                }
                ForEach(model.serverProbes) { probe in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(probe.host == model.client.host ? Theme.accent : Theme.secondary)
                            .frame(width: 8, height: 8)
                        Text(probe.host).font(.system(size: 12, weight: .medium))
                        if probe.ok {
                            Text("\(Int(probe.latency * 1000)) ms").font(.system(size: 12)).foregroundColor(Theme.secondary)
                            if let city = probe.edgeCity {
                                Text("· \(L("via")) \(city)").font(.system(size: 12)).foregroundColor(Theme.secondary)
                            }
                        } else {
                            Text(L("unreachable")).font(.system(size: 12)).foregroundColor(.red)
                        }
                    }
                }
                HStack(spacing: 10) {
                    TButton(model.probing ? L("Testing…") : L("Test again"), icon: "speedometer") {
                        Task { await model.applyServer() }
                    }
                    .disabled(model.probing)
                }
                Text(L("SoundCloud routes you to the nearest edge server based on your IP. Auto measures each API host through your connection and uses the fastest."))
                    .font(.system(size: 11))
                    .foregroundColor(Theme.secondary)
            }

            section("Storage") {
                HStack(spacing: 12) {
                    Text("\(L("Image cache")): \(cacheBytes.map(Self.formatBytes) ?? "…")")
                    TButton(L("Clear cache"), icon: "trash") {
                        Task {
                            await ImageCache.shared.clear()
                            await ResponseCache.shared.clear()
                            PageCache.shared.clear()
                            cacheBytes = await ImageCache.shared.size()
                            model.toast = L("Cache cleared")
                        }
                    }
                }
            }

            section("Account") {
                if let me = model.me {
                    HStack(spacing: 10) {
                        RemoteImage(url: me.avatarUrl, size: 36, radius: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("Signed in as")).font(.system(size: 11)).foregroundColor(Theme.secondary)
                            Text(me.name).font(.system(size: 14, weight: .semibold))
                        }
                        Spacer()
                        TButton(L("Sign out"), icon: "rectangle.portrait.and.arrow.right") { model.signOut() }
                    }
                }
            }

            section("About") {
                Text("SoundCloud Desktop 0.1").font(.system(size: 13, weight: .semibold))
                Text(L("Unofficial SoundCloud client built with Swift and SwiftUI."))
                    .foregroundColor(Theme.secondary)
            }
        }
        .frame(maxWidth: 760, alignment: .leading)
        .task { cacheBytes = await ImageCache.shared.size() }
    }

    func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        let p = Theme.current
        return VStack(alignment: .leading, spacing: 10) {
            Text(L(title).uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.secondary)
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(p.surface.color(p.glass ? 0.35 : 0.45))
            .cornerRadius(10)
        }
    }

    static func formatBytes(_ n: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
    }
}

/// Grid of theme preview cards.
struct ThemeGallery: View {
    var model: AppModel
    var body: some View {
        // Reflows with the window width instead of a fixed 4 per row.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 150), spacing: 12, alignment: .leading)],
                  alignment: .leading, spacing: 12) {
            ForEach(Palette.all) { palette in
                ThemeCard(palette: palette, selected: model.themeName == palette.name) {
                    model.setTheme(palette.name)
                }
            }
        }
    }
}

/// Miniature of the app drawn in a palette's colors.
struct ThemeCard: View {
    var palette: Palette
    var selected: Bool
    var action: () -> Void

    var body: some View {
        let p = palette
        let ring = Theme.current.accent
        VStack(alignment: .leading, spacing: 6) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        p.accent.color.frame(width: 28, height: 6).cornerRadius(3)
                        p.sidebarText.color(0.5).frame(width: 22, height: 4).cornerRadius(2)
                        p.sidebarText.color(0.5).frame(width: 26, height: 4).cornerRadius(2)
                        p.sidebarText.color(0.5).frame(width: 20, height: 4).cornerRadius(2)
                        Spacer()
                    }
                    .padding(6)
                    .frame(width: 40, height: 64)
                    .background(p.glass ? Color(white: 0.2) : p.sidebar.color)
                    VStack(alignment: .leading, spacing: 5) {
                        p.text.color.frame(width: 50, height: 6).cornerRadius(3)
                        HStack(spacing: 4) {
                            p.surface.color.frame(width: 14, height: 14).cornerRadius(2)
                            p.secondary.color.frame(width: 44, height: 4).cornerRadius(2)
                        }
                        HStack(spacing: 4) {
                            p.surface.color.frame(width: 14, height: 14).cornerRadius(2)
                            p.secondary.color.frame(width: 36, height: 4).cornerRadius(2)
                        }
                        Spacer()
                    }
                    .padding(6)
                    .frame(width: 110, height: 64, alignment: .topLeading)
                    .background(p.glass ? Color(white: 0.12) : p.background.color)
                }
                HStack(spacing: 6) {
                    Circle().fill(p.play.color).frame(width: 10, height: 10)
                    p.barHighlight.color.frame(width: 40, height: 2)
                    p.barText.color(0.3).frame(width: 70, height: 2)
                }
                .padding(.horizontal, 6)
                .frame(width: 150, height: 20, alignment: .leading)
                .background(p.glass ? Color(white: 0.16) : p.bar.color)
            }
            .frame(width: 150, height: 84)
            .cornerRadius(8)
            .padding(3)
            .background(selected ? ring.color : Color.clear)
            .cornerRadius(10)

            Text(p.name)
                .font(.system(size: 12, weight: selected ? .semibold : nil))
                .lineLimit(1)
                .frame(width: 150, alignment: .leading)
                .padding(.leading, 4)
        }
        .onTapGesture(perform: action)
    }
}

/// Switch drawn in theme colors.
struct ThemedToggle: View {
    var label: String
    var isOn: Bool
    var action: () -> Void

    var body: some View {
        let p = Theme.current
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                if isOn { Spacer() }
                Circle().fill(Color.white).frame(width: 16, height: 16)
                if !isOn { Spacer() }
            }
            .padding(2)
            .frame(width: 38, height: 20)
            .background(isOn ? p.accent.color : p.secondary.color(0.4))
            .cornerRadius(10)
            Text(label)
            Spacer()
        }
        .onTapGesture(perform: action)
    }
}
