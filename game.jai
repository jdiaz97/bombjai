#import "Basic";
#import "Math";
#import "Random";
#import "Window_Creation";
Input :: #import "Input";
#import "String";
#import "System";
#import "GL";

Simp :: #import "Simp";
Sound :: #import "Sound_Player"(VERBOSE = false);
Sound_Data :: Sound.Sound_Data;

// All gameplay timings below are tick counts. The game runs vsync-locked at the
// monitor refresh, intended for 60 Hz — so divide a *_FRAMES/*_DURATION value by
// 60 to convert it to seconds.
TARGET_FPS :: 60;

// ─── Board shape ────────────────────────────────────────────────────────────
COLS :: 15;                  // grid width in tiles
ROWS :: 13;                  // grid height in tiles
TILE :: 60;                  // one tile's size in world units / pixels

// ─── Fuse + explosion timings (ticks @ 60 Hz) ───────────────────────────────
BOMB_TIMER             :: 135;   // ticks from bomb placement to detonation (~2.25 s)
EXPLOSION_DURATION     :: 20;    // ticks an explosion sprite is visible on the floor
MELT_DURATION          :: 14;    // ticks a destroyed brick spends fading away
POWERUP_SPAWN_DELAY    :: 35;    // ticks a fresh powerup is invisible/ungrabbable for
POWERUP_MELT_DURATION  :: 12;    // ticks for a powerup's pickup/destroy animation

// ─── Stun & projectile motion (ticks @ 60 Hz) ──────────────────────────────
STUN_DURATION          :: 60;    // ticks an enemy stays knocked out after being punched
PLAYER_STUN            :: 60;    // ticks the player is stunned when hit by a thrown bomb
BOMB_SLIDE_SPEED       :: 4;     // ticks per tile traversed by a kicked bomb sliding
PUNCH_HOP_FRAMES       :: 14;    // ticks per single tile in a punched bomb's arc hop
PUNCH_ARC_HEIGHT       :: 38.0;  // peak height (pixels) of a punched bomb mid-arc
LERP_SPEED             :: 0.25;  // per-tick lerp factor for character render position (0..1)

// ─── Movement cadence (ticks per step) ──────────────────────────────────────
PLAYER_MOVE_DELAY      :: 10;    // base ticks between player move steps (start)
PLAYER_MOVE_DELAY_MIN  :: 7;     // floor for player move delay after skate pickups
ENEMY_MOVE_DELAY       :: 20;    // base ticks between enemy AI move steps (start)
ENEMY_MOVE_DELAY_MIN   :: 16;    // floor for enemy move delay after skate pickups
SKATE_BOOST_PLAYER     :: 1;     // ticks shaved off player move delay per SKATE pickup
SKATE_BOOST_ENEMY      :: 1;     // ticks shaved off enemy move delay per SKATE pickup
AI_BOMB_DIST           :: 3;     // (legacy, unused — kept for reference)

// ─── Powerup economy ────────────────────────────────────────────────────────
START_MAX_BOMBS        :: 1;     // starting simultaneous bomb cap (player + enemies)
START_FIRE_RANGE       :: 1;     // starting fire range in tiles (player)
ENEMY_FIRE_RANGE       :: 1;     // starting fire range in tiles (enemy)
POWERUP_DROP_RATE      :: 0.5;   // probability a destroyed brick drops a powerup
BRICK_DENSITY          :: 0.65;  // probability a non-spawn tile starts as a brick
KICK_MAX               :: 4;     // map-lifetime cap on spawned KICK powerups
PUNCH_MAX              :: 4;     // map-lifetime cap on spawned PUNCH powerups
SKATE_MAX              :: 6;     // map-lifetime cap on spawned SKATE powerups

// ─── Enemy AI tuning ────────────────────────────────────────────────────────
// Powerups are "pretended closer" to the enemy by this many tiles when picking
// a target. Higher → enemies abandon hunts more aggressively to grab loot.
POWERUP_INTEREST       :: 7;
// Walking *through* a brick in the planning Dijkstra costs this many tile-steps
// (one bomb fuse worth of waiting + the explosion + the step past). Roughly:
// BOMB_TIMER / ENEMY_MOVE_DELAY ≈ 7, +1 for the step itself.
BRICK_COST             :: 8;
// Score offset added to other enemies as targets, so the AI prefers the player
// and powerups over picking fights with siblings.
ENEMY_AVOIDANCE        :: 3;
// Enemies can't use KICK or PUNCH, so make them slightly less appealing as
// targets than the powerups they actually benefit from.
USELESS_PUP_PENALTY    :: 4;
// Sentinel for "unreachable" in the Dijkstra field.
DIJK_INF               :: 999999;

WINDOW_W :: COLS * TILE;
WINDOW_H :: ROWS * TILE;

// ─── Level system ───────────────────────────────────────────────────────────
// Everything that makes a level visually or mechanically distinct is bundled
// into a Theme (colors used by every drawing routine) plus a small set of
// level-specific globals (mine cart, etc). Drawing code reads from
// `current_theme`; mechanic code branches on `current_level`. Add a new level
// by writing a new theme constructor + any new mechanic state.

LevelKind :: enum u8 {
    VANILLA;    // Level 1 — wizard ruins. No level-mechanic, pure Bomberman.
    VOLCANIC;   // Level 2 — mine. Rock blocks + a ridable mine cart on rails.
    SNOW;       // Level 3 — blizzard. Snowballs form, get punched by bombs, roll over everything, squish characters.
    PIRATE;     // Level 4 — deck. Two cannons spawn; a bomb on the back-tile lights their fuse, then they fire a long fire line.
    BEACH;      // Level 5 — boardwalk. Some tiles are exposed water (blocked); fish on EMPTY tiles swallow + teleport.
}

Theme :: struct {
    // Sky gradient stops (top → bottom of the background quad strip)
    sky_top:      Vector4;
    sky_high:     Vector4;
    sky_mid:      Vector4;
    sky_horizon:  Vector4;
    sky_under:    Vector4;
    sky_floor:    Vector4;

    // Celestial body (moon for vanilla; smoldering sun for volcanic)
    body_glow:    Vector4;
    body_core:    Vector4;
    body_hot:     Vector4;

    // Horizon band pulse
    horizon_band:  Vector4;
    horizon_sliver: Vector4;

    // 3-layer "aurora" / sky curtain. Volcanic repurposes these as smoke + ember bands.
    aurora_0a, aurora_0b: Vector4;
    aurora_1a, aurora_1b: Vector4;
    aurora_2a, aurora_2b: Vector4;

    // Floor tiles (checkerboard a/b)
    floor_a_base:   Vector4;
    floor_a_accent: Vector4;
    floor_b_base:   Vector4;
    floor_b_accent: Vector4;
    floor_ao:       Vector4;
    floor_speck:    Vector4;

    // Indestructible walls
    wall_base:   Vector4;
    wall_top:    Vector4;
    wall_edge:   Vector4;
    wall_mortar: Vector4;
    wall_rune:   Vector4;  // pulsing fleck on top of walls

    // Destructible "bricks"
    brick_base:  Vector4;
    brick_top:   Vector4;
    brick_rim:   Vector4;
    brick_inner: Vector4;
    brick_grain: Vector4;
    brick_face:  Vector4;

    // Melting-brick tint
    melt_base: Vector4;
    melt_top:  Vector4;

    // Recent-boom screen overlay
    boom_tint: Vector4;

    // Ambient mote palette weights (3 mote types blend by these RGB hints)
    mote_a: Vector4;
    mote_b: Vector4;
    mote_c: Vector4;

    // Optional per-level renderers. Null → use the default stone wall +
    // mortar brick. Themes that set these get a fully custom block silhouette.
    wall_renderer:  #type (c: int, r: int);
    brick_renderer: #type (c: int, r: int);
}

// LevelMechanic is the one place levels hook into the main loop. Add a new
// level by writing its setup/tick/draw procs and a mechanic constructor that
// fills the table; the main update + render call through these pointers so
// inactive levels pay nothing per frame. Null fields = no hook for that slot.
LevelMechanic :: struct {
    setup:           #type ();           // once after init_grid on level load
    tick:            #type ();           // every update tick
    draw_ground:     #type ();           // between floor lights and walls
    draw_row:        #type (r: int);     // inside the per-row painter loop
    draw_overlay:    #type ();           // after the world, before HUD
    on_explosion:    #type (bx: int, by: int, range: int);   // bomb just exploded
    on_player_moved: #type ();           // player.x/y just changed via move_player
    tile_blocked:    #type (x: int, y: int) -> bool;         // dynamic per-tile block (e.g. snowballs)
}

current_level: LevelKind;
current_theme: Theme;
current_mechanic: LevelMechanic;

vanilla_theme :: () -> Theme {
    t: Theme;
    t.sky_top      = col(0.025, 0.012, 0.110, 1);
    t.sky_high     = col(0.062, 0.024, 0.180, 1);
    t.sky_mid      = col(0.205, 0.055, 0.290, 1);
    t.sky_horizon  = col(0.420, 0.110, 0.395, 1);
    t.sky_under    = col(0.070, 0.025, 0.135, 1);
    t.sky_floor    = col(0.020, 0.012, 0.058, 1);

    t.body_glow    = col(1.0, 0.78, 0.92, 1);
    t.body_core    = col(1.0, 0.93, 0.98, 1);
    t.body_hot     = col(0.96, 0.82, 0.94, 1);

    t.horizon_band   = col(1.0, 0.36, 0.78, 1);
    t.horizon_sliver = col(1.0, 0.78, 0.96, 1);

    t.aurora_0a = col(0.40, 0.96, 0.78, 1);
    t.aurora_0b = col(0.55, 0.42, 1.0,  1);
    t.aurora_1a = col(0.60, 0.40, 1.0,  1);
    t.aurora_1b = col(1.0,  0.42, 0.85, 1);
    t.aurora_2a = col(0.32, 0.78, 1.0,  1);
    t.aurora_2b = col(0.95, 0.70, 1.0,  1);

    t.floor_a_base   = col(0.196, 0.180, 0.290, 1);
    t.floor_a_accent = col(0.169, 0.157, 0.267, 1);
    t.floor_b_base   = col(0.220, 0.204, 0.318, 1);
    t.floor_b_accent = col(0.196, 0.184, 0.302, 1);
    t.floor_ao       = col(0.012, 0.008, 0.024, 0.55);
    t.floor_speck    = col(0.706, 0.580, 0.961, 1);

    t.wall_base   = col(0.314, 0.290, 0.408, 1);
    t.wall_top    = col(0.494, 0.463, 0.624, 1);
    t.wall_edge   = col(0.173, 0.157, 0.251, 1);
    t.wall_mortar = col(0.149, 0.137, 0.224, 1);
    t.wall_rune   = col(0.65, 0.42, 1.0, 1);

    t.brick_base  = col(0.580, 0.439, 0.227, 1);
    t.brick_top   = col(0.769, 0.620, 0.376, 1);
    t.brick_rim   = col(0.341, 0.231, 0.098, 1);
    t.brick_inner = col(0.847, 0.694, 0.439, 1);
    t.brick_grain = col(0.435, 0.314, 0.157, 1);
    t.brick_face  = col(0.353, 0.239, 0.102, 0.85);

    t.melt_base = col(0.486, 0.302, 1.0, 1);
    t.melt_top  = col(0.702, 0.533, 1.0, 1);

    t.boom_tint = col(1.0, 0.55, 0.85, 1);

    t.mote_a = col(0.85, 0.65, 1.0, 1);   // lavender
    t.mote_b = col(0.55, 0.92, 1.0, 1);   // cyan
    t.mote_c = col(1.0, 0.88, 0.55, 1);   // soft gold
    return t;
}

volcanic_theme :: () -> Theme {
    t: Theme;
    // Dark cavern sky shading down into magma glow at the horizon.
    t.sky_top      = col(0.025, 0.012, 0.020, 1);
    t.sky_high     = col(0.075, 0.025, 0.025, 1);
    t.sky_mid      = col(0.180, 0.055, 0.030, 1);
    t.sky_horizon  = col(0.690, 0.220, 0.060, 1);
    t.sky_under    = col(0.140, 0.040, 0.020, 1);
    t.sky_floor    = col(0.045, 0.020, 0.015, 1);

    // "Sun" is a smoldering ember — orange core, dim red halo.
    t.body_glow    = col(1.0, 0.45, 0.18, 1);
    t.body_core    = col(1.0, 0.78, 0.36, 1);
    t.body_hot     = col(1.0, 0.92, 0.55, 1);

    t.horizon_band   = col(1.0, 0.36, 0.10, 1);
    t.horizon_sliver = col(1.0, 0.85, 0.45, 1);

    // "Aurora" layers reused as drifting smoke + ember bands.
    t.aurora_0a = col(0.18, 0.12, 0.10, 1);  // smoke
    t.aurora_0b = col(0.62, 0.30, 0.15, 1);
    t.aurora_1a = col(0.95, 0.45, 0.15, 1);  // ember sheet
    t.aurora_1b = col(0.30, 0.10, 0.05, 1);
    t.aurora_2a = col(1.0,  0.65, 0.25, 1);
    t.aurora_2b = col(0.45, 0.18, 0.08, 1);

    // Floor: cracked basalt with hot magma fissures peeking through.
    t.floor_a_base   = col(0.110, 0.078, 0.078, 1);
    t.floor_a_accent = col(0.090, 0.060, 0.060, 1);
    t.floor_b_base   = col(0.135, 0.090, 0.080, 1);
    t.floor_b_accent = col(0.110, 0.075, 0.070, 1);
    t.floor_ao       = col(0.020, 0.005, 0.000, 0.65);
    t.floor_speck    = col(1.0, 0.55, 0.18, 1);   // glowing ember on the floor

    // Walls: dark obsidian with hot orange seams.
    t.wall_base   = col(0.180, 0.110, 0.105, 1);
    t.wall_top    = col(0.320, 0.200, 0.180, 1);
    t.wall_edge   = col(0.080, 0.040, 0.035, 1);
    t.wall_mortar = col(0.620, 0.220, 0.060, 1);  // visible lava crack
    t.wall_rune   = col(1.0, 0.55, 0.18, 1);

    // Bricks: weathered rock with brown/orange tones (mine rubble).
    t.brick_base  = col(0.380, 0.260, 0.180, 1);
    t.brick_top   = col(0.560, 0.400, 0.260, 1);
    t.brick_rim   = col(0.210, 0.130, 0.080, 1);
    t.brick_inner = col(0.640, 0.480, 0.320, 1);
    t.brick_grain = col(0.260, 0.170, 0.100, 1);
    t.brick_face  = col(0.220, 0.130, 0.070, 0.85);

    t.melt_base = col(1.0, 0.55, 0.18, 1);
    t.melt_top  = col(1.0, 0.80, 0.40, 1);

    t.boom_tint = col(1.0, 0.45, 0.12, 1);

    t.mote_a = col(1.0,  0.55, 0.18, 1);   // ember orange
    t.mote_b = col(1.0,  0.80, 0.35, 1);   // hot yellow
    t.mote_c = col(0.55, 0.30, 0.20, 1);   // soot brown
    t.wall_renderer = draw_wall_volcanic;
    return t;
}

snow_theme :: () -> Theme {
    t: Theme;
    t.sky_top      = col(0.040, 0.080, 0.180, 1);
    t.sky_high     = col(0.085, 0.135, 0.270, 1);
    t.sky_mid      = col(0.180, 0.275, 0.460, 1);
    t.sky_horizon  = col(0.560, 0.700, 0.880, 1);
    t.sky_under    = col(0.220, 0.310, 0.500, 1);
    t.sky_floor    = col(0.075, 0.115, 0.230, 1);

    t.body_glow    = col(0.92, 0.96, 1.00, 1);  // pale winter sun
    t.body_core    = col(1.00, 0.98, 0.94, 1);
    t.body_hot     = col(0.88, 0.94, 1.00, 1);

    t.horizon_band   = col(0.85, 0.92, 1.00, 1);
    t.horizon_sliver = col(1.00, 1.00, 1.00, 1);

    t.aurora_0a = col(0.55, 0.78, 1.00, 1);
    t.aurora_0b = col(0.85, 0.95, 1.00, 1);
    t.aurora_1a = col(0.75, 0.90, 1.00, 1);
    t.aurora_1b = col(0.40, 0.55, 0.85, 1);
    t.aurora_2a = col(0.92, 0.98, 1.00, 1);
    t.aurora_2b = col(0.65, 0.80, 0.95, 1);

    t.floor_a_base   = col(0.78, 0.84, 0.92, 1);
    t.floor_a_accent = col(0.70, 0.78, 0.88, 1);
    t.floor_b_base   = col(0.84, 0.90, 0.96, 1);
    t.floor_b_accent = col(0.76, 0.82, 0.90, 1);
    t.floor_ao       = col(0.18, 0.22, 0.32, 0.50);
    t.floor_speck    = col(1.00, 1.00, 1.00, 1);

    t.wall_base   = col(0.55, 0.66, 0.82, 1);  // packed ice
    t.wall_top    = col(0.78, 0.88, 0.98, 1);
    t.wall_edge   = col(0.34, 0.44, 0.62, 1);
    t.wall_mortar = col(0.42, 0.55, 0.78, 1);
    t.wall_rune   = col(0.70, 0.92, 1.00, 1);

    t.brick_base  = col(0.86, 0.91, 0.96, 1);  // snow drift
    t.brick_top   = col(0.95, 0.98, 1.00, 1);
    t.brick_rim   = col(0.55, 0.65, 0.80, 1);
    t.brick_inner = col(1.00, 1.00, 1.00, 1);
    t.brick_grain = col(0.62, 0.72, 0.86, 1);
    t.brick_face  = col(0.50, 0.62, 0.80, 0.85);

    t.melt_base = col(0.78, 0.88, 1.00, 1);
    t.melt_top  = col(1.00, 1.00, 1.00, 1);

    t.boom_tint = col(0.85, 0.92, 1.00, 1);

    t.mote_a = col(1.00, 1.00, 1.00, 1);
    t.mote_b = col(0.78, 0.90, 1.00, 1);
    t.mote_c = col(0.62, 0.78, 0.95, 1);
    t.wall_renderer  = draw_wall_snow;
    t.brick_renderer = draw_brick_snow;
    return t;
}

pirate_theme :: () -> Theme {
    t: Theme;
    t.sky_top      = col(0.030, 0.055, 0.110, 1);
    t.sky_high     = col(0.060, 0.095, 0.170, 1);
    t.sky_mid      = col(0.180, 0.240, 0.340, 1);
    t.sky_horizon  = col(0.480, 0.420, 0.300, 1);
    t.sky_under    = col(0.140, 0.180, 0.260, 1);
    t.sky_floor    = col(0.040, 0.060, 0.110, 1);

    t.body_glow    = col(1.00, 0.85, 0.55, 1);
    t.body_core    = col(1.00, 0.95, 0.78, 1);
    t.body_hot     = col(1.00, 0.90, 0.65, 1);

    t.horizon_band   = col(0.85, 0.60, 0.30, 1);
    t.horizon_sliver = col(1.00, 0.85, 0.55, 1);

    t.aurora_0a = col(0.60, 0.75, 0.85, 1);  // sea spray
    t.aurora_0b = col(0.30, 0.45, 0.55, 1);
    t.aurora_1a = col(0.45, 0.55, 0.65, 1);
    t.aurora_1b = col(0.85, 0.75, 0.55, 1);
    t.aurora_2a = col(0.75, 0.65, 0.45, 1);
    t.aurora_2b = col(0.35, 0.40, 0.50, 1);

    t.floor_a_base   = col(0.42, 0.28, 0.16, 1);  // wood deck
    t.floor_a_accent = col(0.35, 0.22, 0.12, 1);
    t.floor_b_base   = col(0.48, 0.32, 0.18, 1);
    t.floor_b_accent = col(0.40, 0.26, 0.14, 1);
    t.floor_ao       = col(0.05, 0.03, 0.02, 0.60);
    t.floor_speck    = col(0.85, 0.65, 0.35, 1);

    t.wall_base   = col(0.28, 0.18, 0.10, 1);  // ship hull
    t.wall_top    = col(0.48, 0.32, 0.18, 1);
    t.wall_edge   = col(0.14, 0.08, 0.04, 1);
    t.wall_mortar = col(0.60, 0.42, 0.20, 1);  // brass bolts
    t.wall_rune   = col(0.90, 0.70, 0.30, 1);

    t.brick_base  = col(0.42, 0.28, 0.16, 1);  // crate
    t.brick_top   = col(0.60, 0.42, 0.22, 1);
    t.brick_rim   = col(0.22, 0.14, 0.08, 1);
    t.brick_inner = col(0.72, 0.55, 0.30, 1);
    t.brick_grain = col(0.30, 0.20, 0.10, 1);
    t.brick_face  = col(0.25, 0.16, 0.08, 0.85);

    t.melt_base = col(0.62, 0.42, 0.20, 1);
    t.melt_top  = col(0.85, 0.62, 0.32, 1);

    t.boom_tint = col(1.00, 0.55, 0.20, 1);

    t.mote_a = col(0.85, 0.70, 0.45, 1);   // dust
    t.mote_b = col(1.00, 0.85, 0.55, 1);   // lantern glow
    t.mote_c = col(0.55, 0.60, 0.70, 1);   // sea spray
    t.wall_renderer  = draw_wall_pirate;
    t.brick_renderer = draw_brick_pirate;
    return t;
}

beach_theme :: () -> Theme {
    t: Theme;
    t.sky_top      = col(0.050, 0.180, 0.380, 1);
    t.sky_high     = col(0.140, 0.380, 0.620, 1);
    t.sky_mid      = col(0.350, 0.620, 0.820, 1);
    t.sky_horizon  = col(0.85, 0.75, 0.55, 1);   // warm sandy haze
    t.sky_under    = col(0.260, 0.500, 0.680, 1);
    t.sky_floor    = col(0.080, 0.220, 0.420, 1);

    t.body_glow    = col(1.00, 0.95, 0.70, 1);
    t.body_core    = col(1.00, 1.00, 0.90, 1);
    t.body_hot     = col(1.00, 0.90, 0.60, 1);

    t.horizon_band   = col(1.00, 0.78, 0.45, 1);
    t.horizon_sliver = col(1.00, 0.95, 0.78, 1);

    t.aurora_0a = col(0.60, 0.85, 1.00, 1);
    t.aurora_0b = col(0.95, 0.80, 0.55, 1);
    t.aurora_1a = col(0.85, 0.95, 1.00, 1);
    t.aurora_1b = col(0.40, 0.65, 0.85, 1);
    t.aurora_2a = col(1.00, 0.85, 0.55, 1);
    t.aurora_2b = col(0.55, 0.75, 0.95, 1);

    t.floor_a_base   = col(0.62, 0.42, 0.22, 1);  // wood plank
    t.floor_a_accent = col(0.52, 0.34, 0.16, 1);
    t.floor_b_base   = col(0.68, 0.46, 0.24, 1);
    t.floor_b_accent = col(0.58, 0.38, 0.18, 1);
    t.floor_ao       = col(0.05, 0.03, 0.02, 0.55);
    t.floor_speck    = col(0.95, 0.85, 0.60, 1);

    t.wall_base   = col(0.42, 0.32, 0.22, 1);  // weathered post
    t.wall_top    = col(0.62, 0.50, 0.36, 1);
    t.wall_edge   = col(0.24, 0.18, 0.12, 1);
    t.wall_mortar = col(0.80, 0.65, 0.40, 1);
    t.wall_rune   = col(1.00, 0.92, 0.65, 1);

    t.brick_base  = col(0.55, 0.40, 0.24, 1);  // driftwood
    t.brick_top   = col(0.75, 0.58, 0.36, 1);
    t.brick_rim   = col(0.32, 0.22, 0.12, 1);
    t.brick_inner = col(0.85, 0.68, 0.42, 1);
    t.brick_grain = col(0.40, 0.28, 0.16, 1);
    t.brick_face  = col(0.30, 0.20, 0.10, 0.85);

    t.melt_base = col(0.85, 0.65, 0.35, 1);
    t.melt_top  = col(1.00, 0.85, 0.55, 1);

    t.boom_tint = col(1.00, 0.80, 0.50, 1);

    t.mote_a = col(1.00, 0.92, 0.68, 1);
    t.mote_b = col(0.55, 0.85, 1.00, 1);
    t.mote_c = col(1.00, 0.78, 0.45, 1);
    t.wall_renderer  = draw_wall_beach;
    t.brick_renderer = draw_brick_beach;
    return t;
}

theme_for :: (kind: LevelKind) -> Theme {
    if kind == .VOLCANIC return volcanic_theme();
    if kind == .SNOW     return snow_theme();
    if kind == .PIRATE   return pirate_theme();
    if kind == .BEACH    return beach_theme();
    return vanilla_theme();
}

// Mechanic constructors. Each one returns the dispatch table for that level.
// Vanilla has no mechanic — all-null table, so dispatch sites become noops.
vanilla_mechanic :: () -> LevelMechanic {
    return .{};
}

volcanic_mechanic :: () -> LevelMechanic {
    m: LevelMechanic;
    m.setup       = setup_mine_cart;
    m.tick        = update_mine_cart;
    m.draw_ground = draw_mine_cart_rails;
    m.draw_row    = draw_mine_cart_row;
    return m;
}

snow_mechanic :: () -> LevelMechanic {
    m: LevelMechanic;
    m.setup        = setup_snow;
    m.tick         = tick_snow;
    m.draw_row     = draw_snowballs_row;
    m.draw_overlay = draw_snow_overlay;
    m.on_explosion = on_explosion_snow;
    m.tile_blocked = snow_tile_blocked;
    return m;
}

pirate_mechanic :: () -> LevelMechanic {
    m: LevelMechanic;
    m.setup        = setup_pirate;
    m.tick         = tick_pirate;
    m.draw_row     = draw_cannons_row;
    m.on_explosion = on_explosion_pirate;
    return m;
}

beach_mechanic :: () -> LevelMechanic {
    m: LevelMechanic;
    m.setup           = setup_beach;
    m.tick            = tick_beach;
    m.draw_row        = draw_fishes_row;
    m.draw_overlay    = draw_beach_overlay;
    m.on_player_moved = on_player_moved_beach;
    return m;
}

mechanic_for :: (kind: LevelKind) -> LevelMechanic {
    if kind == .VOLCANIC return volcanic_mechanic();
    if kind == .SNOW     return snow_mechanic();
    if kind == .PIRATE   return pirate_mechanic();
    if kind == .BEACH    return beach_mechanic();
    return vanilla_mechanic();
}

Tile :: enum u8 {
    EMPTY;
    WALL;
    BRICK;
    BRICK_MELTING;
    WATER;   // beach only — blocks movement + blast, rendered as exposed water
}

Dir :: enum u8 {
    UP;
    DOWN;
    LEFT;
    RIGHT;
}

// What the AI is currently chasing. Lets the chaser pick the right finisher:
// ENTITY targets get bombed when in range; POWERUP targets are stepped onto and
// MUST NOT be bombed (that would destroy them).
TargetKind :: enum u8 {
    NONE;
    ENTITY;
    POWERUP;
}

PType :: enum u8 {
    BOMB;
    FIRE;
    KICK;
    PUNCH;
    SKATE;
}

Player :: struct {
    x, y: int;
    rx, ry: float;
    max_bombs: int;
    fire_range: int;
    dir: Dir;
    has_kick: bool;
    has_punch: bool;
    stun_timer: int;
    move_delay: int;
    skate_count: int;

    // Arc-hop state — used when ejected from a mine cart. Behaves like a
    // punched bomb: jump 1 tile in the hop direction, bounce another tile if
    // the landing is a wall/brick/bomb, otherwise land. Invulnerable while
    // airborne.
    hopping: bool;
    hop_dx, hop_dy: int;
    hop_from_x, hop_from_y: float;
    hop_target_x, hop_target_y: float;
    hop_t: float;

    // Generic "a mechanic owns me right now" flag. Any level mechanic that
    // takes over the player (cart ride, fish swallow, etc) sets this and
    // clears it on release. move/bomb/punch short-circuit on it.
    locked_by_mechanic: bool;
}

Enemy :: struct {
    x, y: int;
    rx, ry: float;
    alive: bool;
    max_bombs: int;
    fire_range: int;
    move_timer: int;
    move_delay: int;
    skate_count: int;
    color: Vector4;
    glow: Vector4;
    id: int;
    dir: Dir;
    stun_timer: int;
    flee_x, flee_y: int;
    has_flee: bool;
    last_x, last_y: int;   // anti-backtrack memory; -1 = none
    idle_streak: int;      // ticks spent staying put; lets us nudge if stuck too long

    // Arc-hop state — mirrors Player.hopping. Active when an enemy is ejected
    // from the mine cart. AI/movement is paused while airborne; explosions and
    // the cart pass through them.
    hopping: bool;
    hop_dx, hop_dy: int;
    hop_from_x, hop_from_y: float;
    hop_target_x, hop_target_y: float;
    hop_t: float;
}

Bomb :: struct {
    x, y: int;
    timer: int;
    range: int;
    owner: int; // 0=player, 1-3=enemy id
    slide_dx, slide_dy: int;
    slide_timer: int;
    chain: bool;
    // Punch flight
    punching: bool;
    punch_dx, punch_dy: int;
    punch_from_x, punch_from_y: float;     // unwrapped continuous (interp source)
    punch_target_x, punch_target_y: float; // unwrapped continuous (interp dest; may go out of bounds)
    punch_t: float;                        // 0..1 progress in current hop
}

Explosion :: struct {
    x, y: int;
    timer: int;
    duration: int;
    origin: bool;
}

MeltingBrick :: struct {
    x, y: int;
    timer: int;
}

MeltingPowerup :: struct {
    x, y: int;
    type: PType;
    timer: int;
}

Powerup :: struct {
    x, y: int;
    type: PType;
    delay: int;
}

FxKind :: enum u8 {
    SMALL;      // powerup destroy, brick destroy, bomb place, powerup pickup
    BIG;        // player/enemy death
    BOING;      // bomb landing/bouncing during a punch
    DUST;       // footstep or slide trail — quiet ground puff
}

DeathFx :: struct {
    x, y: float;        // world grid coordinates (matches rx/ry for moving entities)
    color: Vector4;
    timer: int;
    duration: int;
    kind: FxKind;
}

BFSNode :: struct {
    x, y: int;
}

// ─── Level 2 (VOLCANIC) — mine cart ─────────────────────────────────────────
// The cart sits on a fixed track. The player walking onto its tile mounts the
// cart, which then animates tile-by-tile through a pre-baked route. Tiles the
// cart enters destroy any brick or kill any enemy standing on them; powerups
// are left untouched (player can't grab from the cart either). At the end of
// the route the player is ejected onto the closest free tile beyond the cart.

CART_MOVE_DELAY        :: 8;     // ticks between cart tile-steps
PLAYER_HOP_FRAMES      :: 14;    // ticks per single tile of the dismount arc
PLAYER_HOP_HEIGHT      :: 42.0;  // peak height (pixels) of a player hop arc

// ── EDIT THIS to change the rails ───────────────────────────────────────────
// MINE_CART_WAYPOINTS is the single source of truth for both the rail visuals
// and the cart's mechanical path. Each entry is a grid (col, row). Adjacent
// waypoints are connected as axis-aligned tile-by-tile segments (the cart
// destroys bricks / kills enemies on every tile it enters; powerups and
// indestructible walls are left alone).
//
// DESIGN RULE: keep the route off the wall lattice. Walls sit at every (even
// col, even row) tile, so:
//   - horizontal segments → use an ODD row,
//   - vertical segments   → use an ODD col,
//   - waypoints themselves → never use (even, even).
// Otherwise the cart will collide with an indestructible wall on the rails.
MINE_CART_WAYPOINTS :: BFSNode.[
    .{3,  3},   // start
    .{11, 3},   // run right along row 3 (odd, no walls)
    .{11, 9},   // drop down col 11 (odd, no walls)
    .{5,  9},   // run back left along row 9 (odd, no walls)
    .{3,  7},   // exit-ramp: x-first then y → cart dismounts heading UP
];

MineCartState :: enum u8 {
    IDLE;     // sitting at start, waiting for someone to step on
    RIDING;   // rider mounted, advancing along route
}

MineCartRider :: enum u8 {
    NONE;
    PLAYER;
    ENEMY;
}

MineCart :: struct {
    // `state == RIDING && rider == PLAYER` (or `.ENEMY`) is the canonical
    // "cart is doing something" signal. load_level zeroes the whole struct
    // when switching levels, so on non-volcanic levels every field stays in
    // its default state and read-sites short-circuit naturally.
    state:  MineCartState;
    x, y:   int;             // current grid tile
    rx, ry: float;           // interpolated render position (tile space)
    route_index: int;        // index into mine_cart_path
    move_timer: int;
    dx, dy: int;             // last direction of travel (faces the cart + sets dismount direction)

    // Direction to advance route_index each tick. +1 forward (toward path end),
    // -1 backward (toward path start). Set when a new rider mounts: the cart
    // heads away from whichever endpoint it's currently parked at.
    dir_sign: int;

    // Who is currently aboard. The cart parks where the ride ends; the next
    // rider sends it back the OPPOSITE direction. Unlimited rides.
    rider:           MineCartRider;
    rider_enemy_id:  int;    // valid when rider == ENEMY (index into enemies[])
}

mine_cart: MineCart;
mine_cart_path: [..] BFSNode;    // expanded tile-by-tile path (for collisions/ticks)

// ─── Level 3 (SNOW) — snowballs ─────────────────────────────────────────────
SNOWBALL_FORM_TICKS  :: 240;    // 4 s to finish forming
SNOWBALL_ROLL_DELAY  :: 5;
SNOWBALL_MAX         :: 3;
SNOWBALL_SPAWN_MIN   :: 720;    // 12 s between spawn attempts
SNOWBALL_SPAWN_MAX   :: 1320;   // 22 s

