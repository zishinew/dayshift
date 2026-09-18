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
    }

    func testUrgentTaskWithTime() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-18T12:00:00Z"))
        let result = NaturalLanguageParser(calendar: calendar).parse("Submit report tomorrow at 4:30pm urgent", now: now)
        XCTAssertEqual(result.title, "Submit report")
        XCTAssertEqual(calendar.component(.day, from: result.dueDate), 19)
        XCTAssertEqual(calendar.component(.hour, from: result.dueDate), 16)
        XCTAssertEqual(calendar.component(.minute, from: result.dueDate), 30)
        XCTAssertEqual(result.priority, .high)
    }
}
