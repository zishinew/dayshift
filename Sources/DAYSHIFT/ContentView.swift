import SwiftUI

private enum TutorialTarget: Hashable {
    case commandBar, taskTitle(UUID), classes, calendar
}

private enum TaskDetailEditor: Equatable {
    case date, priority, repeatRule
}

private struct OpenTaskDetail: Equatable {
    let taskID: UUID
    let editor: TaskDetailEditor
}

private struct TutorialAnchorKey: PreferenceKey {
    static var defaultValue: [TutorialTarget: Anchor<CGRect>] = [:]

    static func reduce(value: inout [TutorialTarget: Anchor<CGRect>], nextValue: () -> [TutorialTarget: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct TutorialDimmer: View {
    let spotlight: CGRect

    var body: some View {
        Color.black.opacity(0.48)
            .mask {
                Rectangle()
                    .fill(.white)
                    .overlay {
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .fill(.black)
                            .frame(width: spotlight.width, height: spotlight.height)
                            .position(x: spotlight.midX, y: spotlight.midY)
                            .blur(radius: 18)
                    }
                    .compositingGroup()
                    .luminanceToAlpha()
            }
    }
}

@MainActor
struct ContentView: View {
    private enum Page { case todo, calendar, settings }

    @Environment(TaskStore.self) private var store
    @Environment(AppearanceSettings.self) private var appearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("hasCompletedTutorial") private var hasCompletedTutorial = false
    @State private var page: Page = .todo
    @State private var tutorialStep = 0
    @State private var tutorialQuizID: UUID?
    @State private var tutorialTaskID: UUID?
    @State private var tutorialTaskTitleFrame = CGRect.zero
    @State private var openTaskDetail: OpenTaskDetail?
    @State private var input = ""
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var displayedMonth = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    @State private var calendarTransitionID = UUID()
    @State private var calendarDragOffset: CGFloat = 0
    @State private var calendarSettlingDirection = 0
    @State private var calendarViewportHeight: CGFloat = 700
    @State private var feedback: String?
    @FocusState private var commandBarIsFocused: Bool

    private let interpreter = TaskCommandInterpreter()
    private let classPanelWidth: CGFloat = 252
    private var serif: String { appearance.fontName }
    private var motion: Animation? { reduceMotion ? nil : .easeInOut(duration: 0.18) }
    private var calendarMotion: Animation? {
        reduceMotion ? nil : .timingCurve(0.22, 0.88, 0.28, 1, duration: 0.46)
    }

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
                        SettingsPage(onShowTutorial: startTutorial)
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(motion, value: page)
                .anchorPreference(key: TutorialAnchorKey.self, value: .bounds) { [.calendar: $0] }

                classPanel
                    .anchorPreference(key: TutorialAnchorKey.self, value: .bounds) { [.classes: $0] }
            }

            commandBar
                .anchorPreference(key: TutorialAnchorKey.self, value: .bounds) { [.commandBar: $0] }
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
        .background(WindowAccessor(tutorialDimmed: !hasCompletedTutorial))
        .overlayPreferenceValue(TutorialAnchorKey.self) { anchors in
            GeometryReader { proxy in
                if !hasCompletedTutorial,
                   case .taskTitle = tutorialTarget,
                   !tutorialTaskTitleFrame.isEmpty {
                    let overlayFrame = proxy.frame(in: .global)
                    let localTitleFrame = tutorialTaskTitleFrame.offsetBy(
                        dx: -overlayFrame.minX,
                        dy: -overlayFrame.minY
                    )
                    tutorialOverlay(
                        in: proxy.size,
                        spotlight: tutorialSpotlight(around: localTitleFrame, in: proxy.size)
                    )
                    .transition(.opacity)
                } else if !hasCompletedTutorial, let anchor = anchors[tutorialTarget] {
                    let spotlight = tutorialSpotlight(
                        around: proxy[anchor],
                        in: proxy.size
                    )
                    tutorialOverlay(
                        in: proxy.size,
                        spotlight: spotlight
                    )
                    .transition(.opacity)
                }
            }
        }
        .overlay(alignment: .topLeading) {
            if !hasCompletedTutorial {
                Button("skip tutorial") { completeTutorial() }
                    .buttonStyle(.plain)
                    .font(.custom(serif, size: appearance.scaled(13)))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .padding(.top, 18)
                    .padding(.leading, 22)
                    .modifier(SubtleHover())
            }
        }
        .onAppear {
            if !hasCompletedTutorial { commandBarIsFocused = true }
        }
        .onChange(of: page) { _, _ in openTaskDetail = nil }
    }

    private func tutorialOverlay(in size: CGSize, spotlight: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            TutorialDimmer(spotlight: spotlight)
                .allowsHitTesting(false)

            tutorialCard
                .position(tutorialCardPosition(in: size, spotlight: spotlight))
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(tutorialStep >= 4)
        .animation(motion, value: tutorialStep)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Dayshift tutorial, step \(tutorialStep + 1) of 6")
    }

    private func tutorialSpotlight(around anchor: CGRect, in size: CGSize) -> CGRect {
        switch tutorialTarget {
        case .commandBar:
            // Extend beyond every window edge except the softly feathered top.
            // This keeps the complete command area illuminated, including the
            // bottom safe-area inset beneath its visible SwiftUI bounds.
            return CGRect(
                x: -40,
                y: anchor.minY - 18,
                width: size.width + 80,
                height: size.height - anchor.minY + 76
            )
        case .taskTitle:
            return anchor.insetBy(dx: -18, dy: -15)
        case .classes:
            return CGRect(
                x: anchor.minX - 16,
                y: anchor.minY - 18,
                width: size.width - anchor.minX + 56,
                height: anchor.height + 36
            )
        case .calendar:
            return anchor.insetBy(dx: -14, dy: -14)
        }
    }

    private var tutorialCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(tutorialStep + 1) of 6")
                .font(.custom(serif, size: appearance.scaled(11)))
                .foregroundStyle(appearance.textColor.opacity(0.42))
                .padding(.bottom, 12)

            Text(tutorialTitle)
                .font(.custom(serif, size: appearance.scaled(21)))
                .padding(.bottom, 9)

            Text(tutorialBody)
                .font(.custom(serif, size: appearance.scaled(14)))
                .foregroundStyle(appearance.textColor.opacity(0.7))
                .lineSpacing(3)

            if let example = tutorialExample {
                Text(example)
                    .font(.custom(serif, size: appearance.scaled(14)))
                    .italic()
                    .padding(.top, 13)
                    .textSelection(.enabled)
            }

            if tutorialStep < 4 {
                Text(tutorialStep < 2 ? "type it below and press return" : tutorialStep == 2 ? "click the title to continue" : "right-click the title to continue")
                    .font(.custom(serif, size: appearance.scaled(11)))
                    .foregroundStyle(appearance.textColor.opacity(0.42))
                    .padding(.top, 14)
            } else {
                Button(tutorialStep == 5 ? "finish" : "next") {
                    advanceTutorial()
                }
                .buttonStyle(.plain)
                .font(.custom(serif, size: appearance.scaled(14)))
                .padding(.top, 16)
                .modifier(SubtleHover())
            }
        }
        .foregroundStyle(appearance.textColor)
        .frame(width: 370, alignment: .leading)
        .padding(.horizontal, 22)
        .padding(.vertical, 19)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(appearance.backgroundColor)
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(appearance.textColor.opacity(0.14), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.22), radius: 24, y: 10)
        }
        .id(tutorialStep)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    private var tutorialTarget: TutorialTarget {
        switch tutorialStep {
        case 2, 3:
            tutorialTaskID.map(TutorialTarget.taskTitle) ?? .commandBar
        case 4: .classes
        case 5: .calendar
        default: .commandBar
        }
    }

    private func tutorialCardPosition(in size: CGSize, spotlight: CGRect) -> CGPoint {
        switch tutorialTarget {
        case .commandBar:
            CGPoint(x: size.width / 2, y: max(135, spotlight.minY - 135))
        case .taskTitle:
            CGPoint(
                x: min(size.width - 225, spotlight.maxX + 225),
                y: min(size.height - 135, max(135, spotlight.midY))
            )
        case .classes:
            CGPoint(x: max(225, spotlight.minX - 225), y: min(size.height - 135, spotlight.minY + 145))
        case .calendar:
            CGPoint(x: min(size.width - 225, spotlight.midX), y: min(size.height - 135, spotlight.maxY - 135))
        }
    }

    private var tutorialTitle: String {
        switch tutorialStep {
        case 0: "add a sample event"
        case 1: "now add a task"
        case 2: "rename the task"
        case 3: "remove the task"
        case 4: "keep classes together"
        default: "your month at a glance"
        }
    }

    private var tutorialBody: String {
        switch tutorialStep {
        case 0:
            "the command bar understands ordinary language. start with a quiz; dayshift will recognize it as an event without a checkbox."
        case 1:
            "tasks get checkboxes. add a small sample task so you can see the difference."
        case 2:
            "click the highlighted title, type a new name, then press return."
        case 3:
            "right-click the highlighted title to delete it immediately. this works for every task and event."
        case 4:
            "your classes appear here. add them anytime with commands like “i have classes math237, cs136”; class names will autocomplete later."
        default:
            appearance.usesScrollingCalendar
                ? "the calendar shows tasks and events together. scroll to change months, or switch to arrows in settings."
                : "the calendar shows tasks and events together. use the arrows to change months, or switch to scrolling in settings."
        }
    }

    private var tutorialExample: String? {
        switch tutorialStep {
        case 0: "tutorial quiz tomorrow"
        case 1: "write tutorial notes tomorrow"
        default: nil
        }
    }

    private func advanceTutorial() {
        guard tutorialStep < 5 else {
            completeTutorial()
            return
        }
        withAnimation(motion) {
            tutorialStep += 1
            if tutorialStep == 5 { page = .calendar }
        }
        commandBarIsFocused = tutorialStep < 2
    }

    private func completeTutorial() {
        store.discardTasks(withIDs: Set([tutorialQuizID, tutorialTaskID].compactMap { $0 }))
        withAnimation(motion) { hasCompletedTutorial = true }
    }

    private func startTutorial() {
        store.discardTasks(withIDs: Set([tutorialQuizID, tutorialTaskID].compactMap { $0 }))
        tutorialStep = 0
        tutorialQuizID = nil
        tutorialTaskID = nil
        tutorialTaskTitleFrame = .zero
        input = ""
        feedback = nil
        page = .todo
        withAnimation(motion) { hasCompletedTutorial = false }
        commandBarIsFocused = true
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
        .frame(width: classPanelWidth - 62, alignment: .leading)
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
                Text("/").foregroundStyle(appearance.textColor.opacity(0.5))
                modeButton("calendar", active: page == .calendar) { withAnimation(motion) { page = .calendar } }
                Text("/").foregroundStyle(appearance.textColor.opacity(0.5))
                modeButton("settings", active: page == .settings) { withAnimation(motion) { page = .settings } }
            }
            Spacer()
        }
        .frame(width: 280, height: 28)
        .foregroundStyle(appearance.textColor)
    }

    private func modeButton(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.custom(serif, size: appearance.scaled(15)))
            .fontWeight(active ? .semibold : .regular)
            .buttonStyle(.plain)
            .foregroundStyle(appearance.textColor)
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
            openDetail: $openTaskDetail,
            highlightsTitle: !hasCompletedTutorial && tutorialTaskID == task.id && (tutorialStep == 2 || tutorialStep == 3),
            onTitleFrameChange: { tutorialTaskTitleFrame = $0 },
            onToggle: { withAnimation(motion) { store.toggle(task) } },
            onRename: {
                let previousTitle = task.title
                let renamed = store.rename(task, to: $0)
                if tutorialStep == 2, tutorialTaskID == task.id, renamed != nil, renamed != previousTitle {
                    moveTutorial(to: 3)
                }
            },
            onDelete: {
                if openTaskDetail?.taskID == task.id { openTaskDetail = nil }
                let deleted = store.delete(task)
                if tutorialStep == 3, tutorialTaskID == task.id, deleted != nil {
                    moveTutorial(to: 4)
                }
            },
            onDateChange: { _ = store.setDate(task, to: $0) },
            onTimeChange: { hour, minute in _ = store.setTime(task, hour: hour, minute: minute) },
            onClearTime: { _ = store.clearTime(task) },
            onPriorityChange: { _ = store.setPriority(task, to: $0) },
            onRepeatChange: { _ = store.setRepeat(task, to: $0) }
        )
        .transition(.opacity)
    }

    private var calendarPage: some View {
        Group {
            if appearance.usesScrollingCalendar {
                scrollingCalendarPage
            } else {
                arrowCalendarPage
            }
        }
    }

    private var scrollingCalendarPage: some View {
        GeometryReader { proxy in
            ZStack {
                scrollingCalendarLayer(month(byAdding: -1, to: displayedMonth), in: proxy.size)
                    .offset(y: calendarDragOffset - proxy.size.height)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                scrollingCalendarLayer(displayedMonth, in: proxy.size)
                    .offset(y: calendarDragOffset)
                scrollingCalendarLayer(month(byAdding: 1, to: displayedMonth), in: proxy.size)
                    .offset(y: calendarDragOffset + proxy.size.height)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .clipped()
            .background {
                ScrollWheelPager { event in
                    handleCalendarGesture(event, pageHeight: proxy.size.height)
                }
            }
            .onAppear { calendarViewportHeight = proxy.size.height }
            .onChange(of: proxy.size.height) { _, height in calendarViewportHeight = height }
        }
        // The classes panel occupies fixed space on the right. Its matching
        // leading inset keeps the calendar centered in the whole window.
        .padding(.leading, classPanelWidth)
    }

    private func scrollingCalendarLayer(_ month: Date, in viewport: CGSize) -> some View {
        calendarPageLayer(month)
            // Give every month a concrete page-sized surface before applying
            // its transform. Without this, SwiftUI can independently redraw
            // lazy grid descendants while their header moves as one layer.
            .frame(width: viewport.width, height: viewport.height, alignment: .top)
            .background(appearance.backgroundColor)
            .compositingGroup()
            .id(month)
    }

    private var arrowCalendarPage: some View {
        VStack(spacing: 0) {
            HStack {
                Button("←") { moveMonth(by: -1) }
                    .modifier(SubtleHover())
                Spacer()
                Text(displayedMonth.formatted(.dateTime.month(.wide).year()).lowercased())
                    .font(.custom(serif, size: appearance.scaled(20)))
                Spacer()
                Button("→") { moveMonth(by: 1) }
                    .modifier(SubtleHover())
            }
            .font(.custom(serif, size: appearance.scaled(17)))
            .buttonStyle(.plain)
            .padding(.bottom, 24)

            calendarWeekdayHeader
            calendarDateGrid(for: displayedMonth)
        }
        .padding(.horizontal, 38)
        .padding(.top, 30)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // The classes panel occupies fixed space on the right. Its matching
        // leading inset keeps the calendar centered in the whole window.
        .padding(.leading, classPanelWidth)
    }

    private var calendarColumns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 0), count: 7) }

    private func calendarPageLayer(_ month: Date) -> some View {
        calendarMonth(month)
            .padding(.horizontal, 38)
            .padding(.top, 30)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func calendarMonth(_ month: Date) -> some View {
        VStack(spacing: 0) {
            Text(month.formatted(.dateTime.month(.wide).year()).lowercased())
                .font(.custom(serif, size: appearance.scaled(20)))
                .padding(.bottom, 24)

            calendarWeekdayHeader
            calendarDateGrid(for: month)
        }
        .frame(maxWidth: 1040, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var calendarWeekdayHeader: some View {
        LazyVGrid(columns: calendarColumns, spacing: 0) {
            ForEach(Array(weekdayLabels.enumerated()), id: \.offset) { _, weekday in
                Text(weekday.lowercased())
                    .font(.custom(serif, size: appearance.scaled(13)))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 10)
            }
        }
    }

    private func calendarDateGrid(for month: Date) -> some View {
        LazyVGrid(columns: calendarColumns, spacing: 18) {
            ForEach(monthDates(for: month), id: \.self) { date in
                calendarDay(date, in: month)
            }
        }
    }

    private var weekdayLabels: [String] {
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        let first = max(0, Calendar.current.firstWeekday - 1)
        return Array(symbols[first...] + symbols[..<first])
    }

    private func monthDates(for month: Date) -> [Date] {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let weekday = calendar.component(.weekday, from: interval.start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let start = calendar.date(byAdding: .day, value: -leading, to: interval.start) ?? interval.start
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private func calendarDay(_ date: Date, in month: Date) -> some View {
        let calendar = Calendar.current
        let inMonth = calendar.isDate(date, equalTo: month, toGranularity: .month)
        let selected = calendar.isDate(date, inSameDayAs: selectedDate)
        let tasks = store.tasks(on: date)

        return Button {
            withAnimation(motion) {
                selectedDate = date
                page = .todo
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
                    .tint(appearance.textColor)
                    .font(.custom(serif, size: appearance.scaled(19)))
                    .focused($commandBarIsFocused)
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
        let taskIDsBeforeCommand = Set(store.tasks.map(\.id))

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

        updateTutorial(
            after: command,
            taskIDsBeforeCommand: taskIDsBeforeCommand
        )
    }

    private func updateTutorial(
        after command: TaskCommand,
        taskIDsBeforeCommand: Set<UUID>
    ) {
        guard !hasCompletedTutorial else { return }
        let addedTask = store.tasks.first { !taskIDsBeforeCommand.contains($0.id) }

        switch tutorialStep {
        case 0:
            guard case .add = command, let addedTask, addedTask.isEvent else { return }
            tutorialQuizID = addedTask.id
            moveTutorial(to: 1)
        case 1:
            guard case .add = command, let addedTask, !addedTask.isEvent else { return }
            tutorialTaskID = addedTask.id
            moveTutorial(to: 2)
        default:
            break
        }
    }

    private func moveTutorial(to step: Int) {
        withAnimation(motion) { tutorialStep = step }
        commandBarIsFocused = false
        guard step < 2 else { return }
        Task { @MainActor in
            await Task.yield()
            commandBarIsFocused = true
        }
    }

    private func moveMonth(by amount: Int) {
        let direction = amount >= 0 ? 1 : -1

        if !appearance.usesScrollingCalendar {
            withAnimation(motion) {
                displayedMonth = month(byAdding: direction, to: displayedMonth)
            }
            return
        }

        settleCalendar(in: direction, pageHeight: calendarViewportHeight)
    }

    private func handleCalendarGesture(_ event: ScrollWheelPager.GestureEvent, pageHeight: CGFloat) {
        guard pageHeight > 0 else { return }

        switch event {
        case .began:
            finishInterruptedCalendarSettlement()
        case .changed(let delta):
            calendarTransitionID = UUID()
            calendarSettlingDirection = 0
            calendarDragOffset += delta * 2.15

            // Momentum is allowed to carry through more than one month. Each
            // full-height crossing rebases the three visible pages seamlessly.
            while calendarDragOffset <= -pageHeight {
                displayedMonth = month(byAdding: 1, to: displayedMonth)
                calendarDragOffset += pageHeight
            }
            while calendarDragOffset >= pageHeight {
                displayedMonth = month(byAdding: -1, to: displayedMonth)
                calendarDragOffset -= pageHeight
            }
        case .ended:
            guard abs(calendarDragOffset) > 8 else {
                withAnimation(calendarMotion) { calendarDragOffset = 0 }
                return
            }
            settleCalendar(in: calendarDragOffset < 0 ? 1 : -1, pageHeight: pageHeight)
        case .page(let direction):
            finishInterruptedCalendarSettlement()
            settleCalendar(in: direction, pageHeight: pageHeight)
        }
    }

    private func settleCalendar(in direction: Int, pageHeight: CGFloat) {
        let transitionID = UUID()
        calendarTransitionID = transitionID
        calendarSettlingDirection = direction
        withAnimation(calendarMotion) {
            calendarDragOffset = direction > 0 ? -pageHeight : pageHeight
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: reduceMotion ? 1_000_000 : 480_000_000)
            guard calendarTransitionID == transitionID else { return }
            displayedMonth = month(byAdding: direction, to: displayedMonth)
            calendarDragOffset = 0
            calendarSettlingDirection = 0
        }
    }

    private func finishInterruptedCalendarSettlement() {
        calendarTransitionID = UUID()
        guard calendarSettlingDirection != 0 else { return }
        displayedMonth = month(byAdding: calendarSettlingDirection, to: displayedMonth)
        calendarDragOffset = 0
        calendarSettlingDirection = 0
    }

    private func month(byAdding amount: Int, to date: Date) -> Date {
        let calendar = Calendar.current
        let shifted = calendar.date(byAdding: .month, value: amount, to: date) ?? date
        return calendar.dateInterval(of: .month, for: shifted)?.start ?? shifted
    }

    private func mutationFeedback(_ title: String?, verb: String, query: String) -> String { title.map { "\(verb) “\($0)”." } ?? notFound(query) }
    private func notFound(_ query: String) -> String { "no task matches “\(query)”." }
    private func hasTime(_ date: Date) -> Bool { let p = Calendar.current.dateComponents([.hour, .minute], from: date); return p.hour != 0 || p.minute != 0 }
    private func formattedTime(hour: Int, minute: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
        return date.formatted(date: .omitted, time: .shortened).lowercased()
    }
}

@MainActor
private struct TaskRow: View {
    let task: TaskItem
    let serif: String
    let showsDueDate: Bool
    @Binding var openDetail: OpenTaskDetail?
    let highlightsTitle: Bool
    let onTitleFrameChange: (CGRect) -> Void
    let onToggle: () -> Void
    let onRename: (String) -> Void
    let onDelete: () -> Void
    let onDateChange: (Date) -> Void
    let onTimeChange: (Int, Int) -> Void
    let onClearTime: () -> Void
    let onPriorityChange: (TaskPriority) -> Void
    let onRepeatChange: (RepeatRule?) -> Void
    @Environment(AppearanceSettings.self) private var appearance

    @State private var isEditingTitle = false
    @State private var titleDraft = ""
    @FocusState private var titleIsFocused: Bool

    private var detailEditor: TaskDetailEditor? {
        openDetail?.taskID == task.id ? openDetail?.editor : nil
    }

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
                        .tint(appearance.textColor)
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
                        .background { tutorialTitleFrameReader }
                        .transition(.opacity)
                } else {
                    Text(task.title.lowercased())
                        .font(.custom(serif, size: appearance.scaled(18)))
                        .strikethrough(task.isComplete)
                        .foregroundStyle(task.isComplete ? .secondary : .primary)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: beginEditing)
                        .help("click to rename · right-click to delete")
                        .modifier(SubtleHover())
                        .background { tutorialTitleFrameReader }
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
            .background {
                RightClickHandler(action: onDelete)
            }

            Spacer()
        }
        .padding(.vertical, appearance.rowSpacing)
        .zIndex(detailEditor == nil ? 0 : 1)
        .animation(.easeInOut(duration: 0.15), value: detailEditor)
    }

    @ViewBuilder
    private var tutorialTitleFrameReader: some View {
        if highlightsTitle {
            GeometryReader { proxy in
                let frame = proxy.frame(in: .global)
                Color.clear
                    .onAppear { onTitleFrameChange(frame) }
                    .onChange(of: frame) { _, newFrame in onTitleFrameChange(newFrame) }
            }
        }
    }

    private var detailLine: some View {
        HStack(spacing: 7) {
            detailButton(dateLabel, editor: .date)

            if hasTime {
                detailSeparator
                detailButton(task.dueDate.formatted(date: .omitted, time: .shortened), editor: .date)
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

    private func detailButton(_ title: String, editor: TaskDetailEditor) -> some View {
        Button(title.lowercased()) {
            withAnimation(.easeInOut(duration: 0.15)) {
                openDetail = detailEditor == editor ? nil : OpenTaskDetail(taskID: task.id, editor: editor)
            }
        }
        .buttonStyle(.plain)
        .modifier(SubtleHover())
        .foregroundStyle(detailEditor == editor ? appearance.textColor : Color.secondary)
    }

    @ViewBuilder
    private func detailEditorView(_ editor: TaskDetailEditor) -> some View {
        switch editor {
        case .date:
            DateAndTimeEditor(
                selectedDate: task.dueDate,
                serif: serif,
                onDateChange: onDateChange,
                onTimeChange: onTimeChange,
                onClearTime: onClearTime,
                onDone: { openDetail = nil }
            )
            .frame(width: 238)
            .modifier(DetailPanel())
        case .priority:
            VStack(alignment: .leading, spacing: 0) {
                ForEach(TaskPriority.allCases, id: \.self) { priority in
                    detailChoice(priority.rawValue.lowercased(), selected: task.priority == priority) {
                        onPriorityChange(priority)
                        openDetail = nil
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
                        openDetail = nil
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

struct SubtleHover: ViewModifier {
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

@MainActor
private struct DateAndTimeEditor: View {
    @Environment(AppearanceSettings.self) private var appearance
    let selectedDate: Date
    let serif: String
    let onDateChange: (Date) -> Void
    let onTimeChange: (Int, Int) -> Void
    let onClearTime: () -> Void
    let onDone: () -> Void
    @State private var timeDraft: String

    init(
        selectedDate: Date,
        serif: String,
        onDateChange: @escaping (Date) -> Void,
        onTimeChange: @escaping (Int, Int) -> Void,
        onClearTime: @escaping () -> Void,
        onDone: @escaping () -> Void
    ) {
        self.selectedDate = selectedDate
        self.serif = serif
        self.onDateChange = onDateChange
        self.onTimeChange = onTimeChange
        self.onClearTime = onClearTime
        self.onDone = onDone
        let parts = Calendar.current.dateComponents([.hour, .minute], from: selectedDate)
        let hasTime = parts.hour != 0 || parts.minute != 0
        _timeDraft = State(initialValue: hasTime ? selectedDate.formatted(date: .omitted, time: .shortened).lowercased() : "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            CompactCalendar(selectedDate: selectedDate, serif: serif, onSelect: onDateChange)

            HStack(spacing: 9) {
                Text("time")
                    .foregroundStyle(.secondary)

                TextField("4:30 pm", text: $timeDraft)
                    .textFieldStyle(.plain)
                    .font(.custom(serif, size: appearance.scaled(13)))
                    .frame(width: 70)
                    .padding(.vertical, 3)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(appearance.textColor.opacity(0.18))
                            .frame(height: 1)
                    }
                    .onSubmit(applyTime)

                Button("set", action: applyTime)
                    .disabled(parsedTime == nil)
                    .opacity(parsedTime == nil ? 0.35 : 1)
                    .modifier(SubtleHover())

                if hasTime {
                    Button("clear") {
                        timeDraft = ""
                        onClearTime()
                    }
                    .modifier(SubtleHover())
                }
            }
            .buttonStyle(.plain)
            .font(.custom(serif, size: appearance.scaled(12)))

            HStack {
                Spacer()
                Button("done", action: onDone)
                    .buttonStyle(.plain)
                    .font(.custom(serif, size: appearance.scaled(12)))
                    .foregroundStyle(.secondary)
                    .modifier(SubtleHover())
            }
        }
    }

    private var parsedTime: (hour: Int, minute: Int)? {
        NaturalLanguageParser().timeComponents(in: "at " + timeDraft)
    }

    private var hasTime: Bool {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: selectedDate)
        return parts.hour != 0 || parts.minute != 0
    }

    private func applyTime() {
        guard let parsedTime else { return }
        onTimeChange(parsedTime.hour, parsedTime.minute)
        let date = Calendar.current.date(
            bySettingHour: parsedTime.hour,
            minute: parsedTime.minute,
            second: 0,
            of: selectedDate
        ) ?? selectedDate
        timeDraft = date.formatted(date: .omitted, time: .shortened).lowercased()
    }
}

@MainActor
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
