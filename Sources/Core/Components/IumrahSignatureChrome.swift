import SwiftUI

/// Root tab offset only. Detail screens and modal NavigationStacks do not share this space.
private struct IumrahSignatureTopPreference: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Attach to the full-height black title area inside each root ScrollView.
struct IumrahSignatureScrollMarker: View {
    var body: some View {
        GeometryReader { geometry in
            Color.clear.preference(
                key: IumrahSignatureTopPreference.self,
                value: geometry.frame(in: .named("iumrah.root.signature.scroll")).minY
            )
        }
        .frame(height: 0)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// A single, permanently mounted 56-pt top rail shared by all five tabs.
/// The full-size title and selector live in the ScrollView below; the scroll
/// offset simply crossfades the rail from brand controls to the pinned selector.
/// This does not reflow the scroll view or move the refresh indicator.
struct IumrahSignaturePinnedBar: View {
    let collapseProgress: CGFloat
    let title: String
    var accessory: AnyView? = nil
    @EnvironmentObject private var chrome: AppChromeStore
    @ObservedObject private var notifications = ClientNotificationCenter.shared

    private var fraction: CGFloat { min(1, max(0, collapseProgress)) }

    var body: some View {
        ZStack(alignment: .leading) {
            brandControls
                .opacity(1 - fraction)
                .offset(y: -10 * fraction)
                .allowsHitTesting(fraction < 0.5)
                .accessibilityHidden(fraction >= 0.5)

            Group {
                if let accessory {
                    accessory
                } else {
                    Text(title)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
            }
            .opacity(fraction)
            .offset(y: 10 * (1 - fraction))
            .allowsHitTesting(fraction >= 0.5)
            .accessibilityHidden(fraction < 0.5)
        }
        .frame(height: 56)
        .padding(.horizontal, IumrahDesign.pagePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Only the rail owns the status-bar background. The scroll view remains
        // light and its native pull-to-refresh indicator appears BELOW the rail.
        .background(Color.iumrahSignatureBlack.ignoresSafeArea(edges: .top))
    }

    private var brandControls: some View {
        ViewThatFits(in: .horizontal) {
            brandRow(wordmarkWidth: 192)
            brandRow(wordmarkWidth: 158)
        }
    }

    private func brandRow(wordmarkWidth: CGFloat) -> some View {
        HStack(spacing: 10) {
            Image("HeaderWordmarkDark")
                .resizable()
                .scaledToFit()
                .frame(width: wordmarkWidth, height: 45, alignment: .leading)
                .accessibilityLabel("iumrah Project")
            Spacer(minLength: 2)
            Button { chrome.openNotifications() } label: {
                Image(systemName: notifications.unreadCount > 0 ? "bell.badge.fill" : "bell")
                    .font(.system(size: 17))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.10), in: Circle())
            }
            .accessibilityLabel("Notifications")
            Button { chrome.openSidebar() } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 17))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.10), in: Circle())
            }
            .accessibilityLabel("Menu")
        }
    }

}

private struct IumrahSignatureScrollChrome: ViewModifier {
    let title: String
    var pinnedAccessory: AnyView? = nil
    @State private var scrollTop: CGFloat = 0

    private var collapseProgress: CGFloat {
        min(1, max(0, -scrollTop / 140))
    }

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            IumrahSignaturePinnedBar(
                collapseProgress: collapseProgress,
                title: title,
                accessory: pinnedAccessory
            )
            content
                .coordinateSpace(name: "iumrah.root.signature.scroll")
                .background(Color.iumrahPageBackground)
                .onPreferenceChange(IumrahSignatureTopPreference.self) { top in
                    // Do not animate discrete layout changes on every scroll tick:
                    // the continuous opacity/offset tracks the actual gesture.
                    scrollTop = min(0, top)
                }
        }
        .background(Color.iumrahPageBackground)
    }
}

extension View {
    func iumrahSignatureScrollChrome(title: String, pinnedAccessory: AnyView? = nil) -> some View {
        modifier(IumrahSignatureScrollChrome(title: title, pinnedAccessory: pinnedAccessory))
    }
}

/// The same three-button signature switch is used by every root tab.
/// Selection/actions are supplied by the screen; it does not create fake pages.
struct IumrahSignatureTab: Identifiable {
    let id: String
    let title: String
}

struct IumrahSignatureThreeTabs: View {
    let tabs: [IumrahSignatureTab]
    let selectedID: String
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tabs) { tab in
                    let active = selectedID == tab.id
                    Button { onSelect(tab.id) } label: {
                        Text(tab.title)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .padding(.horizontal, 16)
                            .frame(height: 42)
                            .foregroundStyle(active ? Color.iumrahSignatureBlack : .white)
                            .background(active ? Color.white : Color.clear, in: Capsule())
                            .overlay {
                                Capsule().strokeBorder(Color.white.opacity(active ? 0 : 0.4), lineWidth: 0.9)
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(active ? .isSelected : [])
                    .accessibilityIdentifier("signature.tab.\(tab.id)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }
}

/// A reusable Booking-like interaction in iumrah's own graphite language.
/// Content owns the real search fields and action; the shell never fabricates results.
struct IumrahGraphiteSearchSurface<Content: View>: View {
    @Binding var isExpanded: Bool
    let summary: String
    let subtitle: String
    let content: Content
    @EnvironmentObject private var settings: AppSettingsStore

    init(isExpanded: Binding<Bool>, summary: String, subtitle: String,
         @ViewBuilder content: () -> Content) {
        _isExpanded = isExpanded
        self.summary = summary
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                    isExpanded.toggle()
                }
                IumrahHaptics.selection()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 23, weight: .medium))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(summary).font(.system(size: 16, weight: .semibold))
                            .lineLimit(2).minimumScaleFactor(0.8)
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(Color.black)
                .padding(18)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isExpanded
                ? localized("Свернуть поиск", "Qidiruvni yopish", "Collapse search")
                : localized("Изменить параметры", "Qidiruv shartlarini o‘zgartirish", "Edit search"))

            if isExpanded {
                Rectangle().fill(Color.black.opacity(0.12)).frame(height: 1)
                content
                    .padding(16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.white, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Color(red: 28/255, green: 28/255, blue: 30/255), lineWidth: 2.3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .animation(.easeInOut(duration: 0.20), value: isExpanded)
        .environment(\.colorScheme, .light)
    }

    private func localized(_ ru: String, _ uz: String, _ en: String) -> String {
        switch settings.language {
        case .russian: return ru
        case .uzbek: return uz
        case .uzbekCyrillic: return ru
        default: return en
        }
    }
}
