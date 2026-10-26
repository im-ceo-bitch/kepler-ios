import SwiftUI
import UIKit

@main
struct IumrahApp: App {
    @UIApplicationDelegateAdaptor(IumrahAppDelegate.self) private var appDelegate
    @StateObject private var chrome = AppChromeStore()

    init() {
        // Keychain may survive an uninstall. Establish the installation boundary
        // before RootView creates BookingStore / IumrahAccountStore so stale
        // sessions can never be loaded into memory after a reinstall.
        AppInstallationLifecycle.prepare()
        Self.configureNativeLiquidGlassTabBar()
    }

    /// Customize only the foreground colors and the native selection tint.
    /// Do not set a custom background, blur view, or replacement tab-bar shape:
    /// iOS 26 keeps responsibility for its actual Liquid Glass rendering.
    private static func configureNativeLiquidGlassTabBar() {
        if #available(iOS 26.0, *) {
            // Dynamic colors ensure the glass remains legible if the user
            // switches iOS / iumrah into dark appearance.
            let primary = UIColor { traits in
                traits.userInterfaceStyle == .dark ? .white : .black
            }
            let secondary = UIColor { traits in
                (traits.userInterfaceStyle == .dark ? UIColor.white : UIColor.black)
                    .withAlphaComponent(0.72)
            }
            let selection = UIColor { traits in
                (traits.userInterfaceStyle == .dark ? UIColor.white : UIColor.black)
                    .withAlphaComponent(0.50)
            }
            let appearance = UITabBarAppearance()
            // This tints the native selection indicator; the actual capsule,
            // blur, animations, and interactivity remain system-managed.
            appearance.selectionIndicatorTintColor = selection
            for items in [appearance.stackedLayoutAppearance,
                          appearance.inlineLayoutAppearance,
                          appearance.compactInlineLayoutAppearance] {
                items.normal.iconColor = secondary
                items.normal.titleTextAttributes = [.foregroundColor: secondary]
                items.selected.iconColor = primary
                items.selected.titleTextAttributes = [.foregroundColor: primary]
            }
            let bar = UITabBar.appearance()
            bar.standardAppearance = appearance
            bar.scrollEdgeAppearance = appearance
            bar.tintColor = primary
            bar.unselectedItemTintColor = secondary
        }
    }

    var body: some Scene {
        WindowGroup {
            IumrahLaunchExperience {
                RootView(chrome: chrome)
                    .background { IumrahPlatformWindowConfiguration() }
            }
        }
        .commands {
            IumrahNavigationCommands(chrome: chrome)
        }
    }
}
