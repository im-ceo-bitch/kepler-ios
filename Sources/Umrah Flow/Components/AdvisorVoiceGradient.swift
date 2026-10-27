import SwiftUI

/// Full-width, bottom-anchored voice aura for iumrah Advisor.
///
/// Feed `amplitude` with a normalized 0...1 audio level. The renderer keeps a
/// small idle motion, then raises the glow, spread and brightness as the level rises.
struct AdvisorVoiceGradient: View {
    var amplitude: CGFloat
    var isSpeaking: Bool = true
    var minimumHeight: CGFloat = 220
    var maximumHeightRatio: CGFloat = 0.58
    var bottomOverscan: CGFloat = 34

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var displayedAmplitude: CGFloat = 0

    private var palette: Palette {
        colorScheme == .dark ? .dark : .light
    }

    private var normalizedAmplitude: CGFloat {
        min(max(amplitude, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: isSpeaking ? 1.0 / 45.0 : 1.0 / 20.0, paused: reduceMotion)) { timeline in
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let width = proxy.size.width
                let fullHeight = proxy.size.height
                let energy = max(isSpeaking ? 0.10 : 0.045, displayedAmplitude)
                let auraHeight = min(
                    max(minimumHeight, fullHeight * (0.24 + 0.34 * energy)),
                    fullHeight * maximumHeightRatio
                )

                ZStack(alignment: .bottom) {
                    Color.clear

                    aura(width: width, height: auraHeight, energy: energy, time: time)
                        .frame(width: width, height: auraHeight + bottomOverscan)
                        .offset(y: bottomOverscan * 0.48)
                        .mask(
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0.00),
                                    .init(color: .black.opacity(0.08), location: 0.10),
                                    .init(color: .black.opacity(0.44), location: 0.28),
                                    .init(color: .black, location: 0.55),
                                    .init(color: .black, location: 1.00)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .opacity(isSpeaking ? 1 : 0.62)
                        .allowsHitTesting(false)
                }
                .frame(width: width, height: fullHeight, alignment: .bottom)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            displayedAmplitude = normalizedAmplitude
        }
        .onChange(of: normalizedAmplitude) { _, newValue in
            let duration = newValue >= displayedAmplitude ? 0.055 : 0.18
            withAnimation(.linear(duration: duration)) {
                displayedAmplitude = newValue
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func aura(width: CGFloat, height: CGFloat, energy: CGFloat, time: TimeInterval) -> some View {
        let horizontalTravel = width * (0.020 + 0.034 * energy)
        let verticalTravel = height * (0.018 + 0.030 * energy)
        let breathing = 1 + sin(time * 1.38) * (0.018 + 0.022 * energy)
        let lift = height * (0.02 + 0.11 * energy)
        let bloomOpacity = 0.58 + 0.40 * energy

        ZStack(alignment: .bottom) {
            // Soft monochrome anchor at the left edge.
            auraBlob(
                colors: palette.violet,
                width: width * (0.60 + 0.10 * energy),
                height: height * (0.66 + 0.08 * energy),
                blur: 36 + 16 * energy
            )
            .offset(
                x: -width * 0.32 + sin(time * 0.86 + 0.3) * horizontalTravel,
                y: height * 0.12 + cos(time * 0.74 + 1.2) * verticalTravel - lift * 0.16
            )
            .scaleEffect(x: breathing, y: 1.02 + 0.05 * energy, anchor: .bottom)

            // Center-left diffusion layer.
            auraBlob(
                colors: palette.magenta,
                width: width * (0.72 + 0.16 * energy),
                height: height * (0.62 + 0.15 * energy),
                blur: 42 + 18 * energy
            )
            .offset(
                x: -width * 0.08 + sin(time * 0.69 + 2.0) * horizontalTravel * 1.10,
                y: height * 0.15 + sin(time * 0.91 + 0.8) * verticalTravel - lift * 0.34
            )
            .scaleEffect(x: 1.02 + 0.05 * energy, y: breathing, anchor: .bottom)

            // Right lobe rises higher for spatial depth.
            auraBlob(
                colors: palette.orange,
                width: width * (0.70 + 0.18 * energy),
                height: height * (0.84 + 0.20 * energy),
                blur: 40 + 20 * energy
            )
            .offset(
                x: width * 0.30 + cos(time * 0.77 + 0.4) * horizontalTravel * 1.15,
                y: height * 0.06 + sin(time * 0.63 + 1.8) * verticalTravel - lift * 0.52
            )
            .scaleEffect(x: breathing, y: 1.02 + 0.10 * energy, anchor: .bottom)

            // Bridge prevents a hard seam between soft light fields.
            auraBlob(
                colors: palette.peach,
                width: width * (0.58 + 0.14 * energy),
                height: height * (0.56 + 0.18 * energy),
                blur: 34 + 16 * energy
            )
            .offset(
                x: width * 0.14 + sin(time * 1.02 + 4.1) * horizontalTravel * 0.72,
                y: height * 0.17 + cos(time * 0.82 + 2.6) * verticalTravel - lift * 0.25
            )

            // Focused core responds to the spoken amplitude.
            auraBlob(
                colors: palette.core,
                width: width * (0.86 + 0.12 * energy),
                height: height * (0.34 + 0.14 * energy),
                blur: 24 + 11 * energy
            )
            .offset(
                x: sin(time * 0.58 + 3.2) * horizontalTravel * 0.40,
                y: height * 0.28 - lift * 0.08
            )
            .opacity(0.78 + 0.22 * energy)

            // The bright horizontal base visible in the reference video.
            Capsule(style: .continuous)
                .fill(
                    LinearGradient(
                        colors: palette.baseBand,
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: width * 0.92, height: 38 + 32 * energy)
                .blur(radius: 14 + 9 * energy)
                .offset(y: 12)
                .opacity(0.74 + 0.24 * energy)

            // A second blurred veil makes the whole lower edge feel fluid instead of blob-like.
            LinearGradient(
                colors: palette.floorVeil,
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: height * (0.34 + 0.10 * energy))
            .blur(radius: 30 + 16 * energy)
            .offset(y: height * 0.13)
            .opacity(bloomOpacity)
        }
        .compositingGroup()
        .blendMode(colorScheme == .dark ? .plusLighter : .normal)
        .drawingGroup(opaque: false, colorMode: .extendedLinear)
    }

    private func auraBlob(
        colors: [Color],
        width: CGFloat,
        height: CGFloat,
        blur: CGFloat
    ) -> some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: colors,
                    center: .center,
                    startRadius: 0,
                    endRadius: max(width, height) * 0.48
                )
            )
            .frame(width: width, height: height)
            .blur(radius: blur)
    }
}

private extension AdvisorVoiceGradient {
    struct Palette {
        let violet: [Color]
        let magenta: [Color]
        let orange: [Color]
        let peach: [Color]
        let core: [Color]
        let baseBand: [Color]
        let floorVeil: [Color]

