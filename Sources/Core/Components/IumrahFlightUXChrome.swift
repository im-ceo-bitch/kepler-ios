import SwiftUI
import UIKit

/// Opt-in vertical bounce, required for the journey pull-to-refresh gesture.
struct IumrahNoVerticalBounce: UIViewRepresentable {
    final class Marker: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            configureScrollView()
        }
        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            configureScrollView()
        }
        func configureScrollView() {
            var ancestor = superview
            while let view = ancestor {
                if let scroll = view as? UIScrollView {
                    scroll.bounces = true
                    scroll.alwaysBounceVertical = true
                    return
                }
                ancestor = view.superview
            }
        }
    }
    func makeUIView(context: Context) -> Marker {
        let view = Marker(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }
    func updateUIView(_ uiView: Marker, context: Context) {
        uiView.configureScrollView()
    }
}

/// Reports where the bottom of the scrolling hero is relative to its ScrollView.
struct IumrahScrollingHeroBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = 1000
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Apple Liquid Glass segmented picker on iOS 26 and an accessible native
/// material fallback on iOS 17–18. Keeps selection and accessibility explicit.
struct IumrahGlassPillSelector<Value: Hashable>: View {
    struct Option {
        let value: Value
        let title: String
        let enabled: Bool
        init(_ value: Value, _ title: String, enabled: Bool = true) {
            self.value = value
            self.title = title
            self.enabled = enabled
        }
    }

    let options: [Option]
    let selection: Value
    let onSelect: (Value) -> Void
    var height: CGFloat = 54
    var body: some View {
        Picker("", selection: Binding(get: { selection }, set: { value in
            guard options.contains(where: { $0.value == value && $0.enabled }) else { return }
            IumrahHaptics.selection()
            onSelect(value)
        })) {
            ForEach(options.indices, id: \.self) { index in
                Text(options[index].title)
                    .tag(options[index].value)
                    .disabled(!options[index].enabled)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(minHeight: 44)
    }
}

/// Uses the system button renderer, including its interaction on iOS 26.
struct IumrahNativeChromeButton: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.regular)
        } else {
            content.buttonStyle(.bordered).buttonBorderShape(.circle).controlSize(.regular)
        }
    }
}

struct IumrahJourneySheetStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
            .presentationBackground(Color.iumrahPageBackground)
    }
}

/// The header is exactly the same height for Flights, Nuitee, Transfer and
/// Review, even when the search/route details are expanded.
/// Only the WHITE card grows: it never stretches the black world-map surface.
struct IumrahJourneyHeader<Summary: View>: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var chrome: AppChromeStore
    @EnvironmentObject private var settings: AppSettingsStore
    @ObservedObject private var notifications = ClientNotificationCenter.shared
    @Environment(\.journeyRefreshing) private var refreshing
    @Environment(\.journeyHeaderPull) private var pull
    @Environment(\.iumrahPullHandler) private var pullHandler
    @Environment(\.journeyTopInset) private var topInset
    var showsNotifications: Bool = false
    let summary: Summary

    init(showsNotifications: Bool = false, @ViewBuilder summary: () -> Summary) {
        self.showsNotifications = showsNotifications
        self.summary = summary()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 23, height: 23)
                }
                .modifier(IumrahNativeChromeButton())
                .accessibilityLabel(IumrahAccessibilityCopy.text(settings.language, ru: "Назад", en: "Back", uz: "Orqaga", cy: "Орқага", tr: "Geri", id: "Kembali"))
                Spacer(minLength: 0)
                Image("HeaderWordmarkLight")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: IumrahSignatureHeaderGeometry.logoWidth,
                           height: IumrahSignatureHeaderGeometry.logoHeight)
                    .accessibilityLabel("iumrah")
                Spacer(minLength: 0)
                if showsNotifications {
                    Button { chrome.openNotifications() } label: {
                        Image(systemName: notifications.unreadCount > 0 ? "bell.badge" : "bell")
                            .font(.system(size: 17, weight: .medium))
                            .frame(width: 23, height: 23)
                    }
                    .modifier(IumrahNativeChromeButton())
                    .accessibilityLabel(IumrahAccessibilityCopy.text(settings.language, ru: "Уведомления", en: "Notifications", uz: "Bildirishnomalar", cy: "Билдиришномалар", tr: "Bildirimler", id: "Notifikasi"))
                } else {
                    Color.clear.frame(width: 46, height: 46).accessibilityHidden(true)
                }
            }
            .foregroundStyle(.white)
            .frame(height: IumrahSignatureHeaderGeometry.logoHeight)
            .padding(.horizontal, 20)
            .padding(.top, IumrahSignatureHeaderGeometry.topInset + topInset)
            .padding(.bottom, IumrahSignatureHeaderGeometry.lowerInset)
            .frame(maxWidth: .infinity)
            .background {
                IumrahWorldDotsHeaderBackground(mapOpacity: 0.30)
            }
            .offset(y: -pull)
            .transaction { $0.animation = nil }

            if refreshing || pull > 18 {
                ProgressView().frame(maxWidth: .infinity)
                    .frame(height: 32 + IumrahSignatureHeaderGeometry.summaryOverlap)
            }

            // The fixed overlap is relative to the *collapsed* summary. When
            // expanded, only the card below the boundary grows downward.
            summary
                .foregroundStyle(Color.iumrahInk)
                .padding(.horizontal, 18)
                .offset(y: -IumrahSignatureHeaderGeometry.summaryOverlap)
                .padding(.bottom, -IumrahSignatureHeaderGeometry.summaryOverlap)


        }
        .background(Color.iumrahPageBackground)
        .background(IumrahPullObserver(onChange: pullHandler))
    }
}

