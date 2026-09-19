import Foundation
import Observation

@MainActor
@Observable
final class TaskStore {
    private(set) var tasks: [TaskItem] = []
    private(set) var classes: [ClassItem] = []
    private let fileURL: URL
    private let classesURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
            self.classesURL = fileURL.deletingLastPathComponent().appendingPathComponent("classes.json")
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.fileURL = base.appending(path: "DAYSHIFT/tasks.json")
            self.classesURL = base.appending(path: "DAYSHIFT/classes.json")
        }
        load()
        loadClasses()
    }

    func add(_ parsed: ParsedTask) {
        tasks.insert(TaskItem(title: parsed.title, dueDate: parsed.dueDate, priority: parsed.priority, classCode: parsed.classCode, repeatRule: parsed.repeatRule), at: 0)
        save()
    }

    func addClass(code: String, name: String) {
        let normalized = code.replacingOccurrences(of: " ", with: "").uppercased()
        if let index = classes.firstIndex(where: { $0.code == normalized }) {
            classes[index].name = name
        } else {
            classes.append(ClassItem(code: normalized, name: name))
        }
        saveClasses()
    }

    func addClasses(_ codes: [String]) {
        for code in codes {
            addClass(code: code, name: "")
        }
    }

    func suggestedClass(for input: String) -> ClassItem? {
        let query = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.range(of: #"(class|study|quiz|exam|homework|assignment|lab|lecture|math|essay)"#, options: .regularExpression) != nil else { return nil }
        guard !classes.contains(where: { query.contains($0.code.lowercased()) }) else { return nil }
        let tail = query.split(separator: " ").last.map(String.init) ?? query
        return classes.first(where: { $0.code.lowercased().hasPrefix(tail) || $0.name.lowercased().contains(tail) }) ?? classes.first
    }

    func toggle(_ task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].isComplete.toggle()
        save()
    }

    @discardableResult
    func setCompletion(matching query: String, to value: Bool) -> String? {
        guard let index = matchingIndex(for: query) else { return nil }
        let wasComplete = tasks[index].isComplete
        tasks[index].isComplete = value
        let title = tasks[index].title
        if value, !wasComplete, let rule = tasks[index].repeatRule {
            let nextDate = rule.nextDate(after: tasks[index].dueDate)
            let next = TaskItem(title: tasks[index].title, dueDate: nextDate, priority: tasks[index].priority, classCode: tasks[index].classCode, repeatRule: rule)
            tasks.insert(next, at: 0)
        }
        save()
        return title
    }

    @discardableResult
    func delete(matching query: String) -> String? {
        guard let index = matchingIndex(for: query) else { return nil }
        let title = tasks[index].title
        tasks.remove(at: index)
        save()
        return title
    }

    @discardableResult
    func rename(matching query: String, to title: String) -> String? {
        guard let index = matchingIndex(for: query) else { return nil }
        tasks[index].title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let updated = tasks[index].title
        save()
        return updated
    }

    @discardableResult
    func setPriority(matching query: String, to priority: TaskPriority) -> String? {
        guard let index = matchingIndex(for: query) else { return nil }
        tasks[index].priority = priority
        let title = tasks[index].title
        save()
        return title
    }

    @discardableResult
    func reschedule(matching query: String, to date: Date) -> String? {
        guard let index = matchingIndex(for: query) else { return nil }
        tasks[index].dueDate = date
        let title = tasks[index].title
        save()
        return title
    }

    @discardableResult
    func setRepeat(matching query: String, to rule: RepeatRule) -> String? {
        guard let index = matchingIndex(for: query) else { return nil }
        tasks[index].repeatRule = rule
        let title = tasks[index].title
        save()
        return title
    }

    func clearCompleted() -> Int {
        let count = tasks.count(where: \.isComplete)
        tasks.removeAll(where: \.isComplete)
        save()
        return count
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

    private func matchingIndex(for query: String) -> Int? {
        let needle = normalize(query)
        guard !needle.isEmpty else { return nil }

        if let exact = tasks.firstIndex(where: { normalize($0.title) == needle }) {
            return exact
        }
        return tasks.firstIndex(where: { normalize($0.title).contains(needle) })
    }

    private func normalize(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode([TaskItem].self, from: data) else { return }
        tasks = stored
    }

    private func loadClasses() {
        guard let data = try? Data(contentsOf: classesURL),
              let stored = try? JSONDecoder().decode([ClassItem].self, from: data) else { return }
        classes = stored
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

    private func saveClasses() {
        do {
            try FileManager.default.createDirectory(at: classesURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(classes)
            try data.write(to: classesURL, options: .atomic)
        } catch {
            assertionFailure("Could not save classes: \(error)")
        }
    }
}
