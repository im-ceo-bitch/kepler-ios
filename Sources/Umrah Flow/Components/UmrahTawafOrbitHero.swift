import SwiftUI

/// Monochrome tawaf-inspired kinetic artwork. The orbital center sits beyond the
/// leading edge, so only the visible half of the concentric motion is rendered.
/// Decorative only: it does not measure physical location or completed laps.
struct UmrahTawafOrbitHero: View {
    let completed: Int
    let language: UmrahGuideLanguage

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var currentRound: Int { min(7, completed + 1) }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Color.black

                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion || scenePhase != .active)) { timeline in
                    Canvas(opaque: false, rendersAsynchronously: true) { context, size in
                        let leftArea = size.width * 0.55
                        context.clip(to: Path(CGRect(x: 0, y: 0, width: leftArea, height: size.height)))
                        let t = reduceMotion ? 0.0 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
                        let center = CGPoint(x: -7, y: size.height * 0.50)

                        // Deterministic varied segments avoid re-randomizing on redraw.
                        for index in 0..<150 {
                            let indexD = Double(index)
                            let seed = Double((index * 127 + 23) % 997) / 997.0
                            let noise = Double((index * 283 + 83) % 991) / 991.0
                            let radius = 28.0 + (indexD / 149.0) * min(166.0, Double(size.height) * 0.78)
                            let yRadius = radius * (0.60 + noise * 0.075)
                            let velocity = (0.20 + seed * 0.29) * (1.0 - indexD / 500.0)
                            let phase = seed * Double.pi * 2 - t * velocity
                            let angularLength = 0.14 + noise * 0.48
                            var path = Path()
                            for step in 0...11 {
                                let angle = phase + angularLength * Double(step) / 11.0
                                let ripple = sin(angle * 5 + indexD * 0.43) * 1.15
                                let point = CGPoint(
                                    x: center.x + (radius + ripple) * cos(angle),
                                    y: center.y + (yRadius + ripple) * sin(angle)
                                )
                                if step == 0 { path.move(to: point) }
                                else { path.addLine(to: point) }
                            }
                            let alpha = 0.16 + noise * 0.49
                            context.stroke(path, with: .color(.white.opacity(alpha)),
                                           style: StrokeStyle(lineWidth: (index % 5 == 0 ? 1.45 : 0.75), lineCap: .round))
                        }
                    }
                    .accessibilityHidden(true)
                }

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .clear, location: 0.36),
                        .init(color: .black.opacity(0.84), location: 0.62),
                        .init(color: .black, location: 0.76)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .allowsHitTesting(false)

                HStack(spacing: 0) {
                    Spacer(minLength: proxy.size.width * 0.46)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(UmrahTawafCopy.currentRound(language).uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(.white.opacity(0.65))
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text("\(currentRound)")
                                .font(.system(size: 50, weight: .light, design: .rounded))
                                .contentTransition(.numericText())
                            Text("/ 7")
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.60))
                        }
                        .foregroundStyle(.white)
                        Text("\(UmrahTawafCopy.completed(language)): \(completed)/7")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.78))
                            .lineLimit(2)
                    }
                    .padding(.leading, 8)
                    .padding(.trailing, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .frame(height: 198)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(UmrahTawafCopy.currentRound(language)) \(currentRound) / 7. \(UmrahTawafCopy.completed(language)) \(completed) / 7")
    }
}
