import Foundation

enum Language: String, CaseIterable, Identifiable {
    case english = "en"
    case russian = "ru"

    var id: String { rawValue }

    var name: String {
        switch self {
            case .english: "English"
            case .russian: "Русский"
        }
    }

    static var current: Language = .english
}

/// Looks up the UI string in the current language. English text is the key.
func L(_ key: String) -> String {
    switch Language.current {
        case .english: key
        case .russian: russian[key] ?? key
    }
}

/// "12 tracks" / "12 треков" with Russian plural rules.
func plural(_ n: Int, _ one: String, _ few: String, _ many: String, english: String) -> String {
    guard Language.current == .russian else { return "\(n) \(n == 1 ? english : english + "s")" }
    let mod10 = n % 10, mod100 = n % 100
    let word: String
    if mod10 == 1 && mod100 != 11 {
        word = one
    } else if (2...4).contains(mod10) && !(12...14).contains(mod100) {
        word = few
    } else {
        word = many
    }
    return "\(n) \(word)"
}

func tracksCount(_ n: Int) -> String { plural(n, "трек", "трека", "треков", english: "track") }
func followersCount(_ n: Int?) -> String {
    Language.current == .russian
        ? "\(Format.count(n)) подписчиков" : "\(Format.count(n)) followers"
}

