import Foundation
import SwiftData

enum Persistence {
    static let container: ModelContainer = {
        let schema = Schema([Drive.self, RateEntry.self, NamedLocation.self])
        let config = ModelConfiguration(schema: schema)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // A corrupt store is unrecoverable in place; fall back to an
            // in-memory store rather than crash-looping. Synced data can be
            // restored from the server.
            NSLog("Miles: persistent store failed (\(error)); using in-memory store")
            let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do {
                return try ModelContainer(for: schema, configurations: [memory])
            } catch {
                fatalError("Unable to create any SwiftData container: \(error)")
            }
        }
    }()

    /// Seeds default IRS rates for known years on first launch.
    @MainActor
    static func seedDefaultRates() {
        let context = container.mainContext
        let existing = (try? context.fetch(FetchDescriptor<RateEntry>())) ?? []
        let existingYears = Set(existing.map(\.year))
        for (year, cents) in DefaultRates.known where !existingYears.contains(year) {
            context.insert(RateEntry(year: year, centsPerMile: cents))
        }
        try? context.save()
    }
}
