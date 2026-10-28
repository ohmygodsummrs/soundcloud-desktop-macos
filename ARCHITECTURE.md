# Architecture

Everything lives in `Sources/SCDesktop/`. Data flow:

```
SCDesktopApp → ThemedRoot → RootView (sidebar + content + PlayerBar)
                   │
               AppModel (@Observable, environment)
               ├── SCClient  → api-v2 HTTP, ResponseCache
               └── Player    → AVPlayer, queue, Now Playing / media keys
```

## Core files

| File | Role |
|---|---|
| `SCDesktopApp.swift` | `@main` App, window, menu commands; `ThemedRoot` applies theme, installs `Glass` + `Shortcuts`. |
| `AppModel.swift` | App state: signed-in user, `SidebarItem`, `Route` stack, toast, like/repost/follow sets, own & liked playlists, prefs (theme, language, animateThemes, showSidebarPlaylists, autoplayRelated, logPlays, server). Actions: signIn/out, restore, toggleLike/Repost/Follow, playlist CRUD, stations, share links. `Setting` helper for bool prefs. |
| `SCClient.swift` | HTTP client. `send` (any method, auto client_id, OAuth header, 401/403 retry), `get<T>` (cached decode), `page<T>`, typed endpoints (me, user, track, playlist, hydrate, ids, streamURL, likes, reposts, follow, comment, playlists, logPlay). Also `ServerChoice` (api-v2 / api-mobi / auto) and `ServerProbe` latency test. `debugLog` (SC_DEBUG=1). |
| `Models.swift` | `SCUser`, `SCTrack`, `SCTranscoding`, `SCPlaylist`, `SCComment`, `StreamItem`, `LikeItem`, `LibraryItem`, `Activity`, `SCMessage`, `Conversation`, `ChartItem`, `HistoryItem`, `Selection`, `Page<T>` (collection + nextHref), `Lossy<T>`, `IDList`, `Format` (durations/counts). |
| `Player.swift` | Queue, index, play/pause/next/previous/seek, shuffle, `RepeatMode`, volume (persisted), prefetch next stream URL, autoplay related tracks when queue ends, play logging, `MPRemoteCommandCenter` + `MPNowPlayingInfoCenter`. |
| `Storage.swift` | `TokenStore` (file in Application Support, legacy keychain migration), `ImageCache` (disk), `ResponseCache` (5-min TTL memory+disk, stale fallback). |
| `Theme.swift` | `RGB`, `Palette` (named themes, `Palette.all`), `Theme.current`, background image views. |
| `Glass.swift` | Window background: Liquid Glass on macOS 26, vibrancy fallback; disabled for solid themes. |
| `Shortcuts.swift` | soundcloud.com-style single-key shortcuts (space, arrows, `G`+letter page jumps). Ignored in text fields / with ⌘⌃⌥. |
| `Strings.swift` | `Language` (en, ru), `L()`, `plural()`, Russian dictionary. |

## Views (`Views/`)

| File | Contents |
|---|---|
| `RootView.swift` | Main split layout, `SplashView`, `LoginView` (token paste), sidebar rows, `PlayerBar` (timeline, transport, volume), `RefreshButton`. |
| `Screens.swift` | Sidebar screens: Feed, Discover (+RecommendedPlaylists), Search (`SearchKind`), Likes, Library playlists/albums, Users (following/followers), History, My Tracks, Queue. |
| `DetailScreens.swift` | `RouteScreen` dispatcher; `PlaylistScreen`, `UserScreen` (`UserTab`s), `TrackScreen` (comments, post comment, related), `CommentRow`. |
| `SocialScreens.swift` | Notifications, Messages/Conversation, Charts. |
| `SettingsScreen.swift` | Settings sections, `ThemeGallery`/`ThemeCard`, `ThemedToggle`, server picker. |
| `Components.swift` | Shared UI: `TButton`, `PlayableArtwork`, `StatsRow`, `LinkText`, `PagedList` (+`PageCache`), `Loader`, `TrackRow`, `TrackActions`, `TrackMenu`, `PlaylistRow`, `UserRow`, `StreamRow`, `Tabs`, `embedCode`, `copyToPasteboard`. |
| `FeedPost.swift` | Feed post/repost card. |
| `Carousel.swift` | Horizontal playlist carousel. |
| `NativeImages.swift` | `RemoteImage` (AppKit `ArtworkView` + `ArtworkCache`), `Icon`, `IconButton`. |
| `Waveform.swift` | AppKit waveform from SoundCloud waveform JSON, with comment markers. |
| `SeekBar.swift` | AppKit seek bar; polls `Player.position` to avoid SwiftUI churn. |

## Persistence summary
- UserDefaults: `theme`, `language`, `animateThemes`, `showSidebarPlaylists`, `autoplayRelated`, `logPlays`, `server`, `volume`, `scClientID`.
- `~/Library/Application Support/SCDesktop/token` — oauth token.
- `~/Library/Caches/SCDesktop/` — api responses, images.

## Adding things — recipes
- **New sidebar page**: add a `SidebarItem` case → screen view in `Screens.swift` → map it in `SidebarScreen` → icon/label in `RootView` sidebar → `L()` string + Russian.
- **New detail page**: `Route` case → `RouteScreen` switch → `model.push(.x)`.
- **New endpoint**: method on `SCClient` using `get`/`send`; model in `Models.swift`.
- **New setting**: property on `AppModel` with `Setting.bool` + `didSet { Setting.set }` → toggle in `SettingsScreen`.
