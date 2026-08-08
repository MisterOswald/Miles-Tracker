import CoreLocation
import Foundation

enum Geo {
    static let metersPerMile = 1609.344

    /// Haversine distance between two coordinates in meters.
    static func haversineMeters(
        lat1: Double, lng1: Double, lat2: Double, lng2: Double
    ) -> Double {
        let r = 6_371_000.0
        let φ1 = lat1 * .pi / 180
        let φ2 = lat2 * .pi / 180
        let dφ = (lat2 - lat1) * .pi / 180
        let dλ = (lng2 - lng1) * .pi / 180
        let a = sin(dφ / 2) * sin(dφ / 2)
            + cos(φ1) * cos(φ2) * sin(dλ / 2) * sin(dλ / 2)
        return r * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    /// Total route distance in miles, summing haversine segments and skipping
    /// GPS glitches (segments implying > 60 m/s ≈ 134 mph).
    static func routeMiles(points: [DrivePoint]) -> Double {
        guard points.count > 1 else { return 0 }
        var meters = 0.0
        for i in 1..<points.count {
            let a = points[i - 1]
            let b = points[i]
            let d = haversineMeters(
                lat1: a.latitude, lng1: a.longitude,
                lat2: b.latitude, lng2: b.longitude
            )
            let dt = b.timestamp.timeIntervalSince(a.timestamp)
            if dt > 0, d / dt > 60 { continue }
            meters += d
        }
        return meters / metersPerMile
    }
}
