import SwiftUI
import TycoonCore

/// Prestige: sell the street for stars that permanently boost profit.
struct FranchiseView: View {
    @Environment(GameStore.self) private var store
    @State private var confirming = false

    var body: some View {
        let gain = store.state.starsAvailableOnPrestige
        let currentBonus = store.state.stars * Catalog.starBonus * 100
        let newBonus = (store.state.stars + gain) * Catalog.starBonus * 100

        ScrollView {
            VStack(spacing: 20) {
                Text("⭐️").font(.system(size: 72))
                Text("Franchise Your Street")
                    .font(.title.bold())
                Text("Sell everything to a big chain. You start over with $5 and a single lemonade stand, but every star you earn adds +\(Int(Catalog.starBonus * 100))% to all profits forever.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    statRow("Stars now", MoneyFormat.short(store.state.stars))
                    statRow("Current bonus", "+\(MoneyFormat.short(currentBonus))%")
                    statRow("Stars from franchising", "+\(MoneyFormat.short(gain))")
                    statRow("Bonus after", "+\(MoneyFormat.short(newBonus))%")
                    statRow("Earned this run", MoneyFormat.money(store.state.runEarnings))
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))

                Button {
                    confirming = true
                } label: {
                    Text(gain >= 1 ? "Franchise for \(MoneyFormat.short(gain)) stars" : "Earn $1T this run to franchise")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.yellow)
                .foregroundStyle(.black)
                .disabled(gain < 1)
            }
            .padding()
        }
        .confirmationDialog("Franchise now?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Franchise for \(MoneyFormat.short(gain)) stars", role: .destructive) {
                store.prestige()
            }
        } message: {
            Text("Your cash, businesses, managers and upgrades will reset.")
        }
    }

    private func statRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).bold().monospacedDigit()
        }
    }
}
