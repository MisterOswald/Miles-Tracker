import SwiftUI

/// Soft SaaS palette — matches the web dashboard design tokens.
enum Theme {
    static let accent = Color(red: 0x54 / 255, green: 0x57 / 255, blue: 0xD6 / 255)      // #5457D6
    static let accentSoft = Color(red: 0xEC / 255, green: 0xEB / 255, blue: 0xFC / 255)  // #ECEBFC
    static let business = Color(red: 0x2F / 255, green: 0x9E / 255, blue: 0x77 / 255)    // #2F9E77
    static let businessSoft = Color(red: 0xE3 / 255, green: 0xF4 / 255, blue: 0xED / 255)
    static let personal = Color(red: 0xB4 / 255, green: 0x65 / 255, blue: 0xD1 / 255)    // #B465D1
    static let personalSoft = Color(red: 0xF5 / 255, green: 0xE9 / 255, blue: 0xF9 / 255)
    static let unclassified = Color(red: 0xD9 / 255, green: 0x9A / 255, blue: 0x2B / 255) // #D99A2B
    static let unclassifiedSoft = Color(red: 0xF9 / 255, green: 0xEF / 255, blue: 0xDC / 255)
    static let danger = Color(red: 0xD0 / 255, green: 0x5A / 255, blue: 0x5A / 255)       // #D05A5A

    static func color(for category: DriveCategory) -> Color {
        switch category {
        case .business: return business
        case .personal: return personal
        case .unclassified: return unclassified
        }
    }

    static func softColor(for category: DriveCategory) -> Color {
        switch category {
        case .business: return businessSoft
        case .personal: return personalSoft
        case .unclassified: return unclassifiedSoft
        }
    }
}
