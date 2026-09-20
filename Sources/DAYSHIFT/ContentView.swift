import SwiftUI

@MainActor
struct ContentView: View {
    private enum Page { case todo, calendar }

    @Environment(TaskStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page: Page = .todo
    @State private var input = ""
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var displayedMonth = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    @State private var feedback: String?

    private let interpreter = TaskCommandInterpreter()
    private let serif = "Times New Roman"
    private var motion: Animation? { reduceMotion ? nil : .easeInOut(duration: 0.18) }

    private var today: Date { Calendar.current.startOfDay(for: Date()) }
    private var todayTasks: [TaskItem] { store.tasks(on: today) }
    private var futureTasks: [TaskItem] { store.tasks(after: today) }
    private var agendaTasks: [TaskItem] { todayTasks + futureTasks }
    private var classSuggestion: ClassItem? { store.suggestedClass(for: input) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ZStack {
                    if page == .todo {
                        todoPage
                            .transition(.opacity)
                    } else {
                        calendarPage
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(motion, value: page)

                classPanel
            }

            commandBar
        }
        .background(Color.white)
        .foregroundStyle(Color.black)
        .preferredColorScheme(.light)
        .toolbar {
#if compiler(>=6.0)
            if #available(macOS 26.0, *) {
                ToolbarItem(placement: .principal) {
                    topToggle
                }
                .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .principal) {
                    topToggle
                }
            }
#else
            ToolbarItem(placement: .principal) {
                topToggle
            }
#endif
        }
        .background(WindowAccessor())
    }

    private var classPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("classes")
                .font(.custom(serif, size: 14))

            if store.classes.isEmpty {
                Text("none")
                    .font(.custom(serif, size: 11))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            } else {
                ForEach(store.classes.sorted { $0.code < $1.code }) { item in
                    Text(item.code.lowercased())
                        .font(.custom(serif, size: 12))
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }

            Spacer(minLength: 0)
        }
        .frame(width: 150, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 32)
        .padding(.leading, 20)
        .padding(.trailing, 38)
        .animation(motion, value: store.classes)
    }

    private var topToggle: some View {
        HStack {
            Spacer()
            HStack(spacing: 14) {
                modeButton("todo", active: page == .todo) { withAnimation(motion) { page = .todo } }
                Text("/").foregroundStyle(.secondary)
                modeButton("calendar", active: page == .calendar) { withAnimation(motion) { page = .calendar } }
            }
            Spacer()
        }
        .frame(width: 190, height: 28)
    }

    private func modeButton(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.custom(serif, size: 13))
            .fontWeight(active ? .semibold : .regular)
            .buttonStyle(.plain)
            .opacity(active ? 1 : 0.5)
            .animation(motion, value: active)
    }

    private var todoPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(today.formatted(.dateTime.weekday(.wide).month(.wide).day()).lowercased())
                    .font(.custom(serif, size: 22))
                    .padding(.bottom, 22)

                if todayTasks.isEmpty {
                    Text("no todos")
                        .font(.custom(serif, size: 15))
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                } else {
                    ForEach(todayTasks) { task in
                        TaskRow(task: task, serif: serif, showsDueDate: false) {
                            withAnimation(motion) { store.toggle(task) }
                        }
                        .transition(.opacity)
                    }
                }

                Text("upcoming")
                    .font(.custom(serif, size: 14))
                    .padding(.top, 34)
                    .padding(.bottom, 12)

                if futureTasks.isEmpty {
                    Text("nothing upcoming")
                        .font(.custom(serif, size: 12))
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                } else {
                    ForEach(futureTasks) { task in
                        TaskRow(task: task, serif: serif, showsDueDate: true) {
                            withAnimation(motion) { store.toggle(task) }
                        }
                        .transition(.opacity)
                    }
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, 38)
            .padding(.top, 30)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .animation(motion, value: agendaTasks)
        }
    }

    private var calendarPage: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack {
                    Button("←") { moveMonth(by: -1) }
                    Spacer()
                    Text(displayedMonth.formatted(.dateTime.month(.wide).year()).lowercased())
                        .font(.custom(serif, size: 18))
                        .contentTransition(.numericText())
                    Spacer()
                    Button("→") { moveMonth(by: 1) }
                }
                .font(.custom(serif, size: 15))
                .buttonStyle(.plain)
                .padding(.bottom, 24)

                LazyVGrid(columns: calendarColumns, spacing: 0) {
                    ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { _, weekday in
                        Text(weekday.lowercased())
                            .font(.custom(serif, size: 11))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 10)
                    }
                }

                LazyVGrid(columns: calendarColumns, spacing: 18) {
                    ForEach(monthDates, id: \.self) { date in calendarDay(date) }
                }
                .id(displayedMonth)
                .transition(.opacity)
            }
            .frame(maxWidth: 1040, alignment: .center)
            .padding(.horizontal, 38)
            .padding(.top, 30)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .top)
            .animation(motion, value: displayedMonth)
        }
    }

    private var calendarColumns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 0), count: 7) }

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
        let start = calendar.date(byAdding: .day, value: -leading, to: month.start) ?? month.start
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private func calendarDay(_ date: Date) -> some View {
        let calendar = Calendar.current
        let inMonth = calendar.isDate(date, equalTo: displayedMonth, toGranularity: .month)
        let selected = calendar.isDate(date, inSameDayAs: selectedDate)
        let tasks = store.tasks(on: date)

        return Button {
            withAnimation(motion) {
                selectedDate = date
                page = .todo
                if !inMonth { displayedMonth = calendar.dateInterval(of: .month, for: date)?.start ?? date }
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(date.formatted(.dateTime.day()))
                    .font(.custom(serif, size: 13))
                    .fontWeight(selected ? .semibold : .regular)
                ForEach(tasks.prefix(2)) { task in
                    Text(task.title.lowercased())
                        .font(.custom(serif, size: 10))
                        .lineLimit(1)
                        .opacity(task.isComplete ? 0.45 : 0.85)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.black)
            .opacity(inMonth ? 1 : 0.25)
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
            .overlay(alignment: .topLeading) {
                if selected {
                    Rectangle()
                        .frame(width: 18, height: 1)
                        .offset(y: -4)
                        .transition(.opacity.combined(with: .scale(scale: 0.7, anchor: .leading)))
                }
            }
        }
        .buttonStyle(.plain)
        .animation(motion, value: selected)
    }

    private var commandBar: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 12) {
                TextField("type anything…", text: $input)
                    .textFieldStyle(.plain)
                    .font(.custom(serif, size: 17))
                    .onSubmit(executeCommand)
                    .onChange(of: input) { _, _ in
                        withAnimation(motion) { feedback = nil }
                    }
                    .onKeyPress(.tab) {
                        guard let completion = store.completedClassInput(for: input) else { return .ignored }
                        withAnimation(motion) {
                            input = completion
                        }
                        return .handled
                    }
                Text("return ↵")
                    .font(.custom(serif, size: 10))
                    .foregroundStyle(.secondary)
            }
            .frame(height: 32)

            if let feedback {
                Text(feedback.lowercased())
                    .font(.custom(serif, size: 10))
                    .foregroundStyle(Color.black)
                    .lineLimit(2)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else if !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let classSuggestion {
                    Text("tab ↹ add \(classSuggestion.code.lowercased()) · \(classSuggestion.name.lowercased())")
                        .font(.custom(serif, size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .transition(.opacity)
                } else {
                    Text(interpreter.interpret(input).preview.lowercased())
                        .font(.custom(serif, size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .transition(.opacity)
                }
            } else {
                Text("try “quiz next wednesday” or “move quiz to friday”")
                    .font(.custom(serif, size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 38)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .animation(motion, value: feedback)
        .animation(motion, value: classSuggestion?.id)
    }

    private func executeCommand() {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        let command = interpreter.interpret(value)

        withAnimation(motion) {
            switch command {
            case .add(let task): store.add(task); selectedDate = Calendar.current.startOfDay(for: task.dueDate); page = .todo; feedback = "added “\(task.title)”."
            case .addClasses(let codes): store.addClasses(codes); feedback = "saved \(codes.map { $0.lowercased() }.joined(separator: ", "))."
            case .repeatTask(let query, let rule): feedback = store.setRepeat(matching: query, to: rule).map { "\($0.lowercased()) will repeat \(rule.label)." } ?? notFound(query)
            case .complete(let query): feedback = mutationFeedback(store.setCompletion(matching: query, to: true), verb: "completed", query: query)
            case .reopen(let query): feedback = mutationFeedback(store.setCompletion(matching: query, to: false), verb: "reopened", query: query)
            case .delete(let query): feedback = mutationFeedback(store.delete(matching: query), verb: "deleted", query: query)
            case .rename(let query, let title): feedback = store.rename(matching: query, to: title).map { "renamed task to “\($0)”." } ?? notFound(query)
            case .setPriority(let query, let priority): feedback = store.setPriority(matching: query, to: priority).map { "set “\($0)” to \(priority.rawValue.lowercased()) priority." } ?? notFound(query)
            case .reschedule(let query, let date): feedback = store.reschedule(matching: query, to: date).map { "moved “\($0)” to \(date.formatted(date: .abbreviated, time: hasTime(date) ? .shortened : .omitted))." } ?? notFound(query)
            case .clearCompleted: let count = store.clearCompleted(); feedback = count == 0 ? "no completed tasks to delete." : "deleted \(count) completed tasks."
            case .showToday: selectedDate = Calendar.current.startOfDay(for: Date()); page = .todo; feedback = "showing today."
            case .showDate(let date): selectedDate = Calendar.current.startOfDay(for: date); displayedMonth = Calendar.current.dateInterval(of: .month, for: date)?.start ?? date; page = .todo; feedback = "showing \(date.formatted(date: .long, time: .omitted))."
            case .showCalendar: page = .calendar; feedback = "showing calendar."
            case .nextMonth: page = .calendar; moveMonth(by: 1); feedback = "showing next month."
            case .previousMonth: page = .calendar; moveMonth(by: -1); feedback = "showing previous month."
            case .help: feedback = "try “complete the quiz”, “priority quiz high”, “move quiz to friday”, or “show next tuesday”."
            }
            input = ""
        }
    }

    private func moveMonth(by amount: Int) {
        let calendar = Calendar.current
        guard let date = calendar.date(byAdding: .month, value: amount, to: displayedMonth) else { return }
        withAnimation(motion) {
            displayedMonth = calendar.dateInterval(of: .month, for: date)?.start ?? date
        }
    }

    private func mutationFeedback(_ title: String?, verb: String, query: String) -> String { title.map { "\(verb) “\($0)”." } ?? notFound(query) }
    private func notFound(_ query: String) -> String { "no task matches “\(query)”." }
    private func hasTime(_ date: Date) -> Bool { let p = Calendar.current.dateComponents([.hour, .minute], from: date); return p.hour != 0 || p.minute != 0 }
}

private struct TaskRow: View {
    let task: TaskItem
    let serif: String
    let showsDueDate: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: task.isComplete ? "checkmark.square" : "square")
                    .font(.system(size: 13, weight: .regular))
                    .frame(width: 14, height: 14)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isComplete ? "Mark incomplete" : "Mark complete")
            Text(task.title.lowercased())
                .font(.custom(serif, size: 16))
                .strikethrough(task.isComplete)
                .foregroundStyle(task.isComplete ? .secondary : .primary)
            Spacer()
            Text(metadata.lowercased())
                .font(.custom(serif, size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
    }

    private var metadata: String {
        let calendar = Calendar.current
        let time = calendar.component(.hour, from: task.dueDate) == 0 && calendar.component(.minute, from: task.dueDate) == 0 ? "no time" : task.dueDate.formatted(date: .omitted, time: .shortened)
        let datePart = showsDueDate ? task.dueDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()).lowercased() + "  ·  " : ""
        let classPart = task.classCode.map { "  ·  \($0.lowercased())" } ?? ""
        let repeatPart = task.repeatRule.map { "  ·  \($0.label)" } ?? ""
        return "\(datePart)\(time)  ·  \(task.priority.rawValue)\(classPart)\(repeatPart)"
    }
}
