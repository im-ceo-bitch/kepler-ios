import SwiftUI
import UIKit

// MARK: - iumrah Pure White / Soft Gray / Black
// Centralized semantic tokens. iOS appearance variants are monochrome in both
// modes; the approved light appearance is exact #FFFFFF / #F2F3F5 / #111111.
enum IumrahDesign {
    static let pagePadding: CGFloat = 20
    static let cardRadius: CGFloat = 20
    static let heroRadius: CGFloat = 20
    static let compactRadius: CGFloat = 16
    static let controlHeight: CGFloat = 52
    static let glassIconSize: CGFloat = 44

    enum Space {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }
}

private extension UIColor {
    static func iumrahAdaptive(light: UInt, dark: UInt) -> UIColor {
        UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                           green: CGFloat((rgb >> 8) & 0xFF) / 255,
                           blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
        }
    }

    static let iumrahHeader = iumrahAdaptive(light: 0xFFFFFF, dark: 0x111111)
    static let iumrahPage = iumrahAdaptive(light: 0xF2F3F5, dark: 0x161719)
    static let iumrahCard = iumrahAdaptive(light: 0xFFFFFF, dark: 0x232427)
    static let iumrahRaised = iumrahAdaptive(light: 0xF7F8FA, dark: 0x303136)
    static let iumrahInk = iumrahAdaptive(light: 0x111111, dark: 0xF8F8F8)
    static let iumrahMuted = iumrahAdaptive(light: 0x6E727A, dark: 0xADB0B8)
    static let iumrahDivider = iumrahAdaptive(light: 0xE7E9ED, dark: 0x35373A)
    static let iumrahPrimaryButton = iumrahAdaptive(light: 0x111111, dark: 0xFFFFFF)
    static let iumrahPrimaryButtonText = iumrahAdaptive(light: 0xFFFFFF, dark: 0x111111)
    static let iumrahCareDark = iumrahAdaptive(light: 0x111111, dark: 0x111111)
    static let iumrahCareLight = iumrahAdaptive(light: 0x6E727A, dark: 0xADB0B8)
    static let iumrahPhotoCard = iumrahAdaptive(light: 0xFFFFFF, dark: 0x232427)
    static let iumrahPhotoRaised = iumrahAdaptive(light: 0xF7F8FA, dark: 0x303136)
}

extension Color {
    static let iumrahHeaderBackground = Color(uiColor: .iumrahHeader)
    static let iumrahPageBackground = Color(uiColor: .iumrahPage)
    static let iumrahCardBackground = Color(uiColor: .iumrahCard)
    static let iumrahRaisedBackground = Color(uiColor: .iumrahRaised)
    static let iumrahInk = Color(uiColor: .iumrahInk)
    static let iumrahMuted = Color(uiColor: .iumrahMuted)
    static let iumrahDivider = Color(uiColor: .iumrahDivider)
    static let iumrahPrimaryButtonBackground = Color(uiColor: .iumrahPrimaryButton)
    static let iumrahPrimaryButtonText = Color(uiColor: .iumrahPrimaryButtonText)
    static let iumrahGraphite = Color.iumrahInk
    static let iumrahCareDark = Color(uiColor: .iumrahCareDark)
    static let iumrahCareLight = Color(uiColor: .iumrahCareLight)
    static let iumrahPhotoCardBackground = Color(uiColor: .iumrahPhotoCard)
    static let iumrahPhotoRaisedBackground = Color(uiColor: .iumrahPhotoRaised)
}

/// Lato is the product's approved font. On developer branches where the actual
/// Lato resources have not yet been bundled, use a predictable system fallback.
/// Every style scales with the user's Dynamic Type size.
enum IumrahType {
    static func regular(_ size: CGFloat, relativeTo textStyle: Font.TextStyle = .body) -> Font {
        UIFont(name: "Lato-Regular", size: size) == nil
          ? .system(textStyle, design: .default, weight: .regular)
          : .custom("Lato-Regular", size: size, relativeTo: textStyle)
    }
    static func bold(_ size: CGFloat, relativeTo textStyle: Font.TextStyle = .headline) -> Font {
        UIFont(name: "Lato-Bold", size: size) == nil
          ? .system(textStyle, design: .default, weight: .bold)
          : .custom("Lato-Bold", size: size, relativeTo: textStyle)
    }
    static var display: Font { bold(34, relativeTo: .largeTitle) }
    static var screenTitle: Font { bold(28, relativeTo: .largeTitle) }
    static var sectionTitle: Font { bold(22, relativeTo: .title2) }
    static var cardTitle: Font { bold(18, relativeTo: .headline) }
    static var body: Font { regular(16, relativeTo: .body) }
    static var secondary: Font { regular(14, relativeTo: .subheadline) }
    static var caption: Font { regular(12, relativeTo: .caption) }
}

