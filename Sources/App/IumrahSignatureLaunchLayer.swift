import SwiftUI

/// Static monochrome logo. The native iOS LaunchScreen shows the same brand
/// before SwiftUI mounts. Home's animated world map and booking sounds remain
/// completely independent from this one-shot app-launch surface.
struct IumrahSignatureLaunchLayer: View {
    var body: some View {
        ZStack {
            Color("LaunchBackground")
            VStack(spacing: 4) {
                Image("HeaderWordmarkLight")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .foregroundStyle(.white)
                    .frame(maxWidth: 224)
                    .accessibilityLabel("iumrah")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
    }
}
