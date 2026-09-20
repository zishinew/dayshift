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

    func testDeleteWithShortWeekday() {
        XCTAssertEqual(
            TaskCommandInterpreter().interpret("remove the quiz on next weds", now: now),
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

    func testNaturalWeekdayRepeatCommands() {
        let interpreter = TaskCommandInterpreter()
        let expected = TaskCommand.repeatTask(
            query: "math237 quiz",
            rule: RepeatRule(interval: 2, unit: .week, weekday: 3)
        )

        XCTAssertEqual(interpreter.interpret("make math237 quiz repeat every other tuesday", now: now), expected)
        XCTAssertEqual(interpreter.interpret("please repeat the math237 quiz every second tue", now: now), expected)
        XCTAssertEqual(interpreter.interpret("could you set math237 quiz to recur every 2 weeks on tuesdays?", now: now), expected)
        XCTAssertEqual(interpreter.interpret("math237 quiz should repeat every other tues", now: now), expected)
    }

    func testStopRepeatingCommands() {
        let interpreter = TaskCommandInterpreter()
        XCTAssertEqual(interpreter.interpret("stop repeating the math237 quiz", now: now), .stopRepeating("math237 quiz"))
        XCTAssertEqual(interpreter.interpret("make math237 quiz stop recurring", now: now), .stopRepeating("math237 quiz"))
        XCTAssertEqual(interpreter.interpret("don't repeat math237 quiz anymore", now: now), .stopRepeating("math237 quiz"))
    }

    func testConversationalCommandWrappers() {
        let interpreter = TaskCommandInterpreter()

        XCTAssertEqual(interpreter.interpret("could you please get rid of the quiz?", now: now), .delete("quiz"))
        XCTAssertEqual(interpreter.interpret("I finished my chemistry homework", now: now), .complete("chemistry homework"))
        XCTAssertEqual(interpreter.interpret("would you move the quiz from Tuesday to Friday please", now: now).rescheduleQuery, "quiz")
        XCTAssertEqual(interpreter.interpret("make the lab important", now: now), .setPriority(query: "lab", priority: .high))
        XCTAssertEqual(interpreter.interpret("the essay should be low priority", now: now), .setPriority(query: "essay", priority: .low))
    }

    func testCommonCommandTyposAreCorrected() {
        let interpreter = TaskCommandInterpreter()
        XCTAssertEqual(interpreter.interpret("set prioirty of quiz to high", now: now), .setPriority(query: "quiz", priority: .high))
        XCTAssertEqual(interpreter.interpret("reapeat quiz every alternate tuesday", now: now), .repeatTask(query: "quiz", rule: RepeatRule(interval: 2, unit: .week, weekday: 3)))
        XCTAssertEqual(interpreter.interpret("rescheduel quiz to tommorow", now: now).rescheduleQuery, "quiz")
    }

    func testNaturalDetailEditingCommands() {
        let interpreter = TaskCommandInterpreter()

        XCTAssertEqual(interpreter.interpret("change quiz's title to math237 midterm", now: now), .rename(query: "quiz", title: "math237 midterm"))
        XCTAssertEqual(interpreter.interpret("call quiz math237 midterm", now: now), .rename(query: "quiz", title: "math237 midterm"))
        XCTAssertEqual(interpreter.interpret("quiz should be due next tuesday", now: now).rescheduleQuery, "quiz")
        XCTAssertEqual(interpreter.interpret("change the time of quiz to 4:30pm", now: now), .setTime(query: "quiz", hour: 16, minute: 30))
        XCTAssertEqual(interpreter.interpret("make quiz an all-day task", now: now), .clearTime("quiz"))
        XCTAssertEqual(interpreter.interpret("change quiz priority to low", now: now), .setPriority(query: "quiz", priority: .low))
        XCTAssertEqual(interpreter.interpret("assign quiz to class math237", now: now), .setClass(query: "quiz", code: "MATH237"))
        XCTAssertEqual(interpreter.interpret("remove the class from quiz", now: now), .clearClass("quiz"))
        XCTAssertEqual(interpreter.interpret("push quiz back by two days", now: now), .shiftDate(query: "quiz", amount: 2, unit: .day))
        XCTAssertEqual(interpreter.interpret("bring quiz forward one week", now: now), .shiftDate(query: "quiz", amount: -1, unit: .week))
    }
}

private extension TaskCommand {
    var rescheduleQuery: String? {
        guard case .reschedule(let query, _) = self else { return nil }
        return query
    }
}