// MARK: - Semantic icon language

/// A restrained semantic palette for content icons. Color is a navigation aid,
/// not decoration: the same kind of information keeps the same family across
/// Account, Booking, Hotels, Care, checkout and supporting screens.
enum IumrahIconRole: Hashable {
    case accent
    case travel
    case hotel
    case booking
    case umrah
    case care
    case profile
    case phone
    case mail
    case message
    case connectivity
    case device
    case gift
    case search
    case rating
    case calendar
    case location
    case security
    case notification
    case appearance
    case language
    case settings
    case document
    case payment
    case waiting
    case paymentPending
    case confirmed
    case ready
    case inTrip
    case completed
    case telegram
    case whatsapp
    case transfer
    case success
    case warning
    case destructive
    case neutral

    var color: Color {
        switch self {
        // Semantics only: danger, pending, and confirmed states must remain
        // distinguishable without depending on hue alone (paired with symbols).
        case .warning, .waiting, .paymentPending: return Color(red: 0.69, green: 0.39, blue: 0.08)
        case .destructive: return Color(red: 0.72, green: 0.16, blue: 0.18)
        case .success, .confirmed, .ready, .inTrip, .completed: return Color(red: 0.13, green: 0.43, blue: 0.32)
        default: return .iumrahInk
        }
    }

    static func inferred(from systemName: String) -> IumrahIconRole {
        let name = systemName.lowercased()

        if name.contains("trash") || name.contains("delete") { return .destructive }
        if name.contains("exclamation") || name.contains("warning") { return .warning }
        if name.contains("checkmark") || name.contains("seal") { return .success }
        if name.contains("creditcard") || name.contains("wallet") || name.contains("dollarsign") || name.contains("banknote") { return .payment }
        if name.contains("passport") || name.contains("doc") || name.contains("text.rectangle") || name.contains("id") { return .document }
        if name.contains("lock") || name.contains("shield") || name.contains("key") || name.contains("faceid") || name.contains("touchid") { return .security }
        if name.contains("bell") { return .notification }
        if name.contains("simcard") || name.contains("wifi") || name.contains("antenna") || name.contains("network") { return .connectivity }
        if name.contains("iphone") || name.contains("ipad") || name.contains("desktopcomputer") || name.contains("laptopcomputer") || name.contains("apps.iphone") { return .device }
        if name.contains("gift") { return .gift }
        if name.contains("magnifyingglass") || name.contains("scope") { return .search }
        if name.contains("star") { return .rating }
        if name.contains("lefthalf") || name.contains("sun.") || name == "sun.max.fill" || name.contains("paintpalette") { return .appearance }
        if name.contains("globe") || name.contains("character") { return .language }
        if name.contains("gear") || name.contains("slider") || name.contains("switch") { return .settings }
        if name.contains("mappin") || name.contains("location") || name.contains("map") { return .location }
        if name.contains("calendar") { return .calendar }
        if name.contains("clock") || name.contains("timer") { return .waiting }
        if name.contains("phone") { return .phone }
        if name.contains("envelope") || name.contains("mail") { return .mail }
        if name.contains("paperplane") || name.contains("message") || name.contains("bubble") || name.contains("chat") { return .message }
        if name.contains("heart") { return .care }
        if name.contains("building") || name.contains("bed") || name.contains("hotel") { return .hotel }
        if name.contains("suitcase") || name.contains("briefcase") || name.contains("ticket") { return .booking }
        if name.contains("airplane") || name.contains("car") || name.contains("bus") || name.contains("tram") || name.contains("ferry") { return .travel }
        if name.contains("book") || name.contains("moon.stars") || name.contains("hands") || name.contains("sparkles") { return .umrah }
        if name.contains("person") || name.contains("figure") { return .profile }
        if name.contains("plus") { return .accent }
        return .neutral
    }
}

/// One status = one color everywhere in the app. These are semantic state colors,
/// not decorative accents and never Liquid Glass tints.
enum IumrahBookingStatusVisual {
    static func role(for status: String) -> IumrahIconRole {
        switch status.uppercased() {
        case "NEW", "AVAILABILITY_CHECK": return .waiting
        case "PAYMENT_PENDING": return .paymentPending
        case "PAID", "BOOKING_CONFIRMED": return .confirmed
        case "DOCUMENTS_READY", "READY_TO_TRAVEL": return .ready
        case "IN_TRIP": return .inTrip
        case "COMPLETED": return .completed
        case "CANCELLED": return .destructive
        default: return .booking
        }
    }

