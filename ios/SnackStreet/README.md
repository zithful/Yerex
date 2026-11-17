# Snack Street Tycoon (iOS)

An idle tycoon game for iPhone. You start with one lemonade stand and grow a street-food
empire. Tap businesses to cook, buy more units, hire managers to automate them, buy
upgrades, and franchise for stars that permanently boost profit.

SwiftUI, iOS 17+, iPhone, portrait.

## Run it on your Mac

You need a Mac with Xcode 15 or newer, which is free from the Mac App Store.

```bash
brew install xcodegen          # one-time
cd ios/SnackStreet
xcodegen generate              # creates SnackStreet.xcodeproj from project.yml
open SnackStreet.xcodeproj
```

In Xcode, pick an iPhone simulator and press **Run** (⌘R).

To run on your own iPhone, select the **SnackStreet** target → **Signing & Capabilities** →
choose your Apple ID team. You can also change the bundle identifier
(`com.example.snackstreet`) to something unique.

Run the logic tests in Terminal:

```bash
cd ios/SnackStreet/Packages/TycoonCore
swift test
```

## How it plays

| System | Details |
| --- | --- |
| Businesses | 8 food businesses, from 🍋 Lemonade Stand to 🏬 Food Court. Each new one appears once you own the previous one. |
| Tapping | Tap a business's icon to run one production cycle and get paid when it finishes. |
| Buying | Buy ×1, ×10, ×100 or Max. Each unit costs a bit more than the last. |
| Speed milestones | Owning 25, 50, 100, 200, 300, 400 or 500 units of a business doubles its speed each time. |
| Managers | Run a business automatically, forever. Managed businesses also earn while the app is closed (up to 8 hours). |
| Upgrades | Profit ×3 for one business, or ×3 / ×5 for everything. |
| Franchise (prestige) | After earning $1T in a run, reset for stars. Each star gives +2% profit permanently. |
| Saving | Autosaves every 10 seconds and whenever the app is backgrounded. |

All balancing numbers are in
[`Packages/TycoonCore/Sources/TycoonCore/Catalog.swift`](Packages/TycoonCore/Sources/TycoonCore/Catalog.swift).

## Code layout

- `Packages/TycoonCore`: pure game logic (economy formulas, game state, simulation,
  number formatting) plus unit tests. It doesn't depend on UIKit or SwiftUI.
- `App/GameStore.swift`: runs the game loop (30 Hz), saves, pays offline earnings and
  triggers haptics.
- `App/Views`: SwiftUI screens (Street, Managers, Upgrades, Franchise).
- `project.yml`: XcodeGen spec. The `.xcodeproj` is generated, not committed.

## Next ideas

- App icon and art (the icon slot is empty for now)
- Sound effects and juicier animations (coin pops, cha-ching on cycle complete)
- Achievements and Game Center leaderboards
- Timed events and daily rewards
- Optional rewarded ads or in-app purchases (StoreKit 2)
