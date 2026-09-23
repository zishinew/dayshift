import AppKit
import SwiftUI

@main
@MainActor
struct DAYSHIFTApp: App {
    @State private var store = TaskStore()
    @State private var appearance = AppearanceSettings()
    @State private var reminders = ReminderManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(appearance)
                .environment(reminders)
                .frame(minWidth: 700, minHeight: 580)
                .onAppear { reminders.update(tasks: store.tasks) }
                .onChange(of: store.tasks) { _, tasks in reminders.update(tasks: tasks) }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    reminders.update(tasks: store.tasks)
                }
        }
        .defaultSize(width: 900, height: 700)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { store.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!store.canUndo)
                Button("Redo") { store.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!store.canRedo)
            }
        }
    }
}
