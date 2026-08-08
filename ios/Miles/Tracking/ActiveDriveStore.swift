import CoreLocation
import Foundation

/// A single recorded GPS sample during a drive.
struct DrivePoint: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    let speed: Double
    let horizontalAccuracy: Double

    init(location: CLLocation) {
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        timestamp = location.timestamp
        speed = max(location.speed, 0)
        horizontalAccuracy = location.horizontalAccuracy
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// In-progress drive state, persisted to disk so a drive survives the app
/// being suspended or killed mid-trip.
struct ActiveDriveState: Codable {
    var id: UUID
    var startedAt: Date
    var points: [DrivePoint]
    /// Last moment we saw movement (speed above the stationary threshold).
    var lastMovementAt: Date
    /// Last moment motion activity reported automotive.
    var lastAutomotiveAt: Date
}

/// Persists the active drive as JSON in Application Support. Writes are
/// atomic so a crash mid-write can't corrupt recovery state.
final class ActiveDriveStore {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.miles.activeDriveStore")

    init() {
        let dir = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        fileURL = dir.appendingPathComponent("active_drive.json")
    }

    func save(_ state: ActiveDriveState) {
        queue.async { [fileURL] in
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(state)
                try data.write(to: fileURL, options: .atomic)
            } catch {
                NSLog("Miles: failed to persist active drive: \(error)")
            }
        }
    }

    func load() -> ActiveDriveState? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ActiveDriveState.self, from: data)
    }

    func clear() {
        queue.async { [fileURL] in
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
}
