import Foundation
import SwiftUI

// MARK: - Time formatting

extension TimeInterval {
    var clockString: String {
        guard self.isFinite, self >= 0 else { return "0:00" }
        let total = Int(self.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    var humanDuration: String {
        let total = Int(self.rounded())
        let h = total / 3600, m = (total % 3600) / 60
        if h > 0 { return "\(h) ч \(m) мин" }
        if m > 0 { return "\(m) мин" }
        return "\(total) сек"
    }
}

// MARK: - Date

extension Date {
    var dayStart: Date {
        Calendar.current.startOfDay(for: self)
    }

    func isWithin(days: Int, of other: Date = Date()) -> Bool {
        let daySeconds: TimeInterval = 86_400
        return abs(timeIntervalSince(other)) <= daySeconds * TimeInterval(days)
    }
}

// MARK: - Strings

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    var initials: String {
        let parts = split(separator: " ").prefix(2)
        return parts.compactMap(\.first).map(String.init).joined().uppercased()
    }

    /// Определяет, похоже ли начало строки на вопрос на естественном языке (RU/EN).
    var looksLikeNaturalQuery: Bool {
        let words = split(separator: " ")
        return words.count >= 3
    }
}

// MARK: - Color from hex

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - View helpers

extension View {
    func cornerRadius(_ radius: CGFloat) -> some View {
        clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

// MARK: - Debouncer

final class Debouncer {
    private var workItem: DispatchWorkItem?
    private let delay: TimeInterval

    init(delay: TimeInterval = 0.35) { self.delay = delay }

    func run(_ block: @escaping () -> Void) {
        workItem?.cancel()
        let item = DispatchWorkItem(block: block)
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
}

// MARK: - JSON helpers

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

extension JSONDecoder {
    static var standard: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
