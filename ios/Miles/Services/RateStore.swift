import Foundation
import SwiftData

enum RateStore {
    /// The IRS rate (decimal cents/mile) to apply for a given year: the
    /// user-edited value if present, otherwise the built-in default.
    @MainActor
    static func rate(forYear year: Int, context: ModelContext) -> Double {
        var descriptor = FetchDescriptor<RateEntry>(
            predicate: #Predicate { $0.year == year }
        )
        descriptor.fetchLimit = 1
        if let entry = try? context.fetch(descriptor).first {
            return entry.centsPerMile
        }
        return DefaultRates.rate(forYear: year)
    }
}
