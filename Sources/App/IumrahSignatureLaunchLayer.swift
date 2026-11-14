import SwiftUI

/// Native one-shot monochrome launch. The geographic dot cloud is precomputed
/// from the same Natural Earth data used by the flight detail globe.
struct IumrahSignatureLaunchLayer: View {
    let startDate: Date?
    let reduceMotion: Bool
    let handoffToHeader: Bool
    let topInset: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: startDate == nil)) { timeline in
            let time = max(0, min(IumrahLaunchGeometry.duration, startDate.map { timeline.date.timeIntervalSince($0) } ?? 0))
            GeometryReader { proxy in
                let w = proxy.size.width, h = proxy.size.height
                if reduceMotion {
                    ZStack {
                        Color("LaunchBackground")
                        wordmark.frame(width: min(220, w * 0.62), height: 90)
                    }
                    .opacity(1 - IumrahLaunchGeometry.stage(time, 0.04, 0.18))
                } else {
                    scene(time: time, width: w, height: h)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private var wordmark: some View {
        Image("HeaderWordmarkLight")
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .foregroundStyle(.white)
    }

    private func scene(time: Double, width: CGFloat, height: CGFloat) -> some View {
        let emergence = IumrahLaunchGeometry.stage(time, 0.06, 0.43)
        let reveal = IumrahLaunchGeometry.stage(time, 0.74, 0.88)
        let handoff = handoffToHeader ? IumrahLaunchGeometry.stage(time, 0.87, 1.12) : 0
        let fade = IumrahLaunchGeometry.stage(time, IumrahLaunchGeometry.fadeStart, IumrahLaunchGeometry.duration)
        let diameter = min(width * 0.80, height * 0.49, 390)
        let headerCenter = topInset + IumrahSignatureHeaderGeometry.topInset + IumrahSignatureHeaderGeometry.logoHeight / 2
        let y = height * 0.48 + (headerCenter - height * 0.48) * CGFloat(handoff)
        let logoWidth = min(width * 0.66, 248)
        let targetWidth = min(IumrahSignatureHeaderGeometry.logoWidth, max(90, width - 2 * IumrahDesign.pagePadding - 184))
        let logoFrameWidth = logoWidth + (targetWidth - logoWidth) * CGFloat(handoff)
        let logoFrameHeight: CGFloat = 82 + (IumrahSignatureHeaderGeometry.logoHeight - 82) * CGFloat(handoff)
        return ZStack {
            Color("LaunchBackground")
                .opacity(1 - fade)
            // The first pulse expands from a single white point.
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let ring = IumrahLaunchGeometry.stage(time, 0.01, 0.25)
                let opacity = 1 - IumrahLaunchGeometry.stage(time, 0.12, 0.30)
                for index in 0..<2 {
                    let radius = CGFloat(5 + ring * Double(20 + index * 14))
                    context.stroke(Path(ellipseIn: CGRect(x: center.x-radius, y: center.y-radius, width: radius*2, height: radius*2)),
                                   with: .color(.white.opacity(opacity * (index == 0 ? 0.24 : 0.12))), lineWidth: 0.8)
                }
                context.fill(Path(ellipseIn: CGRect(x: center.x-2.5, y: center.y-2.5, width: 5, height: 5)), with: .color(.white.opacity(opacity)))
            }
            .frame(width: 88, height: 88)
            .position(x: width / 2, y: height * 0.48)

            IumrahSignatureLaunchGlobe(time: time)
                .frame(width: diameter, height: diameter)
                .scaleEffect(CGFloat(0.06 + 0.94 * emergence))
                .opacity(emergence * (1 - 0.82 * reveal) * (1 - handoff) * (1 - fade))
                .position(x: width / 2, y: height * 0.48 + (headerCenter - height * 0.48) * CGFloat(handoff))

            // Cross-fade to the actual atlas texture used by the Home masthead.
            // This is not a second loading screen; the root takes over at 1.2 s.
            if handoffToHeader, handoff > 0 {
                let mapWidth = min(max(width * 0.94, 300), 920)
                let headerHeight = IumrahSignatureHeaderGeometry.contentHeight + 52
                IumrahWorldDotsMap(isAnimating: false, waveIntensity: 0, opacity: 0.33)
                    .frame(width: mapWidth, height: mapWidth / 2)
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .white.opacity(0.32), location: 0.25), .init(color: .white, location: 0.61), .init(color: .white, location: 1)], startPoint: .leading, endPoint: .trailing))
                    .position(x: width * 0.57, y: topInset + headerHeight * 0.50)
                    .opacity(handoff * (1 - fade))
            }
            wordmark
                .frame(width: logoFrameWidth, height: logoFrameHeight)
                .position(x: width / 2, y: y)
                .opacity(reveal * (1 - fade))
        }
    }
}

