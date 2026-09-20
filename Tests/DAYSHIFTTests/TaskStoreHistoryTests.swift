import XCTest
@testable import DAYSHIFT

final class TaskStoreHistoryTests: XCTestCase {
    @MainActor
    func testUndoAndRedoRestoreTaskMutations() {
        let store = makeStore()
        let originalDate = Date(timeIntervalSince1970: 1_700_000_000)
        let movedDate = originalDate.addingTimeInterval(86_400)

        store.add(ParsedTask(title: "Quiz", dueDate: originalDate, priority: .medium, classCode: nil, repeatRule: nil))
        XCTAssertEqual(store.tasks.count, 1)

        XCTAssertEqual(store.reschedule(matching: "quiz", to: movedDate), "Quiz")
        XCTAssertEqual(store.tasks.first?.dueDate, movedDate)

        store.undo()
        XCTAssertEqual(store.tasks.first?.dueDate, originalDate)

        store.undo()
        XCTAssertTrue(store.tasks.isEmpty)

        store.redo()
        XCTAssertEqual(store.tasks.first?.dueDate, originalDate)

        store.redo()
        XCTAssertEqual(store.tasks.first?.dueDate, movedDate)
    }

    @MainActor
    func testClassAutocompleteReplacesOnlyPartialClassToken() {
        let store = makeStore()
        store.addClasses(["MATH237", "CS136"])

        XCTAssertEqual(store.completedClassInput(for: "ma"), "math237")
        XCTAssertEqual(store.completedClassInput(for: "quiz ma"), "quiz math237")
        XCTAssertEqual(store.completedClassInput(for: "quiz"), "quiz math237")
        XCTAssertNil(store.completedClassInput(for: "dinner"))
    }

