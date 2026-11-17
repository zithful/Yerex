import SwiftUI
import TycoonCore

/// The main screen: every business with its run button and buy button.
struct StreetView: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 8) {
            Picker("Buy amount", selection: $store.buyAmount) {
                ForEach(BuyAmount.allCases, id: \.self) { amount in
                    Text(amount.rawValue).tag(amount)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(visibleBusinesses) { business in
                        BusinessRow(business: business)
                    }
                }
                .padding()
            }
        }
    }

    /// Owned businesses plus the next one to unlock, so the street grows as you play.
    private var visibleBusinesses: [BusinessDefinition] {
        var result: [BusinessDefinition] = []
        for business in Catalog.businesses {
            result.append(business)
            if store.state.state(of: business.id).owned == 0 { break }
        }
        return result
    }
}

struct BusinessRow: View {
    @Environment(GameStore.self) private var store
    let business: BusinessDefinition

    var body: some View {
        let s = store.state.state(of: business.id)
        let owned = s.owned
        let price = store.priceToBuy(business)
        let quantity = store.quantityToBuy(business)
        let affordable = store.state.canAfford(price)

        HStack(spacing: 12) {
            Button {
                store.tap(business)
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    Text(business.emoji)
                        .font(.system(size: 40))
                        .frame(width: 64, height: 64)
                        .background(Circle().fill(Theme.accent.opacity(owned > 0 ? 0.2 : 0.05)))
                    if owned > 0 {
                        Text("\(owned)")
                            .font(.caption.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Theme.accent))
                            .foregroundStyle(.white)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(owned == 0 || s.running)
            .opacity(owned == 0 ? 0.4 : 1)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(business.name).font(.headline)
                    Spacer()
                    if s.hasManager {
                        Image(systemName: "person.fill.checkmark").foregroundStyle(Theme.money)
                    }
                }
                ProgressBar(progress: cycleProgress(s), label: revenueLabel(owned: owned))
                HStack {
                    Text(milestoneText(owned: owned))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        store.buy(business)
                    } label: {
                        VStack(spacing: 0) {
                            Text("Buy ×\(quantity)").font(.caption.bold())
                            Text(MoneyFormat.money(price)).font(.caption2).monospacedDigit()
                        }
                        .frame(minWidth: 86)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(affordable ? Theme.accent : .gray)
                    .disabled(!affordable)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }

    private func cycleProgress(_ s: BusinessState) -> Double {
        // Very fast businesses would flicker; show a full bar instead.
        if s.hasManager && store.state.cycleTime(of: business) < 0.15 { return 1 }
        return s.running ? s.progress : 0
    }

    private func revenueLabel(owned: Int) -> String {
        guard owned > 0 else { return "Not owned yet" }
        let revenue = MoneyFormat.money(store.state.revenuePerCycle(of: business))
        let time = MoneyFormat.duration(store.state.cycleTime(of: business))
        return "\(revenue) every \(time)"
    }

    private func milestoneText(owned: Int) -> String {
        guard let next = Economy.nextMilestone(owned: owned) else { return "Max speed!" }
        return "Speed ×2 at \(next)"
    }
}

struct ProgressBar: View {
    let progress: Double
    let label: String

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.gray.opacity(0.15))
                Capsule()
                    .fill(Theme.money.gradient)
                    .frame(width: geo.size.width * min(max(progress, 0), 1))
                Text(label)
                    .font(.caption.bold())
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
            }
        }
        .frame(height: 22)
    }
}
