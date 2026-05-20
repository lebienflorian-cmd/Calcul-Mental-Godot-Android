extends Control
class_name MathRenderer
# ============================================================
# MATH RENDERER — Affiche une expression arithmétique selon le mode :
#   0 = Normal  (texte, identique à l'ancien Label)
#   1 = Fractions (inline avec barre de fraction pour ÷)
#   2 = Colonne   (notation scolaire alignée à droite)
# Utilise un arbre {type, op, left, right, v} produit par CalcGenerator.
# Si l'arbre est vide, fallback sur fallback_text (draw_string).
# ============================================================

var expr_tree: Dictionary = {}
var fallback_text: String = ""
var display_mode: int = 0       # 0 Normal 1 Fraction 2 Colonne
var font_size: int = 72
var text_color: Color = Color.WHITE
var op_color: Color = Color(1, 1, 1, 0.6)

# Priorités pour la décision de parenthèses
const _PRIO := {"+": 1, "−": 1, "×": 2, "÷": 2}

# Constantes de layout
const _GAP_OP   := 10.0   # espace autour d'un opérateur inline
const _FRAC_GAP := 6.0    # espace entre numérateur/dénominateur et barre
const _FRAC_BAR := 3.0    # épaisseur barre de fraction
const _PAREN_W  := 0.35   # largeur d'une parenthèse = facteur × font_size

func _ready() -> void:
	resized.connect(queue_redraw)

func _draw() -> void:
	if size.x <= 0 or size.y <= 0:
		return
	var font := ThemeDB.fallback_font
	if expr_tree.is_empty() or display_mode == 0:
		_draw_fallback(font)
		return
	var saved_fs := font_size
	if display_mode == 2:
		_draw_column(font)
	else:
		# Mode Fraction (1) — scale to fit then render
		var m := _measure(expr_tree, font)
		var tw: float = float(m.w)
		var th: float = float(m.above) + float(m.below)
		if tw > 0 and th > 0:
			var scale := minf(size.x * 0.90 / tw, size.y * 0.90 / th)
			if scale < 1.0:
				font_size = max(18, int(font_size * scale))
				m = _measure(expr_tree, font)
		var x: float = (size.x - float(m.w)) / 2.0
		var by: float = size.y / 2.0 + (float(m.above) - float(m.below)) / 2.0
		_render(expr_tree, x, by, font, -1)
	font_size = saved_fs

# ── Fallback texte ──────────────────────────────────────────
func _draw_fallback(font: Font) -> void:
	var txt := fallback_text
	if txt.is_empty(): return
	var fs := _adaptive_font_size(txt.length())
	var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x := 8.0 if txt.begins_with("[") else (size.x - tw) / 2.0
	var by := size.y / 2.0 + fs * 0.35
	draw_string(font, Vector2(x, by), txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, text_color)

func _adaptive_font_size(l: int) -> int:
	if l <= 8:    return font_size
	if l <= 14:   return int(font_size * 0.74)
	if l <= 22:   return int(font_size * 0.56)
	if l <= 32:   return int(font_size * 0.41)
	return int(font_size * 0.33)

# ── Mesure récursive ─────────────────────────────────────────
# Retourne {w, above, below} en pixels.
func _measure(node: Dictionary, font: Font, parent_op: String = "") -> Dictionary:
	if node.type == "num":
		return _measure_str(str(node.v) if int(node.v) >= 0 else "(%d)" % int(node.v), font, font_size)

	var op: String = node.op
	var is_frac := (op == "÷" and display_mode == 1)

	if is_frac:
		var nm := _measure(node.left,  font)
		var dm := _measure(node.right, font)
		var w: float = maxf(float(nm.w), float(dm.w)) + _FRAC_GAP * 2
		return {
			"w":     w,
			"above": float(nm.above) + float(nm.below) + _FRAC_GAP + _FRAC_BAR,
			"below": float(dm.above) + float(dm.below) + _FRAC_GAP,
		}

	# Inline op
	var need_paren_l := _needs_paren(node.left,  op, true)
	var need_paren_r := _needs_paren(node.right, op, false)
	var lm := _measure(node.left,  font, op)
	var rm := _measure(node.right, font, op)
	var op_w: float = float(_measure_str(" %s " % op, font, font_size).w)
	var pw: float = _paren_w()
	var w: float = float(lm.w) + op_w + float(rm.w)
	if need_paren_l: w += pw * 2
	if need_paren_r: w += pw * 2
	return {
		"w":     w,
		"above": maxf(float(lm.above), float(rm.above)),
		"below": maxf(float(lm.below), float(rm.below)),
	}

func _measure_str(s: String, font: Font, fs: int) -> Dictionary:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	return {"w": w, "above": fs * 0.80, "below": fs * 0.20}

