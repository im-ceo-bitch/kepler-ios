import SwiftUI
import UIKit

enum TripProgressStage: Int, CaseIterable {
    case trip = 1
    case hotel = 2
    case flight = 3
    case transfer = 4
    case ready = 5

    var localizationKey: String {
        switch self {
        case .trip: return "step_trip"
        case .hotel: return "step_hotel"
        case .flight: return "step_flight"
        case .transfer: return "step_transfer"
        case .ready: return "step_ready"
        }
    }

    fileprivate var carouselSymbol: String {
        switch self {
        case .trip: return "calendar"
        case .hotel: return "building.2.fill"
        case .flight: return "airplane.departure"
        case .transfer: return "car.side.fill"
        case .ready: return "checkmark.seal.fill"
        }
    }

    fileprivate var carouselRole: IumrahIconRole {
        switch self {
        case .trip: return .calendar
        case .hotel: return .hotel
        case .flight: return .travel
        case .transfer: return .transfer
        case .ready: return .success
        }
    }
}

/// Compatibility progress view retained for non-generator call sites. The five
/// generator destinations now render the same progress information inside the
/// pinned generator header instead of duplicating a card in scroll content.
struct IumrahFlowProgress: View {
    @EnvironmentObject private var settings: AppSettingsStore
    let stage: TripProgressStage
    var labelKey: String? = nil
    var currentPriceText: String? = nil

    var body: some View {
        GeneratorProgressStrip(
            stage: stage,
            labelKey: labelKey,
            currentPriceText: currentPriceText
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .iumrahGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Generator pinned header

/// The progress strip is deliberately surface-free here because it lives inside
/// the single pinned generator container with the carousel and back control.
private struct GeneratorProgressStrip: View {
    @EnvironmentObject private var settings: AppSettingsStore

    let stage: TripProgressStage
    var labelKey: String? = nil
    var currentPriceText: String? = nil
    var isPriceLoading: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: IumrahFoundation.Space.sm) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(FlowCopy.text(.stepOfFour, settings.language)) \(stage.rawValue) / 5")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)

                if let currentPriceText {
                    HStack(spacing: 5) {
                        if isPriceLoading { ProgressView().controlSize(.mini) }
                        Text(currentPriceText)
                            .font(.callout.monospacedDigit().weight(.bold))
                            .contentTransition(.numericText())
                            .accessibilityLabel(currentPriceLabel + ": " + currentPriceText)
                    }
                } else {
                    Text(L10n.text(labelKey ?? stage.localizationKey, settings.language))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            IumrahFoundationStageRail(
                stages: TripProgressStage.allCases.map {
                    IumrahFoundationStage(
                        id: $0.rawValue - 1,
                        title: L10n.text($0.localizationKey, settings.language),
                        symbol: $0.carouselSymbol
                    )
                },
                currentIndex: stage.rawValue - 1
            )
        }
    }

    private var currentPriceLabel: String {
        switch settings.language {
        case .russian: return "ТЕКУЩАЯ ЦЕНА"
        case .turkish: return TurkishLocalization.phrase("CURRENT TOTAL")
        case .arabic: return ArabicLocalization.phrase("CURRENT TOTAL")
        case .indonesian, .malay, .english: return "CURRENT TOTAL"
        case .uzbek: return "JORIY NARX"
        case .uzbekCyrillic: return "ЖОРИЙ НАРХ"
        }
    }

}

/// Compact generator chrome that is rendered *inside* each screen's scroll
/// content. It therefore clears the hardware safe area naturally on entry and
/// scrolls away with the page instead of staying pinned above the content.
///
/// The outer surface and the back button both use Apple's iOS 26 Liquid Glass
/// APIs. On earlier iOS versions the design system falls back to a restrained
/// opaque surface; blur is never used to imitate Liquid Glass.
struct IumrahGeneratorHeader: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettingsStore

