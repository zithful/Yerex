import SwiftUI
import TycoonCore

/// Cash, income per second and stars, always on screen.
struct HeaderView: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        VStack(spacing: 4) {
            Text(MoneyFormat.money(store.state.cash))
                .font(.system(size: 38, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.money)
                .contentTransition(.numericText())
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            HStack(spacing: 16) {
                Label("\(MoneyFormat.money(store.state.managedIncomePerSecond))/s", systemImage: "chart.line.uptrend.xyaxis")
                if store.state.stars > 0 {
                    Label("\(MoneyFormat.short(store.state.stars)) stars", systemImage: "star.fill")
                        .foregroundStyle(.yellow)
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
}
