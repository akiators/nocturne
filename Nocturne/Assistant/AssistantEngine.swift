import Foundation

/// Локальный музыкальный ассистент (аналог Beyond — бесплатно, без квот и сервера).
/// Это НЕ LLM: детерминированный интент-движок на правилах RU/EN,
/// выполняет действия с плеером, ищет музыку, собирает плейлисты по описанию,
/// показывает статистику и ищет треки по строке текста.
@MainActor
final class AssistantEngine: ObservableObject {
    struct Message: Identifiable {
        enum Role { case user, assistant }
        let id = UUID()
        let role: Role
        let text: String
        var tracks: [Track] = []
        var draft: PlaylistDraft? = nil
    }

    struct PlaylistDraft {
        let name: String
        let tracks: [Track]
    }

    @Published var messages: [Message] = []
    @Published var isProcessing = false

    private let player: PlayerController
    private let search: SearchService
    private let wave: WaveFeedService
    private let store: LibraryStore
    private let lyrics: LyricsService
    private let stats: StatsService

    init(player: PlayerController, search: SearchService, wave: WaveFeedService,
         store: LibraryStore, lyrics: LyricsService) {
        self.player = player
        self.search = search
        self.wave = wave
        self.store = store
        self.lyrics = lyrics
        self.stats = StatsService(store: store)
    }

    // MARK: - Intents

    enum Intent {
        case play(query: String)
        case playWave
        case pause
        case resume
        case next
        case previous
        case toggleRepeat(mode: RepeatMode?)
        case toggleShuffle
        case similarToCurrent
        case createPlaylist(description: String)
        case showStats
        case findLyrics(query: String)
        case fallbackSearch(query: String)
    }

    static func parse(_ input: String) -> Intent {
        let text = input.lowercased().trimmed
        let words = text.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return .fallbackSearch(query: input) }

        func hasAny(_ prefixes: [String]) -> Bool { prefixes.contains { text.hasPrefix($0) } }
        func contains(_ needles: [String]) -> Bool { needles.contains { text.contains($0) } }

        // Пауза/стоп раньше play («останови» тоже play-подобное)
        if contains(["пауза", "останови", "стоп"]) && !contains(["собери", "плейлист"]) {
            return .pause
        }
        if contains(["продолж", "возобнови"]) { return .resume }
        if contains(["следующий", "дальше трек", "next", "скип", "пропусти"]) { return .next }
        if contains(["предыдущ", "назад"]) { return .previous }

        if contains(["повтор"]) || contains(["repeat"]) {
            if contains(["выключ", "отключ", "off", "убрать"]) { return .toggleRepeat(mode: .off) }
            if contains(["один трек", "один", "one", "этот трек"]) { return .toggleRepeat(mode: .one) }
            if contains(["всю очередь", "все", "queue", "all"]) { return .toggleRepeat(mode: .all) }
            return .toggleRepeat(mode: nil)
        }
        if contains(["перемеш", "шаффл", "shuffle", "случайный порядок"]) { return .toggleShuffle }

        if contains(["похож"]) || contains(["similar"]) { return .similarToCurrent }
        if contains(["волну", "волна", "my wave", "моя волна"]) { return .playWave }

        if contains(["статистик", "стата", "сколько слушал", "статистику", "stats"]) {
            return .showStats
        }
        if contains(["по тексту", "строчке текста", "по строчке", "текст песни"]) {
            let query = strip(text, prefixes: ["найди", "поиск", "search", "трек", "песню"])
            return .findLyrics(query: query)
        }

        if hasAny(["собери плейлист", "составь плейлист", "сделай плейлист", "плейлист под", "плейлист по",
                   "create playlist", "generate playlist", "подбери музыку"]) {
            let description = strip(text, prefixes: ["собери плейлист", "составь плейлист", "сделай плейлист",
                                                     "плейлист под", "плейлист по", "create playlist",
                                                     "generate playlist", "подбери музыку"])
            return .createPlaylist(description: description)
        }

        if hasAny(["включи", "играй", "поставь", "запусти", "слушать", "воспроизведи",
                   "play", "listen to", "put on"]) {
            let query = strip(text, prefixes: ["включи", "играй", "играть", "поставь", "запусти",
                                               "слушать", "воспроизведи", "play", "listen to", "put on",
                                               "песню", "трек", "song", "track"])
            return .play(query: query)
        }

