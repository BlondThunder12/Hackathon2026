#!/usr/bin/env python3
"""
Challenge 8: PC Retro Game — Sweep Tetris

A Tetris variant where the active piece auto-sweeps left/right across the board.
You cannot move the piece horizontally — only timing and rotation matter.

Controls:
  KEY0       = rotate clockwise
  KEY1       = hard drop  (or restart when game over)
  SW[9:8]    = starting difficulty  (0=Easy … 3=Insane)
  SW[7:4]    = color theme  (0–15, cycles through 4 built-in themes)
  SW[3:0]    = bit 0: ghost piece on/off  |  bits 3:1: level head-start (0–7)
  SW[4]      = debug overlay

Keyboard fallback (no hardware needed):
  UP / Z   = rotate      SPACE = hard drop
  P / ESC  = pause       R     = restart

Usage:
  python game.py [COM_PORT]   # explicit port
  python game.py              # auto-detect; falls back to keyboard-only
"""

import sys, threading, time, random
import pygame

try:
    import serial, serial.tools.list_ports
    SERIAL_AVAILABLE = True
except ImportError:
    SERIAL_AVAILABLE = False

# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------
CELL          = 28
COLS, ROWS    = 10, 20
GRID_X        = 14
GRID_Y        = 22
PANEL_X       = GRID_X + COLS * CELL + 14   # 308
SCREEN_W      = PANEL_X + 178               # 486
SCREEN_H      = GRID_Y * 2 + ROWS * CELL    # 604
FPS           = 60
BAUD_PC       = 115200

# ---------------------------------------------------------------------------
# Difficulty: (sweep_ms, gravity_ms)
# ---------------------------------------------------------------------------
DIFF = [
    (560, 3000),  # 0 — Easy
    (380, 2200),  # 1 — Medium
    (230, 1600),  # 2 — Hard
    (110, 1100),  # 3 — Insane
]
DIFF_NAMES = ["EASY", "MEDIUM", "HARD", "INSANE"]

# ---------------------------------------------------------------------------
# Themes: (bg, grid_line, text_color, 7-color piece palette)
# ---------------------------------------------------------------------------
def _pal(*colors): return list(colors)

THEMES = [
    # classic
    ((18, 18, 28), (42, 42, 58), (220, 220, 220), _pal(
        (0,220,220),(220,220,0),(160,0,220),(0,200,0),
        (220,0,0),(0,80,220),(220,120,0))),
    # night
    ((10, 10, 20), (30, 30, 46), (180, 200, 255), _pal(
        (40,200,255),(200,200,50),(200,50,255),(50,255,100),
        (255,50,100),(50,100,255),(255,140,0))),
    # desert
    ((75, 45, 18), (105, 72, 38), (255, 230, 180), _pal(
        (220,180,80),(255,220,120),(200,100,40),(180,140,60),
        (240,80,40),(160,80,0),(255,160,40))),
    # forest
    ((15, 35, 18), (35, 60, 32), (190, 255, 190), _pal(
        (80,200,100),(180,220,80),(40,160,80),(100,200,60),
        (200,180,40),(60,140,80),(140,200,60))),
]

def get_theme(idx):
    return THEMES[idx % len(THEMES)]

# ---------------------------------------------------------------------------
# Tetrominoes — (row, col) offsets from pivot
# ---------------------------------------------------------------------------
PIECES = [
    [(0,-1),(0, 0),(0, 1),(0, 2)],   # I
    [(0, 0),(0, 1),(1, 0),(1, 1)],   # O
    [(0,-1),(0, 0),(0, 1),(1, 0)],   # T
    [(0, 0),(0, 1),(1,-1),(1, 0)],   # S
    [(0,-1),(0, 0),(1, 0),(1, 1)],   # Z
    [(0,-1),(0, 0),(0, 1),(1, 1)],   # J
    [(0,-1),(0, 0),(0, 1),(1,-1)],   # L
]

def rotate_cw(cells):
    return [(c, -r) for r, c in cells]

