import SwiftUI
import TycoonCore

/// Managers run a business forever and keep earning while the app is closed.
struct ManagersView: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        List {
            Section {
                ForEach(Catalog.businesses) { business in
                    let s = store.state.state(of: business.id)
                    HStack {
                        Text(business.emoji).font(.largeTitle)
                        VStack(alignment: .leading) {
                            Text(business.managerName).font(.headline)
                            Text("Runs your \(business.name)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if s.hasManager {
                            Text("Hired").font(.subheadline.bold()).foregroundStyle(Theme.money)
                        } else {
                            Button(MoneyFormat.money(business.managerCost)) {
                                store.hireManager(business)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.accent)
                            .disabled(s.owned == 0 || !store.state.canAfford(business.managerCost))
                        }
                    }
                }
            } footer: {
                Text("You need to own at least one of a business to hire its manager. Managed businesses earn while you're away (up to 8 hours).")
            }
        }
        .scrollContentBackground(.hidden)
    }
}
