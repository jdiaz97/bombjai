#import "Basic";
#import "Math";
#import "Random";
#import "Window_Creation";
Input :: #import "Input";
#import "String";
#import "System";
#import "GL";

Simp :: #import "Simp";

COLS :: 15;
ROWS :: 13;
TILE :: 60;
BOMB_TIMER :: 135;
POWERUP_DROP_RATE :: 0.5;
ENEMY_MOVE_DELAY :: 16;
START_FIRE_RANGE :: 1;
START_MAX_BOMBS :: 1;
ENEMY_FIRE_RANGE :: 1;
EXPLOSION_DURATION :: 20;
MELT_DURATION :: 14;
POWERUP_SPAWN_DELAY :: 35;
POWERUP_MELT_DURATION :: 12;
BRICK_DENSITY :: 0.65;
PLAYER_MOVE_DELAY :: 8;
AI_BOMB_DIST :: 3;
BOMB_SLIDE_SPEED :: 4;
STUN_DURATION :: 60;
KICK_MAX :: 4;
PUNCH_MAX :: 4;
LERP_SPEED :: 0.25;

WINDOW_W :: COLS * TILE;
WINDOW_H :: ROWS * TILE;

Tile :: enum u8 {
    EMPTY;
    WALL;
    BRICK;
    BRICK_MELTING;
}

Dir :: enum u8 {
    UP;
    DOWN;
    LEFT;
    RIGHT;
}

PType :: enum u8 {
    BOMB;
    FIRE;
    KICK;
    PUNCH;
}

Player :: struct {
    x, y: int;
    rx, ry: float;
    max_bombs: int;
    fire_range: int;
    dir: Dir;
    has_kick: bool;
    has_punch: bool;
}

Enemy :: struct {
    x, y: int;
    rx, ry: float;
    alive: bool;
    max_bombs: int;
    fire_range: int;
    move_timer: int;
    color: Vector4;
    glow: Vector4;
    id: int;
    dir: Dir;
    stun_timer: int;
    flee_x, flee_y: int;
    has_flee: bool;
}

