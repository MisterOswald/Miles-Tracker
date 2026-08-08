import CoreLocation
import Foundation
import SwiftData

/// A named place (e.g. "Home", "Warehouse") used for auto-classification.
/// A drive that starts or ends within `radiusMeters` of a location with a
/// category rule is tagged automatically.
@Model
final class NamedLocation {
    @Attribute(.unique) var id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    var radiusMeters: Double
    /// nil means "label only, no auto-classification".
    var autoCategoryRaw: String?

    var autoCategory: DriveCategory? {
        get { autoCategoryRaw.flatMap(DriveCategory.init(rawValue:)) }
        set { autoCategoryRaw = newValue?.rawValue }
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(
        id: UUID = UUID(),
        name: String,
        latitude: Double,
        longitude: Double,
        radiusMeters: Double = 150,
        autoCategory: DriveCategory? = nil
    ) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.radiusMeters = radiusMeters
        self.autoCategoryRaw = autoCategory?.rawValue
    }

    func contains(latitude lat: Double, longitude lng: Double) -> Bool {
        let here = CLLocation(latitude: latitude, longitude: longitude)
        let there = CLLocation(latitude: lat, longitude: lng)
        return here.distance(from: there) <= radiusMeters
    }
}
