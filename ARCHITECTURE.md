# ARCHITECTURE

## Обзор

```
┌────────────────────────────── SwiftUI UI ──────────────────────────────┐
│ RootView (таббар+мини-плеер) → WaveView / SearchView / LibraryView /   │
│ SettingsView → PlayerFullView (Queue / Lyrics / EQ / Speed sheets)     │
│ AssistantView, StatsView, TrackRow                                     │
└──────────────┬─────────────────────────────────────────────────────────┘
               │ EnvironmentObjects
┌──────────────▼───────────── AppEnvironment (состав) ───────────────────┐
│ SettingsStore   PlayerController   SearchService   WaveFeedService     │
│ LyricsService   AssistantEngine    DownloadManager StatsService        │
│ BackupService   PlaylistImporter   ProviderRegistry                    │
└───┬──────────────┬──────────────────────┬──────────────────┬───────────┘
    │              │                      │                  │
┌───▼────┐   ┌─────▼──────┐        ┌──────▼──────┐   ┌──────▼─────────┐
│Library │   │AudioEngine │        │MusicProvider│   │Внешние API     │
│Store   │   │AVAudioEngin│        │(7 адаптеров)│   │Deezer/LRCLIB/  │
│SQLite  │   │2 голоса, EQ│        │             │   │Spotify/Genius/ │
│Keychain│   │timePitch   │        │             │   │YT/Genius       │
└────────┘   └────────────┘        └─────────────┘   └────────────────┘
```

## Модули

| Папка | Ответственность |
|---|---|
| `App/` | точка входа, DI-состав (`AppEnvironment`), корневая навигация |
| `Models/` | Track, Playlist, SearchResults, EQPreset, ProviderID, capabilities |
| `Persistence/` | `SQLiteDatabase` (sqlite3 C API), `LibraryStore` (DAO + схема), `SettingsStore`, `KeychainStore` |
| `Providers/` | протокол `MusicProvider`, реестр, адаптеры: LocalFiles, Deezer, AppleMusic (MusicKit), Spotify (PKCE+WebAPI), YouTubeMusic, VK, SoundCloud; `HTTPClient`; `SearchService` |
| `Player/` | `AudioEngine` (граф AVAudioEngine), `PlayerController` (очередь/crossfade/now playing/sleep/состояние), пресеты EQ |
| `MyWave/` | `RecommendationEngine` (чистый скоринг, детерминированный RNG), `WaveFeedService` (волна, миксы, радио, автодобор) |
| `Lyrics/` | `LRCParser`, `LyricsService` (LRCLIB + кэш + перевод), `GeniusService`, `LibreTranslateService` |
| `Assistant/` | `AssistantEngine`: интент-парсер RU/EN, выполнение, генерация плейлистов |
| `Features/` | `DownloadManager`, `StatsService`, `PlaylistImporter`, `BackupService` |
| `DesignSystem/` | палитра, метрики, шрифты, WaveBackground, GlassCard, Shimmer, CoverImage (NSCache) |
| `UI/` | экраны SwiftUI |
| `Tests/` | XCTest: LRC, рекомендации, SQLite, интенты, импортер, PKCE |

## Ключевые решения

1. **SQLite вместо Core Data/SwiftData.** SwiftData требует iOS 17, Core Data — xcdatamodeld-файл, неудобный для xcodegen-only workflow. sqlite3 системный, нулевые зависимости, полный контроль схемы; WAL-режим. Данные: треки, лайки/дизлайки, плейлисты, история, кэш текстов, аннотации, пресеты EQ, загрузки, affinity, kv.
2. **AVAudioEngine с двумя голосами.** Каждый голос: `AVAudioPlayerNode → AVAudioUnitTimePitch (скорость) → mainMixer`; после микшера: `mixer → AVAudioUnitEQ (10 полос) → output`. Crossfade = запустить трек на втором голосе с fade-in, затухая первый. Скорость через timePitch сохраняет тональность.
3. **Потоковая подача**: сегменты по 64k фреймов из `AVAudioFile` планируются вперёд с completion-цепочкой; EOF → `handleVoiceFinished`. Remote-аудио (preview mp3) сначала качается в `Caches/stream-cache` (переиспользуется).
4. **Провайдеры — capability-based.** `ProviderCapabilities` (search/preview/full/download/import/handoff/auth) описывает, что сервис легально отдаёт. Реестр решает, откуда брать поток: офлайн-загрузка → локальный файл → кэш → сеть. Ограничения (VK/YT/SC/FLAC) — не баги, а документированные Blocked-гейты кода.
5. **My Wave без сети как обязательного условия.** Скоринг — чистые функции над `Profile` (строится из SQLite). Сеть нужна только для добора кандидатов (чарт Deezer + поиск). Тесты прогоняют алгоритм детерминированно (`SeededGenerator`).
6. **Ассистент — интент-движок**, не LLM: парс правил → действие. Никаких квот, работает офлайн (кроме поисковых действий).
7. **Один DI-объект** (`AppEnvironment`) с ручным составом — предсказуемо, без контейнеров; для iOS 15 совместимо.
8. **XcodeGen** — `project.yml` источник правды; pbxproj генерится и в CI, и локально, в git не попадает.

## Поток воспроизведения

```
UI (TrackRow.play) → PlayerController.play(track, queue)
  → ProviderRegistry.stream(track)      // офлайн → файл → кэш → сеть
  → [если remote] URLSession.download   // в stream-cache
  → AudioEngine.play(file, voice, fadeIn)
  → MPRemoteCommandCenter / MPNowPlayingInfoCenter
  → EOF → next(auto) → (repeat/shuffle/sleep) → queueRefill (My Wave)
  → logPlay → SQLite (история/affinity) → влияет на волну
```

## Безопасность и приватность

- Токены (Spotify, Genius, YT, LibreTranslate) — только Keychain.
- БД и кэш — Application Support / Caches; загрузки — Documents.
- Никаких телеметрии и внешних серверов приложения.

## Расширение

Новый источник = 1 файл, реализующий `MusicProvider`, + регистрация в `ProviderRegistry.init`. Новая фича волны — чистая функция в `RecommendationEngine` + тест. UI-паттерн: экран = SwiftUI View + сервисы из `AppEnvironment`, состояние через `@Published`.
