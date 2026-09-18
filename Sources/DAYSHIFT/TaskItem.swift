import Foundation

enum TaskPriority: String, Codable, CaseIterable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"
}

struct TaskItem: Identifiable, Codable, Hashable {
    var id: UUID
    var title: String
    var dueDate: Date
    var priority: TaskPriority
    var isComplete: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        dueDate: Date,
        priority: TaskPriority,
        isComplete: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.dueDate = dueDate
        self.priority = priority
        self.isComplete = isComplete
        self.createdAt = createdAt
    }
}

struct ParsedTask: Equatable {
    let title: String
    let dueDate: Date
    let priority: TaskPriority
}
