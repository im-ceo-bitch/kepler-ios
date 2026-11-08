import SwiftUI
import UIKit

/// Non-global scroll configuration. Disables overscroll/stretch only in the
/// Home and Flight First pages that opt into this marker.
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
                    scroll.bounces = false
                    scroll.alwaysBounceVertical = false
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
            content.buttonStyle(.glass).buttonBorderShape(.circle)
        } else {
            content.buttonStyle(.bordered).buttonBorderShape(.circle)
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

/// Shared compact identity for the flight and hotel selection screens.
struct IumrahJourneyHeader<Summary: View>: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var chrome: AppChromeStore
    @EnvironmentObject private var settings: AppSettingsStore
    @ObservedObject private var notifications = ClientNotificationCenter.shared
    var showsNotifications: Bool = false
    let summary: Summary
    init(showsNotifications: Bool = false, @ViewBuilder summary: () -> Summary) {
        self.showsNotifications = showsNotifications
        self.summary = summary()
    }
    var body: some View {
        VStack(spacing: 32) {
            HStack {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                }
                .modifier(IumrahNativeChromeButton())
                .accessibilityLabel(IumrahAccessibilityCopy.text(settings.language, ru: "Назад", en: "Back", uz: "Orqaga", cy: "Орқага", tr: "Geri", id: "Kembali"))
                Spacer(minLength: 0)
                Image("HeaderWordmarkLight")
                    .resizable().renderingMode(.template).scaledToFit()
                    .frame(width: 208, height: 64)
                    .accessibilityLabel("iumrah")
                Spacer(minLength: 0)
                if showsNotifications {
                    Button { chrome.openNotifications() } label: {
                        Image(systemName: notifications.unreadCount > 0 ? "bell.badge" : "bell")
                            .frame(width: 44, height: 44)
                    }
                    .modifier(IumrahNativeChromeButton())
                    .accessibilityLabel(IumrahAccessibilityCopy.text(settings.language, ru: "Уведомления", en: "Notifications", uz: "Bildirishnomalar", cy: "Билдиришномалар", tr: "Bildirimler", id: "Notifikasi"))
                } else {
                    Color.clear.frame(width: 44, height: 44)
                }
            }
            .foregroundStyle(.white)
            summary
                .foregroundStyle(Color.iumrahInk)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 24)
        .background {
            IumrahWorldDotsHeaderBackground(mapOpacity: 0.30)
                .ignoresSafeArea(edges: .top)
        }
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 30, bottomTrailingRadius: 30))
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
