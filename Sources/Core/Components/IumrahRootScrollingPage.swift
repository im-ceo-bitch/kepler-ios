import SwiftUI

/// Normal upward scrolling, no rubber-band pull or refresh indicator.
/// The masthead stays at the top boundary when dragged down.
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
    private let headerHelp: Bool

    init(
        onRefresh: @escaping () async -> Void,
        searchCardOverlap: CGFloat = 0,
        extendsUnderStatusBar: Bool = true,
        headerHelp: Bool = false,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Page
    ) {
        self.extendsUnderStatusBar = extendsUnderStatusBar
        self.headerHelp = headerHelp
        self.onRefresh = onRefresh
        self.searchCardOverlap = searchCardOverlap
        self.masthead = header()
        self.page = content()
    }

    var body: some View {
        GeometryReader { viewport in
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
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
                    .offset(y: 0)
                    .transaction { $0.animation = nil }
                    // The following search card must paint ABOVE the lower
                    // edge of the hero; a positive zIndex on the masthead
                    // hid the card title on Home and Hotels.

                page
                    .environment(\.iumrahSearchPullActive, false)
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .background(IumrahNoVerticalBounce())
        }
        .ignoresSafeArea(.container, edges: extendsUnderStatusBar ? .top : [])
        .background(Color.iumrahPageBackground.ignoresSafeArea())


        }
        .coordinateSpace(name: "iumrah.root.nonstickyScroll")
        .modifier(IumrahHelpOverlayHost(enabled: headerHelp))
    }
}

struct IumrahCollapseSearchOnPull: ViewModifier {
    @Environment(\.iumrahSearchPullActive) private var pulling
    let collapse: () -> Void
    func body(content: Content) -> some View {
        content.onChange(of: pulling) { _, active in if active { collapse() } }
    }
}
