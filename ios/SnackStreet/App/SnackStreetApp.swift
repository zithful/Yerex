import SwiftUI

@main
struct SnackStreetApp: App {
    @State private var store = GameStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active: store.resume()
            case .inactive, .background: store.pause()
            @unknown default: break
            }
        }
    }
}