    static func color(for status: String) -> Color { role(for: status).color }

    static func symbol(for status: String) -> String {
        switch status.uppercased() {
        case "NEW", "AVAILABILITY_CHECK": return "clock.fill"
        case "PAYMENT_PENDING": return "creditcard.fill"
        case "PAID", "BOOKING_CONFIRMED": return "checkmark.circle.fill"
        case "DOCUMENTS_READY", "READY_TO_TRAVEL": return "checkmark.seal.fill"
        case "IN_TRIP": return "location.fill"
        case "COMPLETED": return "flag.checkered"
        case "CANCELLED": return "xmark.circle.fill"
        default: return "suitcase.fill"
        }
    }
}

enum IumrahIconBadgeShape {
    case squircle
    case circle
}

/// Solid content icon badge. This intentionally never uses Liquid Glass.
/// It is the default for information rows, settings, cards and section headers.
struct IumrahIconBadge: View {
    let systemName: String
    var role: IumrahIconRole? = nil
    var tint: Color? = nil
    var size: CGFloat = 42
    var symbolSize: CGFloat = 16
    var cornerRadius: CGFloat = 14
    var shape: IumrahIconBadgeShape = .squircle

    private var resolvedRole: IumrahIconRole {
        role ?? IumrahIconRole.inferred(from: systemName)
    }

    private var resolvedColor: Color {
        if let tint { return tint }
        switch resolvedRole {
        case .warning, .waiting, .paymentPending, .destructive,
             .success, .confirmed, .ready, .inTrip, .completed:
            return resolvedRole.color.opacity(0.12)
        default:
            return .iumrahRaisedBackground
        }
    }

    private var symbolColor: Color { tint == nil ? resolvedRole.color : .white }

    @ViewBuilder
    var body: some View {
        let symbol = Image(systemName: systemName)
            .font(.system(size: symbolSize, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(symbolColor)
            .frame(width: size, height: size)

        switch shape {
        case .squircle:
            symbol
                .background(resolvedColor, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        case .circle:
            symbol
                .background(resolvedColor, in: Circle())
        }
    }
}

/// Small semantic SF Symbol without a badge, for inline metadata.
struct IumrahInlineIcon: View {
    let systemName: String
    var role: IumrahIconRole? = nil
    var size: CGFloat = 14

    var body: some View {
        let resolvedRole = role ?? IumrahIconRole.inferred(from: systemName)
        Image(systemName: systemName)
            .font(.system(size: size, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(resolvedRole.color)
    }
}

struct IumrahCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(IumrahDesign.Space.md)
            .background(Color.iumrahCardBackground,
                        in: RoundedRectangle(cornerRadius: IumrahDesign.cardRadius, style: .continuous))
    }
}

struct IumrahMarketingCardModifier: ViewModifier {
    var dark: Bool

    func body(content: Content) -> some View {
        content
            .padding(IumrahDesign.Space.lg)
            .background(dark ? Color.iumrahCareDark : Color.iumrahCardBackground,
                        in: RoundedRectangle(cornerRadius: IumrahDesign.heroRadius, style: .continuous))
    }
}

extension View {
    func iumrahCard() -> some View { modifier(IumrahCardModifier()) }
    func iumrahMarketingCard(dark: Bool = false) -> some View { modifier(IumrahMarketingCardModifier(dark: dark)) }
}

/// Primary call-to-action follows the AutoSale Umar reference: a crisp system
/// primary surface. Liquid Glass is reserved for floating / secondary controls.
struct IumrahPrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(IumrahType.bold(16, relativeTo: .body))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: IumrahDesign.controlHeight)
            .foregroundStyle(Color.iumrahPrimaryButtonText)
            .background(Color.iumrahPrimaryButtonBackground.opacity(configuration.isPressed ? 0.88 : 1),
                        in: RoundedRectangle(cornerRadius: IumrahDesign.compactRadius, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.99 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

struct IumrahSecondaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(IumrahType.bold(16, relativeTo: .body))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: IumrahDesign.controlHeight)
            .foregroundStyle(Color.iumrahInk)
            .background(Color.iumrahRaisedBackground,
                        in: RoundedRectangle(cornerRadius: IumrahDesign.compactRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

enum IumrahHaptics {
    static func soft() {
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.prepare()
        generator.impactOccurred()
    }

    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }

    static func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.success)
    }

    static func error() {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.error)
    }
}

private struct IumrahGlassModifier<S: Shape>: ViewModifier {
    let shape: S
    let interactive: Bool
    let tint: Color?
    let allowsStaticGlass: Bool
    let chrome: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), chrome || allowsStaticGlass {
            // Liquid Glass is opt-in chrome only. `interactive` changes the glass
            // response after a control has been classified as chrome; it no longer
            // turns ordinary content controls into glass by itself.
            if let tint {
                content.glassEffect(.regular.interactive(interactive).tint(tint), in: shape)
            } else {
                content.glassEffect(.regular.interactive(interactive), in: shape)
            }
        } else {
            // Content/static fallback: deterministic adaptive surface, never fake glass.
            content
                .background(tint ?? Color.iumrahRaisedBackground, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.07), lineWidth: 0.7))
        }
    }
}