Snowball :: struct {
    x, y: int;
    rx, ry: float;
    forming: bool;
    form_timer: int;
    rolling: bool;
    roll_dx, roll_dy: int;
    roll_timer: int;
}
snowballs: [..] Snowball;
snowball_spawn_cooldown: int;

SNOWFLAKE_COUNT :: 160;
Snowflake :: struct {
    sx, sy: float;
    vy: float;
    size: float;
    sway: float;
}
snowflakes: [SNOWFLAKE_COUNT] Snowflake;
snowflakes_initialized: bool;

// ─── Level 4 (PIRATE) — cannons ─────────────────────────────────────────────
// 4 fixed-position cannons: 2 on the left (face RIGHT), 2 on the right (face
// LEFT). CANNON_EDGE_OFFSET is the *single* parameter that controls how far
// from the side wall they sit. 1 = flush against the wall (back tile is the
// border wall, unreachable); 2 = one tile in (back tile is interior, the
// player can drop a bomb there). 2 is the recommended sweet spot.
CANNON_FUSE_TICKS  :: 90;
CANNON_RANGE       :: 5;
CANNON_EDGE_OFFSET :: 2;     // columns from the side wall — 2 keeps back-tile reachable

Cannon :: struct {
    x, y: int;
    dir: Dir;
    fuse_timer: int;   // 0 = not lit; counts down once lit
    fired: bool;
}
cannons: [..] Cannon;

// ─── Level 5 (BEACH) — fish teleport ────────────────────────────────────────
BEACH_WATER_DENSITY :: 0.08;
BEACH_WATER_MAX     :: 12;
BEACH_FISH_COUNT    :: 3;
FISH_SWALLOW_TICKS  :: 18;
FISH_TRAVEL_TICKS   :: 8;
FISH_EJECT_TICKS    :: 18;
FISH_TOTAL_TICKS    :: FISH_SWALLOW_TICKS + FISH_TRAVEL_TICKS + FISH_EJECT_TICKS;

Fish :: struct {
    x, y: int;
    bob_phase: float;
}
fishes: [..] Fish;

FishTeleport :: struct {
    active: bool;
    phase: int;
    src_x, src_y: int;
    dst_x, dst_y: int;
}
fish_teleport: FishTeleport;

DIRS :: int.[0, -1, 0, 1, -1, 0, 1, 0]; // pairs (dx, dy) flattened

grid: [ROWS][COLS] Tile;
player: Player;
enemies: [3] Enemy;
powerups: [..] Powerup;
bombs: [..] Bomb;
explosions_list: [..] Explosion;
melting_bricks: [..] MeltingBrick;
melting_powerups: [..] MeltingPowerup;
death_fx_list: [..] DeathFx;
kick_spawned: int;
punch_spawned: int;
skate_spawned: int;
game_over_delay: int;       // counts down after a fatal hit so the death FX plays before the screen flips
hit_flash_timer: int;       // brief red overlay when player gets hit
victory_flash_timer: int;   // gold overlay when last enemy dies

key_up: bool;
key_down: bool;
key_left: bool;
key_right: bool;
game_over: bool;
player_won: bool;
frame_count: int;
move_timer: int;

window: Window_Type;
my_font: *Simp.Dynamic_Font;
should_quit: bool;
window_w_actual: s32 = WINDOW_W;
window_h_actual: s32 = WINDOW_H;
is_fullscreen: bool;
saved_window_info: Saved_Window_Info;
cam_mvp: Matrix4;

// Sound effects. Loaded once in main(); fired through play_sfx() at the
// trigger sites (explosion, entity death, powerup pickup).
sound_explosion: Sound_Data;
sound_hit:       Sound_Data;
sound_powerup:   Sound_Data;
audio_ready:     bool;

play_sfx :: (data: *Sound_Data, volume: float = 0.7) {
    if !audio_ready return;
    if !data.loaded return;
    stream := Sound.make_stream(data, .GENERAL_SFX);
    if !stream return;
    stream.user_volume_scale = volume;
    Sound.start_playing(stream);
}

// ─── Atmosphere & juice state ────────────────────────────────────────────────
// SHAKE_INTENSITY: master shake knob.
//   0   → disables shake completely
//   0.5 → current default (very subtle)
//   1   → previous dialled-down baseline
//   2   → punchy / arcade-feel
SHAKE_INTENSITY    :: 0.5;
SHAKE_DECAY        :: 0.78;   // per-tick decay multiplier (lower → settles faster)
SHAKE_MAX          :: 2.2;    // cap on accumulated shake_amount so chains can't over-shake
SHAKE_PER_BOOM     :: 0.55;   // shake added per non-chain explosion
SHAKE_PER_CHAIN    :: 0.95;   // shake added per chained explosion (more impactful)
RECENT_BOOM_DECAY  :: 0.025;  // per-tick decay of `recent_boom` (drives warm-tint overlay)
shake_amount: float;          // current shake intensity (decays each frame)
recent_boom:  float;          // 0..1, brief surge that tints atmosphere

AMBIENT_MOTE_COUNT :: 90;
AmbientMote :: struct {
    x, z:   float;   // world XZ (grid space, in pixels)
    height: float;   // world Y above floor
    vy:     float;
    phase:  float;
    size:   float;
    color:  Vector4;
}
ambient_motes: [AMBIENT_MOTE_COUNT] AmbientMote;

STAR_COUNT :: 200;
Star :: struct {
    sx, sy:  float;   // screen-space position (seeded once)
    size:    float;
    base:    float;
    twinkle: float;
    color:   Vector4;
}
stars: [STAR_COUNT] Star;

atmosphere_initialized: bool;

col :: (r: float, g: float, b: float, a: float) -> Vector4 {
    return .{r, g, b, a};
}

powerup_color :: (t: PType) -> Vector4 {
    if t == {
        case .BOMB;  return col(0.702, 0.533, 1.0, 1);
        case .FIRE;  return col(1.0, 0.671, 0.251, 1);
        case .KICK;  return col(0, 0.737, 0.827, 1);
        case .PUNCH; return col(1.0, 0.757, 0.027, 1);
        case .SKATE; return col(0.420, 0.812, 1.0, 1);
    }
    return col(1, 1, 1, 1);
}

spawn_fx :: (x: float, y: float, color: Vector4, kind: FxKind) {
    fx: DeathFx;
    fx.x = x;
    fx.y = y;
    fx.color = color;
    if kind == {
        case .BIG;      fx.duration = 36;
        case .SMALL;    fx.duration = 22;
        case .BOING;    fx.duration = 18;
        case .DUST;     fx.duration = 12;
    }
    fx.timer = fx.duration;
    fx.kind = kind;
    array_add(*death_fx_list, fx);
}

spawn_death_fx :: (x: float, y: float, color: Vector4, big: bool) {
    spawn_fx(x, y, color, ifx big then FxKind.BIG else FxKind.SMALL);
}

add_shake :: (amount: float) {
    shake_amount += amount;
    if shake_amount > SHAKE_MAX shake_amount = SHAKE_MAX;
}

init_atmosphere :: () {
    for i: 0..AMBIENT_MOTE_COUNT-1 {
        m := *ambient_motes[i];
        m.x      = random_get_zero_to_one() * cast(float)(COLS * TILE);
        m.z      = random_get_zero_to_one() * cast(float)(ROWS * TILE);
        m.height = random_get_zero_to_one() * cast(float)TILE * 3.0;
        m.vy     = 0.15 + random_get_zero_to_one() * 0.45;
        m.phase  = random_get_zero_to_one() * TAU;
        m.size   = 1.0 + random_get_zero_to_one() * 1.8;
        roll := random_get_zero_to_one();
        jitter := random_get_zero_to_one() * 0.18;
        // Pick one of three theme palette hints; small jitter keeps the cloud lively.
        if roll < 0.55 {
            base := current_theme.mote_a;
            m.color = col(min(1.0, base.x + jitter), min(1.0, base.y + jitter * 0.6), min(1.0, base.z), 1);
        } else if roll < 0.82 {
            base := current_theme.mote_b;
            m.color = col(min(1.0, base.x + jitter * 0.6), min(1.0, base.y), min(1.0, base.z), 1);
        } else {
            base := current_theme.mote_c;
            m.color = col(min(1.0, base.x), min(1.0, base.y + jitter * 0.3), min(1.0, base.z + jitter * 0.4), 1);
        }
    }

    for i: 0..STAR_COUNT-1 {
        s := *stars[i];
        s.sx = random_get_zero_to_one() * cast(float)WINDOW_W;
        ny := random_get_zero_to_one();
        s.sy = ny * ny * cast(float)WINDOW_H * 0.62;
        s.size = 0.5 + random_get_zero_to_one() * 1.6;
        s.base = 0.35 + random_get_zero_to_one() * 0.55;
        s.twinkle = random_get_zero_to_one() * TAU;
        roll := random_get_zero_to_one();
        if roll < 0.7 {
            s.color = col(1.0, 1.0, 1.0, 1);
        } else if roll < 0.85 {
            s.color = col(0.70, 0.85, 1.0, 1);
        } else if roll < 0.95 {
            s.color = col(1.0, 0.83, 0.70, 1);
        } else {
            s.color = col(0.95, 0.62, 1.0, 1);
        }
    }

    atmosphere_initialized = true;
}

update_atmosphere :: () {
    if !atmosphere_initialized init_atmosphere();

    for * ambient_motes {
        it.height += it.vy;
        it.phase  += 0.05;
        // Gentle sway, breath of air pushing motes sideways
        it.x += sin(it.phase * 0.6) * 0.18;
        if it.height > cast(float)TILE * 4.0 {
            it.height = 0;
            it.x = random_get_zero_to_one() * cast(float)(COLS * TILE);
            it.z = random_get_zero_to_one() * cast(float)(ROWS * TILE);
            it.phase = random_get_zero_to_one() * TAU;
        }
    }

    if recent_boom > 0 {
        recent_boom -= RECENT_BOOM_DECAY;
        if recent_boom < 0 recent_boom = 0;
    }
}

mix4 :: (a: Vector4, b: Vector4, t: float) -> Vector4 {
    return .{a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t, a.w + (b.w - a.w) * t};
}

draw_vgradient :: (x: float, y: float, w: float, h: float, top: Vector4, bot: Vector4) {
    Simp.immediate_quad(
        Vector2.{x,     y    },
        Vector2.{x + w, y    },
        Vector2.{x + w, y + h},
        Vector2.{x,     y + h},
        top, top, bot, bot
    );
}

// Edge fade: solid `color` on one edge, fully transparent on the opposite.
// `edge` picks which side is solid: 0=top, 1=bottom, 2=left, 3=right.
draw_edge_fade :: (x: float, y: float, w: float, h: float, edge: int, color: Vector4) {
    clear := Vector4.{color.x, color.y, color.z, 0};
    if edge == {
        case 0; // top solid
            Simp.immediate_quad(
                Vector2.{x,     y    }, Vector2.{x + w, y    },
                Vector2.{x + w, y + h}, Vector2.{x,     y + h},
                color, color, clear, clear
            );
        case 1; // bottom solid
            Simp.immediate_quad(
                Vector2.{x,     y    }, Vector2.{x + w, y    },
                Vector2.{x + w, y + h}, Vector2.{x,     y + h},
                clear, clear, color, color
            );
        case 2; // left solid
            Simp.immediate_quad(
                Vector2.{x,     y    }, Vector2.{x + w, y    },
                Vector2.{x + w, y + h}, Vector2.{x,     y + h},
                color, clear, clear, color
            );
        case 3; // right solid
            Simp.immediate_quad(
                Vector2.{x,     y    }, Vector2.{x + w, y    },
                Vector2.{x + w, y + h}, Vector2.{x,     y + h},
                clear, color, color, clear
            );
    }
}

init_grid :: () {
    for r: 0..ROWS-1 {
        for c: 0..COLS-1 {
            if r == 0 || r == ROWS-1 || c == 0 || c == COLS-1 {
                grid[r][c] = .WALL;
            } else if r % 2 == 0 && c % 2 == 0 {
                grid[r][c] = .WALL;
            } else if (r == 1 && c <= 2) || (c == 1 && r <= 2) {
                grid[r][c] = .EMPTY;
            } else if (r == ROWS-2 && c >= COLS-3) || (c == COLS-2 && r >= ROWS-3) {
                grid[r][c] = .EMPTY;
            } else if (r == 1 && c >= COLS-3) || (c == COLS-2 && r <= 2) {
                grid[r][c] = .EMPTY;
            } else if (r == ROWS-2 && c <= 2) || (c == 1 && r >= ROWS-3) {
                grid[r][c] = .EMPTY;
            } else {
                if random_get_zero_to_one() < BRICK_DENSITY {
                    grid[r][c] = .BRICK;
                } else {
                    grid[r][c] = .EMPTY;
                }
            }
        }
    }
}

draw_filled_rect :: (x: float, y: float, w: float, h: float, color: Vector4) {
    Simp.immediate_quad(x, y, x + w, y + h, color);
}

draw_filled_circle :: (cx: float, cy: float, radius: float, color: Vector4, segments: int = 16) {
    if radius <= 0 return;
    for i: 0..segments-1 {
        a1 := (cast(float) i / cast(float) segments) * TAU;
        a2 := (cast(float) (i + 1) / cast(float) segments) * TAU;
        p1 := Vector3.{cx + cos(a1) * radius, cy + sin(a1) * radius, 0};
        p2 := Vector3.{cx + cos(a2) * radius, cy + sin(a2) * radius, 0};
        center := Vector3.{cx, cy, 0};
        Simp.immediate_triangle(center, p1, p2, color, color, color);
    }
}

draw_filled_ellipse :: (cx: float, cy: float, rx: float, ry: float, color: Vector4, segments: int = 16) {
    if rx <= 0 || ry <= 0 return;
    for i: 0..segments-1 {
        a1 := (cast(float) i / cast(float) segments) * TAU;
        a2 := (cast(float) (i + 1) / cast(float) segments) * TAU;
        p1 := Vector3.{cx + cos(a1) * rx, cy + sin(a1) * ry, 0};
        p2 := Vector3.{cx + cos(a2) * rx, cy + sin(a2) * ry, 0};
        center := Vector3.{cx, cy, 0};
        Simp.immediate_triangle(center, p1, p2, color, color, color);
    }
}

draw_triangle :: (x1: float, y1: float, x2: float, y2: float, x3: float, y3: float, color: Vector4) {
    Simp.immediate_triangle(Vector3.{x1, y1, 0}, Vector3.{x2, y2, 0}, Vector3.{x3, y3, 0}, color, color, color);
}

draw_rounded_rect :: (x: float, y: float, w: float, h: float, r: float, color: Vector4) {
    rr := r;
    if rr > w * 0.5 rr = w * 0.5;
    if rr > h * 0.5 rr = h * 0.5;
    draw_filled_rect(x + rr, y, w - 2 * rr, h, color);
    draw_filled_rect(x, y + rr, w, h - 2 * rr, color);
    draw_filled_circle(x + rr, y + rr, rr, color, 8);
    draw_filled_circle(x + w - rr, y + rr, rr, color, 8);
    draw_filled_circle(x + rr, y + h - rr, rr, color, 8);
    draw_filled_circle(x + w - rr, y + h - rr, rr, color, 8);
}

draw_stroke_rect :: (x: float, y: float, w: float, h: float, color: Vector4, thickness: float = 1.0) {
    draw_filled_rect(x, y, w, thickness, color);
    draw_filled_rect(x, y + h - thickness, w, thickness, color);
    draw_filled_rect(x, y, thickness, h, color);
    draw_filled_rect(x + w - thickness, y, thickness, h, color);
}

draw_line :: (x1: float, y1: float, x2: float, y2: float, color: Vector4, thickness: float = 1.0) {
    dx := x2 - x1;
    dy := y2 - y1;
    len := sqrt(dx * dx + dy * dy);
    if len == 0 return;
    nx := -dy / len * thickness * 0.5;
    ny := dx / len * thickness * 0.5;
    Simp.immediate_quad(
        Vector2.{x1 + nx, y1 + ny},
        Vector2.{x1 - nx, y1 - ny},
        Vector2.{x2 - nx, y2 - ny},
        Vector2.{x2 + nx, y2 + ny},
        color
    );
}

make_view :: (eye: Vector3, target: Vector3, up: Vector3) -> Matrix4 {
    f := target - eye;  normalize(*f, fallback=.{0,0,-1});
    s := cross_product(f, up); normalize(*s, fallback=.{1,0,0});
    u := cross_product(s, f);

    m: Matrix4;
    m._11 = s.x; m._12 = s.y; m._13 = s.z; m._14 = -dot_product(s, eye);
    m._21 = u.x; m._22 = u.y; m._23 = u.z; m._24 = -dot_product(u, eye);
    m._31 = -f.x; m._32 = -f.y; m._33 = -f.z; m._34 = dot_product(f, eye);
    m._44 = 1;
    return m;
}

make_perspective :: (fov_y_rad: float, aspect: float, znear: float, zfar: float) -> Matrix4 {
    f := 1.0 / tan(fov_y_rad * 0.5);
    m: Matrix4;
    m._11 = f / aspect;
    m._22 = f;
    m._33 = (zfar + znear) / (znear - zfar);
    m._34 = (2.0 * zfar * znear) / (znear - zfar);
    m._43 = -1;
    return m;
}

build_camera :: () {
    board_cx := cast(float) (COLS * TILE) * 0.5;
    board_cz := cast(float) (ROWS * TILE) * 0.5;

    t := cast(float)frame_count;
    sx := sin(t * 1.31 + 0.7) * shake_amount * 4.0 * SHAKE_INTENSITY;
    sy := cos(t * 1.77 + 1.3) * shake_amount * 3.0 * SHAKE_INTENSITY;
    sz := sin(t * 2.13 + 2.4) * shake_amount * 4.0 * SHAKE_INTENSITY;

    eye    := Vector3.{ board_cx + sx, 1700 + sy, board_cz + 260 + sz };
    target := Vector3.{ board_cx + sx * 0.4, 0, board_cz + sz * 0.4 };
    up     := Vector3.{ 0, 1, 0 };

    aspect := cast(float) WINDOW_W / cast(float) WINDOW_H;
    proj := make_perspective(0.52, aspect, 50, 5000);
    view := make_view(eye, target, up);
    cam_mvp = proj * view;
}

project :: (p: Vector3) -> Vector2, bool {
    v := cam_mvp * Vector4.{p.x, p.y, p.z, 1};
    if v.w <= 0.0001 return .{0, 0}, false;
    inv_w := 1.0 / v.w;
    sx := (v.x * inv_w + 1.0) * 0.5 * cast(float) WINDOW_W;
    sy := (1.0 - v.y * inv_w) * 0.5 * cast(float) WINDOW_H;
    return .{sx, sy}, true;
}

draw_tri_3d :: (a: Vector3, b: Vector3, c: Vector3, color: Vector4) {
    pa, oa := project(a);
    pb, ob := project(b);
    pc, oc := project(c);
    if !oa || !ob || !oc return;
    Simp.immediate_triangle(Vector3.{pa.x, pa.y, 0}, Vector3.{pb.x, pb.y, 0}, Vector3.{pc.x, pc.y, 0}, color, color, color);
}

draw_quad_3d :: (a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Vector4) {
    pa, oa := project(a);
    pb, ob := project(b);
    pc, oc := project(c);
    pd, od := project(d);
    if !oa || !ob || !oc || !od return;
    Simp.immediate_quad(pa, pb, pc, pd, color);
}

shade :: (c: Vector4, mul: float) -> Vector4 {
    return .{c.x * mul, c.y * mul, c.z * mul, c.w};
}

draw_cube_3d :: (cx: float, cz: float, half_w: float, height: float, top_c: Vector4, side_c: Vector4) {
    x0 := cx - half_w; x1 := cx + half_w;
    z0 := cz - half_w; z1 := cz + half_w;
    y0 := 0.0;         y1 := height;

    top_color   := shade(top_c, 1.0);
    front_color := shade(side_c, 0.72);
    left_color  := shade(side_c, 0.92);
    right_color := shade(side_c, 0.48);

    draw_quad_3d(.{x0, y1, z1}, .{x1, y1, z1}, .{x1, y1, z0}, .{x0, y1, z0}, top_color);
    draw_quad_3d(.{x0, y0, z1}, .{x1, y0, z1}, .{x1, y1, z1}, .{x0, y1, z1}, front_color);
    draw_quad_3d(.{x0, y0, z0}, .{x0, y0, z1}, .{x0, y1, z1}, .{x0, y1, z0}, left_color);
    draw_quad_3d(.{x1, y0, z1}, .{x1, y0, z0}, .{x1, y1, z0}, .{x1, y1, z1}, right_color);
}

screen_scale_at :: (world: Vector3) -> float {
    a, _ := project(world);
    b, _ := project(.{world.x, world.y + cast(float)TILE, world.z});
    return abs(a.y - b.y) / cast(float) TILE;
}

tile_is_solid :: (c: int, r: int) -> bool {
    if c < 0 || c >= COLS || r < 0 || r >= ROWS return false;
    return grid[r][c] == .WALL || grid[r][c] == .BRICK;
}

draw_floor_3d :: (c: int, r: int) {
    x0 := cast(float)(c * TILE);
    x1 := x0 + cast(float)TILE;
    z0 := cast(float)(r * TILE);
    z1 := z0 + cast(float)TILE;

    base: Vector4;
    accent: Vector4;
    if (r + c) % 2 == 0 {
        base   = current_theme.floor_a_base;
        accent = current_theme.floor_a_accent;
    } else {
        base   = current_theme.floor_b_base;
        accent = current_theme.floor_b_accent;
    }
    draw_quad_3d(.{x0, 0, z0}, .{x1, 0, z0}, .{x1, 0, z1}, .{x0, 0, z1}, base);
    inset := 2.0;
    draw_quad_3d(.{x0 + inset, 0.1, z0 + inset}, .{x1 - inset, 0.1, z0 + inset}, .{x1 - inset, 0.1, z1 - inset}, .{x0 + inset, 0.1, z1 - inset}, accent);

    ao_w :: 12.0;
    ao_c := current_theme.floor_ao;
    if tile_is_solid(c, r - 1) {
        draw_quad_3d(.{x0, 0.2, z0}, .{x1, 0.2, z0}, .{x1, 0.2, z0 + ao_w}, .{x0, 0.2, z0 + ao_w}, ao_c);
    }
    if tile_is_solid(c, r + 1) {
        draw_quad_3d(.{x0, 0.2, z1 - ao_w}, .{x1, 0.2, z1 - ao_w}, .{x1, 0.2, z1}, .{x0, 0.2, z1}, ao_c);
    }
    if tile_is_solid(c - 1, r) {
        draw_quad_3d(.{x0, 0.2, z0}, .{x0 + ao_w, 0.2, z0}, .{x0 + ao_w, 0.2, z1}, .{x0, 0.2, z1}, ao_c);
    }
    if tile_is_solid(c + 1, r) {
        draw_quad_3d(.{x1 - ao_w, 0.2, z0}, .{x1, 0.2, z0}, .{x1, 0.2, z1}, .{x1 - ao_w, 0.2, z1}, ao_c);
    }

    seed := c * 131 + r * 977;
    if (seed % 4) == 0 {
        twinkle := 0.45 + (sin(cast(float)frame_count / 30.0 + cast(float)seed) + 1) * 0.30;
        offset_x := cast(float)(seed % 30) - 15;
        offset_z := cast(float)((seed / 7) % 30) - 15;
        cx_w := x0 + cast(float)TILE * 0.5 + offset_x;
        cz_w := z0 + cast(float)TILE * 0.5 + offset_z;
        sc, _ := project(.{cx_w, 0.3, cz_w});
        sp := current_theme.floor_speck;
        draw_filled_circle(sc.x, sc.y, 1.5, col(sp.x, sp.y, sp.z, twinkle), 6);
    }
}

draw_wall_3d :: (c: int, r: int) {
    if current_theme.wall_renderer { current_theme.wall_renderer(c, r); return; }
    cx_w := cast(float)(c * TILE) + cast(float)TILE * 0.5;
    cz_w := cast(float)(r * TILE) + cast(float)TILE * 0.5;
    base := current_theme.wall_base;
    top  := current_theme.wall_top;
    draw_cube_3d(cx_w, cz_w, cast(float)TILE * 0.5, cast(float)TILE, top, base);

    edge_dark := current_theme.wall_edge;
    x0 := cx_w - cast(float)TILE * 0.5;
    x1 := cx_w + cast(float)TILE * 0.5;
    z0 := cz_w - cast(float)TILE * 0.5;
    z1 := cz_w + cast(float)TILE * 0.5;
    h  := cast(float)TILE;
    tr := 1.5;
    draw_quad_3d(.{x0, h, z1}, .{x1, h, z1}, .{x1, h - tr, z1}, .{x0, h - tr, z1}, shade(edge_dark, 1));
    draw_quad_3d(.{x0, h, z0}, .{x0, h, z1}, .{x0, h - tr, z1}, .{x0, h - tr, z0}, shade(edge_dark, 1));

    mortar    := current_theme.wall_mortar;
    mid_x := (x0 + x1) * 0.5;
    mid_z := (z0 + z1) * 0.5;
    mort_w :: 2.0;
    draw_quad_3d(.{x0 + 6, h + 0.1, mid_z - mort_w}, .{x1 - 6, h + 0.1, mid_z - mort_w}, .{x1 - 6, h + 0.1, mid_z + mort_w}, .{x0 + 6, h + 0.1, mid_z + mort_w}, mortar);
    draw_quad_3d(.{mid_x - mort_w, h + 0.1, z0 + 6}, .{mid_x + mort_w, h + 0.1, z0 + 6}, .{mid_x + mort_w, h + 0.1, z1 - 6}, .{mid_x - mort_w, h + 0.1, z1 - 6}, mortar);
    seed := c * 53 + r * 211;
    rune_phase := cast(float)frame_count / 22.0 + cast(float)seed * 0.013;
    rune_pulse := 0.55 + 0.45 * sin(rune_phase);
    rb := current_theme.wall_rune;
    // Pulse mixes a brighter version of the rune base color toward white.
    rune_c := col(rb.x * (0.7 + 0.3 * rune_pulse) + 0.3 * rune_pulse,
                  rb.y * (0.7 + 0.3 * rune_pulse) + 0.2 * rune_pulse,
                  rb.z * (0.7 + 0.3 * rune_pulse) + 0.1 * rune_pulse, 1);
    dot_x := x0 + cast(float)(seed % 18) + 8;
    dot_z := z0 + cast(float)((seed / 5) % 18) + 8;
    draw_quad_3d(.{dot_x - 0.6, h + 0.18, dot_z - 0.6}, .{dot_x + 3.6, h + 0.18, dot_z - 0.6}, .{dot_x + 3.6, h + 0.18, dot_z + 3.6}, .{dot_x - 0.6, h + 0.18, dot_z + 3.6}, col(rune_c.x, rune_c.y, rune_c.z, 0.30 * rune_pulse));
    draw_quad_3d(.{dot_x, h + 0.22, dot_z}, .{dot_x + 3, h + 0.22, dot_z}, .{dot_x + 3, h + 0.22, dot_z + 3}, .{dot_x, h + 0.22, dot_z + 3}, rune_c);
}

draw_brick_3d :: (c: int, r: int) {
    if current_theme.brick_renderer { current_theme.brick_renderer(c, r); return; }
    cx_w := cast(float)(c * TILE) + cast(float)TILE * 0.5;
    cz_w := cast(float)(r * TILE) + cast(float)TILE * 0.5;
    h := cast(float)TILE * 0.72;
    base := current_theme.brick_base;
    top  := current_theme.brick_top;
    draw_cube_3d(cx_w, cz_w, cast(float)TILE * 0.45, h, top, base);

    half := cast(float)TILE * 0.45;
    x0 := cx_w - half;
    x1 := cx_w + half;
    z0 := cz_w - half;
    z1 := cz_w + half;

    rim_dark := current_theme.brick_rim;
    inner    := current_theme.brick_inner;
    grain    := current_theme.brick_grain;
    rim_w :: 2.5;
    draw_quad_3d(.{x0, h + 0.1, z0}, .{x1, h + 0.1, z0}, .{x1, h + 0.1, z0 + rim_w}, .{x0, h + 0.1, z0 + rim_w}, rim_dark);
    draw_quad_3d(.{x0, h + 0.1, z1 - rim_w}, .{x1, h + 0.1, z1 - rim_w}, .{x1, h + 0.1, z1}, .{x0, h + 0.1, z1}, rim_dark);
    draw_quad_3d(.{x0, h + 0.1, z0}, .{x0 + rim_w, h + 0.1, z0}, .{x0 + rim_w, h + 0.1, z1}, .{x0, h + 0.1, z1}, rim_dark);
    draw_quad_3d(.{x1 - rim_w, h + 0.1, z0}, .{x1, h + 0.1, z0}, .{x1, h + 0.1, z1}, .{x1 - rim_w, h + 0.1, z1}, rim_dark);

    draw_quad_3d(.{x0 + 8, h + 0.15, z0 + 8}, .{x1 - 8, h + 0.15, z0 + 8}, .{x1 - 8, h + 0.15, z1 - 8}, .{x0 + 8, h + 0.15, z1 - 8}, inner);

    seed := c * 7 + r * 13;
    for i: 0..2 {
        gx0 := x0 + cast(float)((seed * (i + 1)) % 24) + 6;
        gz  := z0 + cast(float)(((seed * 3) + i * 11) % 20) + 10;
        draw_quad_3d(.{gx0, h + 0.2, gz}, .{gx0 + 8, h + 0.2, gz}, .{gx0 + 8, h + 0.2, gz + 1.2}, .{gx0, h + 0.2, gz + 1.2}, grain);
    }

    offset := cast(float)((seed % 18) - 8);
    bx := cx_w - 14 + offset;
    z_face := cz_w + half + 0.5;
    draw_quad_3d(.{bx, h * 0.4, z_face}, .{bx + 10, h * 0.4, z_face}, .{bx + 10, h * 0.4 + 4, z_face}, .{bx, h * 0.4 + 4, z_face}, current_theme.brick_face);
}

// ── Custom per-theme wall/brick renderers ───────────────────────────────────
// Each level installs its own block silhouette so the playfield feels distinct
// instead of "same shape, different paint". Wired into Theme.wall_renderer /
// Theme.brick_renderer; draw_wall_3d / draw_brick_3d delegate to them.
//
// LEVEL 1 (VANILLA) intentionally has NO custom renderer — it stays the boring
// stone cube. Every other level pins a recognisable decoration on top.

// Helper — project the world-space center of a wall's top face to 2D so we
// can scatter top-of-wall ornaments (snowman heads, rope coils, etc).
wall_top_screen :: (c: int, r: int, height_frac: float = 1.0) -> sx: float, sy: float, scale: float {
    cx_w := cast(float)(c * TILE) + cast(float)TILE * 0.5;
    cz_w := cast(float)(r * TILE) + cast(float)TILE * 0.5;
    y := cast(float)TILE * height_frac;
    sc, _ := project(.{cx_w, y, cz_w});
    s := screen_scale_at(.{cx_w, y, cz_w});
    return sc.x, sc.y, s;
}

draw_wall_volcanic :: (c: int, r: int) {
    cx_w := cast(float)(c * TILE) + cast(float)TILE * 0.5;
    cz_w := cast(float)(r * TILE) + cast(float)TILE * 0.5;
    half := cast(float)TILE * 0.5;
    h    := cast(float)TILE;
    // Obsidian-like dark rock.
    base := col(0.18, 0.12, 0.10, 1);
    top  := col(0.36, 0.24, 0.20, 1);
    draw_cube_3d(cx_w, cz_w, half, h, top, base);

    x0 := cx_w - half;
    x1 := cx_w + half;
    z0 := cz_w - half;
    z1 := cz_w + half;

    // Glowing magma vein running across the top face.
    seed := c * 73 + r * 211;
    pulse := 0.65 + 0.35 * sin(cast(float)frame_count / 8.0 + cast(float)seed * 0.04);
    vein  := col(1.0, 0.45 * pulse + 0.30, 0.15 * pulse, 1);
    // Horizontal-ish vein with slight offset.
    voff := cast(float)((seed % 16) - 8);
    draw_quad_3d(.{x0 + 6, h + 0.08, cz_w - 1.5 + voff * 0.2},
                 .{x1 - 6, h + 0.08, cz_w - 1.5 + voff * 0.2},
                 .{x1 - 6, h + 0.08, cz_w + 1.5 + voff * 0.2},
                 .{x0 + 6, h + 0.08, cz_w + 1.5 + voff * 0.2}, vein);
    // Bright hot core line on top of the vein.
    core := col(1.0, 0.92, 0.70, pulse);
    draw_quad_3d(.{x0 + 8, h + 0.14, cz_w - 0.4 + voff * 0.2},
                 .{x1 - 8, h + 0.14, cz_w - 0.4 + voff * 0.2},
                 .{x1 - 8, h + 0.14, cz_w + 0.4 + voff * 0.2},
                 .{x0 + 8, h + 0.14, cz_w + 0.4 + voff * 0.2}, core);

    // Lava drip from top edge of the front face.
    drip_x := x0 + 10 + cast(float)((seed * 3) % 30);
    drip_top  := col(1.0, 0.55, 0.18, 1);
    drip_glow := col(1.0, 0.30, 0.10, 0.55);
    drip_h := cast(float)TILE * (0.18 + 0.08 * sin(cast(float)frame_count / 7.0 + cast(float)seed * 0.1));
    // Glow halo
    draw_quad_3d(.{drip_x - 3, h - drip_h, z1 + 0.1}, .{drip_x + 5, h - drip_h, z1 + 0.1}, .{drip_x + 5, h, z1 + 0.1}, .{drip_x - 3, h, z1 + 0.1}, drip_glow);
    // Drip body
    draw_quad_3d(.{drip_x, h - drip_h, z1 + 0.15}, .{drip_x + 2, h - drip_h, z1 + 0.15}, .{drip_x + 2.5, h, z1 + 0.15}, .{drip_x - 0.5, h, z1 + 0.15}, drip_top);

    // Floating ember above the wall (2D billboard).
    sx, sy, s := wall_top_screen(c, r, 1.0);
    ember_phase := cast(float)frame_count / 30.0 + cast(float)seed * 0.07;
    ey_off := sin(ember_phase) * 6.0;
    ex_off := cos(ember_phase * 0.7) * 5.0;
    a := 0.65 + 0.35 * sin(ember_phase * 2.0);
    draw_filled_circle(sx + ex_off, sy - 14 + ey_off, 4.0 * s, col(1.0, 0.45, 0.15, a * 0.55), 10);
    draw_filled_circle(sx + ex_off, sy - 14 + ey_off, 2.2 * s, col(1.0, 0.85, 0.45, a),         8);
}

