# Development Log

## 2026-05-17 — Initial build

Wizard-themed Bomberman in `game.jai` using Simp for rendering and Window_Creation/Input. 15×13 grid, walls + bricks, BFS-driven enemy AI (3 warlocks), bomb chain reactions, powerups (bomb, fire, kick, punch) with melt animations, smooth lerped movement.

## 2026-05-17 — Fixes & visuals

LEFT_HANDED render target so origin sits top-left; F11 fullscreen with a centered aspect-preserving viewport so resizing never stretches. Bigger, clearer characters — distinct silhouettes per enemy (horned demon / tall wizard / hooded necromancer) and a glowing-orb staff for the player. Walls and bricks got drop-shadow strips for depth; floor got subtle twinkles.

## 2026-05-17 — 3D look

Switched the scene to a software-projected 3D pipeline. Custom perspective + view matrices feed `project(Vector3) → screen Vector2`; walls and bricks render as shaded cubes via 2D triangles, characters/bombs/powerups stay as billboards at projected positions. Painter's algorithm row-by-row, no depth buffer. Camera pitch ~82° (near-zenithal) so layout is easy to read and nothing important hides behind a brick.
