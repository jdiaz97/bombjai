# Jai for AI agents

**Goal of this file:** get a model that has never seen Jai productive in this repo in ~5 minutes. The language is post-2024 and rare in training data, so don't pattern-match from C/Go/Rust. **Anchor on `game.jai`** — it's a ~2000-line, working, idiomatic example covering structs, enums, dynamic arrays, polymorphism-free generics, immediate-mode rendering, file I/O, OS interop, and the full game-loop pattern. When you're unsure how something is done in Jai, grep `game.jai` first.

When this file isn't enough, see [Where to look](#where-to-look).

---

## Mental model

- **`::` declares constants and procedures.** `FOO :: 60;` makes a compile-time int constant. `f :: (x: int) -> int { return x*2; }` is a procedure. There is no `fn`, no `func`, no `def`.
- **`:=` declares a variable** with inferred type. `x := 5;` is an `int` local. `x: float = 5;` is the explicit form.
- **`=` is assignment** (not declaration).
- Structs, enums, and procedures are all just constants with that syntax: `Foo :: struct { ... }`, `Bar :: enum { A; B; }`, `do_thing :: () { ... }`.
- A file is a translation unit. Stick everything top-level; you don't need a `main` package, just a top-level `main :: () { ... }`.

```jai
// Module-level constants
TILE :: 60;
MAX_BOMBS :: 4;

// Types
Bomb :: struct {
    x, y: int;
    timer: int;
    range: int;
}

Dir :: enum u8 { UP; DOWN; LEFT; RIGHT; }

// Globals — module-level vars use `:` or `:=`
bombs: [..] Bomb;
player_x: int = 1;

// Procedures
add :: (a: int, b: int) -> int { return a + b; }

main :: () {
    // local var
    counter := 0;
    counter += 1;
}
```

---

## Types you'll actually use

| Type | What it is | Notes |
|---|---|---|
| `int`, `s32`, `s64`, `u8`, `u32`, `u64` | integers | `int` is `s64` on 64-bit |
| `float`, `float32`, `float64` | floats | `float` is `float32` |
| `bool` | bool | |
| `string` | UTF-8 string, length-prefixed | not null-terminated |
| `[N] T` | fixed-size array, `N` is a compile-time integer | `arr: [4] int;` |
| `[..] T` | dynamic array (grows) | use `array_add(*arr, v)` to push |
| `[] T` | array view / slice | passed by value but references the data |
| `*T` | pointer | `p := *x;` takes address; access via `p.field` (auto-deref) |
| `Vector2`, `Vector3`, `Vector4`, `Matrix4` | from `Math` | standard graphics types |

**Take an address with `*x`** (not `&x`). **Dereference is automatic on field access** — you almost never write an explicit deref. If you really need it, `<<p`.

---

## Control flow

```jai
// if — braces optional for a single statement
if cond do_a_thing();
if cond { a(); b(); } else { c(); }

// switch-like: `if x == { case A; ...; case B; ...; }`
if dir == {
    case .UP;    dy = -1;
    case .DOWN;  dy = 1;
    case .LEFT;  dx = -1;
    case .RIGHT; dx = 1;
}

// for over an array — `it` is the element, `it_index` is the int index
for bombs {
    if it.timer <= 0 { ... }
}

// pointer for-loop — `it` is *Bomb so you can mutate
for * bombs {
    it.timer -= 1;
}

// rename `it` and `it_index` — DO THIS when nesting for-loops to avoid shadow bugs
for * b, bi: bombs {
    for other, oi: bombs {
        if oi == bi continue;          // bi is the outer bomb's index
        if other.x == b.x { ... }
    }
}

// range loop — half-open is NOT supported; this is INCLUSIVE
for r: 0..ROWS-1 { ... }              // 0, 1, ..., ROWS-1

while cond { ... }
break;
continue;

// ifx — ternary
x := ifx cond then 1 else 2;
```

**Gotcha:** in nested `for` loops, an inner loop's `it_index` shadows the outer's. If you need the outer index inside an inner loop, **always rename**: `for *outer, oi: arr { for inner, ii: other { ... oi ... } }`. (This bit us in the punch logic.)

---

## Casting and conversion

```jai
y := cast(float) i;            // explicit cast (preferred when readable)
y := xx i;                     // "auto-cast", picks the target type from context
b := cast(int) some_float;     // truncates toward zero
v := cast,no_check(u64) x;     // skip range check (use sparingly)
```

Integer division of two ints yields an int; for float division, cast at least one side: `cast(float)i / cast(float)N`.

---

## Procedures: defaults, named args, multi-return

```jai
// default parameter
spawn :: (x: int, y: int, color: Vector4, big: bool = false) { ... }

// call with positional, then named (any tail can be named)
spawn(3, 4, red);
spawn(3, 4, red, big = true);

// multiple return values
divmod :: (a: int, b: int) -> q: int, r: int {
    return a / b, a % b;
}
q, r := divmod(17, 5);

// the second return is `_` if you don't want it
pos, _ := project(world_point);
```

