import SwiftUI
import MusicKit
import UniformTypeIdentifiers

/// Настройки: источники, качество, тексты/перевод, данные, о приложении.
struct SettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var downloads: DownloadManager

    @State private var showRestoreImporter = false
    @State private var statusMessage: String?
    @State private var secretPrompt: String?          // keychain account
    @State private var secretInput = ""

    var body: some View {
        NavigationView {
            Form {
                sourcesSection
                qualitySection
                lyricsSection
                dataSection
                aboutSection
            }
            .navigationTitle("Настройки")
            .scrollContentBackgroundCompat()
            .sheet(item: secretPromptBinding) { account in
                secretSheet(account)
            }
            .fileImporter(isPresented: $showRestoreImporter,
                          allowedContentTypes: [.json, .data],
                          allowsMultipleSelection: false) { result in
                guard let url = result.first else { return }
                do {
                    let count = try environment.backup.restore(from: url)
                    statusMessage = "Восстановлено треков: \(count)"
                } catch {
                    statusMessage = "Ошибка восстановления: \(error.localizedDescription)"
                }
            }
            .background(Palette.backgroundCompat.ignoresSafeArea())
        }
        .navigationViewStyle(.stack)
    }

    private var secretPromptBinding: Binding<SecretPrompt?> {
        Binding(
            get: { secretPrompt.map(SecretPrompt.init(account:)) },
            set: { secretPrompt = $0?.account }
        )
    }

    struct SecretPrompt: Identifiable {
        let account: String
        var id: String { account }

        var title: String {
            switch account {
            case "spotify_client_id": return "Client ID Spotify"
            case "genius_token": return "Токен Genius API"
            case "yt_api_key": return "Ключ YouTube Data API"
            case "libretranslate_key": return "Ключ LibreTranslate"
            default: return account
            }
        }

        var hint: String {
            switch account {
            case "spotify_client_id": return "developer.spotify.com → Ваше приложение → Client ID. Redirect URI: nocturne://auth/spotify"
            case "genius_token": return "genius.com/api-clients → создать клиент → Client Access Token (бесплатно)"
            case "yt_api_key": return "console.cloud.google.com → включить YouTube Data API v3 → создать ключ"
            case "libretranslate_key": return "Ключ вашего инстанса LibreTranslate (если требуется)"
            default: return ""
            }
        }
    }

    // MARK: - Sources

    private var sourcesSection: some View {
        Section("Источники музыки") {
            ForEach(environment.providers.allProviders, id: \.id) { provider in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Circle()
                            .fill(statusColor(provider))
                            .frame(width: 8, height: 8)
                        Text(provider.id.displayName)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Palette.textPrimary)
                        Spacer()
                        if provider.capabilities.contains(.auth) && provider.id == .spotify {
                            spotifyAuthButtons
                        }
                        if provider.id == .appleMusic {
                            Button("Разрешить") {
                                Task { await MusicAuthorization.request() }
                            }
                            .font(.secondary())
                            .foregroundColor(Palette.accent)
                        }
                        if provider.id == .local {
                            Button("Импорт файлов") {
                                NotificationCenter.default.post(name: .nocturneImportFiles, object: nil)
                            }
                            .font(.secondary())
                            .foregroundColor(Palette.accent)
                        }
                        if provider.id == .vk {
                            Button("Открыть VK") {
                                if let url = URL(string: "https://vk.com/audio") {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .font(.secondary())
                            .foregroundColor(Palette.accent)
                        }
                        if provider.id == .spotify || provider.id == .youtubeMusic || provider.id == .soundCloud {
                            Button("Ключ/ID") {
                                secretPrompt = provider.id == .spotify ? "spotify_client_id"
                                    : provider.id == .youtubeMusic ? "yt_api_key" : nil
                                if secretPrompt == nil {
                                    statusMessage = SoundCloudProviderHint
                                }
                            }
                            .font(.secondary())
                            .foregroundColor(Palette.accent)
                            .opacity(provider.id == .soundCloud ? 0.4 : 1)
                            .disabled(provider.id == .soundCloud)
                        }
                    }
                    Text(provider.setupHint)
                        .font(.caption())
                        .foregroundColor(Palette.textSecondary)
                    Text(capabilitiesText(provider.capabilities))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Palette.accent.opacity(0.8))
                }
                .padding(.vertical, 4)
            }
        }
    }

    private let SoundCloudProviderHint = "SoundCloud закрыл выдачу API-ключей: доступны только ссылки (handoff)."

    private var spotifyAuthButtons: some View {
        HStack(spacing: 12) {
            Button("Войти") {
                Task {
                    do {
                        try await (environment.providers.provider(.spotify) as? SpotifyProvider)?.login()
                        statusMessage = "Spotify подключён."
                    } catch {
                        statusMessage = "Spotify: \(error.localizedDescription)"
                    }
                }
            }
            .font(.secondary())
            .foregroundColor(Palette.accent)

            if (environment.providers.provider(.spotify) as? SpotifyProvider)?.isConfigured == true {
                Button("Выйти", role: .destructive) {
                    Task { await (environment.providers.provider(.spotify) as? SpotifyProvider)?.logout() }
                }
                .font(.secondary())
            }
        }
    }

    private func statusColor(_ provider: MusicProvider) -> Color {
        if provider.isConfigured {
            return .green
        }
        return provider.capabilities.contains(.auth) ? .orange : .green
    }

    private func capabilitiesText(_ capabilities: ProviderCapabilities) -> String {
        var parts: [String] = []
        if capabilities.contains(.fullPlayback) { parts.append("полное воспроизведение") }
        if capabilities.contains(.previewPlayback) { parts.append("фрагменты 30 сек") }
        if capabilities.contains(.search) { parts.append("поиск") }
        if capabilities.contains(.playlistImport) { parts.append("импорт плейлистов") }
        if capabilities.contains(.handoff) { parts.append("открытие в оригинале") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Quality / lyrics

    private var qualitySection: some View {
        Section("Качество") {
            Picker("Качество воспроизведения", selection: $settings.audioQuality) {
                ForEach(AudioQuality.allCases) { quality in
                    Text(quality.title).tag(quality)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            Text("Источники отдают максимум доступного легально: локальные файлы — как есть, стриминги — их доступный формат/фрагменты.")
                .font(.caption())
                .foregroundColor(Palette.textSecondary)
        }
    }

    private var lyricsSection: some View {
        Section("Тексты и перевод") {
            Picker("Язык перевода", selection: $settings.translationTarget) {
                Text("Русский").tag("ru")
                Text("English").tag("en")
                Text("Español").tag("es")
                Text("Deutsch").tag("de")
                Text("Français").tag("fr")
            }
            HStack {
                Text("URL переводчика")
                    .foregroundColor(Palette.textPrimary)
                TextField("https://libretranslate.example.com", text: $settings.libreTranslateURL)
                    .font(.secondary())
                    .foregroundColor(Palette.textSecondary)
                    .autocorrectionDisabled(true)
                    .keyboardType(.URL)
            }
            Button("Ключ LibreTranslate") { secretPrompt = "libretranslate_key" }
            Button("Токен Genius (аннотации)") { secretPrompt = "genius_token" }
            Text("Перевод работает через открытый LibreTranslate (можно свой инстанс). Тексты — открытая база LRCLIB. Всё без лимитов.")
                .font(.caption())
                .foregroundColor(Palette.textSecondary)
        }
    }

    // MARK: - Data

    private var dataSection: some View {
        Section("Данные") {
            Button {
                do {
                    let url = try environment.backup.exportToFile()
                    statusMessage = "Резервная копия сохранена: \(url.lastPathComponent)"
                } catch {
                    statusMessage = "Ошибка экспорта: \(error.localizedDescription)"
                }
            } label: {
                Label("Экспорт резервной копии", systemImage: "square.and.arrow.up")
            }
            Button {
                showRestoreImporter = true
            } label: {
                Label("Восстановить из копии", systemImage: "tray.and.arrow.down")
            }
            Button(role: .destructive) {
                downloads.removeAll()
                statusMessage = "Все скачанные аудиофайлы удалены с устройства."
            } label: {
                Label("Очистить загрузки (\(downloads.totalSize / 1_048_576) МБ)", systemImage: "trash")
            }
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption())
                    .foregroundColor(Palette.accent)
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section("О приложении") {
            HStack {
                Text("Nocturne")
                Spacer()
                Text("0.1.0")
                    .foregroundColor(Palette.textSecondary)
            }
            Text("Все функции бесплатны: никакой подписки, квот и премиум-гейтов. Данные хранятся только на устройстве. Ограничения источников честно документированы: VK и YouTube не отдают стриминги сторонним приложениям, Deezer и Spotify дают метаданные и фрагменты, Apple Music играет через MusicKit.")
                .font(.caption())
                .foregroundColor(Palette.textSecondary)
        }
    }

    private func secretSheet(_ prompt: SecretPrompt) -> some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 12) {
                Text(prompt.hint)
                    .font(.secondary())
                    .foregroundColor(Palette.textSecondary)
                TextField("Вставьте значение", text: $secretInput)
                    .textFieldStyle(StyledTextFieldStyle())
                    .autocorrectionDisabled(true)
                PrimaryButton(title: "Сохранить") {
                    settings.setSecret(secretInput.trimmed, account: prompt.account)
                    secretInput = ""
                    secretPrompt = nil
                    statusMessage = "Сохранено в Keychain."
                }
                Spacer()
            }
            .padding(Metrics.hPadding)
            .navigationTitle(prompt.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { secretPrompt = nil }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}

extension Color {
    static let backgroundCompat = Palette.background
}

extension Notification.Name {
    static let nocturneImportFiles = Notification.Name("nocturne.import_files")
}
