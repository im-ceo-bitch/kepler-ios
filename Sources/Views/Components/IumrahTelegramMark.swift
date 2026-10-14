import SwiftUI

/// The official visual supplied for iumrah Telegram controls, not an SF Paperplane.
/// Do not apply foregroundStyle/tint: the asset contains the original blue glow.
struct IumrahTelegramMark: View {
    var size: CGFloat = 28

    var body: some View {
        Image("IumrahTelegramMark")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
