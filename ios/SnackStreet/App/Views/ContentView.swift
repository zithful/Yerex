import SwiftUI
import TycoonCore

struct ContentView: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            HeaderView()
            TabView {
                StreetView()
                    .tabItem { Label("Street", systemImage: "storefront") }
                ManagersView()
                    .tabItem { Label("Managers", systemImage: "person.2") }
                UpgradesView()
                    .tabItem { Label("Upgrades", systemImage: "arrow.up.circle") }
                FranchiseView()
                    .tabItem { Label("Franchise", systemImage: "star") }
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .sheet(isPresented: Binding(
            get: { store.offlineEarnings != nil },
            set: { if !$0 { store.offlineEarnings = nil } }
        )) {
            OfflineEarningsView(amount: store.offlineEarnings ?? 0) {
                store.offlineEarnings = nil
            }
            .presentationDetents([.fraction(0.35)])
        }
    }
}

enum Theme {
    static let background = Color(red: 0.99, green: 0.96, blue: 0.90)
    static let card = Color.white
    static let accent = Color.orange
    static let money = Color(red: 0.13, green: 0.55, blue: 0.25)
}

#Preview {
    ContentView().environment(GameStore())
}
