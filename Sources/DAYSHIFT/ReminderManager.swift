import Foundation
import Observation
import UserNotifications

struct PlannedReminder: Equatable {
    let id: String
    let title: String
    let body: String
    let fireDate: Date
    let occurrenceDate: Date

    var signature: String {
        "\(title)|\(body)|\(fireDate.timeIntervalSince1970)|\(occurrenceDate.timeIntervalSince1970)"
    }
}

struct ReminderPlanner {
    let calendar: Calendar
    let maximumPending: Int

    init(calendar: Calendar = .current, maximumPending: Int = 60) {
        self.calendar = calendar
        self.maximumPending = maximumPending
    }

    func reminders(for tasks: [TaskItem], now: Date = Date()) -> [PlannedReminder] {
        guard maximumPending > 0 else { return [] }
        let horizon = calendar.date(byAdding: .day, value: 180, to: now) ?? now
        var reminders: [PlannedReminder] = []

        for task in tasks where !task.isComplete {
            var occurrence = task.dueDate
            var iterations = 0
            var plannedForTask = 0
            while occurrence <= horizon && iterations < 10_000 && plannedForTask < maximumPending {
                if let reminder = reminder(for: task, occurrence: occurrence, now: now) {
                    reminders.append(reminder)
                    plannedForTask += 1
                }
                guard let rule = task.repeatRule else { break }
                let next = rule.nextDate(after: occurrence, calendar: calendar)
                guard next > occurrence else { break }
                occurrence = next
                iterations += 1
            }
        }

        return Array(reminders.sorted {
            if $0.fireDate != $1.fireDate { return $0.fireDate < $1.fireDate }
            return $0.id < $1.id
        }.prefix(maximumPending))
    }

    private func reminder(for task: TaskItem, occurrence: Date, now: Date) -> PlannedReminder? {
        let components = calendar.dateComponents([.hour, .minute], from: occurrence)
        let hasTime = components.hour != 0 || components.minute != 0
        let fireDate: Date
        let body: String

        if hasTime {
            guard occurrence > now else { return nil }
            let advance = occurrence.addingTimeInterval(-3_600)
            fireDate = advance > now ? advance : occurrence
            body = task.isEvent
                ? (advance > now ? "starts in 1 hour" : "starting now")
                : (advance > now ? "due in 1 hour" : "due now")
        } else {
            let dueMorning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: occurrence)
                ?? calendar.startOfDay(for: occurrence)
            let previousMorning = calendar.date(byAdding: .day, value: -1, to: dueMorning) ?? dueMorning
            if previousMorning > now {
                fireDate = previousMorning
                body = task.isEvent ? "happening tomorrow" : "due tomorrow"
            } else if dueMorning > now {
                fireDate = dueMorning
                body = task.isEvent ? "happening today" : "due today"
            } else {
                return nil
            }
        }

        let occurrenceID = Int(occurrence.timeIntervalSince1970)
        return PlannedReminder(
            id: "dayshift.reminder.\(task.id.uuidString).\(occurrenceID)",
            title: task.title.lowercased(),
            body: body,
            fireDate: fireDate,
            occurrenceDate: occurrence
        )
    }
}

private final class ReminderPresentationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

@MainActor
@Observable
final class ReminderManager {
    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "remindersEnabled")
            queueSync()
        }
    }
    private(set) var statusMessage: String?

    @ObservationIgnored private let center: UNUserNotificationCenter
    @ObservationIgnored private let presentationDelegate = ReminderPresentationDelegate()
    @ObservationIgnored private var tasks: [TaskItem] = []
    @ObservationIgnored private var syncGeneration = 0
    @ObservationIgnored private var lastSync: Task<Void, Never>?
    @ObservationIgnored private let planner = ReminderPlanner()

    init() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.object(forKey: "remindersEnabled") == nil
            ? true
            : defaults.bool(forKey: "remindersEnabled")
        center = UNUserNotificationCenter.current()
        center.delegate = presentationDelegate
    }

    func update(tasks: [TaskItem]) {
        self.tasks = tasks
        queueSync()
    }

    private func queueSync() {
        syncGeneration += 1
        let generation = syncGeneration
        let previous = lastSync
        lastSync = Task { [weak self] in
            await previous?.value
            await self?.sync(generation: generation)
        }
    }

    private func sync(generation: Int) async {
        guard generation == syncGeneration else { return }
        let desired = isEnabled ? planner.reminders(for: tasks) : []
        var settings = await center.notificationSettings()
        guard generation == syncGeneration else { return }

        if isEnabled && !desired.isEmpty && settings.authorizationStatus == .notDetermined {
            do {
                _ = try await center.requestAuthorization(options: [.alert, .sound])
                settings = await center.notificationSettings()
            } catch {
                statusMessage = "could not request notification permission"
                return
            }
        }

        guard generation == syncGeneration else { return }
        let authorized = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
        statusMessage = isEnabled && settings.authorizationStatus == .denied
            ? "allow dayshift notifications in macos settings"
            : nil

        let pending = await center.pendingNotificationRequests()
        guard generation == syncGeneration else { return }
        let ours = pending.filter { $0.identifier.hasPrefix("dayshift.reminder.") }
        let desiredByID = Dictionary(uniqueKeysWithValues: (authorized ? desired : []).map { ($0.id, $0) })
        let staleIDs = ours.map(\.identifier).filter { desiredByID[$0] == nil }
        if !staleIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: staleIDs)
        }
        guard authorized && isEnabled else { return }

        let pendingByID = Dictionary(uniqueKeysWithValues: ours.map { ($0.identifier, $0) })
        for reminder in desired {
            guard generation == syncGeneration else { return }
            if pendingByID[reminder.id]?.content.userInfo["dayshiftSignature"] as? String == reminder.signature {
                continue
            }

            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            content.userInfo = ["dayshiftSignature": reminder.signature]

            var components = calendarComponents(for: reminder.fireDate)
            components.calendar = Calendar.current
            components.timeZone = Calendar.current.timeZone
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)
            do {
                try await center.add(request)
            } catch {
                statusMessage = "could not schedule an alert"
            }
        }
    }

    private func calendarComponents(for date: Date) -> DateComponents {
        Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    }
}
