import Foundation

/// Lightweight settings stored in UserDefaults. Drives, rates, and named
/// locations live in SwiftData; these are simple scalar preferences.
enum AppSettings {
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let autoTrackingEnabled = "autoTrackingEnabled"
        static let workHoursRuleEnabled = "workHoursRuleEnabled"
        static let workHoursStartMinutes = "workHoursStartMinutes"
        static let workHoursEndMinutes = "workHoursEndMinutes"
        static let serverURL = "serverURL"
        static let accountEmail = "accountEmail"
        static let syncCursor = "syncCursor"
        static let lastSyncAt = "lastSyncAt"
        static let lastParkedLatitude = "lastParkedLatitude"
        static let lastParkedLongitude = "lastParkedLongitude"
        static let lastParkedAt = "lastParkedAt"
    }

    /// Master switch for automatic drive detection.
    static var autoTrackingEnabled: Bool {
        get { defaults.object(forKey: Key.autoTrackingEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.autoTrackingEnabled) }
    }

    /// Work-hours rule: drives starting Mon–Fri inside the window default to
    /// Business when no named-location rule matches.
    static var workHoursRuleEnabled: Bool {
        get { defaults.bool(forKey: Key.workHoursRuleEnabled) }
        set { defaults.set(newValue, forKey: Key.workHoursRuleEnabled) }
    }

    /// Minutes past midnight, default 9:00.
    static var workHoursStartMinutes: Int {
        get { defaults.object(forKey: Key.workHoursStartMinutes) as? Int ?? 9 * 60 }
        set { defaults.set(newValue, forKey: Key.workHoursStartMinutes) }
    }

    /// Minutes past midnight, default 17:00.
    static var workHoursEndMinutes: Int {
        get { defaults.object(forKey: Key.workHoursEndMinutes) as? Int ?? 17 * 60 }
        set { defaults.set(newValue, forKey: Key.workHoursEndMinutes) }
    }

    /// Base URL of the web deployment, e.g. https://miles.example.vercel.app
    static var serverURL: String {
        get { defaults.string(forKey: Key.serverURL) ?? "" }
        set { defaults.set(newValue, forKey: Key.serverURL) }
    }

    static var accountEmail: String {
        get { defaults.string(forKey: Key.accountEmail) ?? "" }
        set { defaults.set(newValue, forKey: Key.accountEmail) }
    }

    /// Server-issued cursor (ISO timestamp) from the last successful sync.
    static var syncCursor: String? {
        get { defaults.string(forKey: Key.syncCursor) }
        set { defaults.set(newValue, forKey: Key.syncCursor) }
    }

    static var lastSyncAt: Date? {
        get { defaults.object(forKey: Key.lastSyncAt) as? Date }
        set { defaults.set(newValue, forKey: Key.lastSyncAt) }
    }

    /// Where the car was last parked (previous drive's end, or a CLVisit).
    /// Used to anchor the start of the next drive at the true origin even
    /// when iOS wakes the app a few blocks into the trip.
    static var lastParked: (latitude: Double, longitude: Double, at: Date)? {
        get {
            guard let lat = defaults.object(forKey: Key.lastParkedLatitude) as? Double,
                  let lng = defaults.object(forKey: Key.lastParkedLongitude) as? Double,
                  let at = defaults.object(forKey: Key.lastParkedAt) as? Date else {
                return nil
            }
            return (lat, lng, at)
        }
        set {
            defaults.set(newValue?.latitude, forKey: Key.lastParkedLatitude)
            defaults.set(newValue?.longitude, forKey: Key.lastParkedLongitude)
            defaults.set(newValue?.at, forKey: Key.lastParkedAt)
        }
    }
}
