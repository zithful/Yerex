import Foundation
import Observation
import TycoonCore
import UIKit

/// Owns the live game state, runs the game loop and saves progress.
@MainActor
@Observable
final class GameStore {
    private static let saveKey = "snackstreet.save.v1"
    private static let tickInterval: Duration = .milliseconds(33)
    private static let autosaveSeconds: Double = 10

    private(set) var state: GameState
    var buyAmount: BuyAmount = .one
    /// Set when the player returns and managers earned money while away.
    var offlineEarnings: Double?

    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored private var lastTick = Date()
    @ObservationIgnored private var lastSave = Date()
    private let lightHaptic = UIImpactFeedbackGenerator(style: .light)
    private let successHaptic = UINotificationFeedbackGenerator()

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.saveKey),
           let saved = try? JSONDecoder().decode(GameState.self, from: data) {
            state = saved
        } else {
            state = GameState()
        }
    }

    // MARK: Lifecycle

    /// Call when the app becomes active: pays offline earnings and starts the loop.
    func resume() {
        let now = Date()
        let away = now.timeIntervalSince(state.lastActive)
        let earned = state.applyOfflineProgress(now: now)
        // Skip the popup for quick interruptions like pulling down Control Center.
        if earned > 0 && away >= 60 {
            offlineEarnings = earned
        }
        lastTick = Date()
        startLoop()
    }

    /// Call when the app leaves the foreground.
    func pause() {
        loopTask?.cancel()
        loopTask = nil
        save()
    }

    private func startLoop() {
        guard loopTask == nil else { return }
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.tickInterval)
                self?.step()
            }
        }
    }

    private func step() {
        let now = Date()
        // Clamp so a debugger pause or hitch can't produce a giant jump.
        let dt = min(now.timeIntervalSince(lastTick), 1)
        lastTick = now
        state.tick(dt)
        state.lastActive = now
        if now.timeIntervalSince(lastSave) >= Self.autosaveSeconds {
            save()
        }
    }

    func save() {
        lastSave = Date()
        state.lastActive = Date()
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Self.saveKey)
        }
    }

    // MARK: Player actions

    func tap(_ business: BusinessDefinition) {
        if state.tap(business.id) {
            lightHaptic.impactOccurred()
        }
    }

    func buy(_ business: BusinessDefinition) {
        if state.buy(business.id, amount: buyAmount) > 0 {
            lightHaptic.impactOccurred()
        }
    }

    func hireManager(_ business: BusinessDefinition) {
        if state.hireManager(business.id) {
            successHaptic.notificationOccurred(.success)
            save()
        }
    }

    func buyUpgrade(_ upgrade: UpgradeDefinition) {
        if state.buyUpgrade(upgrade.id) {
            successHaptic.notificationOccurred(.success)
            save()
        }
    }

    func prestige() {
        if state.prestige() > 0 {
            successHaptic.notificationOccurred(.success)
            save()
        }
    }

    // MARK: View helpers

    func quantityToBuy(_ business: BusinessDefinition) -> Int {
        let owned = state.state(of: business.id).owned
        return buyAmount.quantity(for: business, owned: owned, cash: state.cash)
    }

    func priceToBuy(_ business: BusinessDefinition) -> Double {
        let owned = state.state(of: business.id).owned
        return Economy.cost(of: business, owned: owned, quantity: quantityToBuy(business))
    }

    #if DEBUG
    /// Debug-only cheat for testing late-game screens.
    func debugAddCash(_ amount: Double) {
        state.cash += amount
    }
    #endif
}
