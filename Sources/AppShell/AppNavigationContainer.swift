import SwiftUI

struct AppNavigationContainer<Content: View>: View {
    @EnvironmentObject private var chrome: AppChromeStore
    @EnvironmentObject private var settings: AppSettingsStore
    @EnvironmentObject private var bookings: BookingStore
    @Environment(\.iumrahNavigationChromeStyle) private var navigationChromeStyle

    let tab: AppTab?
    let content: Content

    init(tab: AppTab? = nil, @ViewBuilder content: () -> Content) {
        self.tab = tab
        self.content = content()
    }

    private var isESIMDestinationActive: Binding<Bool> {
        Binding(
            get: { chrome.isESIMPresented && (tab == nil || chrome.currentTab == tab) },
            set: { newValue in
                if !newValue { chrome.isESIMPresented = false }
            }
        )
    }

    private var isNotificationsDestinationActive: Binding<Bool> {
        Binding(
            get: { chrome.isNotificationsPresented && (tab == nil || chrome.currentTab == tab) },
            set: { newValue in
                if !newValue { chrome.isNotificationsPresented = false }
            }
        )
    }

    var body: some View {
        ZStack {
            Color.iumrahPageBackground
                .ignoresSafeArea()

            // CRITICAL: Always retain ONE NavigationStack identity. Previously
            // setImmersive(true) swapped two branches, dismissing Umrah Flow right
            // after the language picker and occasionally resetting other routes.
            navigationStack
                .iumrahAdaptiveReadableWidth(unconstrained: chrome.isImmersiveMode)
        }
    }

    private var navigationStack: some View {
        NavigationStack {
            content
                // Install the signature bar on root content, not outside the
                // NavigationStack: pushed detail screens cover it naturally.
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if tab != nil && navigationChromeStyle == .drawer &&
                        !chrome.isImmersiveMode && !chrome.isInternalNavigationActive {
                        IumrahStoreTabBar(selection: $chrome.currentTab)
                    }
                }
                .toolbar(.hidden, for: .navigationBar)
                .background(Color.iumrahPageBackground.ignoresSafeArea())
                .navigationDestination(isPresented: isESIMDestinationActive) {
                    ESIMView()
                        .environmentObject(settings)
                        .environmentObject(chrome)
                        .environmentObject(bookings)
                }
                .navigationDestination(isPresented: isNotificationsDestinationActive) {
                    AccountNotificationsView()
                }
        }
    }
}
