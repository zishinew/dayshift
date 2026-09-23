import XCTest
@testable import DAYSHIFT

final class ReminderPlannerTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    func testTimedItemsAlertOneHourBeforeOrAtDueTimeWhenAddedLate() {
        let due = date("2026-09-24T16:00:00Z")
        let item = TaskItem(title: "Quiz", dueDate: due, priority: .medium, isEvent: true)
        let planner = ReminderPlanner(calendar: calendar)

        let early = planner.reminders(for: [item], now: date("2026-09-24T12:00:00Z"))
        XCTAssertEqual(early.first?.fireDate, date("2026-09-24T15:00:00Z"))
        XCTAssertEqual(early.first?.body, "starts in 1 hour")

        let late = planner.reminders(for: [item], now: date("2026-09-24T15:30:00Z"))
        XCTAssertEqual(late.first?.fireDate, due)
        XCTAssertEqual(late.first?.body, "starting now")
    }

    func testUntimedItemsAlertThePreviousMorningWithSameDayFallback() {
        let item = TaskItem(title: "Assignment", dueDate: date("2026-09-25T00:00:00Z"), priority: .medium)
        let planner = ReminderPlanner(calendar: calendar)

        let early = planner.reminders(for: [item], now: date("2026-09-23T12:00:00Z"))
        XCTAssertEqual(early.first?.fireDate, date("2026-09-24T09:00:00Z"))
        XCTAssertEqual(early.first?.body, "due tomorrow")

        let late = planner.reminders(for: [item], now: date("2026-09-24T12:00:00Z"))
        XCTAssertEqual(late.first?.fireDate, date("2026-09-25T09:00:00Z"))
        XCTAssertEqual(late.first?.body, "due today")
    }

    func testCompletedAndExpiredItemsDoNotSchedule() {
        let due = date("2026-09-22T12:00:00Z")
        let completed = TaskItem(title: "Done", dueDate: date("2026-09-25T12:00:00Z"), priority: .medium, isComplete: true)
        let expired = TaskItem(title: "Old", dueDate: due, priority: .medium)

        XCTAssertTrue(ReminderPlanner(calendar: calendar).reminders(
            for: [completed, expired], now: date("2026-09-23T12:00:00Z")
        ).isEmpty)
    }

    func testRecurringItemsShareCapacityWithOtherTasks() {
        let daily = TaskItem(
            title: "Daily review",
            dueDate: date("2026-09-24T09:00:00Z"),
            priority: .medium,
            repeatRule: RepeatRule(interval: 1, unit: .day)
        )
        let quiz = TaskItem(title: "Quiz", dueDate: date("2026-09-24T11:00:00Z"), priority: .medium, isEvent: true)
        let planned = ReminderPlanner(calendar: calendar, maximumPending: 3)
            .reminders(for: [daily, quiz], now: date("2026-09-23T12:00:00Z"))

        XCTAssertEqual(planned.count, 3)
        XCTAssertEqual(planned.map(\.title), ["daily review", "quiz", "daily review"])
        XCTAssertEqual(Set(planned.map(\.id)).count, 3)
    }
}
