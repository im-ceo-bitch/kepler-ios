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
    @Namespace private var highlightNamespace

    var body: some View {
        IumrahGlassGroup(spacing: 8) {
            HStack(spacing: 3) {
                ForEach(options.indices, id: \.self) { index in
                    let option = options[index]
                    Button {
                        guard option.enabled else { return }
                        if selection != option.value {
                            IumrahHaptics.selection()
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
                                onSelect(option.value)
                            }
                        }
                    } label: {
                        ZStack {
                            if selection == option.value {
                                Capsule()
                                    .fill(Color.white.opacity(0.88))
                                    .matchedGeometryEffect(id: "selectedPill", in: highlightNamespace)
                                    .iumrahGlass(in: Capsule(), interactive: true, chrome: true)
                            }
                            Text(option.title)
                                .font(.system(size: 14, weight: selection == option.value ? .bold : .medium))
                                .foregroundStyle(option.enabled ? Color.iumrahInk : Color.iumrahMuted.opacity(0.5))
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                                .padding(.horizontal, 6)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: height - 8)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!option.enabled)
                    .accessibilityLabel(option.title)
                    .accessibilityAddTraits(selection == option.value ? .isSelected : [])
                }
            }
            .padding(4)
            .background(Color.iumrahRaisedBackground, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.iumrahInk.opacity(0.07), lineWidth: 0.8))
        }
        .frame(height: height)
    }
}
