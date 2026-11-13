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

/// One native root chrome for all five tabs.
/// The large masthead collapses into a real, accessible compact navigation bar;
/// it never disappears to a zero-height black strip above the results.
struct IumrahSignaturePinnedBar: View {
    let collapseProgress: CGFloat
    let title: String
    var subtitle: String? = nil
    var accessory: AnyView? = nil
    var showsHeading = true
    var expandedContent: AnyView? = nil
    @EnvironmentObject private var chrome: AppChromeStore
    @Environment(\.iumrahNavigationChromeStyle) private var navigationChromeStyle
    @ObservedObject private var notifications = ClientNotificationCenter.shared

    private var fraction: CGFloat { min(1, max(0, collapseProgress)) }
    private var brandHeight: CGFloat { 52 * (1 - fraction) }
    private var titleHeight: CGFloat {
        guard showsHeading else { return 0 }
        return (subtitle == nil ? 45 : 68) * (1 - fraction)
    }
    private var compactHeight: CGFloat { 48 * fraction }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            compactControls
                .opacity(fraction)
                .frame(height: compactHeight, alignment: .center)
                .clipped()
                .allowsHitTesting(fraction > 0.5)
                .accessibilityHidden(fraction <= 0.5)

            brandControls
                .opacity(1 - fraction)
                .frame(height: brandHeight, alignment: .top)
                .clipped()
                .allowsHitTesting(fraction < 0.5)
                .accessibilityHidden(fraction >= 0.5)

            if showsHeading {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.72))
                            .lineLimit(2)
                    }
                }
                .padding(.top, 4)
                .opacity(1 - fraction)
                .frame(height: titleHeight, alignment: .top)
                .clipped()
                .accessibilityHidden(fraction >= 0.9)
            }

            if let accessory {
                accessory
                    .opacity(1 - fraction)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: max(0, 46 * (1 - fraction)))
                    .clipped()
                    .allowsHitTesting(fraction < 0.95)
                    .accessibilityHidden(fraction >= 0.95)
                    .accessibilityIdentifier("iumrah.root.pinnedSelector")
            }

            if let expandedContent {
                expandedContent
                    .opacity(1 - fraction)
                    .frame(height: max(0, 56 * (1 - fraction)))
                    .clipped()
                    .allowsHitTesting(fraction < 0.5)
            }
        }
        .padding(.horizontal, IumrahDesign.pagePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { IumrahWorldDotsHeaderBackground(mapOpacity: 0.28 * Double(1 - fraction)) }
        .background(Color.iumrahSignatureBlack.ignoresSafeArea(edges: .top))
        .accessibilityIdentifier("iumrah.root.unifiedHeader")
    }

    /// Replaces the expanded wordmark/title/selector after the user scrolls.
    /// Controls stay reachable, unlike the former disappearing header.
    private var compactControls: some View {
        HStack(spacing: 10) {
            Text(title.isEmpty ? "iumrah" : title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 6)
            trailingControls
        }
    }

    private var brandControls: some View {
        ViewThatFits(in: .horizontal) {
            brandRow(wordmarkWidth: 176)
            brandRow(wordmarkWidth: 144)
        }
    }

    private func brandRow(wordmarkWidth: CGFloat) -> some View {
        HStack(spacing: 10) {
            Image("HeaderWordmarkDark")
                .resizable()
                .scaledToFit()
                .frame(width: wordmarkWidth, height: 42, alignment: .leading)
                .accessibilityLabel("iumrah Project")
            Spacer(minLength: 2)
            trailingControls
        }
    }

    private var trailingControls: some View {
        HStack(spacing: 10) {
            Button { chrome.openNotifications() } label: {
                Image(systemName: notifications.unreadCount > 0 ? "bell.badge.fill" : "bell")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    
            }
            .modifier(IumrahNativeChromeButton())
            .accessibilityLabel("Notifications")

            if navigationChromeStyle == .drawer {
                Button { chrome.openSidebar() } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        
                }
                .modifier(IumrahNativeChromeButton())
                .accessibilityLabel("Menu")
            }
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
        min(1, max(0, -scrollTop / 112))
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
                ForEach(tabs, id: \.id) { tab in
                    let active = selectedID == tab.id
                    Button { onSelect(tab.id) } label: {
                        Text(tab.title)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .padding(.horizontal, 15)
                            .frame(height: 40)
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
    @Environment(\.iumrahSearchPullActive) private var pulling
    @Environment(\.journeyRefreshing) private var refreshing
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
                .foregroundStyle(Color.primary)
                .padding(15)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isExpanded
                ? localized("Свернуть поиск", "Qidiruvni yopish", "Collapse search")
                : localized("Изменить параметры", "Qidiruv shartlarini o‘zgartirish", "Edit search"))

            if isExpanded {
                Rectangle().fill(Color.black.opacity(0.12)).frame(height: 1)
                content
                    .padding(15)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(minHeight: 80)
        .modifier(IumrahAnimatedSearchBorder())
        .animation(.easeInOut(duration: 0.20), value: isExpanded)
        .onChange(of: pulling || refreshing) { _, active in
            if active { isExpanded = false }
        }
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

/// One opaque search surface and the original moving monochrome border.
struct IumrahAnimatedSearchBorder: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    var radius: CGFloat = 34
    var guidance: Bool = false
    var greenAccent: Bool = false
    func body(content: Content) -> some View {
        content
            .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                TimelineView(.animation(minimumInterval: 1.0 / 24.0,
                                         paused: reduceMotion || scenePhase != .active)) { timeline in
                    let rotation = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 5) * 72
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(AngularGradient(colors: greenAccent ? [Color(red: 0.08, green: 0.55, blue: 0.30), Color(red: 0.40, green: 0.88, blue: 0.55), .white, Color(red: 0.14, green: 0.65, blue: 0.39), Color(red: 0.08, green: 0.55, blue: 0.30)] : guidance ? [Color(red: 0.96, green: 0.66, blue: 0.08), Color(red: 1, green: 0.83, blue: 0.33), .white, Color(red: 1, green: 0.92, blue: 0.65), Color(red: 0.96, green: 0.66, blue: 0.08)] : [.black, .black, .white, .gray, .black, .white, .black],
                            center: .center, startAngle: .degrees(rotation), endAngle: .degrees(rotation + 360)), lineWidth: 3)
                        .allowsHitTesting(false)
                }
            }
    }
}
