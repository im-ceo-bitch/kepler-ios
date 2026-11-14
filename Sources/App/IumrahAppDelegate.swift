import GoogleSignIn
import UIKit
import UserNotifications

final class IumrahAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private let quickActions = IumrahQuickActionCenter.shared

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self

        Task { @MainActor in
            await PushNotificationManager.shared.refreshAndRegisterIfAllowed()
            // Restore local prayer reminders after normal launches, without
            // requesting permissions or touching flight/booking notifications.
            _ = await IumrahPrayerNotifications.synchronize(state: IumrahPrayerState())
            quickActions.refreshShortcutItems(language: AppSettingsStore.Language(rawValue: UserDefaults.standard.string(forKey: "iumrah.language") ?? AppSettingsStore.Language.uzbek.rawValue) ?? .uzbek, activeBooking: BookingSessionVault.load().first)
        }

        if let shortcutItem = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem {
            Task { @MainActor in
                _ = quickActions.queue(shortcutItem: shortcutItem)
            }
        }

        return true
    }


    func applicationDidBecomeActive(_ application: UIApplication) {
        Task { @MainActor in
            quickActions.refreshShortcutItems(
                language: AppSettingsStore.Language(rawValue: UserDefaults.standard.string(forKey: "iumrah.language") ?? AppSettingsStore.Language.uzbek.rawValue) ?? .uzbek,
                activeBooking: BookingSessionVault.load().first
            )
        }
    }

    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        Task { @MainActor in
            let handled = quickActions.queue(shortcutItem: shortcutItem)
            completionHandler(handled)
        }
    }

    func application(
        _ application: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        if GIDSignIn.sharedInstance.handle(url) {
            return true
        }
        // Keep every existing custom URL flow available to the SwiftUI app.
        return false
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            PushNotificationManager.shared.didRegister(deviceToken: deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            PushNotificationManager.shared.didFailToRegister(error: error)
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        if !notification.request.identifier.hasPrefix("iumrah.prayer.") {
            let inCurrentChat = await MainActor.run {
                let manager = PushNotificationManager.shared
                manager.receiveRemotePayload(notification.request.content.userInfo, opened: false)
                guard let active = manager.activeChatBookingID, let event = manager.lastEvent else { return false }
                return event.type.hasPrefix("chat_") && event.bookingID == active
            }
            if inCurrentChat { return [.list, .badge] }
        }
        return [.banner, .list, .sound, .badge]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        // Prayer alerts are local reminders, not server booking events.
        guard !response.notification.request.identifier.hasPrefix("iumrah.prayer.") else { return }
        await MainActor.run {
            PushNotificationManager.shared.receiveRemotePayload(response.notification.request.content.userInfo, opened: true)
        }
    }
}
