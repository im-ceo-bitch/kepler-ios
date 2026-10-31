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

/// Unified, edge-to-edge black header for the five root tabs.
/// The entire expanded state lives here, OUTSIDE the refreshable ScrollView:
/// UIKit therefore lays out the refresh control directly below this header.
/// On scroll, only the left-aligned selector remains mounted and interactive.
struct IumrahSignaturePinnedBar: View {
    let collapseProgress: CGFloat
    let title: String
    var subtitle: String? = nil
    var accessory: AnyView? = nil
    var showsHeading = true
    var expandedContent: AnyView? = nil
    @EnvironmentObject private var chrome: AppChromeStore
    @ObservedObject private var notifications = ClientNotificationCenter.shared

    private var fraction: CGFloat { min(1, max(0, collapseProgress)) }
    private var brandHeight: CGFloat { max(0, 64 * (1 - fraction)) }
    private var titleHeight: CGFloat {
        guard showsHeading else { return 0 }
        return (subtitle == nil ? 60 : 88) * (1 - fraction)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brandControls
                .opacity(1 - fraction)
                .frame(height: brandHeight, alignment: .top)
                .clipped()
                .allowsHitTesting(fraction < 0.5)
                .accessibilityHidden(fraction >= 0.5)

            if showsHeading {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.7))
                            .lineLimit(2)
                    }
                }
                .padding(.top, 7)
                .opacity(1 - fraction)
                .frame(height: titleHeight, alignment: .top)
                .clipped()
                .accessibilityHidden(fraction >= 0.9)
            }

            Group {
                if let accessory {
                    accessory
                } else {
                    Text(title)
                        .foregroundStyle(.white)
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 52)
            .accessibilityIdentifier("iumrah.root.pinnedSelector")

            // Home's prayer/weather panel extends the SAME black surface.
            // The panel is not another black section inside the ScrollView.
            if fraction < 0.01, let expandedContent {
                expandedContent
                    .padding(.top, 4)
                    .padding(.bottom, 12)
            }
        }
        .padding(.horizontal, IumrahDesign.pagePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { IumrahWorldDotsHeaderBackground() }
        .background(Color.iumrahSignatureBlack.ignoresSafeArea(edges: .top))
        .accessibilityIdentifier("iumrah.root.unifiedHeader")
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

/// The scroll view is permanently BELOW the single black header; no header
/// fragments are rendered in the scrolling content. All five tabs use this.
private struct IumrahSignatureScrollChrome: ViewModifier {
    let title: String
    var subtitle: String? = nil
    var pinnedAccessory: AnyView? = nil
    var showsHeading = true
    var expandedContent: AnyView? = nil
    @State private var scrollTop: CGFloat = 0

    private var collapseProgress: CGFloat {
        min(1, max(0, -scrollTop / 135))
    }

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            IumrahSignaturePinnedBar(
                collapseProgress: collapseProgress,
                title: title,
                subtitle: subtitle,
                accessory: pinnedAccessory,
                showsHeading: showsHeading,
                expandedContent: expandedContent
            )
            content
                .coordinateSpace(name: "iumrah.root.signature.scroll")
                .background(Color.iumrahPageBackground)
                .onPreferenceChange(IumrahSignatureTopPreference.self) { top in
                    // Ignore positive overscroll: pulling to refresh does NOT
                    // stretch/move the black header or render a black gap.
                    scrollTop = min(0, top)
                }
        }
        .background(Color.iumrahPageBackground)
    }
}

extension View {
    func iumrahSignatureScrollChrome(
        title: String,
        subtitle: String? = nil,
        pinnedAccessory: AnyView? = nil,
        showsHeading: Bool = true,
        expandedContent: AnyView? = nil
    ) -> some View {
        modifier(IumrahSignatureScrollChrome(
            title: title,
            subtitle: subtitle,
            pinnedAccessory: pinnedAccessory,
            showsHeading: showsHeading,
            expandedContent: expandedContent
        ))
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