draw_wall_snow :: (c: int, r: int) {
    cx_w := cast(float)(c * TILE) + cast(float)TILE * 0.5;
    cz_w := cast(float)(r * TILE) + cast(float)TILE * 0.5;
    half := cast(float)TILE * 0.5;
    h_body := cast(float)TILE * 0.78;
    base := col(0.42, 0.62, 0.86, 1);
    top  := col(0.78, 0.92, 1.00, 1);
    draw_cube_3d(cx_w, cz_w, half, h_body, top, base);

    // Wider snow cap.
    cap_h := h_body + cast(float)TILE * 0.10;
    draw_cube_3d(cx_w, cz_w, half - 1.5, cap_h, col(1, 1, 1, 1), col(0.88, 0.95, 1.00, 1));

    // Snowman head perched on top — a clear "cute thing".
    seed := c * 73 + r * 137;
    sx, sy, s := wall_top_screen(c, r, 1.0);
    bob := sin(cast(float)frame_count / 22.0 + cast(float)seed * 0.05) * 1.2;
    head_y := sy - 18 + bob;
    head_r := 11.0 * s;
    // Shadow under head
    draw_filled_ellipse(sx, sy - 4, head_r * 1.2, head_r * 0.45, col(0.20, 0.30, 0.45, 0.45));
    // Body
    draw_filled_circle(sx, head_y + 6, head_r * 0.95, col(0.92, 0.97, 1.00, 1), 18);
    // Head
    draw_filled_circle(sx, head_y, head_r * 0.78, col(1.00, 1.00, 1.00, 1), 18);
    // Coal eyes
    draw_filled_circle(sx - head_r * 0.28, head_y - head_r * 0.10, head_r * 0.13, col(0.10, 0.10, 0.18, 1), 8);
    draw_filled_circle(sx + head_r * 0.28, head_y - head_r * 0.10, head_r * 0.13, col(0.10, 0.10, 0.18, 1), 8);
    // Carrot nose
    nose_c := col(1.00, 0.55, 0.18, 1);
    draw_triangle(sx, head_y + 1, sx + head_r * 0.85, head_y - 1, sx + 1, head_y + 4, nose_c);
    // Tiny smile dots
    draw_filled_circle(sx - head_r * 0.30, head_y + head_r * 0.30, 1.4 * s, col(0.10, 0.10, 0.18, 1), 6);
    draw_filled_circle(sx,                  head_y + head_r * 0.38, 1.4 * s, col(0.10, 0.10, 0.18, 1), 6);
    draw_filled_circle(sx + head_r * 0.30, head_y + head_r * 0.30, 1.4 * s, col(0.10, 0.10, 0.18, 1), 6);

    // Twinkles next to the snowman.
    pulse := 0.4 + 0.6 * sin(cast(float)frame_count / 11.0 + cast(float)seed * 0.05);
    draw_filled_circle(sx - head_r * 1.6, head_y - 4, 1.6 * pulse * s, col(1, 1, 1, pulse), 6);
    draw_filled_circle(sx + head_r * 1.6, head_y + 2, 1.4 * pulse * s, col(1, 1, 1, pulse), 6);
}

draw_brick_snow :: (c: int, r: int) {
    cx_w := cast(float)(c * TILE) + cast(float)TILE * 0.5;
    cz_w := cast(float)(r * TILE) + cast(float)TILE * 0.5;
    h := cast(float)TILE * 0.50;
    half := cast(float)TILE * 0.40;
    base := col(0.85, 0.92, 1.00, 1);
    top  := col(1.00, 1.00, 1.00, 1);
    draw_cube_3d(cx_w, cz_w, half, h, top, base);

    x0 := cx_w - half;
    x1 := cx_w + half;
    z0 := cz_w - half;
    z1 := cz_w + half;

    // Pile a smaller rounded mound on top.
    pile_h := h + cast(float)TILE * 0.18;
    draw_cube_3d(cx_w, cz_w, half - 4.0, pile_h, col(1, 1, 1, 1), col(0.94, 0.97, 1.00, 1));

    // Sparkles
    seed := c * 41 + r * 19;
    pulse := 0.5 + 0.5 * sin(cast(float)frame_count / 9.0 + cast(float)seed * 0.03);
    for i: 0..2 {
        sx := x0 + 6 + cast(float)((seed * (i + 1)) % 18);
        sz := z0 + 6 + cast(float)((seed * 3 + i * 11) % 18);
        a := pulse * (0.5 + cast(float)i * 0.2);
        draw_quad_3d(.{sx, pile_h + 0.2, sz}, .{sx + 1.6, pile_h + 0.2, sz}, .{sx + 1.6, pile_h + 0.2, sz + 1.6}, .{sx, pile_h + 0.2, sz + 1.6}, col(1, 1, 1, a));
    }
}

draw_wall_pirate :: (c: int, r: int) {
    cx_w := cast(float)(c * TILE) + cast(float)TILE * 0.5;
    cz_w := cast(float)(r * TILE) + cast(float)TILE * 0.5;
    half := cast(float)TILE * 0.5;
    h := cast(float)TILE;
    base := col(0.24, 0.15, 0.09, 1);
    top  := col(0.48, 0.32, 0.18, 1);
    draw_cube_3d(cx_w, cz_w, half, h, top, base);

    x0 := cx_w - half;
    x1 := cx_w + half;
    z1 := cz_w + half;

    // Vertical plank seams on the front face — quick "wood" tell.
    seam := col(0.10, 0.05, 0.03, 1);
    for i: 1..2 {
        px := x0 + cast(float)TILE * cast(float) i / 3.0;
        draw_quad_3d(.{px - 0.8, 0.05, z1 + 0.1}, .{px + 0.8, 0.05, z1 + 0.1}, .{px + 0.8, h - 0.05, z1 + 0.1}, .{px - 0.8, h - 0.05, z1 + 0.1}, seam);
    }

    seed := c * 41 + r * 73;
    sx, sy, s := wall_top_screen(c, r, 1.0);

    // Rope coil sitting on top — a brown annulus.
    coil_outer := col(0.62, 0.40, 0.20, 1);
    coil_mid   := col(0.78, 0.52, 0.26, 1);
    coil_inner := col(0.32, 0.18, 0.08, 1);
    coil_r     := 12.0 * s;
    draw_filled_ellipse(sx, sy - 2, coil_r * 1.30, coil_r * 0.50, col(0, 0, 0, 0.35));
    draw_filled_circle(sx, sy - 4, coil_r,        coil_outer, 18);
    draw_filled_circle(sx, sy - 4, coil_r * 0.85, coil_mid,   18);
    draw_filled_circle(sx, sy - 4, coil_r * 0.40, coil_inner, 14);
    // Coil grain — couple of arcs.
    for i: 0..6 {
        ang := (cast(float)i / 7.0) * TAU + cast(float)frame_count * 0.005;
        px := sx + cos(ang) * coil_r * 0.72;
        py := sy - 4 + sin(ang) * coil_r * 0.72 * 0.55;
        draw_filled_circle(px, py, 1.2 * s, coil_inner, 6);
    }

    // Little flag on a pole — sticks up over the rope.
    flag_sway := sin(cast(float)frame_count / 18.0 + cast(float)seed * 0.07) * 1.5;
    pole_top_y := sy - 38;
    pole_bot_y := sy - 6;
    draw_line(sx + 6, pole_bot_y, sx + 6, pole_top_y, col(0.30, 0.20, 0.10, 1), 1.6);
    flag_c := ifx (seed % 2) == 0 then col(0.78, 0.10, 0.10, 1) else col(0.10, 0.10, 0.14, 1);
    draw_triangle(sx + 6, pole_top_y,
                  sx + 22 + flag_sway, pole_top_y + 4,
                  sx + 6, pole_top_y + 10, flag_c);
    // Skull dot on the flag for the dark version.
    if (seed % 2) != 0 {
        draw_filled_circle(sx + 13 + flag_sway * 0.5, pole_top_y + 5, 1.6 * s, col(0.95, 0.95, 0.90, 1), 6);
    }

    // Brass-glint accent
    pulse := 0.5 + 0.5 * sin(cast(float)frame_count / 4.0);
    draw_filled_circle(sx + 6, pole_top_y, 2.0 * pulse, col(1, 0.92, 0.65, pulse), 6);
}

draw_brick_pirate :: (c: int, r: int) {
    cx_w := cast(float)(c * TILE) + cast(float)TILE * 0.5;
    cz_w := cast(float)(r * TILE) + cast(float)TILE * 0.5;
    h := cast(float)TILE * 0.70;
    half := cast(float)TILE * 0.42;
    base := col(0.50, 0.34, 0.20, 1);
    top  := col(0.74, 0.54, 0.32, 1);
    draw_cube_3d(cx_w, cz_w, half, h, top, base);

    x0 := cx_w - half;
    x1 := cx_w + half;
    z0 := cz_w - half;
    z1 := cz_w + half;

    // Edge rim on the top face — picture-frame look.
    rim := col(0.28, 0.18, 0.10, 1);
    rim_w :: 2.6;
    draw_quad_3d(.{x0, h + 0.05, z0}, .{x1, h + 0.05, z0}, .{x1, h + 0.05, z0 + rim_w}, .{x0, h + 0.05, z0 + rim_w}, rim);
    draw_quad_3d(.{x0, h + 0.05, z1 - rim_w}, .{x1, h + 0.05, z1 - rim_w}, .{x1, h + 0.05, z1}, .{x0, h + 0.05, z1}, rim);
    draw_quad_3d(.{x0, h + 0.05, z0}, .{x0 + rim_w, h + 0.05, z0}, .{x0 + rim_w, h + 0.05, z1}, .{x0, h + 0.05, z1}, rim);
    draw_quad_3d(.{x1 - rim_w, h + 0.05, z0}, .{x1, h + 0.05, z0}, .{x1, h + 0.05, z1}, .{x1 - rim_w, h + 0.05, z1}, rim);

    // X-cross on top to read as a crate.
    cross := col(0.28, 0.18, 0.10, 1);
    cross_w :: 3.0;
    in_x0 := x0 + rim_w + 2;
    in_x1 := x1 - rim_w - 2;
    in_z0 := z0 + rim_w + 2;
    in_z1 := z1 - rim_w - 2;
    draw_quad_3d(.{in_x0, h + 0.10, in_z0}, .{in_x0 + cross_w, h + 0.10, in_z0}, .{in_x1, h + 0.10, in_z1}, .{in_x1 - cross_w, h + 0.10, in_z1}, cross);
    draw_quad_3d(.{in_x1 - cross_w, h + 0.10, in_z0}, .{in_x1, h + 0.10, in_z0}, .{in_x0 + cross_w, h + 0.10, in_z1}, .{in_x0, h + 0.10, in_z1}, cross);

    // Tag on the front face.
    label_bg := col(0.86, 0.78, 0.52, 1);
    label_edge := col(0.40, 0.30, 0.16, 1);
    fy := h * 0.40;
    seed := c * 7 + r * 11;
    off := cast(float)((seed % 8) - 4);
    draw_quad_3d(.{cx_w - 9 + off, fy - 1, z1 + 0.1}, .{cx_w + 9 + off, fy - 1, z1 + 0.1}, .{cx_w + 9 + off, fy + 9, z1 + 0.1}, .{cx_w - 9 + off, fy + 9, z1 + 0.1}, label_edge);
    draw_quad_3d(.{cx_w - 8 + off, fy, z1 + 0.15}, .{cx_w + 8 + off, fy, z1 + 0.15}, .{cx_w + 8 + off, fy + 8, z1 + 0.15}, .{cx_w - 8 + off, fy + 8, z1 + 0.15}, label_bg);
}

draw_wall_beach :: (c: int, r: int) {
    cx_w := cast(float)(c * TILE) + cast(float)TILE * 0.5;
    cz_w := cast(float)(r * TILE) + cast(float)TILE * 0.5;
    half := cast(float)TILE * 0.46;
    h := cast(float)TILE * 0.92;
    base := col(0.38, 0.30, 0.22, 1);
    top  := col(0.60, 0.50, 0.38, 1);
    draw_cube_3d(cx_w, cz_w, half, h, top, base);

    x0 := cx_w - half;
    x1 := cx_w + half;
    z1 := cz_w + half;

    // Horizontal grain bands on the face.
    grain := col(0.20, 0.14, 0.08, 1);
    for i: 1..3 {
        gy := h * cast(float)i / 4.0;
        draw_quad_3d(.{x0 + 3, gy, z1 + 0.1}, .{x1 - 3, gy, z1 + 0.1}, .{x1 - 3, gy + 0.8, z1 + 0.1}, .{x0 + 3, gy + 0.8, z1 + 0.1}, grain);
    }

    seed := c * 23 + r * 41;
    sx, sy, s := wall_top_screen(c, r, 0.92);
    pick := seed % 3;

    if pick == 0 {
        // Starfish on top.
        bob := sin(cast(float)frame_count / 20.0 + cast(float)seed * 0.07) * 1.0;
        star_y := sy - 6 + bob;
        body_c := col(1.00, 0.55, 0.28, 1);
        body_l := col(1.00, 0.78, 0.50, 1);
        body_d := col(0.65, 0.30, 0.12, 1);
        arm_r := 11.0 * s;
        for i: 0..4 {
            ang := (cast(float)i / 5.0) * TAU - PI * 0.5 + cast(float)frame_count * 0.004;
            ax := sx + cos(ang) * arm_r;
            ay := star_y + sin(ang) * arm_r;
            mx := sx + cos(ang) * arm_r * 0.45;
            my := star_y + sin(ang) * arm_r * 0.45;
            wx := -sin(ang) * 4.0 * s;
            wy :=  cos(ang) * 4.0 * s;
            // Arm outline
            draw_triangle(mx - wx * 1.1, my - wy * 1.1, mx + wx * 1.1, my + wy * 1.1, ax, ay, body_d);
            // Arm fill
            draw_triangle(mx - wx, my - wy, mx + wx, my + wy, ax, ay, body_c);
        }
        draw_filled_circle(sx, star_y, 6 * s, body_d, 14);
        draw_filled_circle(sx, star_y, 4.6 * s, body_c, 14);
        // Speckles
        for i: 0..3 {
            ang := (cast(float)i / 4.0) * TAU + cast(float)seed;
            sxp := sx + cos(ang) * 2.5 * s;
            syp := star_y + sin(ang) * 2.5 * s;
            draw_filled_circle(sxp, syp, 0.9 * s, body_l, 5);
        }
    } else if pick == 1 {
        // Two seashells stacked.
        sh1 := col(1.00, 0.92, 0.78, 1);
        sh2 := col(0.96, 0.75, 0.58, 1);
        sh_rim := col(0.65, 0.42, 0.28, 1);
        // Bottom shell
        cx1 := sx - 4 * s;
        cy1 := sy - 4;
        draw_filled_ellipse(cx1, cy1 + 1, 11 * s, 4 * s, col(0, 0, 0, 0.30));
        draw_filled_ellipse(cx1, cy1, 10 * s, 6 * s, sh_rim);
        draw_filled_ellipse(cx1, cy1, 9 * s, 5 * s, sh1);
        // Ridges
        for i: 0..3 {
            rx := cx1 - 6 * s + cast(float)i * 4 * s;
            draw_line(rx, cy1 - 4 * s, rx, cy1 + 4 * s, sh2, 0.9 * s);
        }
        // Top spiral shell
        cx2 := sx + 6 * s;
        cy2 := sy - 12;
        draw_filled_circle(cx2, cy2 + 1, 7 * s, col(0, 0, 0, 0.30), 12);
        draw_filled_circle(cx2, cy2, 7 * s, sh_rim, 14);
        draw_filled_circle(cx2, cy2, 6 * s, sh1, 14);
        for i: 0..2 {
            ang := cast(float)i * 1.6 + cast(float)frame_count * 0.01;
            rr := 4.5 * s - cast(float)i * 1.5 * s;
            draw_filled_circle(cx2 + cos(ang) * rr * 0.4, cy2 + sin(ang) * rr * 0.4, 1.8 * s, sh2, 6);
        }
    } else {
        // Palm frond fan.
        sway := sin(cast(float)frame_count / 28.0 + cast(float)seed * 0.05) * 0.18;
        stem_c := col(0.30, 0.22, 0.10, 1);
        leaf_d := col(0.18, 0.45, 0.22, 1);
        leaf_l := col(0.36, 0.78, 0.36, 1);
        // Pot (coconut at base)
        draw_filled_circle(sx, sy - 6, 6 * s, col(0.40, 0.25, 0.12, 1), 12);
        draw_filled_circle(sx, sy - 6, 4.5 * s, col(0.22, 0.14, 0.08, 1), 12);
        // Fronds — 5 of them fanning up.
        leaf_len := 22 * s;
        for i: 0..4 {
            t := cast(float)(i - 2);
            ang := -PI * 0.5 + t * 0.42 + sway;
            tip_x := sx + cos(ang) * leaf_len;
            tip_y := sy - 6 + sin(ang) * leaf_len;
            mid_x := sx + cos(ang) * leaf_len * 0.55;
            mid_y := sy - 6 + sin(ang) * leaf_len * 0.55;
            wx := -sin(ang) * 4 * s;
            wy :=  cos(ang) * 4 * s;
            draw_triangle(mid_x - wx, mid_y - wy, mid_x + wx, mid_y + wy, tip_x, tip_y, leaf_d);
            // Highlight
            draw_line(sx, sy - 6, tip_x, tip_y, leaf_l, 1.2 * s);
        }
    }
}

draw_brick_beach :: (c: int, r: int) {
    cx_w := cast(float)(c * TILE) + cast(float)TILE * 0.5;
    cz_w := cast(float)(r * TILE) + cast(float)TILE * 0.5;
    // Driftwood log lying flat.
    h := cast(float)TILE * 0.45;
    half := cast(float)TILE * 0.42;
    base := col(0.50, 0.36, 0.22, 1);
    top  := col(0.74, 0.58, 0.38, 1);
    draw_cube_3d(cx_w, cz_w, half, h, top, base);

    x0 := cx_w - half;
    x1 := cx_w + half;
    z0 := cz_w - half;
    z1 := cz_w + half;

    // Concentric growth rings on the top face (using progressively shrinking
    // squares — keeps it block-aligned with the rest of the art).
    ring1 := col(0.34, 0.22, 0.14, 1);
    ring2 := col(0.60, 0.44, 0.28, 1);
    ring3 := col(0.82, 0.66, 0.44, 1);
    for i: 0..2 {
        inset := 4.0 + cast(float) i * 4.0;
        c_band := ifx (i % 2) == 0 then ring1 else ring2;
        draw_quad_3d(.{x0 + inset, h + 0.05 + cast(float)i * 0.02, z0 + inset},
                     .{x1 - inset, h + 0.05 + cast(float)i * 0.02, z0 + inset},
                     .{x1 - inset, h + 0.05 + cast(float)i * 0.02, z1 - inset},
                     .{x0 + inset, h + 0.05 + cast(float)i * 0.02, z1 - inset}, c_band);
    }
    draw_quad_3d(.{cx_w - 2, h + 0.12, cz_w - 2}, .{cx_w + 2, h + 0.12, cz_w - 2}, .{cx_w + 2, h + 0.12, cz_w + 2}, .{cx_w - 2, h + 0.12, cz_w + 2}, ring3);

    // Knot on the front face.
    knot_d := col(0.20, 0.12, 0.06, 1);
    knot_l := col(0.40, 0.26, 0.14, 1);
    seed := c * 11 + r * 29;
    kx := cx_w - 6 + cast(float)((seed % 14) - 7);
    ky := h * 0.4;
    draw_quad_3d(.{kx - 3, ky - 1, z1 + 0.1}, .{kx + 3, ky - 1, z1 + 0.1}, .{kx + 3, ky + 7, z1 + 0.1}, .{kx - 3, ky + 7, z1 + 0.1}, knot_d);
    draw_quad_3d(.{kx - 1.5, ky + 1, z1 + 0.15}, .{kx + 1.5, ky + 1, z1 + 0.15}, .{kx + 1.5, ky + 5, z1 + 0.15}, .{kx - 1.5, ky + 5, z1 + 0.15}, knot_l);
}

draw_background :: () {
    vw := cast(float)WINDOW_W;
    vh := cast(float)WINDOW_H;

    // Multi-stop vertical sky pulled from the active level theme.
    sky_top     := current_theme.sky_top;
    sky_high    := current_theme.sky_high;
    sky_mid     := current_theme.sky_mid;
    sky_horizon := current_theme.sky_horizon;
    sky_under   := current_theme.sky_under;
    sky_floor   := current_theme.sky_floor;

    h1 := vh * 0.18;
    h2 := vh * 0.40;
    h3 := vh * 0.50;
    h4 := vh * 0.68;
    draw_vgradient(0, 0,        vw, h1,       sky_top,    sky_high);
    draw_vgradient(0, h1,       vw, h2 - h1,  sky_high,   sky_mid);
    draw_vgradient(0, h2,       vw, h3 - h2,  sky_mid,    sky_horizon);
    draw_vgradient(0, h3,       vw, h4 - h3,  sky_horizon, sky_under);
    draw_vgradient(0, h4,       vw, vh - h4,  sky_under,  sky_floor);

    // Glowing moon up-right
    moon_pulse := 0.92 + sin(cast(float)frame_count / 90.0) * 0.08;
    mx := vw * 0.78;
    my := vh * 0.18;
    bg := current_theme.body_glow;
    bc := current_theme.body_core;
    bh := current_theme.body_hot;
    for i: 0..4 {
        rr := 36.0 + cast(float)i * 22.0;
        a  := (0.28 - cast(float)i * 0.055) * moon_pulse;
        if a > 0 draw_filled_circle(mx, my, rr, col(bg.x, bg.y, bg.z, a), 22);
    }
    draw_filled_circle(mx, my, 32, col(bc.x, bc.y, bc.z, moon_pulse * 0.96), 22);
    draw_filled_circle(mx - 6, my - 8, 8, col(bh.x, bh.y, bh.z, 0.55), 14);
    draw_filled_circle(mx + 8, my + 6, 5, col(bh.x * 0.95, bh.y * 0.92, bh.z * 0.92, 0.45), 12);

    // Aurora curtain — flowing wavy bands of color across the upper sky
    aurora_t := cast(float)frame_count / 110.0;
    for layer: 0..2 {
        lf := cast(float)layer;
        base_y := vh * 0.16 + lf * 18.0;
        layer_alpha := (0.22 - lf * 0.055) * (0.85 + sin(aurora_t * 0.7 + lf) * 0.20);
        col_a, col_b: Vector4;
        if layer == 0 {
            col_a = current_theme.aurora_0a;
            col_b = current_theme.aurora_0b;
        } else if layer == 1 {
            col_a = current_theme.aurora_1a;
            col_b = current_theme.aurora_1b;
        } else {
            col_a = current_theme.aurora_2a;
            col_b = current_theme.aurora_2b;
        }
        steps :: 32;
        sw := vw / cast(float)steps;
        for i: 0..steps-1 {
            t0 := cast(float)i / cast(float)steps;
            t1 := cast(float)(i + 1) / cast(float)steps;
            x0 := t0 * vw;
            x1 := t1 * vw;
            y0_off := sin(aurora_t + t0 * 6.0 + lf * 1.7) * 22.0;
            y1_off := sin(aurora_t + t1 * 6.0 + lf * 1.7) * 22.0;
            h := 56.0 + sin(aurora_t * 1.3 + t0 * 4.0 + lf) * 16.0;
            ya := base_y + y0_off;
            yb := base_y + y1_off;
            ca := mix4(col_a, col_b, t0);
            cb := mix4(col_a, col_b, t1);
            ca.w = layer_alpha;
            cb.w = layer_alpha;
            ca_bottom := ca; ca_bottom.w = 0;
            cb_bottom := cb; cb_bottom.w = 0;
            Simp.immediate_quad(
                Vector2.{x0, ya},
                Vector2.{x1, yb},
                Vector2.{x1, yb + h},
                Vector2.{x0, ya + h},
                ca, cb, cb_bottom, ca_bottom
            );
        }
    }

    // Horizon halo band (pulsing magenta)
    horizon_y := vh * 0.50;
    horizon_pulse := 0.85 + sin(cast(float)frame_count / 70.0) * 0.18 + recent_boom * 0.4;
    hb := current_theme.horizon_band;
    hs := current_theme.horizon_sliver;
    for i: 0..5 {
        thick := 14.0 + cast(float)i * 22.0;
        a := (0.22 - cast(float)i * 0.038) * horizon_pulse;
        if a > 0 Simp.immediate_quad(0, horizon_y - thick * 0.5, vw, horizon_y + thick * 0.5, col(hb.x, hb.y, hb.z, a));
    }
    // Hot sliver right on the horizon
    Simp.immediate_quad(0, horizon_y - 1.2, vw, horizon_y + 1.2, col(hs.x, hs.y, hs.z, 0.85 * horizon_pulse));

    // Stars
    for stars {
        // Stars near the horizon dim out
        dimming := 1.0;
        if it.sy > vh * 0.42 {
            dimming = max(0.0, 1.0 - (it.sy - vh * 0.42) / (vh * 0.18));
        }
        a := it.base * dimming * (0.55 + 0.45 * sin(cast(float)frame_count / 22.0 + it.twinkle));
        if a < 0.02 continue;
        c := col(it.color.x, it.color.y, it.color.z, a);
        draw_filled_circle(it.sx, it.sy, it.size, c, 6);
        if it.size > 1.3 {
            glint := a * 0.55;
            Simp.immediate_quad(it.sx - it.size * 3.0, it.sy - 0.3, it.sx + it.size * 3.0, it.sy + 0.3, col(it.color.x, it.color.y, it.color.z, glint));
            Simp.immediate_quad(it.sx - 0.3, it.sy - it.size * 3.0, it.sx + 0.3, it.sy + it.size * 3.0, col(it.color.x, it.color.y, it.color.z, glint));
        }
    }

    // A couple of slow shooting streaks every now and then (deterministic on frame_count)
    streak_period :: 320;
    sp := frame_count % streak_period;
    if sp < 38 {
        t := cast(float)sp / 38.0;
        seed := cast(float)((frame_count / streak_period) * 73 + 11);
        sxa := (seed * 0.3 - floor(seed * 0.3)) * vw;
        sya := (seed * 0.71 - floor(seed * 0.71)) * vh * 0.35;
        tx := sxa + t * 280.0;
        ty := sya + t * 70.0;
        a := sin(t * PI) * 0.85;
        draw_line(tx - 28, ty - 7, tx, ty, col(1.0, 1.0, 1.0, a), 1.6);
        draw_line(tx - 14, ty - 3.5, tx + 4, ty + 1, col(0.85, 0.92, 1.0, a * 0.65), 0.9);
        draw_filled_circle(tx, ty, 1.6, col(1, 1, 1, a), 6);
    }
}

draw_ambient_motes_world :: () {
    // Draw motes by projecting their world position. They get a soft glow.
    for ambient_motes {
        // Twinkle alpha
        a := 0.45 + sin(it.phase) * 0.30;
        sc, ok := project(.{it.x, it.height, it.z});
        if !ok continue;
        if sc.x < -20 || sc.x > cast(float)WINDOW_W + 20 continue;
        if sc.y < -20 || sc.y > cast(float)WINDOW_H + 20 continue;
        s := screen_scale_at(.{it.x, it.height, it.z});
        sz := it.size * (0.8 + 0.4 * s);
        // outer halo
        draw_filled_circle(sc.x, sc.y, sz * 2.4, col(it.color.x, it.color.y, it.color.z, a * 0.10), 8);
        draw_filled_circle(sc.x, sc.y, sz * 1.4, col(it.color.x, it.color.y, it.color.z, a * 0.45), 8);
        draw_filled_circle(sc.x, sc.y, sz * 0.65, col(1, 1, 1, a * 0.85), 6);
    }
}

draw_floor_light :: (cx_w: float, cz_w: float, world_radius: float, color: Vector4, intensity: float) {
    s := screen_scale_at(.{cx_w, 0.4, cz_w});
    sc, _ := project(.{cx_w, 0.4, cz_w});
    rx := world_radius * s;
    if rx < 1 return;
    ry := rx * 0.5;
    layers :: 6;
    for i: 0..layers-1 {
        t := cast(float)i / cast(float)(layers - 1);
        f := 1.0 - t;
        a := intensity * f * f * 0.55;
        if a < 0.01 continue;
        scale := 0.25 + 0.75 * f;
        draw_filled_ellipse(sc.x, sc.y, rx * scale, ry * scale, col(color.x, color.y, color.z, a), 22);
    }
}

draw_floor_lights :: () {
    // Bombs: pulsing magenta pools, intensity rises near detonation.
    for bombs {
        if it.punching continue;
        if it.x < 0 || it.y < 0 continue;
        pct_left := cast(float)it.timer / cast(float)BOMB_TIMER;
        danger := 1.0 - pct_left;
        pulse := 0.7 + sin(cast(float)frame_count / (3.5 - danger * 1.8)) * 0.30;
        cx_w := cast(float)(it.x * TILE) + cast(float)TILE * 0.5;
        cz_w := cast(float)(it.y * TILE) + cast(float)TILE * 0.5;
        radius := cast(float)TILE * (1.05 + danger * 0.45);
        glow_c := col(0.702, 0.404, 1.0, 1);
        if danger > 0.65 glow_c = col(1.0, 0.55, 0.78, 1);
        draw_floor_light(cx_w, cz_w, radius, glow_c, (0.65 + danger * 0.45) * pulse);
    }

    // Powerups: gentle pool of their own color.
    for powerups {
        if it.delay > 0 continue;
        cx_w := cast(float)(it.x * TILE) + cast(float)TILE * 0.5;
        cz_w := cast(float)(it.y * TILE) + cast(float)TILE * 0.5;
        c := powerup_color(it.type);
        wob := 0.85 + sin(cast(float)frame_count / 18.0 + cast(float)(it.x * 7 + it.y * 11)) * 0.15;
        draw_floor_light(cx_w, cz_w, cast(float)TILE * 0.85, c, 0.55 * wob);
    }

    // Active explosions: very bright, brief.
    for explosions_list {
        cx_w := cast(float)(it.x * TILE) + cast(float)TILE * 0.5;
        cz_w := cast(float)(it.y * TILE) + cast(float)TILE * 0.5;
        prog := 1.0 - cast(float)it.timer / cast(float)it.duration;
        inv := 1.0 - prog;
        radius := cast(float)TILE * (1.1 + prog * 0.6);
        // Hot pink-white pool
        draw_floor_light(cx_w, cz_w, radius, col(1.0, 0.85, 1.0, 1), 1.1 * inv);
        // Outer magenta ring
        draw_floor_light(cx_w, cz_w, radius * 1.5, col(0.95, 0.45, 1.0, 1), 0.55 * inv);

        if it.origin {
            // Expanding floor shockwave — bright thin ring crawling outward.
            ring_r_world := cast(float)TILE * (0.2 + prog * 1.6);
            sc, _ := project(.{cx_w, 0.5, cz_w});
            s := screen_scale_at(.{cx_w, 0.5, cz_w});
            rx := ring_r_world * s;
            ry := rx * 0.5;
            ring_a := inv * 0.85;
            segs :: 40;
            for j: 0..segs-1 {
                ang := (cast(float)j / cast(float)segs) * TAU;
                px := sc.x + cos(ang) * rx;
                py := sc.y + sin(ang) * ry;
                draw_filled_circle(px, py, 1.6 + inv * 1.6, col(1.0, 0.92, 1.0, ring_a), 5);
            }
            // Inner trailing ring
            if prog > 0.15 {
                inner_r := ring_r_world * 0.7;
                irx := inner_r * s;
                iry := irx * 0.5;
                for j: 0..segs-1 {
                    ang := (cast(float)j / cast(float)segs) * TAU + 0.08;
                    px := sc.x + cos(ang) * irx;
                    py := sc.y + sin(ang) * iry;
                    draw_filled_circle(px, py, 1.0 + inv * 0.7, col(0.92, 0.62, 1.0, ring_a * 0.55), 5);
                }
            }
        }
    }

    // Characters: subtle aura pool under each
    if !game_over {
        p_cx := player.rx * cast(float)TILE + cast(float)TILE * 0.5;
        p_cz := player.ry * cast(float)TILE + cast(float)TILE * 0.5;
        p_pulse := 0.85 + sin(cast(float)frame_count / 28.0) * 0.15;
        draw_floor_light(p_cx, p_cz, cast(float)TILE * 0.75, col(0.40, 0.72, 1.0, 1), 0.42 * p_pulse);

        for * en: enemies {
            if !en.alive continue;
            e_cx := en.rx * cast(float)TILE + cast(float)TILE * 0.5;
            e_cz := en.ry * cast(float)TILE + cast(float)TILE * 0.5;
            e_pulse := 0.85 + sin(cast(float)frame_count / 26.0 + cast(float)en.id) * 0.15;
            draw_floor_light(e_cx, e_cz, cast(float)TILE * 0.70, en.glow, 0.40 * e_pulse);
        }
    }
}

