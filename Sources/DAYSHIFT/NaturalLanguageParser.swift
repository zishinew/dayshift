import Foundation

struct NaturalLanguageParser {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func parse(_ input: String, now: Date = Date()) -> ParsedTask {
        let original = normalizingWeekdays(in: input.trimmingCharacters(in: .whitespacesAndNewlines))
        let lower = original.lowercased()
        let start = calendar.startOfDay(for: now)
        var dueDate = start
        let repeatRule = repetition(in: lower)
        let classCode = classCode(in: lower)

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
            priority: priority,
            classCode: classCode,
            repeatRule: repeatRule
        )
    }

    func normalizingWeekdays(in input: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\b[a-z]+\b\.?"#, options: [.caseInsensitive]) else { return input }
        let matches = regex.matches(in: input, range: NSRange(input.startIndex..., in: input))
        var result = input

        for (index, match) in matches.enumerated().reversed() {
            guard let range = Range(match.range, in: input) else { continue }
            let token = input[range].trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
            let previous = index > 0 ? Range(matches[index - 1].range, in: input).map { input[$0].lowercased() } : nil
            guard let weekday = canonicalWeekday(for: token, previousWord: previous) else { continue }
            result.replaceSubrange(range, with: weekday)
        }
        return result
    }

    private func canonicalWeekday(for token: String, previousWord: String?) -> String? {
        let aliases: [String: String] = [
            "su": "sunday", "sun": "sunday", "sund": "sunday", "sunda": "sunday", "sunday": "sunday",
            "mo": "monday", "mon": "monday", "mond": "monday", "monda": "monday", "monday": "monday",
            "tu": "tuesday", "tue": "tuesday", "tues": "tuesday", "tuesd": "tuesday", "tuesda": "tuesday", "tuesday": "tuesday",
            "we": "wednesday", "wed": "wednesday", "weds": "wednesday", "wedn": "wednesday", "wedne": "wednesday", "wednes": "wednesday", "wednesd": "wednesday", "wednesda": "wednesday", "wednesday": "wednesday",
            "th": "thursday", "thu": "thursday", "thur": "thursday", "thurs": "thursday", "thursd": "thursday", "thursda": "thursday", "thursday": "thursday",
            "fr": "friday", "fri": "friday", "frid": "friday", "frida": "friday", "friday": "friday",
            "sa": "saturday", "sat": "saturday", "satu": "saturday", "satur": "saturday", "saturd": "saturday", "saturda": "saturday", "saturday": "saturday"
        ]
        if let exact = aliases[token] { return exact }

        let commonMisspellings: [String: String] = [
            "sundy": "sunday", "sundey": "sunday",
            "mnday": "monday", "mondy": "monday", "monay": "monday",
            "tuseday": "tuesday", "teusday": "tuesday", "tusday": "tuesday",
            "wensday": "wednesday", "wednsday": "wednesday", "wendsday": "wednesday", "wensdey": "wednesday",
            "thrusday": "thursday", "thurday": "thursday", "thusday": "thursday",
            "firday": "friday", "fridy": "friday",
            "saterday": "saturday", "sturday": "saturday", "satrday": "saturday"
        ]
        if let corrected = commonMisspellings[token] { return corrected }

        let dateSignals = ["next", "this", "on", "to", "for", "until", "by"]
        guard previousWord.map(dateSignals.contains) == true, token.count >= 3 else { return nil }
        return calendar.weekdaySymbols
            .map { $0.lowercased() }
            .min(by: { editDistance(token, $0) < editDistance(token, $1) })
            .flatMap { editDistance(token, $0) <= 2 ? $0 : nil }
    }

    private func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        var previous = Array(0...right.count)

        for (leftIndex, leftCharacter) in left.enumerated() {
            var current = [leftIndex + 1]
            for (rightIndex, rightCharacter) in right.enumerated() {
                current.append(min(
                    current[rightIndex] + 1,
                    previous[rightIndex + 1] + 1,
                    previous[rightIndex] + (leftCharacter == rightCharacter ? 0 : 1)
                ))
            }
            previous = current
        }
        return previous[right.count]
    }

    private func repetition(in text: String) -> RepeatRule? {
        guard let regex = try? NSRegularExpression(pattern: #"\bevery\s+(?:(\d+)\s+)?(day|days|week|weeks|month|months|weekday|weekdays)\b"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        let interval = match.range(at: 1).location == NSNotFound ? 1 : (Range(match.range(at: 1), in: text).flatMap { Int(text[$0]) } ?? 1)
        guard let unitRange = Range(match.range(at: 2), in: text) else { return nil }
        let unitText = String(text[unitRange])
        let unit: RepeatUnit = unitText.hasPrefix("day") || unitText.hasPrefix("weekday") ? .day : unitText.hasPrefix("week") ? .week : .month
        return RepeatRule(interval: unitText.hasPrefix("weekday") ? 1 : interval, unit: unitText.hasPrefix("weekday") ? .week : unit)
    }

    private func classCode(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"\b([a-z]{2,8}\s?\d{2,4})\b"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range]).replacingOccurrences(of: " ", with: "").uppercased()
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
        title = replacing(#"^\s*(?:i\s+(?:have|need|want|must|should)\s+(?:to\s+)?|remind\s+me\s+to\s+|don't\s+forget\s+to\s+|remember\s+to\s+|add\s+(?:a\s+)?(?:repeating\s+)?)"#, in: title)
        title = replacing(#"\b(?:today|tomorrow|tonight|next week|this\s+(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)|next\s+(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)|on\s+(?:(?:next|this)\s+)?(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)|at\s+\d{1,2}(?::\d{2})?\s*(?:am|pm)|by\s+\d{1,2}(?::\d{2})?\s*(?:am|pm)|urgent|important|asap|critical|high priority|low priority|whenever|someday|sometime)\b"#, in: title)
        title = replacing(#"\bevery\s+(?:(?:\d+)\s+)?(?:day|days|week|weeks|month|months|weekday|weekdays)\b"#, in: title)
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
