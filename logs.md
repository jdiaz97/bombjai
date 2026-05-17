# Development Log

## Pirate deck pass + audit fixes

Pirate level got the ship-deck feel it was missing: `draw_pirate_deck` (wired to `draw_ground`) paints horizontal plank seams + brass deck nails across the entire arena, and `draw_pirate_overlay` (wired to `draw_overlay`) drifts sea-spray strands across the lower frame with seagulls circling above. `draw_brick_pirate` now picks between crate and wooden barrel by tile seed (50/50), so the destructibles read as mixed cargo instead of a crate maze. Bug audit fixes: punched bombs now consult `tile_blocked` + `.WATER` so they bounce off cannons/snowballs/water instead of dying on top of a cannon (which silently disabled it); kicked-bomb slide + initial-kick checks gained the same gate; `update_single_enemy` skips the cart rider so they can't drop bombs from the cart or BFS off it; `place_bomb` and `enemy_try_place_bomb` got defense-in-depth `tile_blocked` checks.

## Wall border/interior split + cannon + volcanic pass

Walls now read border vs interior via `wall_is_border(c, r)`: the ring around the arena keeps the showy ornaments (snowman, rope-coil flag, starfish, lava drip + ember, rune), interior pillars stop at the base cube + plain texture so they stop distracting from the cannon fire lanes on level 4. Cannons (L4) got the bigger silhouette they deserved — wide cast-iron carriage with brass bands + rivet, fatter barrel with bore + muzzle ring + flash, two wheels, armed/cooldown halo, smoke wisps while cooling. They no longer vanish after firing: `cn.fired` replaced by `cooldown_timer` (one bomb fuse long, `BOMB_TIMER` ticks) and `flash_timer`. `pirate_tile_blocked` makes the cannon tile solid for player + enemies. Volcanic level got its mine feel back: `draw_brick_volcanic` (ore vein + flecks), `draw_volcanic_overlay` (drifting embers above the arena), and the mine cart now carries a swinging miner's lantern + coal + a glowing ore chunk in the bed when idle. Cart riders are now invulnerable (explosions, snowballs); `enemy_is_riding(ei)` mirrors `player_is_riding()`. Fixed cart-squash: an enemy walking into the cart's tile between cart moves now dies — `update_mine_cart` calls `cart_hit_tile(cart.x, cart.y)` every frame, not just on each tile-step.

## Audio + level polish pass

Wired `Sound_Player` with three SFX (explosion / hitHurt / powerUp). `play_sfx(data, volume)` helper short-circuits when `audio_ready` is false so missing audio never crashes the game. Triggers: bomb origin only (`!b.chain`) at vol 0.10 — chained blasts share one boom; any player/enemy death at 0.55; player powerup pickup at 0.70. Patched a bug in `C:\Users\finxo\jai\modules\Sound_Player\os\win32.jai` where the win32 DSound backend hard-coded the 5.1 channel mask even for 8-channel systems, so init failed silently on 7.1 speaker configs — added an `else if num_channels == 8 { channel_mask = KSAUDIO_SPEAKER_7POINT1_SURROUND; }` branch.

Level 3 (Snow): bumped spawn cadence (12–22 s between snowballs, 6 s first-spawn grace, 4 s forming) and added a new `LevelMechanic.tile_blocked` hook so idle/forming snowballs occupy their tile for both player + AI — rolling snowballs still pass through and kill. Level 4 (Pirate): swapped random spawn for a fixed-position layout — 4 cannons (2 left facing RIGHT, 2 right facing LEFT) controlled by the single `CANNON_EDGE_OFFSET` knob. `add_cannon` clears the cannon tile, back tile, and front tile so the trigger + fire path is always clean.

Walls got per-theme renderers (`Theme.wall_renderer` proc field; `draw_wall_3d` delegates). Vanilla stays the boring stone block on purpose; the other four now have unique top-of-block ornaments drawn as billboards: volcanic = pulsing magma vein + lava drip + floating ember; snow = a snowman head bobbing on top (coal eyes, carrot nose, smile dots); pirate = brown rope coil + flag-on-pole (red or skull, picked by tile seed); beach = seed-picked starfish / paired seashells / palm frond fan. `wall_top_screen` helper projects the wall's top-face center to 2D so each renderer can scatter screen-space decorations without re-projecting.

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

## Levels 3 / 4 / 5 — snow, pirate, beach

Three levels live on top of the LevelMechanic table — no edits to the main update or render path. `Player.locked_by_mechanic` generalizes the cart's "the mechanic owns the player" gate so any mechanic (cart, fish) can claim it. New `LevelMechanic` hooks: `draw_overlay` (screen overlay), `on_explosion(bx, by, range)`, `on_player_moved`. New `Tile.WATER` (blocked, beach-only render).

**Level 3 (SNOW).** Cool palette, packed-ice walls, snow-drift bricks, falling snowflake overlay. `Snowball`s spawn every 4–9 s on random empty tiles, take 3 s to form (pulsing while forming). A bomb explosion *orthogonally adjacent* to a formed snowball pushes it away (perpendicular to the bomb), and it rolls tile-by-tile, squishing any non-airborne entity it enters. Snowballs ignore walls/bricks and pass over both; they fall off the world at the border.

