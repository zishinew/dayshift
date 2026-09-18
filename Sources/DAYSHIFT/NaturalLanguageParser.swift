import Foundation

struct NaturalLanguageParser {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func parse(_ input: String, now: Date = Date()) -> ParsedTask {
        let original = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = original.lowercased()
        let start = calendar.startOfDay(for: now)
        var dueDate = start

        if lower.contains("tomorrow") {
            dueDate = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        } else if lower.contains("next week") {
            dueDate = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        } else if let weekday = matchedWeekday(in: lower) {
            dueDate = next(weekday: weekday, after: start)
        } else if let explicitDate = explicitDate(in: lower, relativeTo: start) {
            dueDate = explicitDate
        }

        if let time = explicitTime(in: lower) {
            dueDate = calendar.date(
                bySettingHour: time.hour,
                minute: time.minute,
                second: 0,
                of: dueDate
            ) ?? dueDate
        } else if lower.contains("tonight") {
            dueDate = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: dueDate) ?? dueDate
        } else if lower.contains("morning") {
            dueDate = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: dueDate) ?? dueDate
        } else if lower.contains("afternoon") {
            dueDate = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: dueDate) ?? dueDate
        }

        let priority: TaskPriority
        if lower.range(of: #"\b(urgent|important|asap|critical|high priority)\b"#, options: .regularExpression) != nil {
            priority = .high
        } else if lower.range(of: #"\b(low priority|whenever|someday|sometime)\b"#, options: .regularExpression) != nil {
            priority = .low
        } else {
            priority = .medium
        }

        return ParsedTask(
            title: cleanedTitle(from: original),
            dueDate: dueDate,
            priority: priority
        )
    }

    private func matchedWeekday(in text: String) -> Int? {
        let names = calendar.weekdaySymbols.map { $0.lowercased() }
        for (index, name) in names.enumerated() where text.contains(name) {
            return index + 1
        }
        return nil
    }

    private func next(weekday: Int, after date: Date) -> Date {
        let current = calendar.component(.weekday, from: date)
        var distance = (weekday - current + 7) % 7
        if distance == 0 { distance = 7 }
        return calendar.date(byAdding: .day, value: distance, to: date) ?? date
    }

    private func explicitDate(in text: String, relativeTo date: Date) -> Date? {
        let formats = ["MMMM d", "MMM d", "M/d", "M/d/yyyy"]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            formatter.defaultDate = date
            if let range = text.range(of: datePattern(for: format), options: .regularExpression),
               let parsed = formatter.date(from: String(text[range])) {
                var result = parsed
                if !format.contains("y"), result < date {
                    result = calendar.date(byAdding: .year, value: 1, to: result) ?? result
                }
                return result
            }
        }
        return nil
    }

    private func datePattern(for format: String) -> String {
        switch format {
        case "MMMM d", "MMM d":
            return #"\b(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\s+\d{1,2}\b"#
        case "M/d":
            return #"\b\d{1,2}/\d{1,2}\b"#
        default:
            return #"\b\d{1,2}/\d{1,2}/\d{4}\b"#
        }
    }

    private func explicitTime(in text: String) -> (hour: Int, minute: Int)? {
        guard let regex = try? NSRegularExpression(pattern: #"\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let hourRange = Range(match.range(at: 1), in: text),
              var hour = Int(text[hourRange]) else { return nil }

        var minute = 0
        if match.range(at: 2).location != NSNotFound,
           let minuteRange = Range(match.range(at: 2), in: text) {
            minute = Int(text[minuteRange]) ?? 0
        }
        let marker = Range(match.range(at: 3), in: text).map { String(text[$0]) } ?? "am"
        if marker == "pm", hour < 12 { hour += 12 }
        if marker == "am", hour == 12 { hour = 0 }
        return (hour, minute)
    }

    private func cleanedTitle(from input: String) -> String {
        var title = input
        title = replacing(#"^\s*i\s+(?:have|need|want|must|should)\s+(?:to\s+)?"#, in: title)
        title = replacing(#"\b(?:today|tomorrow|tonight|next week|this\s+(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)|next\s+(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)|on\s+(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)|at\s+\d{1,2}(?::\d{2})?\s*(?:am|pm)|by\s+\d{1,2}(?::\d{2})?\s*(?:am|pm)|urgent|important|asap|critical|high priority|low priority|whenever|someday|sometime)\b"#, in: title)
        title = replacing(#"\s+"#, with: " ", in: title).trimmingCharacters(in: .whitespacesAndNewlines)
        title = replacing(#"^(?:a|an|the)\s+"#, in: title)

        if input.lowercased().contains("quiz"), input.lowercased().contains("i have") {
            title = "Study for \(title.isEmpty ? "quiz" : title)"
        }
        guard !title.isEmpty else { return "Untitled task" }
        return title.prefix(1).uppercased() + title.dropFirst()
    }

    private func replacing(_ pattern: String, with replacement: String = "", in value: String) -> String {
        value.replacingOccurrences(of: pattern, with: replacement, options: [.regularExpression, .caseInsensitive])
    }
}