# ---------------------------------------------------------------------------
# Controllers
# ---------------------------------------------------------------------------
class ControllerThread(threading.Thread):
    def __init__(self, port):
        super().__init__(daemon=True)
        self.port      = port
        self._lock     = threading.Lock()
        self._running  = True
        self._ser      = None
        self.connected = False
        self.key0 = self.key1 = False
        self.switches  = 0
        self._k0p = self._k1p = False
        self._e0  = self._e1  = False

    def run(self):
        try:
            self._ser = serial.Serial(self.port, BAUD_PC, timeout=0.1)
            self.connected = True
            print(f"[Serial] Connected on {self.port}")
        except Exception as e:
            print(f"[Serial] {e}"); return
        buf = bytearray()
        while self._running:
            try:
                chunk = self._ser.read(64)
                if chunk: buf.extend(chunk)
                while len(buf) >= 3:
                    if buf[0] != 0xAA: buf.pop(0); continue
                    ctrl, sw_lo = buf[1], buf[2]
                    if ctrl & 0xF0: buf.pop(0); continue
                    k0 = bool(ctrl & 1); k1 = bool(ctrl & 2)
                    sw = ((ctrl & 0x0C) << 6) | sw_lo
                    with self._lock:
                        self._e0 |= k0 and not self._k0p
                        self._e1 |= k1 and not self._k1p
                        self._k0p = k0; self._k1p = k1
                        self.key0 = k0; self.key1 = k1
                        self.switches = sw
                    del buf[:3]
            except Exception: break

    def get_state(self):
        with self._lock:
            s = dict(key0=self.key0, key1=self.key1,
                     key0_edge=self._e0, key1_edge=self._e1,
                     switches=self.switches, connected=self.connected)
            self._e0 = self._e1 = False
        return s

    def stop(self):
        self._running = False
        if self._ser: self._ser.close()


class KeyboardController:
    def __init__(self):
        self.switches  = 0
        self.connected = False
        self._e0 = self._e1 = False

    def handle_event(self, ev):
        if ev.type == pygame.KEYDOWN:
            if ev.key in (pygame.K_UP, pygame.K_z, pygame.K_x): self._e0 = True
            if ev.key == pygame.K_SPACE:                          self._e1 = True

    def get_state(self):
        s = dict(key0=False, key1=False, key0_edge=self._e0, key1_edge=self._e1,
                 switches=self.switches, connected=False)
        self._e0 = self._e1 = False
        return s

    def stop(self): pass

