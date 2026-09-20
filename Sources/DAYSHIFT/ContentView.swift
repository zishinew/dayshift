import SwiftUI

@MainActor
struct ContentView: View {
    private enum Page { case todo, calendar, settings }

    @Environment(TaskStore.self) private var store
    @Environment(AppearanceSettings.self) private var appearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page: Page = .todo
    @State private var input = ""
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var displayedMonth = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    @State private var feedback: String?

    private let interpreter = TaskCommandInterpreter()
    private var serif: String { appearance.fontName }
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
                    } else if page == .calendar {
                        calendarPage
                            .transition(.opacity)
                    } else {
                        SettingsPage()
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(motion, value: page)

                classPanel
            }

            commandBar
        }
        .background(appearance.backgroundColor)
        .foregroundStyle(appearance.textColor)
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
        VStack(alignment: .leading, spacing: 0) {
            Text("classes")
                .font(.custom(serif, size: appearance.scaled(16)))
                .padding(.bottom, 18)

            if store.classes.isEmpty {
                Text("no classes")
                    .font(.custom(serif, size: appearance.scaled(13)))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            } else {
                ForEach(store.classes.sorted { $0.code < $1.code }) { item in
                    classRow(item)
                        .padding(.bottom, 17)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }

            Spacer(minLength: 0)
        }
        .frame(width: 190, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .padding(.top, 32)
        .padding(.leading, 24)
        .padding(.trailing, 38)
        .animation(motion, value: store.classes)
        .animation(motion, value: store.tasks)
    }

    private func classRow(_ item: ClassItem) -> some View {
        let tasks = store.tasks.filter {
            !$0.isComplete
                && $0.dueDate >= today
                && $0.classCode?.caseInsensitiveCompare(item.code) == .orderedSame
        }
        let nextTask = tasks.min { $0.dueDate < $1.dueDate }

        return VStack(alignment: .leading, spacing: 3) {
            Text(item.code.lowercased())
                .font(.custom(serif, size: appearance.scaled(15)))

            Text(classSummary(taskCount: tasks.count, nextTask: nextTask))
                .font(.custom(serif, size: appearance.scaled(12)))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
    }

    private func classSummary(taskCount: Int, nextTask: TaskItem?) -> String {
        let count = taskCount == 1 ? "1 task" : "\(taskCount) tasks"
        guard let nextTask else { return count }
        let date = nextTask.dueDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()).lowercased()
        return "\(count)  ·  next \(date)"
    }

    private var topToggle: some View {
        HStack {
            Spacer()
            HStack(spacing: 14) {
                modeButton("todo", active: page == .todo) { withAnimation(motion) { page = .todo } }
                Text("/").foregroundStyle(.secondary)
                modeButton("calendar", active: page == .calendar) { withAnimation(motion) { page = .calendar } }
                Text("/").foregroundStyle(.secondary)
                modeButton("settings", active: page == .settings) { withAnimation(motion) { page = .settings } }
            }
            Spacer()
        }
        .frame(width: 280, height: 28)
    }

    private func modeButton(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.custom(serif, size: appearance.scaled(15)))
            .fontWeight(active ? .semibold : .regular)
            .buttonStyle(.plain)
            .modifier(SubtleHover())
            .opacity(active ? 1 : 0.5)
            .animation(motion, value: active)
    }

    private var todoPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(today.formatted(.dateTime.weekday(.wide).month(.wide).day()).lowercased())
                    .font(.custom(serif, size: appearance.scaled(24)))
                    .padding(.bottom, 22)

                if todayTasks.isEmpty {
                    Text("no tasks today")
                        .font(.custom(serif, size: appearance.scaled(17)))
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                } else {
                    if todayTasks.contains(where: { $0.isEvent }) {
                        Text("events")
                            .font(.custom(serif, size: appearance.scaled(15)))
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 3)
                        ForEach(todayTasks.filter(\.isEvent)) { task in taskRow(task, showsDueDate: false) }
                    }
                    if todayTasks.contains(where: { !$0.isEvent }) {
                        Text("tasks")
                            .font(.custom(serif, size: appearance.scaled(15)))
                            .foregroundStyle(.secondary)
                            .padding(.top, todayTasks.contains(where: { $0.isEvent }) ? 18 : 0)
                            .padding(.bottom, 3)
                        ForEach(todayTasks.filter { !$0.isEvent }) { task in taskRow(task, showsDueDate: false) }
                    }
                }

                Text("upcoming")
                    .font(.custom(serif, size: appearance.scaled(16)))
                    .padding(.top, 34)
                    .padding(.bottom, 12)

                if futureTasks.isEmpty {
                    Text("nothing upcoming")
                        .font(.custom(serif, size: appearance.scaled(14)))
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                } else {
                    if futureTasks.contains(where: { $0.isEvent }) {
                        Text("events")
                            .font(.custom(serif, size: appearance.scaled(15)))
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 3)
                        ForEach(futureTasks.filter(\.isEvent)) { task in taskRow(task, showsDueDate: true) }
                    }
                    if futureTasks.contains(where: { !$0.isEvent }) {
                        Text("tasks")
                            .font(.custom(serif, size: appearance.scaled(15)))
                            .foregroundStyle(.secondary)
                            .padding(.top, futureTasks.contains(where: { $0.isEvent }) ? 18 : 0)
                            .padding(.bottom, 3)
                        ForEach(futureTasks.filter { !$0.isEvent }) { task in taskRow(task, showsDueDate: true) }
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

    @ViewBuilder
    private func taskRow(_ task: TaskItem, showsDueDate: Bool) -> some View {
        TaskRow(
            task: task,
            serif: serif,
            showsDueDate: showsDueDate,
            onToggle: { withAnimation(motion) { store.toggle(task) } },
            onRename: { _ = store.rename(task, to: $0) },
            onDateChange: { _ = store.setDate(task, to: $0) },
            onPriorityChange: { _ = store.setPriority(task, to: $0) },
            onRepeatChange: { _ = store.setRepeat(task, to: $0) }
        )
        .transition(.opacity)
    }

    private var calendarPage: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack {
                    Button("←") { moveMonth(by: -1) }
                        .modifier(SubtleHover())
                    Spacer()
                    Text(displayedMonth.formatted(.dateTime.month(.wide).year()).lowercased())
                        .font(.custom(serif, size: appearance.scaled(20)))
                        .contentTransition(.numericText())
                    Spacer()
                    Button("→") { moveMonth(by: 1) }
                        .modifier(SubtleHover())
                }
                .font(.custom(serif, size: appearance.scaled(17)))
                .buttonStyle(.plain)
                .padding(.bottom, 24)

                LazyVGrid(columns: calendarColumns, spacing: 0) {
                    ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { _, weekday in
                        Text(weekday.lowercased())
                            .font(.custom(serif, size: appearance.scaled(13)))
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
                    .font(.custom(serif, size: appearance.scaled(15)))
                    .fontWeight(selected ? .semibold : .regular)
                ForEach(tasks.prefix(2)) { task in
                    Text(task.title.lowercased())
                        .font(.custom(serif, size: appearance.scaled(12)))
                        .lineLimit(1)
                        .opacity(task.isComplete ? 0.45 : 0.85)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(appearance.textColor)
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
        .modifier(SubtleHover())
        .animation(motion, value: selected)
    }

    private var commandBar: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 12) {
                TextField("type anything…", text: $input)
                    .textFieldStyle(.plain)
                    .font(.custom(serif, size: appearance.scaled(19)))
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
                    .font(.custom(serif, size: appearance.scaled(12)))
                    .foregroundStyle(.secondary)
            }
            .frame(height: 32)

            if appearance.showCommandHints {
                if let feedback {
                Text(feedback.lowercased())
                        .font(.custom(serif, size: appearance.scaled(12)))
                    .foregroundStyle(appearance.textColor)
                    .lineLimit(2)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else if !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if let classSuggestion {
                    Text("tab ↹ add \(classSuggestion.code.lowercased()) · \(classSuggestion.name.lowercased())")
                        .font(.custom(serif, size: appearance.scaled(12)))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .transition(.opacity)
                } else {
                    Text(interpreter.interpret(input).preview.lowercased())
                        .font(.custom(serif, size: appearance.scaled(12)))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .transition(.opacity)
                }
                } else {
                Text("try “quiz next wednesday” or “move quiz to friday”")
                        .font(.custom(serif, size: appearance.scaled(12)))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, 38)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
        .background(appearance.backgroundColor)
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
            case .stopRepeating(let query): feedback = store.clearRepeat(matching: query).map { "\($0.lowercased()) will no longer repeat." } ?? notFound(query)
            case .complete(let query): feedback = mutationFeedback(store.setCompletion(matching: query, to: true), verb: "completed", query: query)
            case .reopen(let query): feedback = mutationFeedback(store.setCompletion(matching: query, to: false), verb: "reopened", query: query)
            case .delete(let query): feedback = mutationFeedback(store.delete(matching: query), verb: "deleted", query: query)
            case .rename(let query, let title): feedback = store.rename(matching: query, to: title).map { "renamed task to “\($0)”." } ?? notFound(query)
            case .setPriority(let query, let priority): feedback = store.setPriority(matching: query, to: priority).map { "set “\($0)” to \(priority.rawValue.lowercased()) priority." } ?? notFound(query)
            case .reschedule(let query, let date): feedback = store.reschedule(matching: query, to: date).map { "moved “\($0)” to \(date.formatted(date: .abbreviated, time: hasTime(date) ? .shortened : .omitted))." } ?? notFound(query)
            case .shiftDate(let query, let amount, let unit): feedback = store.shiftDate(matching: query, amount: amount, unit: unit).map { "moved “\($0)” \(abs(amount)) \(unit.rawValue)\(abs(amount) == 1 ? "" : "s") \(amount < 0 ? "earlier" : "later")." } ?? notFound(query)
            case .setTime(let query, let hour, let minute): feedback = store.setTime(matching: query, hour: hour, minute: minute).map { "set “\($0)” to \(formattedTime(hour: hour, minute: minute))." } ?? notFound(query)
            case .clearTime(let query): feedback = store.clearTime(matching: query).map { "removed the time from “\($0)”." } ?? notFound(query)
            case .setClass(let query, let code): feedback = store.setClass(matching: query, to: code).map { "set “\($0)” to \(code.lowercased())." } ?? notFound(query)
            case .clearClass(let query): feedback = store.clearClass(matching: query).map { "removed the class from “\($0)”." } ?? notFound(query)
            case .clearCompleted: let count = store.clearCompleted(); feedback = count == 0 ? "no completed tasks to delete." : "deleted \(count) completed tasks."
            case .showToday: selectedDate = Calendar.current.startOfDay(for: Date()); page = .todo; feedback = "showing today."
            case .showDate(let date): selectedDate = Calendar.current.startOfDay(for: date); displayedMonth = Calendar.current.dateInterval(of: .month, for: date)?.start ?? date; page = .todo; feedback = "showing \(date.formatted(date: .long, time: .omitted))."
            case .showCalendar: page = .calendar; feedback = "showing calendar."
            case .nextMonth: page = .calendar; moveMonth(by: 1); feedback = "showing next month."
            case .previousMonth: page = .calendar; moveMonth(by: -1); feedback = "showing previous month."
            case .help: feedback = "try “rename quiz to midterm”, “move quiz to friday”, “priority quiz high”, or “assign quiz to math237”."
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
    private func formattedTime(hour: Int, minute: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
        return date.formatted(date: .omitted, time: .shortened).lowercased()
    }
}

private struct TaskRow: View {
    private enum DetailEditor: Equatable { case date, priority, repeatRule }

    let task: TaskItem
    let serif: String
    let showsDueDate: Bool
    let onToggle: () -> Void
    let onRename: (String) -> Void
    let onDateChange: (Date) -> Void
    let onPriorityChange: (TaskPriority) -> Void
    let onRepeatChange: (RepeatRule?) -> Void
    @Environment(AppearanceSettings.self) private var appearance

    @State private var isEditingTitle = false
    @State private var titleDraft = ""
    @State private var detailEditor: DetailEditor?
    @FocusState private var titleIsFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if !task.isEvent {
                Button(action: onToggle) {
                    Image(systemName: task.isComplete ? "checkmark.square" : "square")
                        .font(.system(size: 15, weight: .regular))
                        .frame(width: 16, height: 16)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .modifier(SubtleHover())
                .accessibilityLabel(task.isComplete ? "Mark incomplete" : "Mark complete")
                .padding(.top, 2)
            }

            VStack(alignment: .leading, spacing: 3) {
                if isEditingTitle {
                    TextField("task title", text: $titleDraft)
                        .textFieldStyle(.plain)
                        .font(.custom(serif, size: appearance.scaled(18)))
                        .focused($titleIsFocused)
                        .onSubmit(commitTitle)
                        .onKeyPress(.escape) {
                            cancelEditing()
                            return .handled
                        }
                        .onChange(of: titleIsFocused) { _, focused in
                            if !focused { commitTitle() }
                        }
                        .transition(.opacity)
                } else {
                    Text(task.title.lowercased())
                        .font(.custom(serif, size: appearance.scaled(18)))
                        .strikethrough(task.isComplete)
                        .foregroundStyle(task.isComplete ? .secondary : .primary)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: beginEditing)
                        .help("click to rename")
                        .modifier(SubtleHover())
                        .transition(.opacity)
                }

                detailLine

                if let detailEditor {
                    detailEditorView(detailEditor)
                        .padding(.top, 7)
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .topLeading)))
                        .zIndex(2)
                }
            }

            Spacer()
        }
        .padding(.vertical, appearance.rowSpacing)
        .zIndex(detailEditor == nil ? 0 : 1)
        .animation(.easeInOut(duration: 0.15), value: detailEditor)
    }

    private var detailLine: some View {
        HStack(spacing: 7) {
            detailButton(dateLabel, editor: .date)

            if hasTime {
                detailSeparator
                Text(task.dueDate.formatted(date: .omitted, time: .shortened).lowercased())
            }

            detailSeparator
            detailButton(task.priority.rawValue.lowercased(), editor: .priority)

            if let classCode = task.classCode, !task.title.localizedCaseInsensitiveContains(classCode) {
                detailSeparator
                Text(classCode.lowercased())
            }

            detailSeparator
            detailButton(repeatLabel, editor: .repeatRule)
        }
        .font(.custom(serif, size: appearance.scaled(13)))
        .foregroundStyle(.tertiary)
    }

    private var detailSeparator: some View {
        Text("·")
            .accessibilityHidden(true)
    }

    private func detailButton(_ title: String, editor: DetailEditor) -> some View {
        Button(title.lowercased()) {
            withAnimation(.easeInOut(duration: 0.15)) {
                detailEditor = detailEditor == editor ? nil : editor
            }
        }
        .buttonStyle(.plain)
        .modifier(SubtleHover())
        .foregroundStyle(detailEditor == editor ? appearance.textColor : Color.secondary)
    }

    @ViewBuilder
    private func detailEditorView(_ editor: DetailEditor) -> some View {
        switch editor {
        case .date:
            CompactCalendar(selectedDate: task.dueDate, serif: serif) { date in
                onDateChange(date)
                detailEditor = nil
            }
            .frame(width: 238)
            .modifier(DetailPanel())
        case .priority:
            VStack(alignment: .leading, spacing: 0) {
                ForEach(TaskPriority.allCases, id: \.self) { priority in
                    detailChoice(priority.rawValue.lowercased(), selected: task.priority == priority) {
                        onPriorityChange(priority)
                        detailEditor = nil
                    }
                }
            }
            .frame(width: 116, alignment: .leading)
            .modifier(DetailPanel())
        case .repeatRule:
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(repeatChoices.enumerated()), id: \.offset) { _, choice in
                    detailChoice(choice.label, selected: repeatChoiceIsSelected(choice.rule)) {
                        onRepeatChange(choice.rule)
                        detailEditor = nil
                    }
                }
            }
            .frame(width: 178, alignment: .leading)
            .modifier(DetailPanel())
        }
    }

    private func detailChoice(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Text(label.lowercased())
                Spacer(minLength: 8)
                if selected { Text("·") }
            }
            .font(.custom(serif, size: appearance.scaled(13)))
            .contentShape(Rectangle())
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .modifier(SubtleHover())
    }

    private var repeatChoices: [(label: String, rule: RepeatRule?)] {
        let weekday = Calendar.current.component(.weekday, from: task.dueDate)
        let weekdayName = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"][weekday - 1]
        return [
            ("does not repeat", nil),
            ("every day", RepeatRule(interval: 1, unit: .day)),
            ("every \(weekdayName)", RepeatRule(interval: 1, unit: .week, weekday: weekday)),
            ("every other \(weekdayName)", RepeatRule(interval: 2, unit: .week, weekday: weekday)),
            ("every month", RepeatRule(interval: 1, unit: .month))
        ]
    }

    private var repeatLabel: String {
        guard let rule = task.repeatRule else { return "repeat" }
        guard rule.unit == .week, rule.weekday == nil else { return rule.label }
        let weekday = Calendar.current.component(.weekday, from: task.dueDate)
        let name = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"][weekday - 1]
        if rule.interval == 1 { return "every \(name)" }
        if rule.interval == 2 { return "every other \(name)" }
        return rule.label
    }

    private func repeatChoiceIsSelected(_ choice: RepeatRule?) -> Bool {
        if task.repeatRule == choice { return true }
        guard let current = task.repeatRule, let choice,
              current.unit == .week, current.weekday == nil,
              choice.unit == .week, choice.interval == current.interval else { return false }
        return choice.weekday == Calendar.current.component(.weekday, from: task.dueDate)
    }

    private func beginEditing() {
        titleDraft = task.title
        isEditingTitle = true
        titleIsFocused = true
    }

    private func commitTitle() {
        guard isEditingTitle else { return }
        let title = titleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        isEditingTitle = false
        titleIsFocused = false
        if !title.isEmpty, title != task.title {
            onRename(title)
        }
    }

    private func cancelEditing() {
        titleDraft = task.title
        isEditingTitle = false
        titleIsFocused = false
    }

    private var hasTime: Bool {
        let calendar = Calendar.current
        return calendar.component(.hour, from: task.dueDate) != 0 || calendar.component(.minute, from: task.dueDate) != 0
    }

    private var dateLabel: String {
        showsDueDate ? task.dueDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) : "today"
    }
}