draw_melting_brick_3d :: (m: MeltingBrick) {
    cx_w := cast(float)(m.x * TILE) + cast(float)TILE * 0.5;
    cz_w := cast(float)(m.y * TILE) + cast(float)TILE * 0.5;
    pct := cast(float)m.timer / cast(float)MELT_DURATION;
    height := cast(float)TILE * 0.72 * pct;
    if height < 1 return;
    alpha := 0.4 + pct * 0.6;
    mb := current_theme.melt_base;
    mt := current_theme.melt_top;
    base := col(mb.x, mb.y, mb.z, alpha);
    topc := col(mt.x, mt.y, mt.z, alpha);
    half := cast(float)TILE * 0.45 * (0.7 + pct * 0.3);
    draw_cube_3d(cx_w, cz_w, half, height, topc, base);
}

draw_player_char :: (cx: float, cy: float) {
    d := player.dir;
    bob := sin(cast(float)frame_count / 12.0) * 0.6;
    cyb := cy + bob;

    glow_pulse := 0.55 + sin(cast(float)frame_count / 18.0) * 0.15;
    draw_filled_ellipse(cx, cy + cast(float)TILE/2 - 4, 30, 10, col(0.353, 0.604, 0.965, 0.22 * glow_pulse));
    draw_filled_ellipse(cx, cy + cast(float)TILE/2 - 4, 19, 6.5, col(0.565, 0.792, 0.976, 0.36 * glow_pulse));
    draw_filled_ellipse(cx, cy + cast(float)TILE/2 - 2, 14, 5, col(0, 0, 0, 0.40));

    // Orbiting magical sparkles (3 motes circling the wizard)
    for i: 0..2 {
        ang := cast(float)frame_count / 24.0 + cast(float)i * (TAU / 3.0);
        ox := cos(ang) * 18.0;
        oy := sin(ang) * 5.0 + 6;
        depth := sin(ang) * 0.5 + 0.5;
        a := 0.45 + depth * 0.45;
        sz := 1.3 + depth * 1.2;
        draw_filled_circle(cx + ox, cyb + oy, sz * 2.0, col(0.55, 0.85, 1.0, a * 0.30), 8);
        draw_filled_circle(cx + ox, cyb + oy, sz,       col(0.78, 0.92, 1.0, a),        6);
        draw_filled_circle(cx + ox, cyb + oy, sz * 0.5, col(1, 1, 1, a),                4);
    }

    robe_dark   := col(0.043, 0.227, 0.482, 1);
    robe_mid    := col(0.084, 0.396, 0.753, 1);
    robe_light  := col(0.227, 0.561, 0.886, 1);
    skin        := col(0.957, 0.847, 0.690, 1);
    skin_shade  := col(0.745, 0.612, 0.490, 1);
    hat_dark    := col(0.137, 0.078, 0.298, 1);
    hat_mid     := col(0.290, 0.196, 0.498, 1);

    draw_triangle(cx - 17, cyb + 22, cx - 9, cyb + 1, cx + 9, cyb + 1, robe_dark);
    draw_triangle(cx - 17, cyb + 22, cx + 9, cyb + 1, cx + 17, cyb + 22, robe_dark);
    draw_triangle(cx - 14, cyb + 20, cx - 7, cyb + 2, cx + 7, cyb + 2, robe_mid);
    draw_triangle(cx - 14, cyb + 20, cx + 7, cyb + 2, cx + 14, cyb + 20, robe_mid);
    draw_filled_rect(cx - 11, cyb + 9, 22, 3, robe_dark);
    draw_filled_rect(cx - 3, cyb + 9, 6, 3, col(0.937, 0.804, 0.196, 1));

    draw_filled_circle(cx - 4, cyb + 14, 2, robe_light, 6);
    draw_filled_circle(cx + 5, cyb + 18, 1.6, robe_light, 6);

    draw_filled_circle(cx + 14, cyb - 4, 1.8, col(0.412, 0.275, 0.118, 1), 6);
    draw_line(cx + 14, cyb - 4, cx + 14, cyb + 18, col(0.412, 0.275, 0.118, 1), 2.2);
    draw_filled_circle(cx + 14, cyb - 6, 3.5, col(0.565, 0.792, 0.976, 0.95), 10);
    draw_filled_circle(cx + 14, cyb - 6, 1.8, col(1, 1, 1, 0.9), 8);

    draw_filled_circle(cx, cyb - 7, 11, skin_shade, 14);
    draw_filled_circle(cx - 1, cyb - 8, 10, skin, 14);

    if d == {
        case .UP;
            draw_filled_rect(cx - 13, cyb - 14, 26, 4, hat_dark);
            draw_filled_circle(cx, cyb - 12, 11, hat_dark, 14);
        case .DOWN;
            draw_filled_rect(cx - 13, cyb - 14, 26, 4, hat_dark);
            draw_triangle(cx - 13, cyb - 14, cx + 13, cyb - 14, cx + 1, cyb - 33, hat_mid);
            draw_triangle(cx - 11, cyb - 14, cx + 1, cyb - 33, cx - 4, cyb - 14, hat_dark);
            draw_filled_circle(cx + 1, cyb - 33, 2.5, col(1, 0.961, 0.620, 1), 8);
            draw_filled_circle(cx + 1, cyb - 33, 1.2, col(1, 1, 1, 1), 6);
        case .LEFT;
            draw_filled_rect(cx - 14, cyb - 14, 26, 4, hat_dark);
            draw_triangle(cx + 12, cyb - 14, cx - 14, cyb - 14, cx - 14, cyb - 30, hat_mid);
            draw_triangle(cx - 14, cyb - 14, cx - 14, cyb - 30, cx - 9, cyb - 14, hat_dark);
            draw_filled_circle(cx - 14, cyb - 30, 2.3, col(1, 0.961, 0.620, 1), 8);
        case .RIGHT;
            draw_filled_rect(cx - 12, cyb - 14, 26, 4, hat_dark);
            draw_triangle(cx - 12, cyb - 14, cx + 14, cyb - 14, cx + 14, cyb - 30, hat_mid);
            draw_triangle(cx + 14, cyb - 14, cx + 14, cyb - 30, cx + 9, cyb - 14, hat_dark);
            draw_filled_circle(cx + 14, cyb - 30, 2.3, col(1, 0.961, 0.620, 1), 8);
    }

    pupil_color := col(0.102, 0.137, 0.494, 1);
    if player.stun_timer > 0 {
        wob := sin(cast(float)frame_count / 4.0) * 1.4;
        x_col := col(0.102, 0.137, 0.494, 1);
        ex1 := cx - 5 + wob;
        ex2 := cx + 4 + wob;
        ey  := cyb - 5;
        draw_line(ex1 - 3, ey - 3, ex1 + 3, ey + 3, x_col, 2);
        draw_line(ex1 - 3, ey + 3, ex1 + 3, ey - 3, x_col, 2);
        draw_line(ex2 - 3, ey - 3, ex2 + 3, ey + 3, x_col, 2);
        draw_line(ex2 - 3, ey + 3, ex2 + 3, ey - 3, x_col, 2);
        for i: 0..2 {
            angle := (cast(float)i / 3.0) * TAU + cast(float)frame_count / 12.0;
            sx := cx + cos(angle) * 14;
            sy := cyb - 26 + sin(angle) * 4;
            draw_filled_circle(sx, sy, 2.8, col(1, 0.922, 0.231, 1), 6);
        }
    } else if d != .UP {
        eye_shift: float;
        if d == .LEFT eye_shift = -1.5;
        else if d == .RIGHT eye_shift = 1.5;
        draw_filled_circle(cx - 5 + eye_shift * 0.4, cyb - 5, 4.5, col(1, 1, 1, 1), 10);
        draw_filled_circle(cx + 4 + eye_shift * 0.4, cyb - 5, 4.5, col(1, 1, 1, 1), 10);
        pdx: float;
        pdy: float;
        if d == .LEFT pdx = -2;
        else if d == .RIGHT pdx = 2;
        if d == .DOWN pdy = 1;
        draw_filled_circle(cx - 5 + pdx + eye_shift * 0.4, cyb - 5 + pdy, 2.5, pupil_color, 8);
        draw_filled_circle(cx + 4 + pdx + eye_shift * 0.4, cyb - 5 + pdy, 2.5, pupil_color, 8);
        draw_filled_circle(cx - 4 + pdx + eye_shift * 0.4, cyb - 6 + pdy, 0.9, col(1, 1, 1, 1), 4);
        draw_filled_circle(cx + 5 + pdx + eye_shift * 0.4, cyb - 6 + pdy, 0.9, col(1, 1, 1, 1), 4);
    } else {
        draw_filled_circle(cx - 5, cyb - 7, 3.8, col(1, 1, 1, 1), 10);
        draw_filled_circle(cx + 4, cyb - 7, 3.8, col(1, 1, 1, 1), 10);
        draw_filled_circle(cx - 5, cyb - 9, 2.1, pupil_color, 6);
        draw_filled_circle(cx + 4, cyb - 9, 2.1, pupil_color, 6);
    }
}

draw_enemy_char :: (e: *Enemy, cx: float, cy: float) {
    if !e.alive return;
    d := e.dir;
    bob := sin(cast(float)frame_count / 11.0 + cast(float)e.id) * 0.5;
    cyb := cy + bob;

    fx: float = 0;
    fy: float = 0;
    if d == .LEFT       fx = -2;
    else if d == .RIGHT fx = 2;
    if d == .UP         fy = -1.5;

    pdx: float = 0;
    pdy: float = 0;
    if d == .LEFT       pdx = -1.6;
    else if d == .RIGHT pdx = 1.6;
    if d == .UP         pdy = -1.5;
    else if d == .DOWN  pdy = 1.0;

    robe_dark, robe_mid, skin: Vector4;
    if e.id == {
        case 1; // red demon
            robe_dark = col(0.357, 0.039, 0.039, 1);
            robe_mid  = col(0.620, 0.094, 0.094, 1);
            skin      = col(0.871, 0.604, 0.486, 1);
        case 2; // purple wizard
            robe_dark = col(0.180, 0.039, 0.349, 1);
            robe_mid  = col(0.357, 0.122, 0.620, 1);
            skin      = col(0.847, 0.769, 0.694, 1);
        case 3; // green necromancer
            robe_dark = col(0.063, 0.220, 0.078, 1);
            robe_mid  = col(0.157, 0.435, 0.180, 1);
            skin      = col(0.706, 0.808, 0.643, 1);
    }

    glow_pulse := 0.6 + sin(cast(float)frame_count / 22.0 + cast(float)e.id) * 0.20;
    draw_filled_ellipse(cx, cy + cast(float)TILE/2 - 4, 26, 8.5, col(e.glow.x, e.glow.y, e.glow.z, 0.20 * glow_pulse));
    draw_filled_ellipse(cx, cy + cast(float)TILE/2 - 4, 16, 5.5, col(e.glow.x, e.glow.y, e.glow.z, 0.32 * glow_pulse));
    draw_filled_ellipse(cx, cy + cast(float)TILE/2 - 2, 13, 4, col(0, 0, 0, 0.40));

    // Orbiting embers in the enemy's glow color
    if e.stun_timer == 0 {
        for i: 0..1 {
            ang := cast(float)frame_count / 20.0 + cast(float)(e.id * 2 + i) * (TAU / 2.0);
            ox := cos(ang) * 17.0;
            oy := sin(ang) * 4.5 + 7;
            depth := sin(ang) * 0.5 + 0.5;
            a := 0.45 + depth * 0.45;
            sz := 1.2 + depth * 1.0;
            draw_filled_circle(cx + ox, cyb + oy, sz * 2.2, col(e.glow.x, e.glow.y, e.glow.z, a * 0.30), 8);
            draw_filled_circle(cx + ox, cyb + oy, sz,       col(e.glow.x, e.glow.y, e.glow.z, a),        6);
            draw_filled_circle(cx + ox, cyb + oy, sz * 0.5, col(1, 1, 1, a * 0.85),                       4);
        }
    }

    // Robe is the body — stays fixed (doesn't pivot with head)
    draw_triangle(cx - 16, cyb + 22, cx - 8, cyb + 2, cx + 8, cyb + 2, robe_dark);
    draw_triangle(cx - 16, cyb + 22, cx + 8, cyb + 2, cx + 16, cyb + 22, robe_dark);
    draw_triangle(cx - 13, cyb + 20, cx - 6, cyb + 3, cx + 6, cyb + 3, robe_mid);
    draw_triangle(cx - 13, cyb + 20, cx + 6, cyb + 3, cx + 13, cyb + 20, robe_mid);
    draw_filled_rect(cx - 10, cyb + 10, 20, 3, robe_dark);

    // Head pivots with facing
    hx := cx + fx;
    hy := cyb - 7 + fy;
    draw_filled_circle(hx, hy, 11, skin, 14);
    draw_filled_circle(hx + 3, hy - 2, 4, col(1, 1, 1, 0.10), 8);

    if e.id == 1 {
        hc := col(0.137, 0.039, 0.039, 1);
        if d == .UP {
            // Looking away — bigger horns visible on top of head
            draw_triangle(hx - 10, hy - 5, hx - 6, hy - 5, hx - 13, hy - 16, hc);
            draw_triangle(hx + 6, hy - 5, hx + 10, hy - 5, hx + 13, hy - 16, hc);
            draw_triangle(hx - 12, hy - 8, hx, hy - 13, hx + 12, hy - 8, hc);
        } else if d == .LEFT {
            // Side-on horns — far horn smaller and tucked behind
            draw_triangle(hx - 9, hy - 7, hx - 4, hy - 7, hx - 14, hy - 16, hc);
            draw_triangle(hx + 4, hy - 7, hx + 7, hy - 7, hx + 7, hy - 13, hc);
            draw_triangle(hx - 10, hy - 9, hx - 2, hy - 12, hx + 7, hy - 9, hc);
        } else if d == .RIGHT {
            draw_triangle(hx + 4, hy - 7, hx + 9, hy - 7, hx + 14, hy - 16, hc);
            draw_triangle(hx - 7, hy - 7, hx - 4, hy - 7, hx - 7, hy - 13, hc);
            draw_triangle(hx - 7, hy - 9, hx + 2, hy - 12, hx + 10, hy - 9, hc);
        } else { // DOWN
            draw_triangle(hx - 9, hy - 7, hx - 5, hy - 7, hx - 12, hy - 15, hc);
            draw_triangle(hx + 5, hy - 7, hx + 9, hy - 7, hx + 12, hy - 15, hc);
            draw_triangle(hx - 11, hy - 9, hx, hy - 12, hx + 11, hy - 9, hc);
        }
    } else if e.id == 2 {
        hat_d := col(0.110, 0.027, 0.220, 1);
        hat_m := col(0.247, 0.078, 0.443, 1);
        star  := col(0.918, 0.502, 0.988, 1);
        if d == .LEFT {
            draw_filled_rect(hx - 14, hy - 7, 26, 4, hat_d);
            draw_triangle(hx + 12, hy - 7, hx - 14, hy - 7, hx - 17, hy - 27, hat_m);
            draw_filled_circle(hx - 17, hy - 27, 2.3, star, 8);
        } else if d == .RIGHT {
            draw_filled_rect(hx - 12, hy - 7, 26, 4, hat_d);
            draw_triangle(hx - 12, hy - 7, hx + 14, hy - 7, hx + 17, hy - 27, hat_m);
            draw_filled_circle(hx + 17, hy - 27, 2.3, star, 8);
        } else if d == .UP {
            // Hat tilted back — wider brim visible from behind, short tip
            draw_filled_rect(hx - 13, hy - 7, 26, 4, hat_d);
            draw_triangle(hx - 11, hy - 7, hx + 11, hy - 7, hx, hy - 20, hat_d);
            draw_filled_circle(hx, hy - 20, 2.0, star, 8);
        } else { // DOWN
            draw_filled_rect(hx - 13, hy - 7, 26, 4, hat_d);
            draw_triangle(hx - 13, hy - 7, hx + 13, hy - 7, hx, hy - 29, hat_m);
            draw_filled_circle(hx, hy - 29, 2.2, star, 8);
        }
    } else if e.id == 3 {
        hood_d := col(0.043, 0.149, 0.055, 1);
        hood_m := col(0.094, 0.282, 0.106, 1);
        // Peak (back of the hood) swings opposite to facing
        peak_x := hx;
        peak_y := hy - 11;
        if d == .LEFT       peak_x = hx + 3;
        else if d == .RIGHT peak_x = hx - 3;
        else if d == .UP    peak_y = hy - 6;
        lbx := cx - 15; lby := cyb + 4;
        rbx := cx + 15; rby := cyb + 4;
        draw_triangle(lbx, lby, hx - 14, hy - 9, peak_x, peak_y, hood_d);
        draw_triangle(lbx, lby, peak_x, peak_y, rbx, rby, hood_d);
        draw_triangle(rbx, rby, hx + 14, hy - 9, peak_x, peak_y, hood_d);
        draw_triangle(cx - 12, cyb + 2, hx - 11, hy - 6, peak_x, peak_y + 3, hood_m);
        draw_triangle(cx + 12, cyb + 2, hx + 11, hy - 6, peak_x, peak_y + 3, hood_m);
        // Face shadow under hood
        draw_filled_circle(hx, hy + 1, 9, col(0.157, 0.106, 0.157, 1), 12);
    }

    // Eyes
    if e.stun_timer > 0 {
        // Knocked out — X eyes, wobbling slightly
        wob := sin(cast(float)frame_count / 4.0 + cast(float)e.id) * 1.4;
        x_col := col(0.1, 0.06, 0.06, 1);
        ex1 := hx - 5 + wob;
        ex2 := hx + 5 + wob;
        ey  := hy + 2;
        draw_line(ex1 - 3, ey - 3, ex1 + 3, ey + 3, x_col, 2);
        draw_line(ex1 - 3, ey + 3, ex1 + 3, ey - 3, x_col, 2);
        draw_line(ex2 - 3, ey - 3, ex2 + 3, ey + 3, x_col, 2);
        draw_line(ex2 - 3, ey + 3, ex2 + 3, ey - 3, x_col, 2);
    } else if e.id == 3 {
        ey := hy + 2;
        if d == .UP {
            // hood hides face — single glow visible
            draw_filled_circle(hx, hy - 2, 2.2, e.glow, 8);
            draw_filled_circle(hx, hy - 2, 1.0, col(1, 1, 1, 1), 6);
        } else {
            draw_filled_circle(hx - 4 + pdx * 0.7, ey + pdy * 0.7, 2.5, e.glow, 8);
            draw_filled_circle(hx + 4 + pdx * 0.7, ey + pdy * 0.7, 2.5, e.glow, 8);
            draw_filled_circle(hx - 4 + pdx * 0.7, ey + pdy * 0.7, 1.3, col(1, 1, 1, 1), 6);
            draw_filled_circle(hx + 4 + pdx * 0.7, ey + pdy * 0.7, 1.3, col(1, 1, 1, 1), 6);
        }
    } else {
        if d == .UP {
            // Looking up/away — just back of head, no eyes from this angle
        } else {
            ey := hy + 2;
            draw_filled_circle(hx - 5, ey, 4.5, col(1, 1, 1, 1), 10);
            draw_filled_circle(hx + 5, ey, 4.5, col(1, 1, 1, 1), 10);
            draw_filled_circle(hx - 5 + pdx, ey + pdy, 2.6, e.color, 8);
            draw_filled_circle(hx + 5 + pdx, ey + pdy, 2.6, e.color, 8);
            draw_filled_circle(hx - 5 + pdx, ey + pdy, 1.2, e.glow, 6);
            draw_filled_circle(hx + 5 + pdx, ey + pdy, 1.2, e.glow, 6);
            draw_filled_circle(hx - 4 + pdx, ey + pdy - 1, 0.7, col(1, 1, 1, 1), 4);
            draw_filled_circle(hx + 6 + pdx, ey + pdy - 1, 0.7, col(1, 1, 1, 1), 4);
        }
    }

    // Fangs — red demon only, facing forward/sideways, not while knocked out
    if e.id == 1 && d != .UP && e.stun_timer == 0 {
        fy_base := hy + 6;
        if d == .LEFT {
            draw_triangle(hx - 4, fy_base, hx - 6, fy_base + 3, hx - 3, fy_base + 3, col(1, 1, 1, 0.9));
        } else if d == .RIGHT {
            draw_triangle(hx + 4, fy_base, hx + 6, fy_base + 3, hx + 3, fy_base + 3, col(1, 1, 1, 0.9));
        } else {
            draw_triangle(hx - 2, fy_base, hx - 4, fy_base + 3, hx - 1, fy_base + 3, col(1, 1, 1, 0.9));
            draw_triangle(hx + 2, fy_base, hx + 4, fy_base + 3, hx + 1, fy_base + 3, col(1, 1, 1, 0.9));
        }
    }

    if e.stun_timer > 0 {
        for i: 0..2 {
            angle := (cast(float)i / 3.0) * TAU + cast(float)frame_count / 12.0;
            sx := cx + cos(angle) * 14;
            sy := cyb - 18 + sin(angle) * 4;
            draw_filled_circle(sx, sy, 2.8, col(1, 0.922, 0.231, 1), 6);
        }
    }
}

draw_bomb :: (b: Bomb, bx: float, by: float) {
    pct_left := cast(float)b.timer / cast(float)BOMB_TIMER;
    danger := 1.0 - pct_left;
    pulse_rate := 4.0 - danger * 2.5;
    if pulse_rate < 1.2 pulse_rate = 1.2;
    pulse := sin(cast(float)frame_count / pulse_rate) * (2.5 + danger * 5.0);
    r := 11 + pulse;

    // Drop shadow under the bomb (tilted ellipse for perspective)
    draw_filled_ellipse(bx, by + r + 1, r * 1.05, 3.5, col(0, 0, 0, 0.50));

    // Pulsing aura — magenta near boom, lavender otherwise
    aura_col := mix4(col(0.722, 0.498, 1.0, 1), col(1.0, 0.55, 0.78, 1), danger);
    aura_pulse := 0.7 + sin(cast(float)frame_count / 6.0) * 0.30;
    for i: 0..3 {
        rr := r + 5.0 + cast(float)i * 5.5;
        a := (0.32 - cast(float)i * 0.075) * aura_pulse;
        if a > 0 draw_filled_circle(bx, by, rr, col(aura_col.x, aura_col.y, aura_col.z, a), 16);
    }

    // Body — darker rim, mid, highlight
    body_dark := col(0.235, 0.063, 0.392, 1);
    body_mid  := col(0.486, 0.302, 1.0, 1);
    body_hi   := col(0.737, 0.604, 1.0, 1);
    draw_filled_circle(bx, by, r,           body_dark, 18);
    draw_filled_circle(bx, by, r - 1.6,     body_mid,  18);
    draw_filled_circle(bx - r * 0.30, by - r * 0.32, r * 0.36, body_hi, 12);
    draw_filled_circle(bx - r * 0.40, by - r * 0.42, r * 0.18, col(1, 1, 1, 0.65), 8);

    // Equator highlight (subtle scanline)
    Simp.immediate_quad(bx - r * 0.85, by - 0.7, bx + r * 0.85, by + 0.7, col(0.88, 0.78, 1.0, 0.18));

    // Plasma arc skating across the bomb near detonation
    if danger > 0.55 {
        arc_phase := cast(float)frame_count / 2.0;
        if sin(arc_phase + cast(float)(b.x * 7 + b.y * 11)) > 0.0 {
            ax := bx + cos(arc_phase * 0.7) * r * 0.45;
            ay := by + sin(arc_phase * 0.9) * r * 0.45;
            bx2 := bx + cos(arc_phase * 0.7 + 2.0) * r * 0.45;
            by2 := by + sin(arc_phase * 0.9 + 2.4) * r * 0.45;
            draw_line(ax, ay, bx2, by2, col(1, 0.92, 1.0, 0.85), 1.4);
        }
    }

    // Fuse — wire + spark
    fuse_wob := sin(cast(float)frame_count / 5.0) * 3;
    fuse_top_y := by - r - 8 + fuse_wob;
    fuse_mid_x := bx + sin(cast(float)frame_count / 7.0) * 2.5;
    fuse_mid_y := by - r - 2 + fuse_wob * 0.5;
    draw_line(bx, by - r + 0.5, fuse_mid_x, fuse_mid_y, col(0.34, 0.18, 0.45, 1), 2.2);
    draw_line(fuse_mid_x, fuse_mid_y, fuse_mid_x + 1.5, fuse_top_y, col(0.34, 0.18, 0.45, 1), 2.2);

    spark_x := fuse_mid_x + 1.5;
    spark_y := fuse_top_y;
    spark_size := 3.0 + sin(cast(float)frame_count / 2.0) * 0.9 + danger * 1.4;
    spark_c    := mix4(col(1.0, 0.86, 0.32, 1), col(1.0, 0.42, 0.32, 1), danger);
    // outer glow
    draw_filled_circle(spark_x, spark_y, spark_size * 2.2, col(spark_c.x, spark_c.y, spark_c.z, 0.30), 10);
    draw_filled_circle(spark_x, spark_y, spark_size * 1.4, col(spark_c.x, spark_c.y, spark_c.z, 0.65), 8);
    draw_filled_circle(spark_x, spark_y, spark_size,        spark_c, 8);
    draw_filled_circle(spark_x, spark_y, spark_size * 0.5,  col(1, 1, 1, 1), 6);

    // Tiny dancing sparks
    for i: 0..3 {
        t := cast(float)(frame_count + i * 9 + cast(int)(bx * 0.3)) / 5.0;
        ox := cos(t + cast(float)i) * (4.5 + cast(float)i);
        oy := sin(t * 1.3 + cast(float)i) * 3.0 - 2.0;
        a  := 0.7 - cast(float)i * 0.15;
        if a > 0 {
            draw_filled_circle(spark_x + ox, spark_y + oy, 0.9 + danger * 0.4, col(1, 0.88, 0.50, a), 4);
        }
    }
}

draw_explosion :: (e: Explosion, ex: float, ey: float) {
    progress := 1 - cast(float)e.timer / cast(float)e.duration;
    inv      := 1.0 - progress;
    alpha    := min(1.0, cast(float)e.timer / cast(float)e.duration + 0.2);
    size     := cast(float)TILE - 4 + sin(progress * PI) * 10;

    // Wide halo (bloom-ish)
    halo_a := inv * 0.55;
    draw_filled_circle(ex, ey, size * 0.95, col(1.0, 0.65, 0.96, halo_a * 0.35), 22);
    draw_filled_circle(ex, ey, size * 0.72, col(0.95, 0.75, 1.0, halo_a * 0.55), 22);

    if e.origin {
        // Bright central flash for the first ~third of life
        flash := max(0.0, (0.45 - progress) / 0.45);
        if flash > 0 {
            draw_filled_circle(ex, ey, size * 0.62, col(1, 0.96, 1.0, flash * 0.95), 18);
            draw_filled_circle(ex, ey, size * 0.40, col(1, 1, 1,   flash), 18);
        }

        // Outward spokes — sharp, bright, with white core
        for i: 0..7 {
            ray_angle := (cast(float)i / 8.0) * TAU + progress * 0.6;
            ray_len := size * 0.85 + sin(progress * PI) * 14;
            rx := ex + cos(ray_angle) * ray_len;
            ry := ey + sin(ray_angle) * ray_len * 0.78;
            draw_line(ex, ey, rx, ry, col(1.0, 0.92, 0.88, alpha * 0.8 * inv), 3.2);
            draw_line(ex, ey, rx, ry, col(1, 1, 1, alpha * inv * 0.6), 1.1);
        }

        // Smaller secondary spokes at 45° offset
        for i: 0..7 {
            ray_angle := (cast(float)i / 8.0) * TAU + 0.39 - progress * 0.4;
            ray_len := size * 0.55 + sin(progress * PI) * 8;
            rx := ex + cos(ray_angle) * ray_len;
            ry := ey + sin(ray_angle) * ray_len * 0.78;
            draw_line(ex, ey, rx, ry, col(1.0, 0.72, 0.92, alpha * 0.45 * inv), 1.6);
        }

        // Core layers
        draw_filled_circle(ex, ey, size * 0.50, col(0.940, 0.785, 1.0,   alpha), 20);
        draw_filled_circle(ex, ey, size * 0.36, col(0.702, 0.533, 1.0,   alpha), 18);
        draw_filled_circle(ex, ey, size * 0.22, col(1.0, 0.96, 1.0,      alpha), 14);
        draw_filled_circle(ex, ey, size * 0.10, col(1, 1, 1, alpha), 8);

        // Hot embers ejecting outward
        ember_n :: 8;
        for k: 0..ember_n-1 {
            seed := cast(float)(k * 41 + e.x * 17 + e.y * 53);
            ang := seed + progress * 1.4;
            spd := 38.0 + (seed * 0.13 - floor(seed * 0.13)) * 30.0;
            dist := spd * progress;
            px := ex + cos(ang) * dist;
            py := ey + sin(ang) * dist * 0.7 - progress * 8.0;
            sz := (2.4 + (seed * 0.7 - floor(seed * 0.7)) * 1.6) * inv;
            if sz > 0.3 {
                draw_filled_circle(px, py, sz * 1.5, col(1.0, 0.72, 0.58, inv * 0.50), 5);
                draw_filled_circle(px, py, sz,       col(1.0, 0.92, 0.82, inv * 0.85), 5);
                draw_filled_circle(px, py, sz * 0.5, col(1, 1, 1, inv * 0.75), 4);
            }
        }
    } else {
        // Branch arms — swirly flames
        seg :: 14;
        for i: 0..seg-1 {
            t := cast(float)i / cast(float)seg;
            ang := t * TAU + progress * 1.4;
            r := size * 0.50 * (0.6 + sin(t * PI + progress * 3.0) * 0.30);
            fx_x := ex + cos(ang) * r;
            fx_y := ey + sin(ang) * r * 0.8;
            draw_filled_circle(fx_x, fx_y, 2.6 + inv * 1.6, col(1.0, 0.68, 0.96, alpha * inv * 0.85), 6);
        }
        // Core
        draw_filled_circle(ex, ey, size * 0.55, col(0.486, 0.302, 1.0, alpha),       18);
        draw_filled_circle(ex, ey, size * 0.40, col(0.736, 0.564, 1.0, alpha),       16);
        draw_filled_circle(ex, ey, size * 0.26, col(0.946, 0.790, 1.0, alpha),       14);
        draw_filled_circle(ex, ey, size * 0.12, col(1, 1, 1, alpha), 10);
    }
}

draw_death_fx :: (fx: DeathFx, cx: float, cy: float) {
    progress := 1.0 - cast(float)fx.timer / cast(float)fx.duration;
    inv      := 1.0 - progress;
    base_color := fx.color;

    if fx.kind == .DUST {
        // Subtle ground puff. Just a few small particles, no flash, no ring.
        for k: 0..2 {
            ang := cast(float)(k * 120 + 30) * PI / 180.0;
            dist := 5.0 + progress * 6.0;
            px := cx + cos(ang) * dist;
            py := cy + sin(ang) * dist * 0.5;
            sz := 1.6 * inv;
            if sz > 0.3 draw_filled_circle(px, py, sz, .{base_color.x, base_color.y, base_color.z, inv * 0.55}, 5);
        }
        return;
    }

    if fx.kind == .BOING {
        // Quick squashed shockwave on the ground. Implies impact.
        ring_r := progress * 22.0;
        a_ring := inv * 0.9;
        segs := 18;
        for j: 0..segs-1 {
            ang := (cast(float)j / cast(float)segs) * TAU;
            rx := cx + cos(ang) * ring_r;
            ry := cy + sin(ang) * ring_r * 0.45;
            draw_filled_circle(rx, ry, 1.6 + inv * 1.4, .{base_color.x, base_color.y, base_color.z, a_ring}, 6);
        }
        if progress < 0.35 {
            a := (0.35 - progress) / 0.35;
            draw_filled_circle(cx, cy, 8 * inv, .{1, 1, 1, a * 0.8}, 10);
        }
        return;
    }

    max_r       := ifx fx.kind == .BIG then 46.0 else 28.0;
    flash_r     := ifx fx.kind == .BIG then 26.0 else 16.0;
    particle_n  := ifx fx.kind == .BIG then 10 else 6;

    ring_r := progress * max_r;
    ring_thickness := 3.5 * inv + 1.0;
    ring_alpha := inv * 0.85;
    segs := 22;
    for j: 0..segs-1 {
        ang := (cast(float)j / cast(float)segs) * TAU;
        rx := cx + cos(ang) * ring_r;
        ry := cy + sin(ang) * ring_r * 0.55;
        draw_filled_circle(rx, ry, ring_thickness, .{base_color.x, base_color.y, base_color.z, ring_alpha}, 6);
    }

    if progress < 0.45 {
        a := (0.45 - progress) / 0.45;
        rad := flash_r * (1.0 - progress * 1.6);
        if rad > 0.5 {
            draw_filled_circle(cx, cy, rad, .{1, 1, 1, a * 0.85}, 14);
            draw_filled_circle(cx, cy, rad * 0.65, .{base_color.x, base_color.y, base_color.z, a}, 14);
        }
    }

    for k: 0..particle_n-1 {
        seed := cast(float)(k * 37 + cast(int)(fx.x * 53.0) + cast(int)(fx.y * 91.0));
        ang := seed + progress * 1.3;
        spd := 30.0 + (seed - cast(float)(cast(int)seed)) * 24.0;
        dist := spd * progress;
        px := cx + cos(ang) * dist;
        py := cy + sin(ang) * dist * 0.65 - progress * 12.0;
        sz := (2.4 + (seed - cast(float)(cast(int)seed)) * 1.6) * inv;
        if sz > 0.3 {
            draw_filled_circle(px, py, sz, .{base_color.x, base_color.y, base_color.z, inv * 0.85}, 5);
            draw_filled_circle(px, py, sz * 0.55, .{1, 1, 1, inv * 0.6}, 5);
        }
    }

    if fx.kind == .BIG {
        for i: 0..7 {
            ang := (cast(float)i / 8.0) * TAU;
            len := max_r * 0.85 * progress;
            x2 := cx + cos(ang) * len;
            y2 := cy + sin(ang) * len * 0.55;
            draw_line(cx, cy, x2, y2, .{1, 1, 1, inv * 0.45}, 1.5);
        }
    }
}

