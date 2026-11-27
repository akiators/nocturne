import Foundation

/// Парсер синхронизированных текстов LRC. Поддерживает мульти-таймстампы,
/// метатеги [ar:]/[ti:]/[offset:] и форматы mm:ss.xx / mm:ss.xxx.
enum LRCParser {
    static func parse(_ lrc: String) -> [LyricLine]? {
        let pattern = #"\[(\d{1,2}):(\d{1,2})(?:[.:](\d{1,3}))?\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        var lines: [(time: TimeInterval, text: String)] = []

        for rawLine in lrc.components(separatedBy: .newlines) {
            let line = rawLine.trimmed
            guard !line.isEmpty else { continue }

            let matches = regex.matches(in: line, range: NSRange(line.startIndex..., in: line))
            guard !matches.isEmpty else { continue }

            let textStart = matches.last!.range.upperBound
            guard let textRange = Range(textStart..<line.count, in: line) else { continue }
            let text = String(line[textRange]).trimmed

            for match in matches {
                guard let minutesRange = Range(match.range(at: 1), in: line),
                      let secondsRange = Range(match.range(at: 2), in: line) else { continue }

                let minutes = Double(line[minutesRange]) ?? 0
                let seconds = Double(line[secondsRange]) ?? 0
                var fraction = 0.0
                if match.range(at: 3).location != NSNotFound,
                   let fractionRange = Range(match.range(at: 3), in: line) {
                    let raw = line[fractionRange]
                    let divisor = pow(10, Double(raw.count))
                    fraction = (Double(raw) ?? 0) / divisor
                }
                let time = minutes * 60 + seconds + fraction
                lines.append((time, text))
            }
        }

        guard !lines.isEmpty else { return nil }
        let sorted = lines.sorted { $0.time < $1.time }
        return sorted.enumerated().map { index, entry in
            LyricLine(id: index, time: entry.time, text: entry.text)
        }
    }

    /// Поиск строки по времени (для karaoke-подсветки).
    static func activeLineIndex(in lines: [LyricLine], at time: TimeInterval) -> Int? {
        guard !lines.isEmpty else { return nil }
        var low = 0
        var high = lines.count - 1
        var result: Int?
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].time <= time {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result
    }
}
