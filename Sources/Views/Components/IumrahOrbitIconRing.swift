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
    var services: [IumrahOrbitService] = IumrahOrbitService.showcase
    var diameter: CGFloat = 240
    var isActive: Bool = true
    var lightOnDark: Bool = true
    var rotationDuration: TimeInterval = IumrahFoundation.Motion.orbitRevolution
    var revealDuration: TimeInterval = IumrahFoundation.Motion.orbitReveal

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
            // Hold the enlarged service long enough for the icon to be recognised.
            // 0..0.24 expansion; 0.24..0.73 hold; 0.73..1 contraction.
            let expansion = smoothStep(revealPhase / 0.24) *
                (1 - smoothStep((revealPhase - 0.73) / 0.27))
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
                            if ring == 0 && mode == .showcase && dot == tick % 24 { continue }
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

                if mode == .showcase && !services.isEmpty {
                    let angle = Double(tick % 24) * 2 * .pi / 24 + orbitTime * 2 * .pi / max(3, rotationDuration)
                    let radius = diameter * 0.39
                    // The point is ~7pt at rest and up to ~68pt when active (240pt ring).
                    let bubble = CGFloat(3.5 + 30.5 * (reduceMotion ? 1 : expansion)) * diameter / 240
                    Circle()
                        .fill(foreground)
                        .frame(width: bubble * 2, height: bubble * 2)
                        .overlay {
                            Image(systemName: services[tick % count].symbol)
                                .font(.system(size: bubble * 0.95, weight: .semibold))
                                .foregroundStyle(background)
                                .opacity((reduceMotion ? 1 : smoothStep((revealPhase - 0.13) / 0.17) *
                                         (1 - smoothStep((revealPhase - 0.78) / 0.18))))
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


// MARK: - Production journey assembly

extension IumrahOrbitService {
    /// Only include services selected in the real JourneyStore. This is a visual
    /// summary, not a booking/quote confirmation or an inventory guarantee.
    @MainActor
    static func selectedForJourney(_ journey: JourneyStore) -> [IumrahOrbitService] {
        var result: [IumrahOrbitService] = []
        if journey.selectedOutbound != nil || journey.selectedInbound != nil ||
            !journey.localJourneyFlights.isEmpty || !journey.stagedUmrahFlights.isEmpty {
            result.append(.init(id: "flight", symbol: "airplane"))
        }
        if journey.selectedHotel != nil || journey.selectedMadinahHotel != nil ||
            !journey.localJourneyRooms.isEmpty {
            result.append(.init(id: "hotel", symbol: "building.2.fill"))
        }
        if journey.transferSelectionConfirmed {
            result.append(.init(id: "transfer", symbol: "car.side.fill"))
        }
        if journey.haramainTrainSelected {
            result.append(.init(id: "train", symbol: "tram.fill"))
        }
        return result
    }
}

struct IumrahOrbitPackageAssemblyCard: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let services: [IumrahOrbitService]

    private func copy(_ ru: String, _ en: String, _ uz: String, _ uzc: String) -> String {
        switch settings.language {
        case .russian: return ru
        case .uzbek: return uz
        case .uzbekCyrillic: return uzc
        default: return en
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            IumrahOrbitIconRing(
                mode: reduceMotion ? .progress(completed: services.count, active: 0) : .assembling,
                services: services,
                diameter: 205,
                lightOnDark: true
            )
            .frame(height: 215)
            .accessibilityIdentifier("iumrah.orbit.package.assembly")

            Text(copy("Всё объединяется в один пакет", "Everything becomes one package", "Barcha xizmatlar bitta paketda", "Барча хизматлар битта пакетда"))
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            Text(copy("Ваши выбранные услуги · бронирование ещё не создано", "Your selected services · booking not created yet", "Tanlangan xizmatlaringiz · bron hali yaratilmagan", "Танланган хизматларингиз · брон ҳали яратилмаган"))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.63))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 12)
        .background(Color(red: 0.034, green: 0.034, blue: 0.044), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}
