import Foundation

/// Bundled export of the existing Umrah Flow content. The app does not generate
/// religious instructions: it uses the project's reviewed CSV translations and
/// published audio URLs when the online catalogue cannot be reached.
struct UmrahFlowOfflineCatalog {
    private struct Payload: Decodable {
        let translations: [String: [String: String]]
        let audio: [String: [String: String]]
    }

    static let shared = UmrahFlowOfflineCatalog()

    private let payload: Payload?

    private init() {
        guard let url = Bundle.main.url(forResource: "umrah_flow_catalog", withExtension: "json")
                ?? Bundle.main.url(forResource: "umrah_flow_catalog", withExtension: "json", subdirectory: "UmrahFlow"),
              let data = try? Data(contentsOf: url),
              let catalog = try? JSONDecoder().decode(Payload.self, from: data) else {
            payload = nil
            return
        }
        payload = catalog
    }

    func translations(for language: String) -> [String: String] {
        payload?.translations[language] ?? [:]
    }

    func audioURLs(for language: String) -> [String: URL] {
        (payload?.audio[language] ?? [:]).reduce(into: [String: URL]()) { result, row in
            guard let url = AppConfig.apiURL(row.value),
                  UmrahFlowAudioURLPolicy.isAllowed(url) else { return }
            result[row.key] = url
        }
    }
}


/// Reject legacy cached URLs and all arbitrary recording origins.
enum UmrahFlowAudioURLPolicy {
    static func isAllowed(_ url: URL) -> Bool {
        AppConfig.isUnifiedAPIOrigin(url) && url.path.hasPrefix("/api/services/advisor/audio/") && url.query == nil && url.fragment == nil
    }
}
