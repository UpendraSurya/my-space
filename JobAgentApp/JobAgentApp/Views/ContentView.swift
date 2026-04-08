import SwiftUI

struct ContentView: View {
    @StateObject private var appState = AppState()

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            SidebarView()
                .environmentObject(appState)
                .navigationSplitViewColumnWidth(min: 190, ideal: 200, max: 220)
        } detail: {
            ZStack {
                Theme.bg.ignoresSafeArea()
                switch appState.selectedTab {
                case .dashboard: DashboardView()
                case .jobs:      JobsView()
                case .tracker:   TrackerView()
                case .profile:   ProfileView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    BackendStatusBadge().environmentObject(appState)
                }
            }
        }
        .background(Theme.bg)
        .environmentObject(appState)
    }
}