draw_powerup :: (p: Powerup, cx: float, cy: float) {
    if p.delay > 0 return;
    pulse := sin(cast(float)frame_count / 14.0) * 1.4;
    bob   := sin(cast(float)frame_count / 22.0) * 2.5;
    base_c := powerup_color(p.type);

    // Pedestal halo on the ground
    ped_y := cy + 18;
    for i: 0..2 {
        rr := 24.0 + cast(float)i * 7.0;
        a  := (0.32 - cast(float)i * 0.10);
        draw_filled_ellipse(cx, ped_y, rr, rr * 0.42, col(base_c.x, base_c.y, base_c.z, a), 18);
    }
    draw_filled_ellipse(cx, ped_y + 1, 17, 6, col(0, 0, 0, 0.40), 16);
    draw_filled_ellipse(cx, ped_y,     14, 5, col(base_c.x, base_c.y, base_c.z, 0.85), 16);
    draw_filled_ellipse(cx, ped_y - 1, 9,  3, col(1, 1, 1, 0.55), 12);

    iy := cy + bob - pulse;

    if p.type == {
        case .BOMB;
            // Halo
            for i: 0..2 {
                rr := 26.0 + cast(float)i * 7.0;
                a  := 0.32 - cast(float)i * 0.10;
                draw_filled_circle(cx, iy - 4, rr, col(0.702, 0.404, 1.0, a), 14);
            }
            // Four-pointed magic gem (vertical diamond) — clearly a collectible, not a bomb
            gem_d := col(0.130, 0.025, 0.310, 1);   // dark outline
            gem_m := col(0.486, 0.302, 1.0,   1);   // main facet
            gem_l := col(0.83,  0.66,  1.0,   1);   // bright facet
            gem_b := col(1.0,   0.92,  1.0,   1);   // tip glint

            top_p := iy - 22;
            bot_p := iy + 14;
            rgt_p := cx + 15;
            lft_p := cx - 15;
            mid_y := iy - 4;

            // Outer dark silhouette (slightly larger to act as a 1-pixel rim)
            draw_triangle(cx, top_p - 1, rgt_p + 1, mid_y, cx, mid_y,        gem_d);
            draw_triangle(cx, top_p - 1, lft_p - 1, mid_y, cx, mid_y,        gem_d);
            draw_triangle(cx, bot_p + 1, rgt_p + 1, mid_y, cx, mid_y,        gem_d);
            draw_triangle(cx, bot_p + 1, lft_p - 1, mid_y, cx, mid_y,        gem_d);
            // Gem body facets
            draw_triangle(cx, top_p, rgt_p, mid_y, cx, mid_y,                gem_m);
            draw_triangle(cx, top_p, lft_p, mid_y, cx, mid_y,                gem_l);  // brighter top-left facet
            draw_triangle(cx, bot_p, rgt_p, mid_y, cx, mid_y,                gem_d);  // shadowed bottom-right
            draw_triangle(cx, bot_p, lft_p, mid_y, cx, mid_y,                gem_m);
            // Center band highlight
            draw_filled_rect(cx - 13, mid_y - 0.8, 26, 1.6, col(1, 1, 1, 0.40));

            // Bold "+" emblem in the gem center — "upgrade" symbol
            plus_w := 13.0;
            plus_t := 3.5;
            draw_filled_rect(cx - plus_w/2 - 0.6, mid_y - plus_t/2 - 0.6, plus_w + 1.2, plus_t + 1.2, gem_d);
            draw_filled_rect(cx - plus_t/2 - 0.6, mid_y - plus_w/2 - 0.6, plus_t + 1.2, plus_w + 1.2, gem_d);
            draw_filled_rect(cx - plus_w/2, mid_y - plus_t/2, plus_w, plus_t, gem_b);
            draw_filled_rect(cx - plus_t/2, mid_y - plus_w/2, plus_t, plus_w, gem_b);
            draw_filled_rect(cx - plus_w/2 + 0.5, mid_y - plus_t/2 + 0.5, plus_w - 1, 1.0, col(1, 1, 1, 0.85));

            // Tip glints — sells the gem
            tip_pulse := 0.7 + 0.3 * sin(cast(float)frame_count / 7.0);
            draw_filled_circle(cx,            top_p + 1, 2.2 * tip_pulse, gem_b, 6);
            draw_filled_circle(cx,            bot_p - 1, 1.4 * tip_pulse, gem_b, 5);
            draw_filled_circle(rgt_p - 1,     mid_y,     1.4 * tip_pulse, gem_b, 5);
            draw_filled_circle(lft_p + 1,     mid_y,     1.4 * tip_pulse, gem_b, 5);

            // Orbiting sparkles signal "magical pickup"
            for i: 0..3 {
                ang := cast(float)frame_count / 22.0 + cast(float)i * (TAU / 4.0);
                ox  := cos(ang) * 26.0;
                oy  := sin(ang) * 8.0 - 2.0;
                sz  := 1.6 + sin(cast(float)frame_count / 9.0 + cast(float)i) * 0.4;
                draw_filled_circle(cx + ox, iy + oy, sz * 2.0, col(1.0, 0.85, 1.0, 0.30), 6);
                draw_filled_circle(cx + ox, iy + oy, sz,       col(1.0, 0.95, 1.0, 0.95), 5);
            }

        case .FIRE;
            // Halo
            for i: 0..2 {
                rr := 26.0 + cast(float)i * 6.0;
                a  := 0.30 - cast(float)i * 0.09;
                draw_filled_circle(cx, iy - 6, rr, col(1.0, 0.55, 0.20, a), 14);
            }
            flicker := sin(cast(float)frame_count / 4.0) * 1.6;
            // Outer flame (red), drop-shaped: ellipse base + sharp triangle tip
            draw_filled_ellipse(cx, iy + 2, 16, 16, col(0.78, 0.14, 0.10, 1), 18);
            draw_triangle(cx - 16, iy + 2, cx + 16, iy + 2, cx + flicker, iy - 26, col(0.78, 0.14, 0.10, 1));
            // Mid flame (orange)
            draw_filled_ellipse(cx, iy + 4, 11, 13, col(1.0, 0.45, 0.12, 1), 16);
            draw_triangle(cx - 11, iy + 4, cx + 11, iy + 4, cx + flicker * 0.7, iy - 18, col(1.0, 0.45, 0.12, 1));
            // Inner flame (yellow-orange)
            draw_filled_ellipse(cx, iy + 5, 7, 10, col(1.0, 0.72, 0.20, 1), 14);
            draw_triangle(cx - 7, iy + 5, cx + 7, iy + 5, cx + flicker * 0.4, iy - 11, col(1.0, 0.72, 0.20, 1));
            // Hot core
            draw_filled_ellipse(cx, iy + 6, 4, 6, col(1, 0.95, 0.55, 1), 12);
            draw_filled_circle(cx, iy + 7, 2.6, col(1, 1, 1, 0.9), 10);
            // A few rising sparks
            for i: 0..2 {
                spk_phase := cast(float)((frame_count + i * 17) % 40) / 40.0;
                sxp := cx + cos(cast(float)i * 2.0) * 6;
                syp := iy + 2 - spk_phase * 24;
                ap := 1.0 - spk_phase;
                draw_filled_circle(sxp, syp, 1.4 * ap, col(1, 0.85, 0.40, ap), 5);
            }

        case .KICK;
            // Halo
            for i: 0..2 {
                rr := 24.0 + cast(float)i * 6.0;
                a  := 0.30 - cast(float)i * 0.09;
                draw_filled_circle(cx, iy - 2, rr, col(0, 0.737, 0.827, a), 14);
            }
            // Big stylized boot in cyan
            boot_d := col(0.040, 0.180, 0.220, 1);
            boot_m := col(0,     0.737, 0.827, 1);
            boot_h := col(0.55,  0.93,  0.97,  1);
            // Sole — wide pill across the bottom
            draw_rounded_rect(cx - 19, iy + 2,  38, 10, 4, boot_d);
            draw_rounded_rect(cx - 18, iy + 3,  36, 7,  3, boot_m);
            // Shaft — tall pill on the right
            draw_rounded_rect(cx - 5,  iy - 18, 18, 22, 4, boot_d);
            draw_rounded_rect(cx - 4,  iy - 17, 16, 20, 3, boot_m);
            // Lace highlights
            for i: 0..3 {
                ly := iy - 14 + cast(float)i * 5;
                draw_filled_rect(cx - 1, ly, 12, 1.8, boot_h);
            }
            // Toe highlight
            draw_filled_rect(cx - 16, iy + 4, 6, 2.5, boot_h);
            // Impact stars — kicks bombs!
            for i: 0..3 {
                ang := (cast(float)i / 4.0) * TAU + PI/4 + cast(float)frame_count / 32.0;
                ox  := cos(ang) * 24;
                oy  := sin(ang) * 9 + 2;
                draw_filled_circle(cx + ox, iy + oy, 1.7, col(0.85, 1, 1, 0.7), 5);
            }

        case .PUNCH;
            // Halo
            for i: 0..2 {
                rr := 26.0 + cast(float)i * 6.0;
                a  := 0.30 - cast(float)i * 0.09;
                draw_filled_circle(cx, iy - 2, rr, col(1.0, 0.78, 0.20, a), 14);
            }
            // Boxing glove
            glove_d := col(0.40, 0.18, 0.02, 1);
            glove_m := col(1.0,  0.757, 0.027, 1);
            glove_h := col(1.0,  0.92,  0.60,  1);
            // Wrist cuff
            draw_rounded_rect(cx - 11, iy + 4, 22, 11, 3, glove_d);
            draw_rounded_rect(cx - 10, iy + 5, 20, 9,  2.5, col(0.78, 0.45, 0.10, 1));
            // White stripe across cuff
            draw_filled_rect(cx - 10, iy + 9, 20, 1.6, col(1, 1, 1, 0.85));
            // Main fist
            draw_filled_circle(cx,       iy - 4, 20, glove_d, 18);
            draw_filled_circle(cx,       iy - 4, 18, glove_m, 18);
            // Thumb knuckle
            draw_filled_circle(cx - 15,  iy - 1, 8,  glove_d, 12);
            draw_filled_circle(cx - 15,  iy - 1, 6.4, glove_m, 12);
            // Knuckle ridges
            for i: 0..3 {
                kx := cx - 6 + cast(float)i * 5;
                draw_filled_circle(kx, iy - 13, 2.3, glove_d, 6);
            }
            // Highlight
            draw_filled_circle(cx - 4, iy - 10, 7, glove_h, 12);
            draw_filled_circle(cx - 7, iy - 13, 2.8, col(1, 1, 1, 0.95), 6);
            // Impact zaps
            for i: 0..3 {
                ang := (cast(float)i / 4.0) * TAU + cast(float)frame_count / 26.0;
                ox  := cos(ang) * 26;
                oy  := sin(ang) * 10;
                draw_filled_circle(cx + ox, iy + oy, 1.9, col(1, 0.95, 0.45, 0.7), 5);
            }

        case .SKATE;
            // Halo
            for i: 0..2 {
                rr := 24.0 + cast(float)i * 6.0;
                a  := 0.30 - cast(float)i * 0.09;
                draw_filled_circle(cx, iy, rr, col(0.42, 0.81, 1.0, a), 14);
            }
            wheel_c := col(0.10, 0.13, 0.22, 1);
            boot_d  := col(0.14, 0.20, 0.34, 1);
            boot_m  := col(0.50, 0.70, 0.98, 1);
            boot_l  := col(0.85, 0.95, 1.0,  1);
            // Boot
            draw_rounded_rect(cx - 16, iy - 14, 26, 13, 4, boot_d);
            draw_rounded_rect(cx - 15, iy - 13, 24, 11, 3.5, boot_m);
            // Cuff
            draw_rounded_rect(cx + 4,  iy - 24, 14, 11, 3, boot_d);
            draw_rounded_rect(cx + 5,  iy - 23, 12, 9,  2.5, boot_m);
            // Lace highlight on cuff
            draw_filled_rect(cx + 6, iy - 20, 10, 1.6, boot_l);
            // Frame under boot
            draw_rounded_rect(cx - 17, iy - 1, 30, 4, 1.5, boot_d);
            // Wheels — three big visible
            for i: 0..2 {
                wx := cx - 12 + cast(float)i * 11;
                draw_filled_circle(wx, iy + 6, 5.5, boot_d, 12);
                draw_filled_circle(wx, iy + 6, 4,   wheel_c, 12);
                draw_filled_circle(wx, iy + 6, 1.6, col(0.50, 0.70, 0.98, 1), 8);
            }
            // Speed lines trailing behind
            for i: 0..2 {
                a := col(0.55, 0.92, 1.0, 0.75 - cast(float)i * 0.22);
                ox := -22.0 - cast(float)i * 8;
                draw_filled_rect(cx + ox, iy - 8 - cast(float)i * 2.5, 9, 1.8, a);
            }
    }
}

// Draw a short rail "section" between two world-space points: two parallel
// rails plus a tie at the midpoint. Pulled out so straight + curve emitters
// can share the same drawing code.
draw_rail_section :: (ax: float, az: float, bx: float, bz: float, draw_tie: bool) {
    rail_tie  := col(0.55, 0.40, 0.28, 1);   // wood ties (warm brown)
    rail_iron := col(0.78, 0.68, 0.45, 1);   // metallic rail (brass)
    dxx := bx - ax;
    dzz := bz - az;
    len := sqrt(dxx * dxx + dzz * dzz);
    if len < 0.01 return;
    nx := -dzz / len;
    nz :=  dxx / len;
    gauge :: 9.0;

    if draw_tie {
        mx := (ax + bx) * 0.5;
        mz := (az + bz) * 0.5;
        tw :: 20.0;
        th :: 6.0;
        tx0 := mx - nx * tw - dxx * th / len;
        tz0 := mz - nz * tw - dzz * th / len;
        tx1 := mx + nx * tw - dxx * th / len;
        tz1 := mz + nz * tw - dzz * th / len;
        tx2 := mx + nx * tw + dxx * th / len;
        tz2 := mz + nz * tw + dzz * th / len;
        tx3 := mx - nx * tw + dxx * th / len;
        tz3 := mz - nz * tw + dzz * th / len;
        draw_quad_3d(.{tx0, 0.4, tz0}, .{tx1, 0.4, tz1}, .{tx2, 0.4, tz2}, .{tx3, 0.4, tz3}, rail_tie);
    }

    for side: 0..1 {
        sgn: float = ifx side == 0 then -1.0 else 1.0;
        rxa := ax + nx * gauge * sgn;
        rza := az + nz * gauge * sgn;
        rxb := bx + nx * gauge * sgn;
        rzb := bz + nz * gauge * sgn;
        tt :: 1.6;
        qa_x := rxa - nx * tt;
        qa_z := rza - nz * tt;
        qb_x := rxa + nx * tt;
        qb_z := rza + nz * tt;
        qc_x := rxb + nx * tt;
        qc_z := rzb + nz * tt;
        qd_x := rxb - nx * tt;
        qd_z := rzb - nz * tt;
        draw_quad_3d(.{qa_x, 0.5, qa_z}, .{qb_x, 0.5, qb_z}, .{qc_x, 0.5, qc_z}, .{qd_x, 0.5, qd_z}, rail_iron);
    }
}

// Convert a tile-space (col, row) point to a world-space (x, z) tile center.
tile_to_world_xz :: (tx: float, ty: float) -> x: float, z: float {
    return tx * cast(float)TILE + cast(float)TILE * 0.5,
           ty * cast(float)TILE + cast(float)TILE * 0.5;
}

// Render the rails. Every segment between consecutive waypoints is drawn as a
// chain of tile-aligned straight sections (one per traversed tile). Corners
// stay as the same crisp 90° L-bends as the other vertices.
draw_mine_cart_rails :: () {
    n := MINE_CART_WAYPOINTS.count;
    if n < 2 return;

    for i: 0..n - 2 {
        wa := MINE_CART_WAYPOINTS[i];
        wb := MINE_CART_WAYPOINTS[i + 1];

        // Expand each segment x-first then y, matching the cart's path so the
        // visual rails sit exactly under the cart's tile-by-tile motion.
        dx := wb.x - wa.x;
        dy := wb.y - wa.y;
        sx := ifx dx == 0 then 0 else (ifx dx > 0 then 1 else -1);
        sy := ifx dy == 0 then 0 else (ifx dy > 0 then 1 else -1);
        steps_x := abs(dx);
        steps_y := abs(dy);

        cx := wa.x;
        cy := wa.y;
        for s: 0..steps_x - 1 {
            ax := cast(float) cx;
            ay := cast(float) cy;
            cx += sx;
            bxf := cast(float) cx;
            byf := cast(float) cy;
            axw, azw := tile_to_world_xz(ax, ay);
            bxw, bzw := tile_to_world_xz(bxf, byf);
            draw_rail_section(axw, azw, bxw, bzw, draw_tie = true);
        }
        for s: 0..steps_y - 1 {
            ax := cast(float) cx;
            ay := cast(float) cy;
            cy += sy;
            bxf := cast(float) cx;
            byf := cast(float) cy;
            axw, azw := tile_to_world_xz(ax, ay);
            bxw, bzw := tile_to_world_xz(bxf, byf);
            draw_rail_section(axw, azw, bxw, bzw, draw_tie = true);
        }
    }
}

// Per-row painter hook — installed in volcanic_mechanic.draw_row. Renders the
// cart on the row that matches its current tile so it stacks correctly with
// the player, enemies, and bombs in that row.
draw_mine_cart_row :: (r: int) {
    if cast(int)(mine_cart.ry + 0.5) != r return;
    cx_w := mine_cart.rx * cast(float)TILE + cast(float)TILE * 0.5;
    cz_w := mine_cart.ry * cast(float)TILE + cast(float)TILE * 0.5;
    sc, _ := project(.{cx_w, cast(float)TILE * 0.18, cz_w});
    draw_mine_cart(sc.x, sc.y);
}

draw_mine_cart :: (cx: float, cy: float) {
    // Drawn as a screen-space billboard at the projected tile center.
    // cx, cy are the screen-space center of the cart's tile (top of the rail).
    wagon_d := col(0.32, 0.18, 0.08, 1);
    wagon_m := col(0.58, 0.34, 0.16, 1);
    wagon_h := col(0.86, 0.62, 0.32, 1);
    iron    := col(0.20, 0.15, 0.10, 1);
    wheel_c := col(0.10, 0.07, 0.05, 1);
    rim     := col(0.78, 0.68, 0.45, 1);

    // Soft ground shadow.
    draw_filled_ellipse(cx, cy + 14, 26, 8, col(0, 0, 0, 0.45));

    // Cart body — chunky box. Slight bob if riding.
    bob: float = 0;
    if mine_cart.state == .RIDING {
        bob = sin(cast(float)frame_count / 3.5) * 1.4;
    }
    by := cy + bob;
    // Side wall (back)
    draw_rounded_rect(cx - 24, by - 18, 48, 22, 4, wagon_d);
    // Interior shading
    draw_rounded_rect(cx - 22, by - 16, 44, 18, 3, wagon_m);
    // Rim
    draw_filled_rect(cx - 24, by - 18, 48, 3.5, wagon_h);
    draw_filled_rect(cx - 24, by - 18, 3, 22, iron);
    draw_filled_rect(cx + 21, by - 18, 3, 22, iron);
    // Front lip
    draw_filled_rect(cx - 22, by + 0, 44, 3, iron);

    // Wheels — two big visible.
    for i: 0..1 {
        wx := cx - 14 + cast(float)i * 28;
        wy := by + 8;
        draw_filled_circle(wx, wy, 8, iron, 14);
        draw_filled_circle(wx, wy, 6.4, wheel_c, 14);
        draw_filled_circle(wx, wy, 2.4, rim, 10);
        // Spokes
        for j: 0..3 {
            ang := (cast(float)j / 4.0) * TAU + cast(float)frame_count * 0.18 * (ifx mine_cart.state == .RIDING then 1.0 else 0.0);
            sx := wx + cos(ang) * 5.0;
            sy := wy + sin(ang) * 5.0;
            draw_line(wx, wy, sx, sy, rim, 1.2);
        }
    }

    // Idle: subtle pulse hinting "you can ride this".
    if mine_cart.state == .IDLE {
        pulse := 0.55 + 0.35 * sin(cast(float)frame_count / 12.0);
        for i: 0..2 {
            rr := 22.0 + cast(float)i * 6.0;
            a := (0.32 - cast(float)i * 0.10) * pulse;
            if a > 0 draw_filled_circle(cx, by - 6, rr, col(1.0, 0.78, 0.36, a), 14);
        }
    }
}

draw_melting_powerup :: (m: MeltingPowerup, cx: float, cy: float) {
    pct := cast(float)m.timer / cast(float)POWERUP_MELT_DURATION;
    shrink := (1 - pct) * 24;
    h := 32 - shrink;
    base_c := powerup_color(m.type);
    dark_c  := col(base_c.x * 0.55, base_c.y * 0.55, base_c.z * 0.55, pct);
    mid_c   := col(base_c.x,        base_c.y,        base_c.z,        pct);
    light_c := col(min(1.0, base_c.x + 0.25), min(1.0, base_c.y + 0.25), min(1.0, base_c.z + 0.25), (1 - pct) * 0.55);

    // Shock ring expanding outward
    ring_r := (1 - pct) * 22.0;
    draw_filled_ellipse(cx, cy + 4, ring_r, ring_r * 0.4, col(base_c.x, base_c.y, base_c.z, (1 - pct) * 0.5), 16);
    // Shrinking diamond
    draw_filled_rect(cx - h/2,     cy - h/2,     h,     h,     dark_c);
    draw_filled_rect(cx - h/2 + 3, cy - h/2 + 3, h - 6, h - 6, mid_c);
    draw_filled_circle(cx, cy, (1 - pct) * 10, light_c, 10);
}

drop_enemy_powerups :: (e: *Enemy) {
    // Collect the powerup types this enemy was holding.
    types: [..] PType;
    types.allocator = temp;
    extra_bombs := e.max_bombs - START_MAX_BOMBS;
    extra_fire  := e.fire_range - ENEMY_FIRE_RANGE;
    extra_skate := e.skate_count;
    for i: 0..extra_bombs - 1 array_add(*types, PType.BOMB);
    for i: 0..extra_fire  - 1 array_add(*types, PType.FIRE);
    for i: 0..extra_skate - 1 array_add(*types, PType.SKATE);
    if types.count == 0 return;

    // Build a fresh list of valid empty tiles (no walls, no bricks, no bombs, no existing powerups, no entities).
    candidates: [..] BFSNode;
    candidates.allocator = temp;
    for r: 1..ROWS - 2 {
        for c: 1..COLS - 2 {
            if grid[r][c] != .EMPTY continue;
            occupied := false;
            for bombs        if !it.punching && it.x == c && it.y == r { occupied = true; break; }
            if occupied continue;
            for powerups     if it.x == c && it.y == r { occupied = true; break; }
            if occupied continue;
            for explosions_list if it.x == c && it.y == r { occupied = true; break; }
            if occupied continue;
            if player.x == c && player.y == r continue;
            for * en: enemies if en.alive && en.x == c && en.y == r { occupied = true; break; }
            if occupied continue;
            n: BFSNode;
            n.x = c; n.y = r;
            array_add(*candidates, n);
        }
    }

    // Place each type at a random remaining tile.
    for t: types {
        if candidates.count == 0 break;
        idx := cast(int)(random_get() % cast(u64) candidates.count);
        pos := candidates[idx];
        array_unordered_remove_by_index(*candidates, idx);

        pu: Powerup;
        pu.x = pos.x;
        pu.y = pos.y;
        pu.type = t;
        pu.delay = POWERUP_SPAWN_DELAY;
        array_add(*powerups, pu);

        // A subtle pop where it lands so the player can spot it
        spawn_fx(cast(float)pu.x, cast(float)pu.y, powerup_color(t), .SMALL);
    }
}

// ─── Mine cart helpers ──────────────────────────────────────────────────────
expand_route :: (waypoints: [] BFSNode) -> [..] BFSNode {
    // Expand axis-aligned segments into per-tile steps. Non-axis-aligned segments
    // (the final dismount "ramp") fall back to a step on the dominant axis then
    // the other axis — keeps the path tile-by-tile so collisions stay readable.
    out: [..] BFSNode;
    if waypoints.count == 0 return out;
    array_add(*out, waypoints[0]);
    for i: 1..waypoints.count - 1 {
        from := waypoints[i - 1];
        to   := waypoints[i];
        dx := to.x - from.x;
        dy := to.y - from.y;
        steps_x := abs(dx);
        steps_y := abs(dy);
        sx := ifx dx == 0 then 0 else (ifx dx > 0 then 1 else -1);
        sy := ifx dy == 0 then 0 else (ifx dy > 0 then 1 else -1);

        cx := from.x;
        cy := from.y;
        // Walk x first, then y. Diagonal segments become an L on the path.
        for sx_i: 0..steps_x - 1 {
            cx += sx;
            n: BFSNode; n.x = cx; n.y = cy;
            array_add(*out, n);
        }
        for sy_i: 0..steps_y - 1 {
            cy += sy;
            n: BFSNode; n.x = cx; n.y = cy;
            array_add(*out, n);
        }
    }
    return out;
}

// Clear only the BRICK tiles that sit on the cart's tracks. Indestructible
// walls (border ring + every even/even tile) are left in place — they define
// the level's lattice and shouldn't be perforated by the rails. The route in
// MINE_CART_WAYPOINTS must therefore be designed to never cross a wall tile
// (use odd rows for horizontal segments and odd cols for vertical ones).
clear_route_tiles :: (path: [] BFSNode) {
    for path {
        if it.x <= 0 || it.x >= COLS - 1 continue;
        if it.y <= 0 || it.y >= ROWS - 1 continue;
        if grid[it.y][it.x] == .BRICK grid[it.y][it.x] = .EMPTY;
    }
}

setup_mine_cart :: () {
    // load_level has already zeroed mine_cart + mine_cart_path before this
    // mechanic's setup runs, so we start from a clean slate.
    mine_cart.dir_sign = 1;
    mine_cart.rider_enemy_id = -1;

    mine_cart_path = expand_route(MINE_CART_WAYPOINTS);

    clear_route_tiles(mine_cart_path);

    mine_cart.x = mine_cart_path[0].x;
    mine_cart.y = mine_cart_path[0].y;
    mine_cart.rx = cast(float) mine_cart.x;
    mine_cart.ry = cast(float) mine_cart.y;
    // Initial facing — toward the next tile on the route.
    if mine_cart_path.count > 1 {
        mine_cart.dx = mine_cart_path[1].x - mine_cart_path[0].x;
        mine_cart.dy = mine_cart_path[1].y - mine_cart_path[0].y;
    }
}

// Apply cart-entry effects to a tile: vaporise any brick, kill any non-rider
// entity (enemies and the player). Powerups and bombs are deliberately
// untouched — they pass under the cart.
cart_hit_tile :: (tx: int, ty: int) {
    if tx < 0 || tx >= COLS || ty < 0 || ty >= ROWS return;

    if grid[ty][tx] == .BRICK {
        grid[ty][tx] = .BRICK_MELTING;
        mb: MeltingBrick;
        mb.x = tx; mb.y = ty; mb.timer = MELT_DURATION;
        array_add(*melting_bricks, mb);
        spawn_death_fx(cast(float)tx, cast(float)ty, current_theme.melt_top, false);
        add_shake(SHAKE_PER_BOOM * 0.4);
    }

    // Squash non-rider enemies. The rider's tile is already the cart's *new*
    // tile (set by update_mine_cart before this call), so they're not at the
    // old tile anymore — but be defensive and skip by id anyway.
    for * en, ei: enemies {
        if !en.alive continue;
        if en.hopping continue;
        if mine_cart.rider == .ENEMY && ei == mine_cart.rider_enemy_id continue;
        if en.x == tx && en.y == ty {
            en.alive = false;
            spawn_death_fx(en.rx, en.ry, en.glow, true);
            drop_enemy_powerups(en);
            add_shake(SHAKE_PER_CHAIN * 0.6);
            play_sfx(*sound_hit, 0.55);
        }
    }

    // Squash the player only when an enemy is riding (the player can't run
    // themselves over). Game-over flow mirrors an explosion hit.
    if mine_cart.rider == .ENEMY && !player.hopping && game_over_delay == 0 {
        if player.x == tx && player.y == ty {
            spawn_death_fx(player.rx, player.ry, col(0.353, 0.604, 0.965, 1), true);
            game_over_delay = 50;
            hit_flash_timer = 22;
            player_won = false;
            add_shake(SHAKE_PER_CHAIN * 0.7);
            play_sfx(*sound_hit, 0.55);
        }
    }
}

// Pick the direction to travel based on which endpoint the cart is parked at.
// At path[0] → forward (+1). At path[last] → backward (-1). Anywhere in
// between (rider died mid-route) → keep the existing sign.
choose_cart_direction :: () {
    if mine_cart.route_index == 0 {
        mine_cart.dir_sign = 1;
    } else if mine_cart.route_index == mine_cart_path.count - 1 {
        mine_cart.dir_sign = -1;
    }
}

// Mount the cart if any entity is standing on its current parked tile. Runs
// every frame so both the player and roaming enemies can hop on. The cart
// stays where it last stopped — the next rider sends it the opposite way.
try_mount_cart :: () {
    if mine_cart.state != .IDLE return;

    // Player has priority — if both player and an enemy share the tile, the
    // player gets the ride.
    if !player.hopping && player.x == mine_cart.x && player.y == mine_cart.y {
        mine_cart.state = .RIDING;
        mine_cart.rider = .PLAYER;
        mine_cart.rider_enemy_id = -1;
        mine_cart.move_timer = CART_MOVE_DELAY;
        player.locked_by_mechanic = true;
        choose_cart_direction();
        spawn_fx(cast(float)mine_cart.x, cast(float)mine_cart.y, col(1.0, 0.85, 0.45, 1), .BOING);
        return;
    }

    for * en, ei: enemies {
        if !en.alive continue;
        if en.hopping continue;
        if en.x == mine_cart.x && en.y == mine_cart.y {
            mine_cart.state = .RIDING;
            mine_cart.rider = .ENEMY;
            mine_cart.rider_enemy_id = ei;
            mine_cart.move_timer = CART_MOVE_DELAY;
            choose_cart_direction();
            spawn_fx(cast(float)mine_cart.x, cast(float)mine_cart.y, col(1.0, 0.85, 0.45, 1), .BOING);
            return;
        }
    }
}

start_player_hop :: (dx: int, dy: int, src_x: float, src_y: float) {
    player.hopping = true;
    player.hop_dx = dx;
    player.hop_dy = dy;
    player.hop_from_x   = src_x;
    player.hop_from_y   = src_y;
    player.hop_target_x = src_x + cast(float) dx;
    player.hop_target_y = src_y + cast(float) dy;
    player.hop_t = 0;
    if dy < 0       player.dir = .UP;
    else if dy > 0  player.dir = .DOWN;
    else if dx < 0  player.dir = .LEFT;
    else if dx > 0  player.dir = .RIGHT;
    spawn_fx(src_x, src_y, col(1.0, 0.85, 0.45, 1), .BOING);
}

start_enemy_hop :: (en: *Enemy, dx: int, dy: int, src_x: float, src_y: float) {
    en.hopping = true;
    en.hop_dx = dx;
    en.hop_dy = dy;
    en.hop_from_x   = src_x;
    en.hop_from_y   = src_y;
    en.hop_target_x = src_x + cast(float) dx;
    en.hop_target_y = src_y + cast(float) dy;
    en.hop_t = 0;
    if dy < 0       en.dir = .UP;
    else if dy > 0  en.dir = .DOWN;
    else if dx < 0  en.dir = .LEFT;
    else if dx > 0  en.dir = .RIGHT;
    spawn_fx(src_x, src_y, en.glow, .BOING);
}

// Drop the rider, leave the cart parked at its current tile + facing. The
// next rider mounts here and sends it in the opposite direction.
park_mine_cart :: () {
    mine_cart.state = .IDLE;
    mine_cart.rider = .NONE;
    mine_cart.rider_enemy_id = -1;
    mine_cart.move_timer = 0;
}

eject_rider_from_cart :: () {
    // Cart finished its route. Launch the rider one tile in the cart's last
    // direction. The hop bounces over walls/bricks/bombs and lands on the
    // first free tile. Then the cart respawns at the start.
    dx := mine_cart.dx;
    dy := mine_cart.dy;
    if dx == 0 && dy == 0 dy = -1;   // Defensive fallback.
    src_x := cast(float) mine_cart.x;
    src_y := cast(float) mine_cart.y;

    if mine_cart.rider == .PLAYER {
        player.locked_by_mechanic = false;
        start_player_hop(dx, dy, src_x, src_y);
    } else if mine_cart.rider == .ENEMY {
        en := *enemies[mine_cart.rider_enemy_id];
        if en.alive start_enemy_hop(en, dx, dy, src_x, src_y);
    }

    park_mine_cart();
}

// Shared chain-hop update for one airborne entity. Mirrors the punched-bomb
// arc-hop in update(): each tile-hop checks the landing tile and bounces one
// more tile in the same direction if it's a wall/brick/bomb.
advance_hop :: (hopping: *bool, dx_ref: int, dy_ref: int,
                from_x: *float, from_y: *float,
                target_x: *float, target_y: *float,
                t_ref: *float, x_out: *int, y_out: *int,
                rx_out: *float, ry_out: *float) {
    if !<<hopping return;
    <<t_ref += 1.0 / cast(float) PLAYER_HOP_FRAMES;
    while <<hopping && <<t_ref >= 1.0 {
        // Wrap the destination tile back into the grid (out-of-bounds hops
        // wrap, same as punched bombs).
        tx := cast(int)(floor(<<target_x) + cast(float)(COLS * 100)) % COLS;
        ty := cast(int)(floor(<<target_y) + cast(float)(ROWS * 100)) % ROWS;

        spawn_fx(cast(float)tx, cast(float)ty, col(0.706, 0.671, 0.612, 1), .BOING);

        tile := grid[ty][tx];
        blocked := false;
        if tile == .WALL || tile == .BRICK || tile == .BRICK_MELTING {
            blocked = true;
        } else {
            for bombs if !it.punching && it.x == tx && it.y == ty { blocked = true; break; }
        }

        if blocked {
            <<from_x   = cast(float) tx;
            <<from_y   = cast(float) ty;
            <<target_x = cast(float) tx + cast(float) dx_ref;
            <<target_y = cast(float) ty + cast(float) dy_ref;
            <<t_ref   -= 1.0;
        } else {
            <<x_out  = tx;
            <<y_out  = ty;
            <<rx_out = cast(float) tx;
            <<ry_out = cast(float) ty;
            <<hopping = false;
            <<t_ref   = 0;
            spawn_fx(cast(float)tx, cast(float)ty, col(0.706, 0.671, 0.612, 1), .DUST);
            spawn_fx(cast(float)tx, cast(float)ty, col(1.0, 0.85, 0.45, 1), .BOING);
        }
    }
}