private struct IumrahSignatureLaunchGlobe: View {
    let time: Double

    var body: some View {
        Canvas { context, size in
            let d = min(size.width, size.height)
            guard d > 0 else { return }
            let rect = CGRect(x: (size.width-d)/2, y: (size.height-d)/2, width: d, height: d)
            let projection = IumrahLaunchGeometry.projection(at: time)
            let wave = IumrahLaunchGeometry.stage(time, 0.13, 0.83)
            let dim = IumrahLaunchGeometry.stage(time, 0.73, 0.89)
            // Six batched paths: no per-dot SwiftUI views or per-frame land mesh.
            var bands = Array(repeating: Path(), count: 6)
            for vector in IumrahLaunchLandDots.vectors {
                let p = projection.project(vector)
                guard p.depth > 0 else { continue }
                let light = exp(-pow((p.x - (-1.1 + 2.2 * wave)) * 2.6, 2))
                let brightness = IumrahLaunchGeometry.clamp(0.22 + p.depth * 0.42 + light * 0.35)
                let band = min(5, Int(brightness * 6))
                let radius = max(0.38, d * 0.0032 * CGFloat(0.58 + p.depth * 0.42))
                let x = rect.minX + p.point.x * d, y = rect.minY + p.point.y * d
                bands[band].addEllipse(in: CGRect(x: x-radius, y: y-radius, width: radius*2, height: radius*2))
            }
            context.fill(Path(ellipseIn: rect), with: .radialGradient(Gradient(colors: [Color(white: 0.09), Color(white: 0.02)]), center: CGPoint(x: rect.midX, y: rect.midY), startRadius: 0, endRadius: d/2))
            context.stroke(Path(ellipseIn: rect.insetBy(dx: 0.5, dy: 0.5)), with: .color(.white.opacity(0.09)), lineWidth: 0.8)
            for (index, path) in bands.enumerated() {
                context.fill(path, with: .color(.white.opacity((0.15 + Double(index) * 0.15) * (1 - 0.42 * dim))))
            }
            let progress = IumrahLaunchGeometry.stage(time, 0.25, 0.73)
            guard progress > 0 else { return }
            let points = IumrahLaunchGeometry.route.map { vector -> CGPoint in
                let p = projection.project(vector).point
                return CGPoint(x: rect.minX+p.x*d, y: rect.minY+p.y*d)
            }
            guard let first = points.first, let last = points.last else { return }
            let position = progress * Double(points.count - 1)
            let index = min(points.count - 2, Int(position))
            let fraction = CGFloat(position - Double(index))
            let a = points[index], b = points[index+1]
            let tip = CGPoint(x: a.x + (b.x-a.x)*fraction, y: a.y+(b.y-a.y)*fraction)
            var line = Path(); line.move(to: first)
            for point in points.dropFirst().prefix(index) { line.addLine(to: point) }
            line.addLine(to: tip)
            let routeOpacity = 1 - IumrahLaunchGeometry.stage(time, 0.73, 0.85)
            context.stroke(line, with: .color(.white.opacity(routeOpacity * 0.9)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [3, 3]))
            for point in [first, last] {
                context.fill(Path(ellipseIn: CGRect(x: point.x-2.8, y: point.y-2.8, width: 5.6, height: 5.6)), with: .color(.white.opacity(routeOpacity)))
            }
            // SF Symbols airplane points right; rotate along the projected tangent.
            var plane = context
            plane.opacity = routeOpacity
            plane.translateBy(x: tip.x, y: tip.y)
            plane.rotate(by: .radians(atan2(Double(b.y-a.y), Double(b.x-a.x))))
            plane.draw(Text(Image(systemName: "airplane")).font(.system(size: 15, weight: .semibold)).foregroundColor(.white), at: .zero)
        }
        .accessibilityHidden(true)
    }
}
