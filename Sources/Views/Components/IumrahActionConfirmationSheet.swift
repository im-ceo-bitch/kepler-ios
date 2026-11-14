import SwiftUI

struct IumrahActionConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let message: String
    let confirmTitle: String
    let cancelTitle: String
    var confirmColor: Color = .red
    let onConfirm: () -> Void
    @State private var contentHeight: CGFloat = 310

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 32, weight: .medium))
                    .frame(width: 66, height: 66)
                    .background(Color.iumrahRaisedBackground, in: RoundedRectangle(cornerRadius: 22))
                    .accessibilityHidden(true)
                Text(title).font(.title2.bold()).multilineTextAlignment(.center)
                Text(message).font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { cancelButton; confirmButton }
                    VStack(spacing: 8) { confirmButton; cancelButton }
                }.padding(.top, 4)
            }
            .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 18)
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                if height > 0 { contentHeight = height + 12 }
            }
        }
        .background(Color.iumrahPageBackground)
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(contentHeight)])
        .presentationDragIndicator(.visible)
    }
    private var cancelButton: some View {
        Button { IumrahHaptics.selection(); dismiss() } label: {
            Text(cancelTitle).font(.headline).frame(maxWidth: .infinity).frame(minHeight: 48)
        }.buttonStyle(.bordered).buttonBorderShape(.capsule).tint(.primary)
    }
    private var confirmButton: some View {
        Button(role: .destructive) { IumrahHaptics.selection(); onConfirm(); dismiss() } label: {
            Text(confirmTitle).font(.headline).frame(maxWidth: .infinity).frame(minHeight: 48)
        }.buttonStyle(.borderedProminent).buttonBorderShape(.capsule).tint(confirmColor)
    }
}