update_player_hop :: () {
    if !player.hopping return;
    advance_hop(*player.hopping, player.hop_dx, player.hop_dy,
                *player.hop_from_x, *player.hop_from_y,
                *player.hop_target_x, *player.hop_target_y,
                *player.hop_t, *player.x, *player.y,
                *player.rx, *player.ry);
}

update_enemy_hops :: () {
    for * en: enemies {
        if !en.alive continue;
        if !en.hopping continue;
        advance_hop(*en.hopping, en.hop_dx, en.hop_dy,
                    *en.hop_from_x, *en.hop_from_y,
                    *en.hop_target_x, *en.hop_target_y,
                    *en.hop_t, *en.x, *en.y,
                    *en.rx, *en.ry);
    }
}

update_mine_cart :: () {
    // Smooth render position toward the current tile center.
    mine_cart.rx += (cast(float)mine_cart.x - mine_cart.rx) * LERP_SPEED;
    mine_cart.ry += (cast(float)mine_cart.y - mine_cart.ry) * LERP_SPEED;

    // Anyone standing on the start tile mounts up.
    try_mount_cart();

    if mine_cart.state != .RIDING return;

    // Snap the rider's grid + render position to the cart.
    if mine_cart.rider == .PLAYER {
        player.x  = mine_cart.x;
        player.y  = mine_cart.y;
        player.rx = mine_cart.rx;
        player.ry = mine_cart.ry;
    } else if mine_cart.rider == .ENEMY {
        en := *enemies[mine_cart.rider_enemy_id];
        if en.alive {
            en.x  = mine_cart.x;
            en.y  = mine_cart.y;
            en.rx = mine_cart.rx;
            en.ry = mine_cart.ry;
        } else {
            // Rider died (e.g., bomb caught up). Cart parks where it is; the
            // next rider can mount and continue in the same direction.
            park_mine_cart();
            return;
        }
    }

    mine_cart.move_timer -= 1;
    if mine_cart.move_timer > 0 return;
    mine_cart.move_timer = CART_MOVE_DELAY;

    next_idx := mine_cart.route_index + mine_cart.dir_sign;
    if next_idx < 0 || next_idx >= mine_cart_path.count {
        eject_rider_from_cart();
        return;
    }

    next := mine_cart_path[next_idx];
    mine_cart.dx = next.x - mine_cart.x;
    mine_cart.dy = next.y - mine_cart.y;
    mine_cart.x  = next.x;
    mine_cart.y  = next.y;
    mine_cart.route_index = next_idx;

    cart_hit_tile(mine_cart.x, mine_cart.y);
}

// Visual-only helper — used by the render pass to lift the player onto the
// cart sprite. Movement/bomb gating uses `player.locked_by_mechanic` instead.
player_is_riding :: () -> bool {
    return mine_cart.state == .RIDING && mine_cart.rider == .PLAYER;
}

player_is_busy :: () -> bool {
    // True when the player can't act (mid hop arc, stunned, or owned by a
    // level mechanic — cart ride, fish swallow, etc).
    return player.locked_by_mechanic || player.hopping || player.stun_timer > 0;
}

// ─── Level 3 (SNOW) implementation ──────────────────────────────────────────

setup_snow :: () {
    array_reset(*snowballs);
    snowball_spawn_cooldown = 360;   // 6 s grace before the first snowball
    snowflakes_initialized = false;
}

// Idle/forming snowballs occupy their tile — blocks movement so the player
// is forced to engage with them. Rolling snowballs don't block; they kill.
snow_tile_blocked :: (x: int, y: int) -> bool {
    for sb: snowballs {
        if sb.rolling continue;
        if sb.x == x && sb.y == y return true;
    }
    return false;
}

// Kill any non-airborne entity standing on (x, y). Used by snowballs when
// rolling onto a tile.
snowball_squish_at :: (x: int, y: int) {
    if !player.hopping && game_over_delay == 0 && player.x == x && player.y == y {
        spawn_death_fx(player.rx, player.ry, col(0.353, 0.604, 0.965, 1), true);
        game_over_delay = 50;
        hit_flash_timer = 22;
        player_won = false;
        add_shake(SHAKE_PER_CHAIN);
        play_sfx(*sound_hit, 0.55);
    }
    for * en, ei: enemies {
        if !en.alive continue;
        if en.hopping continue;
        if en.x == x && en.y == y {
            en.alive = false;
            spawn_death_fx(en.rx, en.ry, en.glow, true);
            drop_enemy_powerups(en);
            add_shake(SHAKE_PER_CHAIN * 0.6);
            play_sfx(*sound_hit, 0.55);
        }
    }
}

spawn_snowball :: () {
    // Pick a random interior EMPTY tile that's not on top of player/enemy/bomb
    // and not too close to the player. A few attempts is enough on a sparse grid.
    for attempts: 0..30 {
        c := 1 + cast(int)(random_get() % cast(u64)(COLS - 2));
        r := 1 + cast(int)(random_get() % cast(u64)(ROWS - 2));
        if grid[r][c] != .EMPTY continue;
        if abs(c - player.x) + abs(r - player.y) < 3 continue;
        clash := false;
        for sb: snowballs if sb.x == c && sb.y == r { clash = true; break; }
        if clash continue;
        for b: bombs if !b.punching && b.x == c && b.y == r { clash = true; break; }
        if clash continue;
        sb: Snowball;
        sb.x = c; sb.y = r;
        sb.rx = cast(float) c; sb.ry = cast(float) r;
        sb.forming = true;
        sb.form_timer = SNOWBALL_FORM_TICKS;
        array_add(*snowballs, sb);
        return;
    }
}

tick_snow :: () {
    // Try to spawn new snowballs over time.
    if snowballs.count < SNOWBALL_MAX {
        snowball_spawn_cooldown -= 1;
        if snowball_spawn_cooldown <= 0 {
            spawn_snowball();
            range := SNOWBALL_SPAWN_MAX - SNOWBALL_SPAWN_MIN;
            snowball_spawn_cooldown = SNOWBALL_SPAWN_MIN + cast(int)(random_get() % cast(u64) range);
        }
    }

    // Tick / advance each snowball.
    i := snowballs.count - 1;
    while i >= 0 {
        sb := *snowballs[i];
        // Smooth render position toward grid tile.
        sb.rx += (cast(float)sb.x - sb.rx) * LERP_SPEED;
        sb.ry += (cast(float)sb.y - sb.ry) * LERP_SPEED;

        if sb.forming {
            sb.form_timer -= 1;
            if sb.form_timer <= 0 sb.forming = false;
        } else if sb.rolling {
            sb.roll_timer -= 1;
            if sb.roll_timer <= 0 {
                sb.roll_timer = SNOWBALL_ROLL_DELAY;
                nx := sb.x + sb.roll_dx;
                ny := sb.y + sb.roll_dy;
                // Roll off the playable interior → snowball falls off.
                if nx < 1 || nx >= COLS - 1 || ny < 1 || ny >= ROWS - 1 {
                    spawn_fx(cast(float)sb.x, cast(float)sb.y, col(0.95, 0.98, 1.0, 1), .BIG);
                    array_unordered_remove_by_index(*snowballs, i);
                    i -= 1;
                    continue;
                }
                sb.x = nx;
                sb.y = ny;
                snowball_squish_at(nx, ny);
                spawn_fx(cast(float)nx, cast(float)ny, col(0.95, 0.98, 1.0, 1), .DUST);
            }
        }
        i -= 1;
    }
}

on_explosion_snow :: (bx: int, by: int, range: int) {
    // Push any fully-formed snowball that's orthogonally adjacent to the bomb
    // center. Pushes away from the bomb. Forming snowballs are immune.
    for * sb: snowballs {
        if sb.forming continue;
        if sb.rolling continue;
        dx := sb.x - bx;
        dy := sb.y - by;
        push_dx := 0;
        push_dy := 0;
        if dx == 0 && abs(dy) == 1 {
            push_dy = ifx dy > 0 then 1 else -1;
        } else if dy == 0 && abs(dx) == 1 {
            push_dx = ifx dx > 0 then 1 else -1;
        } else {
            continue;
        }
        sb.rolling = true;
        sb.roll_dx = push_dx;
        sb.roll_dy = push_dy;
        sb.roll_timer = SNOWBALL_ROLL_DELAY;
    }
}

draw_snowballs_row :: (r: int) {
    for sb: snowballs {
        if cast(int)(sb.ry + 0.5) != r continue;
        cx_w := sb.rx * cast(float)TILE + cast(float)TILE * 0.5;
        cz_w := sb.ry * cast(float)TILE + cast(float)TILE * 0.5;
        form_frac: float = 1.0;
        if sb.forming form_frac = 1.0 - cast(float)sb.form_timer / cast(float)SNOWBALL_FORM_TICKS;
        radius := 8.0 + form_frac * 16.0;
        sc, _ := project(.{cx_w, radius * 0.5, cz_w});
        sh, _ := project(.{cx_w, 0.4, cz_w});
        draw_filled_ellipse(sh.x, sh.y, radius * 1.4, radius * 0.5, col(0, 0, 0, 0.45));
        // Body — concentric circles, brightest center.
        draw_filled_circle(sc.x, sc.y, radius * 1.15, col(0.65, 0.78, 0.92, 0.85), 18);
        draw_filled_circle(sc.x, sc.y, radius,        col(0.92, 0.96, 1.00, 1),    18);
        draw_filled_circle(sc.x - radius * 0.35, sc.y - radius * 0.45, radius * 0.4, col(1, 1, 1, 0.95), 10);
        if sb.forming {
            pulse := 0.4 + 0.4 * sin(cast(float)frame_count / 6.0);
            draw_filled_circle(sc.x, sc.y, radius * 2.2 * pulse, col(0.78, 0.92, 1.00, 0.15), 14);
        }
        if sb.rolling {
            // Trailing snow puffs
            for i: 0..2 {
                t := cast(float)i / 3.0;
                ox := -cast(float)sb.roll_dx * 10 * (1 + t * 1.5);
                oy := -cast(float)sb.roll_dy * 6 * (1 + t * 1.5);
                draw_filled_circle(sc.x + ox, sc.y + oy, 3.5 * (1 - t), col(1, 1, 1, 0.55 * (1 - t)), 8);
            }
        }
    }
}

draw_snow_overlay :: () {
    vw := cast(float)WINDOW_W;
    vh := cast(float)WINDOW_H;
    if !snowflakes_initialized {
        for i: 0..SNOWFLAKE_COUNT - 1 {
            f := *snowflakes[i];
            f.sx = random_get_zero_to_one() * vw;
            f.sy = random_get_zero_to_one() * vh;
            f.vy = 0.6 + random_get_zero_to_one() * 1.8;
            f.size = 1.0 + random_get_zero_to_one() * 2.2;
            f.sway = random_get_zero_to_one() * TAU;
        }
        snowflakes_initialized = true;
    }
    for * f: snowflakes {
        f.sy += f.vy;
        f.sx += sin(f.sway + cast(float)frame_count / 18.0) * 0.45;
        if f.sy > vh + 5 { f.sy = -6; f.sx = random_get_zero_to_one() * vw; }
        if f.sx > vw + 6 f.sx = -6;
        if f.sx < -6     f.sx = vw + 6;
        draw_filled_circle(f.sx, f.sy, f.size, col(1, 1, 1, 0.78), 6);
    }
}

// ─── Level 4 (PIRATE) implementation ────────────────────────────────────────

dir_offset :: (d: Dir) -> dx: int, dy: int {
    if d == .UP    return 0, -1;
    if d == .DOWN  return 0, 1;
    if d == .LEFT  return -1, 0;
    return 1, 0;
}

add_cannon :: (cx: int, cy: int, d: Dir) {
    if cx < 1 || cx >= COLS - 1 || cy < 1 || cy >= ROWS - 1 return;
    // Clear the cannon's tile, the back tile (where the bomb-trigger goes),
    // and the first tile in the firing direction so the fuse path is clean.
    grid[cy][cx] = .EMPTY;
    dx, dy := dir_offset(d);
    bx := cx - dx;
    by := cy - dy;
    if bx >= 1 && bx < COLS - 1 && by >= 1 && by < ROWS - 1 && grid[by][bx] == .BRICK {
        grid[by][bx] = .EMPTY;
    }
    fx := cx + dx;
    fy := cy + dy;
    if fx >= 1 && fx < COLS - 1 && fy >= 1 && fy < ROWS - 1 && grid[fy][fx] == .BRICK {
        grid[fy][fx] = .EMPTY;
    }
    cn: Cannon;
    cn.x = cx; cn.y = cy; cn.dir = d;
    array_add(*cannons, cn);
}

setup_pirate :: () {
    array_reset(*cannons);
    // Fixed positions — two on each side, near the top and bottom thirds.
    // Left-side cannons face RIGHT; right-side cannons face LEFT.
    left_col  := CANNON_EDGE_OFFSET;
    right_col := COLS - 1 - CANNON_EDGE_OFFSET;
    top_row    := 3;
    bottom_row := ROWS - 4;
    add_cannon(left_col,  top_row,    .RIGHT);
    add_cannon(left_col,  bottom_row, .RIGHT);
    add_cannon(right_col, top_row,    .LEFT);
    add_cannon(right_col, bottom_row, .LEFT);
}

tick_pirate :: () {
    for * cn: cannons {
        if cn.fired continue;
        if cn.fuse_timer <= 0 continue;
        cn.fuse_timer -= 1;
        if cn.fuse_timer <= 0 {
            // Fire — spawn explosion tiles along the firing direction.
            cn.fired = true;
            dx, dy := dir_offset(cn.dir);
            for k: 1..CANNON_RANGE {
                nx := cn.x + dx * k;
                ny := cn.y + dy * k;
                if nx < 0 || nx >= COLS || ny < 0 || ny >= ROWS break;
                if grid[ny][nx] == .WALL || grid[ny][nx] == .BRICK_MELTING || grid[ny][nx] == .WATER break;
                if grid[ny][nx] == .BRICK {
                    grid[ny][nx] = .BRICK_MELTING;
                    mb: MeltingBrick;
                    mb.x = nx; mb.y = ny; mb.timer = MELT_DURATION;
                    array_add(*melting_bricks, mb);
                    spawn_death_fx(cast(float)nx, cast(float)ny, current_theme.melt_top, false);
                    ne: Explosion;
                    ne.x = nx; ne.y = ny; ne.timer = EXPLOSION_DURATION; ne.duration = EXPLOSION_DURATION;
                    array_add(*explosions_list, ne);
                    break;
                }
                ne: Explosion;
                ne.x = nx; ne.y = ny; ne.timer = EXPLOSION_DURATION; ne.duration = EXPLOSION_DURATION;
                array_add(*explosions_list, ne);
            }
            add_shake(SHAKE_PER_CHAIN);
            recent_boom = 1.0;
        }
    }
}

on_explosion_pirate :: (bx: int, by: int, range: int) {
    // Light any cannon whose back tile lies in this bomb's blast pattern.
    for * cn: cannons {
        if cn.fired continue;
        if cn.fuse_timer > 0 continue;
        dx, dy := dir_offset(cn.dir);
        back_x := cn.x - dx;
        back_y := cn.y - dy;
        if back_x < 0 || back_x >= COLS || back_y < 0 || back_y >= ROWS continue;
        if bomb_hits_tile(bx, by, range, back_x, back_y) {
            cn.fuse_timer = CANNON_FUSE_TICKS;
            spawn_fx(cast(float) back_x, cast(float) back_y, col(1, 0.7, 0.25, 1), .SMALL);
        }
    }
}

draw_cannon_billboard :: (cx: float, cy: float, cn: Cannon) {
    body_d := col(0.16, 0.16, 0.18, 1);
    body_m := col(0.34, 0.34, 0.40, 1);
    body_h := col(0.62, 0.62, 0.72, 1);
    // Drop shadow
    draw_filled_ellipse(cx, cy + 9, 24, 7, col(0, 0, 0, 0.50));
    // Body box
    draw_rounded_rect(cx - 14, cy - 7, 28, 16, 4, body_d);
    draw_rounded_rect(cx - 13, cy - 6, 26, 14, 3, body_m);
    draw_filled_rect(cx - 12, cy - 5, 24, 2, body_h);
    // Barrel oriented by direction
    if cn.dir == {
        case .UP;
            draw_filled_rect(cx - 5, cy - 24, 10, 20, body_d);
            draw_filled_rect(cx - 4, cy - 23, 8, 18, body_m);
            draw_filled_circle(cx, cy - 24, 5, body_d, 12);
            draw_filled_circle(cx, cy - 24, 3, col(0.06, 0.05, 0.05, 1), 10);
        case .DOWN;
            draw_filled_rect(cx - 5, cy + 4, 10, 20, body_d);
            draw_filled_rect(cx - 4, cy + 5, 8, 18, body_m);
            draw_filled_circle(cx, cy + 24, 5, body_d, 12);
            draw_filled_circle(cx, cy + 24, 3, col(0.06, 0.05, 0.05, 1), 10);
        case .LEFT;
            draw_filled_rect(cx - 24, cy - 5, 20, 10, body_d);
            draw_filled_rect(cx - 23, cy - 4, 18, 8, body_m);
            draw_filled_circle(cx - 24, cy, 5, body_d, 12);
            draw_filled_circle(cx - 24, cy, 3, col(0.06, 0.05, 0.05, 1), 10);
        case .RIGHT;
            draw_filled_rect(cx + 4, cy - 5, 20, 10, body_d);
            draw_filled_rect(cx + 5, cy - 4, 18, 8, body_m);
            draw_filled_circle(cx + 24, cy, 5, body_d, 12);
            draw_filled_circle(cx + 24, cy, 3, col(0.06, 0.05, 0.05, 1), 10);
    }
    // Fuse spark at the back tile when lit
    if cn.fuse_timer > 0 && !cn.fired {
        flicker := 0.6 + 0.4 * sin(cast(float)frame_count / 2.5);
        sparkc := col(1.0, 0.78, 0.30, 1);
        bx, by: float;
        if cn.dir == {
            case .UP;    bx = cx; by = cy + 12;
            case .DOWN;  bx = cx; by = cy - 12;
            case .LEFT;  bx = cx + 16; by = cy;
            case .RIGHT; bx = cx - 16; by = cy;
        }
        draw_filled_circle(bx, by, 5 * flicker, col(1.0, 0.55, 0.20, 0.55), 10);
        draw_filled_circle(bx, by, 3 * flicker, sparkc, 8);
        draw_filled_circle(bx, by, 1.5 * flicker, col(1, 1, 1, 1), 6);
    }
}

draw_cannons_row :: (r: int) {
    for cn: cannons {
        if cn.y != r continue;
        if cn.fired continue;  // burned through after firing — gone visually
        cx_w := cast(float)(cn.x * TILE) + cast(float)TILE * 0.5;
        cz_w := cast(float)(cn.y * TILE) + cast(float)TILE * 0.5;
        sc, _ := project(.{cx_w, cast(float)TILE * 0.25, cz_w});
        draw_cannon_billboard(sc.x, sc.y, cn);
    }
}

// ─── Level 5 (BEACH) implementation ─────────────────────────────────────────

setup_beach :: () {
    array_reset(*fishes);
    fish_teleport = .{};

    // Pre-cleared spawn corridors must remain walkable, so only consider tiles
    // that are currently EMPTY. Convert a sparse handful into WATER (blocked)
    // and place a few FISH on remaining EMPTY tiles.
    water_count := 0;
    for r: 1..ROWS - 2 {
        for c: 1..COLS - 2 {
            if grid[r][c] != .EMPTY continue;
            // Keep all spawn corners walkable for the player + enemies.
            if abs(c - 1) + abs(r - 1) < 3 continue;
            if abs(c - (COLS - 2)) + abs(r - (ROWS - 2)) < 3 continue;
            if abs(c - (COLS - 2)) + abs(r - 1) < 3 continue;
            if abs(c - 1) + abs(r - (ROWS - 2)) < 3 continue;
            if water_count >= BEACH_WATER_MAX continue;
            if random_get_zero_to_one() < BEACH_WATER_DENSITY {
                grid[r][c] = .WATER;
                water_count += 1;
            }
        }
    }

    // Place fish on EMPTY tiles, away from each other.
    for attempts: 0..80 {
        if fishes.count >= BEACH_FISH_COUNT break;
        c := 1 + cast(int)(random_get() % cast(u64)(COLS - 2));
        r := 1 + cast(int)(random_get() % cast(u64)(ROWS - 2));
        if grid[r][c] != .EMPTY continue;
        if abs(c - 1) + abs(r - 1) < 4 continue;
        clash := false;
        for f: fishes if abs(f.x - c) + abs(f.y - r) < 4 { clash = true; break; }
        if clash continue;
        f: Fish;
        f.x = c; f.y = r;
        f.bob_phase = random_get_zero_to_one() * TAU;
        array_add(*fishes, f);
    }
}

tick_beach :: () {
    for * f: fishes f.bob_phase += 0.04;

    if !fish_teleport.active return;
    fish_teleport.phase += 1;
    // Mid-teleport: swap player to dst at the exact phase boundary.
    if fish_teleport.phase == FISH_SWALLOW_TICKS {
        player.x = fish_teleport.dst_x;
        player.y = fish_teleport.dst_y;
        player.rx = cast(float) fish_teleport.dst_x;
        player.ry = cast(float) fish_teleport.dst_y;
        spawn_fx(cast(float) fish_teleport.dst_x, cast(float) fish_teleport.dst_y, col(0.4, 0.78, 1.0, 1), .BIG);
    }
    if fish_teleport.phase >= FISH_TOTAL_TICKS {
        fish_teleport.active = false;
        player.locked_by_mechanic = false;
    }
}

on_player_moved_beach :: () {
    if fish_teleport.active return;
    for f, fi: fishes {
        if player.x == f.x && player.y == f.y {
            if fishes.count < 2 return;
            // Random different fish.
            idx := fi;
            for attempt: 0..30 {
                idx = cast(int)(random_get() % cast(u64) fishes.count);
                if idx != fi break;
            }
            if idx == fi return;
            fish_teleport.active = true;
            fish_teleport.phase = 0;
            fish_teleport.src_x = f.x;
            fish_teleport.src_y = f.y;
            fish_teleport.dst_x = fishes[idx].x;
            fish_teleport.dst_y = fishes[idx].y;
            player.locked_by_mechanic = true;
            spawn_fx(cast(float)f.x, cast(float)f.y, col(0.4, 0.78, 1.0, 1), .BIG);
            return;
        }
    }
}

draw_fish_billboard :: (cx: float, cy: float) {
    // Water pool under the fish
    draw_filled_ellipse(cx, cy + 7, 22, 8, col(0.12, 0.36, 0.62, 0.85));
    draw_filled_ellipse(cx, cy + 6, 20, 7, col(0.32, 0.58, 0.85, 0.70));
    // Fish body — koi-orange
    body_d := col(0.78, 0.28, 0.10, 1);
    body_m := col(1.00, 0.55, 0.18, 1);
    body_h := col(1.00, 0.88, 0.55, 1);
    // Tail
    draw_triangle(cx - 17, cy - 6, cx - 17, cy + 6, cx - 8, cy, body_d);
    draw_triangle(cx - 15, cy - 5, cx - 15, cy + 5, cx - 8, cy, body_m);
    // Body
    draw_filled_ellipse(cx, cy, 13, 7, body_d);
    draw_filled_ellipse(cx, cy, 11, 5.5, body_m);
    draw_filled_ellipse(cx, cy + 1.5, 10, 3, body_h);
    // Fin
    draw_triangle(cx, cy - 4, cx + 4, cy - 9, cx + 6, cy - 3, body_d);
    // Eye
    draw_filled_circle(cx + 5, cy - 1, 1.8, col(1, 1, 1, 1), 6);
    draw_filled_circle(cx + 5.5, cy - 1, 1.0, col(0.1, 0.1, 0.15, 1), 5);
}

draw_fishes_row :: (r: int) {
    for f: fishes {
        if f.y != r continue;
        cx_w := cast(float)(f.x * TILE) + cast(float)TILE * 0.5;
        cz_w := cast(float)(f.y * TILE) + cast(float)TILE * 0.5;
        sc, _ := project(.{cx_w, cast(float)TILE * 0.12, cz_w});
        bob := sin(f.bob_phase) * 2.0;
        draw_fish_billboard(sc.x, sc.y + bob);
    }
}

// Water tile rendering — drawn from the floor pass when grid[r][c] == .WATER.
// Beach-only currently; if another level uses WATER tiles it would benefit
// from a per-theme draw_water helper.
draw_water_3d :: (c: int, r: int) {
    x0 := cast(float)(c * TILE);
    x1 := x0 + cast(float)TILE;
    z0 := cast(float)(r * TILE);
    z1 := z0 + cast(float)TILE;
    deep  := col(0.08, 0.22, 0.42, 1);
    base  := col(0.16, 0.40, 0.62, 1);
    light := col(0.40, 0.70, 0.92, 1);
    foam  := col(0.92, 0.96, 1.00, 1);

    // Water plane sits slightly below the boardwalk.
    h: float = -10.0;
    draw_quad_3d(.{x0, h, z0}, .{x1, h, z0}, .{x1, h, z1}, .{x0, h, z1}, deep);
    inset := 4.0;
    draw_quad_3d(.{x0 + inset, h + 0.1, z0 + inset},
                 .{x1 - inset, h + 0.1, z0 + inset},
                 .{x1 - inset, h + 0.1, z1 - inset},
                 .{x0 + inset, h + 0.1, z1 - inset}, base);

    // Animated highlights
    t := cast(float)frame_count / 24.0;
    seed := cast(float)(c * 13 + r * 31);
    cx_w := (x0 + x1) * 0.5;
    cz_w := (z0 + z1) * 0.5;
    for i: 0..2 {
        phase := t + seed + cast(float)i * 1.7;
        ox := sin(phase) * (cast(float)TILE * 0.18);
        oz := cos(phase * 1.3) * (cast(float)TILE * 0.18);
        sc, _ := project(.{cx_w + ox, h + 0.4, cz_w + oz});
        s := screen_scale_at(.{cx_w + ox, h + 0.4, cz_w + oz});
        rr := (5.0 + sin(phase * 2.0) * 2.0) * s;
        if rr > 0.5 draw_filled_circle(sc.x, sc.y, rr, col(light.x, light.y, light.z, 0.55), 14);
    }

    // Foam ring around the hole — implies the wooden boardwalk's edge.
    e :: 3.0;
    draw_quad_3d(.{x0, 0.05, z0}, .{x1, 0.05, z0}, .{x1, 0.05, z0 + e}, .{x0, 0.05, z0 + e}, foam);
    draw_quad_3d(.{x0, 0.05, z1 - e}, .{x1, 0.05, z1 - e}, .{x1, 0.05, z1}, .{x0, 0.05, z1}, foam);
    draw_quad_3d(.{x0, 0.05, z0}, .{x0 + e, 0.05, z0}, .{x0 + e, 0.05, z1}, .{x0, 0.05, z1}, foam);
    draw_quad_3d(.{x1 - e, 0.05, z0}, .{x1, 0.05, z0}, .{x1, 0.05, z1}, .{x1 - e, 0.05, z1}, foam);
}

draw_beach_overlay :: () {
    // Player teleport flash. The world-space player render is suppressed
    // while teleporting; show a column of bubbles at the active endpoint.
    if !fish_teleport.active return;
    swallow_end := FISH_SWALLOW_TICKS;
    travel_end  := FISH_SWALLOW_TICKS + FISH_TRAVEL_TICKS;
    if fish_teleport.phase < swallow_end {
        // Sinking at src
        tx := cast(float) fish_teleport.src_x;
        ty := cast(float) fish_teleport.src_y;
        cx_w := tx * cast(float)TILE + cast(float)TILE * 0.5;
        cz_w := ty * cast(float)TILE + cast(float)TILE * 0.5;
        sc, _ := project(.{cx_w, cast(float)TILE * 0.15, cz_w});
        for i: 0..5 {
            t := cast(float)((fish_teleport.phase + i * 3) % 20) / 20.0;
            r := (1.0 - t) * 3.0 + 1.0;
            draw_filled_circle(sc.x + sin(cast(float)i) * 6, sc.y - t * 14, r, col(0.85, 0.95, 1.0, 0.75 * (1 - t)), 6);
        }
    } else if fish_teleport.phase < travel_end {
        // brief curtain in the middle of travel
        a := 0.18;
        draw_filled_rect(0, 0, cast(float)WINDOW_W, cast(float)WINDOW_H, col(0.35, 0.65, 0.95, a));
    } else {
        // Bursting up at dst
        tx := cast(float) fish_teleport.dst_x;
        ty := cast(float) fish_teleport.dst_y;
        cx_w := tx * cast(float)TILE + cast(float)TILE * 0.5;
        cz_w := ty * cast(float)TILE + cast(float)TILE * 0.5;
        sc, _ := project(.{cx_w, cast(float)TILE * 0.15, cz_w});
        for i: 0..5 {
            t := cast(float)((fish_teleport.phase + i * 4) % 18) / 18.0;
            r := t * 3.0 + 1.0;
            draw_filled_circle(sc.x + sin(cast(float)i + 1) * 7, sc.y - (1 - t) * 18, r, col(0.92, 0.97, 1.0, 0.78 * (1 - t)), 6);
        }
    }
}

place_bomb :: () {
    if player.stun_timer > 0 return;
    if player.locked_by_mechanic return;
    if player.hopping return;
    active_player_bombs := 0;
    for bombs if it.owner == 0 active_player_bombs += 1;
    if active_player_bombs >= player.max_bombs return;
    for bombs if it.x == player.x && it.y == player.y return;
    b: Bomb;
    b.x = player.x; b.y = player.y;
    b.timer = BOMB_TIMER;
    b.range = player.fire_range;
    b.owner = 0;
    array_add(*bombs, b);
    spawn_death_fx(cast(float)b.x, cast(float)b.y, col(0.702, 0.533, 1.0, 1), false);
}

explode :: (b: Bomb) {
    // Fire the level-mechanic hook so per-level entities (snowballs, cannon
    // fuses, etc) can react to a bomb going off.
    if current_mechanic.on_explosion current_mechanic.on_explosion(b.x, b.y, b.range);

    // Only the originating bomb plays the explosion sound — chain links share
    // the origin's blast. Quiet volume so 10 simultaneous bombs don't deafen.
    if !b.chain play_sfx(*sound_explosion, 0.05);

    e: Explosion;
    e.x = b.x; e.y = b.y;
    e.timer = EXPLOSION_DURATION;
    e.duration = EXPLOSION_DURATION;
    e.origin = true;
    array_add(*explosions_list, e);

    add_shake(ifx b.chain then SHAKE_PER_CHAIN else SHAKE_PER_BOOM);
    recent_boom = 1.0;

    for dir_idx: 0..3 {
        dx := DIRS[dir_idx * 2];
        dy := DIRS[dir_idx * 2 + 1];
        for i: 1..b.range {
            nx := b.x + dx * i;
            ny := b.y + dy * i;
            if nx < 0 || nx >= COLS || ny < 0 || ny >= ROWS break;
            if grid[ny][nx] == .WALL || grid[ny][nx] == .BRICK_MELTING || grid[ny][nx] == .WATER break;

            hit_bomb := false;
            for * bombs {
                if !it.punching && it.x == nx && it.y == ny {
                    it.timer = 1;
                    it.chain = true;
                    hit_bomb = true;
                    break;
                }
            }
            if hit_bomb break;

            hit_powerup_idx := -1;
            for powerups {
                if it.x == nx && it.y == ny && it.delay <= 0 {
                    hit_powerup_idx = it_index;
                    break;
                }
            }
            if hit_powerup_idx >= 0 {
                pu := powerups[hit_powerup_idx];
                mp: MeltingPowerup;
                mp.x = pu.x; mp.y = pu.y; mp.type = pu.type; mp.timer = POWERUP_MELT_DURATION;
                array_add(*melting_powerups, mp);
                spawn_death_fx(cast(float)pu.x, cast(float)pu.y, powerup_color(pu.type), false);
                array_unordered_remove_by_index(*powerups, hit_powerup_idx);
                ne: Explosion;
                ne.x = nx; ne.y = ny; ne.timer = EXPLOSION_DURATION; ne.duration = EXPLOSION_DURATION;
                array_add(*explosions_list, ne);
                break;
            }

            if grid[ny][nx] == .BRICK {
                grid[ny][nx] = .BRICK_MELTING;
                mb: MeltingBrick;
                mb.x = nx; mb.y = ny; mb.timer = MELT_DURATION;
                array_add(*melting_bricks, mb);
                spawn_death_fx(cast(float)nx, cast(float)ny, col(0.702, 0.533, 1.0, 1), false);

                if !b.chain && random_get_zero_to_one() < POWERUP_DROP_RATE {
                    r := random_get_zero_to_one();
                    ptype: PType;
                    if r < 0.30 ptype = .BOMB;
                    else if r < 0.60 ptype = .FIRE;
                    else if r < 0.80 {
                        if skate_spawned < SKATE_MAX {
                            ptype = .SKATE;
                            skate_spawned += 1;
                        } else {
                            ptype = ifx random_get_zero_to_one() < 0.5 then PType.BOMB else PType.FIRE;
                        }
                    } else if r < 0.90 {
                        if kick_spawned < KICK_MAX {
                            ptype = .KICK;
                            kick_spawned += 1;
                        } else {
                            ptype = ifx random_get_zero_to_one() < 0.5 then PType.BOMB else PType.FIRE;
                        }
                    } else {
                        if punch_spawned < PUNCH_MAX {
                            ptype = .PUNCH;
                            punch_spawned += 1;
                        } else {
                            ptype = ifx random_get_zero_to_one() < 0.5 then PType.BOMB else PType.FIRE;
                        }
                    }
                    pu: Powerup;
                    pu.x = nx; pu.y = ny; pu.type = ptype; pu.delay = POWERUP_SPAWN_DELAY;
                    array_add(*powerups, pu);
                }

                ne: Explosion;
                ne.x = nx; ne.y = ny; ne.timer = EXPLOSION_DURATION; ne.duration = EXPLOSION_DURATION;
                array_add(*explosions_list, ne);
                break;
            }

            ne: Explosion;
            ne.x = nx; ne.y = ny; ne.timer = EXPLOSION_DURATION; ne.duration = EXPLOSION_DURATION;
            array_add(*explosions_list, ne);
        }
    }
}

