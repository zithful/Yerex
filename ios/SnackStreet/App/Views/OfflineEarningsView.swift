import SwiftUI
import TycoonCore

struct OfflineEarningsView: View {
    let amount: Double
    let onCollect: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Welcome back!").font(.title2.bold())
            Text("Your managers earned")
                .foregroundStyle(.secondary)
            Text(MoneyFormat.money(amount))
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.money)
            Button("Collect", action: onCollect)
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
        }
        .padding()
    }
}
