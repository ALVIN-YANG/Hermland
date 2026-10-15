import SwiftUI

@main
struct HermlandApp: App {
    @StateObject private var store = ConnectionStore()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            RootView(store: store)
                .overlay {
                    if scenePhase != .active {
                        Palette.canvas.ignoresSafeArea().overlay { MessengerIcon(size: 80) }
                    }
                }
                .task { if NSClassFromString("XCTestCase") == nil { store.activate() } }
                .onOpenURL { store.review($0) }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { store.activate() }
                    if phase == .background { store.background() }
                }
        }
    }
}
