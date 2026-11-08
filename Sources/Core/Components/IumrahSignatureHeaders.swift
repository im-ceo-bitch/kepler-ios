import SwiftUI

/// One source of geometry for all five app tabs and all four journey stages.
/// The black surface is part of scroll content, not a pinned navigation bar.
enum IumrahSignatureHeaderGeometry {
    static let logoWidth: CGFloat = 187.2
    static let logoHeight: CGFloat = 57.6
    static let topInset: CGFloat = 14
    // Home's previous 60 pt is extended by the requested 20 pt.
    static let lowerInset: CGFloat = 80
    static let bottomRadius: CGFloat = 30
    static let summaryOverlap: CGFloat = 46
}

/// All non-home primary tabs: wordmark LEFT, notification and drawer RIGHT.
/// Identical hero height to Home and the staged configurator. The content
/// scrolls away, so it does not cover results as a permanent black overlay.
struct IumrahPrimaryTabHeader: View {
    @EnvironmentObject private var chrome: AppChromeStore
    @EnvironmentObject private var settings: AppSettingsStore
    @Environment(\.iumrahNavigationChromeStyle) private var navigationChromeStyle
    @ObservedObject private var notifications = ClientNotificationCenter.shared

    var body: some View {
        HStack(spacing: 12) {
            Image("HeaderWordmarkLight")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .foregroundStyle(.white)
                .frame(width: 145, height: 47, alignment: .leading)
                .accessibilityLabel("iumrah")
            Spacer(minLength: 4)
            Button { chrome.openNotifications() } label: {
                Image(systemName: notifications.unreadCount > 0 ? "bell.badge" : "bell")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 23, height: 23)
            }
            .modifier(IumrahNativeChromeButton())
            .accessibilityLabel(IumrahAccessibilityCopy.text(settings.language, ru: "Уведомления", en: "Notifications", uz: "Bildirishnomalar", cy: "Билдиришномалар", tr: "Bildirimler", id: "Notifikasi"))
            if navigationChromeStyle == .drawer {
                Button { chrome.openSidebar() } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 23, height: 23)
                }
                .modifier(IumrahNativeChromeButton())
                .accessibilityLabel(IumrahAccessibilityCopy.text(settings.language, ru: "Меню", en: "Menu", uz: "Menyu", cy: "Меню", tr: "Menu", id: "Menu"))
            }
        }
        .foregroundStyle(.white)
        .frame(height: IumrahSignatureHeaderGeometry.logoHeight)
        .padding(.horizontal, IumrahDesign.pagePadding)
        .padding(.top, IumrahSignatureHeaderGeometry.topInset)
        .padding(.bottom, IumrahSignatureHeaderGeometry.lowerInset)
        .frame(maxWidth: .infinity)
        .background {
            IumrahWorldDotsHeaderBackground(mapOpacity: 0.33)
                .clipShape(UnevenRoundedRectangle(
                    bottomLeadingRadius: IumrahSignatureHeaderGeometry.bottomRadius,
                    bottomTrailingRadius: IumrahSignatureHeaderGeometry.bottomRadius))
        }
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: IumrahPrimaryTabHeaderEndKey.self,
                    value: geo.frame(in: .global).maxY)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct IumrahPrimaryTabHeaderEndKey: PreferenceKey {
    static var defaultValue: CGFloat = 1000
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// The status bar starts black and returns to page color when the hero scrolls
/// offscreen. Never pin a permanently black substitute navigation background.
struct IumrahPrimaryTabScrollChrome: ViewModifier {
    @State private var heroVisible = true
    func body(content: Content) -> some View {
        content
            .onPreferenceChange(IumrahPrimaryTabHeaderEndKey.self) { bottom in
                heroVisible = bottom > 40
            }
            .background {
                (heroVisible ? Color.iumrahHeaderBackground : Color.iumrahPageBackground)
                    .ignoresSafeArea(edges: .top)
            }
    }
}