private struct DetailPanel: ViewModifier {
    @Environment(AppearanceSettings.self) private var appearance

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(appearance.backgroundColor)
            .overlay {
                Rectangle().stroke(appearance.textColor.opacity(0.13), lineWidth: 1)
            }
            .shadow(color: appearance.textColor.opacity(0.08), radius: 8, y: 3)
    }
}

private struct SubtleHover: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? 1.025 : 1)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

private struct CompactCalendar: View {
    @Environment(AppearanceSettings.self) private var appearance
    let selectedDate: Date
    let serif: String
    let onSelect: (Date) -> Void
    @State private var displayedMonth: Date

    init(selectedDate: Date, serif: String, onSelect: @escaping (Date) -> Void) {
        self.selectedDate = selectedDate
        self.serif = serif
        self.onSelect = onSelect
        let start = Calendar.current.dateInterval(of: .month, for: selectedDate)?.start ?? selectedDate
        _displayedMonth = State(initialValue: start)
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button("←") { moveMonth(-1) }
                    .modifier(SubtleHover())
                Spacer()
                Text(displayedMonth.formatted(.dateTime.month(.wide).year()).lowercased())
                    .font(.custom(serif, size: appearance.scaled(14)))
                Spacer()
                Button("→") { moveMonth(1) }
                    .modifier(SubtleHover())
            }
            .buttonStyle(.plain)

