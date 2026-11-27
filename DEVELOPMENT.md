# DEVELOPMENT

## Требования

- macOS 14+, Xcode 15+ (CI: macos-15, Xcode 16), XcodeGen (`brew install xcodegen`)
- На Windows: Git, любой редактор. Сборка идёт в CI или на mac.

## Локальная сборка (macOS)

```bash
git clone <repo> && cd nocturne
xcodegen generate          # создаёт Nocturne.xcodeproj из project.yml
open Nocturne.xcodeproj    # схема Nocturne, destination iPhone
# тесты: Cmd+U
```

CLI:

```bash
xcodebuild -project Nocturne.xcodeproj -scheme Nocturne \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Nocturne.xcodeproj -scheme Nocturne \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO test
```

## CI

`.github/workflows/ios.yml` (runner macos-15):
1. `brew install xcodegen` → `xcodegen generate`
2. Debug build на свежем доступном iPhone-симуляторе
3. Unit-тесты (XCTest)
4. Release build (проверка deployment target iOS 15)
5. Артефакты xcresult (7 дней)

Подписанный IPA: нужны сертификаты/профиль — добавить секреты `BUILD_CERTIFICATE_BASE64`, `P12_PASSWORD`, `KEYCHAIN_PASSWORD` и шаг экспорта (шаблон в ROADMAP). Сборка без подписи (`CODE_SIGNING_ALLOWED=NO`) работает без них.

## Настройка ключей (всё опционально, бесплатно)

| Ключ | Зачем | Где взять |
|---|---|---|
| Spotify Client ID | поиск/импорт Spotify | developer.spotify.com → Dashboard → Create App; Redirect URI: `nocturne://auth/spotify` |
| YouTube Data API key | поиск YT Music | console.cloud.google.com → YouTube Data API v3 → ключ |
| Genius token | факты о треке | genius.com/api-clients → Client Access Token |
| LibreTranslate URL/key | перевод текстов | свой инстанс или публичный |

Вставляются в **Настройки → соответствующий пункт**; хранение — Keychain.

## Структура коммитов

```
feat(provider): …
feat(player): …
feat(wave): …
fix(sqlite): …
docs: …
ci: …
```

Ветки: `main` (стабильно) ← `development` (работа).

## Известные ограничения сборки

- `.xcodeproj` не коммитится (генерится из `project.yml`).
- Live Activities/Dynamic Island требуют widget extension — см. ROADMAP.
- MusicKit поиск требует capability «MusicKit» в App ID (на устройстве с реальным Team ID; на симуляторе с бесплатной командой может не работать — код деградирует без краша).
- Тесты, трогающие сеть, отсутствуют: все внешние API изолированы за протоколами, unit-тесты идут на чистой логике.
