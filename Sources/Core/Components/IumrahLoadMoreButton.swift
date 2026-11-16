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

/// Requests the next server page; preserves previously loaded rows on failure.
struct IumrahHotelPageButton: View {
    @EnvironmentObject private var settings: AppSettingsStore
    let remaining: Int
    let loading: Bool
    let failed: Bool
    let hasMore: Bool
    let action: () -> Void
    var body: some View {
        if hasMore {
            Button(action: action) {
                HStack {
                    Spacer()
                    if loading { ProgressView().controlSize(.small) }
                    Text(failed ? NuiteeCopy.text("Повторить загрузку", "Qayta yuklash", "Retry loading", settings.language) : NuiteeCopy.text("Показать ещё \(min(10, max(1, remaining))) отелей", "Yana \(min(10, max(1, remaining))) ta mehmonxona", "Show \(min(10, max(1, remaining))) more hotels", settings.language))
                    Spacer()
                }
            }.buttonStyle(IumrahSecondaryButtonStyle()).disabled(loading).padding(.vertical, 6)
        }
    }
}
