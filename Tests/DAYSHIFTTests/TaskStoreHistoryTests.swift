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
