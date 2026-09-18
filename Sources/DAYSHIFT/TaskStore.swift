import Foundation
import Observation

@MainActor
@Observable
final class TaskStore {
    private(set) var tasks: [TaskItem] = []
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.fileURL = base.appending(path: "DAYSHIFT/tasks.json")
        }
        load()
    }

    func add(_ parsed: ParsedTask) {
        tasks.insert(TaskItem(title: parsed.title, dueDate: parsed.dueDate, priority: parsed.priority), at: 0)
        save()
    }

    func toggle(_ task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].isComplete.toggle()
        save()
    }

    func delete(_ task: TaskItem) {
        tasks.removeAll { $0.id == task.id }
        save()
    }

    func tasks(on date: Date, calendar: Calendar = .current) -> [TaskItem] {
        tasks
            .filter { calendar.isDate($0.dueDate, inSameDayAs: date) }
            .sorted {
                if $0.isComplete != $1.isComplete { return !$0.isComplete }
                if $0.priority != $1.priority { return rank($0.priority) < rank($1.priority) }
                return $0.dueDate < $1.dueDate
            }
    }

    private func rank(_ priority: TaskPriority) -> Int {
        switch priority {
        case .high: 0
        case .medium: 1
        case .low: 2
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode([TaskItem].self, from: data) else { return }
        tasks = stored
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(tasks)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            assertionFailure("Could not save tasks: \(error)")
        }
    }
}