            LazyVGrid(columns: columns, spacing: 5) {
                ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { _, day in
                    Text(day.lowercased())
                        .font(.custom(serif, size: appearance.scaled(10)))
                        .foregroundStyle(.secondary)
                }

                ForEach(monthDates, id: \.self) { date in
                    let inMonth = Calendar.current.isDate(date, equalTo: displayedMonth, toGranularity: .month)
                    let selected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
                    Button {
                        onSelect(date)
                    } label: {
                        Text(date.formatted(.dateTime.day()))
                            .font(.custom(serif, size: appearance.scaled(12)))
                            .fontWeight(selected ? .semibold : .regular)
                            .frame(width: 24, height: 23)
                            .overlay(alignment: .bottom) {
                                if selected { Rectangle().frame(height: 1) }
                            }
                    }
                    .buttonStyle(.plain)
                    .modifier(SubtleHover())
                    .opacity(inMonth ? 1 : 0.25)
                }
            }
        }
    }

    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 0), count: 7) }

    private var weekdayLabels: [String] {
        let calendar = Calendar.current
        let labels = calendar.veryShortStandaloneWeekdaySymbols
        let first = max(0, calendar.firstWeekday - 1)
        return Array(labels[first...] + labels[..<first])
    }

    private var monthDates: [Date] {
        let calendar = Calendar.current
        guard let month = calendar.dateInterval(of: .month, for: displayedMonth) else { return [] }
        let leading = (calendar.component(.weekday, from: month.start) - calendar.firstWeekday + 7) % 7
        let start = calendar.date(byAdding: .day, value: -leading, to: month.start) ?? month.start
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private func moveMonth(_ amount: Int) {
        guard let date = Calendar.current.date(byAdding: .month, value: amount, to: displayedMonth) else { return }
        displayedMonth = Calendar.current.dateInterval(of: .month, for: date)?.start ?? date
    }
}
