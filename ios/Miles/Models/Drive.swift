import Foundation
import SwiftData

enum DriveCategory: String, Codable, CaseIterable {
    case unclassified
    case business
    case personal

    var displayName: String {
        switch self {
        case .unclassified: return "Unclassified"
        case .business: return "Business"
        case .personal: return "Personal"
        }
    }
}

enum DriveSource: String, Codable {
    case auto
    case manual
    case merged
}

@Model
final class Drive {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var endedAt: Date
    var distanceMiles: Double
    var startLatitude: Double?
    var startLongitude: Double?
    var endLatitude: Double?
    var endLongitude: Double?
    var startAddress: String
    var endAddress: String
    var categoryRaw: String
    var purposeNote: String
    /// IRS rate snapshotted from the drive's year (decimal cents, e.g. 72.5).
    var rateCentsPerMile: Double
    /// Google-encoded polyline of the recorded route.
    var encodedPolyline: String
    var sourceRaw: String
    var updatedAt: Date
    /// Soft delete so deletions propagate through sync.
    var deletedAt: Date?
    /// True when this drive has local changes not yet pushed to the server.
    var needsSync: Bool

    var category: DriveCategory {
        get { DriveCategory(rawValue: categoryRaw) ?? .unclassified }
        set { categoryRaw = newValue.rawValue }
    }

    var source: DriveSource {
        get { DriveSource(rawValue: sourceRaw) ?? .auto }
        set { sourceRaw = newValue.rawValue }
    }

    var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }

    var deductionDollars: Double {
        guard category == .business else { return 0 }
        return distanceMiles * rateCentsPerMile / 100.0
    }

    init(
        id: UUID = UUID(),
        startedAt: Date,
        endedAt: Date,
        distanceMiles: Double,
        startLatitude: Double? = nil,
        startLongitude: Double? = nil,
        endLatitude: Double? = nil,
        endLongitude: Double? = nil,
        startAddress: String = "",
        endAddress: String = "",
        category: DriveCategory = .unclassified,
        purposeNote: String = "",
        rateCentsPerMile: Double = 0,
        encodedPolyline: String = "",
        source: DriveSource = .auto,
        updatedAt: Date = Date(),
        deletedAt: Date? = nil,
        needsSync: Bool = true
    ) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.distanceMiles = distanceMiles
        self.startLatitude = startLatitude
        self.startLongitude = startLongitude
        self.endLatitude = endLatitude
        self.endLongitude = endLongitude
        self.startAddress = startAddress
        self.endAddress = endAddress
        self.categoryRaw = category.rawValue
        self.purposeNote = purposeNote
        self.rateCentsPerMile = rateCentsPerMile
        self.encodedPolyline = encodedPolyline
        self.sourceRaw = source.rawValue
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.needsSync = needsSync
    }

    /// Marks a local edit: bumps updatedAt and flags the drive for sync.
    func touch() {
        updatedAt = Date()
        needsSync = true
    }
}
