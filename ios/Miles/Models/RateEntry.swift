import Foundation
import SwiftData

/// IRS standard mileage rate for a given year, in decimal cents per mile
/// (the IRS uses half-cent rates, e.g. 72.5¢ for 2026).
@Model
final class RateEntry {
    @Attribute(.unique) var year: Int
    var centsPerMile: Double

    init(year: Int, centsPerMile: Double) {
        self.year = year
        self.centsPerMile = centsPerMile
    }
}

enum DefaultRates {
    /// Known IRS standard business mileage rates. 2026 began at 72.5¢; the
    /// IRS raised it to 76¢ effective July 1, 2026 — edit the 2026 value in
    /// Settings to whichever single rate you want applied to that year.
    static let known: [Int: Double] = [
        2023: 65.5,
        2024: 67.0,
        2025: 70.0,
        2026: 72.5,
    ]

    static func rate(forYear year: Int) -> Double {
        if let exact = known[year] { return exact }
        // Fall back to the latest known rate for future years.
        return known.max(by: { $0.key < $1.key })?.value ?? 0
    }
}