Bomb :: struct {
    x, y: int;
    timer: int;
    range: int;
    owner: int; // 0=player, 1-3=enemy id
    slide_dx, slide_dy: int;
    slide_timer: int;
    chain: bool;
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

BFSNode :: struct {
    x, y: int;
}

DIRS :: int.[0, -1, 0, 1, -1, 0, 1, 0]; // pairs (dx, dy) flattened

grid: [ROWS][COLS] Tile;
player: Player;
enemies: [3] Enemy;
powerups: [..] Powerup;
bombs: [..] Bomb;
explosions_list: [..] Explosion;
melting_bricks: [..] MeltingBrick;
melting_powerups: [..] MeltingPowerup;
kick_spawned: int;
punch_spawned: int;

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

col :: (r: float, g: float, b: float, a: float) -> Vector4 {
    return .{r, g, b, a};
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

draw_wall :: (c: int, r: int) {
    x := cast(float)(c * TILE);
    y := cast(float)(r * TILE);
    T := cast(float)TILE;
    draw_filled_rect(x, y, T, T, col(0.243, 0.227, 0.306, 1));
    draw_filled_rect(x + 1, y + 1, T/2 - 2, T/2 - 2, col(0.302, 0.282, 0.376, 1));
    draw_filled_rect(x + T/2 + 1, y + 1, T/2 - 2, T/2 - 2, col(0.302, 0.282, 0.376, 1));
    draw_filled_rect(x + T/4, y + T/2 + 1, T/2, T/2 - 2, col(0.302, 0.282, 0.376, 1));
    draw_filled_rect(x + 1, y + 1, T/2 - 2, 1, col(0.404, 0.380, 0.502, 1));
    draw_filled_rect(x + T/2 + 1, y + 1, T/2 - 2, 1, col(0.404, 0.380, 0.502, 1));
    draw_filled_rect(x + T/4, y + T/2 + 1, T/2, 1, col(0.404, 0.380, 0.502, 1));
    draw_filled_rect(x, y + T/2 - 1, T, 2, col(0.208, 0.192, 0.290, 1));
    draw_filled_rect(x + T/2 - 1, y, 2, T, col(0.208, 0.192, 0.290, 1));
    draw_filled_rect(x, y, T, 1, col(0.173, 0.157, 0.251, 1));
    draw_filled_rect(x, y, 1, T, col(0.173, 0.157, 0.251, 1));
    draw_filled_rect(x, y + T - 3, T, 3, col(0.082, 0.075, 0.137, 0.55));
    draw_filled_rect(x + T - 3, y, 3, T, col(0.082, 0.075, 0.137, 0.45));
}

draw_brick :: (c: int, r: int) {
    x := cast(float)(c * TILE);
    y := cast(float)(r * TILE);
    T := cast(float)TILE;
    draw_filled_rect(x, y, T, T, col(0.478, 0.361, 0.188, 1));
    draw_filled_rect(x + 2, y + 2, T - 4, T - 6, col(0.545, 0.431, 0.243, 1));
    draw_filled_rect(x + 2, y + T - 6, T - 4, 4, col(0.420, 0.306, 0.141, 1));
    draw_filled_rect(x + 2, y + 2, T - 4, 1, col(0.722, 0.580, 0.376, 1));
    draw_filled_rect(x + 2, y + 2, 1, T - 8, col(0.667, 0.529, 0.329, 1));
    draw_stroke_rect(x + 3, y + 3, T - 6, T - 6, col(0.353, 0.239, 0.102, 1), 1);
    draw_line(x + 4, y + T/2, x + T - 4, y + T/2, col(0.353, 0.239, 0.102, 1), 1);
    draw_filled_rect(x + 5, y + 5, 6, 4, col(0.588, 0.471, 0.290, 1));
    draw_filled_rect(x + T - 14, y + T/2 + 3, 6, 4, col(0.588, 0.471, 0.290, 1));
    seed := c * 7 + r * 13;
    draw_filled_rect(x + cast(float)((seed % 12) + 10), y + cast(float)(((seed * 3) % 8) + 14), 8, 3, col(0.369, 0.259, 0.118, 1));
    draw_filled_rect(x, y + T - 3, T, 3, col(0.137, 0.094, 0.039, 0.55));
    draw_filled_rect(x + T - 3, y, 3, T, col(0.137, 0.094, 0.039, 0.45));
}

draw_melting_brick :: (c: int, r: int, m: MeltingBrick) {
    x := cast(float)(c * TILE);
    y := cast(float)(r * TILE);
    T := cast(float)TILE;
    pct := cast(float)m.timer / cast(float)MELT_DURATION;
    shrink := (1 - pct) * 8;
    wob_x := sin(cast(float)frame_count / 2 + cast(float)c * 3) * (1 - pct) * 4;
    wob_y := cos(cast(float)frame_count / 3 + cast(float)r * 5) * (1 - pct) * 3;
    alpha := 0.4 + pct * 0.6;
    draw_filled_rect(x + shrink * 0.5 + wob_x, y + shrink * 0.5 + wob_y, T - shrink, T - shrink, col(0.486, 0.302, 1.0, alpha));
    inner_shrink := shrink + 2;
    draw_filled_rect(x + inner_shrink * 0.5 + wob_x, y + inner_shrink * 0.5 + wob_y, T - inner_shrink, T - inner_shrink, col(0.545, 0.431, 0.243, alpha));
    draw_filled_rect(x + wob_x, y + wob_y, T, T, col(0.486, 0.302, 1.0, (1 - pct) * 0.6));
}

draw_floor :: (c: int, r: int) {
    x := cast(float)(c * TILE);
    y := cast(float)(r * TILE);
    T := cast(float)TILE;
    if (r + c) % 2 == 0 {
        draw_filled_rect(x, y, T, T, col(0.165, 0.153, 0.251, 1));
        draw_filled_rect(x + 1, y + 1, T - 2, T - 2, col(0.145, 0.133, 0.220, 1));
    } else {
        draw_filled_rect(x, y, T, T, col(0.188, 0.176, 0.282, 1));
        draw_filled_rect(x + 1, y + 1, T - 2, T - 2, col(0.169, 0.157, 0.267, 1));
    }
    seed := c * 131 + r * 977;
    sx := x + cast(float)(seed % 40) + 6;
    sy := y + cast(float)((seed / 7) % 40) + 6;
    draw_filled_circle(sx, sy, 1.2, col(0.302, 0.282, 0.451, 0.55), 6);
    if (seed % 5) == 0 {
        twinkle := 0.4 + (sin(cast(float)frame_count / 30.0 + cast(float)seed) + 1) * 0.25;
        draw_filled_circle(sx + 12, sy + 8, 0.8, col(0.612, 0.502, 0.871, twinkle), 6);
    }
}

draw_player_char :: () {
    px := player.rx * cast(float)TILE;
    py := player.ry * cast(float)TILE;
    cx := px + cast(float)TILE / 2;
    cy := py + cast(float)TILE / 2;
    d := player.dir;

    bob := sin(cast(float)frame_count / 12.0) * 0.6;
    cyb := cy + bob;

    glow_pulse := 0.55 + sin(cast(float)frame_count / 18.0) * 0.15;
    draw_filled_ellipse(cx, cy + cast(float)TILE/2 - 4, 28, 9, col(0.353, 0.604, 0.965, 0.20 * glow_pulse));
    draw_filled_ellipse(cx, cy + cast(float)TILE/2 - 4, 18, 6, col(0.565, 0.792, 0.976, 0.30 * glow_pulse));
    draw_filled_ellipse(cx, cy + cast(float)TILE/2 - 2, 14, 5, col(0, 0, 0, 0.35));

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
    if d != .UP {
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

draw_enemy_char :: (e: *Enemy) {
    if !e.alive return;
    px := e.rx * cast(float)TILE;
    py := e.ry * cast(float)TILE;
    cx := px + cast(float)TILE / 2;
    cy := py + cast(float)TILE / 2;
    d := e.dir;

    bob := sin(cast(float)frame_count / 11.0 + cast(float)e.id) * 0.5;
    cyb := cy + bob;

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

    draw_filled_ellipse(cx, cy + cast(float)TILE/2 - 4, 22, 7, col(e.glow.x, e.glow.y, e.glow.z, 0.16));
    draw_filled_ellipse(cx, cy + cast(float)TILE/2 - 2, 13, 4, col(0, 0, 0, 0.35));

    draw_triangle(cx - 16, cyb + 22, cx - 8, cyb + 2, cx + 8, cyb + 2, robe_dark);
    draw_triangle(cx - 16, cyb + 22, cx + 8, cyb + 2, cx + 16, cyb + 22, robe_dark);
    draw_triangle(cx - 13, cyb + 20, cx - 6, cyb + 3, cx + 6, cyb + 3, robe_mid);
    draw_triangle(cx - 13, cyb + 20, cx + 6, cyb + 3, cx + 13, cyb + 20, robe_mid);
    draw_filled_rect(cx - 10, cyb + 10, 20, 3, robe_dark);

    draw_filled_circle(cx - 1, cyb - 7, 11, skin, 14);
    draw_filled_circle(cx + 2, cyb - 9, 4, col(1, 1, 1, 0.10), 8);

    if e.id == 1 {
        draw_triangle(cx - 9, cyb - 14, cx - 5, cyb - 14, cx - 12, cyb - 22, col(0.137, 0.039, 0.039, 1));
        draw_triangle(cx + 5, cyb - 14, cx + 9, cyb - 14, cx + 12, cyb - 22, col(0.137, 0.039, 0.039, 1));
        draw_triangle(cx - 11, cyb - 16, cx, cyb - 19, cx + 11, cyb - 16, col(0.137, 0.039, 0.039, 1));
    } else if e.id == 2 {
        hat_d := col(0.110, 0.027, 0.220, 1);
        hat_m := col(0.247, 0.078, 0.443, 1);
        if d == .LEFT {
            draw_filled_rect(cx - 14, cyb - 14, 26, 4, hat_d);
            draw_triangle(cx + 12, cyb - 14, cx - 14, cyb - 14, cx - 16, cyb - 34, hat_m);
        } else if d == .RIGHT {
            draw_filled_rect(cx - 12, cyb - 14, 26, 4, hat_d);
            draw_triangle(cx - 12, cyb - 14, cx + 14, cyb - 14, cx + 16, cyb - 34, hat_m);
        } else {
            draw_filled_rect(cx - 13, cyb - 14, 26, 4, hat_d);
            draw_triangle(cx - 13, cyb - 14, cx + 13, cyb - 14, cx, cyb - 36, hat_m);
            draw_filled_circle(cx, cyb - 36, 2.2, col(0.918, 0.502, 0.988, 1), 8);
        }
    } else if e.id == 3 {
        hood_d := col(0.043, 0.149, 0.055, 1);
        hood_m := col(0.094, 0.282, 0.106, 1);
        draw_triangle(cx - 15, cyb + 4, cx - 14, cyb - 16, cx, cyb - 18, hood_d);
        draw_triangle(cx - 15, cyb + 4, cx, cyb - 18, cx + 15, cyb + 4, hood_d);
        draw_triangle(cx + 15, cyb + 4, cx + 14, cyb - 16, cx, cyb - 18, hood_d);
        draw_triangle(cx - 12, cyb + 2, cx - 11, cyb - 13, cx, cyb - 15, hood_m);
        draw_triangle(cx + 12, cyb + 2, cx + 11, cyb - 13, cx, cyb - 15, hood_m);
        draw_filled_circle(cx, cyb - 6, 9, col(0.157, 0.106, 0.157, 1), 12);
    }

    eye_y: float;
    if d == .UP eye_y = cyb - 7; else eye_y = cyb - 5;
    if e.id == 3 {
        draw_filled_circle(cx - 5, eye_y, 2.5, e.glow, 8);
        draw_filled_circle(cx + 5, eye_y, 2.5, e.glow, 8);
        draw_filled_circle(cx - 5, eye_y, 1.4, col(1, 1, 1, 1), 6);
        draw_filled_circle(cx + 5, eye_y, 1.4, col(1, 1, 1, 1), 6);
    } else {
        draw_filled_circle(cx - 5, eye_y, 4.5, col(1, 1, 1, 1), 10);
        draw_filled_circle(cx + 5, eye_y, 4.5, col(1, 1, 1, 1), 10);
        draw_filled_circle(cx - 5, eye_y, 2.6, e.color, 8);
        draw_filled_circle(cx + 5, eye_y, 2.6, e.color, 8);
        draw_filled_circle(cx - 5, eye_y, 1.2, e.glow, 6);
        draw_filled_circle(cx + 5, eye_y, 1.2, e.glow, 6);
        draw_filled_circle(cx - 4, eye_y - 1, 0.7, col(1, 1, 1, 1), 4);
        draw_filled_circle(cx + 6, eye_y - 1, 0.7, col(1, 1, 1, 1), 4);
    }

    if e.id == 1 && d != .UP {
        draw_triangle(cx - 2, cyb - 1, cx - 4, cyb + 2, cx - 1, cyb + 2, col(1, 1, 1, 0.9));
        draw_triangle(cx + 2, cyb - 1, cx + 4, cyb + 2, cx + 1, cyb + 2, col(1, 1, 1, 0.9));
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

draw_bomb :: (b: Bomb) {
    bx := cast(float)(b.x * TILE) + cast(float)TILE / 2;
    by := cast(float)(b.y * TILE) + cast(float)TILE / 2;
    pct_left := cast(float)b.timer / cast(float)BOMB_TIMER;
    pulse := sin(cast(float)frame_count / 4.0) * (3 + (1 - pct_left) * 4);
    r := 11 + pulse;

    draw_filled_ellipse(bx, by + r + 2, r, 3, col(0, 0, 0, 0.2));
    draw_filled_circle(bx, by, r, col(0.486, 0.302, 1.0, 1), 16);
    draw_filled_circle(bx - r * 0.3, by - r * 0.3, r * 0.3, col(0.702, 0.533, 1.0, 0.4), 8);

    if sin(cast(float)frame_count / 3.0) > 0 {
        draw_filled_circle(bx, by - r - 4 + sin(cast(float)frame_count / 5.0) * 3, 3, col(0.882, 0.745, 0.906, 1), 6);
        draw_filled_circle(bx, by - r - 5 + sin(cast(float)frame_count / 5.0) * 3, 1.5, col(1, 1, 1, 1), 4);
    }
}

draw_explosion :: (e: Explosion) {
    ex := cast(float)(e.x * TILE) + cast(float)TILE / 2;
    ey := cast(float)(e.y * TILE) + cast(float)TILE / 2;
    progress := 1 - cast(float)e.timer / cast(float)e.duration;
    alpha := min(1.0, cast(float)e.timer / cast(float)e.duration + 0.2);
    size := cast(float)TILE - 4 + sin(progress * PI) * 8;

    if e.origin {
        for i: 0..7 {
            ray_angle := (cast(float)i / 8.0) * TAU + progress * 0.6;
            ray_len := size * 0.55 + sin(progress * PI) * 6;
            rx := ex + cos(ray_angle) * ray_len;
            ry := ey + sin(ray_angle) * ray_len;
            draw_line(ex, ey, rx, ry, col(1.0, 0.929, 0.804, alpha * 0.5), 2);
        }
        draw_filled_circle(ex, ey, size / 2, col(0.882, 0.745, 0.906, alpha), 16);
        draw_filled_circle(ex, ey, size / 2 - 3, col(0.702, 0.533, 1.0, alpha), 16);
        draw_filled_circle(ex, ey, size / 2 - 8, col(0.820, 0.769, 0.914, alpha), 16);
        draw_filled_circle(ex, ey, size / 3, col(1, 1, 1, alpha), 16);
    } else {
        draw_filled_circle(ex, ey, size / 2, col(0.486, 0.302, 1.0, alpha), 16);
        draw_filled_circle(ex, ey, size / 2 - 4, col(0.702, 0.533, 1.0, alpha), 16);
        draw_filled_circle(ex, ey, size / 2 - 10, col(0.882, 0.745, 0.906, alpha), 16);
        draw_filled_circle(ex, ey, size / 4 - 2, col(1, 1, 1, alpha), 8);
    }
}

draw_powerup :: (p: Powerup) {
    if p.delay > 0 return;
    px := cast(float)(p.x * TILE);
    py := cast(float)(p.y * TILE);
    cx := px + cast(float)TILE / 2;
    cy := py + cast(float)TILE / 2;
    pulse := sin(cast(float)frame_count / 15.0) * 2;
    bob := sin(cast(float)frame_count / 20.0) * 2;

    if p.type == {
        case .BOMB;
            draw_triangle(cx, cy - 14 - pulse + bob, cx - 10, cy - 2 + bob, cx + 10, cy - 2 + bob, col(0.290, 0.078, 0.549, 1));
            draw_triangle(cx, cy - 10 - pulse + bob, cx - 7, cy + bob, cx + 7, cy + bob, col(0.486, 0.302, 1.0, 1));
            draw_triangle(cx, cy - 8 + bob, cx - 4, cy + 8 + bob, cx + 4, cy + 8 + bob, col(0.702, 0.533, 1.0, 1));
        case .FIRE;
            draw_rounded_rect(cx - 4, cy + bob - 14 - pulse, 8, 12, 2, col(0.365, 0.251, 0.216, 1));
            draw_rounded_rect(cx - 6, cy + bob - 4 - pulse, 12, 8, 2, col(1.0, 0.435, 0, 1));
            draw_rounded_rect(cx - 4, cy + bob - 2 - pulse, 8, 4, 1, col(1.0, 0.671, 0.251, 1));
        case .KICK;
            draw_triangle(cx, cy + bob - 14 - pulse, cx - 10, cy + bob + 2, cx + 10, cy + bob + 2, col(0, 0.376, 0.392, 1));
            draw_triangle(cx, cy + bob - 10 - pulse, cx - 6, cy + bob + 2, cx + 6, cy + bob + 2, col(0, 0.737, 0.827, 1));
        case .PUNCH;
            draw_filled_circle(cx, cy + bob - pulse, 10, col(0.498, 0.376, 0, 1), 12);
            draw_filled_circle(cx, cy + bob - pulse, 7, col(1.0, 0.757, 0.027, 1), 12);
            for i: 0..5 {
                angle := (cast(float)i / 6.0) * TAU + cast(float)frame_count / 40.0;
                sx := cx + cos(angle) * 12;
                sy := cy + bob - pulse + sin(angle) * 12;
                draw_filled_circle(sx, sy, 2, col(1.0, 0.878, 0.510, 1), 4);
            }
    }
}

draw_melting_powerup :: (m: MeltingPowerup) {
    px := cast(float)(m.x * TILE);
    py := cast(float)(m.y * TILE);
    cx := px + cast(float)TILE / 2;
    cy := py + cast(float)TILE / 2;
    pct := cast(float)m.timer / cast(float)POWERUP_MELT_DURATION;
    shrink := (1 - pct) * 14;
    h := 16 - shrink;
    dark_c, mid_c, light_c: Vector4;
    if m.type == {
        case .BOMB;
            dark_c = col(0.290, 0.078, 0.549, pct);
            mid_c = col(0.486, 0.302, 1.0, pct);
            light_c = col(0.702, 0.533, 1.0, (1 - pct) * 0.5);
        case .KICK;
            dark_c = col(0, 0.376, 0.392, pct);
            mid_c = col(0, 0.737, 0.827, pct);
            light_c = col(0.502, 0.871, 0.918, (1 - pct) * 0.5);
        case .PUNCH;
            dark_c = col(0.498, 0.376, 0, pct);
            mid_c = col(1.0, 0.757, 0.027, pct);
            light_c = col(1.0, 0.878, 0.510, (1 - pct) * 0.5);
        case .FIRE;
            dark_c = col(0.365, 0.251, 0.216, pct);
            mid_c = col(1.0, 0.435, 0, pct);
            light_c = col(1.0, 0.671, 0.251, (1 - pct) * 0.5);
    }

    draw_filled_rect(cx - h/2, cy - h/2, h, h, dark_c);
    draw_filled_rect(cx - h/2 + 2, cy - h/2 + 2, h - 4, h - 4, mid_c);
    draw_filled_circle(cx, cy, (1 - pct) * 6, light_c, 8);
}

place_bomb :: () {
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
}

explode :: (b: Bomb) {
    e: Explosion;
    e.x = b.x; e.y = b.y;
    e.timer = EXPLOSION_DURATION;
    e.duration = EXPLOSION_DURATION;
    e.origin = true;
    array_add(*explosions_list, e);

    for dir_idx: 0..3 {
        dx := DIRS[dir_idx * 2];
        dy := DIRS[dir_idx * 2 + 1];
        for i: 1..b.range {
            nx := b.x + dx * i;
            ny := b.y + dy * i;
            if nx < 0 || nx >= COLS || ny < 0 || ny >= ROWS break;
            if grid[ny][nx] == .WALL || grid[ny][nx] == .BRICK_MELTING break;

            hit_bomb := false;
            for * bombs {
                if it.x == nx && it.y == ny {
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

                if !b.chain && random_get_zero_to_one() < POWERUP_DROP_RATE {
                    r := random_get_zero_to_one();
                    ptype: PType;
                    if r < 0.38 ptype = .BOMB;
                    else if r < 0.76 ptype = .FIRE;
                    else if r < 0.88 {
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
                if grid[ny][nx] == .WALL || grid[ny][nx] == .BRICK_MELTING break;
                if nx == x && ny == y return true;
                if grid[ny][nx] == .BRICK break;
            }
        }
        return false;
    }

    for bombs if check(it.x, it.y, it.range, x, y) return true;
    for extra if check(it.x, it.y, it.range, x, y) return true;
    return false;
}

can_walk_safe :: (x: int, y: int) -> bool {
    if x < 0 || x >= COLS || y < 0 || y >= ROWS return false;
    if grid[y][x] != .EMPTY return false;
    for bombs if it.x == x && it.y == y return false;
    return true;
}

bfs_path :: (sx: int, sy: int, tx: int, ty: int) -> [..] BFSNode {
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
            if !(nx == tx && ny == ty) && !can_walk_safe(nx, ny) continue;
            if nx == tx && ny == ty && grid[ny][nx] != .EMPTY {
                // Allow ending on the target if it's only blocked by a bomb (we accept colliding)
            }
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

find_nearest_target :: (e: *Enemy) -> bool, int, int {
    best_x := -1;
    best_y := -1;
    best_score := 999999;

    d := abs(e.x - player.x) + abs(e.y - player.y);
    if d < best_score {
        best_score = d;
        best_x = player.x;
        best_y = player.y;
    }

    for * other: enemies {
        if other != e && other.alive {
            d2 := abs(e.x - other.x) + abs(e.y - other.y);
            if d2 < best_score {
                best_score = d2;
                best_x = other.x;
                best_y = other.y;
            }
        }
    }

    for powerups {
        if it.delay > 0 continue;
        d2 := abs(e.x - it.x) + abs(e.y - it.y) - 4;
        if d2 < best_score {
            best_score = d2;
            best_x = it.x;
            best_y = it.y;
        }
    }

    return best_x >= 0, best_x, best_y;
}

set_enemy_dir :: (e: *Enemy, dx: int, dy: int) {
    if dy < 0 e.dir = .UP;
    else if dy > 0 e.dir = .DOWN;
    else if dx < 0 e.dir = .LEFT;
    else if dx > 0 e.dir = .RIGHT;
}

enemy_needs_flee :: (e: *Enemy, extra: [] Bomb = .[]) -> bool {
    if is_in_blast(e.x, e.y, extra) return true;
    for bombs {
        if it.owner == e.id && abs(e.x - it.x) + abs(e.y - it.y) <= it.range + 2 return true;
    }
    for extra {
        if abs(e.x - it.x) + abs(e.y - it.y) <= it.range + 2 return true;
    }
    return false;
}

enemy_do_flee_step :: (e: *Enemy) {
    if e.has_flee && e.flee_x >= 0 && e.flee_y >= 0 && can_walk_safe(e.flee_x, e.flee_y) && !is_in_blast(e.flee_x, e.flee_y) {
        path := bfs_path(e.x, e.y, e.flee_x, e.flee_y);
        if path.count > 0 {
            set_enemy_dir(e, path[0].x - e.x, path[0].y - e.y);
            e.x = path[0].x; e.y = path[0].y;
            return;
        }
    }
    found, sx, sy := find_safe_cell(e.x, e.y);
    if found {
        e.flee_x = sx;
        e.flee_y = sy;
        e.has_flee = true;
        path := bfs_path(e.x, e.y, sx, sy);
        if path.count > 0 {
            set_enemy_dir(e, path[0].x - e.x, path[0].y - e.y);
            e.x = path[0].x; e.y = path[0].y;
            return;
        }
    }
    best_dir_idx := -1;
    best_dist := -1;
    for dir_idx: 0..3 {
        nx := e.x + DIRS[dir_idx * 2];
        ny := e.y + DIRS[dir_idx * 2 + 1];
        if !can_walk_safe(nx, ny) continue;
        min_bomb_dist := 999999;
        for bombs {
            bd := abs(nx - it.x) + abs(ny - it.y);
            if bd < min_bomb_dist min_bomb_dist = bd;
        }
        if min_bomb_dist > best_dist {
            best_dist = min_bomb_dist;
            best_dir_idx = dir_idx;
        }
    }
    if best_dir_idx >= 0 {
        dx := DIRS[best_dir_idx * 2];
        dy := DIRS[best_dir_idx * 2 + 1];
        set_enemy_dir(e, dx, dy);
        e.x += dx;
        e.y += dy;
    }
}

enemy_move_random_safe :: (e: *Enemy) {
    safe_dir_idx: [4] int;
    safe_count := 0;
    for dir_idx: 0..3 {
        nx := e.x + DIRS[dir_idx * 2];
        ny := e.y + DIRS[dir_idx * 2 + 1];
        if can_walk_safe(nx, ny) && !is_in_blast(nx, ny) {
            safe_dir_idx[safe_count] = dir_idx;
            safe_count += 1;
        }
    }
    if safe_count > 0 {
        pick := cast(int)(random_get() % cast(u64) safe_count);
        idx := safe_dir_idx[pick];
        dx := DIRS[idx * 2];
        dy := DIRS[idx * 2 + 1];
        set_enemy_dir(e, dx, dy);
        e.x += dx;
        e.y += dy;
    }
}

enemy_try_place_bomb :: (e: *Enemy, active_bombs: int, max_escape_steps: int) -> bool {
    if active_bombs >= e.max_bombs return false;
    if is_in_blast(e.x, e.y) return false;
    sim: [1] Bomb;
    sim[0].x = e.x; sim[0].y = e.y; sim[0].range = e.fire_range; sim[0].owner = e.id; sim[0].timer = BOMB_TIMER;
    found, sx, sy := find_safe_cell(e.x, e.y, sim);
    if !found return false;
    path := bfs_path(e.x, e.y, sx, sy);
    if path.count == 0 || path.count > max_escape_steps return false;
    b: Bomb;
    b.x = e.x; b.y = e.y; b.timer = BOMB_TIMER; b.range = e.fire_range; b.owner = e.id;
    array_add(*bombs, b);
    return true;
}

update_single_enemy :: (e: *Enemy) {
    if !e.alive return;
    if e.stun_timer > 0 {
        e.stun_timer -= 1;
        return;
    }
    e.move_timer -= 1;
    if e.move_timer > 0 return;
    e.move_timer = ENEMY_MOVE_DELAY;

    max_escape_steps := BOMB_TIMER / ENEMY_MOVE_DELAY - 2;

    if enemy_needs_flee(e) {
        enemy_do_flee_step(e);
        return;
    }

    e.has_flee = false;
    near_own_bomb := false;
    for bombs {
        if it.owner == e.id && abs(e.x - it.x) + abs(e.y - it.y) <= it.range + 2 {
            near_own_bomb = true;
            break;
        }
    }
    if near_own_bomb {
        enemy_do_flee_step(e);
        return;
    }

    active_bombs := 0;
    for bombs if it.owner == e.id active_bombs += 1;

    has_target, tx, ty := find_nearest_target(e);

    if !has_target {
        enemy_move_random_safe(e);
        return;
    }

    path := bfs_path(e.x, e.y, tx, ty);

    if path.count > 0 {
        next_step := path[0];
        if is_in_blast(next_step.x, next_step.y) {
            enemy_move_random_safe(e);
            return;
        }
        set_enemy_dir(e, next_step.x - e.x, next_step.y - e.y);
        e.x = next_step.x; e.y = next_step.y;
        dist := abs(e.x - tx) + abs(e.y - ty);
        if dist <= e.fire_range && dist > 0 && active_bombs < e.max_bombs {
            enemy_try_place_bomb(e, active_bombs, max_escape_steps);
        }
    } else {
        has_adj_brick := false;
        for dir_idx: 0..3 {
            nx := e.x + DIRS[dir_idx * 2];
            ny := e.y + DIRS[dir_idx * 2 + 1];
            if nx >= 0 && nx < COLS && ny >= 0 && ny < ROWS && grid[ny][nx] == .BRICK {
                has_adj_brick = true;
                break;
            }
        }
        if has_adj_brick {
            enemy_try_place_bomb(e, active_bombs, max_escape_steps);
        } else {
            enemy_move_random_safe(e);
        }
    }
}

move_player :: (dx: int, dy: int) {
    nx := player.x + dx;
    ny := player.y + dy;
    if nx < 0 || nx >= COLS || ny < 0 || ny >= ROWS return;
    if grid[ny][nx] != .EMPTY return;

    bomb_idx := -1;
    for bombs {
        if it.x == nx && it.y == ny {
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
                for bombs if it_index != bomb_idx && it.x == sx && it.y == sy blocked = true;
                if !blocked {
                    b.x = sx;
                    b.y = sy;
                    b.slide_dx = dx;
                    b.slide_dy = dy;
                    b.slide_timer = BOMB_SLIDE_SPEED;
                    player.x = nx;
                    player.y = ny;
                }
            }
        }
        return;
    }

    player.x = nx;
    player.y = ny;
}

punch_bomb :: () {
    if !player.has_punch return;
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
        if it.x == bx && it.y == by && it.slide_dx == 0 && it.slide_dy == 0 {
            bomb_idx = it_index;
            break;
        }
    }
    if bomb_idx < 0 return;
    b := *bombs[bomb_idx];

    tx := b.x + ddx * 2;
    ty := b.y + ddy * 2;
    if tx >= 0 && tx < COLS && ty >= 0 && ty < ROWS && grid[ty][tx] == .EMPTY {
        blocked := false;
        for bombs if it_index != bomb_idx && it.x == tx && it.y == ty blocked = true;
        if !blocked {
            for * enemies {
                if it.alive && it.x == tx && it.y == ty it.stun_timer = STUN_DURATION;
            }
            b.x = tx; b.y = ty;
            return;
        }
    }

    MAX_DIM :: 15;
    for i: 1..MAX_DIM {
        cx := tx - ddx * i;
        cy := ty - ddy * i;
        if cx < 0 || cx >= COLS || cy < 0 || cy >= ROWS break;
        if grid[cy][cx] == .WALL || grid[cy][cx] == .BRICK || grid[cy][cx] == .BRICK_MELTING break;
        if grid[cy][cx] == .EMPTY {
            blocked2 := false;
            for bombs if it_index != bomb_idx && it.x == cx && it.y == cy blocked2 = true;
            if !blocked2 {
                for * enemies {
                    if it.alive && it.x == cx && it.y == cy it.stun_timer = STUN_DURATION;
                }
                b.x = cx; b.y = cy;
                return;
            }
        }
    }
}

update :: () {
    if game_over return;
    frame_count += 1;

    player.rx += (cast(float)player.x - player.rx) * LERP_SPEED;
    player.ry += (cast(float)player.y - player.ry) * LERP_SPEED;
    if abs(cast(float)player.x - player.rx) < 0.01 player.rx = cast(float)player.x;
    if abs(cast(float)player.y - player.ry) < 0.01 player.ry = cast(float)player.y;

    for * enemies {
        if !it.alive continue;
        it.rx += (cast(float)it.x - it.rx) * LERP_SPEED;
        it.ry += (cast(float)it.y - it.ry) * LERP_SPEED;
        if abs(cast(float)it.x - it.rx) < 0.01 it.rx = cast(float)it.x;
        if abs(cast(float)it.y - it.ry) < 0.01 it.ry = cast(float)it.y;
    }

    move_timer -= 1;
    if move_timer <= 0 {
        moved := false;
        if key_up { move_player(0, -1); moved = true; player.dir = .UP; }
        else if key_down { move_player(0, 1); moved = true; player.dir = .DOWN; }
        else if key_left { move_player(-1, 0); moved = true; player.dir = .LEFT; }
        else if key_right { move_player(1, 0); moved = true; player.dir = .RIGHT; }
        if moved move_timer = PLAYER_MOVE_DELAY;
    }

    // Update bomb timers and trigger explosions
    {
        i := bombs.count - 1;
        while i >= 0 {
            bombs[i].timer -= 1;
            if bombs[i].timer <= 0 {
                b := bombs[i];
                array_unordered_remove_by_index(*bombs, i);
                explode(b);
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
        if it.x == player.x && it.y == player.y {
            game_over = true;
            player_won = false;
        }
        for * en: enemies {
            if en.alive && it.x == en.x && it.y == en.y en.alive = false;
        }
    }

    all_dead := true;
    for enemies if it.alive { all_dead = false; break; }
    if all_dead {
        game_over = true;
        player_won = true;
    }

    // Powerups pickup / explosion damage
    {
        i := powerups.count - 1;
        while i >= 0 {
            p := *powerups[i];
            if p.delay > 0 {
                p.delay -= 1;
                i -= 1;
                continue;
            }
            in_explosion := false;
            for explosions_list if it.x == p.x && it.y == p.y { in_explosion = true; break; }
            if in_explosion {
                mp: MeltingPowerup;
                mp.x = p.x; mp.y = p.y; mp.type = p.type; mp.timer = POWERUP_MELT_DURATION;
                array_add(*melting_powerups, mp);
                array_unordered_remove_by_index(*powerups, i);
                i -= 1;
                continue;
            }
            if p.x == player.x && p.y == player.y {
                if p.type == .BOMB player.max_bombs += 1;
                else if p.type == .FIRE player.fire_range += 1;
                else if p.type == .KICK player.has_kick = true;
                else if p.type == .PUNCH player.has_punch = true;
                array_unordered_remove_by_index(*powerups, i);
                i -= 1;
                continue;
            }
            picked := false;
            for * en: enemies {
                if en.alive && p.x == en.x && p.y == en.y {
                    if p.type == .BOMB en.max_bombs += 1;
                    else if p.type == .FIRE en.fire_range += 1;
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

draw_hud :: () {
    bx := 8.0; by := 8.0; bw := 280.0; bh := 40.0;
    draw_rounded_rect(bx, by, bw, bh, 8, col(0.078, 0.063, 0.141, 0.85));

    ty := by + bh / 2 - 7;

    draw_filled_circle(bx + 18, by + bh / 2, 6, col(0.702, 0.533, 1.0, 1), 8);
    draw_filled_circle(bx + 18, by + bh / 2, 4, col(0.486, 0.302, 1.0, 1), 8);
    draw_text(tprint("%", player.max_bombs), cast(int)(bx + 28), cast(int) ty, col(0.882, 0.745, 0.906, 1));

    draw_filled_circle(bx + 55, by + bh / 2, 6, col(1.0, 0.671, 0.251, 1), 8);
    draw_text(tprint("%", player.fire_range), cast(int)(bx + 68), cast(int) ty, col(1.0, 0.878, 0.706, 1));

    if player.has_kick {
        draw_filled_circle(bx + 105, by + bh / 2, 6, col(0, 0.737, 0.827, 1), 8);
        draw_text("KICK", cast(int)(bx + 115), cast(int) ty, col(0.698, 0.922, 0.949, 1));
    }

    if player.has_punch {
        px_hud := ifx player.has_kick then bx + 170 else bx + 105;
        draw_filled_circle(px_hud, by + bh / 2, 6, col(1.0, 0.757, 0.027, 1), 8);
        draw_text("PNCH", cast(int)(px_hud + 10), cast(int) ty, col(1.0, 0.976, 0.769, 1));
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

render :: () {
    apply_letterbox();
    Simp.set_shader_for_color(enable_blend=true);
    Simp.immediate_set_2d_projection(WINDOW_W, WINDOW_H);
    draw_filled_rect(0, 0, cast(float)WINDOW_W, cast(float)WINDOW_H, col(0.086, 0.078, 0.165, 1));

    for r: 0..ROWS-1 {
        for c: 0..COLS-1 {
            if grid[r][c] == .WALL draw_wall(c, r);
            else if grid[r][c] == .BRICK draw_brick(c, r);
            else if grid[r][c] == .BRICK_MELTING {
                for melting_bricks {
                    if it.x == c && it.y == r {
                        draw_melting_brick(c, r, it);
                        break;
                    }
                }
            } else {
                draw_floor(c, r);
            }
        }
    }

    for powerups draw_powerup(it);
    for melting_powerups draw_melting_powerup(it);
    for bombs draw_bomb(it);
    for explosions_list draw_explosion(it);

    draw_player_char();
    for * enemies draw_enemy_char(it);

    Simp.immediate_flush();
    Simp.set_shader_for_text();
    Simp.immediate_set_2d_projection(WINDOW_W, WINDOW_H);
    draw_hud();
    Simp.immediate_flush();

    if game_over {
        Simp.set_shader_for_color(enable_blend=true);
        Simp.immediate_set_2d_projection(WINDOW_W, WINDOW_H);
        draw_filled_rect(0, 0, cast(float)WINDOW_W, cast(float)WINDOW_H, col(0.039, 0.031, 0.094, 0.8));
        Simp.immediate_flush();
        Simp.set_shader_for_text();
        Simp.immediate_set_2d_projection(WINDOW_W, WINDOW_H);

        cy := cast(float)WINDOW_H / 2;
        text_color: Vector4;
        if player_won {
            text_color = col(0.486, 0.302, 1.0, 1);
        } else {
            text_color = col(0.957, 0.263, 0.212, 1);
        }

        msg := ifx player_won then "VICTORY" else "DEFEATED";
        if my_font {
            tw := Simp.prepare_text(my_font, msg);
            Simp.draw_prepared_text(my_font, (WINDOW_W - tw) / 2, cast(s64)(cy - 20), text_color);

            restart_text := "Press R to restart";
            tw2 := Simp.prepare_text(my_font, restart_text);
            Simp.draw_prepared_text(my_font, (WINDOW_W - tw2) / 2, cast(s64)(cy + 30), col(1, 1, 1, 0.7));
        }
        Simp.immediate_flush();
    }
}

reset_state :: () {
    init_grid();
    player.x = 1; player.y = 1; player.rx = 1; player.ry = 1;
    player.max_bombs = START_MAX_BOMBS; player.fire_range = START_FIRE_RANGE;
    player.dir = .DOWN; player.has_kick = false; player.has_punch = false;

    enemies[0].x = COLS - 2; enemies[0].y = ROWS - 2;
    enemies[0].rx = cast(float)(COLS - 2); enemies[0].ry = cast(float)(ROWS - 2);
    enemies[0].alive = true; enemies[0].max_bombs = START_MAX_BOMBS;
    enemies[0].fire_range = ENEMY_FIRE_RANGE; enemies[0].move_timer = 0;
    enemies[0].color = col(0.718, 0.110, 0.110, 1);
    enemies[0].glow = col(1.0, 0.090, 0.267, 1);
    enemies[0].id = 1; enemies[0].dir = .LEFT; enemies[0].stun_timer = 0;
    enemies[0].flee_x = -1; enemies[0].flee_y = -1; enemies[0].has_flee = false;

    enemies[1].x = COLS - 2; enemies[1].y = 1;
    enemies[1].rx = cast(float)(COLS - 2); enemies[1].ry = 1;
    enemies[1].alive = true; enemies[1].max_bombs = START_MAX_BOMBS;
    enemies[1].fire_range = ENEMY_FIRE_RANGE; enemies[1].move_timer = 0;
    enemies[1].color = col(0.290, 0.078, 0.549, 1);
    enemies[1].glow = col(0.918, 0.502, 0.988, 1);
    enemies[1].id = 2; enemies[1].dir = .DOWN; enemies[1].stun_timer = 0;
    enemies[1].flee_x = -1; enemies[1].flee_y = -1; enemies[1].has_flee = false;

    enemies[2].x = 1; enemies[2].y = ROWS - 2;
    enemies[2].rx = 1; enemies[2].ry = cast(float)(ROWS - 2);
    enemies[2].alive = true; enemies[2].max_bombs = START_MAX_BOMBS;
    enemies[2].fire_range = ENEMY_FIRE_RANGE; enemies[2].move_timer = 0;
    enemies[2].color = col(0.106, 0.369, 0.125, 1);
    enemies[2].glow = col(0.412, 0.941, 0.678, 1);
    enemies[2].id = 3; enemies[2].dir = .RIGHT; enemies[2].stun_timer = 0;
    enemies[2].flee_x = -1; enemies[2].flee_y = -1; enemies[2].has_flee = false;

    array_reset(*bombs);
    array_reset(*explosions_list);
    array_reset(*powerups);
    array_reset(*melting_bricks);
    array_reset(*melting_powerups);
    kick_spawned = 0;
    punch_spawned = 0;
    game_over = false;
    player_won = false;
    move_timer = 0;
    frame_count = 0;
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
        Simp.swap_buffers(window);
        sleep_milliseconds(1);
    }
}
