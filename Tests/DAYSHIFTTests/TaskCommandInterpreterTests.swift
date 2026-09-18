import XCTest
@testable import DAYSHIFT

final class TaskCommandInterpreterTests: XCTestCase {
    private var now: Date {
        ISO8601DateFormatter().date(from: "2026-09-18T12:00:00Z")!
    }

    func testPriorityCommand() {
        XCTAssertEqual(
            TaskCommandInterpreter().interpret("set priority of quiz to high", now: now),
            .setPriority(query: "quiz", priority: .high)
        )
    }

    func testShortPriorityCommand() {
        XCTAssertEqual(
            TaskCommandInterpreter().interpret("priority quiz high", now: now),
            .setPriority(query: "quiz", priority: .high)
        )
    }

    func testDeleteCommand() {
        XCTAssertEqual(TaskCommandInterpreter().interpret("remove quiz", now: now), .delete("quiz"))
    }

    func testRenameCommand() {
        XCTAssertEqual(
            TaskCommandInterpreter().interpret("rename quiz to chemistry quiz", now: now),
            .rename(query: "quiz", title: "chemistry quiz")
        )
    }

    func testNavigationCommand() {
        XCTAssertEqual(TaskCommandInterpreter().interpret("show calendar", now: now), .showCalendar)
    }

    func testUnrecognizedTextAddsTask() {
        let command = TaskCommandInterpreter().interpret("quiz next Wednesday", now: now)
        guard case .add(let task) = command else { return XCTFail("Expected an add command") }
        XCTAssertEqual(task.title, "Quiz")
    }
}
