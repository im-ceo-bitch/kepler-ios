import SwiftUI

struct HotelConfiguratorDeepLink: Hashable {
    let hotelID: String
    var adults: Int? = nil
    var children: Int? = nil
    var infants: Int? = nil
    var rooms: Int? = nil
    var scope: JourneyScope? = nil
    var firstSaudiCity: SaudiArrivalAirport? = nil
    var mealSelection: PackageMealSelection? = nil
    var outboundOptionID: String? = nil
    var inboundOptionID: String? = nil
}

enum AppTab: Hashable {
    case home
    case hotels
    case booking
    case care
    case account
}

/// Search hand-off from Home to the existing second tab. Only fields supported by
/// the current Nuitee hotel supplier are included; never promise multi-room rates.
struct IumrahHotelTabSearch: Equatable {
    let id = UUID()
    let city: String
    let checkin: Date
    let nights: Int
    let adults: Int
}

final class AppChromeStore: ObservableObject {
    @Published var requestedTab: AppTab?
    @Published var currentTab: AppTab = .home
    @Published var shouldStartTripBuilder = false
    @Published var shouldStartFlightFirstBuilder = false
    @Published var requestedBookingID: String?
    @Published var requestedHotelID: String?
    @Published var requestedHotelConfiguratorID: String?
    @Published var requestedHotelConfiguratorDeepLink: HotelConfiguratorDeepLink?
    @Published var requestedHotelsBoard: HotelsShowcaseBoard?
    /// A new guided journey is distinct from ordinary browsing of the Flights board.
    @Published private(set) var guidedUmrahSearchRevision = 0
    @Published private(set) var isGuidedUmrahSearch = false
    @Published var requestedHotelTabSearch: IumrahHotelTabSearch?
    @Published var requestedPackageID: String?
    @Published var isImmersiveMode = false
    @Published var isSidebarOpen = false
    @Published var isESIMPresented = false
    @Published var isNotificationsPresented = false
    @Published var shouldOpenUmrahPlan = false
    @Published private(set) var internalNavigationDepth = 0

    func navigate(to tab: AppTab) {
        requestedTab = tab
        currentTab = tab
        IumrahHaptics.selection()
    }

    func openBooking(id: String) {
        requestedBookingID = id
        currentTab = .booking
        requestedTab = .booking
        IumrahHaptics.selection()
    }

    func openHotel(
        id: String,
        openConfigurator: Bool = false,
        configuratorDeepLink: HotelConfiguratorDeepLink? = nil
    ) {
        requestedHotelID = id
        requestedHotelConfiguratorID = openConfigurator ? id : nil
        requestedHotelConfiguratorDeepLink = openConfigurator
            ? (configuratorDeepLink ?? HotelConfiguratorDeepLink(hotelID: id))
            : nil
        currentTab = .hotels
        requestedTab = .hotels
        IumrahHaptics.selection()
    }

    /// Switch TabView to Hotels rather than pushing a duplicate results screen.
    func findHotels(_ search: IumrahHotelTabSearch) {
        requestedHotelTabSearch = search
        requestedHotelsBoard = .hotels
        navigate(to: .hotels)
    }

    func openHotels(board: HotelsShowcaseBoard) {
        isGuidedUmrahSearch = false
        requestedHotelsBoard = board
        currentTab = .hotels
        requestedTab = .hotels
        IumrahHaptics.selection()
    }

    func openGuidedUmrahSearch() {
        guidedUmrahSearchRevision &+= 1
        isGuidedUmrahSearch = true
        requestedHotelsBoard = .flights
        currentTab = .hotels
        requestedTab = .hotels
        IumrahHaptics.selection()
    }

    func closeGuidedUmrahSearch() {
        isGuidedUmrahSearch = false
        requestedHotelsBoard = .hotels
    }

    func openPackage(id: String) {
        requestedPackageID = id
        currentTab = .hotels
        requestedTab = .hotels
        IumrahHaptics.selection()
    }

    func startNewTrip() {
        // Every public “start a trip” entry point opens the same Home search.
        // Keep the legacy TripBuilder view for existing deep links, not new sessions.
        shouldStartTripBuilder = false
        shouldStartFlightFirstBuilder = false
        openUmrahPlan()
    }

    func startFlightFirstTrip() {
        shouldStartTripBuilder = false
        shouldStartFlightFirstBuilder = true
        currentTab = .booking
        requestedTab = .booking
        IumrahHaptics.selection()
    }

    func openUmrahPlan() {
        shouldOpenUmrahPlan = true
        currentTab = .home
        requestedTab = .home
        IumrahHaptics.selection()
    }

    func openSidebar() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
            isSidebarOpen = true
        }
        IumrahHaptics.selection()
    }

    func closeSidebar() {
        withAnimation(.spring(response: 0.30, dampingFraction: 0.92)) {
            isSidebarOpen = false
        }
    }

    func presentESIM() {
        closeSidebar()
        // eSIM is a normal destination in the Home NavigationStack. Keeping it out
        // of a modal preserves the system back button and interactive edge-swipe.
        currentTab = .home
        requestedTab = nil
        isESIMPresented = true
        IumrahHaptics.selection()
    }

    func openNotifications() {
        closeSidebar()
        isNotificationsPresented = true
        IumrahHaptics.selection()
    }

    func closeNotifications() {
        isNotificationsPresented = false
    }

    var isInternalNavigationActive: Bool { internalNavigationDepth > 0 }

    func beginInternalNavigation() {
        internalNavigationDepth += 1
    }

    func endInternalNavigation() {
        internalNavigationDepth = max(0, internalNavigationDepth - 1)
    }

    func setImmersive(_ value: Bool) {
        guard isImmersiveMode != value else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            isImmersiveMode = value
        }
    }
}
