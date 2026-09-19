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

    func testNaturalEnglishDeleteWithDateTail() {
        XCTAssertEqual(
            TaskCommandInterpreter().interpret("remove the quiz on next Tuesday", now: now),
            .delete("quiz")
        )
    }

    func testNaturalEnglishCompletion() {
        XCTAssertEqual(
            TaskCommandInterpreter().interpret("mark the quiz as complete", now: now),
            .complete("quiz")
        )
    }

    func testCheckOffCommand() {
        XCTAssertEqual(TaskCommandInterpreter().interpret("check off the quiz", now: now), .complete("quiz"))
        XCTAssertEqual(TaskCommandInterpreter().interpret("the quiz is done", now: now), .complete("quiz"))
    }

    func testNaturalReschedulingCommands() {
        let interpreter = TaskCommandInterpreter()
        let commands = [
            interpreter.interpret("push the quiz to next Wednesday", now: now),
            interpreter.interpret("change the due date of the quiz to next Wednesday", now: now),
            interpreter.interpret("schedule quiz for next Wednesday", now: now)
        ]

        for command in commands {
            guard case .reschedule(let query, let date) = command else { return XCTFail("Expected reschedule command") }
            XCTAssertEqual(query, "quiz")
            XCTAssertEqual(Calendar.current.component(.weekday, from: date), 4)
        }
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

    func testAddClassCommand() {
        XCTAssertEqual(
            TaskCommandInterpreter().interpret("add class math237", now: now),
            .addClasses(["MATH237"])
        )
    }

    func testAddMultipleClassesCommand() {
        XCTAssertEqual(
            TaskCommandInterpreter().interpret("i have classes math237, cs136 and stat230", now: now),
            .addClasses(["MATH237", "CS136", "STAT230"])
        )
    }

    func testRepeatExistingTaskCommand() {
        XCTAssertEqual(
            TaskCommandInterpreter().interpret("repeat the quiz every 2 weeks", now: now),
            .repeatTask(query: "quiz", rule: RepeatRule(interval: 2, unit: .week))
        )
    }
}