/// Resize URLs of the same photo must not occupy multiple collage cells.
enum IumrahHotelPhotoIdentity {
    static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { value in
            guard !value.isEmpty else { return false }
            guard var url = URLComponents(string: value) else { return seen.insert(value).inserted }
            let sizing = Set(["width", "height", "w", "h", "size", "quality", "q", "fit"])
            url.queryItems = url.queryItems?.filter { !sizing.contains($0.name.lowercased()) }
            if url.queryItems?.isEmpty == true { url.queryItems = nil }
            return seen.insert(url.string ?? value).inserted
        }
    }
}

private struct JourneyHeaderFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .null
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}
private struct JourneyHeaderPullKey: EnvironmentKey { static let defaultValue: CGFloat = 0 }
private struct JourneyTopInsetKey: EnvironmentKey { static let defaultValue: CGFloat = 0 }
private struct JourneyRefreshingKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var journeyHeaderPull: CGFloat {
        get { self[JourneyHeaderPullKey.self] }
        set { self[JourneyHeaderPullKey.self] = newValue }
    }
    var journeyTopInset: CGFloat {
        get { self[JourneyTopInsetKey.self] }
        set { self[JourneyTopInsetKey.self] = newValue }
    }
    var journeyRefreshing: Bool {
        get { self[JourneyRefreshingKey.self] }
        set { self[JourneyRefreshingKey.self] = newValue }
    }
}

/// Tracks the scrolling header. Refresh progress belongs below the summary,
/// not in the logo/status-bar area. No timer or simulated network delay.
struct IumrahJourneyRefresh: ViewModifier {
    let action: () async -> Void
    @State private var pull: CGFloat = 0
    @State private var refreshing = false
    func body(content: Content) -> some View {
        GeometryReader { viewport in
            content
                .scrollBounceBehavior(.always)
                .environment(\.journeyRefreshing, refreshing)
                .environment(\.journeyHeaderPull, pull)
                .environment(\.journeyTopInset, viewport.safeAreaInsets.top)
                .environment(\.iumrahSearchPullActive, refreshing || pull > 18)
                .ignoresSafeArea(.container, edges: .top)
                .background(Color.iumrahPageBackground.ignoresSafeArea())
                .environment(\.iumrahPullHandler, { distance, released in
                    if released {
                        guard distance >= 76, !refreshing else { return }
                        refreshing = true
                        Task { @MainActor in
                            await action()
                            refreshing = false
                        }
                    } else { pull = distance }
                })
        }
    }
}
