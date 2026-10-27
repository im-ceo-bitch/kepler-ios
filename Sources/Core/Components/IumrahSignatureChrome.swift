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

/// The compact chrome stays above scrolled content; it never creates a second tab bar.
private struct IumrahCompactSignatureHeader: View {
    let title: String
    @EnvironmentObject private var chrome: AppChromeStore
    @ObservedObject private var notifications = ClientNotificationCenter.shared

    var body: some View {
        HStack(spacing: 10) {
            Image("HeaderWordmarkDark")
                .resizable()
                .scaledToFit()
                .frame(width: 91, height: 31, alignment: .leading)
                .accessibilityLabel("iumrah Project")
            Rectangle().fill(.white.opacity(0.35)).frame(width: 1, height: 22)
            Text(title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .foregroundStyle(.white)
            Spacer(minLength: 0)
            Button { chrome.openNotifications() } label: {
                Image(systemName: notifications.unreadCount > 0 ? "bell.badge.fill" : "bell")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Notifications")
            Button { chrome.openSidebar() } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Menu")
        }
        .padding(.horizontal, IumrahDesign.pagePadding)
        .frame(height: 53)
        .background(Color.iumrahSignatureBlack)
    }
}

private struct IumrahSignatureScrollChrome: ViewModifier {
    let title: String
    var pinnedAccessory: AnyView? = nil
    @State private var collapsed = false

    func body(content: Content) -> some View {
        content
            .coordinateSpace(name: "iumrah.root.signature.scroll")
            // A black scroll-container background makes the rubber-band area
            // black, not system grouped grey, when the user pulls to refresh.
            .background(Color.iumrahSignatureBlack.ignoresSafeArea(edges: .top))
            .onPreferenceChange(IumrahSignatureTopPreference.self) { top in
                let next = top < -108
                if next != collapsed {
                    withAnimation(.easeInOut(duration: 0.20)) { collapsed = next }
                }
            }
            .overlay(alignment: .top) {
                if collapsed {
                    VStack(spacing: 0) {
                        IumrahCompactSignatureHeader(title: title)
                        if let pinnedAccessory {
                            pinnedAccessory
                                .padding(.horizontal, IumrahDesign.pagePadding)
                                .padding(.bottom, 10)
                        }
                    }
                    .background(Color.iumrahSignatureBlack)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .zIndex(10)
                }
            }
    }
}

extension View {
    func iumrahSignatureScrollChrome(title: String, pinnedAccessory: AnyView? = nil) -> some View {
        modifier(IumrahSignatureScrollChrome(title: title, pinnedAccessory: pinnedAccessory))
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