# ---------------------------------------------------------------------------
# Game
# ---------------------------------------------------------------------------
class SweepTetris:
    def __init__(self, ctrl):
        self.ctrl = ctrl
        pygame.init()
        self.screen = pygame.display.set_mode((SCREEN_W, SCREEN_H))
        pygame.display.set_caption("Sweep Tetris — Challenge 8")
        self.clock = pygame.time.Clock()
        self.f_big = pygame.font.SysFont("monospace", 40, bold=True)
        self.f_mid = pygame.font.SysFont("monospace", 22, bold=True)
        self.f_sm  = pygame.font.SysFont("monospace", 16)
        self._new_game()

    # ── setup ────────────────────────────────────────────────────────────────
    def _read_sw(self, sw):
        diff      = (sw >> 8) & 0x03
        theme_idx = (sw >> 4) & 0x0F
        ghost_on  = bool(sw & 0x01)
        lv_boost  = (sw >> 1) & 0x07
        debug     = bool(sw & 0x10)
        return diff, theme_idx, ghost_on, lv_boost, debug

    def _new_game(self):
        sw = self.ctrl.get_state()['switches']
        diff, theme_idx, self.ghost_on, lv_boost, self.debug = self._read_sw(sw)
        self.diff_idx  = diff
        self.theme     = get_theme(theme_idx)
        self.level     = lv_boost
        self.score     = 0
        self.lines     = 0
        self.board     = [[None] * COLS for _ in range(ROWS)]
        self.paused    = False
        self.game_over = False
        self._bag      = []
        self._next     = self._draw_piece()
        self._spawn()
        now = pygame.time.get_ticks()
        self._t_sweep = now
        self._t_grav  = now

    def _draw_piece(self):
        if not self._bag:
            self._bag = list(range(len(PIECES)))
            random.shuffle(self._bag)
        return self._bag.pop()

    def _spawn(self):
        self.ptype    = self._next
        self._next    = self._draw_piece()
        self.cells    = list(PIECES[self.ptype])
        self.pr       = 0               # pivot row
        self.pc       = COLS // 2       # pivot col
        self._dir     = 1               # sweep direction
        if not self._valid(self.cells, self.pr, self.pc):
            self.game_over = True

    def _valid(self, cells, pr, pc):
        for dr, dc in cells:
            r, c = pr + dr, pc + dc
            if r < 0 or r >= ROWS or c < 0 or c >= COLS: return False
            if self.board[r][c] is not None:              return False
        return True

    def _lock(self):
        color = self.theme[3][self.ptype]
        for dr, dc in self.cells:
            r, c = self.pr + dr, self.pc + dc
            if 0 <= r < ROWS and 0 <= c < COLS:
                self.board[r][c] = color
        self._clear_lines()
        self._spawn()

    def _clear_lines(self):
        full = [r for r in range(ROWS)
                if all(self.board[r][c] is not None for c in range(COLS))]
        if not full: return
        for r in full:
            del self.board[r]
            self.board.insert(0, [None] * COLS)
        n = len(full)
        self.lines += n
        self.score += [0, 100, 300, 500, 800][min(n, 4)] * (self.level + 1)
        self.level  = max(self.level, self.lines // 5)

    # ── timing ───────────────────────────────────────────────────────────────
    def _sweep_ms(self):
        base = DIFF[self.diff_idx][0]
        return max(80, int(base * max(0.35, 1.0 - self.level * 0.06)))

    def _grav_ms(self):
        base = DIFF[self.diff_idx][1]
        return max(400, int(base * max(0.35, 1.0 - self.level * 0.06)))

    # ── actions ──────────────────────────────────────────────────────────────
    def _rotate(self):
        rotated = rotate_cw(self.cells)
        # Try column kicks ±2, then allow a downward row kick if near top
        for rk in (0, 1, 2):
            for ck in (0, 1, -1, 2, -2):
                if self._valid(rotated, self.pr + rk, self.pc + ck):
                    self.cells = rotated
                    self.pr   += rk
                    self.pc   += ck
                    return

    def _hard_drop(self):
        dr = 0
        while self._valid(self.cells, self.pr + dr + 1, self.pc):
            dr += 1
        self.pr += dr
        self._lock()

    def _ghost_row(self):
        dr = 0
        while self._valid(self.cells, self.pr + dr + 1, self.pc):
            dr += 1
        return self.pr + dr

    # ── main loop ────────────────────────────────────────────────────────────
    def run(self):
        kbd = isinstance(self.ctrl, KeyboardController)
        while True:
            self.clock.tick(FPS)
            now = pygame.time.get_ticks()

            for ev in pygame.event.get():
                if ev.type == pygame.QUIT:
                    self.ctrl.stop(); pygame.quit(); sys.exit()
                if kbd: self.ctrl.handle_event(ev)
                if ev.type == pygame.KEYDOWN:
                    if ev.key in (pygame.K_p, pygame.K_ESCAPE) and not self.game_over:
                        self.paused = not self.paused
                    if ev.key == pygame.K_r and self.game_over:
                        self._new_game()
                    # keyboard always works as fallback even with serial
                    if ev.key in (pygame.K_UP, pygame.K_z) and not kbd:
                        if not self.paused and not self.game_over: self._rotate()
                    if ev.key == pygame.K_SPACE and not kbd:
                        if self.game_over: self._new_game()
                        elif not self.paused: self._hard_drop()

            state = self.ctrl.get_state()
            # Read SW settings live (switches update theme/ghost in real time)
            _, theme_idx, self.ghost_on, _, self.debug = self._read_sw(state['switches'])
            self.theme = get_theme(theme_idx)

            if state['key0_edge'] and not self.paused and not self.game_over:
                self._rotate()
            if state['key1_edge']:
                if self.game_over: self._new_game()
                elif not self.paused: self._hard_drop()

            if not self.paused and not self.game_over:
                if now - self._t_sweep >= self._sweep_ms():
                    self._t_sweep = now
                    nc = self.pc + self._dir
                    if self._valid(self.cells, self.pr, nc):
                        self.pc = nc
                    else:
                        self._dir = -self._dir          # bounce off wall

                if now - self._t_grav >= self._grav_ms():
                    self._t_grav = now
                    if self._valid(self.cells, self.pr + 1, self.pc):
                        self.pr += 1
                    else:
                        self._lock()

            self._draw(state)
            pygame.display.flip()

    # ── drawing ──────────────────────────────────────────────────────────────
    def _draw(self, state):
        bg, grid_c, txt_c, pal = self.theme
        self.screen.fill(bg)

        gw = COLS * CELL
        gh = ROWS * CELL

        # Grid background
        pygame.draw.rect(self.screen, (0, 0, 0), (GRID_X, GRID_Y, gw, gh))

        # Grid lines
        for c in range(COLS + 1):
            x = GRID_X + c * CELL
            pygame.draw.line(self.screen, grid_c, (x, GRID_Y), (x, GRID_Y + gh))
        for r in range(ROWS + 1):
            y = GRID_Y + r * CELL
            pygame.draw.line(self.screen, grid_c, (GRID_X, y), (GRID_X + gw, y))

        # Locked cells
        for r in range(ROWS):
            for c in range(COLS):
                if self.board[r][c]:
                    self._cell(r, c, self.board[r][c])

        # Ghost piece
        if self.ghost_on and not self.game_over:
            gr  = self._ghost_row()
            dim = tuple(max(0, v - 90) for v in pal[self.ptype])
            for dr, dc in self.cells:
                r, c = gr + dr, self.pc + dc
                if 0 <= r < ROWS and 0 <= c < COLS:
                    self._cell(r, c, dim, ghost=True)

        # Active piece
        if not self.game_over:
            for dr, dc in self.cells:
                r, c = self.pr + dr, self.pc + dc
                if 0 <= r < ROWS and 0 <= c < COLS:
                    self._cell(r, c, pal[self.ptype])

        # Sweep direction arrow above active column
        if not self.game_over and not self.paused:
            ax = GRID_X + self.pc * CELL + CELL // 2
            ay = GRID_Y - 6
            ac = pal[self.ptype]
            tip  = (ax + (8 if self._dir > 0 else -8), ay - 5)
            base = (ax - (8 if self._dir > 0 else -8), ay - 5)
            pygame.draw.polygon(self.screen, ac, [tip, (base[0], ay-10), (base[0], ay)])

        # ── Side panel ──────────────────────────────────────────────────────
        px = PANEL_X
        y  = GRID_Y

        def txt(text, dy, font="sm", color=None):
            f = {"sm": self.f_sm, "mid": self.f_mid, "big": self.f_big}[font]
            s = f.render(text, True, color or txt_c)
            self.screen.blit(s, (px, dy))
            return dy + s.get_height() + 3

        y = txt("NEXT",  y, "mid")
        y = self._draw_next(px, y, pal) + 10
        y = txt("SCORE", y, "sm")
        y = txt(str(self.score), y, "mid", (255, 220, 80))
        y = txt("LINES", y, "sm")
        y = txt(str(self.lines), y, "mid")
        y = txt("LEVEL", y, "sm")
        y = txt(str(self.level), y, "mid")
        y = txt(DIFF_NAMES[self.diff_idx], y + 4, "sm", (255, 200, 60))

        conn  = state.get('connected', False)
        y = txt("FPGA" if conn else "KB", y + 6, "sm", (60,220,60) if conn else (220,100,60))
        y = txt(f"Ghost {'ON' if self.ghost_on else 'OFF'}", y,
                "sm", (80,220,80) if self.ghost_on else (120,120,120))

        # Sweep arrow label
        arrow = "sweep >>>" if self._dir > 0 else "<<< sweep"
        txt(arrow, y, "sm", pal[self.ptype] if not self.game_over else txt_c)

        # Overlays
        if self.paused:
            self._overlay("PAUSED",    (255, 255, 100), "KEY1 / P  to unpause")
        if self.game_over:
            self._overlay("GAME OVER", (255,  60,  60), "KEY1 / R  to restart")

        # Debug
        if self.debug:
            dbg = [
                f"K0={int(state['key0'])} K1={int(state['key1'])}",
                f"SW=0x{state['switches']:03X}",
                f"swp={self._sweep_ms()}ms  grv={self._grav_ms()}ms",
            ]
            for i, line in enumerate(dbg):
                s = self.f_sm.render(line, True, (170, 170, 170))
                self.screen.blit(s, (GRID_X, GRID_Y + gh - (len(dbg) - i) * 18))

    def _cell(self, row, col, color, ghost=False):
        x = GRID_X + col * CELL + 1
        y = GRID_Y + row * CELL + 1
        s = CELL - 2
        if ghost:
            surf = pygame.Surface((s, s), pygame.SRCALPHA)
            surf.fill((*color, 110))
            self.screen.blit(surf, (x, y))
        else:
            pygame.draw.rect(self.screen, color, (x, y, s, s))
            hl = tuple(min(255, v + 65) for v in color)
            pygame.draw.line(self.screen, hl, (x, y), (x + s - 1, y))
            pygame.draw.line(self.screen, hl, (x, y), (x, y + s - 1))

    def _draw_next(self, px, py, pal):
        cells = PIECES[self._next]
        rs = [r for r, c in cells]; cs = [c for r, c in cells]
        SZ = 22
        ox = px + (4 * SZ - (max(cs) - min(cs) + 1) * SZ) // 2
        for dr, dc in cells:
            r = dr - min(rs); c = dc - min(cs)
            pygame.draw.rect(self.screen, pal[self._next],
                             (ox + c*SZ + 1, py + r*SZ + 1, SZ-2, SZ-2))
        return py + (max(rs) - min(rs) + 2) * SZ

    def _overlay(self, title, color, sub):
        cx = GRID_X + (COLS * CELL) // 2
        cy = GRID_Y + (ROWS * CELL) // 2
        s1 = self.f_big.render(title, True, color)
        s2 = self.f_sm.render(sub, True, (220, 220, 220))
        self.screen.blit(s1, (cx - s1.get_width()//2, cy - 44))
        self.screen.blit(s2, (cx - s2.get_width()//2, cy + 10))


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
def auto_detect_port():
    if not SERIAL_AVAILABLE: return None
    for p in serial.tools.list_ports.comports():
        if any(k in (p.description or "").upper()
               for k in ("CP210", "CH340", "UART", "USB SERIAL")):
            return p.device
    ports = list(serial.tools.list_ports.comports())
    return ports[0].device if ports else None

def main():
    port = sys.argv[1] if len(sys.argv) > 1 else (auto_detect_port() if SERIAL_AVAILABLE else None)
    if port and SERIAL_AVAILABLE:
        ctrl = ControllerThread(port)
        ctrl.start()
        time.sleep(0.3)
    else:
        if not SERIAL_AVAILABLE:
            print("pyserial not installed — keyboard-only mode.")
            print("  pip install pyserial pygame")
        else:
            print(f"No port found — keyboard-only mode.  Usage: python {sys.argv[0]} COM3")
        ctrl = KeyboardController()
    SweepTetris(ctrl).run()

if __name__ == "__main__":
    main()
