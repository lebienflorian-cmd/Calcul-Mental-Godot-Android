#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Jeu "Calcul Mental" — Python + pygame

Inspiré du design et de l'architecture fournis (menus, options, scores, scènes,
widgets custom, sauvegarde JSON, courbe d'historique, barres de défilement,
fenêtre redimensionnable, etc.).

Cinq modes de jeu :
  • Mode 1 (Contre-la-montre) : faire un maximum de calculs exacts dans un
    temps imparti.
  • Mode 2 (Série chronométrée) : résoudre un nombre fixé de calculs, mesurer
    le temps total et la vitesse.
  • Mode 3 (Flash Anzan) : mémoriser des nombres puis donner leur somme.
  • Mode 4 (Mode audio) : poser et répondre aux calculs uniquement à la voix.
  • Mode 5 (Calcul Infernal n-back) : répondre au calcul posé il y a N tours,
    un nouveau calcul arrivant à rythme fixe.


Options de difficulté (mixables) :
  • Opérations autorisées (+, −, ×, ÷) et mélange au sein d'une même expression.
  • Nombre d'opérandes (min..max).
  • Taille des nombres (unités, dizaines, centaines, milliers) + mélange.
  • Contraintes d'aisance : addition sans retenue (tentative), soustraction sans
    emprunt (simple), résultat toujours positif ou non, division avec quotient
    entier uniquement (par défaut).
  • Tables de multiplication limitées (ex.: jusqu'à 12).
  • Parenthèses (légères), insérées quand sûr (pas avec les divisions pour
    rester propres en entier).
  • Limite de temps par question (optionnelle) en mode 1 et 2.

Remarque : pour garder les divisions "propres" (entiers), le générateur évite
les parenthèses dès qu'une division est en jeu et construit les opérandes pour
que chaque division tombe juste.
"""
import os, sys, json, math, random, time, re, datetime, queue, tempfile, threading, shutil
import pygame
from utils_anim import lerp, ease_out_cubic
try:
    import pyttsx3
except Exception:
    pyttsx3 = None
try:
    import vosk, sounddevice as sd
    import json as _json
except Exception:
    vosk = None
    sd = None
    _json = None

APP_NAME = "Calcul Mental"
SAVE_DIR = os.path.dirname(os.path.abspath(__file__))
SCORES_PATH = os.path.join(SAVE_DIR, "scores_arith.json")
PROFILES_PATH = os.path.join(SAVE_DIR, "profiles_arith.json")
DEFAULT_PROFILE = "Défaut"
DEFAULT_PROFILE_SAFE = "defaut"

def profile_mode(opts):
    return opts.get("fixed_mode", opts.get("mode", 1))

def profiles_for_mode(profiles: dict, mode: int):
    names = [
        name for name, opts in profiles.items()
        if profile_mode(opts) == mode or name == DEFAULT_PROFILE
    ]
    if DEFAULT_PROFILE in names:
        names.remove(DEFAULT_PROFILE)
        names.insert(0, DEFAULT_PROFILE)
    return names

def _scores_file_for(profile: str) -> str:
    """Return score file path for a given profile name."""
    if profile == DEFAULT_PROFILE:
        return SCORES_PATH
    safe = re.sub(r"[^a-zA-Z0-9_-]+", "_", sanitize(profile)).lower() or DEFAULT_PROFILE_SAFE
    if safe in ("default", DEFAULT_PROFILE_SAFE):
        return SCORES_PATH
    return os.path.join(SAVE_DIR, f"scores_arith_{safe}.json")

pygame.init()
pygame.key.set_repeat(320, 28)

# --- Effets visuels: cadre néon + balayage périmétrique ---
def _draw_glow_line(surf, a, b, color, core_w=3, glow=10, alpha_mult=1.0):
    cr, cg, cb = color
    # couches de halo (du plus large au plus fin)
    for w in range(core_w + glow, core_w, -1):
        al = int(90 * alpha_mult * (w - core_w) / max(1, glow))
        pygame.draw.line(surf, (cr, cg, cb, al), a, b, w)
    # ligne cœur
    pygame.draw.line(surf, (cr, cg, cb, int(220 * alpha_mult)), a, b, core_w)

def _perimeter_offsets(rect):
    w, h = rect.w, rect.h
    # offsets cumulatifs des 4 côtés (haut→droite→bas→gauche)
    return (0, w, w + h, w + h + w, w + h + w + h)

def _edge_and_local_s(rect, s):
    """Retourne (edge_idx, s_local, edge_len) pour s le long du périmètre."""
    w, h = rect.w, rect.h
    P = 2 * (w + h)
    s = s % P
    o0, o1, o2, o3, _ = _perimeter_offsets(rect)
    if s < o1:   return 0, s - o0, w   # haut
    if s < o2:   return 1, s - o1, h   # droite
    if s < o3:   return 2, s - o2, w   # bas
    else:        return 3, s - o3, h   # gauche

def _edge_points(rect, edge_idx):
    if edge_idx == 0:  # top
        return (rect.left, rect.top), (rect.right, rect.top)
    if edge_idx == 1:  # right
        return (rect.right, rect.top), (rect.right, rect.bottom)
    if edge_idx == 2:  # bottom
        return (rect.right, rect.bottom), (rect.left, rect.bottom)
    # left
    return (rect.left, rect.bottom), (rect.left, rect.top)

def _lerp(a, b, t):
    return a[0] + (b[0]-a[0]) * t, a[1] + (b[1]-a[1]) * t

def _draw_segment_on_perimeter(surf, inner_rect, color, start_s, length, core_w, glow, alpha_mult=1.0):
    """Dessine un segment [start_s, start_s+length] le long du périmètre."""
    w, h = inner_rect.w, inner_rect.h
    P = 2 * (w + h)
    s = start_s % P
    L = length
    while L > 0:
        edge, s_local, edge_len = _edge_and_local_s(inner_rect, s)
        take = min(L, edge_len - s_local)
        a0, a1 = _edge_points(inner_rect, edge)
        p0 = _lerp(a0, a1, s_local / max(1, edge_len))
        p1 = _lerp(a0, a1, (s_local + take) / max(1, edge_len))
        _draw_glow_line(surf, p0, p1, color, core_w, glow, alpha_mult)
        L -= take
        s = (s + take) % P

def draw_neon_sweep_rect(surf, rect, base_color=(60,170,90), radius=12,
                         core_w=3, glow=12, sweep_t=0.0, sweep_speed=800.0, sweep_len=260,
                         intensity=1.0):
    """
    Dessine un cadre néon autour de rect, avec un 'tracer' qui balaye le périmètre.
    intensity ∈ [0,1] contrôle la force globale (pour le fade-out).
    """
    # Overlay élargi pour recevoir le halo
    ov = pygame.Surface((rect.w + 2*glow, rect.h + 2*glow), pygame.SRCALPHA)
    inner = pygame.Rect(glow, glow, rect.w, rect.h)

    # halo statique doux (anneaux de plus en plus grands)
    outer = (min(255, base_color[0] + 30),
             min(255, base_color[1] + 85),
             min(255, base_color[2] + 120))
    for k in range(glow, 0, -1):
        t = k / glow
        col = (
            int(base_color[0] + (outer[0] - base_color[0]) * (1 - t)),
            int(base_color[1] + (outer[1] - base_color[1]) * (1 - t)),
            int(base_color[2] + (outer[2] - base_color[2]) * (1 - t)),
        )
        al = int(80 * (t ** 1.5) * intensity)
        pygame.draw.rect(
            ov,
            (*col, al),
            pygame.Rect(glow - k, glow - k, rect.w + 2 * k, rect.h + 2 * k),
            width=max(1, core_w),
            border_radius=radius + k,
        )
    # balayage (un segment brillant + 2 traînes atténuées)
    P = 2 * (rect.w + rect.h)
    s0 = (sweep_t * sweep_speed) % P
    for offset, mult in ((0.0, 1.00), (0.55, 0.55), (1.10, 0.30)):
        _draw_segment_on_perimeter(ov, inner, base_color,
                                   start_s=(s0 - offset * sweep_len) % P,
                                   length=sweep_len, core_w=core_w, glow=glow, alpha_mult=mult * intensity)

    # additif = rendu lumineux
    surf.blit(ov, (rect.x - glow, rect.y - glow), special_flags=pygame.BLEND_ADD)

def lerp_color(a, b, t):
    return (
        int(a[0] + (b[0] - a[0]) * t),
        int(a[1] + (b[1] - a[1]) * t),
        int(a[2] + (b[2] - a[2]) * t),
    )


def _make_orb(radius, color=(255, 255, 255)):
    """Create a soft halo circle surface."""
    surf = pygame.Surface((radius * 2, radius * 2), pygame.SRCALPHA)
    for r in range(radius, 0, -1):
        alpha = int(255 * (r / radius) ** 2)
        pygame.draw.circle(surf, (*color, alpha), (radius, radius), r)
    return surf


class OrbCursor:
    """Small bokeh orb that splits into three on hover."""

    def __init__(self):
        self.base = _make_orb(12)
        self.micro = _make_orb(4)
        self.pos = (0, 0)
        self.target = None
        self.split_t = 0.0
        self.micro_pos = []

    def set_hover(self, pos):
        if APP_INSTANCE and isinstance(
            APP_INSTANCE.scene, (MainMenu, ScoresScene)
        ):
            self.target = pos
        else:
            self.target = None

    def update(self, dt):
        self.pos = pygame.mouse.get_pos()
        if self.target:
            self.split_t = min(1.0, self.split_t + dt * 8)
            dx = self.target[0] - self.pos[0]
            dy = self.target[1] - self.pos[1]
            dist = math.hypot(dx, dy) or 1.0
            dirx, diry = dx / dist, dy / dist
            offsets = (10, 20, 30)
            self.micro_pos = [
                (self.pos[0] + dirx * d, self.pos[1] + diry * d) for d in offsets
            ]
        else:
            self.split_t = max(0.0, self.split_t - dt * 8)
            self.micro_pos = []

    def draw(self, surf):
        if self.split_t < 1.0:
            base = self.base.copy()
            base.set_alpha(int(255 * (1 - self.split_t)))
            surf.blit(base, base.get_rect(center=self.pos))
        if self.split_t > 0.0:
            micro = self.micro.copy()
            micro.set_alpha(int(255 * self.split_t))
            for p in self.micro_pos:
                surf.blit(micro, micro.get_rect(center=p))


# --- instance globale pour accès aux options dans les helpers audio ---
APP_INSTANCE = None

# ---------- SFX (bruitages) ----------
SFX = {}
SFX_FILES = {
    "click": "sfx_click.wav",
    "back": "sfx_back.wav",
    "start": "sfx_start.wav",
    "end": "sfx_end.wav",
    "step": "sfx_step.wav",
    "anzan": "sfx_anzan.wav",
    "ding": "sfx_ding.wav",
    "correct": "sfx_correct.wav",
    "error": "sfx_error.wav",
    "save": "sfx_save.wav",
}

# ---------- Musiques d'ambiance ----------
MUSIC_FILES = {
    "menu": os.path.join(SAVE_DIR, "music_menu.ogg"),
    "game": os.path.join(SAVE_DIR, "music_game.ogg"),
}

SFX_VOL = {}

def init_sfx():
    """Charge les bruitages s'ils existent. Silencieux si absent."""
    try:
        if not pygame.mixer.get_init():
            pygame.mixer.init()
        try:
            cur = pygame.mixer.get_num_channels()
        except Exception:
            cur = 8
        pygame.mixer.set_num_channels(max(16, cur))
        try:
            # reserve deux canaux pour la musique afin d'y faire un crossfade
            pygame.mixer.set_reserved(2)
        except Exception:
            pass
    except Exception:
        return
    for key, fn in SFX_FILES.items():
        path = os.path.join(SAVE_DIR, fn)
        try:
            SFX[key] = pygame.mixer.Sound(path)
        except Exception:
            SFX[key] = None

def sfx_play(name: str):
    """Joue un bruitage si disponible et autorisé."""
    try:
        app = APP_INSTANCE
        if app and not app.options.get("sfx_enabled", True):
            return
        snd = SFX.get(name)
        if not snd:
            return
        vol = app.options.get("sfx_volume", 1.0) if app else 1.0
        ch = None
        try:
            ch = pygame.mixer.find_channel()
            if ch:
                ch.set_volume(vol)
            else:
                snd.set_volume(vol)
            # légère variation de pitch ±3 %
            pitch = 1.0 + random.uniform(-0.03, 0.03)
            if pitch != 1.0:
                try:
                    pygame.sndarray.use_arraytype("array")
                    arr = pygame.sndarray.array(snd)
                    import array as _array
                    if isinstance(arr, _array.array) and snd.get_num_channels() == 1:
                        orig = len(arr)
                        new_len = int(orig / pitch)
                        res = _array.array(arr.typecode)
                        for i in range(new_len):
                            src = i * pitch
                            i0 = int(src)
                            i1 = min(orig - 1, i0 + 1)
                            frac = src - i0
                            sample = int(arr[i0] * (1 - frac) + arr[i1] * frac)
                            res.append(sample)
                        snd = pygame.mixer.Sound(buffer=res.tobytes())
                except Exception:
                    pass
            if ch:
                ch.play(snd)
            else:
                snd.play()
        except Exception:
            snd.play()
    except Exception:
        pass
    
# ---------- Couleurs & polices ----------
THEME = {
    "background": (20, 20, 20),
    "surface": (40, 40, 40),
    "text": (255, 255, 255),
    "text_secondary": (200, 200, 200),
    "accent": (70, 130, 180),
    "success": (60, 170, 90),
    "error": (200, 60, 60),
    "warning": (230, 140, 60),
}

WHITE = THEME["text"]
BLACK = (0, 0, 0)
GRAY = THEME["text_secondary"]
LIGHT_GRAY = (210, 210, 210)
DARK_GRAY = THEME["surface"]
BLUE = THEME["accent"]
GREEN = THEME["success"]
RED = THEME["error"]
ORANGE = THEME["warning"]

# Taille de départ raisonnable (évite de forcer écran total)
UI_BASE_W, UI_BASE_H = 1280, 800
DEFAULT_W, DEFAULT_H = UI_BASE_W, UI_BASE_H
screen = pygame.display.set_mode((DEFAULT_W, DEFAULT_H), pygame.RESIZABLE)
pygame.display.set_caption(APP_NAME)

def compute_ui_scale():
    w, h = screen.get_size()
    return min(w / UI_BASE_W, h / UI_BASE_H)

ui_scale = compute_ui_scale()

FONT_SM = pygame.font.SysFont("arial", int(16 * ui_scale))
FONT_MD = pygame.font.SysFont("arial", int(22 * ui_scale))
FONT_LG = pygame.font.SysFont("arial", int(34 * ui_scale))
FONT_HUGE = pygame.font.SysFont("arial", int(44 * ui_scale))
FONT_TOAST = pygame.font.SysFont("arial", int(66 * ui_scale))

# Compat noms historiques
FONT_SMALL = FONT_SM
FONT_MED = FONT_MD
FONT_BIG = FONT_LG

# Paramètres génériques des spinners (flèches haut/bas)
SPINNER_BTN_W, SPINNER_BTN_H = 28, 18
SPINNER_MARGIN_X = 4
# Permet d'ajuster facilement la zone cliquable : (haut, droite, bas, gauche)
SPINNER_HITBOX = (-5, 2, 2, 2)


def handle_spinner_overlap(spinners, ev):
    """Gère les événements pour des spinners en évitant les clics doubles.

    Si le curseur est dans plusieurs hitbox simultanément, aucun spinner
    n'est survolé et seul celui le plus proche de la souris réagit au clic.
    """
    if (
        ev.type in (pygame.MOUSEMOTION, pygame.MOUSEBUTTONDOWN, pygame.MOUSEBUTTONUP)
        and hasattr(ev, "pos")
    ):
        mx, my = ev.pos
        hits = [b for b in spinners if b.rect.collidepoint((mx, my))]
        if len(hits) > 1:
            for b in spinners:
                if b in hits:
                    b._hover = False
                    if ev.type != pygame.MOUSEMOTION:
                        b._pressed = False
                else:
                    b.handle(ev)
            if ev.type != pygame.MOUSEMOTION:
                nearest = min(
                    hits, key=lambda b: (mx - b.rect.centerx) ** 2 + (my - b.rect.centery) ** 2
                )
                nearest.handle(ev)
            return
    for b in spinners:
        b.handle(ev)

# Si disponible (pygame._sdl2), on maximise la fenêtre (sans full screen)
try:
    from pygame._sdl2.video import Window
    Window.from_display_module().maximize()
except Exception:
    pass
pygame.display.set_caption(APP_NAME)

CLOCK = pygame.time.Clock()

# ---------- Utilitaires ----------
def clamp(v, a, b):
    return max(a, min(b, v))

def now_iso():
    return datetime.datetime.now().isoformat(timespec="seconds")

# petite sanitation pour les champs texte
_DEF_CTL_RE = re.compile(r"[\x00-\x08\x0B-\x0C\x0E-\x1F]")
def sanitize(s):
    if isinstance(s, list):
        s = " ".join(str(x) for x in s)
    elif not isinstance(s, str):
        s = str(s)
    s = s.replace("\r", " ").replace("\n", " ").replace("\t", " ")
    return _DEF_CTL_RE.sub("", s)

class AnimatedBackground:
    """
    Deux styles:
      - "fusion": chiffres flottants + grille + balayage
      - "bokeh" : orbes doux (halos) en parallax lent
    """
    def __init__(self, style="fusion"):
        self.style = style
        self._rng = random.Random(1337)
        # ressources "fusion"
        self._nums = []           # [{surf,x,y,vx,vy}]
        self._grid_static = None  # Surface grille
        self._scan_phase = 0.0
        # ressources "bokeh"
        self._bokeh = []          # [{surf,w,h,x,y,vx,vy,depth}]
        self._last_size = (-1, -1)

    # --- API publique ---
    def set_style(self, style):
        self.style = style
        # on ne jette pas tout : on garde ce qui est réutilisable par style
        if style == "fusion":
            if not self._nums: self._nums = []
            # _grid_static est régénérée à la taille courante au besoin
        elif style == "bokeh":
            if not self._bokeh: self._bokeh = []

    def toggle_style(self):
        self.set_style("bokeh" if self.style == "fusion" else "fusion")
        return self.style

    def update(self, dt, size):
        w, h = size
        if (w, h) != self._last_size:
            # on invalide la grille si la taille change
            self._grid_static = None
            self._last_size = (w, h)
        if self.style == "fusion":
            self._ensure_numbers(w, h)
            self._ensure_grid(w, h)
            for it in self._nums:
                it["x"] = (it["x"] + it["vx"] * dt) % max(1, w)
                it["y"] = (it["y"] + it["vy"] * dt) % max(1, h)
            # balayage très lent
            self._scan_phase = (self._scan_phase + 20 * dt) % (h + 140)
        else:
            self._ensure_bokeh(w, h)
            for it in self._bokeh:
                it["x"] = (it["x"] + it["vx"] * dt) % max(1, w + 200)
                it["y"] = (it["y"] + it["vy"] * dt) % max(1, h + 200)

    def draw(self, surf):
        if self.style == "fusion":
            self._draw_numbers(surf)
            self._draw_grid_and_scan(surf)
        else:
            self._draw_bokeh(surf)

    # --- Impl. "fusion": chiffres + grille + scan ---
    def _ensure_numbers(self, w, h):
        target = max(40, (w * h) // 40000)  # densité douce
        if len(self._nums) >= target:
            return
        glyphs = list("0123456789+−×÷")
        fonts = [FONT_SMALL, FONT_MED, FONT_BIG, FONT_HUGE]
        for _ in range(target - len(self._nums)):
            ch = self._rng.choice(glyphs)
            font = self._rng.choice(fonts)
            col = BLUE if self._rng.random() < 0.85 else ORANGE
            s = font.render(ch, True, col).convert_alpha()
            s.set_alpha(self._rng.randint(24, 64))
            k = 0.7 + self._rng.random() * 0.9
            if k != 1.0:
                s = pygame.transform.rotozoom(s, 0, k)
            vx = (self._rng.random() * 20 + 10) * (1 if self._rng.random() < 0.5 else -1)
            vy = (self._rng.random() * 12 + 6) * (1 if self._rng.random() < 0.5 else -1)
            self._nums.append({
                "surf": s,
                "x": self._rng.randint(0, max(1, w)),
                "y": self._rng.randint(0, max(1, h)),
                "vx": vx, "vy": vy
            })

    def _ensure_grid(self, w, h):
        if self._grid_static and self._grid_static.get_size() == (w, h):
            return
        self._grid_static = pygame.Surface((w, h), pygame.SRCALPHA)
        spacing = 80
        base_alpha = 28
        for x in range(0, w, spacing):
            pygame.draw.line(self._grid_static, (*LIGHT_GRAY, base_alpha), (x, 0), (x, h), 1)
        for y in range(0, h, spacing):
            pygame.draw.line(self._grid_static, (*LIGHT_GRAY, base_alpha), (0, y), (w, y), 1)

    def _draw_numbers(self, surf):
        # dessine sous l’UI (on suppose le fond anthracite déjà rempli)
        for it in self._nums:
            surf.blit(it["surf"], (int(it["x"]), int(it["y"])))

    def _draw_grid_and_scan(self, surf):
        w, h = surf.get_size()
        if not self._grid_static or self._grid_static.get_size() != (w, h):
            self._ensure_grid(w, h)
        surf.blit(self._grid_static, (0, 0))
        scan_y = int(self._scan_phase % (h + 140)) - 70
        if -70 <= scan_y <= h:
            band = pygame.Surface((w, 70), pygame.SRCALPHA)
            # bande principale bleue + léger reflet orange
            pygame.draw.rect(band, (*BLUE, 40), (0, 28, w, 8), border_radius=4)
            pygame.draw.rect(band, (*ORANGE, 12), (0, 24, w, 16), border_radius=6)
            surf.blit(band, (0, scan_y))

    # --- Impl. "bokeh": halos doux ---
    def _ensure_bokeh(self, w, h):
        target = 18  # nombre d’orbes
        if len(self._bokeh) >= target and self._last_size == (w, h):
            return
        if (w, h) != self._last_size:
            self._bokeh.clear()
        while len(self._bokeh) < target:
            r = self._rng.randint(40, 140)
            col = BLUE if self._rng.random() < 0.75 else ORANGE
            surf = pygame.Surface((r*2, r*2), pygame.SRCALPHA)
            # halo radial simple (cercles concentriques)
            steps = 16
            for i in range(steps, 0, -1):
                alpha = int(6 + 180 * (i/steps)**2)
                pygame.draw.circle(surf, (*col, alpha), (r, r), int(r * i/steps))
            # profondeur → parallax (vitesses plus lentes pour les gros)
            depth = 0.4 + 0.6 * (1 - (r - 40) / 100.0)  # [0.4..1.0]
            vx = (self._rng.random()*14 + 6) * depth * (1 if self._rng.random()<0.5 else -1)
            vy = (self._rng.random()*10 + 4) * depth * (1 if self._rng.random()<0.5 else -1)
            self._bokeh.append({
                "surf": surf,
                "w": surf.get_width(), "h": surf.get_height(),
                "x": self._rng.randint(-100, w+100),
                "y": self._rng.randint(-100, h+100),
                "vx": vx, "vy": vy,
                "depth": depth,
            })

    def _draw_bokeh(self, surf):
        # ordre de dessin du plus "loin" au plus "près" ≈ par rayon inverse
        for it in sorted(self._bokeh, key=lambda p: p["w"], reverse=False):
            surf.blit(it["surf"], (int(it["x"] - it["w"]//2), int(it["y"] - it["h"]//2)))


# ---------- TTS & STT ----------
def list_tts_voices():
    out = []
    if pyttsx3 is None:
        return out
    try:
        engine = pyttsx3.init()
        voices = engine.getProperty("voices") or []
    except Exception:
        return out
    def _langs(v):
        res = []
        for lt in getattr(v, "languages", []) or []:
            try:
                res.append(lt.decode() if isinstance(lt, (bytes, bytearray)) else str(lt))
            except Exception:
                pass
        return " ".join(res).lower()
    for v in voices:
        vid = getattr(v, "id", "")
        name = getattr(v, "name", vid)
        blob = f"{vid} {name} {_langs(v)}".lower()
        lang = "FR" if "fr" in blob else ("EN" if "en" in blob else "??")
        out.append({"id": vid, "label": f"{name} ({lang})", "lang": lang})
    out.sort(key=lambda d: d["label"].lower())
    return out

def tts_say(text, voice_id=None):
    if pyttsx3 is None:
        return
    def _worker():
        try:
            engine = pyttsx3.init()
            if voice_id:
                try:
                    engine.setProperty("voice", voice_id)
                except Exception:
                    pass
            cleaned = text.replace("−", " moins ")
            cleaned = cleaned.replace("-", " moins ")
            cleaned = re.sub(r"\s+", " ", cleaned).strip()
            engine.say(cleaned)
            engine.runAndWait()
        except Exception:
            pass
    threading.Thread(target=_worker, daemon=True).start()
class STT:
    def __init__(self, model_dir="vosk-model-small-fr", samplerate=16000):
        self.available = (vosk is not None)
        self.samplerate = samplerate
        self.q = queue.Queue()
        self.stream = None
        self.rec = None
        self.active = False
        self.model = None
        if self.available:
            if not os.path.isabs(model_dir):
                model_dir = os.path.join(SAVE_DIR, model_dir)
            try:
                self.model = vosk.Model(model_dir)
            except Exception:
                self.model = None

    def _audio_cb(self, indata, frames, t, status):
        if status:
            pass
        self.q.put(bytes(indata))

    def start(self):
        if not self.model or self.active:
            return False
        try:
            self.rec = vosk.KaldiRecognizer(self.model, self.samplerate)
            self.stream = sd.InputStream(samplerate=self.samplerate, channels=1, dtype='int16', callback=self._audio_cb)
            self.stream.start()
            self.active = True
            return True
        except Exception:
            return False

    def feed(self):
        if not self.active:
            return
        try:
            while True:
                data = self.q.get_nowait()
                self.rec.AcceptWaveform(data)
        except queue.Empty:
            pass

    def stop_and_get_text(self):
        if not self.active:
            return ""
        try:
            self.stream.stop(); self.stream.close()
        except Exception:
            pass
        self.stream = None
        self.active = False
        self.feed()
        try:
            res = _json.loads(self.rec.FinalResult()) if _json else {}
            return (res.get("text") or "").strip()
        except Exception:
            return ""

def stt_extract_number(text: str, lang: str = "FR") -> str:
    """Essaye d'extraire un nombre (jusqu'à 999 999) depuis un texte STT."""
    if not text:
        return ""
    nums = re.findall(r"\d+", text)
    if nums:
        return "".join(nums)
    lang = (lang or "FR").upper()
    t = re.sub(r"[^a-zA-Z\séèêëàâäîïôöùûüç-]", " ", text).lower()
    t = t.replace("-", " ").replace("milles", "mille").replace("cents", "cent").replace("vingts", "vingt")
    tokens = [tok for tok in t.split() if tok and tok not in ("et", "and")]
    if not tokens:
        return ""
    if lang == "FR":
        units = {
            "zero":0, "zéro":0, "un":1, "une":1, "deux":2, "trois":3,
            "quatre":4, "cinq":5, "six":6, "sept":7, "huit":8, "neuf":9,
        }
        teens = {
            "dix":10, "onze":11, "douze":12, "treize":13, "quatorze":14,
            "quinze":15, "seize":16, "dix sept":17, "dix huit":18,
            "dix neuf":19,
        }
        tens = {
            "vingt":20, "trente":30, "quarante":40, "cinquante":50,
            "soixante":60,
        }
        def parse_0_99(ts):
            if not ts:
                return 0
            joined = " ".join(ts)
            if joined in teens:
                return teens[joined]
            if ts[0] == "soixante" and len(ts) > 1:
                rest = " ".join(ts[1:])
                if rest in teens:
                    return 60 + teens[rest]
                if ts[1] in units:
                    return 60 + units[ts[1]]
                return None
            if len(ts) >= 2 and ts[0] == "quatre" and ts[1] == "vingt":
                base = 80
                if len(ts) > 2:
                    rest = " ".join(ts[2:])
                    if rest in teens:
                        base += teens[rest]
                    elif ts[2] in units:
                        base += units[ts[2]]
                    else:
                        return None
                return base
            if ts[0] in tens:
                base = tens[ts[0]]
                if len(ts) > 1:
                    rest = " ".join(ts[1:])
                    if rest in teens:
                        base += teens[rest]
                    elif ts[1] in units:
                        base += units[ts[1]]
                    else:
                        return None
                return base
            if ts[0] in units and len(ts) == 1:
                return units[ts[0]]
            return None
        def parse_0_999(ts):
            if not ts:
                return 0
            if "cent" in ts:
                idx = ts.index("cent")
            elif "cents" in ts:
                idx = ts.index("cents")
            else:
                return parse_0_99(ts)
            hundreds = parse_0_99(ts[:idx]) if idx > 0 else 1
            if hundreds is None:
                return None
            rest = parse_0_99(ts[idx+1:])
            if rest is None:
                rest = 0
            return hundreds * 100 + rest
        def parse_fr(ts):
            if "mille" in ts:
                idx = ts.index("mille")
            else:
                return parse_0_999(ts)
            thousands = parse_0_999(ts[:idx]) if idx > 0 else 1
            if thousands is None:
                return None
            rest = parse_0_999(ts[idx+1:])
            if rest is None:
                rest = 0
            return thousands * 1000 + rest
        num = parse_fr(tokens)
        return str(num) if num is not None else ""
    else:
        units = {
            "zero":0, "one":1, "two":2, "three":3, "four":4, "five":5,
            "six":6, "seven":7, "eight":8, "nine":9,
        }
        teens = {
            "ten":10, "eleven":11, "twelve":12, "thirteen":13,
            "fourteen":14, "fifteen":15, "sixteen":16, "seventeen":17,
            "eighteen":18, "nineteen":19,
        }
        tens = {
            "twenty":20, "thirty":30, "forty":40, "fifty":50,
            "sixty":60, "seventy":70, "eighty":80, "ninety":90,
        }
        def parse_0_99(ts):
            if not ts:
                return 0
            joined = " ".join(ts)
            if joined in teens:
                return teens[joined]
            if ts[0] in tens:
                base = tens[ts[0]]
                if len(ts) > 1:
                    if ts[1] in units:
                        base += units[ts[1]]
                    else:
                        return None
                return base
            if ts[0] in units and len(ts) == 1:
                return units[ts[0]]
            return None
        def parse_0_999(ts):
            if not ts:
                return 0
            if "hundred" in ts:
                idx = ts.index("hundred")
                hundreds = parse_0_99(ts[:idx]) if idx > 0 else 1
                if hundreds is None:
                    return None
                rest = parse_0_99(ts[idx+1:])
                if rest is None:
                    rest = 0
                return hundreds * 100 + rest
            return parse_0_99(ts)
        def parse_en(ts):
            if "thousand" in ts:
                idx = ts.index("thousand")
                thousands = parse_0_999(ts[:idx]) if idx > 0 else 1
                if thousands is None:
                    return None
                rest = parse_0_999(ts[idx+1:])
                if rest is None:
                    rest = 0
                return thousands * 1000 + rest
            return parse_0_999(ts)
        num = parse_en(tokens)
        return str(num) if num is not None else ""
# ---------- Widgets ----------
class Button:
    def __init__(self, rect, text, on_click=None, font=FONT_MD, sfx="click",
                 variant="default", style="solid"):
        self.rect = pygame.Rect(rect)
        self.text = text
        self.on_click = on_click
        self.font = font
        self.enabled = True
        self.sfx = sfx
        self._hover = False
        self._pressed = False
        self.variant = variant  # "default" ou "toggle"
        self.selected = False
        self.style = style      # "solid" (fond) ou "ghost" (texte seul)
        self.focused = False
        self.hover_t = 0.0
        self.press_t = 0.0
        self._ripples = []  # animations de clic

    def draw(self, surf):
        min_size = int(40 * ui_scale)
        if self.rect.w < min_size:
            self.rect.w = min_size
        if self.rect.h < min_size:
            self.rect.h = min_size
        if self.style == "ghost":
            col = THEME["text_secondary"] if self.enabled else GRAY
            if self._hover and self.enabled:
                col = THEME["accent"]
            if self._pressed and self.enabled:
                col = WHITE
            _draw_text(surf, self.text, self.font, col, rect=self.rect)
            if self.focused:
                pygame.draw.rect(surf, THEME["accent"], self.rect.inflate(4,4), width=2, border_radius=int(12*ui_scale))
            now = pygame.time.get_ticks()
            for r in self._ripples[:]:
                prog = (now - r[2]) / 180.0
                if prog >= 1.0:
                    self._ripples.remove(r)
                    continue
                radius = int(max(self.rect.w, self.rect.h) * prog)
                alpha = int(120 * (1 - prog))
                circ = pygame.Surface(self.rect.size, pygame.SRCALPHA)
                pygame.draw.circle(circ, (255, 255, 255, alpha), (r[0], r[1]), radius)
                surf.blit(circ, self.rect.topleft)
            return

        target_hover = 1.0 if (self._hover and self.enabled) else 0.0
        target_press = 1.0 if (self._pressed and self.enabled) else 0.0
        self.hover_t = lerp(self.hover_t, target_hover, 0.18)
        self.press_t = lerp(self.press_t, target_press, 0.25)

        elev = int(lerp(6 * ui_scale, 10 * ui_scale, ease_out_cubic(self.hover_t)) - 3 * self.press_t * ui_scale)
        shadow = pygame.Rect(self.rect.x, self.rect.y + elev, self.rect.w, self.rect.h)
        s = pygame.Surface(shadow.size, pygame.SRCALPHA)
        s.fill((0, 0, 0, 60))
        surf.blit(s, shadow.topleft)

        accent = THEME["accent"]
        if self.variant == "toggle" and self.selected:
            accent = THEME["warning"]
        accent_hover = tuple(min(255, int(c * 1.2)) for c in accent)
        col_top = tuple(int(lerp(accent[i], accent_hover[i], ease_out_cubic(self.hover_t))) for i in range(3))
        col_bot = tuple(int(c * 0.92) for c in col_top)

        btn_surf = pygame.Surface(self.rect.size, pygame.SRCALPHA)
        for y in range(self.rect.h):
            t = y / (self.rect.h - 1)
            r = int(col_top[0] * (1 - t) + col_bot[0] * t)
            g = int(col_top[1] * (1 - t) + col_bot[1] * t)
            b = int(col_top[2] * (1 - t) + col_bot[2] * t)
            pygame.draw.line(btn_surf, (r, g, b), (0, y), (self.rect.w, y))

        border_radius = int(12 * ui_scale)
        pygame.draw.rect(btn_surf, (255, 255, 255, 25), btn_surf.get_rect(), border_radius=border_radius)

        text_col = WHITE if self.enabled else GRAY
        _draw_text(btn_surf, self.text, self.font, text_col, rect=btn_surf.get_rect())

        if self.hover_t > 0:
            scale = 1 + 0.02 * self.hover_t
            scaled = pygame.transform.smoothscale(
                btn_surf, (int(self.rect.w * scale), int(self.rect.h * scale))
            )
            surf.blit(scaled, scaled.get_rect(center=self.rect.center))
        else:
            surf.blit(btn_surf, self.rect.topleft)

        if self.focused:
            pygame.draw.rect(surf, THEME["accent"], self.rect.inflate(4, 4), width=2, border_radius=border_radius)

        now = pygame.time.get_ticks()
        for r in self._ripples[:]:
            prog = (now - r[2]) / 180.0
            if prog >= 1.0:
                self._ripples.remove(r)
                continue
            radius = int(max(self.rect.w, self.rect.h) * prog)
            alpha = int(120 * (1 - prog))
            circ = pygame.Surface(self.rect.size, pygame.SRCALPHA)
            pygame.draw.circle(circ, (255, 255, 255, alpha), (r[0], r[1]), radius)
            surf.blit(circ, self.rect.topleft)
    def handle(self, ev):
        if not self.enabled: return
        if ev.type == pygame.MOUSEMOTION:
            self._hover = self.rect.collidepoint(ev.pos)
            if APP_INSTANCE and hasattr(APP_INSTANCE, "cursor"):
                if self._hover:
                    APP_INSTANCE.cursor.set_hover(self.rect.center)
                # no else: cursor reset each frame by app
            if self._hover:
                try:
                    pygame.mouse.set_cursor(pygame.SYSTEM_CURSOR_HAND)
                except Exception:
                    pass
        elif ev.type == pygame.MOUSEBUTTONDOWN and ev.button == 1:
            if self.rect.collidepoint(ev.pos):
                self._pressed = True
                rx = ev.pos[0] - self.rect.x
                ry = ev.pos[1] - self.rect.y
                self._ripples.append((rx, ry, pygame.time.get_ticks()))
        elif ev.type == pygame.MOUSEBUTTONUP and ev.button == 1:
            if self._pressed and self.rect.collidepoint(ev.pos):
                if self.sfx:
                    sfx_play(self.sfx)
                if self.on_click:
                    self.on_click()
                if self.variant == "toggle":
                    self.selected = True
            self._pressed = False

class Checkbox:
    def __init__(self, rect, label, checked=False):
        self.rect = pygame.Rect(rect)
        self.label = label
        self.checked = checked
        self.enabled = True
    def draw(self, surf):
        box = pygame.Rect(self.rect.topleft, (24, 24))
        col = WHITE if self.enabled else GRAY
        pygame.draw.rect(surf, col, box, width=2, border_radius=5)
        if self.checked:
            draw_col = GREEN if self.enabled else GRAY
            pygame.draw.line(surf, draw_col, (box.x+5, box.y+12), (box.x+10, box.y+18), 3)
            pygame.draw.line(surf, draw_col, (box.x+10, box.y+18), (box.x+19, box.y+6), 3)
        _draw_text(surf, self.label, FONT_MED, col, topleft=(self.rect.x+32, self.rect.y))
    def handle(self, ev):
        if not self.enabled:
            return
        if ev.type == pygame.MOUSEBUTTONDOWN and ev.button == 1:
            if pygame.Rect(self.rect.topleft, (24, 24)).collidepoint(ev.pos):
                self.checked = not self.checked

class TextInput:
    def __init__(self, rect, text="", placeholder="", numeric_only=False, maxlen=None,
                 font=FONT_MED, centered=False, min_val=None, max_val=None):
        self.rect = pygame.Rect(rect)
        self.text = text
        self.placeholder = placeholder
        self.numeric_only = numeric_only
        self.maxlen = maxlen
        self.font = font
        self.centered = centered
        self.min_val = min_val
        self.max_val = max_val
        self.line_h = self.font.get_linesize()
        self.active = False
        self._hover = False
        self.caret = len(text)
        self.scroll_x = 0
        self.last_blink = time.time(); self.show_caret = True
        self.sel_start = None; self.sel_end = None; self._dragging = False
        self.error_text = ""
    def _has_sel(self):
        return (self.sel_start is not None and self.sel_end is not None and self.sel_start != self.sel_end)
    def _sel_range(self):
        if not self._has_sel(): return (0,0)
        a,b = self.sel_start, self.sel_end
        return (a,b) if a<=b else (b,a)
    def _clear_sel(self):
        self.sel_start = None; self.sel_end = None
    def _delete_sel(self):
        if not self._has_sel(): return False
        a,b = self._sel_range()
        self.text = self.text[:a] + self.text[b:]
        self.caret = a
        self._clear_sel(); return True
    def insert_text(self, s):
        s = sanitize(s)
        if self.numeric_only:
            s = "".join(ch for ch in s if (ch.isdigit() or ch in "+-"))
        if not s: return
        if self.maxlen is not None and len(self.text)+len(s) > self.maxlen:
            s = s[:max(0, self.maxlen-len(self.text))]
        self._delete_sel()
        self.text = self.text[:self.caret] + s + self.text[self.caret:]
        self.caret += len(s)
        self.last_blink = time.time(); self.show_caret = True
    def draw(self, surf):
        min_h = int(40 * ui_scale)
        if self.rect.h < min_h:
            self.rect.h = min_h
        bg = DARK_GRAY if self.active else ((60,60,60) if self._hover else (50,50,50))
        pygame.draw.rect(surf, bg, self.rect, border_radius=8)
        if self.active:
            pygame.draw.rect(surf, THEME["accent"], self.rect, width=2, border_radius=8)
        pad = 6
        if not self.text and self.placeholder and not self.active:
            _draw_text(surf, self.placeholder, self.font, LIGHT_GRAY, topleft=(self.rect.x+pad, self.rect.y+pad))
            if self.error_text:
                _draw_text(surf, self.error_text, FONT_SMALL, RED, topleft=(self.rect.x, self.rect.bottom+2))
            return
        display_text = self.text
        visible_w = self.rect.w - 2*pad
        caret_px = self.font.size(display_text[:self.caret])[0]
        total_w = self.font.size(display_text)[0]
        if self.centered and total_w < visible_w:
            draw_x = self.rect.x + pad + (visible_w - total_w) / 2
        else:
            if self.centered:
                half = visible_w / 2
                self.scroll_x = clamp(caret_px - half, 0, max(0, total_w - visible_w))
            else:
                if caret_px - self.scroll_x > visible_w - 10:
                    self.scroll_x = caret_px - (visible_w - 10)
                if caret_px - self.scroll_x < 10:
                    self.scroll_x = max(0, caret_px - 10)
            draw_x = self.rect.x + pad - self.scroll_x
        clip = pygame.Rect(self.rect.x+pad, self.rect.y+pad, visible_w, self.rect.h-2*pad)
        prev = surf.get_clip(); surf.set_clip(clip)
        if self._has_sel():
            a,b = self._sel_range()
            x_a = draw_x + self.font.size(display_text[:a])[0]
            x_b = draw_x + self.font.size(display_text[:b])[0]
            pygame.draw.rect(surf, BLUE, pygame.Rect(x_a, self.rect.y+pad, max(1, x_b-x_a), self.font.get_height()))
        _draw_text(surf, display_text, self.font, WHITE, topleft=(draw_x, self.rect.y+pad))
        if self.active:
            if time.time() - self.last_blink > 0.5:
                self.show_caret = not self.show_caret; self.last_blink = time.time()
            if self.show_caret:
                cx = draw_x + caret_px
                pygame.draw.line(surf, ORANGE, (cx, self.rect.y+pad), (cx, self.rect.y+pad+self.font.get_height()))
        surf.set_clip(prev)
        if total_w > visible_w:
            bar = pygame.Rect(self.rect.x+pad, self.rect.bottom-6, visible_w, 3)
            pygame.draw.rect(surf, (70,70,75), bar)
            ratio = visible_w / total_w
            handle_w = max(20, int(bar.w * ratio))
            max_scroll = total_w - visible_w
            pos_ratio = (self.scroll_x / max_scroll) if max_scroll>0 else 0
            handle_x = int(bar.x + pos_ratio * (bar.w - handle_w))
            pygame.draw.rect(surf, ORANGE, (handle_x, bar.y, handle_w, bar.h))
        if self.error_text:
            _draw_text(surf, self.error_text, FONT_SMALL, RED, topleft=(self.rect.x, self.rect.bottom+2))
    def _caret_from_mouse(self, mx):
        pad = 6
        visible_w = self.rect.w - 2*pad
        total_w = self.font.size(self.text)[0]
        if self.centered and total_w < visible_w:
            draw_x = self.rect.x + pad + (visible_w - total_w) / 2
            relx = mx - draw_x
        else:
            relx = mx - self.rect.x - pad + self.scroll_x
        lo,hi = 0, len(self.text)
        while lo<hi:
            mid=(lo+hi)//2
            if self.font.size(self.text[:mid])[0] < relx:
                lo=mid+1
            else:
                hi=mid
        return lo
    def handle(self, ev):
        if ev.type == pygame.MOUSEMOTION:
            self._hover = self.rect.collidepoint(ev.pos)
        if ev.type == pygame.MOUSEWHEEL:
            mx,my = pygame.mouse.get_pos()
            if self.active or self.rect.collidepoint((mx,my)):
                self.scroll_x -= ev.y * 24
                self.scroll_x = max(0, self.scroll_x)
        if ev.type == pygame.MOUSEBUTTONDOWN and ev.button==1:
            self.active = self.rect.collidepoint(ev.pos)
            if self.active:
                self.caret = self._caret_from_mouse(ev.pos[0])
                self.sel_start = self.caret
                self.sel_end = self.caret
                self._dragging = True
                self.last_blink = time.time(); self.show_caret = True
        elif ev.type == pygame.MOUSEBUTTONUP and ev.button==1:
            self._dragging = False
        elif ev.type == pygame.MOUSEMOTION and self._dragging and self.active:
            self.caret = self._caret_from_mouse(ev.pos[0])
            self.sel_end = self.caret
            self.last_blink = time.time(); self.show_caret = True
        if not self.active: return
        if ev.type == pygame.KEYDOWN:
            mod = pygame.key.get_mods(); ctrl = mod & (pygame.KMOD_CTRL|pygame.KMOD_META); shift = bool(mod & pygame.KMOD_SHIFT)
            if ctrl and ev.key == pygame.K_a:
                self.sel_start, self.sel_end = 0, len(self.text); self.caret = len(self.text); return
            if ev.key == pygame.K_BACKSPACE:
                if self._delete_sel(): return
                if self.caret>0:
                    self.text = self.text[:self.caret-1] + self.text[self.caret:]
                    self.caret -= 1
                self.last_blink = time.time(); self.show_caret = True; return
            if ev.key == pygame.K_DELETE:
                if self._delete_sel(): return
                if self.caret < len(self.text):
                    self.text = self.text[:self.caret] + self.text[self.caret+1:]
                self.last_blink = time.time(); self.show_caret = True; return
            if ev.key in (pygame.K_LEFT, pygame.K_RIGHT, pygame.K_HOME, pygame.K_END):
                old = self.caret
                if ev.key == pygame.K_LEFT: self.caret = max(0, self.caret-1)
                elif ev.key == pygame.K_RIGHT: self.caret = min(len(self.text), self.caret+1)
                elif ev.key == pygame.K_HOME: self.caret = 0
                elif ev.key == pygame.K_END: self.caret = len(self.text)
                if shift:
                    if not self._has_sel(): self.sel_start = old
                    self.sel_end = self.caret
                else:
                    self._clear_sel()
                self.last_blink = time.time(); self.show_caret = True; return
            ch = ev.unicode
            if not ch: return
            if self.numeric_only:
                if ch.isdigit() or ch in "+-": self.insert_text(ch)
            else:
                self.insert_text(ch)
            self._validate()
        if ev.type == pygame.MOUSEBUTTONUP and ev.button==1 and not self.rect.collidepoint(ev.pos):
            self._hover = False

    def _validate(self):
        if not self.numeric_only:
            self.error_text = ""
            return
        try:
            val = int(self.text or "0")
        except Exception:
            self.error_text = "Valeur invalide"
            return
        if self.min_val is not None and val < self.min_val:
            self.error_text = f"< {self.min_val}"
        elif self.max_val is not None and val > self.max_val:
            self.error_text = f"> {self.max_val}"
        else:
            self.error_text = ""

# helpers dessin
def _draw_text(surf, text, font, color, topleft=None, center=None, rect=None, align="left", midleft=None):
    if rect is not None:
        x,y,w,h = rect
        line_h = font.get_linesize()
        words = text.split(" ")
        cur_line = ""; yy = y
        for tok in words:
            test = (cur_line + " " + tok).strip()
            tw = font.size(test)[0]
            if tw > w - 8 and cur_line:
                if align == "center": tx = x + (w - font.size(cur_line)[0])//2
                elif align == "right": tx = x + w - font.size(cur_line)[0] - 4
                else: tx = x + 4
                surf.blit(font.render(cur_line, True, color), (tx, yy))
                yy += line_h
                cur_line = tok
            else:
                cur_line = test
        if cur_line:
            if align == "center": tx = x + (w - font.size(cur_line)[0])//2
            elif align == "right": tx = x + w - font.size(cur_line)[0] - 4
            else: tx = x + 4
            surf.blit(font.render(cur_line, True, color), (tx, yy))
        return
    img = font.render(text, True, color)
    if topleft:
        surf.blit(img, topleft)
    elif center:
        surf.blit(img, img.get_rect(center=center).topleft)
    elif midleft:
        surf.blit(img, img.get_rect(midleft=midleft).topleft)

def draw_panel(surf, rect, color=DARK_GRAY, border_radius=8):
    pygame.draw.rect(surf, color, rect, border_radius=border_radius)
    pygame.draw.rect(surf, (255, 255, 255, 25), rect, width=1, border_radius=border_radius)

def draw_audio_icon(surf, topleft, color=WHITE):
    x, y = topleft
    pygame.draw.polygon(surf, color, [(x, y+6), (x, y+18), (x+8, y+22), (x+8, y+2)])
    pygame.draw.rect(surf, color, (x-6, y+6, 6, 12))
    pygame.draw.arc(surf, color, (x+8, y+2, 12, 20), -0.5, 0.5, 2)
    pygame.draw.arc(surf, color, (x+8, y-4, 20, 32), -0.5, 0.5, 2)

def draw_play_icon(surf, center, color=WHITE, size=24):
    x, y = center
    half = size // 2
    pts = [(x - half, y - half), (x - half, y + half), (x + half, y)]
    pygame.draw.polygon(surf, color, pts)

def draw_settings_icon(surf, center, color=WHITE, size=24):
    x, y = center
    r = size // 2
    for i in range(8):
        ang = i * math.pi / 4
        x1 = x + math.cos(ang) * r
        y1 = y + math.sin(ang) * r
        x2 = x + math.cos(ang) * (r - 4)
        y2 = y + math.sin(ang) * (r - 4)
        pygame.draw.line(surf, color, (x1, y1), (x2, y2), 2)
    pygame.draw.circle(surf, color, (x, y), r - 6, 2)
    pygame.draw.circle(surf, color, (x, y), 2)

def draw_scores_icon(surf, center, color=WHITE, size=24):
    x, y = center
    w = size
    h = size
    bar_w = w // 5
    heights = [0.4, 0.7, 1.0]
    for i, frac in enumerate(heights):
        bx = x - w // 2 + i * (bar_w + 4)
        bh = int(h * frac)
        by = y + h // 2 - bh
        pygame.draw.rect(surf, color, (bx, by, bar_w, bh))

# ---------- Scores ----------
class ScoreManager:
    def __init__(self, path=SCORES_PATH):
        self.path = path
        self.data = {"sessions": [], "daily_bests": []}
        self.load()

    @staticmethod
    def _date_only(s):
        try:
            return datetime.datetime.fromisoformat(str(s)).date().isoformat()
        except Exception:
            return str(s).split("T")[0][:10]

    def load(self):
        self.data = {"sessions": [], "daily_bests": []}
        if os.path.exists(self.path):
            try:
                with open(self.path, "r", encoding="utf-8") as f:
                    loaded = json.load(f)
                if isinstance(loaded, dict):
                    self.data["sessions"] = loaded.get("sessions", [])
                    self.data["daily_bests"] = loaded.get("daily_bests", [])
                elif isinstance(loaded, list):
                    self.data = {"sessions": loaded, "daily_bests": []}
            except Exception:
                self.data = {"sessions": [], "daily_bests": []}

    def save(self):
        try:
            with open(self.path, "w", encoding="utf-8") as f:
                json.dump(self.data, f, ensure_ascii=False, indent=2)
        except Exception as e:
            print("Erreur sauvegarde scores:", e)

    def add_session(self, entry):
        if not isinstance(self.data, dict) or not isinstance(self.data.get("sessions"), list):
            self.data = {"sessions": [], "daily_bests": []}
        self.data["sessions"].append(entry)
        self.save()

    def history(self, mode=None):
        sessions = []
        if isinstance(self.data, dict) and isinstance(self.data.get("sessions"), list):
            sessions = self.data["sessions"]
        elif isinstance(self.data, list):
            sessions = self.data
        if mode is not None:
            sessions = [e for e in sessions if int(e.get("mode", 0)) == int(mode)]
        return sessions[-200:]

    def sessions_on_date(self, day, mode=None):
        day = self._date_only(day)
        return [e for e in self.history(mode) if self._date_only(e.get("date", "")) == day]

    def best_session_on_date(self, day, mode=None):
        sess = self.sessions_on_date(day, mode)
        return max(sess, key=lambda e: int(e.get("score", 0))) if sess else None

    def get_daily_bests(self, mode=None):
        rows = self.data.get("daily_bests", [])
        if mode is not None:
            rows = [r for r in rows if int(r.get("mode", 0)) == int(mode)]
        try:
            return sorted(rows, key=lambda e: e.get("day", ""))
        except Exception:
            return rows

    def upsert_daily_best(self, entry):
        if not isinstance(self.data, dict):
            self.data = {"sessions": [], "daily_bests": []}
        if "daily_bests" not in self.data or not isinstance(self.data["daily_bests"], list):
            self.data["daily_bests"] = []
        day = entry.get("day")
        mode = entry.get("mode")
        if not day:
            return
        rows = self.data["daily_bests"]
        idx = next((i for i, r in enumerate(rows) if r.get("day") == day and int(r.get("mode", 0)) == int(mode)), None)
        if idx is None:
            rows.append(entry)
        else:
            if int(entry.get("score", 0)) > int(rows[idx].get("score", 0)):
                rows[idx] = entry
        self.save()

    def clear(self):
        self.data = {"sessions": [], "daily_bests": []}
        self.save()

    def clear_mode(self, mode):
        """Remove scores for a specific game mode only."""
        if isinstance(self.data, dict):
            if isinstance(self.data.get("sessions"), list):
                self.data["sessions"] = [
                    e for e in self.data["sessions"]
                    if int(e.get("mode", 0)) != int(mode)
                ]
            if isinstance(self.data.get("daily_bests"), list):
                self.data["daily_bests"] = [
                    e for e in self.data["daily_bests"]
                    if int(e.get("mode", 0)) != int(mode)
                ]
        self.save()

# ---------- Options ----------
DEFAULT_OPTIONS = {
    "mode": 1,                 # 1: contre-la-montre, 2: série chrono, 3: Flash Anzan
                               # 4: mode audio, 5: Calcul Infernal
    "level": 3,                # indicatif (influence score)
    "duration_sec": 60,        # mode 1
    "num_problems": 20,        # mode 2
    "flash_series": 10,       # mode 3: nombre de séries
    "flash_numbers": 5,       # mode 3: nombres par série
    "infernal_n": 3,         # mode 5: décalage n-back
    "infernal_speed": 1,     # mode 5: 0 lent,1 moyen,2 rapide

    # opérations
    "op_add": True,
    "op_sub": True,
    "op_mul": False,
    "op_div": False,
    "mix_ops_in_expr": True,

    # opérandes
    "min_operands": 2,
    "max_operands": 3,

    # taille des nombres
    "digits_units": True,
    "digits_tens": True,
    "digits_hundreds": False,
    "digits_thousands": False,
    "digits_ten_thousands": False,
    "digits_hundred_thousands": False,
    "mix_digit_sizes": True,

    # contraintes
    "allow_negatives": False,
    "only_negatives": False,
    "positive_result": True,
    "div_integer_only": True,
    "add_no_carry": False,
    "sub_no_borrow": False,    # si vrai, on force 2 opérandes pour rester simple
    "limit_tables": True,
    "tables_max": 12,          # tables × jusqu'à...
    "allow_parentheses": False,# ignoré si une division est incluse
    "per_question_timeout": 0, # 0 = illimité
    "limit_result": False,
    "max_result": 100,
    "retry_until_correct": False,

    # audio & affichage
    "audio_mode": False,
    "voice_answer": False,
    "voice_choice_id": "",
    "stt_lang": "FR",
    "audio_stt_delay": 0.6,
    "audio_tts_overlap": 1.2,
    "auto_submit": False,
    "auto_submit_delay": 2.0,
    "music_enabled": True,
    "music_volume": 0.15,
    "sfx_enabled": True,
    "sfx_volume": 1.0,
    "fullscreen": False,
    "center_text": False,
    "center_offset": 35,
    "font_level": 3,
}

# ---------- Générateur d'expressions ----------
SYMBOLS = {"+": "+", "-": "−", "*": "×", "/": "÷"}

class MathGenerator:
    def __init__(self, opts):
        self.o = opts
        self.rng = random.Random()
    def _active_ops(self):
        ops = []
        if self.o.get("op_add", True): ops.append("+")
        if self.o.get("op_sub", True): ops.append("-")
        if self.o.get("op_mul", False): ops.append("*")
        if self.o.get("op_div", False): ops.append("/")
        if not ops: ops = ['+']
        return ops
    def _active_digit_buckets(self):
        buckets = []
        if self.o.get("digits_units", True): buckets.append((0,9))
        if self.o.get("digits_tens", True): buckets.append((10,99))
        if self.o.get("digits_hundreds", False): buckets.append((100,999))
        if self.o.get("digits_thousands", False): buckets.append((1000,9999))
        if self.o.get("digits_ten_thousands", False): buckets.append((10000,99999))
        if self.o.get("digits_hundred_thousands", False): buckets.append((100000,999999))
        if not buckets: buckets=[(0,9)]
        return buckets
    def _rand_from_bucket(self, bucket, nonzero=False):
        a,b = bucket
        if nonzero and a<=0<=b:
            # évite 0 si demandé (utile pour divisions)
            x = 0
            while x == 0:
                x = self.rng.randint(a,b)
            return x
        return self.rng.randint(a,b)
    def _make_add_no_carry_pair(self, bucket):
        # essaie de générer deux nombres dont la somme des unités < 10
        # (simple heuristique, valable quel que soit l'intervalle)
        for _ in range(200):
            x = self._rand_from_bucket(bucket)
            y = self._rand_from_bucket(bucket)
            if (abs(x)%10 + abs(y)%10) < 10:
                return x,y
        return self._rand_from_bucket(bucket), self._rand_from_bucket(bucket)
    def _make_sub_no_borrow_pair(self, bucket):
        # construit deux nombres digit-par-digit pour éviter l'emprunt (2 opérandes)
        # on s'en tient à des nombres positifs de même ordre de grandeur
        a,b = bucket
        maxv = max(abs(a), abs(b))
        digits = max(1, len(str(maxv)))
        x=0; y=0; place=1
        for _ in range(digits):
            dx = self.rng.randint(0,9)
            dy = self.rng.randint(0,dx)
            x += dx*place; y += dy*place; place*=10
        # remet dans le bucket globalement
        base_min = 10**(digits-1)
        if base_min < a: x = max(a, x)
        if base_min < a: y = max(a, y)
        return x,y
    def _pick_bucket_for_problem(self, buckets):
        if self.o.get("mix_digit_sizes", True):
            return None  # signifie: par opérande on choisira
        return self.rng.choice(buckets)
    def _next_operand(self, bucket_fixed, buckets, nonzero=False, limit_tables=False, tables_max=12):
        bucket = bucket_fixed if bucket_fixed else self.rng.choice(buckets)
        if limit_tables and bucket == (0, 9):
            return self.rng.randint(2, max(2, tables_max))
        return self._rand_from_bucket(bucket, nonzero=nonzero)

    def make_problem(self):
        ops = self._active_ops()
        buckets = self._active_digit_buckets()
        limit_res = bool(self.o.get("limit_result", False))
        max_res = int(self.o.get("max_result", 100))
        nmin = int(self.o.get("min_operands",2)); nmax = int(self.o.get("max_operands",3))
        if nmin>nmax: nmin,nmax = nmax,nmin
        if self.o.get("sub_no_borrow", False):
            nmin=nmax=2  # simplifie
        n_operands = self.rng.randint(nmin, nmax)
        bucket_fixed = self._pick_bucket_for_problem(buckets)
        mix_ops = bool(self.o.get("mix_ops_in_expr", True))
        use_par = bool(self.o.get("allow_parentheses", False))
        div_int = bool(self.o.get("div_integer_only", True))
        allow_neg = bool(self.o.get("allow_negatives", False))
        pos_result = bool(self.o.get("positive_result", True))
        limit_tables = bool(self.o.get("limit_tables", True))
        tables_max = int(self.o.get("tables_max", 12))

        # si division possible → on n'utilise pas de parenthèses pour garder les entiers simples
        if "/" in ops: use_par = False

        tokens = []   # version python (opérations: +,-,*,//)
        display = []  # version affichage (+, −, ×, ÷)

        def push_num(v):
            tokens.append(str(int(v)))
            display.append(str(int(v)))
        def push_op(op):
            py = {'+':'+','-':'-','*':'*','/':'//'}[op]
            tokens.append(py)
            display.append(SYMBOLS[op])

        # premier terme
        if self.o.get("add_no_carry", False) and n_operands==2 and "+" in ops and not mix_ops:
            # cas spécial: on fabrique le couple tout de suite
            bucket = bucket_fixed or self.rng.choice(buckets)
            a,b = self._make_add_no_carry_pair(bucket)
            if self.rng.random()<0.5: a,b=b,a
            push_num(a); push_op('+'); push_num(b)
            expr_py = " ".join(tokens); expr_disp = " ".join(display)
            try:
                val = eval(expr_py)
                if not allow_neg and val < 0: raise Exception()
                if limit_res and abs(val) > max_res: raise Exception()
                return expr_disp, val
            except Exception:
                return self.make_problem()

        if self.o.get("sub_no_borrow", False):
            bucket = bucket_fixed or self.rng.choice(buckets)
            a,b = self._make_sub_no_borrow_pair(bucket)
            # s'assure résultat non-négatif si demandé
            if pos_result and a<b: a,b=b,a
            push_num(a); push_op('-'); push_num(b)
            expr_py = " ".join(tokens); expr_disp = " ".join(display)
            try:
                val = eval(expr_py)
                if not allow_neg and val < 0: raise Exception()
                if limit_res and abs(val) > max_res: raise Exception()
                return expr_disp, val
            except Exception:
                return self.make_problem()

        # cas général : on construit pas-à-pas en évitant les divisions non-entières
        cur = self._next_operand(
            bucket_fixed, buckets, nonzero=False,
            limit_tables=limit_tables and "*" in ops, tables_max=tables_max
        )
        push_num(cur)

        chosen_ops = []
        for i in range(n_operands-1):
            op = self.rng.choice(ops) if mix_ops else ops[0]
            if op == "/":
                # choisit un diviseur du cur (non nul)
                divisors = []
                c = abs(int(cur))
                if c==0:
                    cur = self._next_operand(bucket_fixed, buckets, nonzero=True)
                    c = abs(int(cur))
                for d in range(1, c+1):
                    if c % d == 0: divisors.append(d)
                # pour éviter trivial 1 trop souvent
                if len(divisors)>1 and 1 in divisors and self.rng.random()<0.7:
                    divisors.remove(1)
                d = self.rng.choice(divisors)
                # remet le signe selon allow_neg (on garde d>0 ici)
                nxt = d
                push_op(op); push_num(nxt)
                # évalue partiel
                cur = cur // nxt
            elif op == "*":
                nxt = self._next_operand(
                    bucket_fixed, buckets, nonzero=False,
                    limit_tables=limit_tables, tables_max=tables_max
                )
                push_op(op); push_num(nxt)
                cur = cur * nxt
            elif op == "+":
                nxt = self._next_operand(bucket_fixed, buckets, nonzero=False)
                push_op(op); push_num(nxt)
                cur = cur + nxt
            elif op == "-":
                nxt = self._next_operand(bucket_fixed, buckets, nonzero=False)
                # si résultat doit rester positif
                if pos_result and (cur - nxt) < 0:
                    # échange la soustraction en addition inverse si possible
                    # sinon on régénère nxt plus petit
                    tries=0
                    while (cur - nxt) < 0 and tries<50:
                        nxt = self._next_operand(bucket_fixed, buckets, nonzero=False)
                        tries+=1
                    if (cur - nxt) < 0:
                        # bascule l'ordre: nxt - cur et inverse le sens (reconstruit proprement)
                        tokens = [str(int(nxt)), '-', str(int(cur))]
                        display = [str(int(nxt)), SYMBOLS['-'], str(int(cur))]
                        cur = nxt - cur
                        # continue la construction
                        chosen_ops = ['-']
                        continue
                push_op(op); push_num(nxt)
                cur = cur - nxt
            chosen_ops.append(op)

        # Parenthèses légères : entoure un segment si possible et utile (pas de division)
        if use_par and any(op in ['+','-','*'] for op in chosen_ops) and '/' not in chosen_ops and len(tokens)>=5:
            # tokens: n op n op n ... ; on choisit (n op n) quelque part
            # place une paire autour de 3 tokens (a op b)
            # On évite de casser l'évaluation en //
            try:
                # construire indices des nombres
                idx_nums = [i for i,t in enumerate(tokens) if t not in ['+','-','*','//']]
                if len(idx_nums)>=2:
                    k = self.rng.randint(0, len(idx_nums)-2)
                    a_i = idx_nums[k]
                    b_i = idx_nums[k+1]
                    # nous voulons parenthéser [a_i .. b_i], qui correspond à: a_i, op, b_i
                    L = tokens[:a_i] + ['('] + tokens[a_i:b_i+1] + [')'] + tokens[b_i+1:]
                    tokens2 = L
                    disp_ops = {'+':'+','-':SYMBOLS['-'],'*':SYMBOLS['*'] if '*' in SYMBOLS else '×','//':SYMBOLS['/']}
                    # reconstruire display pareil
                    # on refait plus simple: recompose depuis tokens2
                    display2=[]
                    for t in tokens2:
                        if t == '(': display2.append('(')
                        elif t == ')': display2.append(')')
                        elif t in ['+','-','*','//']:
                            if t=='//': display2.append(SYMBOLS['/'])
                            elif t=='*': display2.append(SYMBOLS['*'] if '*' in SYMBOLS else '×')
                            else: display2.append(t if t!='-' else SYMBOLS['-'])
                        else:
                            display2.append(t)
                    expr_py = " ".join(tokens2)
                    val = eval(expr_py)
                    if not allow_neg and val<0: raise Exception()
                    if limit_res and abs(val) > max_res: raise Exception()
                    return " ".join(display2), int(val)
            except Exception:
                pass
        # final
        expr_py = " ".join(tokens)
        expr_disp = " ".join(display)
        try:
            val = eval(expr_py)
            if not allow_neg and val < 0: raise Exception()
            if limit_res and abs(val) > max_res: raise Exception()
            return expr_disp, int(val)
        except Exception:
            # si problème (rare), on régénère
            return self.make_problem()

    # --- séquence d'additions pour Flash Anzan ---
    def make_flash_numbers(self, count):
        buckets = self._active_digit_buckets()
        allow_neg = bool(self.o.get("allow_negatives", False))
        only_neg = bool(self.o.get("only_negatives", False))
        pos_result = bool(self.o.get("positive_result", True))
        limit_res = bool(self.o.get("limit_result", False))
        max_res = int(self.o.get("max_result", 100))
        bucket_fixed = self._pick_bucket_for_problem(buckets)
        while True:
            nums = []
            for _ in range(count):
                while True:
                    n = self._next_operand(bucket_fixed, buckets, nonzero=False)
                    if only_neg:
                        n = -abs(n)
                    elif allow_neg and self.rng.random() < 0.5:
                        n = -n
                    if nums and n == nums[-1]:
                        continue
                    nums.append(n)
                    break
            total = sum(nums)
            if pos_result and total < 0:
                continue
            if limit_res and abs(total) > max_res:
                continue
            return nums, total

# ---------- Scènes ----------
class Scene:
    def handle(self, ev): pass
    def update(self, dt): pass
    def draw(self, surf): pass


class FadeTransition:
    def __init__(self, app, next_scene, dur=300):
        self.app = app
        self.next = next_scene
        self.t0 = pygame.time.get_ticks()
        self.dur = dur
        self.phase = 0

    def update(self):
        t = pygame.time.get_ticks() - self.t0
        if self.phase == 0 and t > self.dur // 2:
            self.app.scene = self.next
            self.phase = 1
        if t > self.dur:
            self.app._transition = None

    def draw(self, surf):
        t = pygame.time.get_ticks() - self.t0
        if self.phase == 0:
            a = 255 * (t / (self.dur // 2))
        else:
            a = 255 * (1 - (t - self.dur // 2) / (self.dur // 2))
        overlay = pygame.Surface(surf.get_size(), pygame.SRCALPHA)
        overlay.fill((0, 0, 0, int(max(0, min(255, a)))))
        surf.blit(overlay, (0, 0))

class MainMenu(Scene):
    def __init__(self, app):
        self.app = app
        self.app.play_bgm("menu", restart=False)
        self.btn_play = Button((0,0,220,44), "Jouer", self.play, sfx="start")
        self.btn_options = Button((0,0,220,44), "Options", self.options)
        self.btn_rules = Button((0,0,220,44), "Règles du jeu", self.rules)
        self.btn_scores = Button((0,0,220,44), "Scores", self.scores)
        self.btn_quit = Button((0,0,220,44), "Quitter", self.quit)
        self.graph_mode = 1
        self.profile_names = profiles_for_mode(app.profiles, self.graph_mode)
        if app.profile_name in self.profile_names:
            self.graph_profile_idx = self.profile_names.index(app.profile_name)
        else:
            self.graph_profile_idx = 0
        self.graph_profile = self.profile_names[self.graph_profile_idx] if self.profile_names else ""
        self.graph_scores = ScoreManager(_scores_file_for(self.graph_profile))
        self.btn_graph_profile = Button((0,0,160,40), f"Profil: {self.graph_profile or '—'}", self.toggle_graph_profile)
        self.btn_graph_mode = Button((0,0,160,40), "Contre-la-montre", self.toggle_graph_mode)
        self.btn_graph_clear = Button((0,0,120,40), "Effacer", self.clear_graph)
        self.scroll = 0.0; self._content_h = 0
        self._graph_clear_armed_until = 0
        self.bg = AnimatedBackground(style="fusion")  # ou "grid"
        self.scroll = 0.0; self._content_h = 0
        self._graph_clear_armed_until = 0
    def play(self): self.app.goto(GameScene(self.app))
    def options(self): self.app.goto(OptionsScene(self.app))
    def rules(self): self.app.goto(RulesScene(self.app))
    def scores(self): self.app.goto(ScoresScene(self.app))
    def quit(self): pygame.event.post(pygame.event.Event(pygame.QUIT))
    def handle(self, ev):
        if ev.type == pygame.MOUSEWHEEL:
            w,h = screen.get_size(); top=110; viewport_h = max(0, h-top-20)
            max_scroll = max(0, self._content_h - viewport_h)
            self.scroll -= ev.y * 36; self.scroll = clamp(self.scroll, 0, max_scroll)
        for b in (self.btn_play, self.btn_options, self.btn_rules, self.btn_scores, self.btn_quit,
                  self.btn_graph_profile, self.btn_graph_mode, self.btn_graph_clear):
            b.handle(ev)
        if ev.type == pygame.KEYDOWN and ev.key == pygame.K_F8:
            new_style = self.bg.toggle_style()
            sfx_play("step")                # petit feedback sonore
            if hasattr(self.app, "toast"):  # message en haut (optionnel)
                self.app.toast(f"Fond: {new_style}")
    def update(self, dt):
        w, h = screen.get_size()
        self.bg.update(dt, (w, h))
    def draw(self, surf):
        w, h = surf.get_size(); surf.fill((25, 27, 30))
        self.bg.draw(surf)                              # <-- arrière-plan animé
        title_surf = FONT_HUGE.render(APP_NAME, True, WHITE)
        title_rect = title_surf.get_rect(center=(w // 2, int(70 * ui_scale)))
        surf.blit(title_surf, title_rect)
        draw_play_icon(surf, (title_rect.left - int(40*ui_scale), title_rect.centery), WHITE, int(32*ui_scale))
        top_margin = int(110 * ui_scale)
        viewport = pygame.Rect(0, top_margin, w, max(0, h - top_margin - int(20 * ui_scale)))
        colx = w // 2 - int(110 * ui_scale); y0 = int(140 * ui_scale)
        btns = (self.btn_play, self.btn_options, self.btn_rules, self.btn_scores, self.btn_quit)
        btn_spacing = int(58 * ui_scale)
        noscroll_y_end = y0 + btn_spacing * len(btns)
        panel_h = int(300 * ui_scale); panel_top_space = int(24 * ui_scale)
        content_bottom_noscroll = noscroll_y_end + panel_top_space + panel_h
        self._content_h = (content_bottom_noscroll - y0) + int(20 * ui_scale)
        prev = surf.get_clip(); surf.set_clip(viewport)
        y = y0 - self.scroll
        for b in btns:
            b.rect.topleft = (colx, y)
            b.rect.size = (int(220 * ui_scale), int(44 * ui_scale))
            b.draw(surf)
            y += btn_spacing
        panel = pygame.Rect(int(80 * ui_scale), (noscroll_y_end + panel_top_space) - self.scroll,
                             w - int(160 * ui_scale), panel_h)
        draw_panel(surf, panel, THEME["surface"], border_radius=int(12 * ui_scale))
        _draw_text(surf, "Progression (meilleurs scores du jour)", FONT_MD, WHITE,
                   topleft=(panel.x + int(12 * ui_scale), panel.y + int(10 * ui_scale)))
        bh = int(40 * ui_scale)
        self.btn_graph_clear.rect = pygame.Rect(panel.right-130, panel.y+8, 120, bh)
        self.btn_graph_mode.rect = pygame.Rect(self.btn_graph_clear.rect.x-170, panel.y+8, 160, bh)
        self.btn_graph_profile.rect = pygame.Rect(self.btn_graph_mode.rect.x-170, panel.y+8, 160, bh)
        self.btn_graph_profile.draw(surf)
        self.btn_graph_mode.draw(surf)
        self.btn_graph_clear.draw(surf)
        self.draw_dailybest_graph(surf, panel.inflate(-24,-50).move(0,30), self.graph_mode, scores=self.graph_scores)
        surf.set_clip(prev)
        if self._content_h > viewport.h:
            bar = pygame.Rect(w-10, viewport.y+8, 6, viewport.h-16)
            pygame.draw.rect(surf, (60,60,70), bar)
            ratio = viewport.h / self._content_h
            handle_h = max(30, int(bar.h * ratio))
            max_scroll = max(1, self._content_h - viewport.h)
            pos_ratio = self.scroll / max_scroll
            handle_y = int(bar.y + pos_ratio * (bar.h - handle_h))
            pygame.draw.rect(surf, ORANGE, (bar.x, clamp(handle_y, bar.y, bar.bottom-handle_h), bar.w, handle_h))
        hint1 = FONT_SMALL.render("F11 : plein écran", True, LIGHT_GRAY)
        hint2 = FONT_SMALL.render("F8 : changer de fond animé", True, LIGHT_GRAY)
        surf.blit(hint1, hint1.get_rect(center=(w//2, h - int(28 * ui_scale))))
        surf.blit(hint2, hint2.get_rect(center=(w//2, h - int(15 * ui_scale))))
    def draw_history_graph(self, surf, rect, mode=None, scores=None):
        sc = scores or self.app.scores
        hist = sc.history(mode)
        if not hist:
            _draw_text(surf, "Aucune session pour l'instant.", FONT_SMALL, LIGHT_GRAY, topleft=(rect.x+8, rect.y+8)); return
        scores = [e.get("score",0) for e in hist]
        maxs = max(scores); mins = min(scores); maxs=max(maxs,1.0)
        draw_panel(surf, rect, (50,50,55), border_radius=8)
        ax = rect.inflate(-20,-20)
        grid_col = (90,90,95)
        for i in range(6):
            y = ax.y + i*(ax.h/5.0); pygame.draw.line(surf,grid_col,(ax.x,y),(ax.right,y),1)
        if mins <= 0 <= maxs and maxs != mins:
            zy = ax.bottom - (0 - mins)/(maxs-mins)*ax.h
            pygame.draw.line(surf, (100,100,105), (ax.x, zy), (ax.right, zy), 1)
        pts=[]
        for i,scv in enumerate(scores):
            t = i/(len(scores)-1) if len(scores)>1 else 0
            x = ax.x + t*ax.w
            y = ax.bottom - (scv-mins)/(maxs-mins)*ax.h if maxs!=mins else ax.centery
            pts.append((int(x),int(y)))
        if len(pts)>=2:
            grad = pygame.Surface(ax.size, pygame.SRCALPHA)
            for y in range(ax.h):
                a = int(120*(1 - y/ax.h))
                pygame.draw.line(grad, (*ORANGE,a), (0,y), (ax.w,y))
            poly=[(px-ax.x,py-ax.y) for (px,py) in pts]
            poly+=[(pts[-1][0]-ax.x, ax.h),(pts[0][0]-ax.x, ax.h)]
            mask = pygame.Surface(ax.size, pygame.SRCALPHA)
            pygame.draw.polygon(mask, (255,255,255,255), poly)
            grad.blit(mask,(0,0),special_flags=pygame.BLEND_RGBA_MULT)
            surf.blit(grad, ax)
            pygame.draw.lines(surf, ORANGE, False, pts, 3)
        for x,y in pts:
            pygame.draw.circle(surf, ORANGE, (x,y), 4)
        mx,my = pygame.mouse.get_pos()
        for i,(x,y) in enumerate(pts):
            if abs(mx-x)<=6 and abs(my-y)<=6:
                entry = hist[i]
                tip = f"{entry.get('score',0)} – {str(entry.get('date',''))[:10]}"
                tip_surf = FONT_SMALL.render(tip, True, WHITE)
                pad = 6
                r = tip_surf.get_rect(); tooltip=pygame.Rect(0,0,r.w+2*pad,r.h+2*pad)
                tooltip.center=(x, y-20)
                box = pygame.Surface(tooltip.size, pygame.SRCALPHA)
                pygame.draw.rect(box,(0,0,0,200),box.get_rect(),border_radius=6)
                box.blit(tip_surf,(pad,pad))
                surf.blit(box, tooltip.topleft)
                break
        _draw_text(surf, f"min {mins:.0f}", FONT_SMALL, LIGHT_GRAY, topleft=(ax.x, ax.y-16))
        _draw_text(surf, f"max {maxs:.0f}", FONT_SMALL, LIGHT_GRAY, topleft=(ax.x+80, ax.y-16))

    def draw_dailybest_graph(self, surf, rect, mode, scores=None):
        sc = scores or self.app.scores
        rows = sc.get_daily_bests(mode)
        if not rows:
            _draw_text(surf, "Aucun 'meilleur du jour' enregistré.", FONT_SMALL, LIGHT_GRAY,
                       topleft=(rect.x+8, rect.y+8))
            return
        scores = [int(r.get("score",0)) for r in rows]
        if not scores:
            return
        maxs = max(scores)
        mins = min(scores)
        maxs = max(maxs, 1.0)
        draw_panel(surf, rect, (50,50,55), border_radius=8)
        ax = rect.inflate(-20,-20)
        grid_col = (90,90,95)
        for i in range(6):
            y = ax.y + i*(ax.h/5.0)
            pygame.draw.line(surf,grid_col,(ax.x,y),(ax.right,y),1)
        if mins <= 0 <= maxs and maxs != mins:
            zy = ax.bottom - (0 - mins)/(maxs-mins)*ax.h
            pygame.draw.line(surf,(100,100,105),(ax.x,zy),(ax.right,zy),1)
        pts=[]
        for i,sc in enumerate(scores):
            t = i/(len(scores)-1) if len(scores)>1 else 0
            x = ax.x + t*ax.w
            y = ax.bottom - (sc-mins)/(maxs-mins)*ax.h if maxs!=mins else ax.centery
            pts.append((int(x),int(y)))
        if len(pts)>=2:
            grad = pygame.Surface(ax.size, pygame.SRCALPHA)
            for y in range(ax.h):
                a = int(120*(1 - y/ax.h))
                pygame.draw.line(grad, (*ORANGE,a), (0,y), (ax.w,y))
            poly=[(px-ax.x,py-ax.y) for (px,py) in pts]
            poly+=[(pts[-1][0]-ax.x, ax.h),(pts[0][0]-ax.x, ax.h)]
            mask = pygame.Surface(ax.size, pygame.SRCALPHA)
            pygame.draw.polygon(mask,(255,255,255,255),poly)
            grad.blit(mask,(0,0),special_flags=pygame.BLEND_RGBA_MULT)
            surf.blit(grad, ax)
            pygame.draw.lines(surf, ORANGE, False, pts, 3)
        for x,y in pts:
            pygame.draw.circle(surf, ORANGE, (x,y), 4)
        mx,my = pygame.mouse.get_pos()
        for i,(x,y) in enumerate(pts):
            if abs(mx-x)<=6 and abs(my-y)<=6:
                entry = rows[i]
                tip = f"{entry.get('score',0)} – {entry.get('day','')[:10]}"
                tip_surf = FONT_SMALL.render(tip, True, WHITE)
                pad=6
                r = tip_surf.get_rect(); tooltip=pygame.Rect(0,0,r.w+2*pad,r.h+2*pad)
                tooltip.center=(x, y-20)
                box = pygame.Surface(tooltip.size, pygame.SRCALPHA)
                pygame.draw.rect(box,(0,0,0,200),box.get_rect(),border_radius=6)
                box.blit(tip_surf,(pad,pad))
                surf.blit(box, tooltip.topleft)
                break
        _draw_text(surf, f"min {mins:.0f}", FONT_SMALL, LIGHT_GRAY, topleft=(ax.x, ax.y-16))
        _draw_text(surf, f"max {maxs:.0f}", FONT_SMALL, LIGHT_GRAY, topleft=(ax.x+80, ax.y-16))

    def toggle_graph_mode(self):
        self.graph_mode = 1 if self.graph_mode == 5 else self.graph_mode + 1
        if self.graph_mode == 1:
            self.btn_graph_mode.text = "Contre-la-montre"
        elif self.graph_mode == 2:
            self.btn_graph_mode.text = "Série"
        elif self.graph_mode == 3:
            self.btn_graph_mode.text = "Flash Anzan"
        elif self.graph_mode == 4:
            self.btn_graph_mode.text = "Mode audio"
        else:
            self.btn_graph_mode.text = "Calcul Infernal"
        self.profile_names = profiles_for_mode(self.app.profiles, self.graph_mode)
        self.graph_profile_idx = 0
        self.graph_profile = self.profile_names[0] if self.profile_names else ""
        self.graph_scores = ScoreManager(_scores_file_for(self.graph_profile))
        self.btn_graph_profile.text = f"Profil: {self.graph_profile or '—'}"

    def clear_graph(self):
        if time.time() < getattr(self, "_graph_clear_armed_until", 0):
            self.graph_scores.clear()
            self.app.toast("Scores effacés.", kind="success")
            self._graph_clear_armed_until = 0
        else:
            self._graph_clear_armed_until = time.time() + 2.0
            self.app.toast("Êtes-vous sûr ?", kind="warning")

    def toggle_graph_profile(self):
        if not self.profile_names:
            return
        self.graph_profile_idx = (self.graph_profile_idx + 1) % len(self.profile_names)
        self.graph_profile = self.profile_names[self.graph_profile_idx]
        self.graph_scores = ScoreManager(_scores_file_for(self.graph_profile))
        self.btn_graph_profile.text = f"Profil: {self.graph_profile}"

class OptionsScene(Scene):
    def __init__(self, app):
        self.app = app; self.o = app.options
        self.app.play_bgm("menu", restart=False)
        self._ptt = False
        # Profils
        self.prof_prev = Button((0,0,40,40), "<", self.prev_profile)
        self.prof_next = Button((0,0,40,40), ">", self.next_profile)
        self.prof_new = Button((0,0,120,40), "Nouveau", lambda: self.start_profile_edit("new"))
        self.prof_ren = Button((0,0,120,40), "Renommer", lambda: self.start_profile_edit("rename"))
        self.prof_del = Button((0,0,120,40), "Supprimer", self.delete_profile)
        self.prof_input = TextInput((0,0,240,40), text="", placeholder="Nom du profil")
        self.prof_ok = Button((0,0,100,40), "OK", self.confirm_profile_edit)
        self.prof_cancel = Button((0,0,100,40), "Annuler", self.cancel_profile_edit)
        self.edit_profile_mode = None
        self._del_confirm_stage = 0
        self._del_confirm_until = 0
        # Champs
        self.mode_btn_prev = Button((0,0,40,40), "<", self.prev_mode)
        self.mode_btn_next = Button((0,0,40,40), ">", self.next_mode)
        self.mode_names = {1:"Contre-la-montre", 2:"Série chronométrée", 3:"Flash Anzan", 4:"Mode audio", 5:"Calcul Infernal"}
        if "fixed_mode" in self.o and self.app.profile_name != DEFAULT_PROFILE:
            self.mode_btn_prev.enabled = False
            self.mode_btn_next.enabled = False
        self.duration = TextInput((0,0,100,40), text=str(self.o["duration_sec"]), numeric_only=True, min_val=10, max_val=999)
        nb_val = self.o["num_problems"] if self.o["mode"] in (2,4) else self.o.get("flash_numbers", self.o.get("flash_additions",5))
        self.nb = TextInput((0,0,100,40), text=str(nb_val), numeric_only=True, min_val=1, max_val=999)
        self.series = TextInput((0,0,100,40), text=str(self.o.get("flash_series",10)), numeric_only=True, min_val=1, max_val=999)
        self.level = TextInput((0,0,90,40), text=str(self.o["level"]), numeric_only=True, min_val=1, max_val=5)

        # spinners pour les champs numériques principaux
        self.duration_up = Button((0,0,28,18), "▲", lambda: self._step(self.duration, +1, 10, 999), sfx="step")
        self.duration_dn = Button((0,0,28,18), "▼", lambda: self._step(self.duration, -1, 10, 999), sfx="step")
        self.nb_up = Button((0,0,28,18), "▲", lambda: self._step(self.nb, +1, 1, 999), sfx="step")
        self.nb_dn = Button((0,0,28,18), "▼", lambda: self._step(self.nb, -1, 1, 999), sfx="step")
        self.series_up = Button((0,0,28,18), "▲", lambda: self._step(self.series, +1, 1, 999), sfx="step")
        self.series_dn = Button((0,0,28,18), "▼", lambda: self._step(self.series, -1, 1, 999), sfx="step")
        self.level_up = Button((0,0,28,18), "▲", lambda: self._step(self.level, +1, 1, 5), sfx="step")
        self.level_dn = Button((0,0,28,18), "▼", lambda: self._step(self.level, -1, 1, 5), sfx="step")

        self.inf_n = TextInput((0,0,80,40), text=str(self.o.get("infernal_n",3)), numeric_only=True, min_val=1, max_val=9)
        self.inf_n_up = Button((0,0,28,18), "▲", lambda: self._step(self.inf_n, +1, 1, 9), sfx="step")
        self.inf_n_dn = Button((0,0,28,18), "▼", lambda: self._step(self.inf_n, -1, 1, 9), sfx="step")
        self.infspd_labels = ["Lent", "Moyen", "Rapide"]
        self.infspd_idx = clamp(int(self.o.get("infernal_speed",1)), 0, 2)
        self.infspd_prev = Button((0,0,40,40), "<", lambda: setattr(self, 'infspd_idx', (self.infspd_idx-1)%3), sfx="step")
        self.infspd_next = Button((0,0,40,40), ">", lambda: setattr(self, 'infspd_idx', (self.infspd_idx+1)%3), sfx="step")

        # opérations
        self.chk_add = Checkbox((0,0,200,24), "Addition (+)", checked=self.o["op_add"])
        self.chk_sub = Checkbox((0,0,200,24), "Soustraction (−)", checked=self.o["op_sub"])
        self.chk_mul = Checkbox((0,0,200,24), "Multiplication (×)", checked=self.o["op_mul"])
        self.chk_div = Checkbox((0,0,200,24), "Division (÷)", checked=self.o["op_div"])
        self.chk_mix_ops = Checkbox((0,0,260,24), "Mélanger les opérations dans un calcul", checked=self.o["mix_ops_in_expr"])

        # opérandes
        self.min_ops = TextInput((0,0,80,40), text=str(self.o["min_operands"]), numeric_only=True, min_val=2, max_val=9)
        self.max_ops = TextInput((0,0,80,40), text=str(self.o["max_operands"]), numeric_only=True, min_val=2, max_val=9)

        self.min_ops_up = Button((0,0,28,18), "▲", lambda: self._step(self.min_ops, +1, 2, 9), sfx="step")
        self.min_ops_dn = Button((0,0,28,18), "▼", lambda: self._step(self.min_ops, -1, 2, 9), sfx="step")
        self.max_ops_up = Button((0,0,28,18), "▲", lambda: self._step(self.max_ops, +1, 2, 9), sfx="step")
        self.max_ops_dn = Button((0,0,28,18), "▼", lambda: self._step(self.max_ops, -1, 2, 9), sfx="step")

        # taille nombres
        self.chk_u = Checkbox((0,0,200,24), "Unités (0–9)", checked=self.o["digits_units"])
        self.chk_t = Checkbox((0,0,200,24), "Dizaines (10–99)", checked=self.o["digits_tens"])
        self.chk_h = Checkbox((0,0,200,24), "Centaines (100–999)", checked=self.o["digits_hundreds"])
        self.chk_k = Checkbox((0,0,200,24), "Milliers (1000–9999)", checked=self.o["digits_thousands"])
        self.chk_10k = Checkbox((0,0,260,24), "Dizaines de milliers (10000–99999)", checked=self.o.get("digits_ten_thousands", False))
        self.chk_100k = Checkbox((0,0,260,24), "Centaines de milliers (100000–999999)", checked=self.o.get("digits_hundred_thousands", False))
        self.chk_mix_digits = Checkbox((0,0,260,24), "Mélanger les tailles dans un calcul", checked=self.o["mix_digit_sizes"])

        # contraintes
        self.chk_pos = Checkbox((0,0,260,24), "Résultat toujours positif", checked=self.o["positive_result"])
        self.chk_neg = Checkbox((0,0,260,24), "Autoriser nombres négatifs", checked=self.o["allow_negatives"])
        self.chk_onlyneg = Checkbox((0,0,260,24), "Uniquement des nombres négatifs", checked=self.o.get("only_negatives", False))
        self.chk_div_int = Checkbox((0,0,260,24), "Division à résultat entier uniquement", checked=self.o["div_integer_only"])
        self.chk_add_nc = Checkbox((0,0,260,24), "Addition sans retenue (2 termes)", checked=self.o["add_no_carry"])
        self.chk_sub_nb = Checkbox((0,0,260,24), "Soustraction sans emprunt (2 termes)", checked=self.o["sub_no_borrow"])
        self.chk_tables = Checkbox((0,0,260,24), "Limiter les tables de ×", checked=self.o["limit_tables"])
        self.tables_max = TextInput((0,0,80,40), text=str(self.o["tables_max"]), numeric_only=True, min_val=2, max_val=20)
        self.tables_up = Button((0,0,28,18), "▲", lambda: self._step(self.tables_max, +1, 2, 20), sfx="step")
        self.tables_dn = Button((0,0,28,18), "▼", lambda: self._step(self.tables_max, -1, 2, 20), sfx="step")
        self.chk_par = Checkbox((0,0,260,24), "Parenthèses (pas avec ÷)", checked=self.o["allow_parentheses"])
        self.q_timeout = TextInput((0,0,100,40), text=str(self.o["per_question_timeout"]), numeric_only=True, min_val=0, max_val=999)
        self.qtime_up = Button((0,0,28,18), "▲", lambda: self._step(self.q_timeout, +1, 0, 999), sfx="step")
        self.qtime_dn = Button((0,0,28,18), "▼", lambda: self._step(self.q_timeout, -1, 0, 999), sfx="step")
        self.chk_limit_res = Checkbox((0,0,260,24), "Limiter le résultat", checked=self.o.get("limit_result", False))
        self.max_result = TextInput((0,0,80,40), text=str(self.o.get("max_result",100)), numeric_only=True, min_val=1, max_val=999999)
        self.res_up = Button((0,0,28,18), "▲", lambda: self._step(self.max_result, +1, 1, 999999), sfx="step")
        self.res_dn = Button((0,0,28,18), "▼", lambda: self._step(self.max_result, -1, 1, 999999), sfx="step")
        self.chk_retry = Checkbox((0,0,260,24), "Répéter jusqu'à réussite", checked=self.o.get("retry_until_correct", False))

        # audio & voix
        self.chk_audio = Checkbox((0,0,260,24), "Audio (voix)", checked=self.o.get("audio_mode", False))
        self.chk_voice = Checkbox((0,0,260,24), "Réponse vocale (push-to-talk)", checked=self.o.get("voice_answer", False))
        if self.o["mode"] == 4:
            self.chk_audio.checked = True
            self.chk_voice.checked = True

        # sélecteur de voix TTS
        self.voice_btn_prev = Button((0,0,40,40), "<", None)
        self.voice_btn_next = Button((0,0,40,40), ">", None)
        self.voice_entries = list_tts_voices() if pyttsx3 is not None else []
        if not self.voice_entries:
            self.voice_entries = [{"id":"","label":"Voix indisponible","lang":"??"}]
        cur_id = self.o.get("voice_choice_id", self.voice_entries[0]["id"])
        try:
            self.voice_idx = next(i for i,e in enumerate(self.voice_entries) if e["id"]==cur_id)
        except StopIteration:
            self.voice_idx = 0
        self.voice_btn_prev.on_click = lambda: setattr(self, 'voice_idx', (self.voice_idx-1) % len(self.voice_entries))
        self.voice_btn_next.on_click = lambda: setattr(self, 'voice_idx', (self.voice_idx+1) % len(self.voice_entries))

        # langue STT
        self.stt_lang = (self.o.get("stt_lang") or "FR").upper()
        self.btn_stt_fr = Button((0,0,80,40), "FR", lambda: self.set_stt_lang("FR"))
        self.btn_stt_en = Button((0,0,80,40), "EN", lambda: self.set_stt_lang("EN"))
        self.btn_stt_fr.variant = self.btn_stt_en.variant = "toggle"
        self.chk_hide_expr = Checkbox((0,0,400,24), "Masquer le calcul (afficher \"Calcul N°\")", checked=self.o.get("audio_hide_problem", False))

        self.chk_auto_submit = Checkbox((0,0,400,24), "Valider automatiquement la réponse", checked=self.o.get("auto_submit", False))

        # musique
        self.chk_music = Checkbox((0,0,280,24), "Musique d'ambiance", checked=self.o.get("music_enabled", True))
        mv = int(round(100 * float(self.o.get("music_volume", 0.15))))
        self.music_vol = TextInput((0,0,90,40), text=str(mv), numeric_only=True, min_val=0, max_val=100)
        self.chk_sfx = Checkbox((0,0,200,24), "Bruitages", checked=self.o.get("sfx_enabled", True))
        sv = int(round(100 * float(self.o.get("sfx_volume", 1.0))))
        self.sfx_vol = TextInput((0,0,90,40), text=str(sv), numeric_only=True, min_val=0, max_val=100)

        self.mvol_up = Button((0,0,28,18), "▲", lambda: self._step(self.music_vol, +1, 0, 100), sfx="step")
        self.mvol_dn = Button((0,0,28,18), "▼", lambda: self._step(self.music_vol, -1, 0, 100), sfx="step")
        self.svol_up = Button((0,0,28,18), "▲", lambda: self._step(self.sfx_vol, +1, 0, 100), sfx="step")
        self.svol_dn = Button((0,0,28,18), "▼", lambda: self._step(self.sfx_vol, -1, 0, 100), sfx="step")

        # affichage
        self.chk_fullscreen = Checkbox((0,0,260,24), "Plein écran (F11)", checked=self.o.get("fullscreen", False))
        self.chk_center = Checkbox((0,0,260,24), "Centrer les textes", checked=self.o.get("center_text", False))
        self.center_off = TextInput((0,0,90,40), text=str(self.o.get("center_offset",35)), numeric_only=True, min_val=0, max_val=100)
        self.font_level = TextInput((0,0,90,40), text=str(self.o.get("font_level",3)), numeric_only=True, min_val=1, max_val=16)
        self.center_up = Button((0,0,28,18), "▲", lambda: self._step(self.center_off, +1, 0, 100), sfx="step")
        self.center_dn = Button((0,0,28,18), "▼", lambda: self._step(self.center_off, -1, 0, 100), sfx="step")
        self.font_up = Button((0,0,28,18), "▲", lambda: self._step(self.font_level, +1, 1, 100), sfx="step")
        self.font_dn = Button((0,0,28,18), "▼", lambda: self._step(self.font_level, -1, 1, 100), sfx="step")

        # effets visuels in-game
        self.chk_green_fx = Checkbox(
            (0, 0, 360, 24),
            "Lumière verte réponses correctes",
            checked=self.o.get("green_fx", True),
        )
        self.bg_styles = [
            "Rectangles + couleurs",
            "Rectangles",
            "Aucun",
        ]
        self.bg_idx = clamp(self.o.get("game_bg_style", 0), 0, len(self.bg_styles) - 1)
        self.bg_prev = Button((0, 0, 40, 40), "<", lambda: setattr(self, "bg_idx", (self.bg_idx - 1) % len(self.bg_styles)), sfx="step")
        self.bg_next = Button((0, 0, 40, 40), ">", lambda: setattr(self, "bg_idx", (self.bg_idx + 1) % len(self.bg_styles)), sfx="step")
        self.btn_save = Button((0,0,220,44), "Enregistrer", self.save, sfx="save")

        def _back_to_menu():
            self.app._suppress_next_back_sfx = True
            self.app.goto(MainMenu(self.app))

        self.btn_back = Button((0,0,220,44), "Retour", _back_to_menu, sfx="back")


        self.scroll = 0.0; self._content_h = 0
        # liste consolidée des spinners pour la gestion des événements
        self._spinners = [
            self.duration_up,self.duration_dn,self.nb_up,self.nb_dn,
            self.series_up,self.series_dn,self.level_up,self.level_dn,
            self.inf_n_up,self.inf_n_dn,
            self.min_ops_up,self.min_ops_dn,
            self.max_ops_up,self.max_ops_dn,self.tables_up,self.tables_dn,
            self.qtime_up,self.qtime_dn,self.res_up,self.res_dn,
            self.mvol_up,self.mvol_dn,self.svol_up,self.svol_dn,
            self.center_up,self.center_dn,self.font_up,self.font_dn
        ]
        for b in self._spinners:
            b.style = "ghost"

        self._sync_neg_opts()

        # sections repliables
        if not hasattr(self.app, "opt_section_open"):
            self.app.opt_section_open = {
                k: False
                for k in (
                    "ops",
                    "operands",
                    "sizes",
                    "constraints",
                    "audio",
                    "music",
                    "display",
                )
            }
        self.section_open = self.app.opt_section_open
        self._section_rects = {}

    def prev_mode(self):
        if "fixed_mode" in self.o and self.app.profile_name != DEFAULT_PROFILE:
            return
        self.o["mode"] = 5 if self.o["mode"]==1 else (self.o["mode"]-1)
        if self.o["mode"] == 4:
            self.chk_audio.checked = True
            self.chk_voice.checked = True
        self.chk_t.checked = False if self.o["mode"] in (3,5) else True
        self._sync_neg_opts()
    def next_mode(self):
        if "fixed_mode" in self.o and self.app.profile_name != DEFAULT_PROFILE:
            return
        self.o["mode"] = 1 if self.o["mode"]==5 else (self.o["mode"]+1)
        if self.o["mode"] == 4:
            self.chk_audio.checked = True
            self.chk_voice.checked = True
        self.chk_t.checked = False if self.o["mode"] in (3,5) else True
        self._sync_neg_opts()

    def _step(self, ti: TextInput, delta: int, vmin: int, vmax: int):
        """Incrémente/décrémente un champ numérique."""
        try:
            cur = int(ti.text or "0")
        except Exception:
            cur = vmin
        cur = clamp(cur + delta, vmin, vmax)
        ti.text = str(cur)
        ti._validate()

    def _sync_neg_opts(self):
        if self.o.get("mode") == 3:
            if self.chk_onlyneg.checked:
                self.chk_pos.enabled = False
                self.chk_neg.enabled = False
                self.chk_pos.checked = False
                self.chk_neg.checked = True
            else:
                self.chk_pos.enabled = True
                self.chk_neg.enabled = True
            if self.chk_pos.checked:
                self.chk_onlyneg.enabled = False
                self.chk_onlyneg.checked = False
            else:
                self.chk_onlyneg.enabled = True
        else:
            self.chk_pos.enabled = True
            self.chk_neg.enabled = True
            self.chk_onlyneg.enabled = True

    def set_stt_lang(self, lang):
        self.stt_lang = lang.upper()


    def _draw_spinner(self, surf, ti, btn_up, btn_dn, bounds=SPINNER_HITBOX):
        """Dessine les flèches du spinner avec une hitbox ajustable.

        ``bounds`` est un tuple (haut, droite, bas, gauche) indiquant combien
        de pixels retirer de chaque côté de la zone cliquable pour affiner
        le ciblage.
        """
        top, right, bottom, left = bounds
        x = ti.rect.right + SPINNER_MARGIN_X
        btn_up.rect = pygame.Rect(
            x + left,
            ti.rect.y + top,
            SPINNER_BTN_W - left - right,
            SPINNER_BTN_H - top - bottom,
        )
        btn_dn.rect = pygame.Rect(
            x + left,
            ti.rect.bottom - SPINNER_BTN_H + top,
            SPINNER_BTN_W - left - right,
            SPINNER_BTN_H - top - bottom,
        )
        btn_up.draw(surf)
        btn_dn.draw(surf)

    def _draw_section_header(self, surf, title, key, y):
        """Dessine l'entête d'une section repliable et retourne la nouvelle ordonnée."""
        arrow = "v" if self.section_open.get(key, False) else ">"
        _draw_text(surf, f"{arrow} {title}", FONT_BIG, WHITE, topleft=(40, y))
        self._section_rects[key] = pygame.Rect(40, y, 700, 32)
        return y + 40

    def prev_profile(self):
        names = list(self.app.profiles.keys())
        idx = names.index(self.app.profile_name)
        self.app.load_profile(names[(idx-1)%len(names)])
        self.app.goto(OptionsScene(self.app))

    def next_profile(self):
        names = list(self.app.profiles.keys())
        idx = names.index(self.app.profile_name)
        self.app.load_profile(names[(idx+1)%len(names)])
        self.app.goto(OptionsScene(self.app))

    def delete_profile(self):
        if self.app.profile_name == DEFAULT_PROFILE or len(self.app.profiles) <= 1:
            self.app.toast("Suppression impossible.", kind="error")
            return
        now = time.time()
        if now > self._del_confirm_until:
            self._del_confirm_stage = 0
        self._del_confirm_stage += 1
        self._del_confirm_until = now + 2.0
        if self._del_confirm_stage >= 3:
            self._del_confirm_stage = 0
            if self.app.delete_profile(self.app.profile_name):
                self.app.toast("Profil supprimé.", kind="success")
                self.app.goto(OptionsScene(self.app))
            else:
                self.app.toast("Suppression impossible.", kind="error")
        else:
            if self._del_confirm_stage == 1:
                self.app.toast("Clique encore pour confirmer la suppression (1/2).", kind="warning")
            else:
                self.app.toast("Dernière confirmation : clique encore pour supprimer (2/2).", kind="warning")

    def start_profile_edit(self, mode):
        self.edit_profile_mode = mode
        self.prof_input.text = self.app.profile_name if mode == "rename" else ""
        self.prof_input.cursor_pos = len(self.prof_input.text)

    def confirm_profile_edit(self):
        name = sanitize(self.prof_input.text).strip()
        if not name:
            return
        if self.edit_profile_mode == "new":
            self.app.create_profile(name)
        else:
            self.app.rename_profile(self.app.profile_name, name)
        self.edit_profile_mode = None
        self.app.goto(OptionsScene(self.app))

    def cancel_profile_edit(self):
        self.edit_profile_mode = None

    def save(self):
        try:
            if self.o["mode"] in (1,5):
                self.o["duration_sec"] = max(10, int(self.duration.text or "60"))
            else:
                self.o["duration_sec"] = max(10, int(self.o.get("duration_sec",60)))
        except:
            self.o["duration_sec"] = 60
        try:
            if self.o["mode"] in (2,4):
                self.o["num_problems"] = max(1, int(self.nb.text or "20"))
            elif self.o["mode"] == 3:
                self.o["flash_numbers"] = max(1, int(self.nb.text or "5"))
                self.o["flash_series"] = max(1, int(self.series.text or "10"))
        except:
            if self.o["mode"] in (2,4):
                self.o["num_problems"] = 20
            elif self.o["mode"] == 3:
                self.o["flash_numbers"] = 5
                self.o["flash_series"] = 10
        try: self.o["level"] = clamp(int(self.level.text or "3"), 1, 5)
        except: self.o["level"] = 3
        try: self.o["infernal_n"] = clamp(int(self.inf_n.text or "3"), 1, 9)
        except: self.o["infernal_n"] = 3
        self.o["infernal_speed"] = int(clamp(self.infspd_idx, 0, 2))
        try:
            self.o["min_operands"] = max(2, int(self.min_ops.text or "2"))
            self.o["max_operands"] = max(self.o["min_operands"], int(self.max_ops.text or "3"))
        except:
            self.o["min_operands"], self.o["max_operands"] = 2, 3
        self.o["op_add"] = self.chk_add.checked
        self.o["op_sub"] = self.chk_sub.checked
        self.o["op_mul"] = self.chk_mul.checked
        self.o["op_div"] = self.chk_div.checked
        self.o["mix_ops_in_expr"] = self.chk_mix_ops.checked
        self.o["digits_units"] = self.chk_u.checked
        self.o["digits_tens"] = self.chk_t.checked
        self.o["digits_hundreds"] = self.chk_h.checked
        self.o["digits_thousands"] = self.chk_k.checked
        self.o["digits_ten_thousands"] = self.chk_10k.checked
        self.o["digits_hundred_thousands"] = self.chk_100k.checked
        self.o["mix_digit_sizes"] = self.chk_mix_digits.checked
        self.o["positive_result"] = self.chk_pos.checked
        self.o["allow_negatives"] = self.chk_neg.checked
        self.o["only_negatives"] = self.chk_onlyneg.checked
        self.o["div_integer_only"] = self.chk_div_int.checked
        self.o["add_no_carry"] = self.chk_add_nc.checked
        self.o["sub_no_borrow"] = self.chk_sub_nb.checked
        self.o["limit_tables"] = self.chk_tables.checked
        try: self.o["tables_max"] = clamp(int(self.tables_max.text or "12"), 2, 20)
        except: self.o["tables_max"] = 12
        self.o["allow_parentheses"] = self.chk_par.checked
        try: self.o["per_question_timeout"] = max(0, int(self.q_timeout.text or "0"))
        except: self.o["per_question_timeout"] = 0
        self.o["limit_result"] = self.chk_limit_res.checked
        try: self.o["max_result"] = max(1, int(self.max_result.text or "100"))
        except: self.o["max_result"] = 100
        self.o["retry_until_correct"] = self.chk_retry.checked
        if self.o["mode"] == 3:
            self.o.update({
                "op_add": True,
                "op_sub": False,
                "op_mul": False,
                "op_div": False,
                "mix_ops_in_expr": False,
                "div_integer_only": False,
                "add_no_carry": False,
                "sub_no_borrow": False,
                "limit_tables": False,
                "allow_parentheses": False,
                "retry_until_correct": False,
            })
        if self.o["mode"] == 5:
            self.o.update({
                "op_add": True,
                "op_sub": True,
                "op_mul": False,
                "op_div": False,
                "mix_ops_in_expr": False,
                "min_operands": 2,
                "max_operands": 2,
                "digits_units": True,
                "digits_tens": False,
                "digits_hundreds": False,
                "digits_thousands": False,
                "digits_ten_thousands": False,
                "digits_hundred_thousands": False,
                "mix_digit_sizes": False,
                "allow_negatives": False,
                "only_negatives": False,
                "positive_result": True,
                "div_integer_only": True,
                "add_no_carry": False,
                "sub_no_borrow": False,
                "limit_tables": False,
                "allow_parentheses": False,
                "retry_until_correct": False,
                "per_question_timeout": 0,
                "limit_result": False,
            })
        self.o["audio_mode"] = self.chk_audio.checked
        self.o["voice_answer"] = self.chk_voice.checked
        if self.o["mode"] == 4:
            self.o["audio_mode"] = True
            self.o["voice_answer"] = True
        self.o["audio_hide_problem"] = self.chk_hide_expr.checked
        self.o["auto_submit"] = self.chk_auto_submit.checked
        self.o["voice_choice_id"] = self.voice_entries[self.voice_idx]["id"]
        self.o["stt_lang"] = self.stt_lang
        self.o["music_enabled"] = self.chk_music.checked
        try:
            mv = int(self.music_vol.text or "15")
            mv = clamp(mv, 0, 100)
        except Exception:
            mv = 15
        self.o["music_volume"] = mv/100.0
        self.o["sfx_enabled"] = self.chk_sfx.checked
        try:
            sv = int(self.sfx_vol.text or "100")
            sv = clamp(sv, 0, 100)
        except Exception:
            sv = 100
        self.o["sfx_volume"] = sv/100.0
        self.o["center_text"] = self.chk_center.checked
        try:
            co = int(self.center_off.text or "35")
            co = clamp(co, 0, 100)
        except Exception:
            co = 35
        self.o["center_offset"] = co
        try:
            lvl = int(self.font_level.text or "3")
            lvl = clamp(lvl, 1, 100)
        except Exception:
            lvl = 3
        self.o["font_level"] = lvl
        self.o["green_fx"] = self.chk_green_fx.checked
        self.o["game_bg_style"] = self.bg_idx
        self.o["fullscreen"] = self.chk_fullscreen.checked
        if self.app.profile_name == DEFAULT_PROFILE:
            self.o.pop("fixed_mode", None)
        elif "fixed_mode" not in self.o:
            self.o["fixed_mode"] = self.o["mode"]
        # applique immédiatement les changements de police
        self.app.options = self.o.copy()
        self.app.profiles[self.app.profile_name] = self.app.options
        self.app.apply_display_mode()
        self.app.save_profiles()
        if hasattr(self.app, "pause_overlay"):
            self.app.pause_overlay.refresh_from_options()

        if self.o["music_enabled"]:
            self.app.play_bgm("menu", restart=False, volume=self.o["music_volume"])
        else:
            self.app.stop_bgm()
        self.app.toast("Options enregistrées.", kind="success")

    def handle(self, ev):
        if self.edit_profile_mode:
            if ev.type == pygame.KEYDOWN and ev.key == pygame.K_ESCAPE:
                self.edit_profile_mode = None
                return
            self.prof_input.handle(ev)
            self.prof_ok.handle(ev)
            self.prof_cancel.handle(ev)
            return
        if ev.type == pygame.KEYDOWN and ev.key == pygame.K_ESCAPE:
            if self._ptt:
                try:
                    threading.Thread(target=self.stt.stop_and_get_text, daemon=True).start()
                except Exception:
                    pass
                self._ptt = False
            self.app._suppress_next_back_sfx = False
            self.app.goto(MainMenu(self.app)); return
        if ev.type == pygame.MOUSEWHEEL:
            w,h = screen.get_size(); top=90; viewport=pygame.Rect(0, top, w, max(0,h-top-90))
            max_scroll = max(0, self._content_h - viewport.h)
            self.scroll -= ev.y * 36; self.scroll = clamp(self.scroll, 0, max_scroll)
        if ev.type == pygame.MOUSEBUTTONDOWN and ev.button == 1:
            for k, r in self._section_rects.items():
                if r.collidepoint(ev.pos):
                    self.section_open[k] = not self.section_open[k]
                    return
        for wdg in [self.duration, self.nb, self.series, self.level, self.inf_n, self.min_ops, self.max_ops, self.tables_max, self.q_timeout,
                    self.max_result, self.music_vol, self.sfx_vol, self.center_off, self.font_level]:
            if self.o["mode"] == 3 and wdg in (self.min_ops, self.max_ops, self.tables_max):
                continue
            if self.o["mode"] == 5 and wdg is self.level:
                continue
            wdg.handle(ev)
        for cb in [self.chk_add,self.chk_sub,self.chk_mul,self.chk_div,self.chk_mix_ops,
                    self.chk_u,self.chk_t,self.chk_h,self.chk_k,self.chk_10k,self.chk_100k,self.chk_mix_digits,
                    self.chk_pos,self.chk_neg,self.chk_onlyneg,self.chk_div_int,self.chk_add_nc,self.chk_sub_nb,
                    self.chk_tables,self.chk_par,self.chk_limit_res,self.chk_retry,
                    self.chk_audio,self.chk_voice,self.chk_hide_expr,self.chk_auto_submit,
                    self.chk_music,self.chk_sfx,self.chk_fullscreen,self.chk_center,self.chk_green_fx]:
            if self.o["mode"] == 4 and cb in (self.chk_audio, self.chk_voice, self.chk_auto_submit):
                continue
            if self.o["mode"] == 3 and cb in (self.chk_add,self.chk_sub,self.chk_mul,self.chk_div,self.chk_mix_ops,
                                              self.chk_div_int,self.chk_add_nc,self.chk_sub_nb,
                                              self.chk_tables,self.chk_par,self.chk_retry):
                continue
            if cb is self.chk_hide_expr and not self.chk_audio.checked:
                continue
            cb.handle(ev)
        handle_spinner_overlap(self._spinners, ev)
        self.mode_btn_prev.handle(ev); self.mode_btn_next.handle(ev)
        self.prof_prev.handle(ev); self.prof_next.handle(ev)
        self.prof_new.handle(ev); self.prof_ren.handle(ev); self.prof_del.handle(ev)
        self.voice_btn_prev.handle(ev); self.voice_btn_next.handle(ev)
        self.btn_stt_fr.handle(ev); self.btn_stt_en.handle(ev)
        self.bg_prev.handle(ev); self.bg_next.handle(ev)
        self.infspd_prev.handle(ev); self.infspd_next.handle(ev)
        self.btn_save.handle(ev); self.btn_back.handle(ev)
        self._sync_neg_opts()

    def update(self, dt): pass

    def draw(self, surf):
        surf.fill((25,27,30)); w,h = surf.get_size()
        icon_sz = int(32 * ui_scale)
        draw_settings_icon(surf, (40 + icon_sz//2, 24 + icon_sz//2), WHITE, icon_sz)
        _draw_text(surf, "Options", FONT_HUGE, WHITE, topleft=(40 + icon_sz + 10,24))
        top=90; viewport=pygame.Rect(0, top, w, max(0,h-top-90)); prev=surf.get_clip(); surf.set_clip(viewport)
        y0=100; y=y0 - self.scroll
        is_def = self.app.profile_name == DEFAULT_PROFILE
        self.prof_ren.enabled = not is_def
        self.prof_del.enabled = not is_def
        self._section_rects = {}

        # Profils
        _draw_text(surf, "Profil", FONT_BIG, WHITE, topleft=(40,y)); y+=46
        rect = pygame.Rect(180,y-6,220,40)
        draw_panel(surf, rect)
        _draw_text(surf, self.app.profile_name, FONT_MED, WHITE, rect=rect, align="center")
        self.prof_prev.rect.topleft=(140,y-6); self.prof_prev.draw(surf)
        self.prof_next.rect.topleft=(180+220,y-6); self.prof_next.draw(surf)
        y+=50
        self.prof_new.rect.topleft=(40,y); self.prof_new.draw(surf)
        self.prof_ren.rect.topleft=(180,y); self.prof_ren.draw(surf)
        self.prof_del.rect.topleft=(320,y); self.prof_del.draw(surf)
        y+=60
        # Mode
        _draw_text(surf, "Mode de jeu", FONT_BIG, WHITE, topleft=(40,y)); y+=46
        _draw_text(surf, self.mode_names[self.o["mode"]], FONT_MED, WHITE, topleft=(100,y))
        self.mode_btn_prev.rect.topleft=(40,y-6); self.mode_btn_prev.draw(surf)
        self.mode_btn_next.rect.topleft=(40+36+320,y-6); self.mode_btn_next.draw(surf)
        y+=50
        if self.o["mode"] == 1:
            _draw_text(surf, "Durée (secondes)", FONT_MED, WHITE, topleft=(40,y))
            self.duration.rect.topleft=(260,y-6); self.duration.rect.size=(100,36); self.duration.draw(surf)
            self._draw_spinner(surf, self.duration, self.duration_up, self.duration_dn)
            y+=50
        elif self.o["mode"] in (2,4):
            _draw_text(surf, "Nombre de calculs", FONT_MED, WHITE, topleft=(40,y))
            self.nb.rect.topleft=(260,y-6); self.nb.rect.size=(100,36); self.nb.draw(surf)
            self._draw_spinner(surf, self.nb, self.nb_up, self.nb_dn)
            y+=50
        elif self.o["mode"] == 3:
            _draw_text(surf, "Nombre de séries", FONT_MED, WHITE, topleft=(40,y))
            self.series.rect.topleft=(260,y-6); self.series.rect.size=(100,36); self.series.draw(surf)
            self._draw_spinner(surf, self.series, self.series_up, self.series_dn)
            y+=50
            _draw_text(surf, "Nombres par série", FONT_MED, WHITE, topleft=(40,y))
            self.nb.rect.topleft=(320,y-6); self.nb.rect.size=(100,36); self.nb.draw(surf)
            self._draw_spinner(surf, self.nb, self.nb_up, self.nb_dn)
            y+=50
        elif self.o["mode"] == 5:
            _draw_text(surf, "N d'écart", FONT_MED, WHITE, topleft=(40,y))
            self.inf_n.rect.topleft=(260,y-6); self.inf_n.rect.size=(80,36); self.inf_n.draw(surf)
            self._draw_spinner(surf, self.inf_n, self.inf_n_up, self.inf_n_dn)
            y+=50
            _draw_text(surf, "Durée (secondes)", FONT_MED, WHITE, topleft=(40,y))
            self.duration.rect.topleft=(260,y-6); self.duration.rect.size=(100,36); self.duration.draw(surf)
            self._draw_spinner(surf, self.duration, self.duration_up, self.duration_dn)
            y+=50
            _draw_text(surf, "Tempo", FONT_MED, WHITE, topleft=(40,y))
            self.infspd_prev.rect.topleft=(260,y-6); self.infspd_prev.draw(surf)
            rect = pygame.Rect(300,y-6,160,40); draw_panel(surf, rect)
            _draw_text(surf, self.infspd_labels[self.infspd_idx], FONT_MED, WHITE, rect=rect, align="center")
            self.infspd_next.rect.topleft=(460,y-6); self.infspd_next.draw(surf)
            y+=50
        if self.o["mode"] != 5:
            _draw_text(surf, "Niveau (1 lent → 5 rapide)", FONT_MED, WHITE, topleft=(40,y))
            self.level.rect.topleft=(320,y-6); self.level.rect.size=(90,36); self.level.draw(surf)
            self._draw_spinner(surf, self.level, self.level_up, self.level_dn)
            y+=56
        else:
            self.level.rect.topleft=(-1000,-1000)
            self.level_up.rect.topleft=(-1000,-1000)
            self.level_dn.rect.topleft=(-1000,-1000)
            y+=56
        if self.o["mode"] not in (3,5):
            y = self._draw_section_header(surf, "Opérations", "ops", y)
            if self.section_open["ops"]:
                for cb in [self.chk_add,self.chk_sub,self.chk_mul,self.chk_div,self.chk_mix_ops]:
                    cb.rect.topleft=(40,y); cb.draw(surf); y+=34
                y+=6
            y = self._draw_section_header(surf, "Nombre d'opérandes (min..max)", "operands", y)
            if self.section_open["operands"]:
                _draw_text(surf, "min", FONT_MED, WHITE, topleft=(40,y)); self.min_ops.rect.topleft=(80,y-6); self.min_ops.rect.size=(80,36); self.min_ops.draw(surf)
                self._draw_spinner(surf, self.min_ops, self.min_ops_up, self.min_ops_dn)
                _draw_text(surf, "max", FONT_MED, WHITE, topleft=(180,y)); self.max_ops.rect.topleft=(220,y-6); self.max_ops.rect.size=(80,36); self.max_ops.draw(surf)
                self._draw_spinner(surf, self.max_ops, self.max_ops_up, self.max_ops_dn)
                y+=56
        if self.o["mode"] != 5:
            y = self._draw_section_header(surf, "Taille des nombres", "sizes", y)
            if self.section_open["sizes"]:
                for cb in [self.chk_u,self.chk_t,self.chk_h,self.chk_k,self.chk_10k,self.chk_100k,self.chk_mix_digits]:
                    cb.rect.topleft=(40,y); cb.draw(surf); y+=34
                y+=6
            y = self._draw_section_header(surf, "Contraintes & confort", "constraints", y)
            if self.section_open["constraints"]:
                if self.o["mode"] == 3:
                    for cb in [self.chk_pos, self.chk_neg, self.chk_onlyneg]:
                        cb.rect.topleft=(40,y); cb.draw(surf); y+=34
                    _draw_text(surf, "Temps max par question (0 = illimité)", FONT_MED, WHITE, topleft=(40,y))
                    self.q_timeout.rect.topleft=(420,y-6); self.q_timeout.rect.size=(100,36); self.q_timeout.draw(surf)
                    self._draw_spinner(surf, self.q_timeout, self.qtime_up, self.qtime_dn)
                    y+=60
                    _draw_text(surf, "Résultat ≤", FONT_MED, WHITE, topleft=(40,y))
                    self.max_result.rect.topleft=(180,y-6); self.max_result.rect.size=(100,36); self.max_result.draw(surf)
                    self._draw_spinner(surf, self.max_result, self.res_up, self.res_dn)
                    self.chk_limit_res.rect.topleft=(300,y); self.chk_limit_res.draw(surf)
                    y+=50
                else:
                    for cb in [self.chk_pos,self.chk_neg,self.chk_onlyneg,self.chk_div_int,self.chk_add_nc,self.chk_sub_nb,self.chk_par]:
                        cb.rect.topleft=(40,y); cb.draw(surf); y+=34
                    _draw_text(surf, "Limiter les tables de × jusqu'à", FONT_MED, WHITE, topleft=(40,y))
                    self.tables_max.rect.topleft=(360,y-6); self.tables_max.rect.size=(80,36); self.tables_max.draw(surf)
                    self._draw_spinner(surf, self.tables_max, self.tables_up, self.tables_dn)
                    self.chk_tables.rect.topleft=(460,y); self.chk_tables.draw(surf)
                    y+=50
                    _draw_text(surf, "Temps max par question (0 = illimité)", FONT_MED, WHITE, topleft=(40,y))
                    self.q_timeout.rect.topleft=(420,y-6); self.q_timeout.rect.size=(100,36); self.q_timeout.draw(surf)
                    self._draw_spinner(surf, self.q_timeout, self.qtime_up, self.qtime_dn)
                    y+=60
                    _draw_text(surf, "Résultat ≤", FONT_MED, WHITE, topleft=(40,y))
                    self.max_result.rect.topleft=(180,y-6); self.max_result.rect.size=(100,36); self.max_result.draw(surf)
                    self._draw_spinner(surf, self.max_result, self.res_up, self.res_dn)
                    self.chk_limit_res.rect.topleft=(300,y); self.chk_limit_res.draw(surf)
                    y+=50
                    self.chk_retry.rect.topleft=(40,y); self.chk_retry.draw(surf)
                    y+=40
        if self.o["mode"] == 4:
            self.chk_audio.checked = True
            self.chk_voice.checked = True
        y = self._draw_section_header(surf, "Audio & voix", "audio", y)
        if self.section_open["audio"]:
            self.chk_audio.rect.topleft=(40,y); self.chk_audio.draw(surf); y+=34
            _draw_text(surf, "Voix TTS", FONT_MED, WHITE, topleft=(40,y))
            self.voice_btn_prev.rect.topleft=(200,y-6); self.voice_btn_prev.draw(surf)
            vname = self.voice_entries[self.voice_idx]["label"]
            rect = pygame.Rect(240,y-6,360,40); draw_panel(surf, rect)
            _draw_text(surf, vname, FONT_MED, WHITE, rect=rect, align="center")
            self.voice_btn_next.rect.topleft=(604,y-6); self.voice_btn_next.draw(surf)
            y+=50
            self.chk_voice.rect.topleft=(40,y); self.chk_voice.draw(surf); y+=34
            _draw_text(surf, "Langue de dictée (STT)", FONT_MED, WHITE, topleft=(40,y))
            self.btn_stt_fr.selected = (self.stt_lang == "FR")
            self.btn_stt_en.selected = (self.stt_lang == "EN")
            self.btn_stt_fr.rect.topleft=(300,y-6); self.btn_stt_fr.draw(surf)
            self.btn_stt_en.rect.topleft=(390,y-6); self.btn_stt_en.draw(surf)
            y+=50
            if self.chk_audio.checked:
                self.chk_hide_expr.rect.topleft=(40,y); self.chk_hide_expr.draw(surf); y+=34
            else:
                self.chk_hide_expr.checked = False
            if self.o["mode"] != 4:
                self.chk_auto_submit.rect.topleft=(40,y); self.chk_auto_submit.draw(surf); y+=34
            y+=6
        y = self._draw_section_header(surf, "Musique", "music", y)
        if self.section_open["music"]:
            self.chk_music.rect.topleft=(40,y); self.chk_music.draw(surf)
            _draw_text(surf, "Volume musique %", FONT_MED, WHITE, topleft=(80,y+34))
            self.music_vol.rect.topleft=(260,y+28); self.music_vol.rect.size=(90,36); self.music_vol.draw(surf)
            self._draw_spinner(surf, self.music_vol, self.mvol_up, self.mvol_dn)
            y+=74
            self.chk_sfx.rect.topleft=(40,y); self.chk_sfx.draw(surf)
            _draw_text(surf, "Volume bruitages %", FONT_MED, WHITE, topleft=(80,y+34))
            self.sfx_vol.rect.topleft=(260,y+28); self.sfx_vol.rect.size=(90,36); self.sfx_vol.draw(surf)
            self._draw_spinner(surf, self.sfx_vol, self.svol_up, self.svol_dn)
            y+=74
        y = self._draw_section_header(surf, "Affichage", "display", y)
        if self.section_open["display"]:
            self.chk_fullscreen.rect.topleft=(40,y); self.chk_fullscreen.draw(surf); y+=34
            self.chk_center.rect.topleft=(40,y); self.chk_center.draw(surf); y+=34
            _draw_text(surf, "Décalage centrage", FONT_MED, WHITE, topleft=(80,y))
            self.center_off.rect.topleft=(260,y-6); self.center_off.rect.size=(90,36); self.center_off.draw(surf)
            self._draw_spinner(surf, self.center_off, self.center_up, self.center_dn)
            y+=50
            _draw_text(surf, "Taille police", FONT_MED, WHITE, topleft=(80,y))
            self.font_level.rect.topleft=(260,y-6); self.font_level.rect.size=(90,36); self.font_level.draw(surf)
            self._draw_spinner(surf, self.font_level, self.font_up, self.font_dn)
            y+=60
            self.chk_green_fx.rect.topleft=(40,y); self.chk_green_fx.draw(surf); y+=34
            _draw_text(surf, "Fond de jeu", FONT_MED, WHITE, topleft=(40,y))
            self.bg_prev.rect.topleft=(240,y-6); self.bg_prev.draw(surf)
            rect = pygame.Rect(280,y-6,260,40); draw_panel(surf, rect)
            _draw_text(surf, self.bg_styles[self.bg_idx], FONT_MED, WHITE, rect=rect, align="center")
            self.bg_next.rect.topleft=(544,y-6); self.bg_next.draw(surf)
            y+=60

        # calc hauteur
        self._content_h = (y - (y0 - self.scroll)) + 20
        surf.set_clip(prev)
        # scroll bar
        if self._content_h > viewport.h:
            bar=pygame.Rect(w-10, viewport.y+8, 6, viewport.h-16); pygame.draw.rect(surf,(60,60,70),bar)
            ratio = viewport.h / self._content_h; handle_h = max(30, int(bar.h*ratio))
            max_scroll = max(1, self._content_h - viewport.h)
            pos_ratio = self.scroll / max_scroll; handle_y = int(bar.y + pos_ratio*(bar.h-handle_h))
            pygame.draw.rect(surf, ORANGE, (bar.x, clamp(handle_y, bar.y, bar.bottom-handle_h), bar.w, handle_h))
        # bas
        self.btn_save.rect = pygame.Rect(w-480, h-64, 200, 44); self.btn_save.draw(surf)
        self.btn_back.rect = pygame.Rect(w-260, h-64, 200, 44); self.btn_back.draw(surf)
        if self.edit_profile_mode:
            overlay = pygame.Surface((w,h), pygame.SRCALPHA)
            overlay.fill((0,0,0,160)); surf.blit(overlay,(0,0))
            panel = pygame.Rect(w//2-220, h//2-80, 440, 160)
            pygame.draw.rect(surf,(30,30,34),panel,border_radius=8)
            title = "Nouveau profil" if self.edit_profile_mode=="new" else "Renommer profil"
            _draw_text(surf, title, FONT_BIG, WHITE, center=(panel.centerx, panel.y+30))
            self.prof_input.rect = pygame.Rect(panel.x+20, panel.y+60, panel.w-40,40); self.prof_input.draw(surf)
            self.prof_ok.rect = pygame.Rect(panel.x+40, panel.bottom-50,120,36); self.prof_ok.draw(surf)
            self.prof_cancel.rect = pygame.Rect(panel.right-160, panel.bottom-50,120,36); self.prof_cancel.draw(surf)

class GameScene(Scene):
    def __init__(self, app):
        self.app = app
        self.app.play_bgm("game", restart=False)
        sfx_play("start")
        self.o = app.options.copy()
        self.mode = self.o["mode"]
        if self.mode == 5:
            self.gen = None
        else:
            self.gen = MathGenerator(self.o)
        if self.mode == 4:
            self.o["audio_mode"] = True
            self.o["voice_answer"] = True
        placeholder = "" if self.mode == 3 else "Votre réponse (Entrée / X pour valider)"
        self.input = TextInput((0,0,0,0), text="", placeholder=placeholder,
                               numeric_only=True, maxlen=16, font=FONT_HUGE,
                               centered=self.o.get("center_text", False))
        self.records = []  # {expr, answer, typed, correct, t}
        self.current_expr = None; self.current_answer = None
        self.timer_total = float(self.o["duration_sec"]) if self.mode in (1,5) else 0.0
        self.timer_q = float(self.o.get("per_question_timeout",0)) if self.o.get("per_question_timeout",0)>0 else 0.0
        self.start_time = time.perf_counter()
        self.running = True
        self.num_target = int(self.o["num_problems"]) if self.mode in (2,4) else (int(self.o.get("flash_series",10)) if self.mode==3 else 0)
        self.flash_count = int(self.o.get("flash_numbers", self.o.get("flash_additions",5))) if self.mode==3 else 0
        self.answered = 0
        self.scroll = 0.0; self._content_h=0
        self._last_expr_time = time.perf_counter()
        self.voice_id = self.o.get("voice_choice_id")
        model = "vosk-model-small-fr" if self.o.get("stt_lang","FR") == "FR" else "vosk-model-small-en-us"
        self.stt = STT(model_dir=model)
        self._ptt = False
        self._stt_result = None
        self.audio_silence_delay = float(self.o.get("audio_stt_delay",0.6))
        self.audio_tts_overlap = float(self.o.get("audio_tts_overlap",1.2))
        self._audio_wait_tts = False
        self._audio_speech_started = False
        self._audio_last_speech = 0.0
        self._audio_last_partial = ""
        self.auto_submit = bool(self.o.get("auto_submit")) and self.mode != 4 and self.mode != 5
        self.auto_submit_delay = float(self.o.get("auto_submit_delay", 2.0))
        self._last_key_time = None
        self._tts_start_time = 0.0
        self._tts_duration = 0.0
        self.shake_time = 0.0
        self.shake_phase = 0.0
        self.shake_duration = 0.5
        self.pending_action = None
        self.pulse_time = 0.0
        self.pulse_duration = 0.25
        self.streak = 0
        self.particles = []
        self.ptt_pulse = 0.0
        self.expr_pos = (0, 0)
        self.halo_timer = 0.0       # temps restant du halo
        self.halo_duration = 0.0    # durée totale du halo
        self.halo_phase = 0.0       # temps cumulé pour le balayage
        self.halo_color = (60,170,90)
        self.bloom_timer = 0.0      # flash très bref du cadre
        self.bar_shimmer_duration = 0.3
        self.bar_shimmer_timer = 0.0
        self.audio_icon_phase = 0.0
        if self.mode == 5:
            self.n_back = int(self.o.get("infernal_n",3))
            self.inf_interval = {0:3.5,1:2.6,2:1.8}.get(int(self.o.get("infernal_speed",1)),2.6)
            self.problems = []
            self.target_idx = -1
            self._tick_timer = 0.0
            self.input.active = False
            self.input.centered = True
            self.flash_countdown = 3
            self.flash_countdown_timer = 1.0
            self.flash_anim = 0.0
            self.current_expr = str(self.flash_countdown)
            sfx_play("ding")
        w, h = screen.get_size()
        self.parallax = []
        for i, spd in enumerate((8, 16, 24, 32)):
            layer = []
            for _ in range(12):
                txt = random.choice("0123456789+-×÷")
                img = FONT_LG.render(txt, True, WHITE)
                img.set_alpha(max(10, 40 - i * 8))
                layer.append({"img": img, "x": random.uniform(0, w), "y": random.uniform(0, h), "speed": spd})
            self.parallax.append(layer)
        self.bg_zoom_phase = 0.0
        self.bg_style = int(self.o.get("game_bg_style", 0))
        self.timer_total_max = self.timer_total
        self.combo_freeze = 0.0
        self.combo_popup = None
        self.fragments = []
        self.orb_timer = 0.0
        self._pending_combo = None

        # --- TTS pré-calculé pour enchaîner sans latence ---
        self._tts_channel = None
        self._tts_sound = None
        self._tts_tmpdir = None
        self._next_expr = None
        self._next_answer = None
        self._next_sound = None
        self._next_tmpdir = None
        self.flash_numbers = []
        self.flash_sounds = []
        self.flash_index = 0
        self.flashing = False
        self.flash_timer = 0.0
        self.flash_interval = {1:3.0,2:2.0,3:1.0,4:0.7,5:0.5}.get(int(self.o.get("level",3)),1.0)
        if self.mode != 5:
            self.flash_countdown = 0
            self.flash_countdown_timer = 0.0
            self.flash_anim = 0.0
        self._next_flash_numbers = None
        self._next_sound_seq = None
        if self.mode != 5:
            self._prepare_next_problem()
            self.next_problem()

    def _tts_stop(self):
        try:
            if self._tts_channel:
                self._tts_channel.stop()
        except Exception:
            pass
        self._tts_channel = None

    def _tts_cleanup(self):
        self._tts_stop()
        try:
            if self._tts_tmpdir and os.path.isdir(self._tts_tmpdir):
                shutil.rmtree(self._tts_tmpdir, ignore_errors=True)
        except Exception:
            pass
        self._tts_sound = None
        self.flash_sounds = []
        self._tts_tmpdir = None

    def _prepare_next_problem(self):
        if self.mode == 3:
            nums, ans = self.gen.make_flash_numbers(self.flash_count)
            snds = []
            tmpdir = None
            if self.o.get("audio_mode") and pyttsx3 is not None:
                try:
                    engine = pyttsx3.init()
                    if self.voice_id:
                        try:
                            engine.setProperty("voice", self.voice_id)
                        except Exception:
                            pass
                    tmpdir = tempfile.mkdtemp(prefix="cm_tts_")
                    for i,n in enumerate(nums):
                        engine.save_to_file(str(n), os.path.join(tmpdir, f"{i}.wav"))
                    engine.runAndWait()
                    if not pygame.mixer.get_init():
                        pygame.mixer.init()
                    for i in range(len(nums)):
                        try:
                            snds.append(pygame.mixer.Sound(os.path.join(tmpdir, f"{i}.wav")))
                        except Exception:
                            snds.append(None)
                except Exception:
                    snds = []
                    if tmpdir:
                        shutil.rmtree(tmpdir, ignore_errors=True)
                        tmpdir = None
            self._next_flash_numbers = nums
            self._next_answer = ans
            self._next_sound_seq = snds
            self._next_tmpdir = tmpdir
        else:
            expr, ans = self.gen.make_problem()
            snd = None
            tmpdir = None
            if self.o.get("audio_mode") and pyttsx3 is not None:
                try:
                    engine = pyttsx3.init()
                    if self.voice_id:
                        try:
                            engine.setProperty("voice", self.voice_id)
                        except Exception:
                            pass
                    cleaned = expr.replace("−", " moins ").replace("-", " moins ")
                    cleaned = re.sub(r"\s+", " ", cleaned).strip()
                    tmpdir = tempfile.mkdtemp(prefix="cm_tts_")
                    path = os.path.join(tmpdir, "q.wav")
                    engine.save_to_file(cleaned, path)
                    engine.runAndWait()
                    if not pygame.mixer.get_init():
                        pygame.mixer.init()
                    snd = pygame.mixer.Sound(path)
                except Exception:
                    snd = None
                    if tmpdir:
                        shutil.rmtree(tmpdir, ignore_errors=True)
                        tmpdir = None
            self._next_expr = expr
            self._next_answer = ans
            self._next_sound = snd
            self._next_tmpdir = tmpdir

    def next_problem(self):
        self.shake_time = 0.0
        self.pending_action = None
        self._tts_cleanup()
        if self._ptt:
            try:
                self.stt.stop_and_get_text()
            except Exception:
                pass
            self._ptt = False
        if self.mode == 3:
            if getattr(self, "_next_flash_numbers", None) is None:
                self._prepare_next_problem()
            self.flash_numbers = self._next_flash_numbers or []
            self.current_answer = self._next_answer
            self.flash_sounds = self._next_sound_seq or []
            self._tts_tmpdir = self._next_tmpdir
            self._next_flash_numbers = None
            self._next_sound_seq = None
            self._next_tmpdir = None
            self.flash_index = 0
            self.flashing = False
            self.flash_timer = 0.0
            self.flash_countdown = 3
            self.flash_countdown_timer = 1.0
            self.flash_anim = 0.0
            self.current_expr = str(self.flash_countdown)
            sfx_play("ding")
            self.input.text = ""; self.input.caret = 0; self.input.scroll_x=0; self.input.active=False
            self._last_expr_time = time.perf_counter()
            if self.o.get("per_question_timeout",0)>0:
                self.timer_q = float(self.o["per_question_timeout"])
            self._prepare_next_problem()
        else:
            if self._next_expr is None:
                self._prepare_next_problem()
            self.current_expr = self._next_expr
            self.current_answer = self._next_answer
            self._tts_sound = self._next_sound
            self._tts_tmpdir = self._next_tmpdir
            self._next_expr = self._next_answer = None
            self._next_sound = None
            self._next_tmpdir = None
            self.input.text = ""; self.input.caret = 0; self.input.scroll_x=0; self.input.active=True
            if self.o.get("per_question_timeout",0)>0:
                self.timer_q = float(self.o["per_question_timeout"])
            if self.o.get("audio_mode") and self._tts_sound:
                ch = pygame.mixer.find_channel()
                if ch:
                    ch.stop(); ch.play(self._tts_sound); self._tts_channel = ch
                self._tts_start_time = time.perf_counter()
                try:
                    self._tts_duration = self._tts_sound.get_length()
                except Exception:
                    self._tts_duration = 0.0
                if self.mode == 4:
                    self._audio_wait_tts = True
                    self._last_expr_time = self._tts_start_time + self._tts_duration
                else:
                    self._last_expr_time = self._tts_start_time
            else:
                self._last_expr_time = time.perf_counter()
                if self.mode == 4:
                    if self.stt.start():
                        self._ptt = True
                        self._audio_speech_started = False
                        self._audio_last_speech = self._last_expr_time
            self._prepare_next_problem()

    def _infernal_generate(self):
        a = random.randint(0,9)
        b = random.randint(0,9)
        if random.random() < 0.5:
            expr = f"{a} + {b}"
            ans = a + b
        else:
            if a < b:
                a, b = b, a
            expr = f"{a} - {b}"
            ans = a - b
        return expr, ans

    def _infernal_next_problem(self):
        if self.target_idx >= 0 and self.target_idx < len(self.problems):
            tgt = self.problems[self.target_idx]
            if not tgt.get("answered"):
                self.submit()
        expr, ans = self._infernal_generate()
        self.problems.append({"expr": expr, "answer": ans, "answered": False})
        self.current_expr = f"{expr} = ?"
        self._tick_timer = self.inf_interval
        self._tts_cleanup()
        if self.o.get("audio_mode") and pyttsx3 is not None:
            tmpdir = None
            try:
                engine = pyttsx3.init()
                if self.voice_id:
                    try:
                        engine.setProperty("voice", self.voice_id)
                    except Exception:
                        pass
                cleaned = expr.replace("−", " moins ").replace("-", " moins ")
                cleaned = cleaned.replace("+", " plus ")
                cleaned = re.sub(r"\s+", " ", cleaned).strip()
                tmpdir = tempfile.mkdtemp(prefix="cm_tts_")
                wav = os.path.join(tmpdir, "q.wav")
                engine.save_to_file(cleaned, wav)
                engine.runAndWait()
                if not pygame.mixer.get_init():
                    pygame.mixer.init()
                snd = pygame.mixer.Sound(wav)
                ch = pygame.mixer.find_channel()
                if ch:
                    ch.stop(); ch.play(snd)
                    self._tts_channel = ch
                    self._tts_sound = snd
                    self._tts_start_time = time.perf_counter()
                    try:
                        self._tts_duration = snd.get_length()
                    except Exception:
                        self._tts_duration = 0.0
                    self._tts_tmpdir = tmpdir
                    self._last_expr_time = self._tts_start_time
                else:
                    self._last_expr_time = time.perf_counter()
            except Exception:
                if tmpdir:
                    shutil.rmtree(tmpdir, ignore_errors=True)
                self._tts_channel = None
                self._tts_sound = None
                self._tts_tmpdir = None
                self._last_expr_time = time.perf_counter()
        else:
            self._last_expr_time = time.perf_counter()
        self.target_idx = len(self.problems) - self.n_back - 1
        if self.target_idx >= 0:
            self.input.active = True
            self.input.text = ""
            self.input.caret = 0
        else:
            self.input.active = False
        sfx_play("step")

    def submit(self, forced=False):
        self._last_key_time = None
        self._tts_stop()
        if self.mode == 5:
            if self.target_idx < 0 or self.target_idx >= len(self.problems):
                return
            tgt = self.problems[self.target_idx]
            typed = self.input.text.strip()
            tnow = time.perf_counter(); dt = tnow - self._last_expr_time
            skipped = (typed == "")
            ok = (not skipped and self.safe_int(typed) == tgt["answer"])
            outcome = "error" if skipped else ("correct" if ok else "error")
            self.records.append({
                "expr": tgt["expr"],
                "answer": tgt["answer"],
                "typed": typed,
                "correct": bool(ok),
                "t": dt,
            })
            self.answered += 1
            tgt["answered"] = True
            self.input.text = ""
            sfx_play(outcome)
            if ok:
                self.streak += 1
                if self.o.get("green_fx", True):
                    self.pulse_time = self.pulse_duration
                    self.halo_duration = 0.8
                    self.halo_timer = self.halo_duration
                    self.bloom_timer = 0.15
                    self.bar_shimmer_timer = self.bar_shimmer_duration
                    if random.random() < 0.1:
                        self.orb_timer = 1.0
                    if self.streak in (10, 20, 50):
                        self.combo_freeze = 0.2
                        self._pending_combo = self.streak
                    if self.streak and self.streak % 5 == 0:
                        self.halo_duration = 1.1
                        self.halo_timer = self.halo_duration
                    if self.streak % 5 == 0:
                        cx, cy = self.expr_pos
                        ops = ["+","-","×","÷"]
                        for _ in range(20):
                            self.particles.append({
                                "x": cx,
                                "y": cy,
                                "vx": random.uniform(-2, 2),
                                "vy": random.uniform(-4, -1),
                                "life": 400,
                                "surf": FONT_MED.render(random.choice(ops), True, (60,170,90)),
                            })
            else:
                self.streak = 0
                self.shake_time = self.shake_duration
                self.shake_phase = 0.0
            if self.timer_total <= 0:
                self.target_idx += 1
                if self.target_idx >= len(self.problems):
                    self.finish()
            return
        typed = self.input.text.strip()
        tnow = time.perf_counter(); dt = tnow - self._last_expr_time
        skipped = (typed == "")
        ok = (not skipped and self.safe_int(typed) == self.current_answer)
        outcome = "step" if skipped else ("correct" if ok else "error")
        self.records.append({
            "expr": self.current_expr,
            "answer": int(self.current_answer),
            "typed": typed,
            "correct": bool(ok),
            "t": dt,
        })
        advance = ok or not self.o.get("retry_until_correct")
        if advance:
            self.answered += 1 if self.mode==1 else 1
            self.timer_q = 0.0
        else:
            self._last_expr_time = tnow
        self.input.text = ""
        finish_pending = False
        if advance:
            finish_pending = (self.mode in (2,3,4) and self.answered >= self.num_target) or (self.mode == 1 and self.timer_total <= 0)
        sfx_play(outcome)
        if ok:
            self.streak += 1
            if self.o.get("green_fx", True):
                self.pulse_time = self.pulse_duration
                self.halo_duration = 0.8
                self.halo_timer = self.halo_duration
                self.bloom_timer = 0.15
                self.bar_shimmer_timer = self.bar_shimmer_duration
                if random.random() < 0.1:
                    self.orb_timer = 1.0
                if self.streak in (10, 20, 50):
                    self.combo_freeze = 0.2
                    self._pending_combo = self.streak
                if self.streak and self.streak % 5 == 0:
                    self.halo_duration = 1.1
                    self.halo_timer = self.halo_duration
                if self.streak % 5 == 0:
                    cx, cy = self.expr_pos
                    ops = ["+","-","×","÷"]
                    for _ in range(20):
                        self.particles.append({
                            "x": cx,
                            "y": cy,
                            "vx": random.uniform(-2, 2),
                            "vy": random.uniform(-4, -1),
                            "life": 400,
                            "surf": FONT_MED.render(random.choice(ops), True, (60,170,90)),
                        })
            if finish_pending:
                self.finish()
            else:
                self.next_problem()
        else:
            self.streak = 0
            self.shake_time = self.shake_duration
            self.shake_phase = 0.0
            if advance:
                self.pending_action = "finish" if finish_pending else "next"
            else:
                self.pending_action = None

    def safe_int(self, s):
        try: return int(s)
        except: return None

    def handle(self, ev):
        if ev.type == pygame.KEYDOWN:
            if ev.key == pygame.K_ESCAPE:
                if self._ptt:
                    try:
                        threading.Thread(target=self.stt.stop_and_get_text, daemon=True).start()
                    except Exception:
                        pass
                    self._ptt = False
                self._tts_cleanup()
                if self._next_tmpdir:
                    try:
                        shutil.rmtree(self._next_tmpdir, ignore_errors=True)
                    except Exception:
                        pass
                    self._next_tmpdir = None
                self.app._suppress_next_back_sfx = False
                self.app.goto(MainMenu(self.app)); return
            if self.shake_time <= 0:
                if not self.flashing and ev.key in (pygame.K_RETURN, pygame.K_x):
                    if self.mode == 5:
                        if self.target_idx >= 0 and self.target_idx < len(self.problems):
                            self.submit()
                        if self.timer_total > 0:
                            self._infernal_next_problem()
                    else:
                        self.submit()
                    return
                if ev.key == pygame.K_q:
                    if self.o.get("audio_mode"):
                        if self.mode == 3 and self.flash_sounds and self.flash_index>0:
                            ch = pygame.mixer.find_channel()
                            snd = self.flash_sounds[self.flash_index-1]
                            if ch and snd:
                                ch.play(snd)
                        elif self._tts_sound:
                            self._tts_stop()
                            ch = pygame.mixer.find_channel()
                            if ch:
                                ch.play(self._tts_sound)
                                self._tts_channel = ch
                    return
        if self.shake_time>0:
            return
        w,h = screen.get_size(); top=70; viewport_h = max(0, h-top-20)
        if ev.type == pygame.MOUSEWHEEL:
            max_scroll = max(0, self._content_h - viewport_h)
            self.scroll -= ev.y * 36; self.scroll = clamp(self.scroll, 0, max_scroll)
        self.input.handle(ev)
        if self.auto_submit and ev.type == pygame.KEYDOWN:
            if ev.unicode and ev.unicode.isdigit():
                self._last_key_time = time.perf_counter()
            elif ev.key in (pygame.K_BACKSPACE, pygame.K_DELETE):
                self._last_key_time = time.perf_counter()
        if self.o.get("voice_answer") and self.stt.available and self.mode != 4:
            if ev.type == pygame.KEYDOWN and ev.key == pygame.K_LCTRL and not self._ptt:
                if self.stt.start():
                    self._ptt = True
            elif ev.type == pygame.KEYUP and ev.key == pygame.K_LCTRL and self._ptt:
                self._ptt = False
                def _proc():
                    txt = self.stt.stop_and_get_text()
                    num = stt_extract_number(txt, self.o.get("stt_lang", "FR"))
                    if num:
                        self._stt_result = num
                threading.Thread(target=_proc, daemon=True).start()

    def update(self, dt):
        real_dt = dt
        if self.combo_freeze > 0:
            self.combo_freeze = max(0.0, self.combo_freeze - real_dt)
            if self.combo_freeze <= 0 and self._pending_combo is not None:
                val = self._pending_combo
                w, h = screen.get_size()
                self.combo_popup = {"text": str(val), "timer": 1.0}
                self.fragments = []
                for _ in range(40):
                    ang = random.uniform(0, math.tau)
                    sp = random.uniform(120, 260)
                    self.fragments.append({
                        "x": w / 2,
                        "y": h / 2,
                        "vx": math.cos(ang) * sp,
                        "vy": math.sin(ang) * sp,
                        "timer": 1.0,
                    })
                self._pending_combo = None
            dt = 0.0

        self.bg_zoom_phase += real_dt
        w, h = screen.get_size()
        for layer in self.parallax:
            for item in layer:
                item["x"] += item["speed"] * real_dt * 0.1
                if item["x"] > w + 50:
                    item["x"] = -50
        if self.orb_timer > 0:
            self.orb_timer = max(0.0, self.orb_timer - real_dt)
        if self.combo_popup:
            self.combo_popup["timer"] -= real_dt
            if self.combo_popup["timer"] <= 0:
                self.combo_popup = None
        for f in self.fragments:
            f["x"] += f["vx"] * real_dt
            f["y"] += f["vy"] * real_dt
            f["vy"] += 60 * real_dt
            f["timer"] -= real_dt
        self.fragments = [f for f in self.fragments if f["timer"] > 0]
        if self.halo_timer > 0:
            self.halo_timer = max(0.0, self.halo_timer - dt)
            self.halo_phase += dt
        if self.bloom_timer > 0:
            self.bloom_timer = max(0.0, self.bloom_timer - dt)
        if self.bar_shimmer_timer > 0:
            self.bar_shimmer_timer = max(0.0, self.bar_shimmer_timer - dt)
        self.audio_icon_phase += real_dt
        if not self.running:
            return
        if self.pulse_time > 0:
            self.pulse_time -= dt
        for p in self.particles:
            p["x"] += p["vx"]
            p["y"] += p["vy"]
            p["vy"] += 0.12
            p["life"] -= dt * 1000
        self.particles = [p for p in self.particles if p["life"] > 0]
        if self._ptt:
            self.ptt_pulse += dt
        else:
            self.ptt_pulse = 0.0
        if self.shake_time > 0:
            self.shake_time -= dt
            self.shake_phase += dt * 40
            if self.shake_time <= 0 and self.pending_action:
                act = self.pending_action
                self.pending_action = None
                if act == "next":
                    self.next_problem()
                elif act == "finish":
                    self.finish()
        if self.shake_time <= 0 and self.mode == 4:
            if self._audio_wait_tts:
                now = time.perf_counter()
                ready = True
                if self._tts_channel and self._tts_channel.get_busy():
                    if now < self._tts_start_time + self._tts_duration - self.audio_tts_overlap:
                        ready = False
                if ready:
                    self._audio_wait_tts = False
                    if self.stt.start():
                        self._ptt = True
                        self._audio_speech_started = False
                        self._audio_last_speech = time.perf_counter()
            elif self._ptt:
                self.stt.feed()
                partial = ""
                if self.stt.rec and _json:
                    try:
                        partial = _json.loads(self.stt.rec.PartialResult()).get("partial", "").strip()
                    except Exception:
                        partial = ""
                if partial != self._audio_last_partial:
                    if partial:
                        self._audio_speech_started = True
                        self._audio_last_speech = time.perf_counter()
                    self._audio_last_partial = partial
                if self._audio_speech_started and time.perf_counter() - self._audio_last_speech > self.audio_silence_delay:
                    self._ptt = False
                    self._audio_last_partial = ""
                    def _proc():
                        txt = self.stt.stop_and_get_text()
                        num = stt_extract_number(txt, self.o.get("stt_lang", "FR"))
                        if num:
                            self.input.text = num
                            self.input.caret = len(self.input.text)
                            self.submit()
                        else:
                            if self.stt.start():
                                self._ptt = True
                                self._audio_speech_started = False
                                self._audio_last_speech = time.perf_counter()
                    threading.Thread(target=_proc, daemon=True).start()
        elif self.shake_time <= 0:
            if self._ptt:
                self.stt.feed()
            if self._stt_result:
                self.input.text = self._stt_result
                self.input.caret = len(self.input.text)
                self._stt_result = None
                if self.auto_submit:
                    self.submit()
                else:
                    self._last_key_time = time.perf_counter()
            if self.auto_submit and not self._ptt:
                if self.input.text and self._last_key_time and time.perf_counter() - self._last_key_time >= self.auto_submit_delay:
                    self.submit()
        if self.mode == 5:
            if self.flash_countdown > 0:
                self.flash_countdown_timer -= dt
                self.flash_anim += dt
                if self.flash_countdown_timer <= 0:
                    self.flash_countdown -= 1
                    if self.flash_countdown > 0:
                        self.current_expr = str(self.flash_countdown)
                        self.flash_countdown_timer = 1.0
                        self.flash_anim = 0.0
                        sfx_play("ding")
                    else:
                        self._infernal_next_problem()
                return            
            if not (self._ptt or self._audio_wait_tts):
                self._tick_timer -= dt
            if self.timer_total > 0 and self._tick_timer <= 0:
                self._infernal_next_problem()
            if self.timer_total_max > 0 and self.timer_total > 0:
                self.timer_total -= dt
                if self.timer_total <= 0:
                    self.timer_total = 0
                    self.current_expr = ""
                    self._tick_timer = float("inf")
                    if self.target_idx < 0 and self.problems:
                        self.target_idx = 0
                    if self.target_idx >= 0:
                        self.input.active = True
            if self.timer_total <= 0 and self.target_idx >= len(self.problems):
                self.finish()
            return
        if self.mode == 3:
            if self.flash_countdown > 0:
                self.flash_countdown_timer -= dt
                self.flash_anim += dt
                if self.flash_countdown_timer <= 0:
                    self.flash_countdown -= 1
                    if self.flash_countdown > 0:
                        self.current_expr = str(self.flash_countdown)
                        self.flash_countdown_timer = 1.0
                        self.flash_anim = 0.0
                        sfx_play("ding")
                    else:
                        self.flashing = True
                        self.flash_timer = 0.0
            elif self.flashing:
                self.flash_timer -= dt
                if self.flash_timer <= 0:
                    if self.flash_index < len(self.flash_numbers):
                        num = self.flash_numbers[self.flash_index]
                        self.current_expr = str(num)
                        sfx_play("anzan")
                        if self.o.get("audio_mode") and self.flash_sounds and self.flash_index < len(self.flash_sounds):
                            ch = pygame.mixer.find_channel()
                            snd = self.flash_sounds[self.flash_index]
                            if ch and snd:
                                ch.play(snd)
                        self.flash_index += 1
                        self.flash_timer = self.flash_interval
                    else:
                        self.flashing = False
                        self.current_expr = "?"
                        self.input.active = True
        if self.mode == 1:
            self.timer_total -= dt
            if self.timer_total <= 0:  # soumet la dernière en cours (si vide → faux)
                self.submit(forced=True); self.finish(); return
        if self.o.get("per_question_timeout",0)>0 and self.timer_q>0:
            self.timer_q -= dt
            if self.timer_q <= 0:
                self.submit(forced=True)

    def finish(self):
        self.running=False
        self._tts_cleanup()
        if self._next_tmpdir:
            try:
                shutil.rmtree(self._next_tmpdir, ignore_errors=True)
            except Exception:
                pass
            self._next_tmpdir = None
        # stats
        total = len(self.records)
        correct = sum(1 for r in self.records if r["correct"]) if total>0 else 0
        acc = (correct/total) if total>0 else 0.0
        avg_t = (sum(r["t"] for r in self.records)/total) if total>0 else 0.0
        elapsed = (time.perf_counter() - self.start_time)
        # score simple tenant compte de niveau, précision et volume
        score = int( 1000*acc + 10*correct + 20*self.o.get("level",3) - 5*avg_t )
        entry = {
            "date": now_iso(),
            "mode": self.mode,
            "level": self.o.get("level",3),
            "duration": int(self.o["duration_sec"]) if self.mode == 1 else int(elapsed),
            "num_problems": total,
            "correct": correct,
            "accuracy": round(acc,3),
            "avg_time": round(avg_t,2),
            "score": max(0, score),
            "ops": "+"*(self.o.get("op_add",0)) + "-"*(self.o.get("op_sub",0)) + "*"*(self.o.get("op_mul",0)) + "/"*(self.o.get("op_div",0)),
        }
        if self.mode == 3:
            entry["flash_numbers"] = self.flash_count
            entry["flash_series"] = self.num_target
        if self.mode == 5:
            entry["n_back"] = self.n_back
            entry["speed"] = int(self.o.get("infernal_speed",1))
        self.app.scores.add_session(entry)
        sfx_play("end")
        self.app.goto(EndScene(self.app, self, entry))

    def draw(self, surf):
        w,h = surf.get_size()
        if self.bg_style == 0:
            c = int(26 + 40 * (0.5 + 0.5 * math.sin(self.bg_zoom_phase * 0.2)))
            surf.fill((20,22,c))
        else:
            surf.fill((20,22,26))
        if self.bg_style != 2:
            zoom = 1.0 + 0.03 * math.sin((self.bg_zoom_phase % 8.0) / 8.0 * math.tau)
            for layer in self.parallax:
                for it in layer:
                    x = (it["x"] - w/2) * zoom + w/2
                    y = (it["y"] - h/2) * zoom + h/2
                    surf.blit(it["img"], (x, y), special_flags=pygame.BLEND_ADD)
        top = pygame.Rect(0,0,w,70); pygame.draw.rect(surf,(35,37,42), top)
        if self.mode==1:
            _draw_text(surf, f"Mode: Contre-la-montre   Temps restant: {max(0.0,self.timer_total):.1f}s", FONT_MED, ORANGE, topleft=(16,20))
        elif self.mode==3:
            _draw_text(surf, f"Mode: Flash Anzan   Série: {self.answered}/{self.num_target}", FONT_MED, ORANGE, topleft=(16,20))
        elif self.mode==4:
            _draw_text(surf, f"Mode: Audio   Progrès: {self.answered}/{self.num_target}", FONT_MED, ORANGE, topleft=(16,20))
        elif self.mode==5:
            _draw_text(surf, f"{self.n_back} d'écart", FONT_MED, ORANGE, topleft=(16,20))
            txt = f"Temps: {int(max(0,self.timer_total))} s"
            tw,_ = FONT_MED.size(txt)
            _draw_text(surf, txt, FONT_MED, ORANGE, topleft=(w-16-tw,20))
        else:
            _draw_text(surf, f"Mode: Série   Progrès: {self.answered}/{self.num_target}", FONT_MED, ORANGE, topleft=(16,20))
        if self.o.get("voice_answer") and self.stt.available and self._ptt:
            mic = pygame.Rect(w-260, 16, 160, 36)
            pygame.draw.rect(surf, (15,15,18), mic, border_radius=10)
            pulse = (math.sin(self.ptt_pulse * 6) + 1) / 2
            radius = 6 + 2 * pulse
            alpha = 150 + int(105 * pulse)
            dot = pygame.Surface((int(radius * 2), int(radius * 2)), pygame.SRCALPHA)
            pygame.draw.circle(dot, (RED[0], RED[1], RED[2], alpha), (int(radius), int(radius)), int(radius))
            surf.blit(dot, (mic.x + 18 - int(radius), mic.centery - int(radius)))
            _draw_text(surf, "PARLEZ", FONT_MED, ORANGE, topleft=(mic.x+36, mic.y+6))
        if self.flash_countdown > 0 and self.mode in (3,5):
            num = str(self.flash_countdown)
            base = FONT_HUGE.render(num, True, ORANGE)
            prog = min(1.0, self.flash_anim)
            scale = 1.0 + 10.0 * (1.0 - prog)
            sized = pygame.transform.rotozoom(base, 0, scale)
            sized.set_alpha(int(255 * (1.0 - prog)))
            rect = sized.get_rect(center=(w//2, h//2))
            surf.blit(sized, rect)
            return
        if self.mode == 5:
            expr = self.current_expr
            if self.o.get("audio_mode") and self.o.get("audio_hide_problem"):
                expr = f"Calcul N°{len(self.problems)}"
            offset_x = 0
            if self.shake_time > 0:
                amp = 10 * (self.shake_time / self.shake_duration)
                offset_x = int(math.sin(self.shake_phase) * amp)
            expr_surf = FONT_HUGE.render(expr, True, WHITE)
            lbl = "???? ="
            lbl_surf = FONT_HUGE.render(lbl, True, WHITE)
            if self.target_idx >= 0:
                box_w = max(expr_surf.get_width(), lbl_surf.get_width() + 200) + 80
            else:
                box_w = expr_surf.get_width() + 80
            box_h = expr_surf.get_height() + 40
            top_band = 70
            viewport_h = max(0, h - top_band - 20)
            center_y = h//2
            if self.app.options.get("center_text"):
                co = clamp(int(self.app.options.get("center_offset",35)),0,100)
                center_y = top_band + int(co/100.0 * viewport_h)
            top_rect = pygame.Rect(0, 0, box_w, box_h)
            if self.target_idx >= 0:
                top_rect.center = (w//2 + offset_x, center_y - 70)
            else:
                top_rect.center = (w//2 + offset_x, center_y)
            bottom_rect = pygame.Rect(0, 0, box_w, box_h)
            bottom_rect.center = (w//2, center_y + 70)
            if expr:
                pygame.draw.rect(surf, (35,37,42), top_rect, border_radius=12)
                pygame.draw.rect(surf, (60,62,66), top_rect, 2, border_radius=12)
                disp = expr_surf
                if self.pulse_time > 0:
                    prog = 1 - self.pulse_time / self.pulse_duration
                    scale = 1 + 0.08 * (1 - abs(1 - 2 * prog))
                    disp = pygame.transform.rotozoom(disp, 0, scale)
                rect = disp.get_rect(center=top_rect.center)
                surf.blit(disp, rect)
                self.expr_pos = rect.center
                idx_curr = len(self.problems)
                _draw_text(surf, str(idx_curr), FONT_BIG, ORANGE, midleft=(top_rect.x - 40, top_rect.centery))
                if self.bloom_timer > 0:
                    t = self.bloom_timer / 0.15
                    ov = pygame.Surface((top_rect.w, top_rect.h), pygame.SRCALPHA)
                    pygame.draw.rect(ov, (*self.halo_color, int(180 * t)), ov.get_rect(), border_radius=12)
                    surf.blit(ov, top_rect.topleft, special_flags=pygame.BLEND_ADD)
                if self.halo_timer > 0:
                    elapsed = self.halo_duration - self.halo_timer
                    fade = 0.80
                    fade_in = ease_out_cubic(min(1.0, elapsed / fade))
                    fade_out = min(1.0, self.halo_timer / fade) ** 3
                    strength = fade_in * fade_out
                    draw_neon_sweep_rect(
                        surf, top_rect, base_color=self.halo_color, radius=12,
                        core_w=3, glow=14, sweep_t=self.halo_phase, sweep_speed=1400.0,
                        sweep_len=max(180, top_rect.w * 0.60), intensity=strength
                    )
            if self.target_idx >= 0:
                pygame.draw.rect(surf, (35,37,42), bottom_rect, border_radius=12)
                pygame.draw.rect(surf, (60,62,66), bottom_rect, 2, border_radius=12)
                surf.blit(lbl_surf, lbl_surf.get_rect(midleft=(bottom_rect.x + 20, bottom_rect.centery)))
                self.input.rect = pygame.Rect(bottom_rect.x + lbl_surf.get_width() + 40, bottom_rect.y + 10,
                                               bottom_rect.w - lbl_surf.get_width() - 60, bottom_rect.h - 20)
                self.input.font = FONT_HUGE
                self.input.line_h = self.input.font.get_linesize()
                self.input.centered = True
                self.input.draw(surf)
                idx_target = self.target_idx + 1
                _draw_text(surf, str(idx_target), FONT_BIG, ORANGE, midleft=(bottom_rect.x - 40, bottom_rect.centery))
                instr_y = bottom_rect.bottom + 8
                _draw_text(surf, "Entrée / X : valider", FONT_MED, LIGHT_GRAY,
                           topleft=(bottom_rect.x + 20, instr_y))
                if self.o.get("audio_mode"):
                    _draw_text(surf, "Q : répéter l'audio", FONT_MED, LIGHT_GRAY,
                               topleft=(bottom_rect.x + 20, instr_y + FONT_MED.get_linesize()))            
            else:
                self.input.rect = pygame.Rect(0, 0, 0, 0)            
            return

        # viewport
        top_band=70; viewport = pygame.Rect(0, top_band, w, max(0,h-top_band-20)); prev=surf.get_clip(); surf.set_clip(viewport)
        pad=16
        label = "Calculez mentalement :"
        label_h = FONT_MED.get_linesize()
        phr_w = w-120
        phr_h = 10 + label_h + pad + FONT_HUGE.get_linesize() + pad
        offset_x = 0
        expr = self.current_expr
        audio_logo = False
        if self.o.get("audio_mode") and self.o.get("audio_hide_problem"):
            expr = f"Calcul N°{self.answered + 1}"
            audio_logo = True
        if self.shake_time > 0:
            amp = 10 * (self.shake_time / self.shake_duration)
            offset_x = int(math.sin(self.shake_phase) * amp)
        if self.app.options.get("center_text"):
            self.scroll = 0.0
            co = clamp(int(self.app.options.get("center_offset",35)),0,100)
            center_y = viewport.y + int(co/100.0 * viewport.h)
            phr_rect = pygame.Rect(0,0,phr_w,phr_h)
            phr_rect.center = (w//2 + offset_x, center_y)
            pygame.draw.rect(surf,(45,48,54), phr_rect, border_radius=12)
            _draw_text(surf, label, FONT_MED, LIGHT_GRAY,
                       rect=pygame.Rect(phr_rect.x+12, phr_rect.y+10, phr_rect.w-24, label_h), align="center")
            expr_surf = FONT_HUGE.render(expr, True, WHITE)
            prog = 0.0
            if self.pulse_time > 0:
                prog = 1 - self.pulse_time / self.pulse_duration
                scale = 1 + 0.08 * (1 - abs(1 - 2 * prog))
                expr_surf = pygame.transform.rotozoom(expr_surf, 0, scale)
            expr_center = (phr_rect.centerx, phr_rect.y+10+label_h+pad+FONT_HUGE.get_linesize()//2)
            expr_rect = expr_surf.get_rect(center=expr_center)
            surf.blit(expr_surf, expr_rect)
            self.expr_pos = expr_rect.center
            if audio_logo:
                icon = pygame.Surface((40,40), pygame.SRCALPHA)
                draw_audio_icon(icon, (6,6))
                al = 200 + int(55 * (math.sin(self.audio_icon_phase*3) + 1)/2)
                icon.set_alpha(al)
                surf.blit(icon, (phr_rect.right-40, phr_rect.y+10))
            input_top = phr_rect.bottom + 30
        else:
            y0=120
            y_offset = -self.scroll
            phr_rect = pygame.Rect(60 + offset_x, y0 + y_offset, phr_w, phr_h)

            pygame.draw.rect(surf,(45,48,54), phr_rect, border_radius=12)
            _draw_text(surf, label, FONT_MED, LIGHT_GRAY, topleft=(phr_rect.x+12, phr_rect.y+10))
            expr_surf = FONT_HUGE.render(expr, True, WHITE)
            prog = 0.0
            if self.pulse_time > 0:
                prog = 1 - self.pulse_time / self.pulse_duration
                scale = 1 + 0.08 * (1 - abs(1 - 2 * prog))
                expr_surf = pygame.transform.rotozoom(expr_surf, 0, scale)
            expr_rect = expr_surf.get_rect(topleft=(phr_rect.x+pad+20, phr_rect.y+10+label_h+pad))
            surf.blit(expr_surf, expr_rect)
            self.expr_pos = expr_rect.center
            if audio_logo:
                icon = pygame.Surface((40,40), pygame.SRCALPHA)
                draw_audio_icon(icon, (6,6))
                al = 200 + int(55 * (math.sin(self.audio_icon_phase*3) + 1)/2)
                icon.set_alpha(al)
                surf.blit(icon, (phr_rect.right-40, phr_rect.y+10))
            input_top = phr_rect.bottom + 30

        if self.bloom_timer > 0:
            t = self.bloom_timer / 0.15
            ov = pygame.Surface((phr_rect.w, phr_rect.h), pygame.SRCALPHA)
            pygame.draw.rect(ov, (*self.halo_color, int(180 * t)), ov.get_rect(), border_radius=12)
            surf.blit(ov, phr_rect.topleft, special_flags=pygame.BLEND_ADD)


        if self.halo_timer > 0:
            elapsed = self.halo_duration - self.halo_timer
            fade = 0.80
            fade_in = ease_out_cubic(min(1.0, elapsed / fade))
            fade_out = min(1.0, self.halo_timer / fade) ** 3
            strength = fade_in * fade_out
            draw_neon_sweep_rect(
                surf, phr_rect, base_color=self.halo_color, radius=12,
                core_w=3, glow=14, sweep_t=self.halo_phase, sweep_speed=1400.0,
                sweep_len=max(180, phr_rect.w * 0.60), intensity=strength
            )

        for p in self.particles:
            a = max(0, min(255, int(255 * (p["life"] / 400))))
            if p.get("surf"):
                ch = p["surf"].copy()
                ch.set_alpha(a)
                r = ch.get_rect(center=(int(p["x"]), int(p["y"])))
                surf.blit(ch, r)
            else:
                pygame.draw.circle(surf, (60,170,90,a), (int(p["x"]), int(p["y"])), 3)
        pad_v = 10
        input_h = FONT_HUGE.get_linesize() + 2*pad_v
        input_rect = pygame.Rect(60, input_top, w-120, input_h)
        self.input.rect = input_rect
        self.input.font = FONT_HUGE
        self.input.line_h = self.input.font.get_linesize()
        self.input.centered = self.app.options.get("center_text")
        self.input.draw(surf)
        if self.mode == 4:
            _draw_text(surf, "Réponse dictée automatiquement", FONT_MED, LIGHT_GRAY,
                       topleft=(input_rect.x+6, input_rect.bottom+8))
        else:
            if self.auto_submit:
                _draw_text(surf, "Validation automatique", FONT_MED, LIGHT_GRAY,
                           topleft=(input_rect.x+6, input_rect.bottom+8))
            else:
                _draw_text(surf, "Entrée / X : valider", FONT_MED, LIGHT_GRAY,
                           topleft=(input_rect.x+6, input_rect.bottom+8))
        if self.o.get("audio_mode"):
            _draw_text(surf, "Q : répéter l'audio", FONT_MED, LIGHT_GRAY,
                       topleft=(input_rect.x+6, input_rect.bottom+8 + FONT_MED.get_linesize()))
        # progression / info question
        bar_y = input_rect.bottom + 80 + FONT_MED.get_linesize()
        bar = pygame.Rect(60, bar_y, w-120, 16)
        pygame.draw.rect(surf, (50,50,55), bar, border_radius=8)
        if self.mode in (2,4) and self.num_target>0:
            prog = self.answered/self.num_target
            fill = bar.copy(); fill.width = int(bar.width * prog)
            pygame.draw.rect(surf, GREEN, fill, border_radius=8)
            if self.bar_shimmer_timer > 0:
                s = 1 - self.bar_shimmer_timer / self.bar_shimmer_duration
                shimmer_w = 80
                x = bar.x + int((bar.width + shimmer_w) * s) - shimmer_w
                sh = pygame.Surface((shimmer_w, bar.h), pygame.SRCALPHA)
                for i in range(shimmer_w):
                    al = int(120 * (1 - abs((i - shimmer_w/2) / (shimmer_w/2))))
                    pygame.draw.line(sh, (255,255,255,al), (i,0), (i,bar.h))
                surf.blit(sh, (x, bar.y), special_flags=pygame.BLEND_ADD)
        hint_y = bar.bottom + 8
        if self.o.get("per_question_timeout",0)>0:
            _draw_text(surf, f"Temps question: {max(0.0,self.timer_q):.1f}s", FONT_MED, LIGHT_GRAY, topleft=(bar.x, hint_y))
            hint_y += FONT_MED.get_linesize()
        if self.o.get("voice_answer") and self.stt.available and self.mode != 4:
            if not self._ptt:
                hint = f"Maintenez Ctrl gauche pour parler ({self.o.get('stt_lang','FR')})"
                _draw_text(surf, hint, FONT_MED, LIGHT_GRAY, topleft=(bar.x, hint_y))
                hint_y += FONT_MED.get_linesize()
        th = FONT_MED.get_linesize()
        esc_txt = "Échap : quitter   Espace : pause"; tw,_ = FONT_MED.size(esc_txt)
        _draw_text(surf, esc_txt, FONT_MED, LIGHT_GRAY, topleft=(bar.right - tw, bar.bottom+8))
        content_bottom_noscroll = hint_y
        self._content_h = (content_bottom_noscroll - 100) + 40
        surf.set_clip(prev)
        if self._content_h > viewport.h:
            bar_sc = pygame.Rect(w-10, viewport.y+8, 6, viewport.h-16)
            pygame.draw.rect(surf,(60,60,70), bar_sc)
            ratio = viewport.h / self._content_h; handle_h = max(30, int(bar_sc.h*ratio))
            max_scroll = max(1, self._content_h - viewport.h)
            pos_ratio = self.scroll / max_scroll
            handle_y = int(bar_sc.y + pos_ratio*(bar_sc.h-handle_h))
            pygame.draw.rect(surf, ORANGE, (bar_sc.x, clamp(handle_y, bar_sc.y, bar_sc.bottom-handle_h), bar_sc.w, handle_h))

        for f in self.fragments:
            al = int(255 * (f["timer"] / 1.0))
            pygame.draw.rect(surf, (*self.halo_color, al), (int(f["x"]), int(f["y"]), 4, 4))
        if self.combo_popup:
            t = 1 - self.combo_popup["timer"] / 1.0
            base = FONT_HUGE.render(self.combo_popup["text"], True, WHITE)
            scale = 1.0 + ease_out_cubic(t) * 1.2
            img = pygame.transform.rotozoom(base, 0, scale)
            rect = img.get_rect(center=(w//2, h//2))
            shadow = FONT_HUGE.render(self.combo_popup["text"], True, BLACK)
            for i in range(6):
                surf.blit(shadow, (rect.x + i + 2, rect.y + i + 2))
            surf.blit(img, rect)
        if self.orb_timer > 0:
            t = self.orb_timer
            r = 30 + 10 * math.sin((1 - t) * 6)
            ov = pygame.Surface((int(r * 2), int(r * 2)), pygame.SRCALPHA)
            pygame.draw.circle(ov, (230, 230, 120, int(180 * t)), (int(r), int(r)), int(r))
            surf.blit(ov, (w//2 - int(r), h//2 - int(r)), special_flags=pygame.BLEND_ADD)
        if self.timer_total_max > 0 and self.mode == 1:
            ratio = 1 - max(0.0, self.timer_total) / self.timer_total_max
            if ratio > 0:
                if ratio < 0.5:
                    c = lerp_color((0, 0, 0), (230, 170, 60), ratio / 0.5)
                else:
                    c = lerp_color((230, 170, 60), (200, 60, 60), (ratio - 0.5) / 0.5)
                ov = pygame.Surface((w, h), pygame.SRCALPHA)
                ov.fill((*c, int(120 * ratio)))
                surf.blit(ov, (0, 0), special_flags=pygame.BLEND_RGBA_ADD)

class EndScene(Scene):
    def __init__(self, app, game: GameScene, summary):
        self.app = app; self.game = game; self.summary = summary
        self.btn_retry = Button((0,0,200,44), "Rejouer", self.retry, sfx="start")
        self.btn_opt = Button((0,0,200,44), "Options", self.options)
        self.btn_menu = Button((0,0,200,44), "Menu principal", self.menu, sfx="back")
        self.scroll_rows = 0.0; self.rows_content_h = 0; self._rows_clip=None

        # surbrillance des réponses lentes
        self.slow_pct = TextInput((0,0,60,40), text="20", numeric_only=True, min_val=0, max_val=100)
        self.slow_up = Button((0,0,28,18), "▲", lambda: self._step_pct(+1), sfx="step")
        self.slow_dn = Button((0,0,28,18), "▼", lambda: self._step_pct(-1), sfx="step")
        for b in (self.slow_up, self.slow_dn):
            b.style = "ghost"
        today = datetime.date.today().isoformat()
        mode = summary.get("mode", 1)
        self.best_today = self.app.scores.best_session_on_date(today, mode=mode)
        saved_map = {r.get("day"): r for r in self.app.scores.get_daily_bests(mode=mode)}
        self.saved_today = saved_map.get(today)
    def retry(self): self.app.goto(GameScene(self.app))
    def options(self): self.app.goto(OptionsScene(self.app))
    def menu(self):
        self.app._suppress_next_back_sfx = True
        self.app.goto(MainMenu(self.app))
    def handle(self, ev):
        if ev.type == pygame.MOUSEWHEEL and self._rows_clip:
            mx,my = pygame.mouse.get_pos()
            if self._rows_clip.collidepoint((mx,my)) and self.rows_content_h>0:
                visible_h = self._rows_clip.h
                max_scroll = max(0, self.rows_content_h - visible_h)
                self.scroll_rows -= ev.y * 24; self.scroll_rows = clamp(self.scroll_rows, 0, max_scroll)
        self.slow_pct.handle(ev)
        handle_spinner_overlap([self.slow_up, self.slow_dn], ev)
        for b in (self.btn_retry,self.btn_opt,self.btn_menu):
            b.handle(ev)
        if ev.type == pygame.KEYDOWN and ev.key == pygame.K_ESCAPE:
            self.app._suppress_next_back_sfx = False
            self.app.goto(MainMenu(self.app)); return
    def update(self, dt): pass
    def draw(self, surf):
        w,h=surf.get_size(); surf.fill((20,22,26))
        _draw_text(surf, "Résultats", FONT_HUGE, WHITE, topleft=(40,20))
        pane = pygame.Rect(40, 90, w-80, 144)
        pygame.draw.rect(surf, (35,37,42), pane, border_radius=12)
        s=self.summary
        _draw_text(surf, f"Score: {s['score']}   Exactitude: {int(s['accuracy']*100)}%   Bonnes réponses: {s['correct']}/{s['num_problems']}", FONT_MED, WHITE, topleft=(pane.x+12, pane.y+12))
        if s.get('mode',1)==1:
            _draw_text(surf, f"Mode: Contre-la-montre   Durée: {int(self.game.o['duration_sec'])} s", FONT_MED, WHITE, topleft=(pane.x+12, pane.y+48))
        elif s.get('mode',1)==3:
            _draw_text(surf, f"Mode: Flash Anzan   Temps écoulé: {s['duration']} s   Temps moyen: {s['avg_time']} s", FONT_MED, WHITE, topleft=(pane.x+12, pane.y+48))
        elif s.get('mode',1)==4:
            _draw_text(surf, f"Mode: Audio   Temps écoulé: {s['duration']} s   Temps moyen: {s['avg_time']} s", FONT_MED, WHITE, topleft=(pane.x+12, pane.y+48))
        else:
            _draw_text(surf, f"Mode: Série   Temps écoulé: {s['duration']} s   Temps moyen: {s['avg_time']} s", FONT_MED, WHITE, topleft=(pane.x+12, pane.y+48))
        info_y = pane.y + 84
        if self.best_today:
            _draw_text(surf, f"Meilleur aujourd'hui (candidat) : {int(self.best_today.get('score',0))}", FONT_MED, WHITE, topleft=(pane.x+12, info_y))
        else:
            _draw_text(surf, "Meilleur aujourd'hui (candidat) : —", FONT_MED, LIGHT_GRAY, topleft=(pane.x+12, info_y))
        info_y += 24
        if self.saved_today:
            _draw_text(surf, f"Enregistré pour aujourd'hui : {int(self.saved_today.get('score',0))}", FONT_MED, GREEN, topleft=(pane.x+12, info_y))
        else:
            _draw_text(surf, "Enregistré pour aujourd'hui : —", FONT_MED, LIGHT_GRAY, topleft=(pane.x+12, info_y))
        # table
        table = pygame.Rect(40, pane.bottom+16, w-80, h-(pane.bottom+120))
        pygame.draw.rect(surf, (35,37,42), table, border_radius=12)
        pad=12; x=table.x+pad; y=table.y+pad
        # réglage du pourcentage des réponses lentes
        _draw_text(surf, "Top % plus lentes:", FONT_MED, LIGHT_GRAY, topleft=(table.right-230, y))
        self.slow_pct.rect = pygame.Rect(table.right-120, y-4, 60, 40)
        self.slow_pct.draw(surf)
        self._draw_spinner(surf, self.slow_pct, self.slow_up, self.slow_dn)
        col_gap=24; colw=(table.w-2*pad-col_gap)//2
        _draw_text(surf, "Calcul", FONT_MED, LIGHT_GRAY, topleft=(x,y))
        _draw_text(surf, "Votre réponse", FONT_MED, LIGHT_GRAY, topleft=(x+colw+col_gap, y))
        y+=28; sep_y = y+6; pygame.draw.line(surf,(60,60,65),(x,sep_y),(table.right-pad,sep_y),1)
        rows_clip = pygame.Rect(x, sep_y+8, table.w-2*pad, table.bottom-(sep_y+8)-pad)
        self._rows_clip = rows_clip
        prev=surf.get_clip(); surf.set_clip(rows_clip)
        # détermination des réponses lentes
        try:
            pct = clamp(int(self.slow_pct.text or "0"), 0, 100)
        except Exception:
            pct = 0
        correct = [(i, r["t"]) for i, r in enumerate(self.game.records) if r["correct"]]
        n_mark = math.ceil(len(correct) * pct / 100) if pct > 0 else 0
        slow_idx = set()
        if n_mark > 0:
            for i, _t in sorted(correct, key=lambda ir: ir[1], reverse=True)[:n_mark]:
                slow_idx.add(i)
        line_h=34; y_rows=rows_clip.y - self.scroll_rows; self.rows_content_h=0
        for idx, rec in enumerate(self.game.records):
            color = GREEN if rec["correct"] else RED
            marker = ""
            if rec["correct"] and idx in slow_idx:
                color = ORANGE
                marker = " !"
            lhs = f"{rec['expr']} = {rec['answer']}"
            rhs = (rec['typed'] if rec['typed'] else "—") + f"   ({rec['t']:.1f}s){marker}"
            row_rect = pygame.Rect(rows_clip.x, y_rows-4, rows_clip.w, line_h)
            if row_rect.bottom>=rows_clip.y and row_rect.y<=rows_clip.bottom:
                _draw_text(surf, lhs, FONT_MED, WHITE, rect=pygame.Rect(x,y_rows,colw,line_h))
                _draw_text(surf, rhs, FONT_MED, color, rect=pygame.Rect(x+colw+col_gap, y_rows, colw, line_h))
            y_rows += line_h; self.rows_content_h += line_h
        surf.set_clip(prev)
        if self.rows_content_h > rows_clip.h:
            bar = pygame.Rect(rows_clip.right-6, rows_clip.y, 6, rows_clip.h)
            pygame.draw.rect(surf,(60,60,70),bar)
            ratio = rows_clip.h / self.rows_content_h; handle_h = max(30, int(bar.h*ratio))
            max_scroll = max(1, self.rows_content_h - rows_clip.h)
            pos_ratio = self.scroll_rows / max_scroll
            handle_y = int(bar.y + pos_ratio*(bar.h-handle_h))
            pygame.draw.rect(surf, ORANGE, (bar.x, clamp(handle_y, bar.y, bar.bottom-handle_h), bar.w, handle_h))
        # boutons
        self.btn_retry.rect = pygame.Rect(w-640, h-52, 180, 40); self.btn_retry.draw(surf)
        self.btn_opt.rect   = pygame.Rect(w-440, h-52, 180, 40); self.btn_opt.draw(surf)
        self.btn_menu.rect  = pygame.Rect(w-240, h-52, 180, 40); self.btn_menu.draw(surf)

    def _draw_spinner(self, surf, ti, btn_up, btn_dn, bounds=SPINNER_HITBOX):
        """Dessine les flèches du spinner avec une hitbox ajustable."""
        top, right, bottom, left = bounds
        x = ti.rect.right + SPINNER_MARGIN_X
        btn_up.rect = pygame.Rect(
            x + left,
            ti.rect.y + top,
            SPINNER_BTN_W - left - right,
            SPINNER_BTN_H - top - bottom,
        )
        btn_dn.rect = pygame.Rect(
            x + left,
            ti.rect.bottom - SPINNER_BTN_H + top,
            SPINNER_BTN_W - left - right,
            SPINNER_BTN_H - top - bottom,
        )
        btn_up.draw(surf)
        btn_dn.draw(surf)

    def _step_pct(self, delta):
        try:
            cur = int(self.slow_pct.text or "0")
        except Exception:
            cur = 0
        self.slow_pct.text = str(clamp(cur + delta, 0, 100))

class ScoresScene(Scene):
    def __init__(self, app):
        self.app = app
        self.app.play_bgm("menu", restart=False)
        def _back_to_menu():
            self.app._suppress_next_back_sfx = True
            self.app.goto(MainMenu(self.app))

        self.btn_back = Button((0,0,200,44), "Retour", _back_to_menu, sfx="back")
        self.btn_clear = Button((0,0,220,40), "Effacer les scores", self._on_clear)
        self.btn_save_daily = Button((0,0,260,40), "Enregistrer meilleur score du jour", self._save_daily_best)
        self.btn_save_daily.sfx = "save"
        self.btn_mode = Button((0,0,200,40), "Mode: Contre-la-montre", self.toggle_mode)
        self.mode = 1
        self.profile_names = profiles_for_mode(app.profiles, self.mode)
        if app.profile_name in self.profile_names:
            self.profile_idx = self.profile_names.index(app.profile_name)
        else:
            self.profile_idx = 0
        self.view_profile = self.profile_names[self.profile_idx] if self.profile_names else ""
        self.view_scores = ScoreManager(_scores_file_for(self.view_profile))
        self.btn_profile = Button((0,0,200,40), f"Profil: {self.view_profile or '—'}", self.toggle_profile)
        self.scroll_page = 0.0; self.content_h_page=0
        self.scroll_rows = 0.0; self.rows_content_h=0
        self.sort_key = "score"; self.sort_dir = "desc"
        self._hdr_rect_date=None; self._hdr_rect_score=None
    def _on_clear(self):
        if getattr(self, "_clear_armed_until",0) > time.time():
            self.view_scores.clear_mode(self.mode)
            if self.app.scores.path == self.view_scores.path:
                self.app.scores.load()
            self.app.toast("Scores effacés.", kind="success")
            self.scroll_rows=0.0; self.scroll_page=0.0
        else:
            self._clear_armed_until = time.time()+2.0
            self.app.toast("Clique encore pour confirmer l'effacement.", kind="warning")
    def _format_date(self,s):
        try:
            dt = datetime.datetime.fromisoformat(str(s)); return dt.strftime("%Y-%m-%d  %H:%M")
        except Exception:
            return str(s).replace("T"," ")[:16]
    def _sorted(self, rows):
        rev = (self.sort_dir=="desc")
        if self.sort_key=="score": return sorted(rows, key=lambda e: int(e.get("score",0)), reverse=rev)
        if self.sort_key=="date":
            def dk(e):
                try: return datetime.datetime.fromisoformat(str(e.get("date","")))
                except: return datetime.datetime.min
            return sorted(rows, key=dk, reverse=rev)
        return rows
    def _toggle_sort(self, key):
        if key==self.sort_key: self.sort_dir = "asc" if self.sort_dir=="desc" else "desc"
        else: self.sort_key=key; self.sort_dir="desc"
    def handle(self, ev):
        if ev.type == pygame.MOUSEWHEEL:
            w,h = screen.get_size(); top=90; viewport_h = max(0,h-top-20)
            y0=100; y_draw = y0 - self.scroll_page
            panel = pygame.Rect(40, y_draw, w-80, 360)
            table = pygame.Rect(40, panel.bottom+20, w-80, 360)
            header_h = 40
            rows_clip = pygame.Rect(table.x+8, table.y+header_h+8, table.w-20, table.bottom-(table.y+header_h+16))
            mx,my = pygame.mouse.get_pos(); over_rows = rows_clip.collidepoint((mx,my))
            if over_rows and self.rows_content_h>0:
                visible_h = max(0, rows_clip.h); max_rows_scroll = max(0, self.rows_content_h - visible_h)
                self.scroll_rows -= ev.y * 24; self.scroll_rows = clamp(self.scroll_rows, 0, max_rows_scroll)
            else:
                max_page_scroll = max(0, self.content_h_page - viewport_h)
                self.scroll_page -= ev.y * 36; self.scroll_page = clamp(self.scroll_page, 0, max_page_scroll)
        if ev.type == pygame.MOUSEBUTTONDOWN and ev.button==1:
            mx,my = ev.pos
            if self._hdr_rect_date and self._hdr_rect_date.collidepoint((mx,my)): self._toggle_sort("date")
            if self._hdr_rect_score and self._hdr_rect_score.collidepoint((mx,my)): self._toggle_sort("score")
        self.btn_back.handle(ev); self.btn_clear.handle(ev); self.btn_save_daily.handle(ev); self.btn_mode.handle(ev); self.btn_profile.handle(ev)
        if ev.type == pygame.KEYDOWN and ev.key == pygame.K_ESCAPE:
            self.app._suppress_next_back_sfx = False
            self.app.goto(MainMenu(self.app)); return
    def update(self, dt): pass
    def draw(self, surf):
        w,h=surf.get_size(); surf.fill((25,27,30))
        icon_sz = int(32*ui_scale)
        draw_scores_icon(surf, (40 + icon_sz//2, 24 + icon_sz//2), WHITE, icon_sz)
        _draw_text(surf, "Scores & Historique", FONT_HUGE, WHITE, topleft=(40 + icon_sz + 10,24))
        rows_all = list(self.view_scores.history(mode=self.mode)); rows_sorted = self._sorted(rows_all)
        top=90; viewport=pygame.Rect(0, top, w, max(0,h-top-20)); prev=surf.get_clip(); surf.set_clip(viewport)
        y0=100; y_draw = y0 - self.scroll_page
        panel = pygame.Rect(40, y_draw, w-80, 360)
        draw_panel(surf, panel, (35,37,42), border_radius=12)
        today = datetime.date.today().isoformat()
        best_today = self.view_scores.best_session_on_date(today, mode=self.mode)
        saved_map = {r.get("day"): r for r in self.view_scores.get_daily_bests(mode=self.mode)}
        saved_today = saved_map.get(today)
        info_x = panel.x + 24; info_y = panel.y + 12
        if best_today:
            _draw_text(surf, f"Meilleur aujourd'hui (candidat) : {int(best_today.get('score',0))}",
                       FONT_MED, WHITE, topleft=(info_x, info_y))
        else:
            _draw_text(surf, "Meilleur aujourd'hui (candidat) : —", FONT_MED, LIGHT_GRAY,
                       topleft=(info_x, info_y))
        info_y += 24
        if saved_today:
            _draw_text(surf, f"Enregistré pour aujourd'hui : {int(saved_today.get('score',0))}",
                       FONT_MED, GREEN, topleft=(info_x, info_y))
        else:
            _draw_text(surf, "Enregistré pour aujourd'hui : —", FONT_MED, LIGHT_GRAY,
                       topleft=(info_x, info_y))
        bh = int(40 * ui_scale)
        self.btn_save_daily.rect = pygame.Rect(panel.right-320, panel.y+10, 300, bh)
        self.btn_mode.rect = pygame.Rect(self.btn_save_daily.rect.x-220, panel.y+10, 200, bh)
        self.btn_profile.rect = pygame.Rect(self.btn_mode.rect.x-220, panel.y+10, 200, bh)
        self.btn_profile.draw(surf)
        self.btn_mode.draw(surf)
        self.btn_save_daily.draw(surf)
        graph_rect = panel.inflate(-24, -(30+56)).move(0,56-24)
        MainMenu(self.app).draw_history_graph(surf, graph_rect, mode=self.mode, scores=self.view_scores)
        self.btn_profile.draw(surf)
        self.btn_mode.draw(surf)
        self.btn_save_daily.draw(surf)
        table = pygame.Rect(40, panel.bottom+20, w-80, 360)
        draw_panel(surf, table, (35,37,42), border_radius=12)
        pad=12; header_y = table.y + pad
        arrow_date = " ▼" if (self.sort_key=="date" and self.sort_dir=="desc") else (" ▲" if self.sort_key=="date" else "")
        arrow_score = " ▼" if (self.sort_key=="score" and self.sort_dir=="desc") else (" ▲" if self.sort_key=="score" else "")
        lbl_date = "Date"+arrow_date; lbl_score="Score"+arrow_score
        if self.mode == 1:
            headers = [lbl_date, "Niv", "Temps", "Calculs", "Bonnes", "Exact.", "Temps moy.", lbl_score]
        elif self.mode == 2:
            headers = [
                lbl_date,
                "Niv",
                "Durée",
                "Calculs",
                "Bonnes",
                "Exact.",
                "Temps moy.",
                lbl_score,
            ]
        elif self.mode == 3:
            headers = [lbl_date, "Niv", "Nbr/série", "Nbr Série", "Bonnes", "Exact.", "Temps moy.", lbl_score]
        else:
            headers = [lbl_date, "Niv", "Durée", "Calculs", "Bonnes", "Exact.", "Temps moy.", lbl_score]
        x = table.x + pad
        colx = []
        colx.append(x)
        x += 180
        colx.append(x)
        x += 60
        for i in range(2, len(headers)-1):
            colx.append(x)
            x += 120
        colx.append(table.right - pad - 120)
        for i,hd in enumerate(headers): _draw_text(surf, hd, FONT_MED, LIGHT_GRAY, topleft=(colx[i], header_y))
        twd,_ = FONT_MED.size(lbl_date); tws,_ = FONT_MED.size(lbl_score)
        self._hdr_rect_date = pygame.Rect(colx[0], header_y, twd, FONT_MED.get_linesize())
        self._hdr_rect_score = pygame.Rect(colx[-1], header_y, tws, FONT_MED.get_linesize())
        header_h=40; sep_y = table.y + header_h; pygame.draw.line(surf,(60,60,65),(table.x+8,sep_y),(table.right-20,sep_y),1)
        rows_clip = pygame.Rect(table.x+8, sep_y+8, table.w-20, table.bottom-(sep_y+16))
        inner_prev = surf.get_clip(); surf.set_clip(rows_clip)
        y = rows_clip.y - self.scroll_rows; line_h=26; score_idx = len(headers)-1
        for e in rows_sorted[-800:]:
            if self.mode == 1:
                vals = [
                    self._format_date(e.get("date","")),
                    str(e.get("level","")),
                    f"{int(e.get('duration',0))} s",
                    str(e.get('num_problems',0)),
                    str(e.get('correct',0)),
                    f"{int(100*e.get('accuracy',0))}%",
                    f"{e.get('avg_time',0):.2f}s",
                    str(e.get("score",0)),
                ]
            elif self.mode == 2:
                vals = [
                    self._format_date(e.get("date","")),
                    str(e.get("level","")),
                    f"{int(e.get('duration',0))} s",
                    str(e.get('num_problems',0)),
                    str(e.get('correct',0)),
                    f"{int(100*e.get('accuracy',0))}%",
                    f"{e.get('avg_time',0):.2f}s",
                    str(e.get("score",0)),
                ]
            elif self.mode == 3:
                vals = [
                    self._format_date(e.get("date","")),
                    str(e.get("level","")),
                    str(e.get('flash_numbers', e.get('flash_additions',0))),
                    str(e.get('flash_series', e.get('num_target',0))),
                    str(e.get('correct',0)),
                    f"{int(100*e.get('accuracy',0))}%",
                    f"{e.get('avg_time',0):.2f}s",
                    str(e.get("score",0)),
                ]
            else:
                vals = [
                    self._format_date(e.get("date","")),
                    str(e.get("level","")),
                    f"{int(e.get('duration',0))} s",
                    str(e.get('num_problems',0)),
                    str(e.get('correct',0)),
                    f"{int(100*e.get('accuracy',0))}%",
                    f"{e.get('avg_time',0):.2f}s",
                    str(e.get("score",0)),
                ]
            row_rect = pygame.Rect(rows_clip.x, y-4, rows_clip.w, line_h)
            if row_rect.bottom>=rows_clip.y and row_rect.y<=rows_clip.bottom:
                if ((y//line_h)%2)==1: pygame.draw.rect(surf,(40,42,48),row_rect)
                for i,val in enumerate(vals):
                    if i == score_idx:
                        tw,_ = FONT_MED.size(val)
                        _draw_text(surf, val, FONT_MED, WHITE, topleft=(colx[i]+90 - tw, y))
                    else:
                        _draw_text(surf, val, FONT_MED, WHITE, topleft=(colx[i], y))
            y += line_h
        self.rows_content_h = max(0, len(rows_sorted[-800:]) * line_h)
        surf.set_clip(inner_prev)
        if self.rows_content_h > rows_clip.h:
            bar = pygame.Rect(table.right-12, rows_clip.y, 6, rows_clip.h)
            pygame.draw.rect(surf,(60,60,70),bar)
            ratio = rows_clip.h / self.rows_content_h; handle_h = max(30, int(bar.h*ratio))
            max_scroll = max(1, self.rows_content_h - rows_clip.h)
            pos_ratio = self.scroll_rows / max_scroll
            handle_y = int(bar.y + pos_ratio*(bar.h-handle_h))
            pygame.draw.rect(surf, ORANGE, (bar.x, clamp(handle_y, bar.y, bar.bottom-handle_h), bar.w, handle_h))
        page_bottom_noscroll = (y0+260) + 20 + 360
        self.content_h_page = (page_bottom_noscroll - y0) + 20
        surf.set_clip(prev)
        if self.content_h_page > viewport.h:
            bar = pygame.Rect(w-10, viewport.y+8, 6, viewport.h-16)
            pygame.draw.rect(surf,(60,60,70),bar)
            ratio = viewport.h / self.content_h_page; handle_h = max(30, int(bar.h*ratio))
            max_scroll = max(1, self.content_h_page - viewport.h)
            pos_ratio = self.scroll_page / max_scroll
            handle_y = int(bar.y + pos_ratio*(bar.h - handle_h))
            pygame.draw.rect(surf, ORANGE, (bar.x, clamp(handle_y, bar.y, bar.bottom-handle_h), bar.w, handle_h))
        self.btn_clear.rect = pygame.Rect(w-880, h-52, 220, 40); self.btn_clear.draw(surf)
        self.btn_back.rect  = pygame.Rect(w-240, h-52, 200, 40); self.btn_back.draw(surf)

    def toggle_mode(self):
        self.mode = 1 if self.mode == 5 else self.mode + 1
        if self.mode == 1:
            self.btn_mode.text = "Mode: Contre-la-montre"
        elif self.mode == 2:
            self.btn_mode.text = "Mode: Série"
        elif self.mode == 3:
            self.btn_mode.text = "Mode: Flash Anzan"
        elif self.mode == 4:
            self.btn_mode.text = "Mode: Audio"
        else:
            self.btn_mode.text = "Mode: Calcul Infernal"
        self.profile_names = profiles_for_mode(self.app.profiles, self.mode)
        self.profile_idx = 0
        self._refresh_profile()
        self.scroll_rows = 0.0; self.scroll_page = 0.0

    def toggle_profile(self):
        if not self.profile_names:
            return
        self.profile_idx = (self.profile_idx + 1) % len(self.profile_names)
        self._refresh_profile()
        self.scroll_rows = 0.0; self.scroll_page = 0.0

    def _refresh_profile(self):
        if self.profile_names:
            self.view_profile = self.profile_names[self.profile_idx]
        else:
            self.view_profile = ""
        self.view_scores = ScoreManager(_scores_file_for(self.view_profile))
        self.btn_profile.text = f"Profil: {self.view_profile or '—'}"

    def _save_daily_best(self):
        today = datetime.date.today().isoformat()
        best = self.view_scores.best_session_on_date(today, mode=self.mode)
        if not best:
            self.app.toast("Aucune session aujourd'hui.")
            return
        entry = {
            "day": today,
            "mode": self.mode,
            "score": int(best.get("score",0)),
            "accuracy": best.get("accuracy",0),
            "level": best.get("level",0),
            "num_problems": best.get("num_problems",0),
            "duration": best.get("duration",0),
            "date_src": best.get("date",""),
        }
        prev_map = {r.get("day"): r for r in self.view_scores.get_daily_bests(mode=self.mode)}
        prev = prev_map.get(today)
        self.view_scores.upsert_daily_best(entry)
        if self.app.scores.path == self.view_scores.path:
            self.app.scores.load()
        if prev is None:
            self.app.toast("Meilleur score du jour enregistré.", kind="success")
        else:
            if int(entry["score"]) > int(prev.get("score",0)):
                self.app.toast("Meilleur du jour mis à jour.", kind="success")
            else:
                self.app.toast("Déjà au meilleur du jour.")

class RulesScene(Scene):
    def __init__(self, app):
        self.app = app; self.scroll=0.0; self.pad=16
        self.app.play_bgm("menu", restart=False)
        def _back_to_menu():
            self.app._suppress_next_back_sfx = True
            self.app.goto(MainMenu(self.app))

        self.btn_back = Button((0,0,200,44), "Retour", _back_to_menu, sfx="back")
        self.sections = [
            ("But du jeu",
             "Renforcer les automatismes de calcul mental (addition, soustraction,\n"
             "multiplication, division) tout en améliorant la vitesse d'exécution\n"
             "et la précision. Quatre modes s'adaptent à votre objectif :\n"
             "• Contre-la-montre : maximiser le nombre de réponses exactes.\n"
             "• Série : atteindre un quota et suivre votre temps moyen.\n"
             "• Flash Anzan : mémoriser une suite de nombres et donner la somme.\n"
             "• Mode audio : enchaîner les calculs uniquement à la voix."),
            ("Comment jouer",
             "• Tapez le résultat puis validez avec Entrée ou X.\n"
             "• (Si la voix TTS est activée) appuyez sur Q pour répéter l'audio.\n"
             "• En mode audio, les calculs sont lus et vous répondez en dictant.\n"
             "• En mode CLM, le chrono global tourne ; en mode Série, vous avez un\n"
             "  nombre de calculs à faire (le chrono total est mesuré).\n"
             "• En Flash Anzan, retenez les nombres affichés puis donnez leur somme.\n"
             "• (Optionnel) Limite par question : si elle expire, la question passe."),
            ("Options utiles",
             "• Mélange des opérations dans un même calcul.\n"
             "• Nombre d'opérandes (2 à 4+).\n"
             "• Taille des nombres (unités→milliers), mélangeable.\n"
             "• Confort : addition sans retenue (2 termes), soustraction sans emprunt (2 termes),\n"
             "  résultat toujours positif, divisions à résultat entier.\n"
             "• Tables de × limitées (ex.: jusqu'à 12).\n"
             "• Parenthèses (légères) — évitées si ÷ est activée pour garder des entiers propres."),
            ("Conseils d'entraînement",
             "• Débutez avec 2 opérandes, unités/dizaines, tables × limitées.\n"
             "• Stabilisez vos options pour mesurer le progrès.\n"
             "• Augmentez progressivement : opérandes, tailles, mélange des opérations.\n"
             "• Travaillez la précision d'abord (≥ 80–90%), puis accélérez."),
        ]
    def handle(self, ev):
        if ev.type == pygame.MOUSEWHEEL:
            w,h = screen.get_size(); vp_h = h-140
            max_scroll = max(0, getattr(self, 'content_h',0) - (vp_h - 2*self.pad))
            self.scroll -= ev.y * 24; self.scroll = clamp(self.scroll, 0, max_scroll)
        self.btn_back.handle(ev)
        if ev.type == pygame.KEYDOWN and ev.key == pygame.K_ESCAPE:
            sfx_play("back")
            self.app._suppress_next_back_sfx = False
            self.app.goto(MainMenu(self.app)); return
    def _wrap_text(self, font, text, max_w):
        all_lines=[]
        for para in text.split("\n"):
            words=para.split(" "); cur=""
            for w in words:
                test=(cur+" "+w).strip() if cur else w
                if font.size(test)[0] <= max_w: cur=test
                else:
                    if cur: all_lines.append(cur)
                    cur=w
            if cur: all_lines.append(cur)
        return all_lines
    def draw(self, surf):
        w,h=surf.get_size(); surf.fill((25,27,30))
        _draw_text(surf, "Règles du jeu", FONT_HUGE, WHITE, topleft=(40,24))
        viewport = pygame.Rect(40,90,w-80,h-140)
        pygame.draw.rect(surf,(35,37,42),viewport,border_radius=12)
        pad=self.pad; inner=viewport.inflate(-2*pad,-2*pad)
        prev=surf.get_clip(); surf.set_clip(inner)
        y=inner.y - self.scroll
        for (title,body) in self.sections:
            _draw_text(surf, title, FONT_BIG, WHITE, topleft=(inner.x,y)); y+=FONT_BIG.get_linesize()+6
            for ln in self._wrap_text(FONT_MED, body, inner.w):
                surf.blit(FONT_MED.render(ln, True, LIGHT_GRAY), (inner.x, y)); y+=FONT_MED.get_linesize()
            y+=10
        surf.set_clip(prev)
        self.content_h = (y - (inner.y - self.scroll))
        if self.content_h > viewport.h:
            bar = pygame.Rect(viewport.right-10, viewport.y+8, 6, viewport.h-16)
            pygame.draw.rect(surf,(60,60,70),bar)
            ratio = viewport.h / self.content_h; handle_h = max(30,int(bar.h*ratio))
            max_scroll = max(1, self.content_h - (viewport.h - 2*pad))
            pos_ratio = self.scroll / max_scroll
            handle_y = int(bar.y + pos_ratio*(bar.h - handle_h))
            pygame.draw.rect(surf, ORANGE, (bar.x, clamp(handle_y, bar.y, bar.bottom-handle_h), bar.w, handle_h))
        self.btn_back.rect = pygame.Rect(w-240, h-48, 200, 44); self.btn_back.draw(surf)

# ---------- App ----------

class PauseOverlay:
    def __init__(self, app):
        self.app = app
        o = app.options
        self.chk_music = Checkbox((0,0,240,24), "Musique", checked=o.get("music_enabled", True))
        mv = int(round(100 * float(o.get("music_volume", 0.15))))
        self.music_vol = TextInput((0,0,90,40), text=str(mv), numeric_only=True, min_val=0, max_val=100)
        self.chk_sfx = Checkbox((0,0,200,24), "Bruitages", checked=o.get("sfx_enabled", True))
        sv = int(round(100 * float(o.get("sfx_volume", 1.0))))
        self.sfx_vol = TextInput((0,0,90,40), text=str(sv), numeric_only=True, min_val=0, max_val=100)
        self.chk_fullscreen = Checkbox((0,0,240,24), "Plein écran (F11)", checked=o.get("fullscreen", False))
        self.chk_center = Checkbox((0,0,220,24), "Centrer les textes", checked=o.get("center_text", False))
        self.center_off = TextInput((0,0,90,40), text=str(int(o.get("center_offset",35))), numeric_only=True, min_val=0, max_val=100)
        self.font_level = TextInput((0,0,90,40), text=str(int(o.get("font_level",3))), numeric_only=True, min_val=1, max_val=100)
        # spinners
        self.mvol_up = Button((0,0,28,18), "▲", lambda: self._step(self.music_vol, +1, 0, 100), sfx="step")
        self.mvol_dn = Button((0,0,28,18), "▼", lambda: self._step(self.music_vol, -1, 0, 100), sfx="step")
        self.svol_up = Button((0,0,28,18), "▲", lambda: self._step(self.sfx_vol, +1, 0, 100), sfx="step")
        self.svol_dn = Button((0,0,28,18), "▼", lambda: self._step(self.sfx_vol, -1, 0, 100), sfx="step")
        self.coff_up = Button((0,0,28,18), "▲", lambda: self._step(self.center_off, +1, 0, 100), sfx="step")
        self.coff_dn = Button((0,0,28,18), "▼", lambda: self._step(self.center_off, -1, 0, 100), sfx="step")
        self.font_up = Button((0,0,28,18), "▲", lambda: self._step(self.font_level, +1, 1, 100), sfx="step")
        self.font_dn = Button((0,0,28,18), "▼", lambda: self._step(self.font_level, -1, 1, 100), sfx="step")
        for b in [self.mvol_up,self.mvol_dn,self.svol_up,self.svol_dn,
                  self.coff_up,self.coff_dn,self.font_up,self.font_dn]:
            b.style = "ghost"
        self.chk_green_fx = Checkbox((0,0,240,24), "Lumière verte", checked=o.get("green_fx", True))
        self.bg_styles = ["Rectangles + couleurs", "Rectangles", "Aucun"]
        self.bg_idx = clamp(o.get("game_bg_style",0),0,len(self.bg_styles)-1)
        self.bg_prev = Button((0,0,40,40), "<", lambda: setattr(self,'bg_idx',(self.bg_idx-1)%len(self.bg_styles)), sfx="step")
        self.bg_next = Button((0,0,40,40), ">", lambda: setattr(self,'bg_idx',(self.bg_idx+1)%len(self.bg_styles)), sfx="step")
        self.btn_resume = Button((0,0,120,44), "Continuer", self._resume)
        self.btn_restart = Button((0,0,120,44), "Rejouer", self._restart)
        self.btn_quit = Button((0,0,120,44), "Quitter", self._quit)

    def refresh_from_options(self):
        o = self.app.options
        self.chk_music.checked = o.get("music_enabled", True)
        self.music_vol.text = str(int(round(100 * float(o.get("music_volume", 0.15)))))
        self.chk_sfx.checked = o.get("sfx_enabled", True)
        self.sfx_vol.text = str(int(round(100 * float(o.get("sfx_volume", 1.0)))))
        self.chk_fullscreen.checked = o.get("fullscreen", False)
        self.chk_center.checked = o.get("center_text", False)
        self.center_off.text = str(int(o.get("center_offset", 35)))
        self.font_level.text = str(int(o.get("font_level", 3)))
        self.chk_green_fx.checked = o.get("green_fx", True)
        self.bg_idx = clamp(o.get("game_bg_style",0),0,len(self.bg_styles)-1)

    def _step(self, ti, delta, lo=0, hi=100):
        try:
            cur = int(ti.text or "0")
        except Exception:
            cur = lo
        ti.text = str(clamp(cur + delta, lo, hi))

    def _resume(self):
        self.app.paused = False

    def _restart(self):
        self.app.paused = False
        GameCls = self.app.scene.__class__
        self.app.goto(GameCls(self.app))

    def _quit(self):
        self.app._suppress_next_back_sfx = True
        self.app.play_bgm("menu", restart=False)
        self.app.goto(MainMenu(self.app))
        self.app.paused = False

    def handle(self, ev):
        self.chk_music.handle(ev)
        self.music_vol.handle(ev)
        self.chk_sfx.handle(ev)
        self.sfx_vol.handle(ev)
        self.chk_fullscreen.handle(ev)
        self.chk_center.handle(ev)
        self.center_off.handle(ev)
        self.font_level.handle(ev)
        self.chk_green_fx.handle(ev)
        self.bg_prev.handle(ev); self.bg_next.handle(ev)
        handle_spinner_overlap(
            [
                self.mvol_up,
                self.mvol_dn,
                self.svol_up,
                self.svol_dn,
                self.coff_up,
                self.coff_dn,
                self.font_up,
                self.font_dn,
            ],
            ev,
        )
        for b in [self.btn_resume, self.btn_restart, self.btn_quit]:
            b.handle(ev)
        self.apply()

    def apply(self):
        o = self.app.options
        o["music_enabled"] = self.chk_music.checked
        try:
            mv = int(self.music_vol.text or "15")
            mv = clamp(mv, 0, 100)
        except Exception:
            mv = 15
        o["music_volume"] = mv/100.0
        o["sfx_enabled"] = self.chk_sfx.checked
        try:
            sv = int(self.sfx_vol.text or "100")
            sv = clamp(sv, 0, 100)
        except Exception:
            sv = 100
        o["sfx_volume"] = sv/100.0
        prev_full = o.get("fullscreen")
        o["fullscreen"] = self.chk_fullscreen.checked
        if o["fullscreen"] != prev_full:
            self.app.apply_display_mode()
            self.app.profiles[self.app.profile_name]["fullscreen"] = o["fullscreen"]
            self.app.save_profiles()
            if hasattr(self.app.scene, "chk_fullscreen"):
                self.app.scene.chk_fullscreen.checked = o["fullscreen"]
        o["center_text"] = self.chk_center.checked
        try:
            co = int(self.center_off.text or "35")
            co = clamp(co, 0, 100)
        except Exception:
            co = 35
        o["center_offset"] = co
        try:
            lvl = int(self.font_level.text or "3")
            lvl = clamp(lvl, 1, 100)
        except Exception:
            lvl = 3
        o["font_level"] = lvl
        o["green_fx"] = self.chk_green_fx.checked
        o["game_bg_style"] = self.bg_idx
        if hasattr(self.app.scene, "o"):
            self.app.scene.o["green_fx"] = o["green_fx"]
            self.app.scene.o["game_bg_style"] = o["game_bg_style"]
            if hasattr(self.app.scene, "bg_style"):
                self.app.scene.bg_style = o["game_bg_style"]
        self.app.rebuild_fonts()
        if o["music_enabled"]:
            track = "menu" if isinstance(self.app.scene, MainMenu) else "game"
            self.app.play_bgm(track, restart=False, volume=o["music_volume"])
        else:
            self.app.stop_bgm()

    def update_fonts(self):
        for ti in [self.music_vol, self.sfx_vol, self.center_off, self.font_level]:
            ti.font = FONT_MED
            ti.line_h = ti.font.get_linesize()
        for b in [self.btn_resume, self.btn_restart, self.btn_quit]:
            b.font = FONT_MED

    def draw(self, surf):
        w,h = surf.get_size()
        overlay = pygame.Surface((w,h), pygame.SRCALPHA)
        overlay.fill((0,0,0,160))
        surf.blit(overlay, (0,0))
        panel = pygame.Rect(w//2-220, h//2-280, 440, 560)
        pygame.draw.rect(surf, (30,30,34,230), panel, border_radius=12)
        _draw_text(surf, "PAUSE", FONT_BIG, WHITE, center=(panel.centerx, panel.y+30))
        # musique
        self.chk_music.rect.topleft = (panel.x+20, panel.y+80); self.chk_music.draw(surf)
        self.music_vol.rect.topleft = (panel.x+240, panel.y+74); self.music_vol.rect.size=(90,36); self.music_vol.draw(surf)
        self.mvol_up.rect = pygame.Rect(self.music_vol.rect.right+3, self.music_vol.rect.y-5.5, 28,18)
        self.mvol_dn.rect = pygame.Rect(self.music_vol.rect.right+3, self.music_vol.rect.y+13.5, 28,18)
        self.mvol_up.draw(surf); self.mvol_dn.draw(surf)
        # bruitages
        self.chk_sfx.rect.topleft = (panel.x+20, panel.y+140); self.chk_sfx.draw(surf)
        self.sfx_vol.rect.topleft = (panel.x+240, panel.y+134); self.sfx_vol.rect.size=(90,36); self.sfx_vol.draw(surf)
        self.svol_up.rect = pygame.Rect(self.sfx_vol.rect.right+3, self.sfx_vol.rect.y-5.5, 28,18)
        self.svol_dn.rect = pygame.Rect(self.sfx_vol.rect.right+3, self.sfx_vol.rect.y+13.5, 28,18)
        self.svol_up.draw(surf); self.svol_dn.draw(surf)
        # plein écran et centrage
        self.chk_fullscreen.rect.topleft = (panel.x+20, panel.y+200); self.chk_fullscreen.draw(surf)
        self.chk_center.rect.topleft = (panel.x+20, panel.y+240); self.chk_center.draw(surf)
        _draw_text(surf, "Décalage vertical", FONT_MED, WHITE, topleft=(panel.x+20, panel.y+284))
        self.center_off.rect.topleft = (panel.x+240, panel.y+278); self.center_off.rect.size=(90,36); self.center_off.draw(surf)
        self.coff_up.rect = pygame.Rect(self.center_off.rect.right+3, self.center_off.rect.y-5.5, 28,18)
        self.coff_dn.rect = pygame.Rect(self.center_off.rect.right+3, self.center_off.rect.y+13.5, 28,18)
        self.coff_up.draw(surf); self.coff_dn.draw(surf)
        # police
        _draw_text(surf, "Taille caractères", FONT_MED, WHITE, topleft=(panel.x+20, panel.y+344))
        self.font_level.rect.topleft = (panel.x+240, panel.y+338); self.font_level.rect.size=(90,36); self.font_level.draw(surf)
        self.font_up.rect = pygame.Rect(self.font_level.rect.right+3, self.font_level.rect.y-5.5, 28,18)
        self.font_dn.rect = pygame.Rect(self.font_level.rect.right+3, self.font_level.rect.y+13.5, 28,18)
        self.font_up.draw(surf); self.font_dn.draw(surf)
        # effets visuels
        self.chk_green_fx.rect.topleft = (panel.x+20, panel.y+384); self.chk_green_fx.draw(surf)
        _draw_text(surf, "Fond de jeu", FONT_MED, WHITE, topleft=(panel.x+20, panel.y+424))
        self.bg_prev.rect.topleft = (panel.x+240, panel.y+418); self.bg_prev.draw(surf)
        rect = pygame.Rect(panel.x+280, panel.y+418, 140,40); draw_panel(surf, rect)
        _draw_text(surf, self.bg_styles[self.bg_idx], FONT_MED, WHITE, rect=rect, align="center")
        self.bg_next.rect.topleft = (rect.right+4, panel.y+418); self.bg_next.draw(surf)
        # boutons
        self.btn_resume.rect.topleft = (panel.x+20, panel.bottom-60); self.btn_resume.draw(surf)
        self.btn_restart.rect.topleft = (panel.x+160, panel.bottom-60); self.btn_restart.draw(surf)
        self.btn_quit.rect.topleft = (panel.x+300, panel.bottom-60); self.btn_quit.draw(surf)

class App:
    def __init__(self):
        global APP_INSTANCE
        APP_INSTANCE = self
        init_sfx()
        self.bgm_files = MUSIC_FILES
        self.bgm_current = None
        self._bgm_a = pygame.mixer.Channel(0)
        self._bgm_b = pygame.mixer.Channel(1)
        self._bgm_active = self._bgm_a
        self._bgm_next = self._bgm_b
        self._bgm_fade = None
        self._bgm_sounds = {}
        self.profiles = {}
        self.profile_name = DEFAULT_PROFILE
        self.load_profiles()
        self.load_profile(self.profile_name)
        self.scene = MainMenu(self)
        self._toast=None
        self.paused = False
        self.pause_overlay = PauseOverlay(self)
        self._pause_bg = None
        self._suppress_next_back_sfx = False
        self._transition = None
        # mémorise la taille fenêtre pour restaurer après un plein écran
        self._windowed_size = screen.get_size()
        self.cursor = OrbCursor()

    def toast(self, msg, dur=1.5, kind="info"):
        self._toast = {"msg": msg, "dur": dur, "start": time.time(), "kind": kind}
    def goto(self, scene):
        if isinstance(scene, MainMenu):
            if getattr(self, "_suppress_next_back_sfx", False):
                self._suppress_next_back_sfx = False
            else:
                sfx_play("back")
        self._transition = FadeTransition(self, scene)
    def play_bgm(self, name, restart=False, fade_ms=400, volume=None):
        if not self.options.get("music_enabled", True):
            return
        if self.bgm_current == name and not restart:
            return
        path = self.bgm_files.get(name)
        if not path or not os.path.exists(path):
            return
        if volume is None:
            volume = self.options.get("music_volume", 0.15)
        try:
            snd = self._bgm_sounds.get(name)
            if snd is None:
                snd = pygame.mixer.Sound(path)
                self._bgm_sounds[name] = snd
        except Exception:
            return
        if not self._bgm_active.get_busy():
            self._bgm_active.play(snd, loops=-1)
            self._bgm_active.set_volume(volume)
            self.bgm_current = name
            return
        self._bgm_next.play(snd, loops=-1)
        self._bgm_next.set_volume(0.0)
        self._bgm_fade = {
            "from": self._bgm_active,
            "to": self._bgm_next,
            "time": 0.0,
            "dur": fade_ms/1000.0,
            "target": volume,
            "start": self._bgm_active.get_volume(),
            "name": name,
        }

    def stop_bgm(self, fade_ms=300):
        if self._bgm_fade:
            self._bgm_fade = None
        try:
            self._bgm_active.fadeout(fade_ms)
            self._bgm_next.fadeout(fade_ms)
        except Exception:
            pass
        self.bgm_current = None

    # ---------- Profils ----------
    def load_profiles(self):
        if os.path.exists(PROFILES_PATH):
            try:
                with open(PROFILES_PATH, "r", encoding="utf-8") as f:
                    data = json.load(f)
                self.profile_name = data.get("current", DEFAULT_PROFILE)
                self.profiles = data.get("profiles", {})
                if "default" in self.profiles:
                    self.profiles[DEFAULT_PROFILE] = self.profiles.pop("default")
                if self.profile_name == "default":
                    self.profile_name = DEFAULT_PROFILE
            except Exception:
                self.profiles = {}
        self.profiles.pop(DEFAULT_PROFILE, None)
        self.profiles[DEFAULT_PROFILE] = DEFAULT_OPTIONS.copy()
        if self.profile_name not in self.profiles:
            self.profile_name = DEFAULT_PROFILE
        self.save_profiles()

    def save_profiles(self):
        try:
            data = {k: v for k, v in self.profiles.items() if k != DEFAULT_PROFILE}
            with open(PROFILES_PATH, "w", encoding="utf-8") as f:
                json.dump({"current": self.profile_name, "profiles": data}, f, ensure_ascii=False, indent=2)
        except Exception:
            pass

    def load_profile(self, name):
        if name not in self.profiles:
            name = next(iter(self.profiles))
        self.profile_name = name
        self.options = self.profiles[name].copy()
        self.scores = ScoreManager(_scores_file_for(name))
        self.apply_display_mode()
        if hasattr(self, "pause_overlay"):
            self.pause_overlay.refresh_from_options()
        if self.options.get("music_enabled", True):
            try:
                try:
                    self._bgm_active.set_volume(self.options.get("music_volume", 0.15))
                except Exception:
                    pass
            except Exception:
                pass
        else:
            self.stop_bgm()

    def create_profile(self, name):
        if name in self.profiles:
            return False
        self.profiles[name] = DEFAULT_OPTIONS.copy()
        self.load_profile(name)
        self.save_profiles()
        return True

    def rename_profile(self, old, new):
        if old == DEFAULT_PROFILE or old not in self.profiles or new in self.profiles:
            return False
        self.profiles[new] = self.profiles.pop(old)
        old_path = _scores_file_for(old)
        new_path = _scores_file_for(new)
        if os.path.exists(old_path):
            try:
                os.replace(old_path, new_path)
            except Exception:
                pass
        self.load_profile(new)
        self.save_profiles()
        return True

    def delete_profile(self, name):
        if name == DEFAULT_PROFILE or name not in self.profiles or len(self.profiles) <= 1:
            return False
        self.profiles.pop(name, None)
        path = _scores_file_for(name)
        try:
            os.remove(path)
        except Exception:
            pass
        if self.profile_name == name:
            self.load_profile(next(iter(self.profiles)))
        self.save_profiles()
        return True

    def apply_display_mode(self):
        global screen
        if self.options.get("fullscreen"):
            # mémorise la taille fenêtre actuelle pour y revenir ensuite
            self._windowed_size = screen.get_size()
            screen = pygame.display.set_mode((0, 0), pygame.FULLSCREEN)
        else:
            size = getattr(self, "_windowed_size", screen.get_size())
            screen = pygame.display.set_mode(size, pygame.RESIZABLE)
        self.rebuild_fonts()

    def rebuild_fonts(self):
        lvl = int(self.options.get("font_level", 3))
        lvl = clamp(lvl, 1, 100)
        base_small, base_med, base_big, base_huge = 16, 22, 34, 44
        expr_size = base_huge + (lvl - 3) * 4
        global ui_scale, FONT_SM, FONT_MD, FONT_LG, FONT_HUGE, FONT_SMALL, FONT_MED, FONT_BIG, FONT_TOAST
        ui_scale = compute_ui_scale()
        FONT_SM = pygame.font.SysFont("arial", int(base_small * ui_scale))
        FONT_MD = pygame.font.SysFont("arial", int(base_med * ui_scale))
        FONT_LG = pygame.font.SysFont("arial", int(base_big * ui_scale))
        FONT_HUGE = pygame.font.SysFont("arial", int(expr_size * ui_scale))
        FONT_TOAST = pygame.font.SysFont("arial", int(base_med * 3 * ui_scale))
        FONT_SMALL = FONT_SM
        FONT_MED = FONT_MD
        FONT_BIG = FONT_LG
        if hasattr(self, "pause_overlay"):
            self.pause_overlay.update_fonts()

    def run(self):
        running=True
        while running:
            dt = CLOCK.tick(60)/1000.0
            self.cursor.set_hover(None)
            for ev in pygame.event.get():
                if ev.type == pygame.QUIT:
                    running=False
                elif ev.type == pygame.VIDEORESIZE:
                    if not self.options.get("fullscreen"):
                        pygame.display.set_mode((ev.w, ev.h), pygame.RESIZABLE)
                        self._windowed_size = (ev.w, ev.h)
                        self.rebuild_fonts()
                elif ev.type == pygame.KEYUP and ev.key in (pygame.K_F11, pygame.K_F1):
                    self.options["fullscreen"] = not self.options.get("fullscreen", False)
                    self.profiles[self.profile_name]["fullscreen"] = self.options["fullscreen"]
                    self.apply_display_mode()
                    self.save_profiles()
                    if hasattr(self.scene, "chk_fullscreen"):
                        self.scene.chk_fullscreen.checked = self.options["fullscreen"]
                    if hasattr(self.pause_overlay, "chk_fullscreen"):
                        self.pause_overlay.chk_fullscreen.checked = self.options["fullscreen"]
                elif (
                    ev.type == pygame.KEYDOWN
                    and ev.key == pygame.K_SPACE
                    and isinstance(self.scene, GameScene)
                ):
                    if self.paused:
                        self.paused = False
                    else:
                        self.paused = True
                        self.scene.draw(screen)
                        pygame.display.flip()
                        snap = screen.copy()
                        w, h = snap.get_size()
                        small = pygame.transform.smoothscale(
                            snap, (max(1, w // 10), max(1, h // 10))
                        )
                        self._pause_bg = pygame.transform.smoothscale(small, (w, h))
                else:
                    if ev.type == pygame.MOUSEMOTION:
                        try:
                            pygame.mouse.set_cursor(pygame.SYSTEM_CURSOR_ARROW)
                        except Exception:
                            pass
                    if self.paused:
                        self.pause_overlay.handle(ev)
                    else:
                        self.scene.handle(ev)
            if self._bgm_fade:
                cf = self._bgm_fade
                cf["time"] += dt
                t = min(1.0, cf["time"] / cf["dur"])
                cf["from"].set_volume(cf["start"] * (1 - t))
                cf["to"].set_volume(cf["target"] * t)
                if t >= 1.0:
                    cf["from"].stop()
                    self._bgm_active = cf["to"]
                    self._bgm_next = cf["from"]
                    self.bgm_current = cf["name"]
                    self._bgm_fade = None
            if not self.paused:
                self.scene.update(dt)
                self.scene.draw(screen)
                if self._transition:
                    self._transition.update()
                    if self._transition:
                        self._transition.draw(screen)
            else:
                screen.blit(self._pause_bg, (0,0))
                self.pause_overlay.draw(screen)
                if self._transition:
                    self._transition.update()
                    self._transition.draw(screen)
            if self._toast:
                t = time.time() - self._toast["start"]
                total = self._toast["dur"]
                if t > total:
                    self._toast = None
                else:
                    fade_in = 0.3
                    fade_out = 0.3
                    y = 60
                    alpha = 1.0
                    if t < fade_in:
                        prog = ease_out_cubic(t / fade_in)
                        y = lerp(-40, 60, prog)
                        alpha = prog
                    elif t > total - fade_out:
                        prog = ease_out_cubic((t - (total - fade_out)) / fade_out)
                        y = lerp(60, -40, prog)
                        alpha = 1 - prog
                    fh = FONT_TOAST.get_height()
                    rect = pygame.Rect(0, 0, min(960, screen.get_width()-120), fh + 48)
                    rect.center = (screen.get_width()//2, int(y))
                    box = pygame.Surface(rect.size, pygame.SRCALPHA)
                    pygame.draw.rect(box, (0,0,0,int(200*alpha)), box.get_rect(), border_radius=10)
                    icon_map = {"info":"i", "success":"v", "error":"!", "warning":"!"}
                    col_map = {"info": BLUE, "success": GREEN, "error": RED, "warning": ORANGE}
                    icon = icon_map.get(self._toast["kind"], "i")
                    col = col_map.get(self._toast["kind"], WHITE)
                    icon_y = (rect.height - fh)//2
                    _draw_text(box, icon, FONT_TOAST, col, topleft=(10, icon_y))
                    _draw_text(box, self._toast["msg"], FONT_TOAST, WHITE, topleft=(10 + fh + 20, icon_y))
                    box.set_alpha(int(255*alpha))
                    screen.blit(box, rect.topleft)
            show_custom = isinstance(self.scene, (MainMenu, ScoresScene)) and not self.paused
            pygame.mouse.set_visible(not show_custom)
            if show_custom:
                self.cursor.update(dt)
                self.cursor.draw(screen)
            pygame.display.flip()
        pygame.quit()

if __name__ == "__main__":
    App().run()
