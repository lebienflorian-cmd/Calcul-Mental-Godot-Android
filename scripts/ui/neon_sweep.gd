extends Control
class_name NeonSweep
# ============================================================
# NEON SWEEP — Lueur verte animée autour du panneau de calcul.
# • Mode continu  : halo statique + segment qui parcourt le périmètre.
# • Mode flash    : 2 points antipodaux rapides lors d'une bonne réponse.
# Utilise BLEND_MODE_ADD pour l'effet néon.
# ============================================================

var panel_rect: Rect2 = Rect2()

const SWEEP_SPEED  := 700.0    # px / s — continu
const SWEEP_LEN    := 220.0    # longueur segment continu (px)
const FLASH_SPEED  := 1400.0   # px / s — flash correct
const FLASH_LEN    := 200.0    # longueur segment flash (px)
const FLASH_DUR    := 0.80     # durée totale du flash (s)
const NEON_COL     := Color(0.0, 1.0, 0.45, 1.0)

var _sweep_pos: float = 0.0
var _flash_time_left: float = 0.0
var _flash_pos: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_right  = 1.0
	anchor_bottom = 1.0
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat
	set_process(true)

func trigger_flash() -> void:
	_flash_time_left = FLASH_DUR
	_flash_pos = _sweep_pos
	visible = true

func _process(delta: float) -> void:
	var w := panel_rect.size.x
	var h := panel_rect.size.y
	if w <= 0.0 or h <= 0.0: return
	var perimeter := 2.0 * (w + h)

	# Avance le sweep continu (même quand invisible — référence pour le flash)
	_sweep_pos = fmod(_sweep_pos + SWEEP_SPEED * delta, perimeter)

	# Avance le flash
	if _flash_time_left > 0:
		_flash_time_left = maxf(0.0, _flash_time_left - delta)
		_flash_pos = fmod(_flash_pos + FLASH_SPEED * delta, perimeter)
		if _flash_time_left <= 0.0:
			# Flash terminé : rétablit la visibilité selon l'option
			visible = bool(GameState.options.show_neon)

	if visible:
		queue_redraw()

func _draw() -> void:
	var r := panel_rect
	if r.size.x <= 0.0 or r.size.y <= 0.0: return
	var w := r.size.x
	var h := r.size.y
	var ox := r.position.x
	var oy := r.position.y
	var perimeter := 2.0 * (w + h)

	# ── Sweep continu ──────────────────────────────────────────
	if bool(GameState.options.show_neon):
		# Halo statique : 3 rectangles concentriques
		for i in 3:
			var exp: float = float(i + 1) * 4.5
			var alpha: float = 0.10 - float(i) * 0.025
			var c := Color(NEON_COL.r, NEON_COL.g, NEON_COL.b, alpha)
			draw_rect(Rect2(ox - exp, oy - exp, w + exp * 2.0, h + exp * 2.0),
					c, false, 3.0 - float(i) * 0.8)

		# Segment mobile + 2 traînes
		for seg in 3:
			var trail_off := float(seg) * (SWEEP_LEN * 0.38)
			var pos := fmod(_sweep_pos - trail_off, perimeter)
			if pos < 0.0: pos += perimeter
			var seg_len := SWEEP_LEN * (1.0 - float(seg) * 0.28)
			var alpha_fac := 1.0 - float(seg) * 0.38
			var col := Color(NEON_COL.r, NEON_COL.g, NEON_COL.b, 0.95 * alpha_fac)
			var thick := 4.5 - float(seg) * 1.2
			_draw_perimeter_segment(ox, oy, w, h, perimeter, pos, seg_len, col, thick)

	# ── Flash correct : 2 points antipodaux ──────────────────
	if _flash_time_left > 0:
		var progress := 1.0 - _flash_time_left / FLASH_DUR   # 0 → 1
		var alpha_mult: float
		if progress < 0.15:
			alpha_mult = progress / 0.15
		elif progress > 0.65:
			alpha_mult = (1.0 - progress) / 0.35
		else:
			alpha_mult = 1.0
		var flash_col := Color(0.0, 1.0, 0.45, 0.95 * alpha_mult)
		var thick := 7.0
		_draw_perimeter_segment(ox, oy, w, h, perimeter, _flash_pos, FLASH_LEN, flash_col, thick)
		var second_pos := fmod(_flash_pos + perimeter * 0.5, perimeter)
		_draw_perimeter_segment(ox, oy, w, h, perimeter, second_pos, FLASH_LEN, flash_col, thick)

func _draw_perimeter_segment(ox: float, oy: float, w: float, h: float,
		perimeter: float, start: float, length: float,
		col: Color, thickness: float) -> void:
	var steps := int(length / 5.0) + 2
	var prev := _perim_point(ox, oy, w, h, perimeter, start)
	for i in range(1, steps + 1):
		var t := start + float(i) / float(steps) * length
		var pt := _perim_point(ox, oy, w, h, perimeter, t)
		draw_line(prev, pt, col, thickness, true)
		prev = pt

func _perim_point(ox: float, oy: float, w: float, h: float,
		perimeter: float, t: float) -> Vector2:
	t = fmod(t, perimeter)
	if t < 0.0: t += perimeter
	if t < w:              return Vector2(ox + t,         oy)
	elif t < w + h:        return Vector2(ox + w,         oy + (t - w))
	elif t < 2.0 * w + h:  return Vector2(ox + w - (t - w - h), oy + h)
	else:                  return Vector2(ox,              oy + h - (t - 2.0 * w - h))
