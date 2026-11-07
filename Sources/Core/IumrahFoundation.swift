import SwiftUI
import UIKit

// Semantic graphite token used by root chrome and navigation.
extension Color {
    static let iumrahDesertGold = Color(red: 181.0 / 255, green: 134.0 / 255, blue: 69.0 / 255)
    static let iumrahHeaderBackground = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.18, green: 0.18, blue: 0.19, alpha: 1)
            : UIColor(white: 17.0 / 255, alpha: 1)
    })
    static let iumrahSignatureBlack = Color(red: 17.0 / 255.0, green: 17.0 / 255.0, blue: 17.0 / 255.0)
}

// MARK: - iumrah Design Foundation v1
// Single source of truth for customer-facing screen geometry and motion.
// No package, pricing, authentication or booking state is stored here.
enum IumrahFoundation {
    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let page: CGFloat = 18
        static let lg: CGFloat = 22
        static let xl: CGFloat = 28
    }

    enum Radius {
        static let control: CGFloat = 19
        static let smallCard: CGFloat = 22
        static let card: CGFloat = 28
        static let hero: CGFloat = 34
    }

    enum Size {
        static let buttonHeight: CGFloat = 56
        static let minimumTapTarget: CGFloat = 44
    }

    enum TypeStyle {
        static let eyebrow: Font = .system(.caption2, design: .rounded, weight: .bold)
        static let hero: Font = .system(.largeTitle, design: .rounded, weight: .bold)
        static let section: Font = .system(.title2, design: .rounded, weight: .bold)
        static let title: Font = .system(.title3, design: .rounded, weight: .bold)
        static let body: Font = .system(.body)
        static let caption: Font = .system(.caption, weight: .medium)
    }

    enum Motion {
        static let press: Animation = .easeOut(duration: 0.16)
        static let change: Animation = .easeInOut(duration: 0.24)
        static let entrance: Animation = .spring(response: 0.48, dampingFraction: 0.88)
        static let orbitRevolution: TimeInterval = 11
        static let orbitReveal: TimeInterval = 0.95
    }
}

/// Monochrome content container. iOS Liquid Glass is reserved for navigation chrome.
struct IumrahFoundationCard<Content: View>: View {
    var dark = false
    var inset: CGFloat = IumrahFoundation.Space.lg
    let content: Content

    init(dark: Bool = false, inset: CGFloat = IumrahFoundation.Space.lg, @ViewBuilder content: () -> Content) {
        self.dark = dark
        self.inset = inset
        self.content = content()
    }

    var body: some View {
        content
            .padding(inset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                dark ? Color.iumrahSignatureBlack : Color.iumrahCardBackground,
                in: RoundedRectangle(cornerRadius: IumrahFoundation.Radius.card, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: IumrahFoundation.Radius.card, style: .continuous)
                    .strokeBorder(dark ? Color.white.opacity(0.10) : Color.primary.opacity(0.09), lineWidth: 0.8)
            }
    }
}

struct IumrahFoundationSectionTitle: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: IumrahFoundation.Space.xs) {
            Text(title)
                .font(IumrahFoundation.TypeStyle.section)
                .tracking(-0.6)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(IumrahFoundation.TypeStyle.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct IumrahFoundationFeature: View {
    let symbol: String
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .foregroundStyle(.primary)
        .accessibilityElement(children: .combine)
    }
}

/// Progress is driven by actual navigation/state, never by an animation timer.
struct IumrahFoundationStage: Identifiable {
    let id: Int
    let title: String
    let symbol: String
}

struct IumrahFoundationStageRail: View {
    let stages: [IumrahFoundationStage]
    let currentIndex: Int

    var body: some View {
        HStack(alignment: .center, spacing: 5) {
            ForEach(stages) { stage in
                let completed = stage.id < currentIndex
                let active = stage.id == currentIndex
                if stage.id != stages.first?.id {
                    Capsule()
                        .fill(completed || active ? Color.primary.opacity(0.60) : Color.primary.opacity(0.10))
                        .frame(maxWidth: .infinity)
                        .frame(height: 2)
                        .accessibilityHidden(true)
                }
                Image(systemName: completed ? "checkmark" : stage.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(active || completed ? Color.iumrahPrimaryButtonText : Color.secondary)
                    .frame(width: active ? 38 : 32, height: active ? 38 : 32)
                    .background(active || completed ? Color.iumrahPrimaryButtonBackground : Color.iumrahRaisedBackground, in: Circle())
                    .overlay {
                        Circle().strokeBorder(Color.primary.opacity(active ? 0 : 0.08), lineWidth: 0.8)
                    }
                    .accessibilityLabel(stage.title)
                    .accessibilityAddTraits(active ? [.isSelected] : [])
            }
        }
        .animation(IumrahFoundation.Motion.change, value: currentIndex)
        .accessibilityElement(children: .contain)
    }
}

/// Small step counter used by the eight-page family configuration branch.
struct IumrahFoundationCompactSteps: View {
    let total: Int
    let current: Int // 1-based
    var language: AppSettingsStore.Language = .english

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<max(1, total), id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(index < current ? Color.primary : Color.primary.opacity(0.12))
                    .frame(maxWidth: .infinity)
                    .frame(height: 4)
            }
            Text("\(min(max(current, 1), max(1, total))) / \(max(1, total))")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        switch language {
        case .russian: return "Шаг \(current) из \(total)"
        case .uzbek: return "\(current)-bosqich, jami \(total)"
        case .uzbekCyrillic: return "\(current)-босқич, жами \(total)"
        default: return "Step \(current) of \(total)"
        }
    }
}

struct IumrahFoundationHomeHero: View {
    let title: String
    let subtitle: String
    let actionTitle: String
    let kicker: String
    let featureTitles: [String]
    let action: () -> Void

    private let symbols = ["airplane", "building.2", "person.2"]

    var body: some View {
        IumrahFoundationCard(inset: 22) {
            VStack(alignment: .leading, spacing: IumrahFoundation.Space.md) {
                HStack(spacing: 10) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.7))
                        .frame(width: 21, height: 1)
                        .accessibilityHidden(true)
                    Text(kicker)
                        .font(.system(.caption2, design: .default, weight: .bold))
                        .tracking(1.5)
                }
                .foregroundStyle(.secondary)

                Text(title)
                    .font(.system(.largeTitle, design: .default, weight: .bold))
                    .tracking(-1.15)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text(subtitle)
                    .font(IumrahFoundation.TypeStyle.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { featureChips }
                    VStack(alignment: .leading, spacing: 7) { featureChips }
                }
                .padding(.vertical, 4)

                Button(action: action) {
                    HStack(spacing: 12) {
                        Text(actionTitle)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
                .buttonStyle(IumrahPrimaryButtonStyle())
                .accessibilityIdentifier("iumrah.home.foundation.start")
            }
        }
    }

    @ViewBuilder private var featureChips: some View {
        ForEach(0..<min(featureTitles.count, symbols.count), id: \.self) { index in
            HStack(spacing: 5) {
                Image(systemName: symbols[index])
                    .font(.system(size: 11, weight: .medium))
                    .accessibilityHidden(true)
                Text(featureTitles[index])
                    .font(.system(.caption, design: .default, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.13), lineWidth: 0.8)
            )
            .accessibilityElement(children: .combine)
        }
    }
}