        // Похож на запрос трека — ищем как fallback.
        return .fallbackSearch(query: input)
    }

    private static func strip(_ text: String, prefixes: [String]) -> String {
        var result = text
        for prefix in prefixes {
            if result.hasPrefix(prefix) {
                result = String(result.dropFirst(prefix.count)).trimmed
            } else {
                result = result.replacingOccurrences(of: " \(prefix) ", with: " ")
            }
        }
        return result.trimmed
    }

    // MARK: - Chat

    func send(_ input: String) async {
        let userMessage = Message(role: .user, text: input)
        messages.append(userMessage)
        isProcessing = true
        defer { isProcessing = false }

        let intent = Self.parse(input)
        let reply = await execute(intent, originalInput: input)
        messages.append(Message(role: .assistant, text: reply.text, tracks: reply.tracks, draft: reply.draft))
    }

    private func execute(_ intent: Intent, originalInput: String) async -> (text: String, tracks: [Track], draft: PlaylistDraft?) {
        switch intent {
        case .play(let query):
            guard !query.isEmpty else { return ("Что включить? Назовите трек, исполнителя или альбом.", [], nil) }
            let (results, _) = await search.unifiedSearch(query, limit: 20)
            guard let track = results.tracks.first else {
                return ("Не нашёл «\(query)» в подключённых источниках. Попробуйте иначе.", [], nil)
            }
            player.play(track, in: results.tracks, startIndex: 0)
            return ("Играю: \(track.artist) — \(track.title) [\(track.provider.displayName)].", results.tracks, nil)

        case .playWave:
            let waveTracks = await wave.buildWave(count: 20)
            guard let first = waveTracks.first else {
                return ("Волна пока пуста: подключите источники или поставьте лайки.", [], nil)
            }
            player.play(first, in: waveTracks, startIndex: 0)
            return ("Моя волна включена: \(waveTracks.count) треков.", waveTracks, nil)

        case .pause:
            player.pause()
            return ("Пауза.", [], nil)

        case .resume:
            player.resume()
            return ("Продолжаю.", [], nil)

        case .next:
            player.next()
            if let track = player.currentTrack {
                return ("Следующий: \(track.artist) — \(track.title).", [track], nil)
            }
            return ("Очередь пуста.", [], nil)

        case .previous:
            player.previous()
            if let track = player.currentTrack {
                return ("Назад: \(track.artist) — \(track.title).", [track], nil)
            }
            return ("В начале очереди.", [], nil)

        case .toggleRepeat(let mode):
            let newMode: RepeatMode = mode ?? (player.repeatMode == .off ? .all : .off)
            player.repeatMode = newMode
            let label: String
            switch newMode {
            case .off: label = "Повтор выключен."
            case .all: label = "Повтор всей очереди."
            case .one: label = "Повтор одного трека."
            }
            return (label, [], nil)

        case .toggleShuffle:
            player.shuffleOn.toggle()
            return (player.shuffleOn ? "Перемешивание включено." : "Порядок очереди восстановлен.", [], nil)

        case .similarToCurrent:
            guard let current = player.currentTrack else {
                return ("Сейчас ничего не играет — включите трек, и я подберу похожие.", [], nil)
            }
            let similar = await wave.radio(for: current, count: 15)
            guard let first = similar.first else {
                return ("Похожие треки не нашлись. Попробуйте ещё раз.", [], nil)
            }
            player.play(first, in: similar, startIndex: 0)
            return ("Радио по треку «\(current.title)»: \(similar.count) похожих.", similar, nil)

        case .createPlaylist(let description):
            let draft = await generatePlaylist(from: description)
            guard let draft, !draft.tracks.isEmpty else {
                return ("Не удалось собрать плейлист по описанию «\(description)». Уточните жанр, настроение или исполнителей.", [], nil)
            }
            return ("Собрал плейлист «\(draft.name)»: \(draft.tracks.count) треков. Проверьте и сохраните.", draft.tracks, draft)

        case .showStats:
            let snapshot = stats.snapshot(period: .month)
            var lines: [String] = ["Статистика за месяц:"]
            lines.append("Всего прослушано: \(snapshot.totalSeconds.humanDuration)")
            if let topArtist = snapshot.topArtists.first {
                lines.append("Топ-исполнитель: \(topArtist.0) (\(topArtist.1) прослушиваний)")
            }
            if let topTrack = snapshot.topTracks.first {
                lines.append("Топ-трек: \(topTrack.0.artist) — \(topTrack.0.title) (\(topTrack.1))")
            }
            if snapshot.topArtists.isEmpty {
                lines.append("Данных пока нет — слушайте музыку, и статистика соберётся.")
            }
            return (lines.joined(separator: "\n"), snapshot.topTracks.map(\.0).prefix(5).map { $0 }, nil)

        case .findLyrics(let query):
            let hits = await lyrics.searchByLyrics(query)
            guard !hits.isEmpty else {
                return ("По строчке «\(query)» ничего не нашлось в LRCLIB.", [], nil)
            }
            let tracks = hits.compactMap(\.track)
            let names = hits.prefix(5).map { "• \($0.artist) — \($0.title)" }.joined(separator: "\n")
            return ("Нашёл по тексту:\n\(names)", tracks, nil)

        case .fallbackSearch(let query):
            let (results, _) = await search.unifiedSearch(query, limit: 15)
            if results.tracks.isEmpty {
                return ("Не нашёл «\(query)». Попробуйте назвать трек или исполнителя.", [], nil)
            }
            let list = results.tracks.prefix(5).map { "• \($0.artist) — \($0.title)" }.joined(separator: "\n")
            return ("Может быть, вы искали:\n\(list)", results.tracks, nil)
        }
    }

    // MARK: - Генерация плейлиста по описанию

    func generatePlaylist(from description: String) async -> PlaylistDraft? {
        let cleaned = description.trimmed
        guard !cleaned.isEmpty else { return nil }

        var queries: [String] = [cleaned]

        // Настроение → жанровые запросы.
        let moodMap: [(mood: [String], queries: [String])] = [
            (["тренировк", "спорт", "качал", "бег"], ["workout edm", "dance hits"]),
            (["спокой", "расслаб", "медитац", "сон", "ночь"], ["ambient chill", "calm piano"]),
            (["весел", "радост", "позитив"], ["happy pop", "feel good"]),
            (["груст", "печал", "тоска"], ["sad acoustic", "melancholic indie"]),
            (["фокус", "работа", "учеба", "концентр"], ["focus instrumental", "lofi study"]),
            (["романтик", "любов", "свидан"], ["romantic ballads", "love songs"]),
            (["дожд", "осен", "зим"], ["rainy day jazz", "cozy autumn"])
        ]
        let lower = cleaned.lowercased()
        for (mood, generated) in moodMap where mood.contains(where: { lower.contains($0) }) {
            queries.append(contentsOf: generated)
        }

        var pool: [Track] = []
        var seen = Set<String>()
        for query in queries.prefix(4) {
            let (results, _) = await search.unifiedSearch(query, limit: 20)
            for track in results.tracks where seen.insert(track.searchKey).inserted {
                pool.append(track)
            }
        }
        guard pool.count >= 4 else { return nil }

        let profile = RecommendationEngine.buildProfile(store: store, explorationRate: 0.35)
        let tracks = RecommendationEngine.selectWave(candidates: pool,
                                                     profile: profile,
                                                     count: 12,
                                                     exploration: 0.4,
                                                     maxSameArtistConsecutive: 1)
        guard tracks.count >= 4 else { return nil }

        let name = cleaned.count > 40 ? String(cleaned.prefix(40)) : cleaned
        return PlaylistDraft(name: name.capitalizingFirstLetter(), tracks: tracks)
    }

    // MARK: - Сохранение черновика

    @discardableResult
    func saveDraft(_ draft: PlaylistDraft) -> Playlist {
        store.upsertTracks(draft.tracks)
        let playlist = store.createPlaylist(name: draft.name)
        for track in draft.tracks {
            store.addTrack(playlistID: playlist.id, trackID: track.id)
        }
        return playlist
    }
}

private extension String {
    func capitalizingFirstLetter() -> String {
        guard let first = first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}
