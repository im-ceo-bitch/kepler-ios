import Foundation
func check(_ path: String, _ host: String) {
    guard let url = AppConfig.apiURL(path) else { fatalError(path) }
    precondition(url.host == host, "\(path): \(url)")
    precondition(AppConfig.isAllowedAPIOrigin(url))
}
let new = "iumrah-backend.helloiumrah.workers.dev", old = "iumrah.app"
for path in ["/api/package/flights/detail?number=HY335", "/api/package/flights/search", "/api/package/nuitee/hotels", "/api/catalog/hotels", "/api/catalog/hotels/intelligence/events", "https://iumrah-package-api.helloiumrah.workers.dev/api/package/flights/detail?x=1", "/api/package/quote-unrelated"] { check(path,new) }
for path in ["/api/bookings", "/api/bookings/123", "/api/package/quote", "/api/package/quote/commit/123", "/api/package/storefront/quote", "/api/package/client/account/login", "/api/catalog/hotels/client/account/session", "/api/catalog/hotels/team", "/api/catalog/ziyarats", "/api/airports", "/api/storefront/packages"] { check(path,new) }
precondition(AppConfig.apiURL("https://example.com/api/bookings") == nil)
precondition(AppConfig.apiURL("/api/../auth") == nil)
precondition(AppConfig.apiURL("//example.com/api/bookings") == nil)
precondition(AppConfig.apiURL("https://iumrah.app/api/bookings/a%2Fb?token=x%2By")!.absoluteString.contains("a%2Fb?token=x%2By"))
precondition(AppConfig.publicWebBaseURL.host == old)
print("iOS routing smoke: PASS")
