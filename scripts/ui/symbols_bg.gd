extends Control
class_name SymbolsBg
# ============================================================
# SYMBOLS BG — Fond animé : symboles mathématiques flottants.
# 4 couches parallaxe (vitesses 8/16/24/32 px/s), 12 symboles par couche.
# with_colors = true  →  style 0 du Python (teinte bleue + symboles)
# with_colors = false →  style 1 du Python (symboles seulement)
# Utilise BLEND_MODE_ADD pour l'effet lumineux.
# ============================================================

const SYMBOLS := ["1","2","3","4","5","6","7","8","9","+","−","×","÷","=","(",")","%"]
const N_PER_LAYER  := 12
const LAYER_SPEEDS := [8.0, 16.0, 24.0, 32.0]

var with_colors: bool = true

var _layers: Array = []
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_right  = 1.0
	anchor_bottom = 1.0
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat
	_rng.randomize()
	call_deferred("_init_symbols")
	set_process(true)

func _init_symbols() -> void:
	var sz := get_viewport_rect().size
	_layers.clear()
	for li in LAYER_SPEEDS.size():
		var spd: float = LAYER_SPEEDS[li]
		var layer: Array = []
		for _i in N_PER_LAYER:
			layer.append({
				"x":    _rng.randf() * sz.x,
				"y":    _rng.randf() * sz.y,
				"vx":   _rng.randf_range(-spd * 0.18, spd * 0.18),
				"vy":   -spd * (0.80 + _rng.randf() * 0.40),
				"char": SYMBOLS[_rng.randi() % SYMBOLS.size()],
				"alpha": _rng.randf_range(0.06, 0.16),
				"size": _rng.randf_range(18.0, 46.0),
				"zoom": 1.0 + _rng.randf_range(-0.03, 0.03),
			})
		_layers.append(layer)

func _process(delta: float) -> void:
	if not visible or _layers.is_empty(): return
	var sz := get_viewport_rect().size
	for layer in _layers:
		for sym in layer:
			sym.x += float(sym.vx) * delta
			sym.y += float(sym.vy) * delta
			if sym.y < -60.0:        sym.y = sz.y + 60.0
			if sym.y > sz.y + 60.0: sym.y = -60.0
			if sym.x < -60.0:        sym.x = sz.x + 60.0
			if sym.x > sz.x + 60.0: sym.x = -60.0
	queue_redraw()

func _draw() -> void:
	# Teinte bleue additionnelle pour le style "couleurs"
	if with_colors:
		draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size),
				Color(0.0, 0.04, 0.10, 0.25))

	var f := ThemeDB.fallback_font
	for layer in _layers:
		for sym in layer:
			var fsz := int(float(sym.size) * float(sym.zoom))
			var col := Color(1.0, 1.0, 1.0, float(sym.alpha))
			draw_string(f, Vector2(float(sym.x), float(sym.y)),
					sym.char, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, col)
