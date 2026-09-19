import SwiftUI

struct ContentView: View {
    @Environment(TaskStore.self) private var store
    @State private var input = ""
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var feedback: String?

    private let interpreter = TaskCommandInterpreter()

    private var visibleTasks: [TaskItem] { store.tasks(on: selectedDate) }

    var body: some View {
        VStack(spacing: 0) {
            taskList
            commandBar
        }
        .background(Color.white)
        .foregroundStyle(Color.black)
        .preferredColorScheme(.light)
    }

    private var taskList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(selectedDate.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        .font(.system(size: 30, weight: .regular, design: .serif))
                    Spacer()
                    Text("\(visibleTasks.filter { !$0.isComplete }.count) open")
                        .font(.system(size: 13, design: .serif))
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 14)

                Divider().overlay(Color.black)

                if visibleTasks.isEmpty {
                    Text("Nothing scheduled.")
                        .font(.system(size: 18, design: .serif))
                        .foregroundStyle(.secondary)
                        .padding(.top, 28)
                } else {
                    ForEach(visibleTasks) { task in
                        TaskRow(task: task)
                        Divider()
                    }
                }
            }
            .frame(maxWidth: 820, alignment: .leading)
            .padding(.horizontal, 34)
            .padding(.top, 34)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var commandBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                TextField("Type anything…", text: $input)
                    .textFieldStyle(.plain)
                    .font(.system(size: 19, design: .serif))
                    .onSubmit(executeCommand)
                    .onChange(of: input) { _, _ in feedback = nil }

                Text("return ↵")
                    .font(.system(size: 12, design: .serif))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 15)
            .frame(height: 52)
            .overlay(Rectangle().stroke(Color.black, lineWidth: 1))

            if let feedback {
                Text(feedback)
                    .font(.system(size: 13, design: .serif))
                    .foregroundStyle(Color.black)
                    .lineLimit(2)
            } else if !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(interpreter.interpret(input).preview)
                    .font(.system(size: 13, design: .serif))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else {
                Text("Add, move, complete, rename, reprioritize, delete, or show a date.")
                    .font(.system(size: 13, design: .serif))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 34)
        .padding(.top, 14)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .overlay(alignment: .top) { Divider().overlay(Color.black) }
    }

    private func executeCommand() {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        let command = interpreter.interpret(value)

        switch command {
        case .add(let task):
            store.add(task)
            selectedDate = Calendar.current.startOfDay(for: task.dueDate)
            feedback = "Added “\(task.title)”."
        case .complete(let query):
            feedback = mutationFeedback(store.setCompletion(matching: query, to: true), verb: "Completed", query: query)
        case .reopen(let query):
            feedback = mutationFeedback(store.setCompletion(matching: query, to: false), verb: "Reopened", query: query)
        case .delete(let query):
            feedback = mutationFeedback(store.delete(matching: query), verb: "Deleted", query: query)
        case .rename(let query, let title):
            feedback = store.rename(matching: query, to: title).map { "Renamed task to “\($0)”." } ?? notFound(query)
        case .setPriority(let query, let priority):
            feedback = store.setPriority(matching: query, to: priority).map { "Set “\($0)” to \(priority.rawValue) priority." } ?? notFound(query)
        case .reschedule(let query, let date):
            feedback = store.reschedule(matching: query, to: date).map { "Moved “\($0)” to \(date.formatted(date: .abbreviated, time: hasTime(date) ? .shortened : .omitted))." } ?? notFound(query)
        case .clearCompleted:
            let count = store.clearCompleted()
            feedback = count == 0 ? "No completed tasks to delete." : "Deleted \(count) completed \(count == 1 ? "task" : "tasks")."
        case .showToday:
            selectedDate = Calendar.current.startOfDay(for: Date())
            feedback = "Showing today."
        case .showDate(let date):
            selectedDate = Calendar.current.startOfDay(for: date)
            feedback = "Showing \(date.formatted(date: .long, time: .omitted))."
        case .showCalendar:
            feedback = "The calendar is command-based. Try “show next Tuesday” or “show October 4”."
        case .nextMonth:
            moveDate(by: 1, component: .month)
            feedback = "Showing next month."
        case .previousMonth:
            moveDate(by: -1, component: .month)
            feedback = "Showing previous month."
        case .help:
            feedback = "Try “complete the quiz”, “priority quiz high”, “move quiz to Friday”, “delete the quiz”, or “show next Tuesday”."
        }

        input = ""
    }

    private func moveDate(by value: Int, component: Calendar.Component) {
        selectedDate = Calendar.current.date(byAdding: component, value: value, to: selectedDate) ?? selectedDate
    }

    private func mutationFeedback(_ title: String?, verb: String, query: String) -> String {
        title.map { "\(verb) “\($0)”." } ?? notFound(query)
    }

    private func notFound(_ query: String) -> String { "No task matches “\(query)”." }

    private func hasTime(_ date: Date) -> Bool {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return parts.hour != 0 || parts.minute != 0
    }
}

private struct TaskRow: View {
    let task: TaskItem

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: task.isComplete ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Color.black)
                .accessibilityHidden(true)

            Text(task.title)
                .font(.system(size: 19, design: .serif))
                .strikethrough(task.isComplete)
                .foregroundStyle(task.isComplete ? .secondary : .primary)

            Spacer()

            Text(metadata)
                .font(.system(size: 13, design: .serif))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 16)
    }

    private var metadata: String {
        let calendar = Calendar.current
        let time = calendar.component(.hour, from: task.dueDate) == 0 && calendar.component(.minute, from: task.dueDate) == 0
            ? "No time"
            : task.dueDate.formatted(date: .omitted, time: .shortened)
        return "\(time)  ·  \(task.priority.rawValue)"
    }
}
