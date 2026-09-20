import Foundation

struct NaturalLanguageParser {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func parse(_ input: String, now: Date = Date()) -> ParsedTask {
        let original = normalizingLanguage(in: input.trimmingCharacters(in: .whitespacesAndNewlines))
        let lower = original.lowercased()
        let start = calendar.startOfDay(for: now)
        var dueDate = start
        let repeatRule = repeatRule(in: lower)
        let classCode = classCode(in: lower)

        if lower.contains("day after tomorrow") {
            dueDate = calendar.date(byAdding: .day, value: 2, to: start) ?? start
        } else if let relativeDate = relativeDate(in: lower, from: start) {
            dueDate = relativeDate
        } else if lower.contains("tomorrow") {
            dueDate = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        } else if lower.contains("next week") {
            dueDate = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        } else if lower.contains("next month") {
            dueDate = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        } else if lower.contains("weekend") {
            dueDate = next(weekday: 7, after: start)
        } else if let weekday = matchedWeekday(in: lower) {
            dueDate = next(weekday: weekday, after: start)
        } else if let explicitDate = explicitDate(in: lower, relativeTo: start) {
            dueDate = explicitDate
        }

        if lower.range(of: #"\bnoon\b"#, options: .regularExpression) != nil {
            dueDate = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: dueDate) ?? dueDate
        } else if lower.range(of: #"\bmidnight\b"#, options: .regularExpression) != nil {
            dueDate = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: dueDate) ?? dueDate
        } else if let time = explicitTime(in: lower) {
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

    func normalizingLanguage(in input: String) -> String {
        var result = input
        let corrections = [
            "tommorow": "tomorrow", "tommorrow": "tomorrow", "tomorow": "tomorrow",
            "calender": "calendar", "prioirty": "priority", "priorty": "priority", "prority": "priority",
            "compelte": "complete", "compelete": "complete", "rescheduel": "reschedule",
            "reschedual": "reschedule", "reshedule": "reschedule", "reapeat": "repeat",
            "repeet": "repeat", "urgant": "urgent", "delte": "delete", "delet": "delete"
        ]
        for (misspelling, correction) in corrections {
            result = result.replacingOccurrences(
                of: #"\b"# + NSRegularExpression.escapedPattern(for: misspelling) + #"\b"#,
                with: correction,
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return normalizingWeekdays(in: result)
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

    func repeatRule(in input: String) -> RepeatRule? {
        let text = normalizingLanguage(in: input).lowercased()
        let weekdayPattern = #"(sunday|monday|tuesday|wednesday|thursday|friday|saturday)s?"#

        if let groups = captures(#"\b(?:every|each)\s+(?:other|alternate|second|2nd)\s+"# + weekdayPattern + #"\b"#, in: text),
           let weekday = weekdayNumber(groups[0]) {
            return RepeatRule(interval: 2, unit: .week, weekday: weekday)
        }

        if let groups = captures(#"\b(?:every|each)\s+(\d+(?:st|nd|rd|th)?|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth|eleventh|twelfth)\s+"# + weekdayPattern + #"\b"#, in: text),
           let interval = number(groups[0]), let weekday = weekdayNumber(groups[1]) {
            return RepeatRule(interval: interval, unit: .week, weekday: weekday)
        }

        if let groups = captures(#"\b(?:every|each)\s+(\d+|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s+weeks?\s+(?:on\s+)?"# + weekdayPattern + #"\b"#, in: text),
           let interval = number(groups[0]), let weekday = weekdayNumber(groups[1]) {
            return RepeatRule(interval: interval, unit: .week, weekday: weekday)
        }

        if let groups = captures(#"\b(?:every|each)\s+"# + weekdayPattern + #"\b"#, in: text),
           let weekday = weekdayNumber(groups[0]) {
            return RepeatRule(interval: 1, unit: .week, weekday: weekday)
        }

        if let groups = captures(#"\bweekly\s+(?:on\s+)?"# + weekdayPattern + #"\b"#, in: text),
           let weekday = weekdayNumber(groups[0]) {
            return RepeatRule(interval: 1, unit: .week, weekday: weekday)
        }

        if text.range(of: #"\b(?:biweekly|fortnightly|every\s+(?:other|second|2nd)\s+week)\b"#, options: .regularExpression) != nil {
            return RepeatRule(interval: 2, unit: .week)
        }

        if let groups = captures(#"\b(?:every|each)\s+(?:other|second|2nd)\s+(day|week|month)s?\b"#, in: text) {
            return RepeatRule(interval: 2, unit: repeatUnit(groups[0]))
        }

        if let groups = captures(#"\b(?:every|each)\s+(?:(\d+|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s+)?(day|days|week|weeks|month|months|weekday|weekdays)\b"#, in: text) {
            let interval = number(groups[0]) ?? 1
            let unitText = groups[1]
            return RepeatRule(interval: unitText.hasPrefix("weekday") ? 1 : interval, unit: unitText.hasPrefix("weekday") ? .week : repeatUnit(unitText))
        }

        if let groups = captures(#"\b(daily|weekly|monthly)\b"#, in: text) {
            return RepeatRule(interval: 1, unit: groups[0] == "daily" ? .day : groups[0] == "weekly" ? .week : .month)
        }

        return nil
    }

    private func repeatUnit(_ text: String) -> RepeatUnit {
        text.hasPrefix("day") ? .day : text.hasPrefix("week") ? .week : .month
    }

    private func weekdayNumber(_ name: String) -> Int? {
        [
            "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4,
            "thursday": 5, "friday": 6, "saturday": 7
        ][name.lowercased()]
    }

    private func number(_ text: String) -> Int? {
        let digits = text.replacingOccurrences(of: #"(?:st|nd|rd|th)$"#, with: "", options: .regularExpression)
        if let value = Int(digits) { return max(1, value) }
        return [
            "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
            "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
            "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5, "sixth": 6,
            "seventh": 7, "eighth": 8, "ninth": 9, "tenth": 10, "eleventh": 11, "twelfth": 12
        ][text]
    }

    private func captures(_ pattern: String, in value: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { return nil }
        return (1..<match.numberOfRanges).map { index in
            guard match.range(at: index).location != NSNotFound,
                  let range = Range(match.range(at: index), in: value) else { return "" }
            return String(value[range]).lowercased()
        }
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

    private func relativeDate(in text: String, from date: Date) -> Date? {
        let quantity = #"(\d+|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|a|an)"#
        let patterns = [
            #"\bin\s+"# + quantity + #"\s+(day|week|month)s?\b"#,
            #"\b"# + quantity + #"\s+(day|week|month)s?\s+(?:from\s+(?:now|today)|away)\b"#
        ]

        for pattern in patterns {
            guard let groups = captures(pattern, in: text) else { continue }
            let amount = ["a", "an"].contains(groups[0]) ? 1 : (number(groups[0]) ?? 1)
            let component: Calendar.Component = groups[1] == "day" ? .day : groups[1] == "week" ? .weekOfYear : .month
            return calendar.date(byAdding: component, value: amount, to: date)
        }
        return nil
    }

    private func explicitDate(in text: String, relativeTo date: Date) -> Date? {
        let formats: [(String, String)] = [
            ("yyyy-MM-dd", #"\b\d{4}-\d{1,2}-\d{1,2}\b"#),
            ("M/d/yyyy", #"\b\d{1,2}/\d{1,2}/\d{4}\b"#),
            ("MMMM d yyyy", #"\b(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\s+\d{1,2}(?:st|nd|rd|th)?[,]?\s+\d{4}\b"#),
            ("MMMM d", #"\b(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\s+\d{1,2}(?:st|nd|rd|th)?\b"#),
            ("d MMMM", #"\b\d{1,2}(?:st|nd|rd|th)?\s+(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\b"#),
            ("M/d", #"\b\d{1,2}/\d{1,2}\b"#)
        ]
        for (format, pattern) in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = format
            formatter.defaultDate = date
            if let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                let dateText = String(text[range])
                    .replacingOccurrences(of: #"(?<=\d)(?:st|nd|rd|th)\b"#, with: "", options: [.regularExpression, .caseInsensitive])
                    .replacingOccurrences(of: ",", with: "")
                guard let parsed = formatter.date(from: dateText) else { continue }
                var result = parsed
                if !format.contains("y"), result < date {
                    result = calendar.date(byAdding: .year, value: 1, to: result) ?? result
                }
                return result
            }
        }
        return nil
    }

    private func explicitTime(in text: String) -> (hour: Int, minute: Int)? {
        let twelveHour = #"\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b"#
        let twentyFourHour = #"\b(?:at|by|around)\s+([01]?\d|2[0-3]):([0-5]\d)\b"#
        guard let regex = try? NSRegularExpression(pattern: twelveHour + "|" + twentyFourHour, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }

        let isTwelveHour = match.range(at: 1).location != NSNotFound
        let hourIndex = isTwelveHour ? 1 : 4
        let minuteIndex = isTwelveHour ? 2 : 5
        guard let hourRange = Range(match.range(at: hourIndex), in: text), var hour = Int(text[hourRange]) else { return nil }

        var minute = 0
        if match.range(at: minuteIndex).location != NSNotFound,
           let minuteRange = Range(match.range(at: minuteIndex), in: text) {
            minute = Int(text[minuteRange]) ?? 0
        }
        if isTwelveHour {
            let marker = Range(match.range(at: 3), in: text).map { String(text[$0]).lowercased() } ?? "am"
            if marker == "pm", hour < 12 { hour += 12 }
            if marker == "am", hour == 12 { hour = 0 }
        }
        return (hour, minute)
    }

    private func cleanedTitle(from input: String) -> String {
        var title = input
        title = replacing(#"^\s*(?:i\s+(?:have|need|want|must|should)\s+(?:to\s+)?|remind\s+me\s+to\s+|don't\s+forget\s+to\s+|remember\s+to\s+|add\s+(?:a\s+)?(?:repeating\s+)?)"#, in: title)
        title = replacing(#"\b(?:day after tomorrow|today|tomorrow|tonight|next week|next month|this weekend|next weekend|this\s+(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)|next\s+(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)|on\s+(?:(?:next|this)\s+)?(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)|(?:in\s+)?(?:\d+|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|a|an)\s+(?:day|week|month)s?(?:\s+(?:from\s+(?:now|today)|away))?|(?:at|by|around)\s+\d{1,2}(?::\d{2})?\s*(?:am|pm)?|noon|midnight|urgent|important|asap|critical|high priority|low priority|whenever|someday|sometime)\b"#, in: title)
        title = replacing(#"\b(?:due|on|by|for)?\s*(?:(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\s+\d{1,2}(?:st|nd|rd|th)?(?:[,]?\s+\d{4})?|\d{1,2}(?:st|nd|rd|th)?\s+(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)|\d{1,2}/\d{1,2}(?:/\d{4})?|\d{4}-\d{1,2}-\d{1,2})\b"#, in: title)
        title = replacing(#"\b(?:every|each)\s+(?:(?:other|second|2nd|\d+|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s+)?(?:day|days|week|weeks|month|months|weekday|weekdays|monday|mondays|tuesday|tuesdays|wednesday|wednesdays|thursday|thursdays|friday|fridays|saturday|saturdays|sunday|sundays)(?:\s+on\s+(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday))?\b"#, in: title)
        title = replacing(#"\b(?:daily|weekly|monthly|biweekly|fortnightly)(?:\s+on\s+(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday))?\b"#, in: title)
        title = replacing(#"\s+"#, with: " ", in: title).trimmingCharacters(in: .whitespacesAndNewlines)
        title = replacing(#"\s+(?:due|on|by|at|for)$"#, in: title)
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