---

## Dynamic arrays

```jai
bombs: [..] Bomb;          // grows; lives in the heap allocator by default
b: Bomb;
b.x = 5;
array_add(*bombs, b);      // push (note `*bombs` — pass pointer)

// remove (unordered = O(1), swaps the last element in)
array_unordered_remove_by_index(*bombs, idx);

// free
array_reset(*bombs);

// length is .count
for i: 0..bombs.count-1 { ... }

// iterate
for b: bombs { ... }
```

**Temp allocator**: for per-frame transient data (BFS queues, lists you'll discard), set the array's allocator and the harness will free everything in one call:

```jai
path: [..] BFSNode;
path.allocator = temp;
// ... use path ...
// no `array_reset` needed; reset_temporary_storage() at top of frame wipes it
```

In the game loop call `reset_temporary_storage();` once per frame (see `main()` in `game.jai`).

---

## Modules and files

```jai
#import "Basic";              // anonymous import — names are top-level
Simp :: #import "Simp";       // aliased — call as Simp.foo()
Input :: #import "Input";

#load "other_file.jai";       // include another file into this compilation
```

Almost everything you'd consider "standard library" is a module under `C:\Users\finxo\jai\modules\`. Open them — **the source IS the docs**.

---

## Pointers, `using`, `defer`, `#expand`

```jai
// pointer field access auto-derefs
b := *bombs[3];
b.x = 5;                       // no -> arrow, just .

// `using` flattens a struct's fields into the current scope
Sprite :: struct {
    using transform: Transform;
    color: Vector4;
}
// inside a Sprite method you can write `position` instead of `transform.position`

// defer: run when the scope exits (reverse order of registration)
file := open(path);
defer close(file);

// #expand: force inline (we used this for nested `check` helpers in is_in_blast)
check :: (...) -> bool #expand { ... }
```

---

## Scope and namespacing

By default, top-level names in a file are exported. Limit visibility with directives at the top of a section:

```jai
#scope_file       // following names are file-only
helper_thing :: () { ... }

#scope_export     // back to default
```

Within a module, `#scope_module` keeps the name visible across the module but not to importers.

---

## Common stdlib pieces used by this project

| You want to | Use |
|---|---|
| Print a debug line | `print("x = %\n", x);` (`%` is the format slot, like Rust's `{}`) |
| Build a temporary string | `tprint("frame % t %", frame_count, t)` (allocates in temp) |
| Random float in [0, 1) | `Random.random_get_zero_to_one()` (we `#import "Random";` so it's just `random_get_zero_to_one()`) |
| Seconds since program start | `seconds_since_init()` |
| Min / max / abs | `min(a, b)`, `max(a, b)`, `abs(x)` — in `Basic` |
| Vector math | `Math` — `Vector3.{x, y, z}`, operator `*` for matrices, `dot_product`, `cross_product`, `normalize(*v)` |
| sin/cos/tan | `Math` — `sin(x)`, `cos(x)`, `tan(x)`, `PI`, `TAU` |
| Allocate temp memory | set `arr.allocator = temp` or call `alloc(size, temp)` |
| Run something only on Windows | `#if OS == .WINDOWS { ... }` |

---

## The game loop pattern (this project)

`game.jai` `main()` is the canonical shape; copy-paste it for new tools:

```jai
main :: () {
    #if OS == .WINDOWS { Windows.SetProcessDPIAware(); Windows.timeBeginPeriod(1); }

    random_seed(cast,no_check(u64)(seconds_since_init() * 1000000.0));

    window = create_window(WINDOW_W, WINDOW_H, "Bomberman");
    Simp.set_render_target(window, .LEFT_HANDED);   // top-left origin

    // resolve data/ relative to the exe
    path := path_strip_filename(get_path_of_running_executable());
    set_working_directory(path);

    my_font = Simp.get_font_at_size("data", "Anonymous Pro.ttf", pixel_height);

    reset_state();

    while !should_quit {
        reset_temporary_storage();     // wipe temp allocator each frame
        Input.update_window_events();

        for Input.get_window_resizes()  Simp.update_window(it.window);

        for event: Input.events_this_frame {
            if event.type == .QUIT { should_quit = true; break; }
            if event.type == .KEYBOARD { /* ... */ }
        }

        update();
        render();
        Simp.swap_buffers(window);
        sleep_milliseconds(1);
    }
}
```

Keep `update()` deterministic in frames; the loop is vsync'd, so 1 frame = 1 logical tick.

---

## Build and run

```
jai game.jai           # produces game.exe (+ .pdb on Windows)
./game.exe
```

The compiler is on PATH. Build artefacts (`game.exe`, `game.pdb`, `.build/`) are gitignored.

There's no `package.json` / `Cargo.toml`. Dependencies are just `#import "Foo";` against modules under `C:\Users\finxo\jai\modules\`.

---

## Gotchas I actually hit in this codebase

1. **`it_index` shadows in nested loops.** Use renamed loops: `for *b, bi: bombs { for other, oi: bombs { ... } }`.
2. **`for r: 0..N-1` is inclusive.** Use `N-1` for an array of length `N`.
3. **Simp's color vertex shader force-zeros Z.** If you want 3D, do software projection (build perspective+view matrices manually, project to 2D, submit to Simp's immediate triangles). See `make_view`, `make_perspective`, `project`, `draw_cube_3d` in `game.jai`.
4. **Pass pointers to mutating helpers**: `array_add(*arr, x)`, not `array_add(arr, x)`.
5. **`cast(int)` of a float truncates toward zero**, not toward negative infinity. For modulo with possibly-negative ints, add `N * big_number` first to force positive: `(val + N * 100) % N`.
6. **Modules are discovered relative to the compiler install.** `#import "Foo";` finds `C:\Users\finxo\jai\modules\Foo\`. There's no `go.mod`-style local dependency yet.
7. **A struct is value-typed.** `b := bombs[0]` copies. To mutate in place, `b := *bombs[0]` and edit through the pointer (`b.x = 3`).
8. **`#if` is compile-time, not runtime.** Use it for OS branches and feature flags that should be erased at compile time.
9. **No null safety, no exceptions.** Out-of-bounds and null deref crash the program. Test array `.count` first if it could be empty.

---

## Where to look

This file is intentionally brief. When you need more, the install on this machine is the source of truth — there's no good online reference for Jai yet.

**Language tutorial** (read in order or grep across):
- `C:\Users\finxo\jai\how_to\` — numbered files. Key ones:
  - `001_first.jai`, `002_number_types.jai`, `004_arrays.jai`, `006_structs.jai`, `013_enums.jai`, `019_looping.jai`
  - `100_polymorphic_procedures.jai`, `120_polymorphic_structs.jai`
  - `200_memory_management.jai`
  - `040_import_and_load/`, `044_using_advanced/`, `095_static_if.jai`, `170_modify.jai`

**Module sources** (the source *is* the documentation):
- `C:\Users\finxo\jai\modules\Basic\` — `print`, allocators, `array_add`/`array_unordered_remove_by_index`, `tprint`, `seconds_since_init`, temp storage
- `C:\Users\finxo\jai\modules\Math\matrix.jai` — `Vector3`, `Vector4`, `Matrix4`, `make_look_at_matrix`, `make_projection_matrix`, `orthographic_projection_matrix`, operator-overloaded `*`
- `C:\Users\finxo\jai\modules\Random.jai` — `random_seed`, `random_get_zero_to_one`, `random_get`
- `C:\Users\finxo\jai\modules\Simp\` — 2D renderer. Key files: `module.jai`, `immediate.jai`, `shader.jai`, `font.jai`
- `C:\Users\finxo\jai\modules\Window_Creation\` — `create_window`, `toggle_fullscreen`, `Saved_Window_Info`. Per-OS: `windows.jai`, `linux.jai`, `osx.jai`
- `C:\Users\finxo\jai\modules\Input\` — `update_window_events`, `events_this_frame`, `get_window_resizes`, `Key_Code`
- `C:\Users\finxo\jai\modules\GL\` — raw OpenGL when you need to go below Simp
- `C:\Users\finxo\jai\modules\String\`, `C:\Users\finxo\jai\modules\System.jai`

**Working sample programs**:
- `C:\Users\finxo\jai\examples\invaders\` — small game with Simp + Input. Closest analogue to this project.
- `C:\Users\finxo\jai\modules\Simp\examples\example.jai` — minimal Simp loop.
- `C:\Users\finxo\jai\modules\Simp\examples\render_to_texture.jai`, `multiple_windows.jai` — advanced rendering.
- `C:\Users\finxo\jai\examples\skeletal-animation\` — for "what would real 3D look like?"

**Reference**:
- `C:\Users\finxo\jai\CHANGELOG.txt` — language changes per beta version. If something behaves unexpectedly, check whether the language changed recently.
- `C:\Users\finxo\jai\README.txt` — top-level intro.
- `C:\Users\finxo\jai\bin\` — `jai.exe` lives here.

**This codebase** — `game.jai` is the worked example. Concrete patterns to copy:
- Game loop: `main()`
- Resetting + initializing all state: `reset_state()`
- 3D software projection: `make_view`, `make_perspective`, `project`, `draw_cube_3d`
- Letterbox fullscreen: `apply_letterbox`, `toggle_fullscreen` callsite
- BFS with optional flags: `bfs_path`
- Per-frame dynamic-array tick + remove: see the explosion / death-FX / powerup loops in `update()`
- Per-direction sprite primitives: `draw_player_char`, `draw_enemy_char`
