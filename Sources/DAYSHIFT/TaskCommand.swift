import Foundation

enum TaskCommand: Equatable {
    case add(ParsedTask)
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
            "Add “\(task.title)” · \(task.dueDate.formatted(date: .abbreviated, time: hasTime(task.dueDate) ? .shortened : .omitted)) · \(task.priority.rawValue)"
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
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
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

        if let groups = captures(#"^(?:rename|change\s+name\s+of)\s+(.+?)\s+to\s+(.+)$"#, in: value) {
            return .rename(query: cleanTarget(groups[0]), title: groups[1])
        }

        if let groups = captures(#"^(?:move|reschedule)\s+(.+?)\s+to\s+(.+)$"#, in: value) {
            return .reschedule(query: cleanTarget(groups[0]), date: taskParser.parse(groups[1], now: now).dueDate)
        }

        if let groups = captures(#"^(?:complete|finish)\s+(?:task\s+)?(.+)$"#, in: value) {
            return .complete(cleanTarget(groups[0]))
        }

        if let groups = captures(#"^mark\s+(.+?)\s+(?:done|complete|completed)$"#, in: value) {
            return .complete(cleanTarget(groups[0]))
        }

        if let groups = captures(#"^mark\s+(.+?)\s+as\s+(?:done|complete|completed)$"#, in: value) {
            return .complete(cleanTarget(groups[0]))
        }

        if let groups = captures(#"^(?:reopen|uncomplete|undo)\s+(?:task\s+)?(.+)$"#, in: value) {
            return .reopen(cleanTarget(groups[0]))
        }

        if let groups = captures(#"^(?:delete|remove|cancel)\s+(?:task\s+)?(.+)$"#, in: value) {
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
        return target.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func replacing(_ pattern: String, in value: String) -> String {
        value.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
    }

    private func captures(_ pattern: String, in value: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { return nil }

        return (1..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: value) else { return nil }
            return String(value[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
