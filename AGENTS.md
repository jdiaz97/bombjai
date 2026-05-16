# Bomberman

**Language: Jai.** All code lives in `game.jai`. No other language is in use in this repo. If you need to add code, add Jai.

## Build & run

```
jai game.jai
./game.exe
```

The compiler is on PATH. `game.exe` and `game.pdb` are build artefacts; the `data/` folder holds the font (`Anonymous Pro.ttf`) and is loaded at runtime via `path_strip_filename(get_path_of_running_executable())`.

## Game

15×13 grid, top-down 3D look (camera ~82° pitch). Player at top-left, three enemy wizards at the other corners. WASD/Arrows move, Space/E place bombs, Q punches a bomb, F11 fullscreen, R restarts after game-over, Esc quits.

## Jai documentation — where to look

Treat the local Jai install as the source of truth. There is no good online reference yet; everything is on disk.

**Language tutorial — read this first when you're stuck on syntax/semantics:**
- `C:\Users\finxo\jai\how_to\` — numbered tutorial files (`001_first.jai`, `002_number_types.jai`, `004_arrays.jai`, `006_structs.jai`, `013_enums.jai`, `019_looping.jai`, `100_polymorphic_procedures.jai`, `200_memory_management.jai`, …). Read in order or grep across when looking for a feature.

**Module sources we actually use** (open and read these — that *is* the documentation):
- `C:\Users\finxo\jai\modules\Basic\` — `print`, allocators, dynamic arrays (`array_add`, `array_unordered_remove_by_index`), `tprint`, `seconds_since_init`, temp storage.
- `C:\Users\finxo\jai\modules\Math\matrix.jai` — `Vector3`, `Vector4`, `Matrix4`, `make_look_at_matrix`, `make_projection_matrix`, `orthographic_projection_matrix`, operator-overloaded `*`.
- `C:\Users\finxo\jai\modules\Random.jai` — `random_seed`, `random_get_zero_to_one`, `random_get`.
- `C:\Users\finxo\jai\modules\Simp\` — 2D renderer. Key files: `module.jai` (`set_render_target`, `update_window`, `clear_render_target`, `swap_buffers`), `immediate.jai` (`immediate_quad`, `immediate_triangle`, `immediate_set_2d_projection`), `shader.jai` (`set_shader_for_color`, `set_shader_for_text`), `font.jai` (`get_font_at_size`, `prepare_text`, `draw_prepared_text`). Note: the color vertex shader force-zeros Z — software-project to 2D for 3D scenes.
- `C:\Users\finxo\jai\modules\Window_Creation\` — `create_window`, `toggle_fullscreen`, `Saved_Window_Info`. Per-OS files: `windows.jai`, `linux.jai`, `osx.jai`.
- `C:\Users\finxo\jai\modules\Input\` — `update_window_events`, `events_this_frame`, `get_window_resizes`, `Key_Code` (`.ARROW_UP`, `.SPACEBAR`, `.F11`, `.ESCAPE`, …).
- `C:\Users\finxo\jai\modules\GL\` — raw OpenGL bindings. `glViewport`, `glClear`, etc. when you need to go below Simp.
- `C:\Users\finxo\jai\modules\String\` — string utilities.
- `C:\Users\finxo\jai\modules\System.jai` — `get_path_of_running_executable`, `set_working_directory`, `path_strip_filename`.

**Working sample programs — copy-paste-able patterns:**
- `C:\Users\finxo\jai\examples\invaders\` — small game with Simp + Input. Closest analogue to this project.
- `C:\Users\finxo\jai\modules\Simp\examples\example.jai` — bare-bones Simp loop.
- `C:\Users\finxo\jai\modules\Simp\examples\multiple_windows.jai` and `render_to_texture.jai` — for more advanced rendering.
- `C:\Users\finxo\jai\examples\skeletal-animation\` — if we ever want real 3D models.

**Reference docs:**
- `C:\Users\finxo\jai\CHANGELOG.txt` — language changes per beta version.
- `C:\Users\finxo\jai\README.txt` — top-level intro.
- `C:\Users\finxo\jai\bin\` — compiler binaries (`jai.exe` is the one on PATH).

## Log

See `logs.md`. Keep entries concise — no lengthy bullet lists.
