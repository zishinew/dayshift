import SwiftUI

@main
@MainActor
struct DAYSHIFTApp: App {
    @State private var store = TaskStore()
    @State private var appearance = AppearanceSettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(appearance)
                .background(WindowAccessor())
                .frame(minWidth: 700, minHeight: 580)
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
