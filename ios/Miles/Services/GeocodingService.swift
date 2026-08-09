import CoreLocation
import Foundation

/// Reverse geocoding via CLGeocoder — free, no API key. Results are cached
/// coarsely (~100 m grid) since drives often start/end at the same places.
/// An actor so cache access is async-safe without manual locking.
actor GeocodingService {
    private var cache: [String: String] = [:]

    func reverseGeocode(latitude: Double, longitude: Double) async -> String {
        let key = String(format: "%.3f,%.3f", latitude, longitude)
        if let cached = cache[key] {
            return cached
        }

        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: latitude, longitude: longitude)
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let placemark = placemarks.first else { return "" }
            let address = Self.format(placemark)
            cache[key] = address
            return address
        } catch {
            // Offline or rate-limited — the drive is still saved; the address
            // just stays empty and can be filled in by hand.
            NSLog("Miles: reverse geocode failed: \(error.localizedDescription)")
            return ""
        }
    }

    private static func format(_ placemark: CLPlacemark) -> String {
        var street = ""
        if let number = placemark.subThoroughfare, let road = placemark.thoroughfare {
            street = "\(number) \(road)"
        } else if let road = placemark.thoroughfare {
            street = road
        } else if let name = placemark.name {
            street = name
        }
        let city = placemark.locality ?? placemark.subAdministrativeArea ?? ""
        switch (street.isEmpty, city.isEmpty) {
        case (false, false): return "\(street), \(city)"
        case (false, true): return street
        case (true, false): return city
        case (true, true): return ""
        }
    }
}