is_in_blast :: (x: int, y: int, extra: [] Bomb = .[]) -> bool {
    for explosions_list if it.x == x && it.y == y return true;

    check :: (bx: int, by: int, range: int, x: int, y: int) -> bool #expand {
        if bx == x && by == y return true;
        for dir_idx: 0..3 {
            dx := DIRS[dir_idx * 2];
            dy := DIRS[dir_idx * 2 + 1];
            for i: 1..range {
                nx := bx + dx * i;
                ny := by + dy * i;
                if nx < 0 || nx >= COLS || ny < 0 || ny >= ROWS break;
                if grid[ny][nx] == .WALL || grid[ny][nx] == .BRICK_MELTING || grid[ny][nx] == .WATER break;
                if nx == x && ny == y return true;
                if grid[ny][nx] == .BRICK break;
            }
        }
        return false;
    }

    for bombs { if !it.punching && check(it.x, it.y, it.range, x, y) return true; }
    for extra if check(it.x, it.y, it.range, x, y) return true;
    return false;
}

can_walk_safe :: (x: int, y: int) -> bool {
    if x < 0 || x >= COLS || y < 0 || y >= ROWS return false;
    if grid[y][x] != .EMPTY return false;
    for bombs if !it.punching && it.x == x && it.y == y return false;
    if current_mechanic.tile_blocked && current_mechanic.tile_blocked(x, y) return false;
    return true;
}

bfs_path :: (sx: int, sy: int, tx: int, ty: int, avoid_blast: bool = false) -> [..] BFSNode {
    path: [..] BFSNode;
    path.allocator = temp;
    if sx == tx && sy == ty return path;

    visited: [ROWS][COLS] bool;
    parent: [ROWS][COLS] BFSNode;

    queue: [..] BFSNode;
    queue.allocator = temp;

    start: BFSNode;
    start.x = sx; start.y = sy;
    array_add(*queue, start);
    visited[sy][sx] = true;

    found := false;
    head := 0;
    while head < queue.count {
        cur := queue[head];
        head += 1;
        if cur.x == tx && cur.y == ty {
            found = true;
            break;
        }
        for dir_idx: 0..3 {
            nx := cur.x + DIRS[dir_idx * 2];
            ny := cur.y + DIRS[dir_idx * 2 + 1];
            if nx < 0 || nx >= COLS || ny < 0 || ny >= ROWS continue;
            if visited[ny][nx] continue;
            is_target := (nx == tx && ny == ty);
            if !is_target && !can_walk_safe(nx, ny) continue;
            if !is_target && avoid_blast && is_in_blast(nx, ny) continue;
            visited[ny][nx] = true;
            parent[ny][nx] = cur;
            n: BFSNode;
            n.x = nx; n.y = ny;
            array_add(*queue, n);
        }
    }

    if !found return path;

    cx := tx;
    cy := ty;
    while !(cx == sx && cy == sy) {
        n: BFSNode;
        n.x = cx; n.y = cy;
        array_add(*path, n);
        p := parent[cy][cx];
        cx = p.x; cy = p.y;
    }
    for i: 0..path.count/2 - 1 {
        j := path.count - 1 - i;
        tmp := path[i];
        path[i] = path[j];
        path[j] = tmp;
    }
    return path;
}

find_safe_cell :: (sx: int, sy: int, extra: [] Bomb = .[]) -> bool, int, int {
    visited: [ROWS][COLS] bool;
    queue: [..] BFSNode;
    queue.allocator = temp;

    start: BFSNode;
    start.x = sx; start.y = sy;
    array_add(*queue, start);
    visited[sy][sx] = true;

    head := 0;
    while head < queue.count {
        cur := queue[head];
        head += 1;
        if !is_in_blast(cur.x, cur.y, extra) {
            return true, cur.x, cur.y;
        }
        for dir_idx: 0..3 {
            nx := cur.x + DIRS[dir_idx * 2];
            ny := cur.y + DIRS[dir_idx * 2 + 1];
            if nx < 0 || nx >= COLS || ny < 0 || ny >= ROWS continue;
            if visited[ny][nx] continue;
            if !can_walk_safe(nx, ny) continue;
            visited[ny][nx] = true;
            n: BFSNode;
            n.x = nx; n.y = ny;
            array_add(*queue, n);
        }
    }
    return false, -1, -1;
}

// Would a bomb dropped at (bx,by) with this `range` blow up the tile (x,y)?
// Mirrors the propagation rules in explode(): a wall, a melting brick, or a
// regular brick stops the line (the brick itself is hit, but anything past it
// is safe).
bomb_hits_tile :: (bx: int, by: int, range: int, x: int, y: int) -> bool {
    if bx == x && by == y return true;
    for dir_idx: 0..3 {
        dx := DIRS[dir_idx * 2];
        dy := DIRS[dir_idx * 2 + 1];
        for i: 1..range {
            nx := bx + dx * i;
            ny := by + dy * i;
            if nx < 0 || nx >= COLS || ny < 0 || ny >= ROWS break;
            if grid[ny][nx] == .WALL || grid[ny][nx] == .BRICK_MELTING || grid[ny][nx] == .WATER break;
            if nx == x && ny == y return true;
            if grid[ny][nx] == .BRICK break;
        }
    }
    return false;
}

// Count how many bricks would be cracked by a bomb dropped at (bx, by) with
// this fire range. Walls/melting-bricks stop the line; the brick itself is hit
// then the line stops.
count_bricks_hit :: (bx: int, by: int, range: int) -> int {
    n := 0;
    for dir_idx: 0..3 {
        dx := DIRS[dir_idx * 2];
        dy := DIRS[dir_idx * 2 + 1];
        for i: 1..range {
            nx := bx + dx * i;
            ny := by + dy * i;
            if nx < 0 || nx >= COLS || ny < 0 || ny >= ROWS break;
            if grid[ny][nx] == .WALL || grid[ny][nx] == .BRICK_MELTING || grid[ny][nx] == .WATER break;
            if grid[ny][nx] == .BRICK { n += 1; break; }
        }
    }
    return n;
}

// "How many ticks would it cost me to reach every other tile?" — a weighted
// flood-fill where stepping onto an empty tile costs 1 and stepping onto a
// BRICK costs BRICK_COST (bomb fuse + step). Walls, melting bricks, and bombs
// are impassable. Used by the AI to score targets and to find which brick to
// bust when the strict-safe path is blocked.
DijkstraField :: struct {
    dist:   [ROWS][COLS] int;
    parent: [ROWS][COLS] BFSNode;
}

dijkstra_through_bricks :: (sx: int, sy: int) -> DijkstraField {
    f: DijkstraField;
    for r: 0..ROWS-1 {
        for c: 0..COLS-1 {
            f.dist[r][c] = DIJK_INF;
            p: BFSNode; p.x = -1; p.y = -1;
            f.parent[r][c] = p;
        }
    }
    if sx < 0 || sx >= COLS || sy < 0 || sy >= ROWS return f;
    f.dist[sy][sx] = 0;

    visited: [ROWS][COLS] bool;
    while true {
        // Pick the unvisited tile with the smallest tentative cost. Grid is
        // tiny (≤195 cells), so a linear scan beats any heap setup.
        bestd := DIJK_INF;
        bx := -1; by := -1;
        for r: 0..ROWS-1 {
            for c: 0..COLS-1 {
                if !visited[r][c] && f.dist[r][c] < bestd {
                    bestd = f.dist[r][c];
                    bx = c; by = r;
                }
            }
        }
        if bx < 0 break;
        visited[by][bx] = true;

        for dir_idx: 0..3 {
            nx := bx + DIRS[dir_idx * 2];
            ny := by + DIRS[dir_idx * 2 + 1];
            if nx < 0 || nx >= COLS || ny < 0 || ny >= ROWS continue;
            if grid[ny][nx] == .WALL || grid[ny][nx] == .BRICK_MELTING || grid[ny][nx] == .WATER continue;
            blocked := false;
            for bombs if !it.punching && it.x == nx && it.y == ny { blocked = true; break; }
            if blocked continue;

            step_cost := ifx grid[ny][nx] == .BRICK then BRICK_COST else 1;
            nd := bestd + step_cost;
            if nd < f.dist[ny][nx] {
                f.dist[ny][nx] = nd;
                p: BFSNode;
                p.x = bx; p.y = by;
                f.parent[ny][nx] = p;
            }
        }
    }
    return f;
}

// Walks the parent chain from (tx, ty) back toward (sx, sy) and returns the
// first BRICK tile on that path — the one we'd need to bust to make progress.
// Returns (-1, -1) if the path is brick-free or the target is unreachable.
first_brick_on_path :: (f: DijkstraField, sx: int, sy: int, tx: int, ty: int) -> bx: int, by: int {
    if tx == sx && ty == sy return -1, -1;
    if f.dist[ty][tx] >= DIJK_INF return -1, -1;

    path: [..] BFSNode;
    path.allocator = temp;
    cx := tx;
    cy := ty;
    safety := 0;
    while !(cx == sx && cy == sy) {
        n: BFSNode;
        n.x = cx; n.y = cy;
        array_add(*path, n);
        p := f.parent[cy][cx];
        if p.x < 0 break;
        cx = p.x; cy = p.y;
        safety += 1;
        if safety > ROWS * COLS break;
    }
    // path[0] is the target; path[last] is the first step from start. Walk
    // from start-side back so we hit the *first* brick we'd encounter.
    for i: 0..path.count-1 {
        idx := path.count - 1 - i;
        n := path[idx];
        if grid[n.y][n.x] == .BRICK return n.x, n.y;
    }
    return -1, -1;
}

// Pick the best empty tile to walk to for brick-farming. Score favours tiles
// that hit multiple bricks at once, and penalises distance. Skips tiles
// already in a blast (we'd just die there).
find_best_farm_tile :: (e: *Enemy, f: DijkstraField) -> int, int {
    best_x := -1; best_y := -1;
    best_score := -1;
    for r: 1..ROWS-2 {
        for c: 1..COLS-2 {
            if grid[r][c] != .EMPTY continue;
            if f.dist[r][c] >= DIJK_INF continue;
            if is_in_blast(c, r) continue;
            adj := count_bricks_hit(c, r, e.fire_range);
            if adj == 0 continue;
            score := adj * 100 - f.dist[r][c];
            if score > best_score {
                best_score = score;
                best_x = c; best_y = r;
            }
        }
    }
    return best_x, best_y;
}

// Returns the most appealing target for this enemy using actual path costs:
// the planning Dijkstra (which can traverse bricks at BRICK_COST) gives a
// realistic "how long would it take me to get there?" metric. Powerups get a
// POWERUP_INTEREST head start; rival enemies get a small penalty (we'd rather
// chase the player); KICK/PUNCH powerups are slightly less appealing because
// enemies can't actually use those.
find_best_target :: (e: *Enemy, f: DijkstraField) -> kind: TargetKind, x: int, y: int {
    best_kind  := TargetKind.NONE;
    best_x     := -1;
    best_y     := -1;
    best_score := DIJK_INF;

    if f.dist[player.y][player.x] < DIJK_INF {
        s := f.dist[player.y][player.x];
        if s < best_score {
            best_score = s;
            best_x = player.x; best_y = player.y;
            best_kind = .ENTITY;
        }
    }

    for * other: enemies {
        if other == e || !other.alive continue;
        d := f.dist[other.y][other.x];
        if d >= DIJK_INF continue;
        s := d + ENEMY_AVOIDANCE;
        if s < best_score {
            best_score = s;
            best_x = other.x; best_y = other.y;
            best_kind = .ENTITY;
        }
    }

    for powerups {
        if it.delay > 0 continue;
        d := f.dist[it.y][it.x];
        if d >= DIJK_INF continue;
        s := d - POWERUP_INTEREST;
        if it.type == .KICK || it.type == .PUNCH s += USELESS_PUP_PENALTY;
        if s < best_score {
            best_score = s;
            best_x = it.x; best_y = it.y;
            best_kind = .POWERUP;
        }
    }

    return best_kind, best_x, best_y;
}

set_enemy_dir :: (e: *Enemy, dx: int, dy: int) {
    if dy < 0 e.dir = .UP;
    else if dy > 0 e.dir = .DOWN;
    else if dx < 0 e.dir = .LEFT;
    else if dx > 0 e.dir = .RIGHT;
}

enemy_step_to :: (e: *Enemy, nx: int, ny: int) {
    e.last_x = e.x;
    e.last_y = e.y;
    set_enemy_dir(e, nx - e.x, ny - e.y);
    e.x = nx;
    e.y = ny;
    e.idle_streak = 0;
    spawn_fx(cast(float)e.last_x, cast(float)e.last_y, col(0.706, 0.671, 0.612, 1), .DUST);
}

enemy_do_flee_step :: (e: *Enemy) {
    // Keep the committed flee destination if it still looks safe.
    if e.has_flee && e.flee_x >= 0 && e.flee_y >= 0
        && can_walk_safe(e.flee_x, e.flee_y)
        && !is_in_blast(e.flee_x, e.flee_y) {
        path := bfs_path(e.x, e.y, e.flee_x, e.flee_y);
        if path.count > 0 {
            enemy_step_to(e, path[0].x, path[0].y);
            return;
        }
    }

    // Find a fresh safe haven.
    found, sx, sy := find_safe_cell(e.x, e.y);
    if found {
        e.flee_x = sx;
        e.flee_y = sy;
        e.has_flee = true;
        if sx == e.x && sy == e.y return;  // already safe; just stay
        path := bfs_path(e.x, e.y, sx, sy);
        if path.count > 0 {
            enemy_step_to(e, path[0].x, path[0].y);
            return;
        }
    }

    // Trapped — step toward whatever adjacent tile is least dangerous.
    // Prefer: walkable AND not in blast, then walkable.
    best_dir_idx := -1;
    best_score := -1;
    for dir_idx: 0..3 {
        nx := e.x + DIRS[dir_idx * 2];
        ny := e.y + DIRS[dir_idx * 2 + 1];
        if !can_walk_safe(nx, ny) continue;
        score := 0;
        if !is_in_blast(nx, ny) score += 100;
        if !(nx == e.last_x && ny == e.last_y) score += 5;
        // tiebreak: farther from nearest bomb is better
        nearest := 999;
        for bombs {
            d := abs(nx - it.x) + abs(ny - it.y);
            if d < nearest nearest = d;
        }
        score += nearest;
        if score > best_score {
            best_score = score;
            best_dir_idx = dir_idx;
        }
    }
    if best_dir_idx >= 0 {
        dx := DIRS[best_dir_idx * 2];
        dy := DIRS[best_dir_idx * 2 + 1];
        enemy_step_to(e, e.x + dx, e.y + dy);
    }
}

enemy_move_random_safe :: (e: *Enemy) {
    // Wander without immediate backtracking and without stepping into blast.
    pref: [4] int;     // safe, not-backtrack
    pref_n := 0;
    alt: [4] int;      // safe, backtrack allowed
    alt_n := 0;
    for dir_idx: 0..3 {
        nx := e.x + DIRS[dir_idx * 2];
        ny := e.y + DIRS[dir_idx * 2 + 1];
        if !can_walk_safe(nx, ny) || is_in_blast(nx, ny) continue;
        if nx == e.last_x && ny == e.last_y {
            alt[alt_n] = dir_idx;
            alt_n += 1;
        } else {
            pref[pref_n] = dir_idx;
            pref_n += 1;
        }
    }
    list_n := ifx pref_n > 0 then pref_n else alt_n;
    if list_n == 0 {
        e.idle_streak += 1;
        return;
    }
    pick := cast(int)(random_get() % cast(u64) list_n);
    idx := ifx pref_n > 0 then pref[pick] else alt[pick];
    dx := DIRS[idx * 2];
    dy := DIRS[idx * 2 + 1];
    enemy_step_to(e, e.x + dx, e.y + dy);
}

enemy_try_place_bomb :: (e: *Enemy, active_bombs: int, max_escape_steps: int) -> bool {
    if active_bombs >= e.max_bombs return false;
    if is_in_blast(e.x, e.y) return false;

    // A free kill from here? Then loot preservation is off — winning the round
    // matters more than saving a powerup.
    would_kill := bomb_hits_tile(e.x, e.y, e.fire_range, player.x, player.y);
    if !would_kill {
        for * other: enemies {
            if other == e || !other.alive continue;
            if bomb_hits_tile(e.x, e.y, e.fire_range, other.x, other.y) {
                would_kill = true;
                break;
            }
        }
    }

    if !would_kill {
        // Never drop a bomb whose blast would destroy an unclaimed powerup —
        // they're worth more to us alive on the floor than vaporised.
        for powerups {
            if it.delay > 0 continue;
            if bomb_hits_tile(e.x, e.y, e.fire_range, it.x, it.y) return false;
        }
    }

    sim: [1] Bomb;
    sim[0].x = e.x; sim[0].y = e.y; sim[0].range = e.fire_range; sim[0].owner = e.id; sim[0].timer = BOMB_TIMER;
    found, sx, sy := find_safe_cell(e.x, e.y, sim);
    if !found return false;
    path := bfs_path(e.x, e.y, sx, sy);
    if path.count == 0 || path.count > max_escape_steps return false;
    b: Bomb;
    b.x = e.x; b.y = e.y; b.timer = BOMB_TIMER; b.range = e.fire_range; b.owner = e.id;
    array_add(*bombs, b);
    spawn_death_fx(cast(float)b.x, cast(float)b.y, col(0.702, 0.533, 1.0, 1), false);
    return true;
}

update_single_enemy :: (e: *Enemy) {
    if !e.alive return;
    if e.hopping return;
    if e.stun_timer > 0 {
        e.stun_timer -= 1;
        return;
    }
    e.move_timer -= 1;
    if e.move_timer > 0 return;
    e.move_timer = e.move_delay;

    max_escape_steps := BOMB_TIMER / e.move_delay - 2;

    // PHASE 1 — In immediate danger? Commit to a flee destination.
    if is_in_blast(e.x, e.y) {
        enemy_do_flee_step(e);
        return;
    }

    // Safe tile. Drop any stale flee plan.
    if e.has_flee && e.x == e.flee_x && e.y == e.flee_y e.has_flee = false;
    if e.has_flee && is_in_blast(e.flee_x, e.flee_y) e.has_flee = false;

    active_bombs := 0;
    for bombs if it.owner == e.id active_bombs += 1;

    field := dijkstra_through_bricks(e.x, e.y);
    target_kind, tx, ty := find_best_target(e, field);

    // PHASE 2 — Strike now if any living rival sits inside our blast line. This
    // overrides whatever target we'd picked: a free kill beats farming.
    if active_bombs < e.max_bombs {
        in_blast_line := bomb_hits_tile(e.x, e.y, e.fire_range, player.x, player.y);
        if !in_blast_line {
            for * other: enemies {
                if other == e || !other.alive continue;
                if bomb_hits_tile(e.x, e.y, e.fire_range, other.x, other.y) {
                    in_blast_line = true;
                    break;
                }
            }
        }
        if in_blast_line && enemy_try_place_bomb(e, active_bombs, max_escape_steps) {
            e.idle_streak = 0;
            return;
        }
    }

    // PHASE 3 — Pursue along a strictly safe path. Bricks aren't walkable here,
    // so this only finds routes through existing corridors.
    if target_kind != .NONE {
        path := bfs_path(e.x, e.y, tx, ty, avoid_blast = true);
        if path.count > 0 {
            ns := path[0];
            if can_walk_safe(ns.x, ns.y) && !is_in_blast(ns.x, ns.y) {
                enemy_step_to(e, ns.x, ns.y);
                return;
            }
        }
    }

    // PHASE 4 — Strict path failed. The planning Dijkstra knows a route that
    // passes through one or more bricks — bust the first brick on that route.
    if target_kind != .NONE {
        bx, by := first_brick_on_path(field, e.x, e.y, tx, ty);
        if bx >= 0 {
            adjacent := abs(bx - e.x) + abs(by - e.y) == 1;
            if adjacent && bomb_hits_tile(e.x, e.y, e.fire_range, bx, by) {
                if active_bombs < e.max_bombs && enemy_try_place_bomb(e, active_bombs, max_escape_steps) {
                    e.idle_streak = 0;
                    return;
                }
            }
            if !adjacent {
                // Approach the brick from whichever empty neighbour is closest
                // to us along a strictly safe path.
                approach_x := -1; approach_y := -1;
                approach_d := DIJK_INF;
                for dir_idx: 0..3 {
                    ax := bx + DIRS[dir_idx * 2];
                    ay := by + DIRS[dir_idx * 2 + 1];
                    if ax < 0 || ax >= COLS || ay < 0 || ay >= ROWS continue;
                    if grid[ay][ax] != .EMPTY continue;
                    if is_in_blast(ax, ay) continue;
                    d := field.dist[ay][ax];
                    if d < approach_d {
                        approach_d = d;
                        approach_x = ax; approach_y = ay;
                    }
                }
                if approach_x >= 0 {
                    apath := bfs_path(e.x, e.y, approach_x, approach_y, avoid_blast = true);
                    if apath.count > 0 {
                        ns := apath[0];
                        if can_walk_safe(ns.x, ns.y) && !is_in_blast(ns.x, ns.y) {
                            enemy_step_to(e, ns.x, ns.y);
                            return;
                        }
                    }
                }
            }
        }
    }

    // PHASE 5 — Productive idle: if a bomb dropped right here would crack some
    // bricks, do it. This is what a real player does between hunts.
    if active_bombs < e.max_bombs {
        n := count_bricks_hit(e.x, e.y, e.fire_range);
        if n > 0 && enemy_try_place_bomb(e, active_bombs, max_escape_steps) {
            e.idle_streak = 0;
            return;
        }
    }

    // PHASE 6 — Walk toward a brick-cluster tile so we can farm next tick.
    fx_, fy_ := find_best_farm_tile(e, field);
    if fx_ >= 0 && !(fx_ == e.x && fy_ == e.y) {
        fpath := bfs_path(e.x, e.y, fx_, fy_, avoid_blast = true);
        if fpath.count > 0 {
            ns := fpath[0];
            if can_walk_safe(ns.x, ns.y) && !is_in_blast(ns.x, ns.y) {
                enemy_step_to(e, ns.x, ns.y);
                return;
            }
        }
    }

    // PHASE 7 — Truly nothing to do. Stay put a beat, then nudge so we don't
    // freeze in place.
    e.idle_streak += 1;
    if e.idle_streak > 5 {
        enemy_move_random_safe(e);
    }
}

move_player :: (dx: int, dy: int) {
    if player.stun_timer > 0 return;
    if player.locked_by_mechanic return;
    if player.hopping return;
    nx := player.x + dx;
    ny := player.y + dy;
    if nx < 0 || nx >= COLS || ny < 0 || ny >= ROWS return;
    if grid[ny][nx] != .EMPTY return;
    if current_mechanic.tile_blocked && current_mechanic.tile_blocked(nx, ny) return;

    bomb_idx := -1;
    for bombs {
        if !it.punching && it.x == nx && it.y == ny {
            bomb_idx = it_index;
            break;
        }
    }

    if bomb_idx >= 0 {
        b := *bombs[bomb_idx];
        if player.has_kick && b.slide_dx == 0 && b.slide_dy == 0 {
            sx := nx + dx;
            sy := ny + dy;
            if sx >= 0 && sx < COLS && sy >= 0 && sy < ROWS && grid[sy][sx] == .EMPTY {
                blocked := false;
                for bombs if !it.punching && it_index != bomb_idx && it.x == sx && it.y == sy blocked = true;
                if !blocked {
                    prev_x := player.x;
                    prev_y := player.y;
                    b.x = sx;
                    b.y = sy;
                    b.slide_dx = dx;
                    b.slide_dy = dy;
                    b.slide_timer = BOMB_SLIDE_SPEED;
                    player.x = nx;
                    player.y = ny;
                    spawn_fx(cast(float)prev_x, cast(float)prev_y, col(0.706, 0.671, 0.612, 1), .DUST);
                }
            }
        }
        return;
    }

    prev_x := player.x;
    prev_y := player.y;
    player.x = nx;
    player.y = ny;
    spawn_fx(cast(float)prev_x, cast(float)prev_y, col(0.706, 0.671, 0.612, 1), .DUST);
}

punch_bomb :: () {
    if !player.has_punch return;
    if player.stun_timer > 0 return;
    if player.locked_by_mechanic return;
    if player.hopping return;
    ddx, ddy: int;
    if player.dir == {
        case .UP;    ddx = 0; ddy = -1;
        case .DOWN;  ddx = 0; ddy = 1;
        case .LEFT;  ddx = -1; ddy = 0;
        case .RIGHT; ddx = 1; ddy = 0;
    }

    bx := player.x + ddx;
    by := player.y + ddy;

    bomb_idx := -1;
    for bombs {
        if !it.punching && it.slide_dx == 0 && it.slide_dy == 0 && it.x == bx && it.y == by {
            bomb_idx = it_index;
            break;
        }
    }
    if bomb_idx < 0 return;
    b := *bombs[bomb_idx];

    // Kick off the first 2-tile hop. Bomb leaves the ground.
    b.punching = true;
    b.punch_dx = ddx;
    b.punch_dy = ddy;
    b.punch_from_x = cast(float)b.x;
    b.punch_from_y = cast(float)b.y;
    b.punch_target_x = cast(float)b.x + 2.0 * cast(float)ddx;
    b.punch_target_y = cast(float)b.y + 2.0 * cast(float)ddy;
    b.punch_t = 0;
    // Liftoff puff
    spawn_fx(cast(float)b.x, cast(float)b.y, col(0.882, 0.745, 0.906, 1), .BOING);
    // While in flight, the ground tile is unoccupied. Mark x,y at -1 so other systems ignore the bomb.
    b.x = -1;
    b.y = -1;
}

update :: () {
    frame_count += 1;
    update_atmosphere();
    shake_amount *= SHAKE_DECAY;
    if shake_amount < 0.01 shake_amount = 0;

    if game_over return;

    // Mount/hop overrides handle player position themselves. Otherwise lerp.
    if !player_is_riding() && !player.hopping {
        player.rx += (cast(float)player.x - player.rx) * LERP_SPEED;
        player.ry += (cast(float)player.y - player.ry) * LERP_SPEED;
        if abs(cast(float)player.x - player.rx) < 0.01 player.rx = cast(float)player.x;
        if abs(cast(float)player.y - player.ry) < 0.01 player.ry = cast(float)player.y;
    }

    for * enemies {
        if !it.alive continue;
        // While riding the cart or mid-arc, position is driven explicitly.
        if it.hopping continue;
        if mine_cart.rider == .ENEMY && it_index == mine_cart.rider_enemy_id continue;
        it.rx += (cast(float)it.x - it.rx) * LERP_SPEED;
        it.ry += (cast(float)it.y - it.ry) * LERP_SPEED;
        if abs(cast(float)it.x - it.rx) < 0.01 it.rx = cast(float)it.x;
        if abs(cast(float)it.y - it.ry) < 0.01 it.ry = cast(float)it.y;
    }

    if player.stun_timer > 0 player.stun_timer -= 1;

    move_timer -= 1;
    if move_timer <= 0 {
        moved := false;
        if !player_is_busy() {
            if key_up { move_player(0, -1); moved = true; player.dir = .UP; }
            else if key_down { move_player(0, 1); moved = true; player.dir = .DOWN; }
            else if key_left { move_player(-1, 0); moved = true; player.dir = .LEFT; }
            else if key_right { move_player(1, 0); moved = true; player.dir = .RIGHT; }
        }
        if moved {
            move_timer = player.move_delay;
            if current_mechanic.on_player_moved current_mechanic.on_player_moved();
        }
    }

    // Per-level mechanic update. Inactive levels have a null tick — zero cost.
    if current_mechanic.tick current_mechanic.tick();

    update_player_hop();
    update_enemy_hops();

    // Advance punching bombs (arc-hop chain)
    for * b, bi: bombs {
        if !b.punching continue;
        b.punch_t += 1.0 / cast(float)PUNCH_HOP_FRAMES;
        while b.punching && b.punch_t >= 1.0 {
            // Wrap the destination tile back into the grid.
            tx := cast(int)(floor(b.punch_target_x) + cast(float)(COLS * 100)) % COLS;
            ty := cast(int)(floor(b.punch_target_y) + cast(float)(ROWS * 100)) % ROWS;

            spawn_fx(cast(float)tx, cast(float)ty, col(0.882, 0.745, 0.906, 1), .BOING);

            should_land := true;
            tile := grid[ty][tx];

            if tile == .WALL || tile == .BRICK || tile == .BRICK_MELTING {
                should_land = false;
            } else {
                if player.x == tx && player.y == ty {
                    player.stun_timer = PLAYER_STUN;
                    should_land = false;
                }
                for * en: enemies {
                    if en.alive && en.x == tx && en.y == ty {
                        en.stun_timer = PLAYER_STUN;
                        should_land = false;
                    }
                }
                for j: 0..bombs.count-1 {
                    if j == bi continue;
                    if !bombs[j].punching && bombs[j].x == tx && bombs[j].y == ty {
                        should_land = false;
                        break;
                    }
                }

                if should_land {
                    pidx := -1;
                    for pup, pi: powerups {
                        if pup.x == tx && pup.y == ty && pup.delay <= 0 {
                            pidx = pi;
                            break;
                        }
                    }
                    if pidx >= 0 {
                        pu := powerups[pidx];
                        mp: MeltingPowerup;
                        mp.x = pu.x; mp.y = pu.y; mp.type = pu.type; mp.timer = POWERUP_MELT_DURATION;
                        array_add(*melting_powerups, mp);
                        spawn_death_fx(cast(float)pu.x, cast(float)pu.y, powerup_color(pu.type), false);
                        array_unordered_remove_by_index(*powerups, pidx);
                    }
                }
            }

            if should_land {
                b.x = tx;
                b.y = ty;
                b.punching = false;
                b.punch_t = 0;
            } else {
                // Initial hop was 2 tiles; bounces over obstacles are 1 tile each.
                b.punch_from_x = cast(float)tx;
                b.punch_from_y = cast(float)ty;
                b.punch_target_x = cast(float)tx + cast(float)b.punch_dx;
                b.punch_target_y = cast(float)ty + cast(float)b.punch_dy;
                b.punch_t -= 1.0;
            }
        }
    }

    // Update bomb timers and trigger explosions
    {
        i := bombs.count - 1;
        while i >= 0 {
            if !bombs[i].punching {
                bombs[i].timer -= 1;
                if bombs[i].timer <= 0 {
                    b := bombs[i];
                    array_unordered_remove_by_index(*bombs, i);
                    explode(b);
                }
            }
            i -= 1;
        }
    }

    // Bomb sliding
    for * bombs {
        if (it.slide_dx != 0 || it.slide_dy != 0) && it.slide_timer > 0 {
            it.slide_timer -= 1;
            if it.slide_timer <= 0 {
                it.slide_timer = BOMB_SLIDE_SPEED;
                snx := it.x + it.slide_dx;
                sny := it.y + it.slide_dy;
                blocked := false;
                if snx < 0 || snx >= COLS || sny < 0 || sny >= ROWS || grid[sny][snx] != .EMPTY {
                    blocked = true;
                } else {
                    for j: 0..bombs.count-1 {
                        if j != it_index && bombs[j].x == snx && bombs[j].y == sny {
                            blocked = true;
                            break;
                        }
                    }
                }
                if !blocked {
                    spawn_fx(cast(float)it.x, cast(float)it.y, col(0.612, 0.502, 0.871, 1), .DUST);
                    it.x = snx;
                    it.y = sny;
                } else {
                    it.slide_dx = 0;
                    it.slide_dy = 0;
                }
            }
        }
    }

    {
        i := explosions_list.count - 1;
        while i >= 0 {
            explosions_list[i].timer -= 1;
            if explosions_list[i].timer <= 0 {
                array_unordered_remove_by_index(*explosions_list, i);
            }
            i -= 1;
        }
    }

    {
        i := melting_bricks.count - 1;
        while i >= 0 {
            melting_bricks[i].timer -= 1;
            if melting_bricks[i].timer <= 0 {
                m := melting_bricks[i];
                grid[m.y][m.x] = .EMPTY;
                array_unordered_remove_by_index(*melting_bricks, i);
            }
            i -= 1;
        }
    }

    {
        i := melting_powerups.count - 1;
        while i >= 0 {
            melting_powerups[i].timer -= 1;
            if melting_powerups[i].timer <= 0 {
                array_unordered_remove_by_index(*melting_powerups, i);
            }
            i -= 1;
        }
    }

    for * enemies update_single_enemy(it);

    // Hit by explosions
    for explosions_list {
        if !player.hopping && game_over_delay == 0 && it.x == player.x && it.y == player.y {
            spawn_death_fx(player.rx, player.ry, col(0.353, 0.604, 0.965, 1), true);
            game_over_delay = 50;
            hit_flash_timer = 22;
            player_won = false;
            play_sfx(*sound_hit, 0.55);
        }
        for * en: enemies {
            if en.alive && !en.hopping && it.x == en.x && it.y == en.y {
                en.alive = false;
                spawn_death_fx(en.rx, en.ry, en.glow, true);
                drop_enemy_powerups(en);
                play_sfx(*sound_hit, 0.55);
            }
        }
    }

    if game_over_delay > 0 {
        game_over_delay -= 1;
        if game_over_delay == 0 game_over = true;
    }

    if !game_over && game_over_delay == 0 {
        all_dead := true;
        for enemies if it.alive { all_dead = false; break; }
        if all_dead {
            game_over_delay = 50;
            victory_flash_timer = 30;
            player_won = true;
        }
    }

    if hit_flash_timer > 0 hit_flash_timer -= 1;
    if victory_flash_timer > 0 victory_flash_timer -= 1;

    // Tick death FX
    {
        i := death_fx_list.count - 1;
        while i >= 0 {
            death_fx_list[i].timer -= 1;
            if death_fx_list[i].timer <= 0 array_unordered_remove_by_index(*death_fx_list, i);
            i -= 1;
        }
    }

    // Powerups pickup / explosion damage
    {
        i := powerups.count - 1;
        while i >= 0 {
            p := *powerups[i];
            if p.delay > 0 {
                p.delay -= 1;
                if p.delay == 0 {
                    spawn_fx(cast(float)p.x, cast(float)p.y, powerup_color(p.type), .SMALL);
                }
                i -= 1;
                continue;
            }
            in_explosion := false;
            for explosions_list if it.x == p.x && it.y == p.y { in_explosion = true; break; }
            if in_explosion {
                mp: MeltingPowerup;
                mp.x = p.x; mp.y = p.y; mp.type = p.type; mp.timer = POWERUP_MELT_DURATION;
                array_add(*melting_powerups, mp);
                spawn_death_fx(cast(float)p.x, cast(float)p.y, powerup_color(p.type), false);
                array_unordered_remove_by_index(*powerups, i);
                i -= 1;
                continue;
            }
            if p.x == player.x && p.y == player.y {
                if p.type == .BOMB player.max_bombs += 1;
                else if p.type == .FIRE player.fire_range += 1;
                else if p.type == .KICK player.has_kick = true;
                else if p.type == .PUNCH player.has_punch = true;
                else if p.type == .SKATE {
                    player.skate_count += 1;
                    player.move_delay = max(PLAYER_MOVE_DELAY_MIN, player.move_delay - SKATE_BOOST_PLAYER);
                }
                spawn_death_fx(cast(float)p.x, cast(float)p.y, powerup_color(p.type), false);
                play_sfx(*sound_powerup, 0.70);
                array_unordered_remove_by_index(*powerups, i);
                i -= 1;
                continue;
            }
            picked := false;
            for * en: enemies {
                if en.alive && p.x == en.x && p.y == en.y {
                    if p.type == .BOMB en.max_bombs += 1;
                    else if p.type == .FIRE en.fire_range += 1;
                    else if p.type == .SKATE {
                        en.skate_count += 1;
                        en.move_delay = max(ENEMY_MOVE_DELAY_MIN, en.move_delay - SKATE_BOOST_ENEMY);
                    }
                    spawn_death_fx(cast(float)p.x, cast(float)p.y, powerup_color(p.type), false);
                    picked = true;
                    break;
                }
            }
            if picked array_unordered_remove_by_index(*powerups, i);
            i -= 1;
        }
    }
}

