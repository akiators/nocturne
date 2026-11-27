import Foundation
import SwiftUI

/// Пользовательские настройки. Секреты (токены) — в Keychain, остальное в UserDefaults.
@MainActor
final class SettingsStore: ObservableObject {
    private let defaults: UserDefaults

    @Published var enabledProviders: Set<ProviderID> {
        didSet { defaults.set(Array(enabledProviders.map(\.rawValue)), forKey: "enabled_providers") }
    }
    @Published var audioQuality: AudioQuality {
        didSet { defaults.set(audioQuality.rawValue, forKey: "audio_quality") }
    }
    @Published var crossfadeSeconds: Double {
        didSet { defaults.set(crossfadeSeconds, forKey: "crossfade_seconds") }
    }
    @Published var eqEnabled: Bool {
        didSet { defaults.set(eqEnabled, forKey: "eq_enabled") }
    }
    @Published var selectedPresetID: String? {
        didSet { defaults.set(selectedPresetID, forKey: "eq_preset_id") }
    }
    @Published var playbackSpeed: Double {
        didSet { defaults.set(playbackSpeed, forKey: "playback_speed") }
    }
    @Published var translationTarget: String {
        didSet { defaults.set(translationTarget, forKey: "translation_target") }
    }
    @Published var libreTranslateURL: String {
        didSet { defaults.set(libreTranslateURL, forKey: "libretranslate_url") }
    }
    @Published var useTrackEQPresets: Bool {
        didSet { defaults.set(useTrackEQPresets, forKey: "use_track_eq") }
    }
    @Published var sleepTimerMinutes: Int {
        didSet { defaults.set(sleepTimerMinutes, forKey: "sleep_timer_minutes") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let all = Set(ProviderID.allCases)
        if let stored = defaults.stringArray(forKey: "enabled_providers") {
            enabledProviders = Set(stored.compactMap(ProviderID.init(rawValue:)))
        } else {
            enabledProviders = all
        }
        audioQuality = AudioQuality(rawValue: defaults.string(forKey: "audio_quality") ?? "") ?? .auto
        crossfadeSeconds = defaults.double(forKey: "crossfade_seconds")
        if defaults.object(forKey: "crossfade_seconds") == nil { crossfadeSeconds = 4 }
        eqEnabled = defaults.bool(forKey: "eq_enabled")
        selectedPresetID = defaults.string(forKey: "eq_preset_id")
        let storedSpeed = defaults.double(forKey: "playback_speed")
        if defaults.object(forKey: "playback_speed") == nil || storedSpeed < 0.5 || storedSpeed > 2.0 {
            playbackSpeed = 1.0
        } else {
            playbackSpeed = storedSpeed
        }
        translationTarget = defaults.string(forKey: "translation_target") ?? "ru"
        libreTranslateURL = defaults.string(forKey: "libretranslate_url") ?? ""
        useTrackEQPresets = defaults.object(forKey: "use_track_eq") == nil
            ? true : defaults.bool(forKey: "use_track_eq")
        sleepTimerMinutes = defaults.integer(forKey: "sleep_timer_minutes")
        if sleepTimerMinutes == 0 { sleepTimerMinutes = 30 }
    }

    // MARK: - Keychain-backed secrets

    static let keychainAccounts: [String: String] = [
        "spotify_token": "Spotify OAuth",
        "spotify_refresh": "Spotify OAuth refresh",
        "spotify_client_id": "Client ID приложения Spotify",
        "genius_token": "Genius API token (бесплатный)",
        "libretranslate_key": "Ключ LibreTranslate (опционально)",
        "yt_api_key": "YouTube Data API key"
    ]

    func secret(_ account: String) -> String? {
        KeychainStore.string(account: account)
    }

    func setSecret(_ value: String?, account: String) {
        try? KeychainStore.setString(value, account: account)
        objectWillChange.send()
    }
}
