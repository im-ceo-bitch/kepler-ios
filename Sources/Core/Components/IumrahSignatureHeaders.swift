import SwiftUI

/// Shared geometry used by the five root tabs and the four booking stages.
/// The black hero participates in scroll layout; it is never a sticky overlay.
enum IumrahSignatureHeaderGeometry {
    static let logoWidth: CGFloat = 187.2
    static let logoHeight: CGFloat = 57.6
    static let topInset: CGFloat = 14
    static let lowerInset: CGFloat = 80
    static let bottomRadius: CGFloat = 30
    static let summaryOverlap: CGFloat = 46
    static let contentHeight: CGFloat = logoHeight + topInset + lowerInset
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
    @EnvironmentObject private var chrome: AppChromeStore
    @EnvironmentObject private var settings: AppSettingsStore
    @Environment(\.iumrahNavigationChromeStyle) private var navigationChromeStyle
    @ObservedObject private var notifications = ClientNotificationCenter.shared

    var title: String? = nil
    var subtitle: String? = nil
    var footer: AnyView? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image("HeaderWordmarkLight")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .foregroundStyle(.white)
                    .frame(width: IumrahSignatureHeaderGeometry.logoWidth,
                           height: IumrahSignatureHeaderGeometry.logoHeight, alignment: .leading)
                    .accessibilityLabel("iumrah")
                Spacer(minLength: 0)
                Button { chrome.openNotifications() } label: {
                    Image(systemName: notifications.unreadCount > 0 ? "bell.badge" : "bell")
                        .font(.system(size: 17, weight: .medium))
                }
                .modifier(IumrahNativeChromeButton())
                .accessibilityLabel(IumrahAccessibilityCopy.text(settings.language,
                    ru: "Уведомления", en: "Notifications", uz: "Bildirishnomalar",
                    cy: "Билдиришномалар", tr: "Bildirimler", id: "Notifikasi"))
                if navigationChromeStyle == .drawer {
                    Button { chrome.openSidebar() } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 17, weight: .medium))
                    }
                    .modifier(IumrahNativeChromeButton())
                    .accessibilityLabel(IumrahAccessibilityCopy.text(settings.language,
                        ru: "Меню", en: "Menu", uz: "Menyu", cy: "Меню", tr: "Menu", id: "Menu"))
                }
            }
            .frame(height: IumrahSignatureHeaderGeometry.logoHeight)

            if let title {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .foregroundStyle(.white)
                    .padding(.top, footer == nil ? 9 : 3)
            }
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 12.5, weight: .regular))
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(0.72))
                    .padding(.top, 3)
            }
            if let footer {
                footer
                    .padding(.top, title == nil ? 8 : 7)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, IumrahDesign.pagePadding)
        .padding(.top, IumrahSignatureHeaderGeometry.topInset)
        .frame(maxWidth: .infinity)
        .frame(height: IumrahSignatureHeaderGeometry.contentHeight, alignment: .top)
        .background {
            IumrahWorldDotsHeaderBackground(mapOpacity: 0.33)
                .clipShape(UnevenRoundedRectangle(
                    bottomLeadingRadius: IumrahSignatureHeaderGeometry.bottomRadius,
                    bottomTrailingRadius: IumrahSignatureHeaderGeometry.bottomRadius))
        }
        .accessibilityElement(children: .contain)
    }
}

/// Paint the status-bar safe area behind the world-map masthead at rest.
/// This modifier does NOT pin the masthead or intercept scroll gestures.
struct IumrahPrimaryTabScrollChrome: ViewModifier {
    func body(content: Content) -> some View {
        content.background {
            Color.iumrahSignatureBlack
                .ignoresSafeArea(.container, edges: .top)
        }
    }
}
