import AppKit
import SwiftUI

@main
@MainActor
struct DAYSHIFTApp: App {
    @State private var store = TaskStore()
    @State private var appearance = AppearanceSettings()
    @State private var reminders = ReminderManager()
    @State private var account = CloudAccount()
    @State private var sync = CloudSync()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(appearance)
                .environment(reminders)
                .environment(account)
                .environment(sync)
                .frame(minWidth: 700, minHeight: 580)
                .onAppear {
                    sync.activate(for: account, store: store)
                    reminders.update(tasks: store.tasks)
                }
                .onChange(of: account.userID) { _, _ in
                    sync.activate(for: account, store: store)
                    reminders.update(tasks: store.tasks)
                }
                .onChange(of: store.tasks) { _, tasks in
                    sync.localStateChanged(store: store, account: account)
                    reminders.update(tasks: tasks)
                }
                .onChange(of: store.classes) { _, _ in
                    sync.localStateChanged(store: store, account: account)
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    sync.syncNow(account: account, store: store)
                    reminders.update(tasks: store.tasks)
                }
                .onReceive(Timer.publish(every: 20, on: .main, in: .common).autoconnect()) { _ in
                    sync.syncNow(account: account, store: store)
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