        // One monochrome system for Umrah Flow, including the voice visualizer.
        // The shape still follows measured audio amplitude for published clips.
        static let dark = Palette(
            violet: [.white.opacity(0.42), .white.opacity(0.15), .clear],
            magenta: [.white.opacity(0.37), .white.opacity(0.13), .clear],
            orange: [.white.opacity(0.48), .white.opacity(0.17), .clear],
            peach: [.white.opacity(0.27), .white.opacity(0.10), .clear],
            core: [.white.opacity(0.76), .white.opacity(0.34), .clear],
            baseBand: [.white.opacity(0.25), .white.opacity(0.68), .white.opacity(0.82), .white.opacity(0.25)],
            floorVeil: [.white.opacity(0.18), .white.opacity(0.24), .white.opacity(0.22)]
        )

        static let light = Palette(
            violet: [.black.opacity(0.23), .black.opacity(0.07), .clear],
            magenta: [.black.opacity(0.19), .black.opacity(0.06), .clear],
            orange: [.black.opacity(0.25), .black.opacity(0.08), .clear],
            peach: [.black.opacity(0.17), .black.opacity(0.05), .clear],
            core: [.white.opacity(0.92), .black.opacity(0.12), .clear],
            baseBand: [.black.opacity(0.12), .black.opacity(0.34), .black.opacity(0.38), .black.opacity(0.12)],
            floorVeil: [.black.opacity(0.08), .black.opacity(0.10), .black.opacity(0.09)]
        )
    }
}
