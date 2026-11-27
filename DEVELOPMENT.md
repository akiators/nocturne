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

Подписанный IPA: нужны сертификаты/профиль — добавить секреты `BUILD_CERTIFICATE_BASE64`, `P12_PASSWORD`, `KEYCHAIN_PASSWORD`, `MOBILEPROVISION_BASE64` и шаг импорта перед архивацией. Сборка без подписи (`CODE_SIGNING_ALLOWED=NO`) работает без них.

## IPA и установка на iPhone

**Unsigned IPA** (задача `build-ipa` в CI): запускается вручную (`Actions → iOS CI → Run workflow`) или на теге `v*`. Артефакт `nocturne-unsigned-ipa` скачивается из завершённого прогона.

Установка unsigned IPA (без платного аккаунта разработчика):
- **Sideloadly** (Windows/macOS): перетащить IPA, ввести Apple ID → подпись бесплатным сертификатом (7 дней, до 3 приложений).
- **AltStore / SideStore**: тот же принцип, переустановка по таймеру.
- **TrollStore**: для поддерживаемых версий iOS без лимитов.

**Подписанный IPA** (платный Apple Developer, $99/год): положить в Secrets репозитория:
1. `BUILD_CERTIFICATE_BASE64` — base64 p12 (`certutil -encode cert.p12 cert.b64` на Windows), `P12_PASSWORD`;
2. `MOBILEPROVISION_BASE64` — профиль provisioning (MusicKit + ShazamKit capabilities в App ID!);
3. `KEYCHAIN_PASSWORD` — пароль временного keychain в CI.

Затем перед шагом Archive добавить: импорт p12 в keychain, установку профиля в `Nocturne.mobileprovision`, замену `CODE_SIGNING_ALLOWED=NO` на `DEVELOPMENT_TEAM=<TEAM_ID>` и профиль через `xcodebuild -exportArchive -exportOptionsPlist`. Шаблон шагов закомментирован в ROADMAP.

Важно: для MusicKit (полный стрим Apple Music) и ShazamKit на устройстве нужен App ID с включёнными capabilities — бесплатная (личная) команда в Xcode умеет включать их автоматически при первом запуске с устройством.

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
