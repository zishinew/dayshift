import Foundation
import Observation

@MainActor
@Observable
final class TaskStore {
    private struct Snapshot {
        let tasks: [TaskItem]
        let classes: [ClassItem]
    }

    private(set) var tasks: [TaskItem] = []
    private(set) var classes: [ClassItem] = []
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    @ObservationIgnored private var completionDeletionTasks: [UUID: Task<Void, Never>] = [:]
    private let fileURL: URL
    private let classesURL: URL
    private let completionDelayNanoseconds: UInt64

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    init(fileURL: URL? = nil, completionDelayNanoseconds: UInt64 = 2_000_000_000) {
        self.completionDelayNanoseconds = completionDelayNanoseconds
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
        reconcileCompletionDeletions()
    }

    func add(_ parsed: ParsedTask) {
        recordMutation()
        tasks.insert(TaskItem(title: parsed.title, dueDate: parsed.dueDate, priority: parsed.priority, classCode: parsed.classCode, repeatRule: parsed.repeatRule), at: 0)
        save()
    }

    func addClass(code: String, name: String) {
        let normalized = code.replacingOccurrences(of: " ", with: "").uppercased()
        guard classes.first(where: { $0.code == normalized })?.name != name else { return }
        recordMutation()
        upsertClass(code: normalized, name: name)
        saveClasses()
    }

    private func upsertClass(code: String, name: String) {
        if let index = classes.firstIndex(where: { $0.code == code }) {
            classes[index].name = name
        } else {
            classes.append(ClassItem(code: code, name: name))
        }
    }

    func addClasses(_ codes: [String]) {
        let normalized = codes.map { $0.replacingOccurrences(of: " ", with: "").uppercased() }
        guard normalized.contains(where: { code in classes.first(where: { $0.code == code })?.name != "" }) else { return }
        recordMutation()
        normalized.forEach { upsertClass(code: $0, name: "") }
        saveClasses()
    }

    func suggestedClass(for input: String) -> ClassItem? {
        let query = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !classes.contains(where: { query.contains($0.code.lowercased()) }) else { return nil }
        let tail = query.split(separator: " ").last.map(String.init) ?? query
        if let prefixMatch = classes.first(where: { $0.code.lowercased().hasPrefix(tail) }) {
            return prefixMatch
        }
        guard query.range(of: #"(class|study|quiz|exam|homework|assignment|lab|lecture|math|essay)"#, options: .regularExpression) != nil else { return nil }
        return classes.first(where: { !$0.name.isEmpty && $0.name.lowercased().contains(tail) }) ?? classes.first
    }

    func completedClassInput(for input: String) -> String? {
        guard let suggestion = suggestedClass(for: input) else { return nil }
        let code = suggestion.code.lowercased()
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return code }

        if let tokenRange = trimmed.range(of: #"[a-z0-9]+$"#, options: [.regularExpression, .caseInsensitive]) {
            let token = trimmed[tokenRange].lowercased()
            if code.hasPrefix(token) {
                var completed = trimmed
                completed.replaceSubrange(tokenRange, with: code)
                return completed
            }
        }
        return trimmed + " " + code
    }

    func toggle(_ task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        recordMutation()
        tasks[index].isComplete.toggle()
        updateCompletionDeletion(for: tasks[index])
        save()
    }

    @discardableResult
    func setCompletion(matching query: String, to value: Bool) -> String? {
        guard let index = matchingIndex(for: query) else { return nil }
        let wasComplete = tasks[index].isComplete
        guard wasComplete != value else { return tasks[index].title }
        recordMutation()
        tasks[index].isComplete = value
        let title = tasks[index].title
        if value, !wasComplete, let rule = tasks[index].repeatRule {
            let nextDate = rule.nextDate(after: tasks[index].dueDate)
            let next = TaskItem(title: tasks[index].title, dueDate: nextDate, priority: tasks[index].priority, classCode: tasks[index].classCode, repeatRule: rule)
            tasks.insert(next, at: 0)
        }
        updateCompletionDeletion(for: tasks[index])
        save()
        return title
    }

    @discardableResult
    func delete(matching query: String) -> String? {
        guard let index = matchingIndex(for: query) else { return nil }
        recordMutation()
        let title = tasks[index].title
        completionDeletionTasks[tasks[index].id]?.cancel()
        completionDeletionTasks[tasks[index].id] = nil
        tasks.remove(at: index)
        save()
        return title
    }

    @discardableResult
    func rename(matching query: String, to title: String) -> String? {
        guard let index = matchingIndex(for: query) else { return nil }
        return rename(at: index, to: title)
    }

