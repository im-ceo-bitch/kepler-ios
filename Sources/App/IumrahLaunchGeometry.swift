import Foundation

/// Pure timing and spherical geometry, shared with the offline smoke test.
enum IumrahLaunchGeometry {
    static let duration = 1.2
    static let firstPulse = 0.08
    static let secondPulse = 0.82
    static let mountContent = 0.84
    static let fadeStart = 0.98

    static func clamp(_ value: Double) -> Double { min(1, max(0, value)) }
    static func ease(_ value: Double) -> Double {
        let x = clamp(value)
        return x * x * (3 - 2 * x)
    }
    static func stage(_ time: Double, _ start: Double, _ end: Double) -> Double {
        ease((time - start) / (end - start))
    }
    static func projection(at time: Double) -> IumrahHemisphereProjection {
        let p = stage(time, 0.12, 0.86)
        return .init(latitude: 30 - 5 * p, longitude: 81 - 33 * p)
    }

    // Illustrative Tashkent → Jeddah route. Not a booking, not live tracking.
    private static let origin = IumrahHemisphereProjection.Vector(latitude: 41.2579, longitude: 69.2812)
    private static let destination = IumrahHemisphereProjection.Vector(latitude: 21.6796, longitude: 39.1565)
    static let route: [IumrahHemisphereProjection.Vector] = {
        let a = origin, b = destination
        let angle = acos(max(-1, min(1, a.dot(b))))
        let denominator = sin(angle)
        return (0...48).map { index in
            let t = Double(index) / 48
            let l = sin((1-t)*angle) / denominator, r = sin(t*angle) / denominator
            return .init(x: l*a.x+r*b.x, y: l*a.y+r*b.y, z: l*a.z+r*b.z)
        }
    }()
}
