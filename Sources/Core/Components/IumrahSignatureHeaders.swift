import SwiftUI

/// Shared geometry used by the five root tabs and the four booking stages.
/// The black hero participates in scroll layout; it is never a sticky overlay.
enum IumrahSignatureHeaderGeometry {
    static let logoWidth: CGFloat = 187.2
    static let logoHeight: CGFloat = 57.6
    static let topInset: CGFloat = 14
    static let lowerInset: CGFloat = 100
    static let bottomRadius: CGFloat = 30
    static let summaryOverlap: CGFloat = 46
    static let contentHeight: CGFloat = logoHeight + topInset + lowerInset
}

/// One brand row shared by all five iPhone root tabs.
/// Identical 44-pt native chrome slots keep the wordmark geometrically
/// centered, including on smaller phones and when the drawer is unavailable.
/// This is also the layout used on Home: menu / wordmark / notifications.
struct IumrahPrimaryHeaderBrandRow: View {
    @EnvironmentObject private var chrome: AppChromeStore
    @EnvironmentObject private var settings: AppSettingsStore
    @Environment(\.iumrahNavigationChromeStyle) private var navigationChromeStyle
    @ObservedObject private var notifications = ClientNotificationCenter.shared

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if navigationChromeStyle == .drawer {
                    Button { chrome.openSidebar() } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 24, height: 24)
                    }
                    .modifier(IumrahNativeChromeButton())
                    .accessibilityLabel(IumrahAccessibilityCopy.text(settings.language,
                        ru: "Меню", en: "Menu", uz: "Menyu", cy: "Меню", tr: "Menu", id: "Menu"))
                } else {
                    Color.clear.accessibilityHidden(true)
                }
            }
            .frame(width: 48, height: 48)

            Spacer(minLength: 0)
            Image("HeaderWordmarkLight")
                .resizable()
                .renderingMode(.template)
                .scaledToFit()
                .foregroundStyle(.white)
                .frame(width: IumrahSignatureHeaderGeometry.logoWidth,
                       height: IumrahSignatureHeaderGeometry.logoHeight)
                .accessibilityLabel("iumrah")
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)

            Button { chrome.openNotifications() } label: {
                Image(systemName: notifications.unreadCount > 0 ? "bell.badge" : "bell")
                    .font(.system(size: 17, weight: .medium))
                            .frame(width: 24, height: 24)
            }
            .modifier(IumrahNativeChromeButton())
            .accessibilityLabel(IumrahAccessibilityCopy.text(settings.language,
                ru: "Уведомления", en: "Notifications", uz: "Bildirishnomalar",
                cy: "Билдиришномалар", tr: "Bildirimler", id: "Notifikasi"))
            .frame(width: 48, height: 48)
        }
        .frame(height: IumrahSignatureHeaderGeometry.logoHeight)
        .foregroundStyle(.white)
    }
}

/// The segmented navigation inside a black hero is intentionally a solid
/// capsule, NOT a mocked Liquid Glass navigation control.
struct IumrahHeaderTripleTabs: View {
    let labels: [String]
    let selection: Int
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(labels.indices, id: \.self) { index in
                Button {
                    IumrahHaptics.selection()
                    onSelect(index)
                } label: {
                    Text(labels[index])
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.74)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .foregroundStyle(index == selection ? Color.black : Color.white)
                        .background(index == selection ? Color.white : Color.clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(index == selection ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6))
    }
}

struct IumrahHeaderCapsuleActions: View {
    let labels: [String]
    let symbols: [String]
    let enabled: [Bool]
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 7) {
            ForEach(labels.indices, id: \.self) { index in
                let allowed = enabled.indices.contains(index) ? enabled[index] : true
                Button { onSelect(index) } label: {
                    Label(labels[index], systemImage: symbols.indices.contains(index) ? symbols[index] : "circle")
                        .font(.system(size: 11.5, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .frame(height: 35)
                        .foregroundStyle(.white)
                        .background(Color.white.opacity(allowed ? 0.15 : 0.06), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(allowed ? 0.32 : 0.13), lineWidth: 0.7))
                }
                .buttonStyle(.plain)
                .disabled(!allowed)
                .accessibilityLabel(labels[index])
            }
        }
    }
}

/// Shared root-tab masthead. Height is constant, but the whole masthead is a
/// normal scroll item: swiping UP moves it offscreen. During top overscroll,
/// IumrahRootScrollingPage compensates its position so it does not stretch.
struct IumrahPrimaryTabHeader: View {
    var title: String? = nil
    var subtitle: String? = nil
    var footer: AnyView? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            IumrahPrimaryHeaderBrandRow()

            if let title {
                Text(title)
                    .font(IumrahType.bold(28, relativeTo: .largeTitle))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                    .foregroundStyle(.white)
                    .padding(.top, footer == nil ? 7 : 2)
                    .accessibilityAddTraits(.isHeader)
            }
            if let subtitle {
                Text(subtitle)
                    .font(IumrahType.regular(14, relativeTo: .subheadline))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(.white.opacity(0.76))
                    .padding(.top, 3)
            }
            if let footer {
                footer
                    .padding(.top, title == nil ? 7 : 4)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, IumrahDesign.pagePadding)
        .padding(.top, IumrahSignatureHeaderGeometry.topInset)
        .frame(maxWidth: .infinity)
        .frame(height: IumrahSignatureHeaderGeometry.contentHeight, alignment: .top)
        // Hotels, Bookings, Support and Account have a STRAIGHT bottom edge.
        // Only Home retains the brand's curved lower corners.
        .background(IumrahWorldDotsHeaderBackground(mapOpacity: 0.33))
        .accessibilityElement(children: .contain)
    }
}

/// The scrolling header owns its top inset. Never leave a black status-bar plate.
struct IumrahPrimaryTabScrollChrome: ViewModifier {
    func body(content: Content) -> some View {
        content.background(Color.iumrahPageBackground.ignoresSafeArea())
    }
}
