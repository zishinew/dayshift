import SwiftUI

struct ContentView: View {
    enum Page: String, CaseIterable {
        case today = "Today"
        case calendar = "Calendar"
    }

    @Environment(TaskStore.self) private var store
    @State private var page: Page = .today
    @State private var input = ""
    @State private var selectedDate = Date()
    @State private var displayedMonth = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()

    private let parser = NaturalLanguageParser()

    private var preview: ParsedTask? {
        input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : parser.parse(input)
    }

    private var displayDate: Date {
        page == .today ? Date() : selectedDate
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.black)

            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    capture

                    if page == .calendar {
                        calendar
                    }

                    taskSection
                }
                .frame(maxWidth: page == .today ? 680 : .infinity, alignment: .leading)
                .padding(.horizontal, page == .today ? 44 : 28)
                .padding(.vertical, 34)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color.white)
        .foregroundStyle(Color.black)
        .preferredColorScheme(.light)
    }

    private var header: some View {
        HStack(spacing: 28) {
            Text("DAYSHIFT")
                .font(.system(size: 14, weight: .semibold, design: .serif))
                .tracking(1.4)

            Spacer()

            ForEach(Page.allCases, id: \.self) { item in
                Button {
                    page = item
                } label: {
                    Text(item.rawValue)
                        .font(.system(size: 15, weight: page == item ? .semibold : .regular, design: .serif))
                        .overlay(alignment: .bottom) {
                            if page == item {
                                Rectangle().frame(height: 1).offset(y: 5)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 28)
        .frame(height: 58)
    }

    private var capture: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                TextField("What needs doing?", text: $input)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20, design: .serif))
                    .onSubmit(addTask)

                Button("Add", action: addTask)
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .buttonStyle(.plain)
                    .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
            .overlay(Rectangle().stroke(Color.black, lineWidth: 1))

            if let preview {
                Text("\(preview.title)  ·  \(preview.dueDate.formatted(date: .abbreviated, time: hasTime(preview.dueDate) ? .shortened : .omitted))  ·  \(preview.priority.rawValue)")
                    .font(.system(size: 13, design: .serif))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("Try “quiz next Wednesday” or “call Mum tomorrow at 6pm”.")
                    .font(.system(size: 13, design: .serif))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var calendar: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    moveMonth(by: -1)
                } label: {
                    Text("←")
                        .font(.system(size: 18, design: .serif))
                }
                .buttonStyle(.plain)
                .frame(width: 36, height: 36)
                .accessibilityLabel("Previous month")

                Spacer()

                Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                    .font(.system(size: 24, weight: .regular, design: .serif))

                Spacer()

                Button {
                    moveMonth(by: 1)
                } label: {
                    Text("→")
                        .font(.system(size: 18, design: .serif))
                }
                .buttonStyle(.plain)
                .frame(width: 36, height: 36)
                .accessibilityLabel("Next month")
            }
            .padding(.bottom, 18)

            LazyVGrid(columns: calendarColumns, spacing: 0) {
                ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { _, weekday in
                    Text(weekday)
                        .font(.system(size: 12, design: .serif))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                }
            }

            LazyVGrid(columns: calendarColumns, spacing: 0) {
                ForEach(monthDates, id: \.self) { date in
                    calendarDay(date)
                }
            }
            .overlay(Rectangle().stroke(Color.black.opacity(0.28), lineWidth: 0.5))
        }
        .frame(maxWidth: .infinity)
    }

    private var calendarColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    }

    private var weekdayLabels: [String] {
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        let first = max(0, Calendar.current.firstWeekday - 1)
        return Array(symbols[first...] + symbols[..<first])
    }

    private var monthDates: [Date] {
        let calendar = Calendar.current
        guard let month = calendar.dateInterval(of: .month, for: displayedMonth) else { return [] }
        let weekday = calendar.component(.weekday, from: month.start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -leading, to: month.start) ?? month.start
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }

    private func calendarDay(_ date: Date) -> some View {
        let calendar = Calendar.current
        let inMonth = calendar.isDate(date, equalTo: displayedMonth, toGranularity: .month)
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let dayTasks = store.tasks(on: date)

        return Button {
            selectedDate = date
            if !inMonth {
                displayedMonth = calendar.dateInterval(of: .month, for: date)?.start ?? date
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(date.formatted(.dateTime.day()))
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular, design: .serif))

                if let first = dayTasks.first {
                    Text(first.title)
                        .font(.system(size: 11, design: .serif))
                        .lineLimit(1)
                        .strikethrough(first.isComplete)
                        .opacity(first.isComplete ? 0.55 : 1)
                }

                if dayTasks.count > 1 {
                    Text("+\(dayTasks.count - 1) more")
                        .font(.system(size: 10, design: .serif))
                        .opacity(0.7)
                }

                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.black)
            .opacity(inMonth ? 1 : 0.3)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
            .padding(8)
            .background(Color.white)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.black.opacity(0.28))
                .frame(height: 0.5)
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.black.opacity(0.18))
                .frame(width: 0.5)
        }
        .overlay {
            if isSelected {
                Rectangle().stroke(Color.black, lineWidth: 1.5)
            }
        }
        .accessibilityLabel(calendarDayLabel(date, tasks: dayTasks))
    }

    private var taskSection: some View {
        let tasks = store.tasks(on: displayDate)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(page == .today ? "Today" : selectedDate.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.system(size: 34, weight: .regular, design: .serif))
                Spacer()
                Text("\(tasks.filter { !$0.isComplete }.count) open")
                    .font(.system(size: 13, design: .serif))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 14)

            Divider().overlay(Color.black)

            if tasks.isEmpty {
                Text("Nothing scheduled.")
                    .font(.system(size: 17, design: .serif))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 28)
            } else {
                ForEach(tasks) { task in
                    TaskRow(task: task)
                    Divider()
                }
            }
        }
    }

    private func addTask() {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        store.add(parser.parse(value))
        input = ""
    }

    private func moveMonth(by amount: Int) {
        let calendar = Calendar.current
        guard let date = calendar.date(byAdding: .month, value: amount, to: displayedMonth) else { return }
        displayedMonth = calendar.dateInterval(of: .month, for: date)?.start ?? date
        selectedDate = displayedMonth
    }

    private func calendarDayLabel(_ date: Date, tasks: [TaskItem]) -> String {
        let count = tasks.count
        return "\(date.formatted(date: .long, time: .omitted)), \(count) \(count == 1 ? "task" : "tasks")"
    }

    private func hasTime(_ date: Date) -> Bool {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return components.hour != 0 || components.minute != 0
    }
}

private struct TaskRow: View {
    @Environment(TaskStore.self) private var store
    let task: TaskItem

    var body: some View {
        HStack(spacing: 14) {
            Button {
                store.toggle(task)
            } label: {
                Image(systemName: task.isComplete ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(Color.black)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isComplete ? "Mark incomplete" : "Mark complete")

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.system(size: 18, design: .serif))
                    .strikethrough(task.isComplete)
                    .foregroundStyle(task.isComplete ? .secondary : .primary)

                Text(metadata)
                    .font(.system(size: 12, design: .serif))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                store.delete(task)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete \(task.title)")
        }
        .padding(.vertical, 15)
    }

    private var metadata: String {
        let time = Calendar.current.component(.hour, from: task.dueDate) == 0 && Calendar.current.component(.minute, from: task.dueDate) == 0
            ? "No time"
            : task.dueDate.formatted(date: .omitted, time: .shortened)
        return "\(time)  ·  \(task.priority.rawValue) priority"
    }
}
