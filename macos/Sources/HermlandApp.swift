import SwiftUI

@main
struct HermlandApp: App {
    @StateObject private var store = AppState()

    var body: some Scene {
        WindowGroup("Hermland") {
            Group {
                if store.isConnected, let url = store.dashboardURL ?? store.settings.baseURL {
                    DashboardScreen(store: store, url: url)
                } else {
                    ConnectView(store: store)
                }
            }
            .frame(minWidth: 960, minHeight: 640)
            .task {
                if NSClassFromString("XCTestCase") != nil { return }
                await store.connectIfConfigured()
            }
        }
        .defaultSize(width: 1100, height: 740)
    }
}