    @MainActor
    func testUpcomingTasksAreReturnedInDateOrder() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = Date(timeIntervalSince1970: 1_700_006_400)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: today)!
        let store = makeStore()

        store.add(ParsedTask(title: "Next week", dueDate: nextWeek, priority: .medium, classCode: nil, repeatRule: nil))
        store.add(ParsedTask(title: "Tomorrow", dueDate: tomorrow, priority: .medium, classCode: nil, repeatRule: nil))
        store.add(ParsedTask(title: "Today", dueDate: today, priority: .medium, classCode: nil, repeatRule: nil))

        XCTAssertEqual(store.tasks(after: today, calendar: calendar).map(\.title), ["Tomorrow", "Next week"])
    }

    @MainActor
    func testCompletingWeekdayRepeatCreatesTheCorrectOccurrence() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let tuesday = ISO8601DateFormatter().date(from: "2026-09-22T16:30:00Z")!
        let rule = RepeatRule(interval: 2, unit: .week, weekday: 3)
        let store = makeStore()
        store.add(ParsedTask(title: "Math237 quiz", dueDate: tuesday, priority: .medium, classCode: "MATH237", repeatRule: rule))

        XCTAssertEqual(store.setCompletion(matching: "math237 quiz", to: true), "Math237 quiz")
        let next = store.tasks.first { !$0.isComplete }
        XCTAssertEqual(next?.repeatRule, rule)
        XCTAssertEqual(next.map { calendar.dateComponents([.day], from: tuesday, to: $0.dueDate).day }, 14)

        XCTAssertEqual(store.clearRepeat(matching: "math237 quiz"), "Math237 quiz")
        XCTAssertNil(store.tasks.first { !$0.isComplete }?.repeatRule)
    }

    @MainActor
    func testEveryTaskDetailCanBeEditedAndUndone() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let original = ISO8601DateFormatter().date(from: "2026-09-22T00:00:00Z")!
        let store = makeStore()
        store.add(ParsedTask(title: "Quiz", dueDate: original, priority: .medium, classCode: nil, repeatRule: nil))

        XCTAssertEqual(store.rename(matching: "quiz", to: "Math237 quiz"), "Math237 quiz")
        XCTAssertEqual(store.setPriority(matching: "math237 quiz", to: .high), "Math237 quiz")
        XCTAssertEqual(store.setClass(matching: "math237 quiz", to: "MATH237"), "Math237 quiz")
        XCTAssertEqual(store.setTime(matching: "math237 quiz", hour: 16, minute: 30, calendar: calendar), "Math237 quiz")
        XCTAssertEqual(store.shiftDate(matching: "math237 quiz", amount: 2, unit: .day, calendar: calendar), "Math237 quiz")

        XCTAssertEqual(store.tasks.first?.priority, .high)
        XCTAssertEqual(store.tasks.first?.classCode, "MATH237")
        XCTAssertEqual(calendar.component(.day, from: store.tasks.first!.dueDate), 24)
        XCTAssertEqual(calendar.component(.hour, from: store.tasks.first!.dueDate), 16)
        XCTAssertEqual(calendar.component(.minute, from: store.tasks.first!.dueDate), 30)
        XCTAssertTrue(store.classes.contains { $0.code == "MATH237" })

        XCTAssertEqual(store.clearTime(matching: "math237 quiz", calendar: calendar), "Math237 quiz")
        XCTAssertEqual(store.clearClass(matching: "math237 quiz"), "Math237 quiz")
        XCTAssertEqual(calendar.component(.hour, from: store.tasks.first!.dueDate), 0)
        XCTAssertNil(store.tasks.first?.classCode)

        store.undo()
        XCTAssertEqual(store.tasks.first?.classCode, "MATH237")
    }

    @MainActor
    func testInlineRenameTargetsTheClickedTask() {
        let store = makeStore()
        store.add(ParsedTask(title: "Quiz", dueDate: Date(), priority: .medium, classCode: "MATH237", repeatRule: nil))
        store.add(ParsedTask(title: "Quiz", dueDate: Date(), priority: .medium, classCode: "STAT230", repeatRule: nil))
        let mathQuiz = store.tasks.first { $0.classCode == "MATH237" }!

        XCTAssertEqual(store.rename(mathQuiz, to: "Calculus quiz"), "Calculus quiz")
        let newDay = Calendar.current.date(byAdding: .day, value: 3, to: mathQuiz.dueDate)!
        XCTAssertEqual(store.setDate(mathQuiz, to: newDay), "Calculus quiz")
        XCTAssertEqual(store.setPriority(mathQuiz, to: .high), "Calculus quiz")
        XCTAssertEqual(store.setRepeat(mathQuiz, to: RepeatRule(interval: 1, unit: .week)), "Calculus quiz")
        XCTAssertEqual(store.tasks.first { $0.id == mathQuiz.id }?.title, "Calculus quiz")
        XCTAssertEqual(store.tasks.first { $0.id == mathQuiz.id }?.priority, .high)
        XCTAssertEqual(store.tasks.first { $0.id == mathQuiz.id }?.repeatRule, RepeatRule(interval: 1, unit: .week))
        XCTAssertEqual(store.tasks.first { $0.classCode == "STAT230" }?.title, "Quiz")
        XCTAssertEqual(store.tasks.first { $0.classCode == "STAT230" }?.priority, .medium)

        store.undo()
        XCTAssertNil(store.tasks.first { $0.id == mathQuiz.id }?.repeatRule)
    }

    @MainActor
    func testCompletedTaskAutoDeletesAndUndoRestoresIt() async throws {
        let store = makeStore(completionDelayNanoseconds: 20_000_000)
        store.add(ParsedTask(title: "Quiz", dueDate: Date(), priority: .medium, classCode: nil, repeatRule: nil))

        XCTAssertEqual(store.setCompletion(matching: "quiz", to: true), "Quiz")
        XCTAssertEqual(store.tasks.first?.isComplete, true)

        for _ in 0..<100 where !store.tasks.isEmpty {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(store.tasks.isEmpty)

        store.undo()
        XCTAssertEqual(store.tasks.count, 1)
        XCTAssertEqual(store.tasks.first?.isComplete, false)
    }

    @MainActor
    private func makeStore(completionDelayNanoseconds: UInt64 = 2_000_000_000) -> TaskStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        return TaskStore(
            fileURL: directory.appendingPathComponent("tasks.json"),
            completionDelayNanoseconds: completionDelayNanoseconds
        )
    }
}
