import SwiftUI

@main
struct DAYSHIFTApp: App {
    @State private var store = TaskStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .frame(minWidth: 620, minHeight: 560)
        }
        .defaultSize(width: 780, height: 680)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