draw_text :: (text: string, x: int, y: int, color: Vector4) {
    if !my_font return;
    Simp.prepare_text(my_font, text);
    Simp.draw_prepared_text(my_font, x, y, color);
}

draw_hud_panel :: () {
    bx := 8.0; by := 8.0; bw := 340.0; bh := 44.0;
    // Subtle drop shadow
    draw_rounded_rect(bx + 2, by + 3, bw, bh, 9, col(0, 0, 0, 0.35));
    // Body
    draw_rounded_rect(bx, by, bw, bh, 9, col(0.058, 0.040, 0.118, 0.88));
    // Inner highlight gradient (thin top strip)
    draw_rounded_rect(bx + 2, by + 1, bw - 4, 6, 7, col(0.18, 0.14, 0.36, 0.42));
    // Outline
    draw_stroke_rect(bx, by, bw, bh, col(0.78, 0.62, 1.0, 0.30), 1.4);

    pulse := 0.85 + sin(cast(float)frame_count / 14.0) * 0.15;

    // Bomb count chip
    cx := bx + 22; cy := by + bh / 2;
    for i: 0..2 {
        rr := 6.0 + cast(float)i * 4.0;
        a := (0.25 - cast(float)i * 0.07) * pulse;
        if a > 0 draw_filled_circle(cx, cy, rr, col(0.702, 0.533, 1.0, a), 14);
    }
    draw_filled_circle(cx, cy, 7, col(0.486, 0.302, 1.0, 1), 12);
    draw_filled_circle(cx - 2, cy - 2, 2.5, col(1, 1, 1, 0.85), 6);

    // Fire chip
    fx := bx + 64;
    for i: 0..2 {
        rr := 6.0 + cast(float)i * 4.0;
        a := (0.25 - cast(float)i * 0.07) * pulse;
        if a > 0 draw_filled_circle(fx, cy, rr, col(1.0, 0.55, 0.20, a), 14);
    }
    draw_filled_circle(fx, cy, 6, col(1.0, 0.671, 0.251, 1), 12);
    draw_filled_circle(fx - 1, cy - 1.5, 2, col(1, 1, 0.85, 0.85), 6);

    // Skate icon
    sx_hud := bx + 105;
    sy_hud := by + bh / 2;
    draw_filled_circle(sx_hud, sy_hud, 11, col(0.42, 0.81, 1.0, 0.22 * pulse), 12);
    draw_filled_rect(sx_hud - 6, sy_hud - 2, 12, 4, col(0.298, 0.329, 0.451, 1));
    draw_filled_rect(sx_hud + 0, sy_hud - 6, 6, 4, col(0.298, 0.329, 0.451, 1));
    draw_filled_circle(sx_hud - 4, sy_hud + 3, 1.7, col(0.10, 0.13, 0.22, 1), 6);
    draw_filled_circle(sx_hud + 1, sy_hud + 3, 1.7, col(0.10, 0.13, 0.22, 1), 6);
    draw_filled_circle(sx_hud + 5, sy_hud + 3, 1.7, col(0.10, 0.13, 0.22, 1), 6);

    if player.has_kick {
        kx := bx + 158;
        for i: 0..1 {
            rr := 7.0 + cast(float)i * 4.0;
            a := (0.30 - cast(float)i * 0.10) * pulse;
            if a > 0 draw_filled_circle(kx, cy, rr, col(0, 0.85, 0.95, a), 12);
        }
        draw_filled_circle(kx, cy, 6, col(0, 0.737, 0.827, 1), 10);
        draw_filled_circle(kx - 1.5, cy - 1.5, 1.6, col(1, 1, 1, 0.85), 5);
    }

    if player.has_punch {
        px_hud := ifx player.has_kick then bx + 225 else bx + 158;
        for i: 0..1 {
            rr := 7.0 + cast(float)i * 4.0;
            a := (0.30 - cast(float)i * 0.10) * pulse;
            if a > 0 draw_filled_circle(px_hud, cy, rr, col(1.0, 0.85, 0.25, a), 12);
        }
        draw_filled_circle(px_hud, cy, 6, col(1.0, 0.757, 0.027, 1), 10);
        draw_filled_circle(px_hud - 1.5, cy - 1.5, 1.6, col(1, 1, 1, 0.85), 5);
    }
}

draw_hud :: () {
    bx := 8.0; by := 8.0; bh := 44.0;
    ty := by + bh / 2 - 7;
    draw_text(tprint("%", player.max_bombs), cast(int)(bx + 32), cast(int) ty, col(0.940, 0.835, 1.0, 1));
    draw_text(tprint("%", player.fire_range), cast(int)(bx + 75), cast(int) ty, col(1.0, 0.93, 0.78, 1));
    draw_text(tprint("%", player.skate_count), cast(int)(bx + 120), cast(int) ty, col(0.74, 0.92, 1.0, 1));
    if player.has_kick {
        draw_text("KICK", cast(int)(bx + 170), cast(int) ty, col(0.78, 0.96, 0.98, 1));
    }
    if player.has_punch {
        px_hud := ifx player.has_kick then bx + 235 else bx + 170;
        draw_text("PNCH", cast(int)(px_hud + 8), cast(int) ty, col(1.0, 0.96, 0.80, 1));
    }
}

apply_letterbox :: () {
    glViewport(0, 0, cast(u32) window_w_actual, cast(u32) window_h_actual);
    Simp.clear_render_target(0.020, 0.018, 0.039, 1);

    sx := cast(float) window_w_actual / cast(float) WINDOW_W;
    sy := cast(float) window_h_actual / cast(float) WINDOW_H;
    s  := min(sx, sy);
    vw := cast(s32)(cast(float)WINDOW_W * s);
    vh := cast(s32)(cast(float)WINDOW_H * s);
    ox := (window_w_actual - vw) / 2;
    oy := (window_h_actual - vh) / 2;
    glViewport(cast(s32) ox, cast(s32) oy, cast(u32) vw, cast(u32) vh);
}

project_tile_center :: (cx: float, cy: float) -> float, float {
    sc, _ := project(.{cx, 0, cy});
    return sc.x, sc.y;
}

render :: () {
    apply_letterbox();
    Simp.set_shader_for_color(enable_blend=true);
    Simp.immediate_set_2d_projection(WINDOW_W, WINDOW_H);

    if !atmosphere_initialized init_atmosphere();

    build_camera();

    // Dramatic backdrop: sky gradient, moon, horizon halo, stars
    draw_background();

    // Background ambient motes — far ones drift behind the play area
    for ambient_motes {
        // Only draw "back" motes here (those whose world Z is in the back half of the board)
        if it.z > cast(float)(ROWS * TILE) * 0.5 continue;
        a := 0.45 + sin(it.phase) * 0.30;
        sc, ok := project(.{it.x, it.height, it.z});
        if !ok continue;
        s := screen_scale_at(.{it.x, it.height, it.z});
        sz := it.size * (0.7 + 0.4 * s);
        draw_filled_circle(sc.x, sc.y, sz * 2.4, col(it.color.x, it.color.y, it.color.z, a * 0.08), 8);
        draw_filled_circle(sc.x, sc.y, sz * 1.3, col(it.color.x, it.color.y, it.color.z, a * 0.40), 8);
        draw_filled_circle(sc.x, sc.y, sz * 0.55, col(1, 1, 1, a * 0.85), 6);
    }

    for r: 0..ROWS-1 {
        for c: 0..COLS-1 {
            if grid[r][c] == .EMPTY || grid[r][c] == .BRICK_MELTING {
                draw_floor_3d(c, r);
            } else if grid[r][c] == .WATER {
                draw_water_3d(c, r);
            }
        }
    }

    // Floor light pools (bombs, powerups, explosions, characters) — drawn over floor, under walls
    draw_floor_lights();

    // Level mechanic ground-pass (e.g. mine cart rails). No-op for vanilla.
    if current_mechanic.draw_ground current_mechanic.draw_ground();

    for r: 0..ROWS-1 {
        for c: 0..COLS-1 {
            if grid[r][c] == .WALL draw_wall_3d(c, r);
            else if grid[r][c] == .BRICK draw_brick_3d(c, r);
            else if grid[r][c] == .BRICK_MELTING {
                for melting_bricks {
                    if it.x == c && it.y == r {
                        draw_melting_brick_3d(it);
                        break;
                    }
                }
            }
        }

        for powerups {
            if it.delay > 0 || it.y != r continue;
            cx_w := cast(float)(it.x * TILE) + cast(float)TILE * 0.5;
            cz_w := cast(float)(it.y * TILE) + cast(float)TILE * 0.5;
            sc, _ := project(.{cx_w, cast(float)TILE * 0.25, cz_w});
            draw_powerup(it, sc.x, sc.y);
        }
        for melting_powerups {
            if it.y != r continue;
            cx_w := cast(float)(it.x * TILE) + cast(float)TILE * 0.5;
            cz_w := cast(float)(it.y * TILE) + cast(float)TILE * 0.5;
            sc, _ := project(.{cx_w, cast(float)TILE * 0.25, cz_w});
            draw_melting_powerup(it, sc.x, sc.y);
        }
        for bombs {
            if it.punching || it.y != r continue;
            cx_w := cast(float)(it.x * TILE) + cast(float)TILE * 0.5;
            cz_w := cast(float)(it.y * TILE) + cast(float)TILE * 0.5;
            sc, _ := project(.{cx_w, cast(float)TILE * 0.3, cz_w});
            draw_bomb(it, sc.x, sc.y);
        }

        // Punching bombs: render at interpolated row, with an arc + ground shadow.
        for bombs {
            if !it.punching continue;
            ix := it.punch_from_x + (it.punch_target_x - it.punch_from_x) * it.punch_t;
            iy := it.punch_from_y + (it.punch_target_y - it.punch_from_y) * it.punch_t;
            wx := ix - floor(ix / cast(float)COLS) * cast(float)COLS;
            wy := iy - floor(iy / cast(float)ROWS) * cast(float)ROWS;
            if cast(int)wy != r continue;
            cx_w := wx * cast(float)TILE + cast(float)TILE * 0.5;
            cz_w := wy * cast(float)TILE + cast(float)TILE * 0.5;
            arc_h := sin(it.punch_t * PI) * PUNCH_ARC_HEIGHT;
            // Ground shadow: small flattened ellipse, smaller and dimmer at apex
            sh_scale := 0.55 + (1.0 - sin(it.punch_t * PI)) * 0.45;
            sh, _ := project(.{cx_w, 0.2, cz_w});
            draw_filled_ellipse(sh.x, sh.y, 11.0 * sh_scale, 4.0 * sh_scale, col(0, 0, 0, 0.35 * sh_scale));
            // Airborne bomb sprite
            sc, _ := project(.{cx_w, cast(float)TILE * 0.3 + arc_h, cz_w});
            draw_bomb(it, sc.x, sc.y);
        }

        // Level mechanic per-row pass. The cart (volcanic) draws here so it
        // depth-sorts correctly against the row's player/enemies/bombs.
        if current_mechanic.draw_row current_mechanic.draw_row(r);

        // Player render: skip while airborne (hop handles its own draw below)
        // and while a beach fish has swallowed us mid-teleport.
        player_hidden := fish_teleport.active &&
            fish_teleport.phase >= FISH_SWALLOW_TICKS - 4 &&
            fish_teleport.phase <= FISH_SWALLOW_TICKS + FISH_TRAVEL_TICKS + 4;
        if !player.hopping && !player_hidden && player.y == r {
            cx_w := player.rx * cast(float)TILE + cast(float)TILE * 0.5;
            cz_w := player.ry * cast(float)TILE + cast(float)TILE * 0.5;
            // Lift the player onto the cart while riding.
            ride_lift: float = ifx player_is_riding() then cast(float)TILE * 0.32 else 0.0;
            sc, _ := project(.{cx_w, ride_lift, cz_w});
            draw_player_char(sc.x, sc.y - 26);
        }

        // Arc-hop render: player on a parabolic arc with a tightening ground shadow.
        if player.hopping {
            ix := player.hop_from_x + (player.hop_target_x - player.hop_from_x) * player.hop_t;
            iy := player.hop_from_y + (player.hop_target_y - player.hop_from_y) * player.hop_t;
            wx := ix - floor(ix / cast(float)COLS) * cast(float)COLS;
            wy := iy - floor(iy / cast(float)ROWS) * cast(float)ROWS;
            if cast(int) wy == r {
                cx_w := wx * cast(float)TILE + cast(float)TILE * 0.5;
                cz_w := wy * cast(float)TILE + cast(float)TILE * 0.5;
                arc_h := sin(player.hop_t * PI) * PLAYER_HOP_HEIGHT;
                sh_scale := 0.55 + (1.0 - sin(player.hop_t * PI)) * 0.45;
                sh, _ := project(.{cx_w, 0.2, cz_w});
                draw_filled_ellipse(sh.x, sh.y, 14.0 * sh_scale, 5.0 * sh_scale, col(0, 0, 0, 0.45 * sh_scale));
                sc, _ := project(.{cx_w, arc_h, cz_w});
                draw_player_char(sc.x, sc.y - 26);
            }
        }
        for * en, ei: enemies {
            if !en.alive continue;
            if en.hopping {
                ix := en.hop_from_x + (en.hop_target_x - en.hop_from_x) * en.hop_t;
                iy := en.hop_from_y + (en.hop_target_y - en.hop_from_y) * en.hop_t;
                wx := ix - floor(ix / cast(float)COLS) * cast(float)COLS;
                wy := iy - floor(iy / cast(float)ROWS) * cast(float)ROWS;
                if cast(int) wy != r continue;
                cx_w := wx * cast(float)TILE + cast(float)TILE * 0.5;
                cz_w := wy * cast(float)TILE + cast(float)TILE * 0.5;
                arc_h := sin(en.hop_t * PI) * PLAYER_HOP_HEIGHT;
                sh_scale := 0.55 + (1.0 - sin(en.hop_t * PI)) * 0.45;
                sh, _ := project(.{cx_w, 0.2, cz_w});
                draw_filled_ellipse(sh.x, sh.y, 14.0 * sh_scale, 5.0 * sh_scale, col(0, 0, 0, 0.45 * sh_scale));
                sc, _ := project(.{cx_w, arc_h, cz_w});
                draw_enemy_char(en, sc.x, sc.y - 28);
                continue;
            }
            if en.y != r continue;
            // Lift the enemy onto the cart while riding.
            ride_lift: float = 0;
            if mine_cart.rider == .ENEMY && ei == mine_cart.rider_enemy_id {
                ride_lift = cast(float)TILE * 0.32;
            }
            cx_w := en.rx * cast(float)TILE + cast(float)TILE * 0.5;
            cz_w := en.ry * cast(float)TILE + cast(float)TILE * 0.5;
            sc, _ := project(.{cx_w, ride_lift, cz_w});
            draw_enemy_char(en, sc.x, sc.y - 28);
        }

        for explosions_list {
            if it.y != r continue;
            cx_w := cast(float)(it.x * TILE) + cast(float)TILE * 0.5;
            cz_w := cast(float)(it.y * TILE) + cast(float)TILE * 0.5;
            sc, _ := project(.{cx_w, cast(float)TILE * 0.35, cz_w});
            draw_explosion(it, sc.x, sc.y);
        }

        for death_fx_list {
            row := cast(int)(it.y + 0.5);
            if row != r continue;
            cx_w := it.x * cast(float)TILE + cast(float)TILE * 0.5;
            cz_w := it.y * cast(float)TILE + cast(float)TILE * 0.5;
            h: float = 0.25 * cast(float)TILE;
            if it.kind == {
                case .BIG;      h = 0.40 * cast(float)TILE;
                case .SMALL;    h = 0.25 * cast(float)TILE;
                case .BOING;    h = 0.10 * cast(float)TILE;
                case .DUST;     h = 0.05 * cast(float)TILE;
            }
            sc, _ := project(.{cx_w, h, cz_w});
            draw_death_fx(it, sc.x, sc.y);
        }
    }

    // Foreground motes — front half of the board (drift past the camera)
    for ambient_motes {
        if it.z <= cast(float)(ROWS * TILE) * 0.5 continue;
        a := 0.45 + sin(it.phase) * 0.30;
        sc, ok := project(.{it.x, it.height, it.z});
        if !ok continue;
        s := screen_scale_at(.{it.x, it.height, it.z});
        sz := it.size * (0.85 + 0.55 * s);
        draw_filled_circle(sc.x, sc.y, sz * 2.6, col(it.color.x, it.color.y, it.color.z, a * 0.10), 8);
        draw_filled_circle(sc.x, sc.y, sz * 1.45, col(it.color.x, it.color.y, it.color.z, a * 0.50), 8);
        draw_filled_circle(sc.x, sc.y, sz * 0.6, col(1, 1, 1, a * 0.9), 6);
    }

    vw := cast(float)WINDOW_W;
    vh := cast(float)WINDOW_H;

    // Smooth edge fades — no square corners, just gentle inward fades for atmosphere.
    vig := col(0.0, 0.0, 0.020, 0.30);
    band :: 90.0;
    draw_edge_fade(0, 0,         vw,   band, 0, vig);
    draw_edge_fade(0, vh - band, vw,   band, 1, vig);
    draw_edge_fade(0, 0,         band, vh,   2, vig);
    draw_edge_fade(vw - band, 0, band, vh,   3, vig);

    // Top warm-tint atmosphere overlay tied to recent explosions
    if recent_boom > 0 {
        a := recent_boom * 0.18;
        bt := current_theme.boom_tint;
        draw_filled_rect(0, 0, vw, vh, col(bt.x, bt.y, bt.z, a));
    }

    if hit_flash_timer > 0 {
        a := cast(float)hit_flash_timer / 22.0;
        draw_filled_rect(0, 0, vw, vh, col(1.0, 0.140, 0.180, a * 0.32));
        rim_a := a * 0.55;
        draw_filled_rect(0, 0, vw, 22, col(1.0, 0.18, 0.20, rim_a));
        draw_filled_rect(0, vh - 22, vw, 22, col(1.0, 0.18, 0.20, rim_a));
        draw_filled_rect(0, 0, 22, vh, col(1.0, 0.18, 0.20, rim_a));
        draw_filled_rect(vw - 22, 0, 22, vh, col(1.0, 0.18, 0.20, rim_a));
    }
    if victory_flash_timer > 0 {
        a := cast(float)victory_flash_timer / 30.0;
        draw_filled_rect(0, 0, vw, vh, col(1.0, 0.937, 0.541, a * 0.30));
        // sunburst rays from center
        cx := vw * 0.5;
        cy := vh * 0.5;
        for i: 0..11 {
            ang := (cast(float)i / 12.0) * TAU + cast(float)(victory_flash_timer) * 0.04;
            ex := cx + cos(ang) * vw;
            ey := cy + sin(ang) * vh;
            draw_line(cx, cy, ex, ey, col(1.0, 0.92, 0.60, a * 0.35), 3.0);
        }
    }

    // Level mechanic overlay (e.g. snow particles falling). After the world,
    // before the HUD.
    if current_mechanic.draw_overlay current_mechanic.draw_overlay();

    draw_hud_panel();

    Simp.immediate_flush();
    Simp.set_shader_for_text();
    Simp.immediate_set_2d_projection(WINDOW_W, WINDOW_H);
    draw_hud();
    Simp.immediate_flush();

    if game_over {
        Simp.set_shader_for_color(enable_blend=true);
        Simp.immediate_set_2d_projection(WINDOW_W, WINDOW_H);

        // Dim background
        draw_filled_rect(0, 0, cast(float)WINDOW_W, cast(float)WINDOW_H, col(0.020, 0.014, 0.050, 0.78));

        cx_w := cast(float)WINDOW_W / 2;
        cy_w := cast(float)WINDOW_H / 2;

        // Beams / rays from the center
        ray_count := 18;
        for i: 0..ray_count-1 {
            ang := (cast(float)i / cast(float)ray_count) * TAU + cast(float)frame_count * 0.008;
            len := 1.4 * cast(float)WINDOW_W;
            ex := cx_w + cos(ang) * len;
            ey := cy_w + sin(ang) * len;
            ray_color := ifx player_won then col(1.0, 0.85, 0.45, 0.10) else col(0.95, 0.25, 0.30, 0.10);
            draw_line(cx_w, cy_w, ex, ey, ray_color, 14.0);
        }

        // Central halo
        halo_color := ifx player_won then col(0.95, 0.78, 0.45, 1) else col(0.95, 0.30, 0.32, 1);
        for i: 0..6 {
            rr := 80.0 + cast(float)i * 32.0;
            a := (0.40 - cast(float)i * 0.055);
            if a > 0 draw_filled_circle(cx_w, cy_w, rr, col(halo_color.x, halo_color.y, halo_color.z, a), 22);
        }

        // Decorative ring
        if player_won {
            ring_pulse := 1.0 + sin(cast(float)frame_count / 20.0) * 0.05;
            ring_r := 95.0 * ring_pulse;
            segs := 36;
            for i: 0..segs-1 {
                ang := (cast(float)i / cast(float)segs) * TAU;
                rx := cx_w + cos(ang) * ring_r;
                ry := cy_w + sin(ang) * ring_r;
                draw_filled_circle(rx, ry, 2.4, col(1.0, 0.95, 0.65, 0.85), 6);
            }
        }

        Simp.immediate_flush();
        Simp.set_shader_for_text();
        Simp.immediate_set_2d_projection(WINDOW_W, WINDOW_H);

        text_color: Vector4;
        if player_won {
            text_color = col(1.0, 0.92, 0.65, 1);
        } else {
            text_color = col(1.0, 0.42, 0.42, 1);
        }

        msg := ifx player_won then "VICTORY" else "DEFEATED";
        if my_font {
            tw := Simp.prepare_text(my_font, msg);
            Simp.draw_prepared_text(my_font, (WINDOW_W - tw) / 2, cast(s64)(cy_w - 20), text_color);

            restart_text := "Press R to restart";
            tw2 := Simp.prepare_text(my_font, restart_text);
            Simp.draw_prepared_text(my_font, (WINDOW_W - tw2) / 2, cast(s64)(cy_w + 40), col(0.92, 0.92, 1, 0.85));
        }
        Simp.immediate_flush();
    }
}

load_level :: (kind: LevelKind) {
    current_level = kind;
    current_theme = theme_for(kind);

    // Tear down any previous mechanic state so stale globals can't leak
    // between level switches (e.g. mine_cart left mid-ride going to vanilla).
    mine_cart = .{};
    array_reset(*mine_cart_path);

    current_mechanic = mechanic_for(kind);
    init_grid();
    if current_mechanic.setup current_mechanic.setup();

    // Re-seed atmosphere so motes pick up the new theme palette.
    atmosphere_initialized = false;
}

reset_state :: () {
    load_level(current_level);
    player.x = 1; player.y = 1; player.rx = 1; player.ry = 1;
    player.max_bombs = START_MAX_BOMBS; player.fire_range = START_FIRE_RANGE;
    player.dir = .DOWN; player.has_kick = false; player.has_punch = false;
    player.stun_timer = 0;
    player.move_delay = PLAYER_MOVE_DELAY;
    player.skate_count = 0;
    player.hopping = false;
    player.hop_t = 0;
    player.hop_dx = 0;
    player.hop_dy = 0;
    player.locked_by_mechanic = false;

    enemies[0].x = COLS - 2; enemies[0].y = ROWS - 2;
    enemies[0].rx = cast(float)(COLS - 2); enemies[0].ry = cast(float)(ROWS - 2);
    enemies[0].alive = true; enemies[0].max_bombs = START_MAX_BOMBS;
    enemies[0].fire_range = ENEMY_FIRE_RANGE; enemies[0].move_timer = 0;
    enemies[0].color = col(0.718, 0.110, 0.110, 1);
    enemies[0].glow = col(1.0, 0.090, 0.267, 1);
    enemies[0].id = 1; enemies[0].dir = .LEFT; enemies[0].stun_timer = 0;
    enemies[0].flee_x = -1; enemies[0].flee_y = -1; enemies[0].has_flee = false;
    enemies[0].last_x = -1; enemies[0].last_y = -1; enemies[0].idle_streak = 0;
    enemies[0].move_delay = ENEMY_MOVE_DELAY; enemies[0].skate_count = 0;

    enemies[1].x = COLS - 2; enemies[1].y = 1;
    enemies[1].rx = cast(float)(COLS - 2); enemies[1].ry = 1;
    enemies[1].alive = true; enemies[1].max_bombs = START_MAX_BOMBS;
    enemies[1].fire_range = ENEMY_FIRE_RANGE; enemies[1].move_timer = 0;
    enemies[1].color = col(0.290, 0.078, 0.549, 1);
    enemies[1].glow = col(0.918, 0.502, 0.988, 1);
    enemies[1].id = 2; enemies[1].dir = .DOWN; enemies[1].stun_timer = 0;
    enemies[1].flee_x = -1; enemies[1].flee_y = -1; enemies[1].has_flee = false;
    enemies[1].last_x = -1; enemies[1].last_y = -1; enemies[1].idle_streak = 0;
    enemies[1].move_delay = ENEMY_MOVE_DELAY; enemies[1].skate_count = 0;

    enemies[2].x = 1; enemies[2].y = ROWS - 2;
    enemies[2].rx = 1; enemies[2].ry = cast(float)(ROWS - 2);
    enemies[2].alive = true; enemies[2].max_bombs = START_MAX_BOMBS;
    enemies[2].fire_range = ENEMY_FIRE_RANGE; enemies[2].move_timer = 0;
    enemies[2].color = col(0.106, 0.369, 0.125, 1);
    enemies[2].glow = col(0.412, 0.941, 0.678, 1);
    enemies[2].id = 3; enemies[2].dir = .RIGHT; enemies[2].stun_timer = 0;
    enemies[2].flee_x = -1; enemies[2].flee_y = -1; enemies[2].has_flee = false;
    enemies[2].last_x = -1; enemies[2].last_y = -1; enemies[2].idle_streak = 0;
    enemies[2].move_delay = ENEMY_MOVE_DELAY; enemies[2].skate_count = 0;

    for * en: enemies {
        en.hopping = false;
        en.hop_t = 0;
        en.hop_dx = 0;
        en.hop_dy = 0;
    }

    array_reset(*bombs);
    array_reset(*explosions_list);
    array_reset(*powerups);
    array_reset(*melting_bricks);
    array_reset(*melting_powerups);
    array_reset(*death_fx_list);
    game_over_delay = 0;
    hit_flash_timer = 0;
    victory_flash_timer = 0;
    kick_spawned = 0;
    punch_spawned = 0;
    skate_spawned = 0;
    game_over = false;
    player_won = false;
    move_timer = 0;
    frame_count = 0;
    shake_amount = 0;
    recent_boom  = 0;
    if !atmosphere_initialized init_atmosphere();
    key_up = false; key_down = false; key_left = false; key_right = false;
}

main :: () {
    #if OS == .WINDOWS {
        Windows :: #import "Windows";
        Windows.SetProcessDPIAware();
        Windows.timeBeginPeriod(1);
    }

    random_seed(cast,no_check(u64) (seconds_since_init() * 1000000.0));

    window = create_window(WINDOW_W, WINDOW_H, "Bomberman");
    Simp.set_render_target(window, .LEFT_HANDED);

    path := path_strip_filename(get_path_of_running_executable());
    set_working_directory(path);

    pixel_height := WINDOW_H / 26;
    my_font = Simp.get_font_at_size("data", "Anonymous Pro.ttf", pixel_height);
    if !my_font {
        #if OS == .WINDOWS {
            my_font = Simp.get_font_at_size("C:/Windows/Fonts", "arial.ttf", pixel_height);
        }
    }

    // Audio init. If anything fails we set audio_ready=false and the rest of
    // the game runs silently — play_sfx() short-circuits.
    audio_ready = Sound.sound_player_init(.{});
    if audio_ready {
        sound_explosion = Sound.load_audio_file("data/explosion.wav");
        sound_hit       = Sound.load_audio_file("data/hitHurt.wav");
        sound_powerup   = Sound.load_audio_file("data/powerUp.wav");
    }

    reset_state();

    while !should_quit {
        reset_temporary_storage();
        Input.update_window_events();

        for Input.get_window_resizes() {
            Simp.update_window(it.window);
            if it.window == window {
                window_w_actual = it.width;
                window_h_actual = it.height;
            }
        }

        for event: Input.events_this_frame {
            if event.type == .QUIT {
                should_quit = true;
                break;
            }
            if event.type == .KEYBOARD {
                pressed := event.key_pressed != 0;
                key := event.key_code;
                if key == .ARROW_UP    key_up = pressed;
                if key == .ARROW_DOWN  key_down = pressed;
                if key == .ARROW_LEFT  key_left = pressed;
                if key == .ARROW_RIGHT key_right = pressed;
                if key == cast(Input.Key_Code) #char "W" key_up = pressed;
                if key == cast(Input.Key_Code) #char "S" key_down = pressed;
                if key == cast(Input.Key_Code) #char "A" key_left = pressed;
                if key == cast(Input.Key_Code) #char "D" key_right = pressed;
                if pressed {
                    if key == .SPACEBAR || key == cast(Input.Key_Code) #char "E" place_bomb();
                    if key == cast(Input.Key_Code) #char "Q" punch_bomb();
                    if game_over && key == cast(Input.Key_Code) #char "R" reset_state();
                    // Level select. '1' loads VANILLA, '2' loads VOLCANIC.
                    if key == cast(Input.Key_Code) #char "1" {
                        current_level = .VANILLA;
                        reset_state();
                    }
                    if key == cast(Input.Key_Code) #char "2" {
                        current_level = .VOLCANIC;
                        reset_state();
                    }
                    if key == cast(Input.Key_Code) #char "3" {
                        current_level = .SNOW;
                        reset_state();
                    }
                    if key == cast(Input.Key_Code) #char "4" {
                        current_level = .PIRATE;
                        reset_state();
                    }
                    if key == cast(Input.Key_Code) #char "5" {
                        current_level = .BEACH;
                        reset_state();
                    }
                    if key == .F11 {
                        is_fullscreen = !is_fullscreen;
                        success, w, h := toggle_fullscreen(window, is_fullscreen, *saved_window_info);
                        if success {
                            window_w_actual = w;
                            window_h_actual = h;
                            Simp.update_window(window);
                        }
                    }
                }
                if key == .ESCAPE && pressed should_quit = true;
            }
        }

        update();
        render();
        if audio_ready Sound.update();
        Simp.swap_buffers(window);
        sleep_milliseconds(1);
    }

    if audio_ready Sound.sound_player_shutdown();
}
