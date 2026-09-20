import Foundation

enum TaskPriority: String, Codable, CaseIterable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"
}

enum RepeatUnit: String, Codable, CaseIterable {
    case day, week, month
}

struct RepeatRule: Codable, Hashable, Equatable {
    var interval: Int
    var unit: RepeatUnit
    var weekday: Int?

    init(interval: Int, unit: RepeatUnit, weekday: Int? = nil) {
        self.interval = interval
        self.unit = unit
        self.weekday = weekday
    }

    var label: String {
        if let weekday {
            let names = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
            let weekdayName = names[max(1, min(7, weekday)) - 1]
            if interval == 2 { return "every other \(weekdayName)" }
            if interval == 1 { return "every \(weekdayName)" }
            return "every \(interval) weeks on \(weekdayName)"
        }
        let unitName = interval == 1 ? unit.rawValue : unit.rawValue + "s"
        return "every \(interval) \(unitName)"
    }

    func nextDate(after date: Date, calendar: Calendar = .current) -> Date {
        if let weekday {
            let currentWeekday = calendar.component(.weekday, from: date)
            var daysUntilWeekday = (weekday - currentWeekday + 7) % 7
            if daysUntilWeekday == 0 {
                daysUntilWeekday = 7 * max(1, interval)
            }
            return calendar.date(byAdding: .day, value: daysUntilWeekday, to: date) ?? date
        }
        return calendar.date(byAdding: unit == .day ? .day : unit == .week ? .weekOfYear : .month, value: interval, to: date) ?? date
    }
}

struct ClassItem: Identifiable, Codable, Hashable {
    var id: UUID
    var code: String
    var name: String

    init(id: UUID = UUID(), code: String, name: String) {
        self.id = id
        self.code = code
        self.name = name
    }
}

struct TaskItem: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var dueDate: Date
    var priority: TaskPriority
    var isComplete: Bool
    var createdAt: Date
    var classCode: String?
    var repeatRule: RepeatRule?
    /// Scheduled items such as quizzes, tests, and meetings are events rather than actionable tasks.
    var isEvent: Bool

    private enum CodingKeys: String, CodingKey {
        case id, title, dueDate, priority, isComplete, createdAt, classCode, repeatRule, isEvent
    }

    init(
        id: UUID = UUID(),
        title: String,
        dueDate: Date,
        priority: TaskPriority,
        isComplete: Bool = false,
        createdAt: Date = Date(),
        classCode: String? = nil,
        repeatRule: RepeatRule? = nil,
        isEvent: Bool = false
    ) {
        self.id = id
        self.title = title
        self.dueDate = dueDate
        self.priority = priority
        self.isComplete = isComplete
        self.createdAt = createdAt
        self.classCode = classCode
        self.repeatRule = repeatRule
        self.isEvent = isEvent
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        dueDate = try values.decode(Date.self, forKey: .dueDate)
        priority = try values.decode(TaskPriority.self, forKey: .priority)
        isComplete = try values.decode(Bool.self, forKey: .isComplete)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        classCode = try values.decodeIfPresent(String.self, forKey: .classCode)
        repeatRule = try values.decodeIfPresent(RepeatRule.self, forKey: .repeatRule)
        isEvent = try values.decodeIfPresent(Bool.self, forKey: .isEvent) ?? Self.looksLikeEvent(title)
    }

    private static func looksLikeEvent(_ title: String) -> Bool {
        title.range(of: #"\b(quiz(?:zes)?|test(?:s)?|exam(?:s)?|midterm(?:s)?|final(?:s)?|assessment(?:s)?|presentation(?:s)?|appointment(?:s)?|meeting(?:s)?|interview(?:s)?|lecture(?:s)?|concert(?:s)?|flight(?:s)?)\b"#, options: .regularExpression) != nil
    }
}

struct ParsedTask: Equatable {
    let title: String
    let dueDate: Date
    let priority: TaskPriority
    let classCode: String?
    let repeatRule: RepeatRule?
    let isEvent: Bool

    init(title: String, dueDate: Date, priority: TaskPriority, classCode: String?, repeatRule: RepeatRule?, isEvent: Bool = false) {
        self.title = title
        self.dueDate = dueDate
        self.priority = priority
        self.classCode = classCode
        self.repeatRule = repeatRule
        self.isEvent = isEvent
    }
}
