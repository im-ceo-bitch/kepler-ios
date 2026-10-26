import SwiftUI

/// Video-matched connectivity indicator used in the Home header.
///
/// Visual cycle (reference timing):
/// 1. compact globe + fast multicolor orbit,
/// 2. morph into a black capsule,
/// 3. reveal Online / Offline while the illuminated border keeps travelling,
/// 4. collapse back to the compact globe and repeat.
///
/// The network state remains driven by `IumrahConnectivityMonitor`; this view is
/// presentation-only and never changes connectivity behaviour.
struct IumrahAnimatedConnectivityIndicator: View {
    @EnvironmentObject private var settings: AppSettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var connectivity = IumrahConnectivityMonitor()

    var lightStyle = false

    @State private var isExpanded = false

    private let compactWidth: CGFloat = 34
    private let expandedWidth: CGFloat = 88
    private let height: CGFloat = 34

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            indicator(at: context.date)
        }
        .frame(width: expandedWidth, height: height, alignment: .trailing)
        .task(id: connectivity.status) {
            await runPresentationCycle(for: connectivity.status)
        }
        .task {
            // Preserve the existing reachability behaviour. The animated control
            // only changes presentation, not the network source of truth.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { break }
                await connectivity.refresh()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(localizedConnectionPrefix): \(localizedConnectivityStatus)")
    }

    private var localizedConnectivityStatus: String {
        switch connectivity.status {
        case .checking:
            return IumrahAccessibilityCopy.text(settings.language, ru: "Проверка", en: "Checking", uz: "Tekshirilmoqda", cy: "Текширилмоқда", tr: "Kontrol ediliyor", id: "Memeriksa")
        case .online:
            return IumrahAccessibilityCopy.text(settings.language, ru: "В сети", en: "Online", uz: "Onlayn", cy: "Онлайн", tr: "Çevrimiçi", id: "Online")
        case .offline:
            return IumrahAccessibilityCopy.text(settings.language, ru: "Не в сети", en: "Offline", uz: "Oflayn", cy: "Офлайн", tr: "Çevrimdışı", id: "Offline")
        }
    }

    private var localizedConnectionPrefix: String {
        IumrahAccessibilityCopy.text(settings.language, ru: "Интернет-соединение", en: "Internet connection", uz: "Internet aloqasi", cy: "Интернет алоқаси", tr: "İnternet bağlantısı", id: "Koneksi internet")
    }

    @ViewBuilder
    private func indicator(at date: Date) -> some View {
        let width = isExpanded ? expandedWidth : compactWidth
        let rotation = borderRotation(at: date)

        ZStack {
            // Soft moving halo visible in the reference around the bright rail.
            Capsule(style: .continuous)
                .stroke(borderGradient(rotation: rotation), lineWidth: isExpanded ? 4.8 : 4.2)
                .blur(radius: isExpanded ? 4.2 : 3.4)
                .opacity(isExpanded ? 0.34 : 0.42)

            Capsule(style: .continuous)
                .fill(Color.black.opacity(0.985))

            Capsule(style: .continuous)
                .strokeBorder(borderGradient(rotation: rotation), lineWidth: 2.15)

            HStack(spacing: 5) {
                Text(localizedConnectivityStatus)
                    .font(.system(size: 11.5, weight: .bold, design: .serif))
                    .italic()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
                    .frame(width: isExpanded ? 40 : 0, alignment: .leading)
                    .opacity(isExpanded ? 1 : 0)
                    .offset(x: isExpanded ? 0 : 7)
                    .clipped()

                Spacer(minLength: 0)

                Image(systemName: "globe")
                    .font(.system(size: 18.5, weight: .bold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
            }
            .padding(.leading, isExpanded ? 10 : 7)
            .padding(.trailing, isExpanded ? 7 : 7)
        }
        .frame(width: width, height: height)
        .shadow(color: haloColor.opacity(isExpanded ? 0.18 : 0.12), radius: 6, y: 2)
        .animation(morphAnimation, value: isExpanded)
    }

    private var morphAnimation: Animation {
        // The reference reaches the full capsule in roughly four tenths of a
        // second with a soft spring and no visible hard stop.
        .spring(response: 0.42, dampingFraction: 0.82, blendDuration: 0.08)
    }

    @MainActor
    private func runPresentationCycle(for status: IumrahConnectivityStatus) async {
        isExpanded = false

        guard !reduceMotion else {
            isExpanded = status != .checking
            return
        }

        // While probing we intentionally stay as the compact spinning globe.
        // A real result restarts this task and begins the reference reveal cycle.
        guard status != .checking else { return }

        while !Task.isCancelled {
            // Compact orbit section from the reference clip.
            try? await Task.sleep(nanoseconds: 1_650_000_000)
            guard !Task.isCancelled else { break }

            withAnimation(morphAnimation) {
                isExpanded = true
            }

            // Full Online / Offline capsule remains readable while the highlight
            // continues to orbit around the rail.
            try? await Task.sleep(nanoseconds: 3_650_000_000)
            guard !Task.isCancelled else { break }

            withAnimation(morphAnimation) {
                isExpanded = false
            }

            // Small compact beat before the next cycle, matching the clip.
            try? await Task.sleep(nanoseconds: 620_000_000)
            guard !Task.isCancelled else { break }
        }
    }

    private func borderRotation(at date: Date) -> Double {
        guard !reduceMotion else { return 18 }
        // The bright rail completes a pass in ~1.55 s in the supplied reference.
        let cycle = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.55)
        return (cycle / 1.55) * 360
    }

    private func borderGradient(rotation: Double) -> AngularGradient {
        AngularGradient(
            gradient: gradient,
            center: .center,
            startAngle: .degrees(rotation),
            endAngle: .degrees(rotation + 360)
        )
    }

    private var gradient: Gradient {
        Gradient(stops: [
            .init(color: .white.opacity(0.55), location: 0.0),
            .init(color: .white.opacity(0.98), location: 0.20),
            .init(color: Color(white: 0.40), location: 0.47),
            .init(color: Color(white: 0.18), location: 0.65),
            .init(color: .white.opacity(0.86), location: 0.86),
            .init(color: .white.opacity(0.55), location: 1.0)
        ])
    }

    private var haloColor: Color { .white }

}

/// Compatibility wrapper for any older call sites. New Home headers use the
/// dedicated animated component directly.
struct ConnectivityStatusPill: View {
    var lightStyle = false

    var body: some View {
        IumrahAnimatedConnectivityIndicator(lightStyle: lightStyle)
    }
}