# ── Rendu récursif ──────────────────────────────────────────
# x = bord gauche du nœud, by = ligne de base.
# parent_prio : priorité de l'opérateur parent (pour décider des parenthèses).
func _render(node: Dictionary, x: float, by: float, font: Font, parent_prio: int) -> void:
	if node.type == "num":
		var s := str(node.v) if int(node.v) >= 0 else "(%d)" % int(node.v)
		draw_string(font, Vector2(x, by), s,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
		return

	var op: String = node.op
	var is_frac := (op == "÷" and display_mode == 1)

	if is_frac:
		var nm := _measure(node.left,  font)
		var dm := _measure(node.right, font)
		var mw  := _measure(node, font)
		var bar_y := by - _FRAC_GAP - _FRAC_BAR / 2.0
		# Barre
		draw_line(Vector2(x, bar_y), Vector2(x + mw.w, bar_y),
				text_color, _FRAC_BAR)
		# Numérateur centré au-dessus
		var nx: float = x + (float(mw.w) - float(nm.w)) / 2.0
		var nby: float = bar_y - _FRAC_BAR / 2.0 - _FRAC_GAP - float(nm.below)
		_render(node.left, nx, nby, font, -1)
		# Dénominateur centré en-dessous
		var dx: float = x + (float(mw.w) - float(dm.w)) / 2.0
		var dby: float = bar_y + _FRAC_BAR / 2.0 + _FRAC_GAP + float(dm.above)
		_render(node.right, dx, dby, font, -1)
		return

	# Inline
	var need_paren_l := _needs_paren(node.left,  op, true)
	var need_paren_r := _needs_paren(node.right, op, false)
	var lm := _measure(node.left,  font, op)
	var rm := _measure(node.right, font, op)
	var op_str := " %s " % op
	var op_w: float = float(_measure_str(op_str, font, font_size).w)
	var pw: float = _paren_w()

	var cx := x
	if need_paren_l:
		draw_string(font, Vector2(cx, by), "(", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, op_color)
		cx += pw
	_render(node.left, cx, by, font, _PRIO.get(op, 1))
	cx += lm.w
	if need_paren_l:
		draw_string(font, Vector2(cx, by), ")", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, op_color)
		cx += pw

	draw_string(font, Vector2(cx, by), op_str,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, op_color)
	cx += op_w

	if need_paren_r:
		draw_string(font, Vector2(cx, by), "(", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, op_color)
		cx += pw
	_render(node.right, cx, by, font, _PRIO.get(op, 1))
	if need_paren_r:
		cx += rm.w
		draw_string(font, Vector2(cx, by), ")", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, op_color)

# ── Mode colonne ────────────────────────────────────────────
func _draw_column(font: Font) -> void:
	if not _is_simple_binop(expr_tree):
		# Fallback: inline fraction render with scaling
		var m := _measure(expr_tree, font)
		var tw: float = float(m.w)
		var th: float = float(m.above) + float(m.below)
		if tw > 0 and th > 0:
			var scale := minf(size.x * 0.90 / tw, size.y * 0.90 / th)
			if scale < 1.0:
				font_size = max(18, int(font_size * scale))
				m = _measure(expr_tree, font)
		var x: float = (size.x - float(m.w)) / 2.0
		var by: float = size.y / 2.0 + (float(m.above) - float(m.below)) / 2.0
		_render(expr_tree, x, by, font, -1)
		return

	var op: String = expr_tree.op
	var a_str := str(int(expr_tree.left.v))
	var b_str := str(abs(int(expr_tree.right.v)))
	var b_neg: bool = int(expr_tree.right.v) < 0

	var display_op := op
	if op == "−" and b_neg:
		display_op = "+"
	elif op == "+" and b_neg:
		display_op = "−"

	# Adaptive font scaling: 3 rows × row_h must fit vertically, col_w must fit horizontally
	var max_digits: int = maxi(a_str.length(), b_str.length()) + 1
	var char_w: float = font.get_string_size("0", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var col_w: float = float(max_digits + 2) * char_w
	var block_h: float = float(font_size) * 3.9   # 3 × row_h where row_h = fs × 1.3
	if col_w > 0 and block_h > 0:
		var scale := minf(size.x * 0.90 / col_w, size.y * 0.92 / block_h)
		if scale < 1.0:
			font_size = max(18, int(font_size * scale))
			char_w = font.get_string_size("0", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x

	var row_h: float = float(font_size) * 1.3
	col_w = float(max_digits + 2) * char_w
	var cx: float = (size.x - col_w) / 2.0
	var right_edge: float = cx + col_w

	# Vertical layout — center the 3-row block
	var start_y: float = (size.y - row_h * 3.0) / 2.0
	var by1: float = start_y + float(font_size) * 0.80           # baseline row 1
	var by2: float = start_y + row_h + float(font_size) * 0.80   # baseline row 2
	var bar_y: float = start_y + row_h * 2.0 + float(font_size) * 0.12  # just below row 2
	var by3: float = start_y + row_h * 2.0 + float(font_size) * 1.00   # baseline "?"

	# Row 1: a right-aligned
	var aw: float = font.get_string_size(a_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, Vector2(right_edge - aw, by1), a_str,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)

	# Row 2: operator at left, b right-aligned
	draw_string(font, Vector2(cx, by2), display_op,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, op_color)
	var bw: float = font.get_string_size(b_str, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, Vector2(right_edge - bw, by2), b_str,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)

	# Separator bar (from operator column to just past numbers)
	draw_line(Vector2(cx, bar_y), Vector2(right_edge + char_w * 0.3, bar_y),
			text_color, 2.5)

	# Row 3: ? centered
	var q_w: float = font.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, Vector2(size.x * 0.5 - q_w * 0.5, by3), "?",
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, op_color)

# ── Helpers ─────────────────────────────────────────────────
func _needs_paren(child: Dictionary, parent_op: String, is_left: bool) -> bool:
	if child.get("type", "") != "op": return false
	var child_prio: int = _PRIO.get(child.op, 1)
	var parent_prio: int = _PRIO.get(parent_op, 1)
	if child_prio < parent_prio: return true
	# Associativité : (a − b) − c ≠ a − (b − c)
	if not is_left and child_prio == parent_prio and parent_op in ["−", "÷"]:
		return true
	return false

func _paren_w() -> float:
	return font_size * _PAREN_W

func _is_simple_binop(node: Dictionary) -> bool:
	if node.get("type", "") != "op": return false
	if node.op not in ["+", "−", "×"]: return false
	if node.left.get("type", "")  != "num": return false
	if node.right.get("type", "") != "num": return false
	return true
