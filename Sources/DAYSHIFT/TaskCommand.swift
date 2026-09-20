import Foundation

enum TaskCommand: Equatable {
    case add(ParsedTask)
    case addClasses([String])
    case repeatTask(query: String, rule: RepeatRule)
    case stopRepeating(String)
    case complete(String)
    case reopen(String)
    case delete(String)
    case rename(query: String, title: String)
    case setPriority(query: String, priority: TaskPriority)
    case reschedule(query: String, date: Date)
    case clearCompleted
    case showToday
    case showCalendar
    case showDate(Date)
    case nextMonth
    case previousMonth
    case help

    var preview: String {
        switch self {
        case .add(let task):
            "Add “\(task.title)” · \(task.dueDate.formatted(date: .abbreviated, time: hasTime(task.dueDate) ? .shortened : .omitted)) · \(task.priority.rawValue)\(task.repeatRule.map { " · \($0.label)" } ?? "")"
        case .addClasses(let codes): "Add \(codes.map { $0.lowercased() }.joined(separator: ", "))"
        case .repeatTask(let query, let rule): "Repeat “\(query)” \(rule.label)"
        case .stopRepeating(let query): "Stop repeating “\(query)”"
        case .complete(let query): "Complete “\(query)”"
        case .reopen(let query): "Reopen “\(query)”"
        case .delete(let query): "Delete “\(query)”"
        case .rename(let query, let title): "Rename “\(query)” to “\(title)”"
        case .setPriority(let query, let priority): "Set “\(query)” to \(priority.rawValue) priority"
        case .reschedule(let query, let date):
            "Move “\(query)” to \(date.formatted(date: .abbreviated, time: hasTime(date) ? .shortened : .omitted))"
        case .clearCompleted: "Delete all completed tasks"
        case .showToday: "Show today"
        case .showCalendar: "Show calendar"
        case .showDate(let date): "Show \(date.formatted(date: .long, time: .omitted))"
        case .nextMonth: "Show next month"
        case .previousMonth: "Show previous month"
        case .help: "Show command help"
        }
    }

    private func hasTime(_ date: Date) -> Bool {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return parts.hour != 0 || parts.minute != 0
    }
}

struct TaskCommandInterpreter {
    private let taskParser: NaturalLanguageParser

    init(taskParser: NaturalLanguageParser = NaturalLanguageParser()) {
        self.taskParser = taskParser
    }

