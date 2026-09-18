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
                VStack(alignment: .leading, spacing: 32) {
                    capture

                    if page == .calendar {
                        calendar
                    }

                    taskSection
                }
                .frame(maxWidth: 680, alignment: .leading)
                .padding(.horizontal, 44)
                .padding(.vertical, 40)
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
        DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
            .datePickerStyle(.graphical)
            .labelsHidden()
            .tint(.black)
            .frame(maxWidth: 340)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
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