    @discardableResult
    func rename(_ task: TaskItem, to title: String) -> String? {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return nil }
        return rename(at: index, to: title)
    }

    private func rename(at index: Int, to title: String) -> String? {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return nil }
        guard tasks[index].title != cleanTitle else { return tasks[index].title }
        recordMutation()
        tasks[index].title = cleanTitle
        let updated = tasks[index].title
        save()
        return updated
    }

    @discardableResult
    func setPriority(matching query: String, to priority: TaskPriority) -> String? {
        guard let index = matchingIndex(for: query) else { return nil }
        guard tasks[index].priority != priority else { return tasks[index].title }
        recordMutation()
        tasks[index].priority = priority
        let title = tasks[index].title
        save()
        return title
    }

    @discardableResult
    func reschedule(matching query: String, to date: Date) -> String? {
        guard let index = matchingIndex(for: query) else { return nil }
        guard tasks[index].dueDate != date else { return tasks[index].title }
        recordMutation()
        tasks[index].dueDate = date
        let title = tasks[index].title
        save()
        return title
    }

    @discardableResult
    func shiftDate(matching query: String, amount: Int, unit: RepeatUnit, calendar: Calendar = .current) -> String? {
        guard let index = matchingIndex(for: query) else { return nil }
        let component: Calendar.Component = unit == .day ? .day : unit == .week ? .weekOfYear : .month
        guard let date = calendar.date(byAdding: component, value: amount, to: tasks[index].dueDate) else { return nil }
        recordMutation()
        tasks[index].dueDate = date
        let title = tasks[index].title
        save()
        return title
    }

    @discardableResult
    func setTime(matching query: String, hour: Int, minute: Int, calendar: Calendar = .current) -> String? {
        guard let index = matchingIndex(for: query),
              let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: tasks[index].dueDate) else { return nil }
        guard tasks[index].dueDate != date else { return tasks[index].title }
        recordMutation()
        tasks[index].dueDate = date
        let title = tasks[index].title
        save()
        return title
    }

    @discardableResult
    func clearTime(matching query: String, calendar: Calendar = .current) -> String? {
        guard let index = matchingIndex(for: query) else { return nil }
        let date = calendar.startOfDay(for: tasks[index].dueDate)
        guard tasks[index].dueDate != date else { return tasks[index].title }
        recordMutation()
        tasks[index].dueDate = date
        let title = tasks[index].title
        save()
        return title
    }

    @discardableResult
    func setClass(matching query: String, to code: String) -> String? {
        guard let index = matchingIndex(for: query) else { return nil }
        let normalized = code.replacingOccurrences(of: " ", with: "").uppercased()
        guard tasks[index].classCode != normalized else { return tasks[index].title }
        recordMutation()
        tasks[index].classCode = normalized
        upsertClass(code: normalized, name: classes.first(where: { $0.code == normalized })?.name ?? "")
        let title = tasks[index].title
        save()
        saveClasses()
        return title
    }

    @discardableResult
    func clearClass(matching query: String) -> String? {
        guard let index = matchingIndex(for: query) else { return nil }
        guard tasks[index].classCode != nil else { return tasks[index].title }
        recordMutation()
        tasks[index].classCode = nil
        let title = tasks[index].title
        save()
        return title
    }

    @discardableResult
    func setRepeat(matching query: String, to rule: RepeatRule) -> String? {
        guard let index = matchingIndex(for: query) else { return nil }
        guard tasks[index].repeatRule != rule else { return tasks[index].title }
        recordMutation()
        tasks[index].repeatRule = rule
        let title = tasks[index].title
        save()
        return title
    }

    @discardableResult
    func clearRepeat(matching query: String) -> String? {
        guard let index = matchingIndex(for: query) else { return nil }
        guard tasks[index].repeatRule != nil else { return tasks[index].title }
        recordMutation()
        tasks[index].repeatRule = nil
        let title = tasks[index].title
        save()
        return title
    }

    func clearCompleted() -> Int {
        let count = tasks.filter(\.isComplete).count
        guard count > 0 else { return 0 }
        recordMutation()
        completionDeletionTasks.values.forEach { $0.cancel() }
        completionDeletionTasks.removeAll()
        tasks.removeAll(where: \.isComplete)
        save()
        return count
    }

    func delete(_ task: TaskItem) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        recordMutation()
        completionDeletionTasks[task.id]?.cancel()
        completionDeletionTasks[task.id] = nil
        tasks.remove(at: index)
        save()
    }

    func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append(currentSnapshot)
        restore(snapshot)
    }

    func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(currentSnapshot)
        restore(snapshot)
    }

    func tasks(on date: Date, calendar: Calendar = .current) -> [TaskItem] {
        tasks
            .filter { calendar.isDate($0.dueDate, inSameDayAs: date) }
            .sorted {
                if $0.priority != $1.priority { return rank($0.priority) < rank($1.priority) }
                return $0.dueDate < $1.dueDate
            }
    }

    func tasks(after date: Date, calendar: Calendar = .current) -> [TaskItem] {
        let startOfNextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
        return tasks
            .filter { $0.dueDate >= startOfNextDay }
            .sorted {
                if $0.dueDate != $1.dueDate { return $0.dueDate < $1.dueDate }
                return rank($0.priority) < rank($1.priority)
            }
    }

    private func rank(_ priority: TaskPriority) -> Int {
        switch priority {
        case .high: 0
        case .medium: 1
        case .low: 2
        }
    }

    private var currentSnapshot: Snapshot { Snapshot(tasks: tasks, classes: classes) }

    private func recordMutation() {
        undoStack.append(currentSnapshot)
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    private func restore(_ snapshot: Snapshot) {
        tasks = snapshot.tasks
        classes = snapshot.classes
        save()
        saveClasses()
        reconcileCompletionDeletions()
    }

    private func updateCompletionDeletion(for task: TaskItem) {
        completionDeletionTasks[task.id]?.cancel()
        completionDeletionTasks[task.id] = nil
        guard task.isComplete else { return }

        completionDeletionTasks[task.id] = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: self?.completionDelayNanoseconds ?? 2_000_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.removeCompletedTask(id: task.id)
        }
    }

    private func reconcileCompletionDeletions() {
        completionDeletionTasks.values.forEach { $0.cancel() }
        completionDeletionTasks.removeAll()
        tasks.filter(\.isComplete).forEach(updateCompletionDeletion)
    }

    private func removeCompletedTask(id: UUID) {
        completionDeletionTasks[id] = nil
        guard let index = tasks.firstIndex(where: { $0.id == id && $0.isComplete }) else { return }
        tasks.remove(at: index)
        save()
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
