import Foundation

enum Formatters {
    static let currency: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        return f
    }()

    static func money(_ dollars: Double) -> String {
        currency.string(from: NSNumber(value: dollars)) ?? String(format: "$%.2f", dollars)
    }

    static func miles(_ miles: Double) -> String {
        String(format: "%.1f mi", miles)
    }

    static func duration(_ interval: TimeInterval) -> String {
        let minutes = max(1, Int((interval / 60).rounded()))
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func dayHeader(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    static func rate(_ centsPerMile: Double) -> String {
        centsPerMile.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f¢/mi", centsPerMile)
            : String(format: "%.1f¢/mi", centsPerMile)
    }
}
