import Foundation

@main
struct UnifiedBackendRoutingSmoke {
    static func main() {
        let host = "iumrah-backend.helloiumrah.workers.dev"
        let paths = ["/api/services/prayer", "/api/services/weather", "/api/services/fx", "/api/services/advisor/audio/en/tawaf_1", "/api/package/health", "/api/package/flights/detail", "/api/package/flights/search", "/api/package/quote", "/api/catalog/hotels", "/api/catalog/ziyarats", "/api/bookings/1234", "/api/package/client/account/login/email/start", "/api/catalog/hotels/client/trips/1234", "/api/catalog/hotels/client/chats/1234/messages", "/api/storefront/packages", "/api/airports", "/api/catalog/hotels/intelligence/events"]
        for path in paths {
            let url = AppConfig.apiURL(path)!
            precondition(url.host == host && url.path == path && AppConfig.isUnifiedAPIOrigin(url))
        }
        let old = "https://iumrah.app/api/catalog/hotels/client/media/x?token=a%2Bb%3D"
        let rewritten = AppConfig.apiURL(old)!
        precondition(rewritten.absoluteString == "https://\(host)/api/catalog/hotels/client/media/x?token=a%2Bb%3D")
        precondition(AppConfig.apiURL("https://iumrah-package-api.helloiumrah.workers.dev/api/package/health")?.host == host)
        precondition(AppConfig.apiURL("https://iumrah-flight-hub.helloiumrah.workers.dev/api/airports")?.host == host)
        let query = AppConfig.apiURL("/api/package/client/account/phone/status?bookingID=1234", query: [.init(name: "locale", value: "ru")])!
        precondition(query.query == "bookingID=1234&locale=ru")
        precondition(AppConfig.apiURL("api/package/flights/search")?.host == host)
        for invalid in ["https://evil.example/api/secret", "//evil.example/api/secret", "http://iumrah.app/api/secret", "https://iumrah.app:8443/api/secret", "https://u@iumrah.app/api/secret", "/api/../id/1", "/api/%2e%2e/id/1", "/id/1", "https://iumrah.app.evil.example/api/secret", "/api/secret#fragment"] {
            precondition(AppConfig.apiURL(invalid) == nil, invalid)
        }
        precondition(AppConfig.publicWebBaseURL.host == "iumrah.app")
        precondition(AppConfig.absoluteURL("https://www.booking.com/photo.jpg")?.host == "www.booking.com")
        precondition(AppConfig.absoluteURL(old)?.host == host)
        precondition(AppConfig.absoluteURL("/api/catalog/hotels/photo.jpg")?.host == host)
        precondition(!AppConfig.isUnifiedAPIOrigin(URL(string: old)!))
        print("PASS: unified API paths, legacy media, query preservation, public links and hostile URL rejection")
    }
}