    func interpret(_ input: String, now: Date = Date()) -> TaskCommand {
        let normalized = taskParser.normalizingLanguage(in: input.trimmingCharacters(in: .whitespacesAndNewlines))
        let value = strippingConversationWrapper(from: normalized)
        let lower = value.lowercased()

        switch lower {
        case "help", "commands", "?": return .help
        case "today", "show today", "go to today", "open today": return .showToday
        case "calendar", "show calendar", "open calendar": return .showCalendar
        case "next month", "show next month": return .nextMonth
        case "previous month", "prev month", "show previous month": return .previousMonth
        case "clear completed", "delete completed", "remove completed": return .clearCompleted
        default: break
        }

        if lower.range(of: #"^(?:add\s+class(?:es)?|i\s+have\s+class(?:es)?|my\s+classes\s+are)\b"#, options: .regularExpression) != nil {
            let codes = classCodes(in: value)
            if !codes.isEmpty { return .addClasses(codes) }
        }

        if let groups = captures(#"^(?:stop|cancel)\s+(?:the\s+|my\s+)?(?:task\s+)?(.+?)\s+from\s+(?:repeating|recurring)$"#, in: value) {
            return .stopRepeating(cleanTarget(groups[0]))
        }

        if let groups = captures(#"^stop\s+repeating\s+(.+)$"#, in: value) {
            return .stopRepeating(cleanTarget(groups[0]))
        }

        if let groups = captures(#"^make\s+(.+?)\s+stop\s+(?:repeating|recurring)$"#, in: value) {
            return .stopRepeating(cleanTarget(groups[0]))
        }

        if let groups = captures(#"^(?:do\s+not|don't)\s+repeat\s+(.+?)(?:\s+anymore)?$"#, in: value) {
            return .stopRepeating(cleanTarget(groups[0]))
        }

        if let repeatCommand = repeatCommand(in: value) {
            return repeatCommand
        }

        if let groups = captures(#"^(?:set\s+)?(?:the\s+)?priority\s+(?:of|for)\s+(.+?)\s+(?:to\s+)?(high|medium|low)$"#, in: value),
           let priority = TaskPriority(rawValue: groups[1].capitalized) {
            return .setPriority(query: cleanTarget(groups[0]), priority: priority)
        }

        if let groups = captures(#"^(?:set\s+)?(.+?)\s+priority\s+(?:to\s+)?(high|medium|low)$"#, in: value),
           let priority = TaskPriority(rawValue: groups[1].capitalized) {
            return .setPriority(query: cleanTarget(groups[0]), priority: priority)
        }

        if let groups = captures(#"^priority\s+(.+?)\s+(?:to\s+)?(high|medium|low)$"#, in: value),
           let priority = TaskPriority(rawValue: groups[1].capitalized) {
            return .setPriority(query: cleanTarget(groups[0]), priority: priority)
        }

        if let groups = captures(#"^make\s+(.+?)\s+(?:a\s+)?(high|medium|low)(?:\s+priority)?$"#, in: value),
           let priority = TaskPriority(rawValue: groups[1].capitalized) {
            return .setPriority(query: cleanTarget(groups[0]), priority: priority)
        }

        if let groups = captures(#"^(?:mark|make|set)\s+(.+?)\s+(?:as\s+)?(?:urgent|important|critical)$"#, in: value) {
            return .setPriority(query: cleanTarget(groups[0]), priority: .high)
        }

        if let groups = captures(#"^(.+?)\s+(?:should\s+be|is)\s+(high|medium|low)(?:\s+priority)?$"#, in: value),
           let priority = TaskPriority(rawValue: groups[1].capitalized) {
            return .setPriority(query: cleanTarget(groups[0]), priority: priority)
        }

        if let groups = captures(#"^(raise|increase|lower|decrease)\s+(?:the\s+)?priority\s+(?:of|for)\s+(.+)$"#, in: value) {
            let priority: TaskPriority = ["raise", "increase"].contains(groups[0].lowercased()) ? .high : .low
            return .setPriority(query: cleanTarget(groups[1]), priority: priority)
        }

        if let groups = captures(#"^(?:rename|change\s+name\s+of)\s+(.+?)\s+to\s+(.+)$"#, in: value) {
            return .rename(query: cleanTarget(groups[0]), title: groups[1])
        }

        if let groups = captures(#"^(?:change|set)\s+(?:the\s+)?(?:due\s+)?date\s+(?:of|for)\s+(.+?)\s+to\s+(.+)$"#, in: value) {
            return .reschedule(query: cleanTarget(groups[0]), date: taskParser.parse(groups[1], now: now).dueDate)
        }

        if let groups = captures(#"^(?:move|reschedule|push(?:\s+back)?|postpone|defer)\s+(?:the\s+|my\s+)?(?:task\s+)?(.+?)\s+from\s+.+?\s+(?:to|until)\s+(.+)$"#, in: value) {
            return .reschedule(query: cleanTarget(groups[0]), date: taskParser.parse(groups[1], now: now).dueDate)
        }

        if let groups = captures(#"^(?:move|reschedule|push(?:\s+back)?|postpone|defer|schedule|put)\s+(?:the\s+|my\s+)?(?:task\s+)?(.+?)\s+(?:to|for|until|on)\s+(.+)$"#, in: value) {
            return .reschedule(query: cleanTarget(groups[0]), date: taskParser.parse(groups[1], now: now).dueDate)
        }

        if let groups = captures(#"^(?:change|set)\s+(.+?)\s+(?:due\s+)?date\s+to\s+(.+)$"#, in: value) {
            return .reschedule(query: cleanTarget(groups[0]), date: taskParser.parse(groups[1], now: now).dueDate)
        }

        if let groups = captures(#"^(?:complete|finish|finished|check\s+off|tick\s+off|mark\s+off)\s+(?:the\s+|my\s+)?(?:task\s+)?(.+)$"#, in: value) {
            return .complete(cleanTarget(groups[0]))
        }

        if let groups = captures(#"^i(?:'ve|\s+have)?\s+(?:finished|completed|done)\s+(.+)$"#, in: value) {
            return .complete(cleanTarget(groups[0]))
        }

        if let groups = captures(#"^done\s+with\s+(.+)$"#, in: value) {
            return .complete(cleanTarget(groups[0]))
        }

        if let groups = captures(#"^(.+?)\s+(?:is|was|has\s+been)\s+(?:done|finished|complete|completed)$"#, in: value) {
            return .complete(cleanTarget(groups[0]))
        }

        if let groups = captures(#"^mark\s+(.+?)\s+(?:done|complete|completed)$"#, in: value) {
            return .complete(cleanTarget(groups[0]))
        }

        if let groups = captures(#"^mark\s+(.+?)\s+as\s+(?:done|complete|completed)$"#, in: value) {
            return .complete(cleanTarget(groups[0]))
        }

        if let groups = captures(#"^(?:reopen|uncomplete|uncheck|restore|mark\s+unfinished|mark\s+incomplete)\s+(?:the\s+|my\s+)?(?:task\s+)?(.+)$"#, in: value) {
            return .reopen(cleanTarget(groups[0]))
        }

        if let groups = captures(#"^(?:delete|remove|cancel|erase|drop|get\s+rid\s+of)\s+(?:the\s+|my\s+)?(?:task\s+)?(.+)$"#, in: value) {
            return .delete(cleanTarget(groups[0]))
        }

        if let groups = captures(#"^i\s+(?:do\s+not|don't)\s+need\s+(.+?)(?:\s+anymore)?$"#, in: value) {
            return .delete(cleanTarget(groups[0]))
        }

        if let groups = captures(#"^(?:show|go\s+to|open)\s+(.+)$"#, in: value) {
            return .showDate(taskParser.parse(groups[0], now: now).dueDate)
        }

        let taskText = value.replacingOccurrences(
            of: #"^add\s+(?:task\s+)?"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        return .add(taskParser.parse(taskText, now: now))
    }

    private func cleanTarget(_ input: String) -> String {
        var target = input
        target = replacing(#"^\s*(?:the|a|an|my)\s+"#, in: target)
        target = replacing(#"\s+(?:on|for|by)\s+(?:(?:next|this)\s+)?(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday|today|tomorrow|tonight|\d{1,2}/\d{1,2}(?:/\d{2,4})?).*$"#, in: target)
        target = replacing(#"\s+(?:(?:next|this)\s+)?(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday|today|tomorrow|tonight)\b.*$"#, in: target)
        target = replacing(#"\s+at\s+\d{1,2}(?::\d{2})?\s*(?:am|pm)\b.*$"#, in: target)
        target = replacing(#"\s+as$"#, in: target)
        return target.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private func strippingConversationWrapper(from input: String) -> String {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        value = replacing(#"^\s*(?:(?:please|hey|okay|ok)\s*[,.]?\s*)+"#, in: value)
        value = replacing(#"^\s*(?:can|could|would|will)\s+(?:you|we)\s+(?:please\s+)?"#, in: value)
        value = replacing(#"^\s*i(?:'d|\s+would)?\s+like\s+(?:you\s+)?to\s+"#, in: value)
        value = replacing(#"^\s*i\s+want\s+(?:you\s+)?to\s+"#, in: value)
        value = replacing(#"\s*[,!.?]?\s+please\s*[!.?]*\s*$"#, in: value)
        return value.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private func repeatCommand(in value: String) -> TaskCommand? {
        let patterns = [
            #"^(?:repeat|recur)\s+(?:the\s+|my\s+)?(?:task\s+)?(.+?)\s+((?:every|each)\s+.+|(?:daily|weekly|monthly|biweekly|fortnightly)(?:\s+on\s+.+)?)$"#,
            #"^(?:make|have)\s+(?:the\s+|my\s+)?(?:task\s+)?(.+?)\s+(?:repeat|recur|recurring)\s+(.+)$"#,
            #"^set\s+(?:the\s+|my\s+)?(?:task\s+)?(.+?)\s+to\s+(?:repeat|recur)\s+(.+)$"#,
            #"^(.+?)\s+(?:should|needs?\s+to|has\s+to|must)\s+(?:repeat|recur)\s+(.+)$"#
        ]

        for pattern in patterns {
            guard let groups = captures(pattern, in: value), groups.count == 2 else { continue }
            var recurrence = groups[1]
            recurrence = recurrence.replacingOccurrences(of: #"^on\s+"#, with: "every ", options: [.regularExpression, .caseInsensitive])
            if let rule = taskParser.repeatRule(in: recurrence) {
                return .repeatTask(query: cleanTarget(groups[0]), rule: rule)
            }
        }
        return nil
    }

    private func replacing(_ pattern: String, in value: String) -> String {
        value.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
    }

    private func captures(_ pattern: String, in value: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { return nil }

        return (1..<match.numberOfRanges).map { index in
            guard match.range(at: index).location != NSNotFound,
                  let range = Range(match.range(at: index), in: value) else { return "" }
            return String(value[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func classCodes(in value: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\b[a-z]{2,8}\s?\d{2,4}[a-z]?\b"#, options: [.caseInsensitive]) else { return [] }
        let matches = regex.matches(in: value, range: NSRange(value.startIndex..., in: value))
        var seen = Set<String>()
        return matches.compactMap { match in
            guard let range = Range(match.range, in: value) else { return nil }
            let code = value[range].replacingOccurrences(of: " ", with: "").uppercased()
            return seen.insert(code).inserted ? code : nil
        }
    }
}
