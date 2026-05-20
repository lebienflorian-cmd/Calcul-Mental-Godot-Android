extends Node
# ============================================================
# THEME — Couleurs, polices, styles. Singleton autoload.
# Palette type « bleu nuit » + helpers de spacing / styles.
# ============================================================

# ── Palette ────────────────────────────────────────────────
const BG          := Color("#0b1424")   # fond principal (bleu nuit)
const BG_2        := Color("#0e1a2e")   # variante légèrement plus claire
const SURFACE     := Color("#142238")   # cartes / panneaux
const SURFACE_2   := Color("#1c2c46")   # boutons, dropdowns, champs
const SURFACE_3   := Color("#22344f")   # hover / surface élevée
const TEXT        := Color("#ffffff")
const TEXT_DIM    := Color("#94a3b8")
const ACCENT      := Color("#3b82f6")   # bleu vif (toggles ON, boutons primaires)
const ACCENT_2    := Color("#f59e0b")   # orange (valeurs numériques)
const SUCCESS     := Color("#22c55e")
const ERROR       := Color("#ef4444")   # rouge supprimer
const WARNING     := Color("#f59e0b")
const BORDER      := Color("#1e3354")   # bordures discrètes
const BORDER_2    := Color("#2a4267")   # bordures un peu plus visibles

# ── Tailles UI de référence (en pixels @ 1280×800) ─────────
# NB : sur mobile portrait, ui_scale rend ces valeurs plus grandes
#      relativement à la largeur d'écran (cf. _on_size_changed).
const FONT_TITLE  := 44
const FONT_LARGE  := 32
const FONT_MED    := 24
const FONT_SMALL  := 20
const FONT_TINY   := 16

# ── Spacing & dimensions standard ──────────────────────────
const SPACING_XS  := 6
const SPACING_SM  := 10
const SPACING_MD  := 16
const SPACING_LG  := 24
const SPACING_XL  := 32

const PADDING_CARD       := 22          # padding interne d'une carte
const RADIUS_CARD        := 16
const RADIUS_BTN         := 12
const RADIUS_CHIP        := 22
const RADIUS_SWITCH      := 999         # ovale total

const SECTION_GAP        := 18          # espace vertical entre sections
const FIELD_ROW_HEIGHT   := 56          # hauteur d'une ligne d'option
const HEADER_HEIGHT      := 84          # hauteur de l'en-tête
const SCROLLBAR_WIDTH    := 6

# Tailles internes propres aux contrôles
const CHECKBOX_SIZE      := 32          # case à cocher (~2× la taille texte)
const SECTION_ICON_BOX   := 44          # tuile d'icône de section
const SWITCH_WIDTH       := 56          # largeur d'un toggle switch
const SWITCH_HEIGHT      := 30          # hauteur d'un toggle switch
const SPIN_BTN_SIZE      := 44          # bouton +/− carré
const SPIN_VALUE_WIDTH   := 64          # zone affichant la valeur

# ── Échelle ────────────────────────────────────────────────
var ui_scale: float = 1.0

func _ready() -> void:
	get_viewport().size_changed.connect(_on_size_changed)
	_on_size_changed()

func _on_size_changed() -> void:
	var s := get_viewport().get_visible_rect().size
	if s.y > s.x:
		# Portrait (mobile) : référence 540 px de large.
		# → sur un écran 1080 px, ui_scale ≈ 2.0 — éléments bien gros
		#   mais ne débordent plus à droite.
		ui_scale = clamp(s.x / 540.0, 0.6, 3.0)
	else:
		# Paysage / desktop : référence 1280×800
		ui_scale = clamp(min(s.x / 1280.0, s.y / 800.0), 0.6, 3.0)

# ── Helpers de scaling ─────────────────────────────────────
func scaled(v: float) -> float:
	return v * ui_scale

func scaled_i(v: int) -> int:
	return int(round(v * ui_scale))

func scaled_v2(x: float, y: float) -> Vector2:
	return Vector2(x * ui_scale, y * ui_scale)

# ── Factories de StyleBox ──────────────────────────────────
func make_panel_style(color: Color = SURFACE, radius: int = RADIUS_CARD,
		border: Color = BORDER, border_w: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.corner_radius_top_left     = radius
	sb.corner_radius_top_right    = radius
	sb.corner_radius_bottom_left  = radius
	sb.corner_radius_bottom_right = radius
	sb.border_color = border
	sb.border_width_left   = border_w
	sb.border_width_right  = border_w
	sb.border_width_top    = border_w
	sb.border_width_bottom = border_w
	return sb

func make_button_style(color: Color = ACCENT, radius: int = RADIUS_BTN,
		pad_x: int = 18, pad_y: int = 14) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.corner_radius_top_left     = radius
	sb.corner_radius_top_right    = radius
	sb.corner_radius_bottom_left  = radius
	sb.corner_radius_bottom_right = radius
	sb.content_margin_left   = pad_x
	sb.content_margin_right  = pad_x
	sb.content_margin_top    = pad_y
	sb.content_margin_bottom = pad_y
	return sb

# StyleBox plat à coins arrondis avec marges internes paramétrables.
func sbox(color: Color, radius: int = RADIUS_BTN,
		ml: int = 0, mr: int = 0, mt: int = 0, mb: int = 0,
		border: Color = Color(0,0,0,0), border_w: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.corner_radius_top_left     = radius
	s.corner_radius_top_right    = radius
	s.corner_radius_bottom_left  = radius
	s.corner_radius_bottom_right = radius
	s.content_margin_left   = ml
	s.content_margin_right  = mr
	s.content_margin_top    = mt
	s.content_margin_bottom = mb
	if border.a > 0.0 and border_w > 0:
		s.border_color = border
		s.border_width_left   = border_w
		s.border_width_right  = border_w
		s.border_width_top    = border_w
		s.border_width_bottom = border_w
	return s

# Séparateur horizontal fin (utilisé entre les lignes d'une section).
func make_hsep_style(color: Color = BORDER) -> StyleBoxLine:
	var sl := StyleBoxLine.new()
	sl.color = color
	sl.thickness = 1
	sl.grow_begin = 0
	sl.grow_end   = 0
	return sl
