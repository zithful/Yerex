# Yerex

An original Roblox football (soccer) game built with [Rojo](https://rojo.space).
The feel takes cues from modern console football sims (assisted passing, charged shots,
finesse curl, timing-based tackles, stamina), but it's its own game. It uses no
licensed names, teams, art or audio.

## Run it in Studio

1. Install the toolchain: `rokit install` (or install Rojo 7.4.x yourself).
2. Run `rojo serve` in this folder.
3. In Roblox Studio, open a new **Baseplate** place, install the Rojo plugin, and click **Connect**.
4. Press **Play**. The server builds the stadium, the ball and two AI goalkeepers at runtime.
   The template baseplate is removed automatically.

To test with more than one player, use **Test → Clients and Servers** with 2–4 players.
Teams are auto-balanced.

## Controls

| Action | Keyboard / mouse | Gamepad |
| --- | --- | --- |
| Shoot (hold to charge, release) | Left click / J | B |
| Finesse shot (curls) | Hold G | R1 + B |
| Low driven shot | Hold T | L1 + B |
| Ground pass | E | A |
| Through pass | R | Y |
| Lofted pass | Q | X |
| Standing tackle | F, or shoot without the ball | B without the ball |
| Slide tackle | C, or Q without the ball | X without the ball |
| Sprint | Hold Left Shift | Hold RT |
| Knock-on (push ball into space) | Z | R3 |
| Drag-back | X | L3 |
| Toggle controls help | H | — |

You aim with your movement direction, not the camera. Touch devices get on-screen
Shoot / Pass / Thru / Slide / Sprint buttons.

## How the mechanics work

| Mechanic | Implementation |
| --- | --- |
| Assisted passing | The server picks the teammate inside a 40° cone of your aim and leads them by their velocity. Through passes lead further and into the run. Lofted passes solve a real ballistic arc. |
| Power bar | Hold to charge (1 s for full power). Past 85% (the white marker) you start over-hitting: more spread and the ball rises over the bar. |
| Shot accuracy | Spread grows with distance, sprinting, shooting across your body and over-power. Finesse is more accurate but slower. Low driven stays under the bar. Volleys and headers happen when you press shoot on a loose ball in reach. |
| Curl | Finesse shots launch wide of the target with spin. A Magnus-style force bends them back. |
| Ball flight | Server-side air drag, rolling drag and a reduced "football" gravity (Roblox's default gravity makes balls drop like rocks). |
| Dribbling | Possession is a server concept. The ball is steered in front of the owner's feet, and touches get bigger when sprinting. Fast balls can't be trapped. |
| Stamina / fatigue | Sprinting drains stamina. Below 30% your top speed drops too. |
| Tackling | Standing tackles succeed about 70% of the time from the front and about 30% from behind. A miss costs you a short stumble. Slides poke the ball away, and sliding through a player from behind can be a foul. |
| Goalkeepers | AI keepers track the ball, come off the line to narrow the angle, react to shots after a short delay, dive, catch weaker shots, parry harder ones with their body, claim loose balls in the box, and distribute to the nearest teammate. |
| Match flow | Warm-up, then kickoff countdown, a 5-minute clock, goal celebration, kickoff to the conceding side, and full time. |

Every tunable number lives in [`src/shared/Config.luau`](src/shared/Config.luau).

## Security model

- The ball is always **server-owned**. Clients never get network ownership, so they can't
  teleport it into a goal.
- Clients send only *intent*: action kind, horizontal aim and charge. The server validates
  the type, range and finiteness of every field, rate-limits to 12 actions/s, and checks
  possession, distance and cooldowns before it touches the ball. Aim is flattened and
  normalised, so it can't add power or height.
- Known limitation: character movement is client-owned (standard Roblox), so a speed
  exploit is still possible. Server-side movement sanity checks are on the roadmap.

## Structure

- `src/shared` → `ReplicatedStorage.Shared`: config, pitch geometry, types, remotes, `Util/KickMath` (pure trajectory maths)
- `src/server` → `ServerScriptService.Server`: `PitchBuilder`, `TeamService`, `BallService`, `AthleteService`, `GoalkeeperService`, `MatchService`, `ActionService`
- `src/client` → `StarterPlayerScripts.Client`: `InputController`, `HudController`

## Checks

- Format: `stylua src`
- Lint: `selene src` (also enforced in CI)

## Roadmap

- Out-of-play restarts (throw-ins, corners, goal kicks) instead of boundary walls
- Kick and tackle animations, ball sounds, crowd ambience
- AI outfield players to fill empty slots
- Shielding, jockeying and more skill moves
- Player ratings/traits that modify pace, shot power and accuracy
- Movement anti-cheat, ranked matchmaking, persistent stats (DataStore)
