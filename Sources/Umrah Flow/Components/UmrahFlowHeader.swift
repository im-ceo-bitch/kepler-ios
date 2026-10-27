import SwiftUI

struct UmrahFlowHeader: View {
    let title: String
    let progress: Double
    let stageNumber: Int
    let language: UmrahGuideLanguage
    let onClose: () -> Void
    let onOpenNavigator: () -> Void

    // Inner ritual navigation has the same anchored monochrome identity as the
    // five root headers. Only the content below it responds to light/dark mode.
    private var primary: Color { .white }
    private var secondary: Color { .white.opacity(0.58) }
    private var normalized: Double { max(0, min(1, progress)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(primary)
                        .frame(width: 44, height: 44)
                        .background(primary.opacity(0.055), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(UmrahFlowCopy.closeFlowLabel)

                Spacer(minLength: 4)
                HStack(spacing: 7) {
                    Image("HeaderWordmarkDark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 94, height: 30)
                        .accessibilityLabel("iumrah Project")
                    Text("FLOW")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .tracking(1.1)
                        .foregroundStyle(secondary)
                }
                Spacer(minLength: 4)
                Button(action: onOpenNavigator) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(primary)
                        .frame(width: 44, height: 44)
                        .background(primary.opacity(0.055), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(UmrahFlowCopy.chooseStageLabel)
            }

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(UmrahTawafCopy.routeStage(language, current: stageNumber))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(secondary)
                    Text(title)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(Int((normalized * 100).rounded()))%")
                        .font(.system(size: 23, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(primary)
                    Text(UmrahTawafCopy.routeProgress(language))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(secondary)
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(primary.opacity(0.10))
                    Capsule().fill(primary)
                        .frame(width: proxy.size.width * normalized)
                        .animation(.easeInOut(duration: 0.28), value: normalized)
                }
            }
            .frame(height: 5)
            .accessibilityLabel(UmrahTawafCopy.routeProgress(language))
            .accessibilityValue("\(Int((normalized * 100).rounded()))%")
        }
        .padding(.horizontal, 20)
        .padding(.top, 5)
        .padding(.bottom, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            IumrahWorldDotsHeaderBackground(mapOpacity: 0.425, waveSpeed: 0.56, waveIntensity: 0.78)
                .ignoresSafeArea(edges: .top)
        }
    }
}
