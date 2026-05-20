extends Control

signal resumed
signal quitted
signal replayed

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	anchor_right = 1.0
	anchor_bottom = 1.0

	var vp := get_viewport_rect().size
	var sc := ThemeManager.ui_scale

	# ── Fond semi-transparent ───────────────────────────────
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.65)
	bg.anchor_right = 1.0; bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	# ── Panneau central (88% largeur, vraiment centré V+H) ─
	var pw := vp.x * 0.88
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5; panel.anchor_right = 0.5
	panel.anchor_top = 0.5;  panel.anchor_bottom = 0.5
	panel.offset_left = -pw * 0.5; panel.offset_right = pw * 0.5
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var pad := ThemeManager.scaled_i(24)
	panel.add_theme_stylebox_override("panel",
			ThemeManager.sbox(ThemeManager.SURFACE,
					ThemeManager.scaled_i(20),
					pad, pad, pad, pad,
					Color(ThemeManager.ACCENT.r, ThemeManager.ACCENT.g,
							ThemeManager.ACCENT.b, 0.35), 2))
	add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", ThemeManager.scaled_i(16))
	panel.add_child(vb)

	# ── En-tête : icône ❚❚ dans un cercle + "Pause" ────────
	var header := HBoxContainer.new()
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_theme_constant_override("separation", ThemeManager.scaled_i(14))
	vb.add_child(header)

	var pause_icon_sz := ThemeManager.scaled_i(52)
	var pause_icon := PanelContainer.new()
	pause_icon.custom_minimum_size = Vector2(pause_icon_sz, pause_icon_sz)
	pause_icon.add_theme_stylebox_override("panel",
			ThemeManager.sbox(ThemeManager.SURFACE_2,
					ThemeManager.scaled_i(26), 0, 0, 0, 0,
					ThemeManager.BORDER_2, 2))
	header.add_child(pause_icon)

	var pause_lbl_icon := Label.new()
	pause_lbl_icon.text = "❚❚"
	pause_lbl_icon.add_theme_color_override("font_color", ThemeManager.TEXT)
	pause_lbl_icon.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_LARGE))
	pause_lbl_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_lbl_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pause_lbl_icon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pause_lbl_icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pause_icon.add_child(pause_lbl_icon)

	var title := Label.new()
	title.text = "Pause"
	title.add_theme_color_override("font_color", ThemeManager.TEXT)
	title.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_TITLE))
	title.add_theme_font_override("font", ThemeDB.fallback_font)
	header.add_child(title)

	# ── Toggles Musique & Bruitages ─────────────────────────
	var toggles := VBoxContainer.new()
	toggles.add_theme_constant_override("separation", ThemeManager.scaled_i(8))
	vb.add_child(toggles)

	# ♪ pour musique, ▸)) pour son (alternative robuste au 🔊 emoji)
	_add_toggle_row(toggles, "♪", "Musique", GameState.options.music_enabled, func(v: bool):
		GameState.set_option("music_enabled", v)
		if v: AudioManager.play_music("game")
		else: AudioManager.stop_music())

	_add_toggle_row(toggles, "♫", "Bruitages", GameState.options.sfx_enabled, func(v: bool):
		GameState.set_option("sfx_enabled", v))

	_add_toggle_row(toggles, "◈", "Lumière verte continue", bool(GameState.options.show_neon), func(v: bool):
		GameState.set_option("show_neon", v))

	_add_toggle_row(toggles, "✦", "Lumière verte si correct", bool(GameState.options.green_correct), func(v: bool):
		GameState.set_option("green_correct", v))

	if bool(GameState.options.op_div):
		_add_toggle_row(toggles, "÷", "Fractions", bool(GameState.options.show_fractions), func(v: bool):
			GameState.set_option("show_fractions", v))

	_add_toggle_row(toggles, "❋", "Fond parallaxe", bool(GameState.options.show_parallax), func(v: bool):
		GameState.set_option("show_parallax", v))

	# ── Séparateur fin ──────────────────────────────────────
	var sep := HSeparator.new()
	sep.add_theme_stylebox_override("separator",
			ThemeManager.make_hsep_style(
					Color(ThemeManager.BORDER.r, ThemeManager.BORDER.g,
							ThemeManager.BORDER.b, 0.40)))
	sep.add_theme_constant_override("separation", ThemeManager.scaled_i(4))
	vb.add_child(sep)

	# ── Boutons d'action ────────────────────────────────────
	_add_action_btn(vb, "play",    "Continuer", ThemeManager.SUCCESS,
			func(): emit_signal("resumed"))
	_add_action_btn(vb, "replay",  "Rejouer",   ThemeManager.ACCENT,
			func(): emit_signal("replayed"))
	_add_action_btn(vb, "exit",    "Quitter",   ThemeManager.ERROR,
			func(): emit_signal("quitted"))