private let russian: [String: String] = [
    "SoundCloud blocked this as automated. Do it on soundcloud.com for now.": "SoundCloud заблокировал это как автоматическое действие. Пока сделайте это на soundcloud.com.",
    "More": "Ещё",
    // Sidebar
    "Feed": "Лента",
    "Discover": "Обзор",
    "Search": "Поиск",
    "Liked Tracks": "Любимые треки",
    "Playlists": "Плейлисты",
    "Albums": "Альбомы",
    "Following": "Подписки",
    "Followers": "Подписчики",
    "History": "История",
    "Your Tracks": "Ваши треки",
    "Queue": "Очередь",
    "Settings": "Настройки",
    "PLAYLISTS": "ПЛЕЙЛИСТЫ",

    // Common
    "Back": "Назад",
    "Refresh": "Обновить",
    "Toggle sidebar": "Показать/скрыть боковую панель",
    "Notifications": "Уведомления",
    "Messages": "Сообщения",
    "Charts": "Чарты",
    "followed you": "подписался(-ась) на вас",
    "commented on": "прокомментировал(а)",
    "liked": "оценил(а)",
    "Follow back": "Подписаться в ответ",
    "Conversation": "Диалог",
    "Reply on soundcloud.com": "Ответить на soundcloud.com",
    "Trending on SoundCloud": "В тренде на SoundCloud",
    "Start station": "Запустить станцию",
    "Share…": "Поделиться…",
    "Share": "Поделиться",
    "Copy link at current time": "Копировать ссылку с текущим временем",
    "Copy embed code": "Копировать код для встраивания",
    "Open on soundcloud.com": "Открыть на soundcloud.com",
    "Station": "Станция",
    "Recommended playlists": "Рекомендуемые плейлисты",
    "Retry": "Повторить",
    "Load more": "Загрузить ещё",
    "Nothing here yet.": "Здесь пока пусто.",
    "Nothing playing": "Ничего не играет",
    "Sign out": "Выйти",
    "Signing in…": "Вход…",
    "Clear": "Очистить",
    "Create": "Создать",
    "Private": "Приватный",
    "Go+ · 30s preview": "Go+ · превью 30 с",
    "The full track needs a SoundCloud Go+ subscription": "Полный трек доступен только с подпиской SoundCloud Go+",
    "Liked": "Нравится",
    "Like": "Нравится",
    "Repost": "Репост",
    "Reposted": "Репостнуто",
    "Follow": "Подписаться",
    "Unfollow": "Отписаться",
    "Copy link": "Копировать ссылку",
    "Link copied": "Ссылка скопирована",
    "Add to queue": "В очередь",
    "Play next": "Играть следующим",
    "Play": "Играть",
    "Shuffle": "Перемешать",
    "Remove from playlist": "Убрать из плейлиста",
    "New playlist with this track": "Новый плейлист с этим треком",
    "Delete playlist": "Удалить плейлист",
    "Add to:": "Добавить в:",
    "Go to": "Открыть",

    // Screens
    "Hear the latest posts and reposts from the people you follow.":
        "Свежие треки и репосты от тех, на кого вы подписаны.",
    "Search for artists, tracks, playlists…": "Артисты, треки, плейлисты…",
    "Tracks": "Треки",
    "People": "Люди",
    "Popular": "Популярное",
    "Reposts": "Репосты",
    "Likes": "Лайки",
    "Comments": "Комментарии",
    "Related tracks": "Похожие треки",
    "Write a comment": "Напишите комментарий",
    "Post": "Отправить",
    "Comments post at the current playback time if this track is playing.":
        "Если трек играет, комментарий привяжется к текущему моменту.",
    "Listening History": "История прослушивания",
    "Queue is empty.": "Очередь пуста.",
    "New playlist title": "Название нового плейлиста",
    "Your playlists": "Ваши плейлисты",
    "Your albums": "Ваши альбомы",
    "PLAYLIST": "ПЛЕЙЛИСТ",
    "ALBUM": "АЛЬБОМ",
    "STATION / MIX": "СТАНЦИЯ / МИКС",
    "Playlist": "Плейлист",
    "Album": "Альбом",
    "reposted": "сделал(а) репост",
    "posted": "опубликовал(а)",
    "followers": "подписчиков",
    "following": "подписок",
    "at": "на",

    // Player
    "Previous": "Предыдущий",
    "Next": "Следующий",
    "Play / Pause": "Пуск / Пауза",
    "Mute": "Без звука",
    "Next up": "Далее",
    "Repeat: off": "Повтор: выкл",
    "Repeat: all": "Повтор: все",
    "Repeat: one": "Повтор: один",

    // Login
    "Sign in with your web session token.": "Войдите с токеном веб-сессии.",
    "1. Sign in at soundcloud.com in your browser.": "1. Войдите на soundcloud.com в браузере.",
    "2. Open DevTools → Application/Storage → Cookies → soundcloud.com.":
        "2. Откройте DevTools → Application/Storage → Cookies → soundcloud.com.",
    "3. Copy the value of the oauth_token cookie and paste it below.":
        "3. Скопируйте значение cookie oauth_token и вставьте ниже.",
    "Sign in": "Войти",
    "The token is stored only on this Mac and is only sent to soundcloud.com.":
        "Токен хранится только на этом Mac и отправляется только на soundcloud.com.",
    "Network": "Сеть",
    "Server": "Сервер",
    "Auto (fastest)": "Авто (самый быстрый)",
    "Test again": "Проверить снова",
    "Testing…": "Проверка…",
    "unreachable": "недоступен",
    "via": "через",
    "SoundCloud routes you to the nearest edge server based on your IP. Auto measures each API host through your connection and uses the fastest.":
        "SoundCloud направляет вас к ближайшему серверу по вашему IP. Режим «Авто» измеряет каждый API-сервер через ваше соединение и выбирает самый быстрый.",

    // Settings
    "Appearance": "Оформление",
    "Theme": "Тема",
    "Language": "Язык",
    "Animate theme changes": "Анимировать смену темы",
    "Show playlists in sidebar": "Показывать плейлисты в боковой панели",
    "Playback": "Воспроизведение",
    "Autoplay related tracks when the queue ends": "Включать похожие треки, когда очередь закончится",
    "Add played tracks to listening history": "Добавлять треки в историю прослушивания",
    "Storage": "Хранилище",
    "Image cache": "Кэш изображений",
    "Clear cache": "Очистить кэш",
    "Account": "Аккаунт",
    "Signed in as": "Вы вошли как",
    "About": "О программе",
    "Unofficial SoundCloud client built with Swift and SwiftUI.":
        "Неофициальный клиент SoundCloud на Swift и SwiftUI.",
    "Cache cleared": "Кэш очищен",
]
