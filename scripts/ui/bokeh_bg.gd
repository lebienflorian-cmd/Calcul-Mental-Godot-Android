extends Control
class_name BokehBg
# ============================================================
# BOKEH BG — Fond parallaxe avec orbes lumineux en mouvement.
# 18 orbes radiales (gradient concentrique), vitesse ∝ profondeur.
# Utilise BLEND_MODE_ADD pour l'effet lumineux sans surbrillance.
# ============================================================

const N_ORBS := 18
const ORB_COLORS := [
	Color(0.05, 0.20, 0.90),   # bleu
	Color(0.90, 0.42, 0.04),   # orange
	Color(0.10, 0.55, 0.95),   # bleu clair
]

var _orbs: Array = []
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_right  = 1.0
	anchor_bottom = 1.0
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat
	_rng.randomize()
	call_deferred("_init_orbs")
	set_process(true)

func _init_orbs() -> void:
	var sz := get_viewport_rect().size
	_orbs.clear()
	for i in N_ORBS:
		var depth: float = 0.25 + _rng.randf() * 0.75  # 0.25=loin/lent … 1.0=proche/rapide
		var radius: float = 35.0 + (1.0 - depth) * 110.0  # loin = gros orbe
		_orbs.append({
			"x":      _rng.randf() * sz.x,
			"y":      _rng.randf() * sz.y,
			"vx":     _rng.randf_range(-1.0, 1.0) * depth * 22.0,
			"vy":     _rng.randf_range(-0.6, 0.6) * depth * 14.0,
			"radius": radius,
			"depth":  depth,
			"color":  ORB_COLORS[i % ORB_COLORS.size()],
		})

func _process(delta: float) -> void:
	if not visible or _orbs.is_empty(): return
	var sz := get_viewport_rect().size
	for orb in _orbs:
		orb.x += float(orb.vx) * delta
		orb.y += float(orb.vy) * delta
		var rad := float(orb.radius)
		if orb.x < -rad:       orb.x = sz.x + rad
		if orb.x > sz.x + rad: orb.x = -rad
		if orb.y < -rad:       orb.y = sz.y + rad
		if orb.y > sz.y + rad: orb.y = -rad
	queue_redraw()

func _draw() -> void:
	for orb in _orbs:
		var c    := orb.color as Color
		var r    := float(orb.radius)
		var dep  := float(orb.depth)
		var ctr  := Vector2(float(orb.x), float(orb.y))
		var rings := 12
		for i in rings:
			var t      := float(i + 1) / float(rings)   # 1/n … 1
			var ring_r := r * (1.0 - t * 0.88)
			var alpha  := t * t * 0.07 * dep
			draw_circle(ctr, ring_r, Color(c.r, c.g, c.b, alpha))
