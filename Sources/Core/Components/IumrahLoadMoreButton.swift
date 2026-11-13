import SwiftUI

/// Reveal another page without requesting the catalogue again.
struct IumrahLoadMoreButton: View {
    @EnvironmentObject private var settings: AppSettingsStore
    let remaining: Int
    let action: () -> Void
    var body: some View {
        if remaining > 0 {
            Button {
                IumrahHaptics.selection()
                action()
            } label: {
                Text(NuiteeCopy.text("Показать ещё \(min(20, remaining))", "Yana \(min(20, remaining)) ta ko‘rsatish", "Show \(min(20, remaining)) more", settings.language))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(IumrahSecondaryButtonStyle())
            .padding(.vertical, 6)
        }
    }
}