    let stage: TripProgressStage
    var currentPriceText: String? = nil
    var isPriceLoading: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: IumrahFoundation.Space.sm) {
            HStack(spacing: 12) {
                nativeBackButton
                VStack(alignment: .leading, spacing: 3) {
                    Text("iumrah CONFIGURATOR")
                        .font(IumrahFoundation.TypeStyle.eyebrow)
                        .tracking(1.15)
                        .foregroundStyle(.secondary)
                    Text(L10n.text(stage.localizationKey, settings.language))
                        .font(IumrahFoundation.TypeStyle.title)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                }
                Spacer(minLength: 0)
            }

            GeneratorProgressStrip(
                stage: stage,
                currentPriceText: currentPriceText,
                isPriceLoading: isPriceLoading
            )
        }
        .padding(IumrahFoundation.Space.md)
        .background(Color.iumrahCardBackground, in: RoundedRectangle(cornerRadius: IumrahFoundation.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: IumrahFoundation.Radius.card, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.8)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var nativeBackButton: some View {
        if #available(iOS 26.0, *) {
            Button {
                IumrahHaptics.selection()
                dismiss()
            } label: {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .contentShape(Circle())
            }
            .buttonStyle(.glass)
            .accessibilityLabel(backAccessibilityLabel)
        } else {
            Button {
                IumrahHaptics.selection()
                dismiss()
            } label: {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .frame(width: 40, height: 40)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .background(Color.iumrahRaisedBackground, in: Circle())
            .overlay(Circle().stroke(Color.primary.opacity(0.07), lineWidth: 0.7))
            .accessibilityLabel(backAccessibilityLabel)
        }
    }

    private var backAccessibilityLabel: String {
        switch settings.language {
        case .russian: return "Назад"
        case .turkish: return TurkishLocalization.phrase("Back")
        case .arabic: return ArabicLocalization.phrase("Back")
        case .indonesian, .malay, .english: return "Back"
        case .uzbek: return "Orqaga"
        case .uzbekCyrillic: return "Орқага"
        }
    }
}

/// Keeps UINavigationController's native edge-swipe pop gesture available even
/// though generator screens hide the stock navigation bar in favor of the
/// in-content generator header above.
private struct GeneratorInteractivePopRestorer: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {}

    final class Controller: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            // The hidden system bar must not disable the standard iOS edge-pop.
            // Resolve the parent UINavigationController after SwiftUI installs
            // the hosting controller, then restore the native gesture only on
            // pushed screens (never on the root of the stack).
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                var candidate: UIViewController? = self
                while let controller = candidate {
                    if let navigation = controller as? UINavigationController ?? controller.navigationController {
                        guard navigation.viewControllers.count > 1 else { return }
                        navigation.interactivePopGestureRecognizer?.delegate = nil
                        navigation.interactivePopGestureRecognizer?.isEnabled = true
                        return
                    }
                    candidate = controller.parent
                }
            }
        }
    }
}

private struct IumrahInternalNavigationModifier: ViewModifier {
    @EnvironmentObject private var chrome: AppChromeStore

    let progressStage: TripProgressStage?
    let showsGeneratorAmbient: Bool
    let currentPriceText: String?

    @State private var registered = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if showsGeneratorAmbient, progressStage != nil {
            content
                // The generator header is part of each destination's own scroll
                // content. This branch only removes the stock navigation bar and
                // preserves Apple's interactive edge-swipe back gesture.
                .toolbar(.hidden, for: .navigationBar)
                .navigationBarBackButtonHidden(true)
                .background {
                    GeneratorInteractivePopRestorer()
                        .frame(width: 0, height: 0)
                }
                .tint(Color.primary)
                .modifier(InternalChromeRegistrationModifier(
                    chrome: chrome,
                    registered: $registered
                ))
        } else {
            content
                .toolbar(.visible, for: .navigationBar)
                .navigationBarBackButtonHidden(false)
                .navigationBarTitleDisplayMode(.inline)
                .tint(Color.primary)
                .modifier(InternalChromeRegistrationModifier(
                    chrome: chrome,
                    registered: $registered
                ))
        }
    }
}

/// Isolated lifecycle registration avoids duplicating onAppear/onDisappear
/// bookkeeping across the two navigation presentation branches above.
private struct InternalChromeRegistrationModifier: ViewModifier {
    let chrome: AppChromeStore
    @Binding var registered: Bool

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard !registered else { return }
                registered = true
                chrome.beginInternalNavigation()
            }
            .onDisappear {
                guard registered else { return }
                registered = false
                chrome.endInternalNavigation()
            }
    }
}

extension View {
    func iumrahInternalNavigation(
        progress: TripProgressStage? = nil,
        showsGeneratorAmbient: Bool = false,
        currentPriceText: String? = nil
    ) -> some View {
        modifier(
            IumrahInternalNavigationModifier(
                progressStage: progress,
                showsGeneratorAmbient: showsGeneratorAmbient,
                currentPriceText: currentPriceText
            )
        )
    }
}
