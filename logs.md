# Development Log

## Foundation — game in Jai

Wizard-themed Bomberman in `game.jai` using Simp + Window_Creation + Input. 15×13 grid, walls + bricks, smooth lerped movement, BFS-driven enemy AI (3 warlocks), bomb chain reactions, powerups (bomb / fire / kick / punch) with melt animations.

## Render layer — 3D look

`LEFT_HANDED` render target (top-left origin), F11 fullscreen with a centered aspect-preserving viewport (no stretching). Then a switch to a software-projected 3D pipeline: custom perspective + view matrices feed `project(Vector3) → Vector2`, walls/bricks render as shaded cubes built from 2D triangles, floor/characters/bombs/powerups stay as billboards at projected positions. Painter's algorithm row-by-row, no depth buffer. Camera pitch ~82° (near-zenithal) so layout is easy to read.

## Feedback layer — DeathFx + polish

Unified `DeathFx` system (kinds: BIG / SMALL / BOING / DUST) covers every destruction and reaction: brick / powerup / enemy / player death, bomb placement, powerup pickup, footsteps, kick-slide trail, bomb hop landings. `game_over_delay` lets the death animation play out before the screen flips. Hit / victory screen flashes, edge vignette. Walls get a mortar cross + highlight fleck on top, bricks get a rim + grain on top, floor draws AO strips against adjacent solid tiles. Cube lighting tightened for stronger contrast.

## AI rewrite — no more dancing

Pursuit BFS gained an `avoid_blast` flag, fixing the loop where the enemy pathfound back through the bomb it just escaped. Single danger check (`is_in_blast` only). When in danger the enemy commits to a flee destination until it's actually reached. `last_x, last_y` prevents immediate U-turns. When safe but with no blast-free path, the enemy stays put instead of shuffling.

## Sprites — directional + knocked out

All three enemies now react to facing (red demon horns / purple wizard hat / green necromancer hood reorient, pupils track). When stunned, characters get X-eyes that wobble plus the existing yellow stars — the 1s knock-down is now clearly readable.

## Punch arc-hop + skates

Punching launches the bomb on a 2-tile arc; if the landing tile has a wall/brick or a stunned character, the bomb bounces another **1 tile** and re-checks. Powerup → destroys it and lands. Edge → wraps via modulo. Bomb timer freezes while airborne; BOING FX on every landing; ground shadow stays under the arc. Kicks now leave a small dust trail per tile.

New `SKATE` powerup. Movement speed moved off the global constants onto per-entity `move_delay` fields (player + enemy), and base values slowed (player `8 → 10`, enemy `16 → 20`). Each skate shaves **1 frame** off `move_delay`; floors at 7 (player) / 16 (enemy). Intentionally minor — top out at ~30% speed boost for the player so it's a filler upgrade, not a must-grab.

## Visual overhaul — atmosphere + game feel

Backdrop replaced with multi-stop sky gradient, glowing moon, layered aurora curtain, ~200 twinkling stars and occasional shooting streaks. ~90 ambient magic motes drift up through the play space at projected world positions. Pulsing magenta floor pools follow every bomb (pulse rate ramps as fuse runs down); explosions paint a bright pool plus an expanding floor shockwave ring. Bombs got an aura, dancing fuse sparks, plasma arcs near detonation, and a faster pulse near boom. Explosions are layered — halo, flash, primary spokes, secondary spokes, embers, core. Walls have soft magenta pulsing runes on top. Player + enemies carry orbiting motes in their glow color and a soft floor halo. HUD repainted as a glowing chip strip with pulsing icon halos; game-over screen is a rotating ray/halo + (victory only) decorative ring. Camera shake (decaying noise on eye/target) fires on every explosion, harder on chain reactions — tuned subtle.

## Readability + drop-on-death

Powerups rebuilt at tile-scale with bold silhouettes. The BOMB powerup is now a 4-pointed magic gem with a "+" emblem (the earlier bomb-sphere icon read as a live bomb). FIRE is a drop-shaped flame, KICK a cyan boot, PUNCH a gold boxing glove with knuckle ridges, SKATE a blue skate with three wheels. Each sits on a soft pedestal halo. Vignette switched from boxy corner overlays to four gradient-quad edge fades — no square corners. When an enemy dies they scatter every picked-up BOMB/FIRE/SKATE across random empty tiles, with a small pop where each lands.

## Tunables + comments

Pulled shake into a single master knob `SHAKE_INTENSITY` (0 disables, 0.5 default subtle, 2 arcade), with `SHAKE_PER_BOOM` / `SHAKE_PER_CHAIN` / `SHAKE_DECAY` / `SHAKE_MAX` exposed alongside. Top-level constants block reorganised into labelled sections (Board shape / Fuse + explosion / Stun + projectile / Movement cadence / Powerup economy) with a comment on each explaining unit and meaning; `BOMB_TIMER` etc. now spell out "ticks @ 60 Hz".

## AI stops vaporising loot

Targets are now typed (`TargetKind.ENTITY` vs `.POWERUP`); the chaser only drops a bomb when finishing an entity. `enemy_try_place_bomb` refuses any bomb whose blast (computed via the new `bomb_hits_tile` helper) would hit an unclaimed powerup — this also blocks opportunistic brick-busting that would have cratered nearby pickups. Powerup interest bumped from -4 → POWERUP_INTEREST (=7) Manhattan-tile head start so enemies divert to collect loot more eagerly.

## AI plays the game

Target scoring moved off Manhattan onto a planning Dijkstra (`dijkstra_through_bricks`) where bricks are walkable at `BRICK_COST` (≈ one fuse worth of waiting). Distances are realistic now — the AI no longer fixates on a target walled off behind bricks. Phase flow rewritten: blast-line attack (uses `bomb_hits_tile`, not Manhattan); strict-safe pursuit; bust the first brick on the Dijkstra path (or approach it if not adjacent); drop a bomb in place if it'd crack ≥1 brick; walk to the best brick-cluster tile via `find_best_farm_tile`. Powerup-preservation in `enemy_try_place_bomb` is bypassed when the same bomb would land a kill — kill > loot. KICK/PUNCH powerups carry `USELESS_PUP_PENALTY` since enemies can't use them. Result: enemies bust through walls to reach the player, farm bricks while idle, and snipe when a rival drifts into their fire line.
