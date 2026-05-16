const COLS = 15;
const ROWS = 13;
const TILE = 60;
const BOMB_TIMER = 135;
const POWERUP_DROP_RATE = 0.5;
const ENEMY_MOVE_DELAY = 16;
const START_FIRE_RANGE = 1;
const START_MAX_BOMBS = 1;
const ENEMY_FIRE_RANGE = 1;
const EXPLOSION_DURATION = 20;
const MELT_DURATION = 14;
const POWERUP_SPAWN_DELAY = 35;
const POWERUP_MELT_DURATION = 12;
const BRICK_DENSITY = 0.65;
const MOVE_DELAY = 8;
const AI_BOMB_DIST = 3;
const BOMB_SLIDE_SPEED = 4;
const STUN_DURATION = 60;
const KICK_MAX = 4;
const PUNCH_MAX = 4;

const canvas = document.getElementById('game');
const ctx = canvas.getContext('2d');
canvas.width = COLS * TILE;
canvas.height = ROWS * TILE;

const EMPTY = 0;
const WALL = 1;
const BRICK = 2;
const BRICK_MELTING = 3;

const LERP_SPEED = 0.25;

let grid = [];
let player = { x: 1, y: 1, rx: 1, ry: 1, maxBombs: START_MAX_BOMBS, fireRange: START_FIRE_RANGE, dir: 'down', hasKick: false, hasPunch: false };
let enemies = [
  { x: COLS - 2, y: ROWS - 2, rx: COLS - 2, ry: ROWS - 2, alive: true, maxBombs: START_MAX_BOMBS, fireRange: ENEMY_FIRE_RANGE, moveTimer: 0, color: '#b71c1c', glow: '#ff1744', id: 'enemy0', dir: 'left', stunTimer: 0, fleeTarget: null },
  { x: COLS - 2, y: 1, rx: COLS - 2, ry: 1, alive: true, maxBombs: START_MAX_BOMBS, fireRange: ENEMY_FIRE_RANGE, moveTimer: 0, color: '#4a148c', glow: '#ea80fc', id: 'enemy1', dir: 'down', stunTimer: 0, fleeTarget: null },
  { x: 1, y: ROWS - 2, rx: 1, ry: ROWS - 2, alive: true, maxBombs: START_MAX_BOMBS, fireRange: ENEMY_FIRE_RANGE, moveTimer: 0, color: '#1b5e20', glow: '#69f0ae', id: 'enemy2', dir: 'right', stunTimer: 0, fleeTarget: null }
];
let powerups = [];
let bombs = [];
let explosions = [];
let meltingBricks = [];
let meltingPowerups = [];
let kickSpawned = 0;
let punchSpawned = 0;
let keys = {};
let gameOver = false;
let playerWon = false;
let frame = 0;

function initGrid() {
  grid = [];
  for (let r = 0; r < ROWS; r++) {
    grid[r] = [];
    for (let c = 0; c < COLS; c++) {
      if (r === 0 || r === ROWS - 1 || c === 0 || c === COLS - 1) {
        grid[r][c] = WALL;
      } else if (r % 2 === 0 && c % 2 === 0) {
        grid[r][c] = WALL;
      } else if ((r === 1 && c <= 2) || (c === 1 && r <= 2)) {
        grid[r][c] = EMPTY;
      } else if ((r === ROWS - 2 && c >= COLS - 3) || (c === COLS - 2 && r >= ROWS - 3)) {
        grid[r][c] = EMPTY;
      } else if ((r === 1 && c >= COLS - 3) || (c === COLS - 2 && r <= 2)) {
        grid[r][c] = EMPTY;
      } else if ((r === ROWS - 2 && c <= 2) || (c === 1 && r >= ROWS - 3)) {
        grid[r][c] = EMPTY;
      } else {
        grid[r][c] = Math.random() < BRICK_DENSITY ? BRICK : EMPTY;
      }
    }
  }
}

function roundRect(x, y, w, h, r) {
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.lineTo(x + w - r, y);
  ctx.quadraticCurveTo(x + w, y, x + w, y + r);
  ctx.lineTo(x + w, y + h - r);
  ctx.quadraticCurveTo(x + w, y + h, x + w - r, y + h);
  ctx.lineTo(x + r, y + h);
  ctx.quadraticCurveTo(x, y + h, x, y + h - r);
  ctx.lineTo(x, y + r);
  ctx.quadraticCurveTo(x, y, x + r, y);
  ctx.closePath();
}

function drawWall(c, r) {
  const x = c * TILE, y = r * TILE;
  ctx.fillStyle = '#3e3a4e';
  ctx.fillRect(x, y, TILE, TILE);
  ctx.fillStyle = '#4d4860';
  ctx.fillRect(x + 1, y + 1, TILE / 2 - 2, TILE / 2 - 2);
  ctx.fillRect(x + TILE / 2 + 1, y + 1, TILE / 2 - 2, TILE / 2 - 2);
  ctx.fillRect(x + TILE / 4, y + TILE / 2 + 1, TILE / 2, TILE / 2 - 2);
  ctx.fillStyle = '#35314a';
  ctx.fillRect(x, y + TILE / 2 - 1, TILE, 2);
  ctx.fillRect(x + TILE / 2 - 1, y, 2, TILE);
  ctx.fillStyle = '#2c2840';
  ctx.fillRect(x, y, TILE, 1);
  ctx.fillRect(x, y, 1, TILE);
}

function drawBrick(c, r) {
  const x = c * TILE, y = r * TILE;
  ctx.fillStyle = '#7a5c30';
  ctx.fillRect(x, y, TILE, TILE);
  ctx.fillStyle = '#8b6e3e';
  ctx.fillRect(x + 2, y + 2, TILE - 4, TILE - 6);
  ctx.fillStyle = '#6b4e24';
  ctx.fillRect(x + 2, y + TILE - 6, TILE - 4, 4);
  ctx.strokeStyle = '#5a3d1a';
  ctx.lineWidth = 1;
  ctx.strokeRect(x + 3, y + 3, TILE - 6, TILE - 6);
  ctx.beginPath();
  ctx.moveTo(x + 4, y + TILE / 2);
  ctx.lineTo(x + TILE - 4, y + TILE / 2);
  ctx.stroke();
  ctx.fillStyle = '#96784a';
  ctx.fillRect(x + 5, y + 5, 6, 4);
  ctx.fillRect(x + TILE - 14, y + TILE / 2 + 3, 6, 4);
  ctx.fillStyle = '#5e421e';
  const seed = c * 7 + r * 13;
  ctx.fillRect(x + (seed % 12) + 10, y + ((seed * 3) % 8) + 14, 8, 3);
}

function drawMeltingBrick(c, r, m) {
  const x = c * TILE, y = r * TILE;
  const pct = m.timer / MELT_DURATION;
  const shrink = (1 - pct) * 8;
  const wobX = Math.sin(frame / 2 + c * 3) * (1 - pct) * 4;
  const wobY = Math.cos(frame / 3 + r * 5) * (1 - pct) * 3;
  ctx.globalAlpha = 0.4 + pct * 0.6;
  ctx.fillStyle = '#7c4dff';
  ctx.shadowColor = '#b388ff';
  ctx.shadowBlur = (1 - pct) * 18;
  ctx.fillRect(x + shrink * 0.5 + wobX, y + shrink * 0.5 + wobY, TILE - shrink, TILE - shrink);
  ctx.shadowBlur = 0;
  ctx.fillStyle = '#8b6e3e';
  const innerShrink = shrink + 2;
  ctx.fillRect(x + innerShrink * 0.5 + wobX, y + innerShrink * 0.5 + wobY, TILE - innerShrink, TILE - innerShrink);
  ctx.fillStyle = '#7c4dff';
  ctx.globalAlpha = (1 - pct) * 0.6;
  ctx.fillRect(x + wobX, y + wobY, TILE, TILE);
  ctx.globalAlpha = 1;
}

