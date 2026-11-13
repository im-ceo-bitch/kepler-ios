import Foundation

struct UmrahFlowTranslationRow: Decodable { let key: String; let value: String }
struct UmrahFlowAudioRow: Decodable { let key: String; let url: String }

// All online content is provided by the single first-party Worker.
struct UmrahFlowBackendClient {
    private let session: URLSession
    init(session: URLSession = URLSession(configuration: .default, delegate: IumrahAPIOriginDelegate(), delegateQueue: nil)) { self.session = session }

    func translations(language: String) async throws -> [String: String] {
        let rows: [UmrahFlowTranslationRow] = try await request(resource: "translations", language: language)
        return rows.reduce(into: [:]) { result, row in
            if UmrahFlowKeys.all.contains(row.key) { result[row.key] = row.value }
        }
    }
    func audioURLs(language: String) async throws -> [String: URL] {
        let rows: [UmrahFlowAudioRow] = try await request(resource: "audio", language: language)
        return rows.reduce(into: [:]) { result, row in
            if let url = AppConfig.apiURL(row.url), UmrahFlowAudioURLPolicy.isAllowed(url) { result[row.key] = url }
        }
    }
    private func request<Row: Decodable>(resource: String, language: String) async throws -> [Row] {
        guard let url = AppConfig.apiURL("/api/services/advisor/\(resource)", query: [.init(name: "lang", value: language)]) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode([Row].self, from: data)
    }
}
