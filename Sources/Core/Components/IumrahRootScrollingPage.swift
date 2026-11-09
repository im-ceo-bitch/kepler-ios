import SwiftUI

/// Root-tab scroll architecture:
/// - upward scrolling moves the entire masthead offscreen with the content;
/// - downward overscroll compensates only the masthead, never stretches it;
/// - the system ProgressView is laid out *after* the masthead, not in the
///   status bar or over the wordmark;
/// - refresh fires once on release, never on an upward swipe.
/// This wrapper intentionally does not use .refreshable: UIKit's refresh
/// control sits above the first scroll item (the masthead), which is the
/// wrong location for the product's under-header refresh indicator.
private struct IumrahSearchPullKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var iumrahSearchPullActive: Bool {
        get { self[IumrahSearchPullKey.self] }
        set { self[IumrahSearchPullKey.self] = newValue }
    }
}

struct IumrahRootScrollingPage<Header: View, Page: View>: View {
    @EnvironmentObject private var settings: AppSettingsStore
    private let masthead: Header
    private let page: Page
    private let onRefresh: () async -> Void
    private let searchCardOverlap: CGFloat
    private let extendsUnderStatusBar: Bool
    @State private var scrollTop: CGFloat = 0
    @State private var refreshing = false

    init(
        onRefresh: @escaping () async -> Void,
        searchCardOverlap: CGFloat = 0,
        extendsUnderStatusBar: Bool = true,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Page
    ) {
        self.extendsUnderStatusBar = extendsUnderStatusBar
        self.onRefresh = onRefresh
        self.searchCardOverlap = searchCardOverlap
        self.masthead = header()
        self.page = content()
    }

    // Never cap the compensation: an unusually deep iOS rubber-band pull
    // must not expose a giant blank area ABOVE the black masthead.
    private var overscroll: CGFloat { max(0, scrollTop) }

    var body: some View {
        GeometryReader { viewport in
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                IumrahPullObserver { distance, released in
                    if released {
                        guard distance >= 76, !refreshing else { return }
                        refreshing = true
                        Task { @MainActor in
                            await onRefresh()
                            refreshing = false
                        }
                    } else {
                        scrollTop = distance
                    }
                }
                .frame(height: 0)
                .accessibilityHidden(true)

                masthead
                    .padding(.top, extendsUnderStatusBar ? viewport.safeAreaInsets.top : 0)
                    .background(alignment: .top) {
                        // Paint only the moving top inset, leaving Home's curved
                        // lower edge transparent rather than filling its corners.
                        Color.iumrahHeaderBackground
                            .frame(height: extendsUnderStatusBar ? viewport.safeAreaInsets.top : 0)
                    }
                    // The header is a normal scroll child: it disappears on
                    // upward swipes. Only positive top overscroll is cancelled.
                    .offset(y: -overscroll)
                    .transaction { $0.animation = nil }
                    // The following search card must paint ABOVE the lower
                    // edge of the hero; a positive zIndex on the masthead
                    // hid the card title on Home and Hotels.

                if refreshing || overscroll > 18 {
                    ProgressView()
                        .tint(Color.iumrahInk)
                        .controlSize(.regular)
                        .frame(maxWidth: .infinity)
                        // The search cards on Home/Hotels overlap the masthead.
                        // Reserve that overlap so the indicator is *visible*
                        // rather than being hidden behind the first card.
                        .frame(height: refreshing
                               ? 64 + searchCardOverlap
                               : min(64 + searchCardOverlap, max(0, overscroll - 8)))
                        .accessibilityLabel(NuiteeCopy.text("Обновление", "Yangilash", "Refreshing", settings.language))
                }

                page
                    .environment(\.iumrahSearchPullActive, refreshing || overscroll > 18)
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .ignoresSafeArea(.container, edges: extendsUnderStatusBar ? .top : [])
        .background(Color.iumrahPageBackground.ignoresSafeArea())
        .scrollBounceBehavior(.always)

        }
        .coordinateSpace(name: "iumrah.root.nonstickyScroll")
    }
}

struct IumrahCollapseSearchOnPull: ViewModifier {
    @Environment(\.iumrahSearchPullActive) private var pulling
    let collapse: () -> Void
    func body(content: Content) -> some View {
        content.onChange(of: pulling) { _, active in if active { collapse() } }
    }
}