function drawFloor(c, r) {
  const x = c * TILE, y = r * TILE;
  ctx.fillStyle = (r + c) % 2 === 0 ? '#2a2740' : '#302d48';
  ctx.fillRect(x, y, TILE, TILE);
  ctx.fillStyle = (r + c) % 2 === 0 ? '#252238' : '#2b2844';
  ctx.fillRect(x + 1, y + 1, TILE - 2, TILE - 2);
  ctx.strokeStyle = (r + c) % 2 === 0 ? '#222038' : '#282542';
  ctx.lineWidth = 0.5;
  ctx.strokeRect(x, y, TILE, TILE);
}

function drawPlayer() {
  const px = player.rx * TILE;
  const py = player.ry * TILE;
  const cx = px + TILE / 2;
  const cy = py + TILE / 2;
  const d = player.dir;
  const pupilDx = d === 'left' ? -2 : d === 'right' ? 2 : 0;
  const pupilDy = d === 'up' ? -2 : d === 'down' ? 1 : 0;
  const antDx = d === 'left' ? -10 : d === 'right' ? 10 : 0;
  const antDy = d === 'up' ? -18 : d === 'down' ? -12 : -15;
  ctx.fillStyle = 'rgba(0,0,0,0.3)';
  ctx.beginPath();
  ctx.ellipse(cx, cy + TILE / 2 - 2, 10, 4, 0, 0, Math.PI * 2);
  ctx.fill();
  ctx.fillStyle = '#1565c0';
  ctx.beginPath();
  ctx.moveTo(cx - 8, cy + 8);
  ctx.lineTo(cx, cy + 4);
  ctx.lineTo(cx + 8, cy + 8);
  ctx.lineTo(cx + 6, cy + 12);
  ctx.lineTo(cx - 6, cy + 12);
  ctx.closePath();
  ctx.fill();
  ctx.fillStyle = '#e8d5b0';
  ctx.beginPath();
  ctx.arc(cx, cy - 2, 9, 0, Math.PI * 2);
  ctx.fill();
  ctx.fillStyle = '#5c3a1e';
  ctx.beginPath();
  ctx.arc(cx, cy - 8, 8, Math.PI, 0);
  ctx.closePath();
  ctx.fill();
  ctx.fillStyle = '#4a2d17';
  if (d === 'left') {
    ctx.beginPath();
    ctx.moveTo(cx + 10, cy - 8);
    ctx.quadraticCurveTo(cx, cy - 18, cx - 10, cy - 8);
    ctx.quadraticCurveTo(cx - 3, cy - 5, cx + 2, cy - 2);
    ctx.quadraticCurveTo(cx + 6, cy - 5, cx + 10, cy - 8);
    ctx.closePath();
    ctx.fill();
  } else if (d === 'right') {
    ctx.beginPath();
    ctx.moveTo(cx - 10, cy - 8);
    ctx.quadraticCurveTo(cx, cy - 18, cx + 10, cy - 8);
    ctx.quadraticCurveTo(cx + 3, cy - 5, cx - 2, cy - 2);
    ctx.quadraticCurveTo(cx - 6, cy - 5, cx - 10, cy - 8);
    ctx.closePath();
    ctx.fill();
  } else if (d === 'up') {
    ctx.beginPath();
    ctx.arc(cx, cy - 7, 9, Math.PI, 0);
    ctx.closePath();
    ctx.fill();
  } else {
    ctx.beginPath();
    ctx.moveTo(cx - 10, cy - 8);
    ctx.quadraticCurveTo(cx, cy - 18, cx + 10, cy - 8);
    ctx.closePath();
    ctx.fill();
  }
  ctx.fillStyle = '#8b6914';
  ctx.beginPath();
  const atx = cx + antDx;
  const aty = cy + antDy;
  ctx.moveTo(cx, cy - 16);
  ctx.lineTo((cx + atx) / 2, (cy - 16 + aty) / 2);
  ctx.lineTo(atx, aty);
  ctx.closePath();
  ctx.fill();
  if (d !== 'up') {
    const eyeShiftX = d === 'left' ? -2 : d === 'right' ? 2 : 0;
    ctx.fillStyle = '#fff';
    ctx.beginPath();
    ctx.arc(cx - 4 + eyeShiftX * 0.3, cy - 3, 4, 0, Math.PI * 2);
    ctx.arc(cx + 4 + eyeShiftX * 0.3, cy - 3, 4, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = '#1a237e';
    ctx.beginPath();
    ctx.arc(cx - 4 + pupilDx + eyeShiftX * 0.3, cy - 3 + pupilDy, 2, 0, Math.PI * 2);
    ctx.arc(cx + 4 + pupilDx + eyeShiftX * 0.3, cy - 3 + pupilDy, 2, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = '#fff';
    ctx.beginPath();
    ctx.arc(cx - 4.5 + pupilDx * 0.5 + eyeShiftX * 0.3, cy - 4 + pupilDy * 0.5, 0.8, 0, Math.PI * 2);
    ctx.arc(cx + 3.5 + pupilDx * 0.5 + eyeShiftX * 0.3, cy - 4 + pupilDy * 0.5, 0.8, 0, Math.PI * 2);
    ctx.fill();
  } else {
    ctx.fillStyle = '#fff';
    ctx.beginPath();
    ctx.arc(cx - 4, cy - 5, 3.5, 0, Math.PI * 2);
    ctx.arc(cx + 4, cy - 5, 3.5, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = '#1a237e';
    ctx.beginPath();
    ctx.arc(cx - 4 + pupilDx, cy - 5 + pupilDy, 1.8, 0, Math.PI * 2);
    ctx.arc(cx + 4 + pupilDx, cy - 5 + pupilDy, 1.8, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = '#fff';
    ctx.beginPath();
    ctx.arc(cx - 4.5 + pupilDx * 0.5, cy - 5.5 + pupilDy * 0.5, 0.7, 0, Math.PI * 2);
    ctx.arc(cx + 3.5 + pupilDx * 0.5, cy - 5.5 + pupilDy * 0.5, 0.7, 0, Math.PI * 2);
    ctx.fill();
    ctx.strokeStyle = '#4a2d17';
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    ctx.moveTo(cx - 5, cy - 2);
    ctx.lineTo(cx - 7, cy + 1);
    ctx.stroke();
    ctx.beginPath();
    ctx.moveTo(cx + 5, cy - 2);
    ctx.lineTo(cx + 7, cy + 1);
    ctx.stroke();
  }
  ctx.fillStyle = '#90caf9';
  ctx.shadowColor = '#42a5f5';
  ctx.shadowBlur = 6;
  ctx.beginPath();
  ctx.arc(atx, aty, 4, 0, Math.PI * 2);
  ctx.fill();
  ctx.shadowBlur = 0;
}

function drawEnemy(e) {
  if (!e.alive) return;
  const stunned = e.stunTimer > 0;
  if (stunned) ctx.globalAlpha = Math.floor(frame / 3) % 2 === 0 ? 0.5 : 1;
  const px = e.rx * TILE;
  const py = e.ry * TILE;
  const cx = px + TILE / 2;
  const cy = py + TILE / 2;
  const c = e.color;
  const g = e.glow;
  const d = e.dir;
  const dx = d === 'left' ? -1.5 : d === 'right' ? 1.5 : 0;
  const upShift = d === 'up' ? -1.5 : 0;
  ctx.fillStyle = 'rgba(0,0,0,0.3)';
  ctx.beginPath();
  ctx.ellipse(cx, cy + TILE / 2 - 2, 10, 4, 0, 0, Math.PI * 2);
  ctx.fill();
  ctx.fillStyle = '#4a0000';
  ctx.beginPath();
  ctx.moveTo(cx - 9, cy + 8);
  ctx.lineTo(cx, cy + 4);
  ctx.lineTo(cx + 9, cy + 8);
  ctx.lineTo(cx + 7, cy + 12);
  ctx.lineTo(cx - 7, cy + 12);
  ctx.closePath();
  ctx.fill();
  ctx.fillStyle = '#d4c4a0';
  ctx.beginPath();
  ctx.arc(cx, cy - 2, 9, 0, Math.PI * 2);
  ctx.fill();
  ctx.fillStyle = '#1a1a1a';
  if (d === 'left') {
    ctx.beginPath();
    ctx.moveTo(cx - 11, cy - 6 + upShift);
    ctx.quadraticCurveTo(cx, cy - 14 + upShift, cx + 11, cy - 6 + upShift);
    ctx.quadraticCurveTo(cx + 6, cy - 2 + upShift, cx + 2, cy + 2 + upShift);
    ctx.quadraticCurveTo(cx - 6, cy + upShift, cx - 11, cy - 6 + upShift);
    ctx.closePath();
    ctx.fill();
  } else if (d === 'right') {
    ctx.beginPath();
    ctx.moveTo(cx - 11, cy - 6 + upShift);
    ctx.quadraticCurveTo(cx, cy - 14 + upShift, cx + 11, cy - 6 + upShift);
    ctx.quadraticCurveTo(cx + 6, cy + upShift, cx - 2, cy + 2 + upShift);
    ctx.quadraticCurveTo(cx - 6, cy + upShift, cx - 11, cy - 6 + upShift);
    ctx.closePath();
    ctx.fill();
  } else if (d === 'up') {
    ctx.beginPath();
    ctx.moveTo(cx - 12, cy - 6 - 2);
    ctx.quadraticCurveTo(cx, cy - 14 - 2, cx + 12, cy - 6 - 2);
    ctx.quadraticCurveTo(cx + 6, cy - 1, cx, cy + 2 - 1);
    ctx.quadraticCurveTo(cx - 6, cy - 1, cx - 12, cy - 6 - 2);
    ctx.closePath();
    ctx.fill();
  } else {
    ctx.beginPath();
    ctx.moveTo(cx - 11, cy - 6);
    ctx.quadraticCurveTo(cx, cy - 14, cx + 11, cy - 6);
    ctx.quadraticCurveTo(cx + 6, cy - 2, cx, cy + 2);
    ctx.quadraticCurveTo(cx - 6, cy - 2, cx - 11, cy - 6);
    ctx.closePath();
    ctx.fill();
  }
  const eyeY = d === 'up' ? cy - 5 : cy - 3;
  ctx.shadowColor = g;
  ctx.shadowBlur = 8;
  ctx.fillStyle = c;
  ctx.beginPath();
  ctx.arc(cx - 5 + dx, eyeY, 5, 0, Math.PI * 2);
  ctx.arc(cx + 5 + dx, eyeY, 5, 0, Math.PI * 2);
  ctx.fill();
  ctx.fillStyle = g;
  ctx.beginPath();
  ctx.arc(cx - 5 + dx * 1.8, eyeY + (d === 'down' ? 1.5 : d === 'up' ? -1.5 : 0), 2, 0, Math.PI * 2);
  ctx.arc(cx + 5 + dx * 1.8, eyeY + (d === 'down' ? 1.5 : d === 'up' ? -1.5 : 0), 2, 0, Math.PI * 2);
  ctx.fill();
  ctx.shadowBlur = 0;
  ctx.fillStyle = '#fff';
  ctx.beginPath();
  ctx.arc(cx - 4.5 + dx * 1.4, eyeY - 1 + (d === 'up' ? -1 : 0), 0.8, 0, Math.PI * 2);
  ctx.arc(cx + 5.5 + dx * 1.4, eyeY - 1 + (d === 'up' ? -1 : 0), 0.8, 0, Math.PI * 2);
  ctx.fill();
  if (d !== 'up') {
    ctx.fillStyle = '#7f0000';
    ctx.beginPath();
    const mouthW = d === 'left' ? cx - 1 : d === 'right' ? cx + 1 : cx;
    ctx.moveTo(mouthW - 3, cy + 4);
    ctx.quadraticCurveTo(mouthW, cy + 8, mouthW + 3, cy + 4);
    ctx.closePath();
    ctx.fill();
  }
  const orbX = d === 'left' ? cx - 13 : d === 'right' ? cx + 13 : d === 'up' ? cx - 10 : cx + 10;
  const orbY = d === 'up' ? cy + 1 : cy + 6;
  ctx.fillStyle = c;
  ctx.shadowColor = g;
  ctx.shadowBlur = 4;
  ctx.beginPath();
  ctx.arc(orbX, orbY, 3, 0, Math.PI * 2);
  ctx.fill();
  ctx.shadowBlur = 0;
  if (stunned) {
    ctx.globalAlpha = 1;
    ctx.fillStyle = '#ffeb3b';
    ctx.shadowColor = '#ffeb3b';
    ctx.shadowBlur = 4;
    for (let i = 0; i < 3; i++) {
      const angle = (i / 3) * Math.PI * 2 + frame / 12;
      const sx = cx + Math.cos(angle) * 12;
      const sy = cy - 14 + Math.sin(angle) * 4;
      ctx.beginPath();
      ctx.arc(sx, sy, 2.5, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.shadowBlur = 0;
  }
}

function drawBomb(b) {
  const bx = b.x * TILE + TILE / 2;
  const by = b.y * TILE + TILE / 2;
  const pctLeft = b.timer / BOMB_TIMER;
  const pulse = Math.sin(frame / 4) * (3 + (1 - pctLeft) * 4);
  const r = 11 + pulse;
  ctx.shadowColor = '#7c4dff';
  ctx.shadowBlur = 10 + pulse * 2;
  ctx.fillStyle = 'rgba(0,0,0,0.2)';
  ctx.beginPath();
  ctx.ellipse(bx, by + r + 2, r, 3, 0, 0, Math.PI * 2);
  ctx.fill();
  const grad = ctx.createRadialGradient(bx - 3, by - 3, 2, bx, by, r);
  grad.addColorStop(0, '#b388ff');
  grad.addColorStop(0.5, '#7c4dff');
  grad.addColorStop(1, '#4a148c');
  ctx.fillStyle = grad;
  ctx.beginPath();
  ctx.arc(bx, by, r, 0, Math.PI * 2);
  ctx.fill();
  ctx.shadowBlur = 0;
  ctx.fillStyle = 'rgba(255,255,255,0.4)';
  ctx.beginPath();
  ctx.arc(bx - r * 0.3, by - r * 0.3, r * 0.3, 0, Math.PI * 2);
  ctx.fill();
  if (Math.sin(frame / 3) > 0) {
    ctx.fillStyle = '#e1bee7';
    ctx.shadowColor = '#ea80fc';
    ctx.shadowBlur = 8;
    ctx.beginPath();
    ctx.arc(bx, by - r - 4 + Math.sin(frame / 5) * 3, 3, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = '#fff';
    ctx.beginPath();
    ctx.arc(bx, by - r - 5 + Math.sin(frame / 5) * 3, 1.5, 0, Math.PI * 2);
    ctx.fill();
    ctx.shadowBlur = 0;
  }
}

function drawExplosion(e) {
  const ex = e.x * TILE + TILE / 2;
  const ey = e.y * TILE + TILE / 2;
  const progress = 1 - e.timer / e.duration;
  const alpha = Math.min(1, e.timer / e.duration + 0.2);
  const size = TILE - 4 + Math.sin(progress * Math.PI) * 8;
  ctx.save();
  ctx.beginPath();
  ctx.rect(e.x * TILE, e.y * TILE, TILE, TILE);
  ctx.clip();
  ctx.globalAlpha = alpha;
  if (e.origin) {
    ctx.shadowColor = '#fff';
    ctx.shadowBlur = 18 + Math.sin(progress * Math.PI) * 10;
    ctx.fillStyle = '#e1bee7';
    ctx.beginPath();
    ctx.arc(ex, ey, size / 2, 0, Math.PI * 2);
    ctx.fill();
    ctx.shadowColor = '#7c4dff';
    ctx.shadowBlur = 10;
    ctx.fillStyle = '#b388ff';
    ctx.beginPath();
    ctx.arc(ex, ey, size / 2 - 3, 0, Math.PI * 2);
    ctx.fill();
    ctx.shadowBlur = 4;
    ctx.fillStyle = '#d1c4e9';
    ctx.beginPath();
    ctx.arc(ex, ey, size / 2 - 8, 0, Math.PI * 2);
    ctx.fill();
    ctx.shadowBlur = 0;
    ctx.fillStyle = '#fff';
    ctx.beginPath();
    ctx.arc(ex, ey, size / 3, 0, Math.PI * 2);
    ctx.fill();
  } else {
    ctx.shadowColor = '#7c4dff';
    ctx.shadowBlur = 12;
    ctx.fillStyle = '#7c4dff';
    ctx.beginPath();
    ctx.arc(ex, ey, size / 2, 0, Math.PI * 2);
    ctx.fill();
    ctx.shadowBlur = 6;
    ctx.fillStyle = '#b388ff';
    ctx.beginPath();
    ctx.arc(ex, ey, size / 2 - 4, 0, Math.PI * 2);
    ctx.fill();
    ctx.shadowBlur = 0;
    ctx.fillStyle = '#e1bee7';
    ctx.beginPath();
    ctx.arc(ex, ey, size / 2 - 10, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = '#fff';
    ctx.beginPath();
    ctx.arc(ex, ey, size / 4 - 2, 0, Math.PI * 2);
    ctx.fill();
  }
  ctx.globalAlpha = 1;
  ctx.restore();
}

function drawPowerup(p) {
  if (p.delay > 0) return;
  const px = p.x * TILE;
  const py = p.y * TILE;
  const cx = px + TILE / 2;
  const cy = py + TILE / 2;
  const pulse = Math.sin(frame / 15) * 2;
  const bob = Math.sin(frame / 20) * 2;
  if (p.type === 'bomb') {
    ctx.shadowColor = '#7c4dff';
    ctx.shadowBlur = 8;
    ctx.fillStyle = '#4a148c';
    ctx.beginPath();
    ctx.moveTo(cx, cy - 14 - pulse + bob);
    ctx.lineTo(cx - 10, cy - 2 + bob);
    ctx.lineTo(cx - 6, cy - 4 + bob);
    ctx.lineTo(cx - 8, cy + 12 + bob);
    ctx.lineTo(cx + 8, cy + 12 + bob);
    ctx.lineTo(cx + 6, cy - 4 + bob);
    ctx.lineTo(cx + 10, cy - 2 + bob);
    ctx.closePath();
    ctx.fill();
    ctx.fillStyle = '#7c4dff';
    ctx.beginPath();
    ctx.moveTo(cx, cy - 10 - pulse + bob);
    ctx.lineTo(cx - 7, cy + bob);
    ctx.lineTo(cx + 7, cy + bob);
    ctx.closePath();
    ctx.fill();
    ctx.fillStyle = '#b388ff';
    ctx.beginPath();
    ctx.moveTo(cx, cy - 8 + bob);
    ctx.lineTo(cx - 4, cy + 8 + bob);
    ctx.lineTo(cx + 4, cy + 8 + bob);
    ctx.closePath();
    ctx.fill();
    ctx.shadowBlur = 0;
  } else if (p.type === 'fire') {
    const fy = cy + bob;
    ctx.shadowColor = '#ff6f00';
    ctx.shadowBlur = 6;
    ctx.fillStyle = '#5d4037';
    roundRect(cx - 4, fy - 14 - pulse, 8, 12, 2);
    ctx.fill();
    ctx.fillStyle = '#ff6f00';
    roundRect(cx - 6, fy - 4 - pulse, 12, 8, 2);
    ctx.fill();
    ctx.fillStyle = '#ffab40';
    roundRect(cx - 4, fy - 2 - pulse, 8, 4, 1);
    ctx.fill();
    ctx.fillStyle = '#fff8e1';
    ctx.font = 'bold 10px sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText('R', cx, fy - pulse);
    ctx.textAlign = 'start';
    ctx.textBaseline = 'alphabetic';
    ctx.shadowBlur = 0;
  } else if (p.type === 'kick') {
    const ky = cy + bob;
    ctx.shadowColor = '#00bcd4';
    ctx.shadowBlur = 8;
    ctx.fillStyle = '#006064';
    ctx.beginPath();
    ctx.moveTo(cx, ky - 14 - pulse);
    ctx.lineTo(cx - 10, ky + 2);
    ctx.lineTo(cx - 6, ky + 2);
    ctx.lineTo(cx - 4, ky + 10);
    ctx.lineTo(cx + 4, ky + 10);
    ctx.lineTo(cx + 6, ky + 2);
    ctx.lineTo(cx + 10, ky + 2);
    ctx.closePath();
    ctx.fill();
    ctx.fillStyle = '#00bcd4';
    ctx.beginPath();
    ctx.moveTo(cx, ky - 10 - pulse);
    ctx.lineTo(cx - 6, ky + 2);
    ctx.lineTo(cx + 6, ky + 2);
    ctx.closePath();
    ctx.fill();
    ctx.fillStyle = '#80deea';
    ctx.font = 'bold 10px sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText('K', cx, ky + 2);
    ctx.textAlign = 'start';
    ctx.textBaseline = 'alphabetic';
    ctx.shadowBlur = 0;
  } else if (p.type === 'punch') {
    const py2 = cy + bob;
    ctx.shadowColor = '#ffc107';
    ctx.shadowBlur = 8;
    ctx.fillStyle = '#7f6000';
    ctx.beginPath();
    ctx.arc(cx, py2 - pulse, 10, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = '#ffc107';
    ctx.beginPath();
    ctx.arc(cx, py2 - pulse, 7, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = '#ffe082';
    const starR = 12;
    for (let i = 0; i < 6; i++) {
      const angle = (i / 6) * Math.PI * 2 + frame / 40;
      ctx.beginPath();
      ctx.arc(cx + Math.cos(angle) * starR, py2 - pulse + Math.sin(angle) * starR, 2, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.fillStyle = '#7f6000';
    ctx.font = 'bold 11px sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText('P', cx, py2 - pulse + 1);
    ctx.textAlign = 'start';
    ctx.textBaseline = 'alphabetic';
    ctx.shadowBlur = 0;
  }
}

function drawMeltingPowerup(m) {
  const px = m.x * TILE;
  const py = m.y * TILE;
  const cx = px + TILE / 2;
  const cy = py + TILE / 2;
  const pct = m.timer / POWERUP_MELT_DURATION;
  const shrink = (1 - pct) * 14;
  ctx.save();
  ctx.beginPath();
  ctx.rect(px, py, TILE, TILE);
  ctx.clip();
  ctx.globalAlpha = pct;
  const isBomb = m.type === 'bomb';
  const isKick = m.type === 'kick';
  const isPunch = m.type === 'punch';
  const shadowC = isBomb ? '#7c4dff' : isKick ? '#00bcd4' : isPunch ? '#ffc107' : '#ff6f00';
  const darkC = isBomb ? '#4a148c' : isKick ? '#006064' : isPunch ? '#7f6000' : '#5d4037';
  const midC = isBomb ? '#7c4dff' : isKick ? '#00bcd4' : isPunch ? '#ffc107' : '#ff6f00';
  const lightC = isBomb ? '#b388ff' : isKick ? '#80deea' : isPunch ? '#ffe082' : '#ffab40';
  ctx.shadowColor = shadowC;
  ctx.shadowBlur = (1 - pct) * 14;
  ctx.fillStyle = darkC;
  const h = 16 - shrink;
  ctx.fillRect(cx - h / 2, cy - h / 2, h, h);
  ctx.fillStyle = midC;
  ctx.fillRect(cx - h / 2 + 2, cy - h / 2 + 2, h - 4, h - 4);
  ctx.shadowBlur = 0;
  ctx.globalAlpha = (1 - pct) * 0.5;
  ctx.fillStyle = lightC;
  ctx.beginPath();
  ctx.arc(cx, cy, (1 - pct) * 6, 0, Math.PI * 2);
  ctx.fill();
  ctx.restore();
}

function placeBomb() {
  const activePlayerBombs = bombs.filter(b => b.owner === 'player').length;
  if (activePlayerBombs < player.maxBombs) {
    const exists = bombs.some(b => b.x === player.x && b.y === player.y);
    if (!exists) {
      bombs.push({ x: player.x, y: player.y, timer: BOMB_TIMER, range: player.fireRange, owner: 'player', slideDx: 0, slideDy: 0, slideTimer: 0 });
    }
  }
}

function explode(b) {
  const dirs = [[0, -1], [0, 1], [-1, 0], [1, 0]];
  explosions.push({ x: b.x, y: b.y, timer: EXPLOSION_DURATION, duration: EXPLOSION_DURATION, origin: true });
  for (const [dx, dy] of dirs) {
    for (let i = 1; i <= b.range; i++) {
      const nx = b.x + dx * i;
      const ny = b.y + dy * i;
      if (nx < 0 || nx >= COLS || ny < 0 || ny >= ROWS) break;
      if (grid[ny][nx] === WALL || grid[ny][nx] === BRICK_MELTING) break;
      const hitBomb = bombs.find(ob => ob.x === nx && ob.y === ny);
      if (hitBomb) {
        hitBomb.timer = 1;
        hitBomb.chain = true;
        break;
      }
      const hitPowerup = powerups.findIndex(p => p.x === nx && p.y === ny && p.delay <= 0);
      if (hitPowerup !== -1) {
        const pu = powerups.splice(hitPowerup, 1)[0];
        meltingPowerups.push({ x: pu.x, y: pu.y, type: pu.type, timer: POWERUP_MELT_DURATION });
        explosions.push({ x: nx, y: ny, timer: EXPLOSION_DURATION, duration: EXPLOSION_DURATION });
        break;
      }
      if (grid[ny][nx] === BRICK) {
        grid[ny][nx] = BRICK_MELTING;
        meltingBricks.push({ x: nx, y: ny, timer: MELT_DURATION });
        if (Math.random() < POWERUP_DROP_RATE) {
          const r = Math.random();
          let type;
          if (r < 0.38) type = 'bomb';
          else if (r < 0.76) type = 'fire';
          else if (r < 0.88 && kickSpawned < KICK_MAX) { type = 'kick'; kickSpawned++; }
          else if (r < 1 && punchSpawned < PUNCH_MAX) { type = 'punch'; punchSpawned++; }
          else type = Math.random() < 0.5 ? 'bomb' : 'fire';
          powerups.push({ x: nx, y: ny, type, delay: POWERUP_SPAWN_DELAY });
        }
        explosions.push({ x: nx, y: ny, timer: EXPLOSION_DURATION, duration: EXPLOSION_DURATION });
        break;
      }
      explosions.push({ x: nx, y: ny, timer: EXPLOSION_DURATION, duration: EXPLOSION_DURATION });
    }
  }
}

function isInBlast(x, y, extraBombs) {
  if (explosions.some(e => e.x === x && e.y === y)) return true;
  const allBombs = extraBombs ? [...bombs, ...extraBombs] : bombs;
  for (const b of allBombs) {
    if (b.x === x && b.y === y) return true;
    const dirs = [[0, -1], [0, 1], [-1, 0], [1, 0]];
    for (const [dx, dy] of dirs) {
      for (let i = 1; i <= b.range; i++) {
        const nx = b.x + dx * i;
        const ny = b.y + dy * i;
        if (nx < 0 || nx >= COLS || ny < 0 || ny >= ROWS) break;
        if (grid[ny][nx] === WALL || grid[ny][nx] === BRICK_MELTING) break;
        if (nx === x && ny === y) return true;
        if (grid[ny][nx] === BRICK) break;
      }
    }
  }
  return false;
}

function canWalkSafe(x, y) {
  if (x < 0 || x >= COLS || y < 0 || y >= ROWS) return false;
  if (grid[y][x] !== EMPTY) return false;
  if (bombs.some(b => b.x === x && b.y === y)) return false;
  return true;
}

function bfsPath(sx, sy, tx, ty) {
  if (sx === tx && sy === ty) return null;
  const visited = new Set();
  const queue = [[sx, sy, []]];
  visited.add(`${sx},${sy}`);
  while (queue.length > 0) {
    const [cx, cy, path] = queue.shift();
    const dirs = [[0, -1], [0, 1], [-1, 0], [1, 0]];
    for (const [dx, dy] of dirs) {
      const nx = cx + dx;
      const ny = cy + dy;
      const key = `${nx},${ny}`;
      if (visited.has(key)) continue;
      if (!canWalkSafe(nx, ny)) continue;
      const newPath = [...path, { x: nx, y: ny }];
      if (nx === tx && ny === ty) return newPath;
      visited.add(key);
      queue.push([nx, ny, newPath]);
    }
  }
  return null;
}

function bfsPathAvoidBlast(sx, sy, tx, ty, extraBombs) {
  if (sx === tx && sy === ty) return null;
  const visited = new Set();
  const queue = [[sx, sy, []]];
  visited.add(`${sx},${sy}`);
  while (queue.length > 0) {
    const [cx, cy, path] = queue.shift();
    const dirs = [[0, -1], [0, 1], [-1, 0], [1, 0]];
    for (const [dx, dy] of dirs) {
      const nx = cx + dx;
      const ny = cy + dy;
      const key = `${nx},${ny}`;
      if (visited.has(key)) continue;
      if (!canWalkSafe(nx, ny)) continue;
      if (isInBlast(nx, ny, extraBombs) && !(nx === tx && ny === ty)) continue;
      const newPath = [...path, { x: nx, y: ny }];
      if (nx === tx && ny === ty) return newPath;
      visited.add(key);
      queue.push([nx, ny, newPath]);
    }
  }
  return null;
}

function findSafeCell(sx, sy, extraBombs) {
  const visited = new Set();
  const queue = [[sx, sy, 0]];
  visited.add(`${sx},${sy}`);
  while (queue.length > 0) {
    const [cx, cy, dist] = queue.shift();
    if (!isInBlast(cx, cy, extraBombs)) return { x: cx, y: cy, dist };
    const dirs = [[0, -1], [0, 1], [-1, 0], [1, 0]];
    for (const [dx, dy] of dirs) {
      const nx = cx + dx;
      const ny = cy + dy;
      const key = `${nx},${ny}`;
      if (visited.has(key)) continue;
      if (!canWalkSafe(nx, ny)) continue;
      visited.add(key);
      queue.push([nx, ny, dist + 1]);
    }
  }
  return null;
}

function findNearestTarget(e) {
  let nearest = null;
  let bestDist = Infinity;
  const candidates = [];
  candidates.push({ x: player.x, y: player.y, priority: 0 });
  for (const other of enemies) {
    if (other !== e && other.alive) candidates.push({ x: other.x, y: other.y, priority: 0 });
  }
  for (const p of powerups) {
    if (p.delay > 0) continue;
    candidates.push({ x: p.x, y: p.y, priority: 1 });
  }
  for (const t of candidates) {
    const d = Math.abs(e.x - t.x) + Math.abs(e.y - t.y);
    const score = d - t.priority * 4;
    if (score < bestDist) { bestDist = score; nearest = t; }
  }
  return nearest;
}

function setEnemyDir(e, dx, dy) {
  if (dy < 0) e.dir = 'up';
  else if (dy > 0) e.dir = 'down';
  else if (dx < 0) e.dir = 'left';
  else if (dx > 0) e.dir = 'right';
}

function updateSingleEnemy(e) {
  if (!e.alive) return;
  if (e.stunTimer > 0) { e.stunTimer--; return; }
  e.moveTimer--;
  if (e.moveTimer > 0) return;
  e.moveTimer = ENEMY_MOVE_DELAY;

  const dirs = [[0, -1], [0, 1], [-1, 0], [1, 0]];
  const maxEscapeSteps = Math.floor(BOMB_TIMER / ENEMY_MOVE_DELAY) - 2;

  const needsFlee = (extraBombs) => {
    if (isInBlast(e.x, e.y, extraBombs)) return true;
    const myBombs2 = extraBombs ? bombs.concat(extraBombs) : bombs.filter(b => b.owner === e.id);
    return myBombs2.some(b => Math.abs(e.x - b.x) + Math.abs(e.y - b.y) <= b.range + 2);
  };

  const fleeIsValid = (ft, extraBombs) => {
    if (!ft) return false;
    if (!canWalkSafe(ft.x, ft.y)) return false;
    if (isInBlast(ft.x, ft.y, extraBombs)) return false;
    const p = bfsPathAvoidBlast(e.x, e.y, ft.x, ft.y, extraBombs) || bfsPath(e.x, e.y, ft.x, ft.y);
    return p !== null;
  };

  const findFleeTarget = (extraBombs) => {
    const safe = findSafeCell(e.x, e.y, extraBombs);
    if (!safe) return null;
    const path = bfsPathAvoidBlast(e.x, e.y, safe.x, safe.y, extraBombs) || bfsPath(e.x, e.y, safe.x, safe.y);
    if (path && path.length > 0) return { x: safe.x, y: safe.y };
    return null;
  };

  const doFleeStep = (extraBombs) => {
    if (fleeIsValid(e.fleeTarget, extraBombs)) {
      const path = bfsPathAvoidBlast(e.x, e.y, e.fleeTarget.x, e.fleeTarget.y, extraBombs) || bfsPath(e.x, e.y, e.fleeTarget.x, e.fleeTarget.y);
      if (path && path.length > 0) {
        setEnemyDir(e, path[0].x - e.x, path[0].y - e.y);
        e.x = path[0].x; e.y = path[0].y;
        return;
      }
    }
    const ft = findFleeTarget(extraBombs);
    if (ft) {
      e.fleeTarget = ft;
      const path = bfsPathAvoidBlast(e.x, e.y, ft.x, ft.y, extraBombs) || bfsPath(e.x, e.y, ft.x, ft.y);
      if (path && path.length > 0) {
        setEnemyDir(e, path[0].x - e.x, path[0].y - e.y);
        e.x = path[0].x; e.y = path[0].y;
        return;
      }
    }
    const safeDirs = dirs.filter(([dx, dy]) => {
      const nx = e.x + dx, ny = e.y + dy;
      return canWalkSafe(nx, ny);
    });
    let bestDir = null, bestDist = -1;
    for (const [dx, dy] of safeDirs) {
      const nx = e.x + dx, ny = e.y + dy;
      let minBombDist = Infinity;
      for (const b of bombs) { minBombDist = Math.min(minBombDist, Math.abs(nx - b.x) + Math.abs(ny - b.y)); }
      if (minBombDist > bestDist) { bestDist = minBombDist; bestDir = [dx, dy]; }
    }
    if (bestDir) { setEnemyDir(e, bestDir[0], bestDir[1]); e.x += bestDir[0]; e.y += bestDir[1]; }
  };

  if (needsFlee()) { doFleeStep(); return; }

  e.fleeTarget = null;
  const myBombs = bombs.filter(b => b.owner === e.id);
  const nearOwnBomb = myBombs.some(b => Math.abs(e.x - b.x) + Math.abs(e.y - b.y) <= b.range + 2);
  if (nearOwnBomb) { doFleeStep(); return; }

  const activeBombs = myBombs.length;
  const target = findNearestTarget(e);

  const moveRandomSafe = () => {
    const safeDirs = dirs.filter(([dx, dy]) => {
      const nx = e.x + dx, ny = e.y + dy;
      if (!canWalkSafe(nx, ny)) return false;
      if (isInBlast(nx, ny)) return false;
      return true;
    });
    if (safeDirs.length > 0) {
      const pick = safeDirs[Math.floor(Math.random() * safeDirs.length)];
      setEnemyDir(e, pick[0], pick[1]);
      e.x += pick[0]; e.y += pick[1];
    }
  };

  const tryPlaceBomb = (bx, by) => {
    if (activeBombs >= e.maxBombs) return false;
    if (isInBlast(e.x, e.y)) return false;
    const simBomb = { x: bx, y: by, range: e.fireRange, owner: e.id };
    const safe = findSafeCell(e.x, e.y, [simBomb]);
    if (!safe) return false;
    const path = bfsPathAvoidBlast(e.x, e.y, safe.x, safe.y, [simBomb]) || bfsPath(e.x, e.y, safe.x, safe.y);
    if (!path || path.length > maxEscapeSteps) return false;
    bombs.push({ x: bx, y: by, timer: BOMB_TIMER, range: e.fireRange, owner: e.id, slideDx: 0, slideDy: 0, slideTimer: 0 });
    return true;
  };

  if (!target) { moveRandomSafe(); return; }

  const path = bfsPath(e.x, e.y, target.x, target.y);

  if (path && path.length > 0) {
    const nextStep = path[0];
    if (isInBlast(nextStep.x, nextStep.y)) { moveRandomSafe(); return; }
    setEnemyDir(e, nextStep.x - e.x, nextStep.y - e.y);
    e.x = nextStep.x; e.y = nextStep.y;
    const dist = Math.abs(e.x - target.x) + Math.abs(e.y - target.y);
    if (dist <= e.fireRange && dist > 0 && activeBombs < e.maxBombs) {
      tryPlaceBomb(e.x, e.y);
    }
  } else {
    const hasAdjacentBrick = dirs.some(([dx, dy]) => {
      const nx = e.x + dx, ny = e.y + dy;
      return nx >= 0 && nx < COLS && ny >= 0 && ny < ROWS && grid[ny][nx] === BRICK;
    });
    if (hasAdjacentBrick) {
      tryPlaceBomb(e.x, e.y);
    } else {
      moveRandomSafe();
    }
  }
}

function movePlayer(dx, dy) {
  const nx = player.x + dx;
  const ny = player.y + dy;
  if (nx < 0 || nx >= COLS || ny < 0 || ny >= ROWS) return;
  if (grid[ny][nx] !== EMPTY) return;
  const bombAtDest = bombs.find(b => b.x === nx && b.y === ny);
  if (bombAtDest) {
    if (player.hasKick && !(bombAtDest.slideDx || bombAtDest.slideDy)) {
      const sx = nx + dx;
      const sy = ny + dy;
      if (sx >= 0 && sx < COLS && sy >= 0 && sy < ROWS && grid[sy][sx] === EMPTY && !bombs.some(b => b.x === sx && b.y === sy)) {
        bombAtDest.x = sx;
        bombAtDest.y = sy;
        bombAtDest.slideDx = dx;
        bombAtDest.slideDy = dy;
        bombAtDest.slideTimer = BOMB_SLIDE_SPEED;
        player.x = nx;
        player.y = ny;
      }
    }
    return;
  }
  player.x = nx;
  player.y = ny;
}

function punchBomb() {
  if (!player.hasPunch) return;
  const dirMap = { up: [0, -1], down: [0, 1], left: [-1, 0], right: [1, 0] };
  const [ddx, ddy] = dirMap[player.dir];
  const bx = player.x + ddx;
  const by = player.y + ddy;
  const bomb = bombs.find(b => b.x === bx && b.y === by && !(b.slideDx || b.slideDy));
  if (!bomb) return;
  const tx = bomb.x + ddx * 2;
  const ty = bomb.y + ddy * 2;
  if (tx >= 0 && tx < COLS && ty >= 0 && ty < ROWS && grid[ty][tx] === EMPTY && !bombs.some(b => b !== bomb && b.x === tx && b.y === ty)) {
    const enemy = enemies.find(e => e.alive && e.x === tx && e.y === ty);
    if (enemy) enemy.stunTimer = STUN_DURATION;
    bomb.x = tx;
    bomb.y = ty;
    return;
  }
  for (let i = 1; i < Math.max(COLS, ROWS); i++) {
    const cx = tx - ddx * i;
    const cy = ty - ddy * i;
    if (cx < 0 || cx >= COLS || cy < 0 || cy >= ROWS) break;
    if (grid[cy][cx] === WALL || grid[cy][cx] === BRICK || grid[cy][cx] === BRICK_MELTING) break;
    if (grid[cy][cx] === EMPTY && !bombs.some(b => b !== bomb && b.x === cx && b.y === cy)) {
      const enemy = enemies.find(e => e.alive && e.x === cx && e.y === cy);
      if (enemy) enemy.stunTimer = STUN_DURATION;
      bomb.x = cx;
      bomb.y = cy;
      return;
    }
  }
}

let moveTimer = 0;
const PLAYER_MOVE_DELAY = 8;

function update() {
  if (gameOver) return;
  frame++;

  player.rx += (player.x - player.rx) * LERP_SPEED;
  player.ry += (player.y - player.ry) * LERP_SPEED;
  if (Math.abs(player.x - player.rx) < 0.01) player.rx = player.x;
  if (Math.abs(player.y - player.ry) < 0.01) player.ry = player.y;
  for (const e of enemies) {
    if (!e.alive) continue;
    e.rx += (e.x - e.rx) * LERP_SPEED;
    e.ry += (e.y - e.ry) * LERP_SPEED;
    if (Math.abs(e.x - e.rx) < 0.01) e.rx = e.x;
    if (Math.abs(e.y - e.ry) < 0.01) e.ry = e.y;
  }

  moveTimer--;
  if (moveTimer <= 0) {
    let moved = false;
    if (keys['ArrowUp'] || keys['w'] || keys['W']) { movePlayer(0, -1); moved = true; player.dir = 'up'; }
    else if (keys['ArrowDown'] || keys['s'] || keys['S']) { movePlayer(0, 1); moved = true; player.dir = 'down'; }
    else if (keys['ArrowLeft'] || keys['a'] || keys['A']) { movePlayer(-1, 0); moved = true; player.dir = 'left'; }
    else if (keys['ArrowRight'] || keys['d'] || keys['D']) { movePlayer(1, 0); moved = true; player.dir = 'right'; }
    if (moved) moveTimer = PLAYER_MOVE_DELAY;
  }

  for (let i = bombs.length - 1; i >= 0; i--) {
    bombs[i].timer--;
    if (bombs[i].timer <= 0) {
      explode(bombs[i]);
      bombs.splice(i, 1);
    }
  }

  for (const b of bombs) {
    if ((b.slideDx || b.slideDy) && b.slideTimer !== undefined) {
      b.slideTimer--;
      if (b.slideTimer <= 0) {
        b.slideTimer = BOMB_SLIDE_SPEED;
        const nx = b.x + b.slideDx;
        const ny = b.y + b.slideDy;
        if (nx >= 0 && nx < COLS && ny >= 0 && ny < ROWS && grid[ny][nx] === EMPTY && !bombs.some(ob => ob !== b && ob.x === nx && ob.y === ny)) {
          b.x = nx;
          b.y = ny;
        } else {
          b.slideDx = 0;
          b.slideDy = 0;
        }
      }
    }
  }

  for (let i = explosions.length - 1; i >= 0; i--) {
    explosions[i].timer--;
    if (explosions[i].timer <= 0) {
      explosions.splice(i, 1);
    }
  }

  for (let i = meltingBricks.length - 1; i >= 0; i--) {
    meltingBricks[i].timer--;
    if (meltingBricks[i].timer <= 0) {
      const m = meltingBricks[i];
      grid[m.y][m.x] = EMPTY;
      meltingBricks.splice(i, 1);
    }
  }

  for (let i = meltingPowerups.length - 1; i >= 0; i--) {
    meltingPowerups[i].timer--;
    if (meltingPowerups[i].timer <= 0) {
      meltingPowerups.splice(i, 1);
    }
  }

  for (const e of enemies) updateSingleEnemy(e);

  for (const ex of explosions) {
    if (ex.x === player.x && ex.y === player.y) { gameOver = true; playerWon = false; }
    for (const e of enemies) {
      if (ex.x === e.x && ex.y === e.y && e.alive) e.alive = false;
    }
  }

  if (enemies.every(e => !e.alive)) { gameOver = true; playerWon = true; }

  for (let i = powerups.length - 1; i >= 0; i--) {
    const p = powerups[i];
    if (p.delay > 0) { p.delay--; continue; }
    const inExplosion = explosions.some(ex => ex.x === p.x && ex.y === p.y);
    if (inExplosion) { meltingPowerups.push({ x: p.x, y: p.y, type: p.type, timer: POWERUP_MELT_DURATION }); powerups.splice(i, 1); continue; }
    if (p.x === player.x && p.y === player.y) {
      if (p.type === 'bomb') player.maxBombs++;
      else if (p.type === 'fire') player.fireRange++;
      else if (p.type === 'kick') player.hasKick = true;
      else if (p.type === 'punch') player.hasPunch = true;
      powerups.splice(i, 1);
    } else {
      for (const e of enemies) {
        if (e.alive && p.x === e.x && p.y === e.y) {
          if (p.type === 'bomb') e.maxBombs++;
          else if (p.type === 'fire') e.fireRange++;
          powerups.splice(i, 1);
          break;
        }
      }
    }
  }
}

function drawHUD() {
  const bx = 8, by = 8, bw = 280, bh = 40;
  ctx.fillStyle = 'rgba(20,16,36,0.85)';
  roundRect(bx, by, bw, bh, 8);
  ctx.fill();
  ctx.strokeStyle = 'rgba(124,77,255,0.4)';
  ctx.lineWidth = 1;
  roundRect(bx, by, bw, bh, 8);
  ctx.stroke();
  ctx.textBaseline = 'middle';
  ctx.font = 'bold 14px sans-serif';
  const ty = by + bh / 2;
  ctx.fillStyle = '#b388ff';
  ctx.textAlign = 'left';
  ctx.fillText('\u2726', bx + 10, ty);
  ctx.fillStyle = '#e1bee7';
  ctx.fillText(`${player.maxBombs}`, bx + 25, ty);
  ctx.fillStyle = '#ffab40';
  ctx.fillText('\u2741', bx + 55, ty);
  ctx.fillStyle = '#ffe0b2';
  ctx.fillText(`${player.fireRange}`, bx + 73, ty);
  if (player.hasKick) {
    ctx.fillStyle = '#00bcd4';
    ctx.fillText('\u26A1', bx + 105, ty);
    ctx.fillStyle = '#b2ebf2';
    ctx.fillText('KICK', bx + 122, ty);
  }
  if (player.hasPunch) {
    const px = player.hasKick ? bx + 170 : bx + 105;
    ctx.fillStyle = '#ffc107';
    ctx.fillText('\u2735', px, ty);
    ctx.fillStyle = '#fff9c4';
    ctx.fillText('PNCH', px + 17, ty);
  }
  ctx.textAlign = 'start';
  ctx.textBaseline = 'alphabetic';
}

function render() {
  ctx.fillStyle = '#16142a';
  ctx.fillRect(0, 0, canvas.width, canvas.height);

  for (let r = 0; r < ROWS; r++) {
    for (let c = 0; c < COLS; c++) {
      if (grid[r][c] === WALL) drawWall(c, r);
      else if (grid[r][c] === BRICK) drawBrick(c, r);
      else if (grid[r][c] === BRICK_MELTING) {
        const m = meltingBricks.find(mb => mb.x === c && mb.y === r);
        if (m) drawMeltingBrick(c, r, m);
      }
      else drawFloor(c, r);
    }
  }

  for (const p of powerups) drawPowerup(p);
  for (const m of meltingPowerups) drawMeltingPowerup(m);
  for (const b of bombs) drawBomb(b);
  for (const e of explosions) drawExplosion(e);
  for (let r = 0; r < ROWS; r++) {
    for (let c = 0; c < COLS; c++) {
      if (grid[r][c] === WALL) drawWall(c, r);
      else if (grid[r][c] === BRICK) drawBrick(c, r);
      else if (grid[r][c] === BRICK_MELTING) {
        const m = meltingBricks.find(mb => mb.x === c && mb.y === r);
        if (m) drawMeltingBrick(c, r, m);
      }
    }
  }
  drawPlayer();
  for (const e of enemies) drawEnemy(e);
  drawHUD();

  if (gameOver) {
    ctx.fillStyle = 'rgba(10,8,24,0.8)';
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    const cy = canvas.height / 2;

    ctx.fillStyle = playerWon ? '#7c4dff' : '#f44336';
    ctx.shadowColor = playerWon ? '#7c4dff' : '#f44336';
    ctx.shadowBlur = 20;
    ctx.font = 'bold 56px sans-serif';
    ctx.fillText(playerWon ? 'VICTORY' : 'DEFEATED', canvas.width / 2, cy - 20);
    ctx.shadowBlur = 0;

    ctx.fillStyle = 'rgba(255,255,255,0.7)';
    ctx.font = '18px sans-serif';
    ctx.fillText('Press R to restart', canvas.width / 2, cy + 30);

    ctx.textAlign = 'start';
    ctx.textBaseline = 'alphabetic';
  }
}

function loop() {
  update();
  render();
  requestAnimationFrame(loop);
}

document.addEventListener('keydown', e => {
  keys[e.key] = true;
  if (gameOver && (e.key === 'r' || e.key === 'R')) {
    initGrid();
    player.x = 1; player.y = 1; player.rx = 1; player.ry = 1; player.maxBombs = START_MAX_BOMBS; player.fireRange = START_FIRE_RANGE; player.dir = 'down'; player.hasKick = false; player.hasPunch = false;
    enemies[0].x = COLS - 2; enemies[0].y = ROWS - 2; enemies[0].rx = COLS - 2; enemies[0].ry = ROWS - 2; enemies[0].alive = true; enemies[0].maxBombs = START_MAX_BOMBS; enemies[0].fireRange = ENEMY_FIRE_RANGE; enemies[0].moveTimer = 0; enemies[0].dir = 'left'; enemies[0].stunTimer = 0; enemies[0].fleeTarget = null;
    enemies[1].x = COLS - 2; enemies[1].y = 1; enemies[1].rx = COLS - 2; enemies[1].ry = 1; enemies[1].alive = true; enemies[1].maxBombs = START_MAX_BOMBS; enemies[1].fireRange = ENEMY_FIRE_RANGE; enemies[1].moveTimer = 0; enemies[1].dir = 'down'; enemies[1].stunTimer = 0; enemies[1].fleeTarget = null;
    enemies[2].x = 1; enemies[2].y = ROWS - 2; enemies[2].rx = 1; enemies[2].ry = ROWS - 2; enemies[2].alive = true; enemies[2].maxBombs = START_MAX_BOMBS; enemies[2].fireRange = ENEMY_FIRE_RANGE; enemies[2].moveTimer = 0; enemies[2].dir = 'right'; enemies[2].stunTimer = 0; enemies[2].fleeTarget = null;
    bombs = []; explosions = []; powerups = []; meltingBricks = []; meltingPowerups = [];
    kickSpawned = 0; punchSpawned = 0;
    gameOver = false; playerWon = false; moveTimer = 0; frame = 0; keys = {};
    return;
  }
  if (e.key === ' ' || e.key === 'e' || e.key === 'E') placeBomb();
  if (e.key === 'q' || e.key === 'Q') punchBomb();
  if (e.key === ' ' || e.key === 'e' || e.key === 'E' || e.key === 'q' || e.key === 'Q' || e.key.startsWith('Arrow')) e.preventDefault();
});
document.addEventListener('keyup', e => { keys[e.key] = false; });

initGrid();
loop();