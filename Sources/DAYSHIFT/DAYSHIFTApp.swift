import SwiftUI

@main
@MainActor
struct DAYSHIFTApp: App {
    @State private var store = TaskStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .background(WindowAccessor())
                .frame(minWidth: 700, minHeight: 580)
        }
        .defaultSize(width: 900, height: 700)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
