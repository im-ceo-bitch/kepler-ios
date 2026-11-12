import Foundation
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}
let p = IumrahHemisphereProjection.arabia
let center = p.point(latitude: 25, longitude: 48)!
check(abs(center.x - 0.5) < 1e-12 && abs(center.y - 0.5) < 1e-12, "center")
check(p.point(latitude: -25, longitude: -132) == nil, "antipode")
check(p.point(latitude: 41.2579, longitude: 69.2812)!.x > p.point(latitude: 21.6702, longitude: 39.1525)!.x, "TAS east of JED")
check(p.point(latitude: .nan, longitude: 0) == nil, "invalid")
let triangles = IumrahHemisphereLandData.triangles
check(triangles.count == 16905, "mesh decode")
for projection in [p, .init(latitude: 0, longitude: 0), .init(latitude: 89, longitude: 179), .init(latitude: -75, longitude: -110)] {
    let polygons = triangles.map(projection.visiblePolygon).filter { !$0.isEmpty }
    check(polygons.count > 1000, "visible land")
    for polygon in polygons {
        check(polygon.count == 3 || polygon.count == 4, "clipped polygon count")
        check(polygon.allSatisfy { hypot($0.x - 0.5, $0.y - 0.5) <= 0.50000001 }, "inside disk")
    }
    print("PASS center \(projection.latitude), \(projection.longitude): \(polygons.count) visible polygons")
}
print("PASS decoded triangles, projection, horizon clipping, geographic placement and invalid coordinates")
