import SwiftUI

@main
struct JobAgentApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
                .frame(minWidth: 900, minHeight: 650)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
