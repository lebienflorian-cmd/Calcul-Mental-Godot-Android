extends Node
# ============================================================
# THEME — Couleurs, polices, styles. Singleton autoload.
# ============================================================

const BG          := Color("#1a1d23")
const SURFACE     := Color("#262a32")
const SURFACE_2   := Color("#2f343e")
const TEXT        := Color("#ffffff")
const TEXT_DIM    := Color("#b0b6c0")
const ACCENT      := Color("#4a90e2")
const ACCENT_2    := Color("#f39c12")
const SUCCESS     := Color("#2ecc71")
const ERROR       := Color("#e74c3c")
const WARNING     := Color("#f39c12")
const BORDER      := Color("#3a4050")

# Tailles UI de référence (en pixels @ 1280x800)
const FONT_TITLE  := 56
const FONT_LARGE  := 36
const FONT_MED    := 24
const FONT_SMALL  := 18

var ui_scale: float = 1.0

func _ready() -> void:
	get_viewport().size_changed.connect(_on_size_changed)
	_on_size_changed()

func _on_size_changed() -> void:
	var s := get_viewport().get_visible_rect().size
	# Echelle basée sur le min entre largeur/hauteur ratio
	var sx := s.x / 1280.0
	var sy := s.y / 800.0
	ui_scale = clamp(min(sx, sy), 0.5, 2.5)

func make_panel_style(color: Color = SURFACE, radius: int = 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	sb.border_color = BORDER
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	return sb

func make_button_style(color: Color = ACCENT, radius: int = 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb

func scaled(v: float) -> float:
	return v * ui_scale

func scaled_i(v: int) -> int:
	return int(round(v * ui_scale))