extension View {
    func iumrahGlass<S: Shape>(
        in shape: S,
        interactive: Bool = false,
        tint: Color? = nil,
        allowsStaticGlass: Bool = false,
        chrome: Bool = false
    ) -> some View {
        modifier(IumrahGlassModifier(
            shape: shape,
            interactive: interactive,
            tint: tint,
            allowsStaticGlass: allowsStaticGlass,
            chrome: chrome
        ))
    }
}

/// Canonical floating icon control used throughout the app.
/// Its iOS 26 appearance is entirely provided by Apple's Liquid Glass API.
struct IumrahGlassIconButton: View {
    let systemName: String
    var size: CGFloat = IumrahDesign.glassIconSize
    var fontSize: CGFloat = 17
    var foreground: Color? = nil
    var tint: Color? = nil
    var accessibilityLabel: String? = nil
    let action: () -> Void

    var body: some View {
        Button {
            IumrahHaptics.selection()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: fontSize, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(foreground ?? Color.primary)
                .frame(width: size, height: size)
                .contentShape(Circle())
                .iumrahGlass(in: Circle(), interactive: true, tint: tint, chrome: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel ?? systemName)
    }
}

/// Canonical glass surface for compact floating information and controls.
struct IumrahGlassSurface<Content: View>: View {
    var radius: CGFloat = 22
    var interactive = false
    var tint: Color? = nil
    private let content: Content

    init(
        radius: CGFloat = 22,
        interactive: Bool = false,
        tint: Color? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.radius = radius
        self.interactive = interactive
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        content.iumrahGlass(
            in: RoundedRectangle(cornerRadius: radius, style: .continuous),
            interactive: interactive,
            tint: tint,
            allowsStaticGlass: true,
            chrome: true
        )
    }
}

/// Groups nearby native Liquid Glass elements so iOS 26 can sample and morph
/// them as one visual system. Older iOS versions simply render the content.
struct IumrahGlassGroup<Content: View>: View {
    let spacing: CGFloat?
    private let content: Content

    init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}

// MARK: - Native tab bar
/// UIKit appearance is configured once and affects only iumrah's shared tab chrome.
@MainActor
enum IumrahTabBarAppearance {
    private static var configured = false

    static func configure() {
        guard !configured else { return }
        configured = true
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .iumrahHeader
        appearance.shadowColor = .iumrahDivider
        for item in [appearance.stackedLayoutAppearance,
                     appearance.inlineLayoutAppearance,
                     appearance.compactInlineLayoutAppearance] {
            item.normal.iconColor = .iumrahMuted
            item.normal.titleTextAttributes = [.foregroundColor: UIColor.iumrahMuted]
            item.selected.iconColor = .iumrahInk
            item.selected.titleTextAttributes = [.foregroundColor: UIColor.iumrahInk]
        }
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}

// MARK: - Reusable empty/loading/error/success state view
struct IumrahStateSurface: View {
    enum Kind { case loading, empty, error, success }
    let kind: Kind
    let title: String
    let detail: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    private var symbol: String {
        switch kind {
        case .loading: return "clock"
        case .empty: return "tray"
        case .error: return "exclamationmark.circle"
        case .success: return "checkmark.circle"
        }
    }

    var body: some View {
        VStack(spacing: IumrahDesign.Space.sm) {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(Color.iumrahInk)
                .frame(width: 56, height: 56)
                .background(Color.iumrahRaisedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)
            Text(title)
                .font(IumrahType.cardTitle)
                .foregroundStyle(Color.iumrahInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(detail)
                .font(IumrahType.secondary)
                .foregroundStyle(Color.iumrahMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(IumrahPrimaryButtonStyle())
                    .padding(.top, IumrahDesign.Space.xs)
            } else if kind == .loading {
                ProgressView()
                    .tint(Color.iumrahInk)
                    .padding(.top, IumrahDesign.Space.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(IumrahDesign.Space.lg)
        .background(Color.iumrahCardBackground,
                    in: RoundedRectangle(cornerRadius: IumrahDesign.cardRadius, style: .continuous))
    }
}
