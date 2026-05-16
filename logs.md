# Development Log

## 2026-05-16 — JS prototype

Built the full game in vanilla JS + Canvas: 17x17 grid, walls/bricks, WASD/arrows + Space/E bombs, BFS-driven enemy AI (3 warlocks), chain reactions, powerups (bomb, fire, kick, punch) with melt animations, smooth lerped movement, medieval/wizard theme.

## 2026-05-17 — Jai port

Translated `game.js` to `game.jai` using Simp for rendering and Window_Creation/Input. Same constants and logic; BFS uses temp-allocated queues, no closures.

## 2026-05-17 — Fixes

Switched Simp render target to LEFT_HANDED so the player spawns visually at top-left and arrow keys move the right direction (Up was previously walking into the top wall because Y was flipped).
