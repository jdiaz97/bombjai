# Bomberman

**Language: Jai.** All code lives in `game.jai`. No other language is in use in this repo. If you need to add code, add Jai.

If you don't already know Jai well, read **`jai.md`** in this directory first — it's a focused crash course built around this repo and points at the local Jai docs.

## Build & run

```
jai game.jai
./game.exe
```

The compiler is on PATH. `game.exe` and `game.pdb` are build artefacts (gitignored). The `data/` folder holds the font (`Anonymous Pro.ttf`) and is loaded at runtime via `path_strip_filename(get_path_of_running_executable())`.

## Game

15×13 grid, top-down 3D look (camera ~82° pitch). Player at top-left, three enemy wizards at the other corners. WASD/Arrows move, Space/E place bombs, Q punches a bomb, F11 fullscreen, R restarts after game-over, Esc quits.

## Log

See `logs.md`. Keep entries concise — no lengthy bullet lists.