# ── Toggle row : icône + label + switch ─────────────────────
func _add_toggle_row(parent: Node, icon_text: String, label: String,
		active: bool, on_change: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", ThemeManager.scaled_i(14))
	row.custom_minimum_size = Vector2(0, ThemeManager.scaled_i(50))
	parent.add_child(row)

	# Icône
	var ic := Label.new()
	ic.text = icon_text
	ic.add_theme_color_override("font_color", ThemeManager.ACCENT)
	ic.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_LARGE))
	ic.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ic.custom_minimum_size = Vector2(ThemeManager.scaled_i(32), 0)
	ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(ic)

	# Label
	var lbl := Label.new()
	lbl.text = label
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", ThemeManager.TEXT)
	lbl.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_MED))
	row.add_child(lbl)

	# Toggle switch
	var sw := _SwitchDrawer.new()
	sw.active = active
	sw.custom_minimum_size = Vector2(
			ThemeManager.scaled_i(ThemeManager.SWITCH_WIDTH),
			ThemeManager.scaled_i(ThemeManager.SWITCH_HEIGHT))
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sw)

	# Clic sur toute la ligne
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			sw.active = not sw.active
			sw.queue_redraw()
			AudioManager.play_sfx("click")
			on_change.call(sw.active))

# ── Bouton d'action pleine largeur ──────────────────────────
func _add_action_btn(parent: Node, icon_name: String, label: String,
		color: Color, cb: Callable) -> void:
	var btn := Button.new()
	btn.text = ""
	var btn_h := ThemeManager.scaled_i(62)
	btn.custom_minimum_size = Vector2(0, btn_h)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var r := ThemeManager.scaled_i(14)
	btn.add_theme_stylebox_override("normal",
			ThemeManager.sbox(color, r,
					ThemeManager.scaled_i(16), ThemeManager.scaled_i(16),
					ThemeManager.scaled_i(8),  ThemeManager.scaled_i(8),
					color.lightened(0.15), 2))
	btn.add_theme_stylebox_override("hover",
			ThemeManager.sbox(color.lightened(0.08), r,
					ThemeManager.scaled_i(16), ThemeManager.scaled_i(16),
					ThemeManager.scaled_i(8),  ThemeManager.scaled_i(8),
					color.lightened(0.25), 2))
	btn.add_theme_stylebox_override("pressed",
			ThemeManager.sbox(color.darkened(0.15), r,
					ThemeManager.scaled_i(16), ThemeManager.scaled_i(16),
					ThemeManager.scaled_i(8),  ThemeManager.scaled_i(8),
					color, 2))

	# Contenu centré : icône vectorielle + label
	var center := CenterContainer.new()
	center.anchor_right = 1.0; center.anchor_bottom = 1.0
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(center)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", ThemeManager.scaled_i(12))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(row)

	# Icône vectorielle (taille uniforme pour alignement)
	var ic := _PauseIconDrawer.new()
	ic.icon_name = icon_name
	ic.color = Color.WHITE
	var isz := ThemeManager.scaled_i(28)
	ic.custom_minimum_size = Vector2(isz, isz)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(ic)

	var lbl := Label.new()
	lbl.text = label
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_LARGE))
	lbl.add_theme_font_override("font", ThemeDB.fallback_font)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl)

	btn.pressed.connect(func():
		AudioManager.play_sfx("click")
		cb.call())
	parent.add_child(btn)

# ── Input ───────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_BACK or event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			emit_signal("resumed")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		emit_signal("resumed")

