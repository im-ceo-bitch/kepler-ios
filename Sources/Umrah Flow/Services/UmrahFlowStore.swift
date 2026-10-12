import Combine
import Foundation

@MainActor
final class UmrahFlowStore: ObservableObject {
    @Published private(set) var translations: [String: String] = [:]
    @Published private(set) var audioURLs: [String: URL] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var loadedLanguage = ""
    @Published private(set) var lastError: String?
    @Published private(set) var guideLanguage: UmrahGuideLanguage

    private let client = UmrahFlowSupabaseClient()
    private let defaults = UserDefaults.standard

    init(language: UmrahGuideLanguage = .english) {
        guideLanguage = language
    }

    func load(forceRefresh: Bool = false) async {
        await load(language: guideLanguage, forceRefresh: forceRefresh)
    }

    func load(language: UmrahGuideLanguage, forceRefresh: Bool = false) async {
        guideLanguage = language
        let code = language.rawValue
        if !forceRefresh, loadedLanguage == code, !translations.isEmpty, !audioURLs.isEmpty { return }

        // Always populate the selected language first, without waiting for any
        // network operation. Avoid showing keys and an inert player on first launch.
        loadedLanguage = code
        let bundled = UmrahFlowOfflineCatalog.shared
        translations = bundled.translations(for: code)
        audioURLs = bundled.audioURLs(for: code)
        loadCache(language: code)
        isLoading = translations.isEmpty
        lastError = nil

        // Fetch each resource independently: a missing audio table must never
        // discard successfully fetched translations (and vice versa).
        async let translationsRequest = try? client.translations(language: code)
        async let audioRequest = try? client.audioURLs(language: code)
        let (freshTranslations, freshAudio) = await (translationsRequest, audioRequest)

        // A language change can occur while the HTTP requests are in flight.
        guard loadedLanguage == code, !Task.isCancelled else { return }
        if let freshTranslations, !freshTranslations.isEmpty {
            translations.merge(freshTranslations) { _, fresh in fresh }
            cacheTranslations(translations, language: code)
        }
        if let freshAudio, !freshAudio.isEmpty {
            audioURLs.merge(freshAudio) { _, fresh in fresh }
            cacheAudio(audioURLs, language: code)
        }

        // No French recordings were present in the supplied source export.
        // Keep any existing French text; do not silently pass off English speech
        // as a French narration or invent ritual instructions.
        if translations.isEmpty, code != UmrahGuideLanguage.english.rawValue {
            translations = bundled.translations(for: UmrahGuideLanguage.english.rawValue)
        }
        if translations.isEmpty, freshTranslations == nil {
            lastError = "Umrah guidance text is currently unavailable."
        }
        isLoading = false
    }

    // Compatibility for any older call site that still passes the app language.
    func load(language: AppSettingsStore.Language, forceRefresh: Bool = false) async {
        await load(language: UmrahGuideLanguage.preferred(for: language), forceRefresh: forceRefresh)
    }

    func text(_ key: String, fallback: String? = nil) -> String {
        let value = translations[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !value.isEmpty { return value }
        return fallback ?? key
    }

    func audioURL(for key: String) -> URL? {
        audioURLs[key]
    }

    private func translationsCacheKey(_ language: String) -> String {
        "iumrah.umrahFlow.translations.\(language)"
    }

    private func audioCacheKey(_ language: String) -> String {
        "iumrah.umrahFlow.audio.\(language)"
    }

    private func loadCache(language: String) {
        if let data = defaults.data(forKey: translationsCacheKey(language)),
           let map = try? JSONDecoder().decode([String: String].self, from: data) {
            translations.merge(map) { _, cached in cached }
        }

        if let data = defaults.data(forKey: audioCacheKey(language)),
           let map = try? JSONDecoder().decode([String: String].self, from: data) {
            for (key, value) in map {
                if let url = URL(string: value), url.scheme?.lowercased() == "https" {
                    audioURLs[key] = url
                }
            }
        }
    }

    private func cacheTranslations(_ map: [String: String], language: String) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        defaults.set(data, forKey: translationsCacheKey(language))
    }

    private func cacheAudio(_ map: [String: URL], language: String) {
        let serializable = map.mapValues(\.absoluteString)
        guard let data = try? JSONEncoder().encode(serializable) else { return }
        defaults.set(data, forKey: audioCacheKey(language))
    }
}
