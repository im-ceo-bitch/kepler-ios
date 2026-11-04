import SwiftUI

/// An icon that can emerge from a rotating orbit dot. All artwork is native SF Symbols.
struct IumrahOrbitService: Identifiable, Hashable {
    let id: String
    let symbol: String

    static let showcase: [IumrahOrbitService] = [
        .init(id: "flight", symbol: "airplane"),
        .init(id: "hotel", symbol: "building.2.fill"),
        .init(id: "transfer", symbol: "car.side.fill"),
        .init(id: "booking", symbol: "checkmark.seal.fill"),
        .init(id: "luggage", symbol: "suitcase.rolling.fill"),
        .init(id: "ziyarat", symbol: "mappin.and.ellipse"),
        .init(id: "guide", symbol: "person.2.fill"),
        .init(id: "esim", symbol: "antenna.radiowaves.left.and.right")
    ]
}

enum IumrahOrbitMode: Equatable {
    /// One moving dot expands into a service symbol, then contracts again.
    case showcase
    /// Progress counts are taken from the actual generator, not from a timer.
    case progress(completed: Int, active: Int)
    /// A one-shot visual merge. Does not create or confirm a booking.
    case assembling
}

/// Standalone, native, reusable iOS 17+ animation. No timers, GIFs or video.
/// Updates pause when the app is inactive, the view is explicitly deactivated, or Reduce Motion is enabled.
struct IumrahOrbitIconRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var mode: IumrahOrbitMode = .showcase
    var services: [IumrahOrbitService] = .showcase
    var diameter: CGFloat = 240
    var isActive: Bool = true
    var lightOnDark: Bool = true
    var rotationDuration: TimeInterval = 11
    var revealDuration: TimeInterval = 0.95

    @State private var orbitStart = Date()
    @State private var assemblyStart = Date()

    private var foreground: Color { lightOnDark ? .white : .black }
    private var muted: Color { lightOnDark ? Color.white.opacity(0.38) : Color.black.opacity(0.30) }
    private var background: Color { lightOnDark ? Color(red: 0.09, green: 0.09, blue: 0.12) : .white }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0,
                                paused: !isActive || scenePhase != .active || reduceMotion)) { timeline in
            let orbitTime = reduceMotion ? 0 : max(0, timeline.date.timeIntervalSince(orbitStart))
            let assemblyTime = reduceMotion ? 4 : max(0, timeline.date.timeIntervalSince(assemblyStart))
            let count = max(1, services.count)
            let step = max(0.35, revealDuration)
            let tick = Int(orbitTime / step)
            let revealPhase = (orbitTime / step).truncatingRemainder(dividingBy: 1)
            let expansion = pow(max(0, sin(.pi * revealPhase)), 0.86)
            let progress = modeProgress
            let merge = smoothStep((assemblyTime - 0.65) / 1.7)
            let completed = smoothStep((assemblyTime - 2.15) / 0.55)

            ZStack {
                Canvas(opaque: false, rendersAsynchronously: true) { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let outerRadius = min(size.width, size.height) * 0.39
                    let rotation = orbitTime * 2 * .pi / max(3, rotationDuration)
                    let fade = mode == .assembling ? 1 - completed * 0.84 : 1.0

                    for ring in 0..<3 {
                        let radius = outerRadius * (1 - CGFloat(ring) * 0.145)
                        for dot in 0..<24 {
                            // The expanding service is drawn as a real SF Symbol overlay.
                            if ring == 0 && mode == .showcase && dot == tick % 24 && !reduceMotion { continue }
                            let angle = Double(dot) * 2 * .pi / 24 + rotation + Double(ring) * 0.11
                            let wobble = 1 + 0.09 * sin(orbitTime * 3 - Double(dot) * 0.5 + Double(ring))
                            let x = center.x + radius * CGFloat(cos(angle))
                            let y = center.y + radius * CGFloat(sin(angle))
                            let r = max(1.0, (2.5 - CGFloat(ring) * 0.25) * CGFloat(wobble) * size.width / 240)
                            let tone = lightOnDark ? Color.white : Color.black
                            context.fill(Path(ellipseIn: CGRect(x: x-r, y: y-r, width: r*2, height: r*2)),
                                         with: .color(tone.opacity((ring == 0 ? 0.82 : 0.48) * fade)))
                        }
                    }

                    if case .assembling = mode {
                        for index in services.indices {
                            let angle = Double(index) * 2 * .pi / Double(count) - .pi / 2
                            let radius = outerRadius * CGFloat(1 - merge)
                            let origin = CGPoint(x: center.x + radius * CGFloat(cos(angle)),
                                                 y: center.y + radius * CGFloat(sin(angle)))
                            var line = Path()
                            line.move(to: origin)
                            line.addLine(to: center)
                            context.stroke(line, with: .color(foreground.opacity(merge * (1 - completed) * 0.19)), lineWidth: 1)
                        }
                    }
                }

                if mode == .showcase && !reduceMotion && !services.isEmpty {
                    let angle = Double(tick % 24) * 2 * .pi / 24 + orbitTime * 2 * .pi / max(3, rotationDuration)
                    let radius = diameter * 0.39
                    let bubble = CGFloat(max(5.0, 28.0 * expansion)) * diameter / 240
                    Circle()
                        .fill(foreground)
                        .frame(width: bubble * 2, height: bubble * 2)
                        .overlay {
                            Image(systemName: services[tick % count].symbol)
                                .font(.system(size: bubble * 0.95, weight: .semibold))
                                .foregroundStyle(background)
                                .opacity(smoothStep((revealPhase - 0.16) / 0.18) *
                                         (1 - smoothStep((revealPhase - 0.72) / 0.18)))
                        }
                        .position(x: diameter / 2 + radius * CGFloat(cos(angle)),
                                  y: diameter / 2 + radius * CGFloat(sin(angle)))
                        .accessibilityHidden(true)
                }

                if case .progress = mode, !services.isEmpty {
                    ForEach(services.indices, id: \.self) { index in
                        let item = services[index]
                        let count = max(1, services.count)
                        let angle = Double(index) * 2 * .pi / Double(count) - .pi / 2
                        let radius = diameter * 0.39
                        let isCurrent = index == progress.active
                        let isDone = index < progress.completed
                        Circle()
                            .fill(isCurrent ? foreground : (isDone ? foreground.opacity(0.75) : muted))
                            .frame(width: isCurrent ? 40 : 27, height: isCurrent ? 40 : 27)
                            .overlay {
                                Image(systemName: isDone ? "checkmark" : item.symbol)
                                    .font(.system(size: isCurrent ? 16 : 11, weight: .bold))
                                    .foregroundStyle(background)
                            }
                            .position(x: diameter / 2 + radius * CGFloat(cos(angle)),
                                      y: diameter / 2 + radius * CGFloat(sin(angle)))
                            .accessibilityLabel(item.id)
                    }
                }

                if case .assembling = mode {
                    ForEach(services.indices, id: \.self) { index in
                        let item = services[index]
                        let angle = Double(index) * 2 * .pi / Double(count) - .pi / 2
                        let radius = diameter * 0.39 * CGFloat(1 - merge)
                        Circle()
                            .fill(foreground)
                            .frame(width: CGFloat(31 * (1 - completed)), height: CGFloat(31 * (1 - completed)))
                            .overlay {
                                Image(systemName: item.symbol)
                                    .font(.system(size: CGFloat(13 * (1 - completed)), weight: .semibold))
                                    .foregroundStyle(background)
                            }
                            .opacity(1 - completed)
                            .position(x: diameter / 2 + radius * CGFloat(cos(angle)),
                                      y: diameter / 2 + radius * CGFloat(sin(angle)))
                            .accessibilityHidden(true)
                    }
                }

                RoundedRectangle(cornerRadius: diameter * 0.12, style: .continuous)
                    .fill(background)
                    .frame(width: diameter * 0.39, height: diameter * 0.39)
                    .overlay {
                        RoundedRectangle(cornerRadius: diameter * 0.12, style: .continuous)
                            .strokeBorder(foreground.opacity(0.22), lineWidth: 1.2)
                    }
                    .shadow(color: foreground.opacity(0.10), radius: 16)
                    .overlay {
                        ZStack {
                            Text("iumrah")
                                .font(.system(size: diameter * 0.096, weight: .bold, design: .rounded))
                                .tracking(-0.65)
                                .foregroundStyle(foreground)
                                .opacity(mode == .assembling ? 1 - completed : 1)
                            if case .assembling = mode {
                                Image(systemName: "checkmark")
                                    .font(.system(size: diameter * 0.14, weight: .bold))
                                    .foregroundStyle(foreground)
                                    .opacity(completed)
                            }
                        }
                    }
                    .accessibilityHidden(true)
            }
            .frame(width: diameter, height: diameter)
        }
        .frame(width: diameter, height: diameter)
        .onAppear { assemblyStart = Date() }
        .onChange(of: mode) { _, newValue in
            if case .assembling = newValue { assemblyStart = Date() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle)
    }

    private var modeProgress: (completed: Int, active: Int) {
        if case let .progress(completed, active) = mode { return (completed, active) }
        return (0, 0)
    }

    private var accessibilityTitle: String {
        switch mode {
        case .showcase: return "iumrah services: flights, hotels, transfers and more"
        case .progress(let completed, _): return "Package configuration, \(completed) stages completed"
        case .assembling: return "Selected services combined into one Umrah package. Booking not yet confirmed."
        }
    }

    private func smoothStep(_ input: Double) -> Double {
        let t = min(1, max(0, input))
        return t * t * (3 - 2 * t)
    }
}