# ════════════════════════════════════════════════════════════
# Switch drawer (copie de celui de options_scene)
# ════════════════════════════════════════════════════════════
class _SwitchDrawer extends Control:
	var active: bool = false

	func _ready() -> void:
		resized.connect(queue_redraw)
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w <= 0 or h <= 0:
			return
		var bg := ThemeManager.ACCENT if active else ThemeManager.SURFACE_3
		_draw_capsule(Vector2.ZERO, Vector2(w, h), bg)
		var pad: float = maxf(2.0, h * 0.10)
		var k: float = h - pad * 2.0
		var kx: float = (w - k - pad) if active else pad
		draw_circle(Vector2(kx + k / 2.0, h / 2.0), k / 2.0, Color.WHITE)

	func _draw_capsule(pos: Vector2, sz: Vector2, col: Color) -> void:
		var r: float = sz.y / 2.0
		draw_rect(Rect2(pos + Vector2(r, 0), Vector2(sz.x - 2 * r, sz.y)), col)
		draw_circle(pos + Vector2(r, r), r, col)
		draw_circle(pos + Vector2(sz.x - r, r), r, col)

# ════════════════════════════════════════════════════════════
# Icônes vectorielles pour les boutons d'action
# ════════════════════════════════════════════════════════════
class _PauseIconDrawer extends Control:
	var icon_name: String = ""
	var color: Color = Color.WHITE

	func _ready() -> void:
		resized.connect(queue_redraw)
		queue_redraw()

	func _draw() -> void:
		var sz := size
		if sz.x <= 0 or sz.y <= 0: return
		var c := Vector2(sz.x / 2.0, sz.y / 2.0)
		var r: float = minf(sz.x, sz.y) / 2.0
		match icon_name:
			"play":   _draw_play(c, r)
			"replay": _draw_replay(c, r)
			"exit":   _draw_exit(c, r)

	func _stroke() -> float:
		return maxf(2.0, size.x * 0.10)

	# Triangle play (légèrement plus petit)
	func _draw_play(c: Vector2, r: float) -> void:
		var a := r * 0.65
		var pts := PackedVector2Array([
			c + Vector2(-a * 0.55, -a * 0.80),
			c + Vector2( a * 0.85, 0),
			c + Vector2(-a * 0.55,  a * 0.80),
		])
		draw_colored_polygon(pts, color)

	# Icône replay (cercle avec flèche)
	func _draw_replay(c: Vector2, r: float) -> void:
		var s := _stroke()
		var rr := r * 0.78
		# Arc principal (3/4 de cercle, ouvert en haut à droite)
		draw_arc(c, rr, deg_to_rad(-30), deg_to_rad(270), 32, color, s, true)
		# Pointe de flèche
		var tip_angle := deg_to_rad(-30)
		var tip := c + Vector2(cos(tip_angle), sin(tip_angle)) * rr
		var bk := rr * 0.42
		# Triangle pointe
		var p1 := tip + Vector2(-bk, -bk * 0.10)
		var p2 := tip + Vector2(-bk * 0.10, -bk)
		var tri := PackedVector2Array([tip, p1, p2])
		draw_colored_polygon(tri, color)

	# Icône exit (porte avec flèche →)
	func _draw_exit(c: Vector2, r: float) -> void:
		var s := _stroke()
		# Porte : rectangle ouvert à droite
		var door_w := r * 0.85
		var door_h := r * 1.30
		var left := c.x - door_w * 0.55
		var top := c.y - door_h / 2.0
		# Trois côtés (haut, gauche, bas) — pas de côté droit
		draw_line(Vector2(left, top), Vector2(left + door_w * 0.65, top), color, s, true)
		draw_line(Vector2(left, top), Vector2(left, top + door_h), color, s, true)
		draw_line(Vector2(left, top + door_h),
				Vector2(left + door_w * 0.65, top + door_h), color, s, true)
		# Flèche sortante (→) qui dépasse la porte
		var ax := left + door_w * 0.15
		var ay := c.y
		var arrow_end := c.x + r * 0.80
		draw_line(Vector2(ax, ay), Vector2(arrow_end, ay), color, s, true)
		# Pointe
		var tip_sz := r * 0.30
		draw_line(Vector2(arrow_end, ay),
				Vector2(arrow_end - tip_sz, ay - tip_sz * 0.8), color, s, true)
		draw_line(Vector2(arrow_end, ay),
				Vector2(arrow_end - tip_sz, ay + tip_sz * 0.8), color, s, true)
