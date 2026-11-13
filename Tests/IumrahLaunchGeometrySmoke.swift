import Foundation

@main
struct IumrahLaunchGeometrySmoke {
    static func main() {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            guard condition() else { fatalError(name) }
            checks += 1
            print("PASS \(name)")
        }
        typealias G = IumrahLaunchGeometry
        let dots = IumrahLaunchLandDots.vectors
        check(dots.count == IumrahLaunchLandDots.count && dots.count > 5000, "complete geographic dot data")
        check(dots.allSatisfy { abs($0.dot($0) - 1) < 1e-10 }, "all dots lie on unit sphere")
        check(G.duration == 1.2, "1.2 second animation target")
        check(G.firstPulse < G.secondPulse && G.secondPulse < G.mountContent && G.mountContent < G.fadeStart && G.fadeStart < G.duration, "haptic and mount timeline ordering")
        check(G.stage(-1, 0.2, 0.7) == 0 && G.stage(1, 0.2, 0.7) == 1, "bounded easing")
        check(abs(G.stage(0.45, 0.2, 0.7) - 0.5) < 1e-10, "smooth midpoint")
        check(G.projection(at: 0).longitude == 81 && G.projection(at: 1.2).longitude == 48, "real rotation")
        check(G.route.count == 49, "great-circle route sample count")
        check(G.route.allSatisfy { abs($0.dot($0)-1) < 1e-10 }, "route on unit sphere")
        let tas = IumrahHemisphereProjection.Vector(latitude: 41.2579, longitude: 69.2812)
        let jed = IumrahHemisphereProjection.Vector(latitude: 21.6796, longitude: 39.1565)
        check(G.route.first!.dot(tas) > 0.9999999 && G.route.last!.dot(jed) > 0.9999999, "TAS/JED endpoints")
        let frames = (0...36).map { G.projection(at: Double($0)/30) }
        check(frames.allSatisfy { projection in G.route.allSatisfy { projection.project($0).depth > 0 } }, "route visible during all frames")
        check(frames.allSatisfy { projection in dots.filter { projection.project($0).depth > 0 }.count > 2000 }, "visible land dot coverage")
        print("\(checks)/\(checks) launch checks passed")
    }
}
