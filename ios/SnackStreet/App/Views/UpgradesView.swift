import SwiftUI
import TycoonCore

struct UpgradesView: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        List {
            let available = Catalog.upgrades.filter { !store.state.upgrades.contains($0.id) }
            let owned = Catalog.upgrades.filter { store.state.upgrades.contains($0.id) }
            Section("Available") {
                if available.isEmpty {
                    Text("You've bought every upgrade!")
                }
                ForEach(available.prefix(8)) { upgrade in
                    UpgradeRow(upgrade: upgrade, bought: false)
                }
            }
            if !owned.isEmpty {
                Section("Bought") {
                    ForEach(owned) { upgrade in
                        UpgradeRow(upgrade: upgrade, bought: true)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
    }
}

private struct UpgradeRow: View {
    @Environment(GameStore.self) private var store
    let upgrade: UpgradeDefinition
    let bought: Bool

    var body: some View {
        HStack {
            Text(icon).font(.title)
            VStack(alignment: .leading) {
                Text(upgrade.name).font(.headline)
                Text(upgrade.detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if bought {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.money)
            } else {
                Button(MoneyFormat.money(upgrade.cost)) {
                    store.buyUpgrade(upgrade)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(!store.state.canAfford(upgrade.cost))
            }
        }
    }

    private var icon: String {
        if let id = upgrade.businessID, let business = Catalog.business(id) {
            return business.emoji
        }
        return "🎉"
    }
}
