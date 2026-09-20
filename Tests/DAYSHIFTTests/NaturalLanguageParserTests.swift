import XCTest
@testable import DAYSHIFT

final class NaturalLanguageParserTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testQuizNextWednesday() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-18T12:00:00Z"))
        let result = NaturalLanguageParser(calendar: calendar).parse("I have a quiz next Wednesday", now: now)
        XCTAssertEqual(result.title, "Study for quiz")
        XCTAssertEqual(calendar.component(.day, from: result.dueDate), 23)
        XCTAssertEqual(result.priority, .medium)
        XCTAssertTrue(result.isEvent)
    }

    func testUrgentTaskWithTime() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-18T12:00:00Z"))
        let result = NaturalLanguageParser(calendar: calendar).parse("Submit report tomorrow at 4:30pm urgent", now: now)
        XCTAssertEqual(result.title, "Submit report")
        XCTAssertEqual(calendar.component(.day, from: result.dueDate), 19)
        XCTAssertEqual(calendar.component(.hour, from: result.dueDate), 16)
        XCTAssertEqual(calendar.component(.minute, from: result.dueDate), 30)
        XCTAssertEqual(result.priority, .high)
        XCTAssertFalse(result.isEvent)
    }

    func testAssessmentLanguageCreatesAnEvent() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-18T12:00:00Z"))
        let parser = NaturalLanguageParser(calendar: calendar)

        XCTAssertTrue(parser.parse("I have a midterm next Tuesday", now: now).isEvent)
        XCTAssertTrue(parser.parse("team meeting tomorrow", now: now).isEvent)
        XCTAssertFalse(parser.parse("finish my assignment tomorrow", now: now).isEvent)
    }

    func testRepeatingClassTask() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-18T12:00:00Z"))
        let result = NaturalLanguageParser(calendar: calendar).parse("add a repeating math237 quiz every week", now: now)
        XCTAssertEqual(result.classCode, "MATH237")
        XCTAssertEqual(result.repeatRule, RepeatRule(interval: 1, unit: .week))
    }

    func testWeekdayShortForms() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-18T12:00:00Z"))
        let examples: [(String, Int)] = [
            ("sun", 1), ("mon", 2), ("tue", 3), ("tues", 3),
            ("wed", 4), ("weds", 4), ("thu", 5), ("thur", 5),
            ("thurs", 5), ("fri", 6), ("sat", 7)
        ]

        for (shortForm, weekday) in examples {
            let result = NaturalLanguageParser(calendar: calendar).parse("quiz next \(shortForm)", now: now)
            XCTAssertEqual(calendar.component(.weekday, from: result.dueDate), weekday, shortForm)
            XCTAssertEqual(result.title, "Quiz", shortForm)
        }
    }

    func testCommonWeekdayMisspellingsAreCorrected() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-18T12:00:00Z"))
        let examples: [(String, Int)] = [
            ("sundy", 1), ("mnday", 2), ("tuseday", 3), ("wensday", 4),
            ("thrusday", 5), ("firday", 6), ("saterday", 7)
        ]

        for (misspelling, weekday) in examples {
            let result = NaturalLanguageParser(calendar: calendar).parse("quiz next \(misspelling)", now: now)
            XCTAssertEqual(calendar.component(.weekday, from: result.dueDate), weekday, misspelling)
            XCTAssertEqual(result.title, "Quiz", misspelling)
        }
    }

    func testEveryOtherWeekdayRecurrence() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-18T12:00:00Z"))
        let result = NaturalLanguageParser(calendar: calendar).parse("add a repeating math237 quiz every other Tuesday", now: now)

        XCTAssertEqual(result.title, "Math237 quiz")
        XCTAssertEqual(result.repeatRule, RepeatRule(interval: 2, unit: .week, weekday: 3))
        XCTAssertEqual(calendar.component(.weekday, from: result.dueDate), 3)
        XCTAssertEqual(result.repeatRule?.label, "every other tuesday")
    }

    func testWeekdayRecurrenceAdvancesOnTheRequestedWeekday() throws {
        let tuesday = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-22T16:30:00Z"))
        let rule = RepeatRule(interval: 2, unit: .week, weekday: 3)
        let next = rule.nextDate(after: tuesday, calendar: calendar)

        XCTAssertEqual(calendar.dateComponents([.day], from: tuesday, to: next).day, 14)
        XCTAssertEqual(calendar.component(.hour, from: next), 16)
        XCTAssertEqual(calendar.component(.minute, from: next), 30)
    }

    func testConversationalRelativeDatesAndTimes() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-18T12:00:00Z"))
        let parser = NaturalLanguageParser(calendar: calendar)

        let relative = parser.parse("submit report in three days at 16:30", now: now)
        XCTAssertEqual(calendar.component(.day, from: relative.dueDate), 21)
        XCTAssertEqual(calendar.component(.hour, from: relative.dueDate), 16)
        XCTAssertEqual(calendar.component(.minute, from: relative.dueDate), 30)
        XCTAssertEqual(relative.title, "Submit report")

        let ordinal = parser.parse("paper due September 22nd at noon", now: now)
        XCTAssertEqual(calendar.component(.day, from: ordinal.dueDate), 22)
        XCTAssertEqual(calendar.component(.hour, from: ordinal.dueDate), 12)
        XCTAssertEqual(ordinal.title, "Paper")
    }
}
