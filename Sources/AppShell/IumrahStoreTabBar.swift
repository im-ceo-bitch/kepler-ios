import SwiftUI

/// Dedicated monochrome navigation for the five primary iPhone tabs.
/// Native TabView still owns screen identity and selection; only its visual
/// tab bar is replaced, so deep links and existing NavigationStacks survive.
struct IumrahStoreTabBar: View {
    @Binding var selection: AppTab
    @EnvironmentObject private var settings: AppSettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let tabs: [AppTab] = [.home, .hotels, .booking, .care, .account]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs, id: \.self) { tab in
                let active = selection == tab
                Button {
                    guard selection != tab else { return }
                    IumrahHaptics.selection()
                    if reduceMotion {
                        selection = tab
                    } else {
                        withAnimation(.easeInOut(duration: 0.18)) { selection = tab }
                    }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 21, weight: active ? .semibold : .regular))
                            .frame(height: 25)
                        Text(tab.title(for: settings.language))
                            .font(.system(size: 10.5, weight: active ? .semibold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .foregroundStyle(active ? Color.white : Color.black.opacity(0.75))
                    .frame(maxWidth: .infinity)
                    .frame(height: 65)
                    .background {
                        if active {
                            RoundedRectangle(cornerRadius: 25, style: .continuous)
                                .fill(Color.iumrahSignatureBlack)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title(for: settings.language))
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .padding(5)
        .background(Color.white.opacity(0.96), in: Capsule())
        .overlay { Capsule().strokeBorder(Color.black.opacity(0.10), lineWidth: 0.8) }
        .shadow(color: .black.opacity(0.055), radius: 20, y: 4)
        .padding(.horizontal, 16)
        .padding(.top, 5)
        .padding(.bottom, 2)
        .environment(\.colorScheme, .light)
    }
}
