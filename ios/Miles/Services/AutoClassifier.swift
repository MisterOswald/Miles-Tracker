import Foundation
import SwiftData

/// Applies auto-classification rules to a freshly detected drive:
/// 1. Named-location rules — if the drive ends (checked first) or starts at a
///    named place with a category rule, use it.
/// 2. Work-hours rule — drives starting Mon–Fri inside the configured window
///    default to Business.
/// Otherwise the drive stays unclassified for a manual swipe.
enum AutoClassifier {
    struct Result {
        let category: DriveCategory
        let note: String
    }

    @MainActor
    static func classify(
        startLat: Double, startLng: Double,
        endLat: Double, endLng: Double,
        startedAt: Date,
        context: ModelContext
    ) -> Result {
        let locations = (try? context.fetch(FetchDescriptor<NamedLocation>())) ?? []

        // Destination is the stronger signal; check it before origin.
        for place in locations where place.autoCategory != nil {
            if place.contains(latitude: endLat, longitude: endLng) {
                return Result(
                    category: place.autoCategory!,
                    note: "Auto: arrived at \(place.name)"
                )
            }
        }
        for place in locations where place.autoCategory != nil {
            if place.contains(latitude: startLat, longitude: startLng) {
                return Result(
                    category: place.autoCategory!,
                    note: "Auto: left from \(place.name)"
                )
            }
        }

        if AppSettings.workHoursRuleEnabled, isWithinWorkHours(startedAt) {
            return Result(category: .business, note: "Auto: work hours")
        }

        return Result(category: .unclassified, note: "")
    }

    static func isWithinWorkHours(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        // 1 = Sunday, 7 = Saturday
        guard (2...6).contains(weekday) else { return false }
        let minutes = calendar.component(.hour, from: date) * 60
            + calendar.component(.minute, from: date)
        return minutes >= AppSettings.workHoursStartMinutes
            && minutes < AppSettings.workHoursEndMinutes
    }
}