**Level 4 (PIRATE).** Dark ship deck, hull walls, crate bricks. Up to 2 `Cannon`s spawn at random tiles facing a direction that has ≥2 open tiles ahead. A bomb whose blast hits a cannon's *back* tile lights the fuse (~1.5 s); on expiry, the cannon spawns a line of explosion tiles up to `CANNON_RANGE=5` in the firing direction (stops at walls/bricks/water like a normal blast). Fired cannons disappear.

**Level 5 (BEACH).** Wooden boardwalk over animated water. `setup_beach` converts a sparse handful of empty interior tiles into `.WATER` (blocked) and places 3 fish on the remaining empty tiles. Stepping onto a fish triggers a 3-phase teleport (sink → travel → emerge) — `on_player_moved` is the hook. Player is `locked_by_mechanic` during teleport; player render is suppressed mid-flight; `draw_beach_overlay` shows bubble bursts at src/dst.

**Adding a level is still purely additive.** Recipe: append a `LevelKind`, write a `*_theme()` constructor, write a `*_mechanic()` constructor (any subset of setup/tick/draw_*/on_*), add cases to `theme_for`/`mechanic_for`, add a key binding.

## Cart polish — block-aligned rails, enemy riders, unlimited rides

Dropped the Bezier finale: every rail corner is now a tile-aligned 90° L-bend (matches the rest of the world's blockiness). `MineCart` gained a `rider: MineCartRider` (NONE / PLAYER / ENEMY) so anyone standing on the start tile mounts up — the AI now uses the cart accidentally too. `cart_hit_tile` skips the active rider (by enemy id) and also kills the player when an enemy is at the wheel. Enemy got the same `hopping / hop_*` fields as the player and an `update_enemy_hops` companion to advance their arc. Dismount eject is shared via `start_player_hop / start_enemy_hop`. After ejecting, `respawn_mine_cart` resets the cart to waypoint[0] / IDLE so it can be ridden again — unlimited uses. AI ticks + explosion damage are both gated on `en.hopping`, matching the player-side invulnerability.

## Cart polish — single config, curved finale, arc dismount

`MINE_CART_WAYPOINTS` is now the single edit point for the rails — both the visual track and the cart's mechanical path read from it. The route extends further right (col 11) and the **final segment** is rendered + traversed as a quadratic Bezier (control at the L-corner) so the cart finishes with a clean curl that exits perpendicular to its entry direction. The cart's render position lerps toward a per-step `mine_cart_visual` array that follows the curve on the final segment. Dismount is no longer a teleport: the player launches into a punched-bomb-style arc hop (1 tile in the cart's exit direction; bounces another tile on a wall/brick/bomb landing; lands on empty/powerup/enemy). New player fields `hopping / hop_dx,dy / hop_from_*,target_* / hop_t` mirror the bomb-punch fields. While airborne the player can't move/bomb/punch/mount, and explosions pass through them.

## Level system + volcanic mine cart

Pulled every level-specific bit into a `Theme` struct (sky/floor/wall/brick/melt/mote palettes) plus `LevelKind` so adding a level means writing a new `*_theme()` constructor and any mechanic state. `current_theme` is read by `draw_background`, `draw_floor_3d`, `draw_wall_3d`, `draw_brick_3d`, `draw_melting_brick_3d`, `init_atmosphere`, and the recent-boom overlay. Level 1 (`VANILLA`) is the original wizard ruins with no level-mechanic; Level 2 (`VOLCANIC`) swaps in basalt/lava colors. `1` / `2` keys reload into the chosen level. Volcanic adds a ridable `MineCart` on a fixed route `(3,2)→(8,2)→(8,10)→(3,10)→(4,9)` (expanded to per-tile L-steps at load time and pre-cleared of walls/bricks so the rails are always passable). Walking onto the cart mounts the player; the cart advances every `CART_MOVE_DELAY` ticks, destroying any brick / killing any enemy on the tile it enters but ignoring powerups and bombs. Player movement / bombs / punch are locked while riding; at route end the player ejects at the first free tile in front of the cart (then the cart sits as a static prop).

## AI plays the game

Target scoring moved off Manhattan onto a planning Dijkstra (`dijkstra_through_bricks`) where bricks are walkable at `BRICK_COST` (≈ one fuse worth of waiting). Distances are realistic now — the AI no longer fixates on a target walled off behind bricks. Phase flow rewritten: blast-line attack (uses `bomb_hits_tile`, not Manhattan); strict-safe pursuit; bust the first brick on the Dijkstra path (or approach it if not adjacent); drop a bomb in place if it'd crack ≥1 brick; walk to the best brick-cluster tile via `find_best_farm_tile`. Powerup-preservation in `enemy_try_place_bomb` is bypassed when the same bomb would land a kill — kill > loot. KICK/PUNCH powerups carry `USELESS_PUP_PENALTY` since enemies can't use them. Result: enemies bust through walls to reach the player, farm bricks while idle, and snipe when a rival drifts into their fire line.
