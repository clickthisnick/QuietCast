import Foundation

enum TimeGate {
    /// Search is allowed between 8:00 AM and 7:59 PM local time.
    /// Returns false when hour >= 20 or hour < 8.
    static func searchAllowed(at date: Date = Date()) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        return hour >= 8 && hour < 20
    }

    /// Nighttime is 8:00 PM – 7:59 AM (the inverse of search hours).
    static func isNighttime(at date: Date = Date()) -> Bool {
        !searchAllowed(at: date)
    }
}
