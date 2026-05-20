extends Control
# ============================================================
# MAIN MENU — Refonte complète :
# • Icônes vectorielles (abacus, play, gear, book, bars, quit)
# • Boutons avec dégradé subtil et bordures arrondies
# • Espacements et proportions fidèles à la référence
# • Profil actif en bas avec conteneur sombre + bordures claires
# ============================================================

var _symbols: Array = []
const SYMBOLS_TEXT := ["1","2","3","4","5","6","7","8","9","+","−","×","÷","="]
var _scan_pos: float = 0.0
var _quit_layer: CanvasLayer = null

func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	AudioManager.play_music("menu")
	_build_ui()
	_init_background()
	set_process(true)

# ── Fond animé ──────────────────────────────────────────────
func _init_background() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in 36:
		var sz := get_viewport_rect().size
		_symbols.append({
			"pos": Vector2(rng.randf() * sz.x, rng.randf() * sz.y),
			"vel": Vector2(rng.randf_range(-8, 8), rng.randf_range(-12, -3)),
			"char": SYMBOLS_TEXT[rng.randi() % SYMBOLS_TEXT.size()],
			"alpha": rng.randf_range(0.06, 0.16),
			"size": rng.randf_range(18, 42),
		})

func _process(delta: float) -> void:
	var sz := get_viewport_rect().size
	for s in _symbols:
		s.pos += s.vel * delta
		if s.pos.y < -50:       s.pos.y = sz.y + 50
		if s.pos.y > sz.y + 50: s.pos.y = -50
		if s.pos.x < -50:       s.pos.x = sz.x + 50
		if s.pos.x > sz.x + 50: s.pos.x = -50
	_scan_pos += delta * 80.0
	if _scan_pos > sz.x + 200: _scan_pos = -200
	queue_redraw()

func _draw() -> void:
	var sz := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, sz), ThemeManager.BG)
	var gc := Color(ThemeManager.BORDER.r, ThemeManager.BORDER.g, ThemeManager.BORDER.b, 0.10)
	var step := 80
	for x in range(0, int(sz.x), step):
		draw_line(Vector2(x, 0), Vector2(x, sz.y), gc, 1)
	for y in range(0, int(sz.y), step):
		draw_line(Vector2(0, y), Vector2(sz.x, y), gc, 1)
	var f := ThemeDB.fallback_font
	for s in _symbols:
		var c := ThemeManager.TEXT; c.a = s.alpha
		draw_string(f, s.pos, s.char, HORIZONTAL_ALIGNMENT_LEFT, -1, int(s.size), c)
	var rect := Rect2(_scan_pos - 80, 0, 160, sz.y)
	draw_rect(rect, Color(ThemeManager.ACCENT.r, ThemeManager.ACCENT.g, ThemeManager.ACCENT.b, 0.03))

# ── Layout ──────────────────────────────────────────────────
func _build_ui() -> void:
	var sc := ThemeManager.ui_scale
	var margin := ThemeManager.scaled_i(18)

	# ScrollContainer pour que le contenu soit scrollable
	var scroll := ScrollContainer.new()
	scroll.anchor_left = 0.0;  scroll.anchor_right  = 1.0
	scroll.anchor_top  = 0.0;  scroll.anchor_bottom = 1.0
	scroll.offset_left = margin; scroll.offset_right = -margin
	scroll.offset_top  = ThemeManager.scaled_i(60)
	scroll.offset_bottom = -ThemeManager.scaled_i(20)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_theme_constant_override("separation", ThemeManager.scaled_i(8))
	scroll.add_child(root)

	# ── HEADER (icône abacus + titre + sous-titre) ──────────
	var header := VBoxContainer.new()
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_theme_constant_override("separation", ThemeManager.scaled_i(8))
	root.add_child(header)

	# Icône abacus dans un conteneur arrondi — bien visible
	var icon_wrap := CenterContainer.new()
	icon_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(icon_wrap)

	var abacus_size := ThemeManager.scaled_i(120)
	var abacus_panel := PanelContainer.new()
	abacus_panel.custom_minimum_size = Vector2(abacus_size, abacus_size)
	abacus_panel.add_theme_stylebox_override("panel",
			ThemeManager.sbox(ThemeManager.SURFACE_2,
					ThemeManager.scaled_i(22), 0, 0, 0, 0,
					ThemeManager.BORDER_2, 2))
	icon_wrap.add_child(abacus_panel)

	var abacus_draw := _AbacusDrawer.new()
	abacus_draw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	abacus_draw.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	abacus_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	abacus_panel.add_child(abacus_draw)

	# Gap après abacus
	var gap1 := Control.new()
	gap1.custom_minimum_size = Vector2(0, ThemeManager.scaled_i(16))
	header.add_child(gap1)

	# Titre "Calcul Mental" — gros et gras
	var title_row := HBoxContainer.new()
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	title_row.add_theme_constant_override("separation", ThemeManager.scaled_i(8))
	header.add_child(title_row)

	var title_fs := ThemeManager.scaled_i(72)

	var t_calc := Label.new()
	t_calc.text = "Calcul"
	t_calc.add_theme_color_override("font_color", ThemeManager.TEXT)
	t_calc.add_theme_font_size_override("font_size", title_fs)
	t_calc.add_theme_font_override("font", ThemeDB.fallback_font)
	title_row.add_child(t_calc)

	var t_mental := Label.new()
	t_mental.text = "Mental"
	t_mental.add_theme_color_override("font_color", ThemeManager.ACCENT)
	t_mental.add_theme_font_size_override("font_size", title_fs)
	t_mental.add_theme_font_override("font", ThemeDB.fallback_font)
	title_row.add_child(t_mental)

	# Sous-titre
	var sub := Label.new()
	sub.text = "Entraîne ta rapidité et ta précision"
	sub.add_theme_color_override("font_color", ThemeManager.TEXT_DIM)
	sub.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_MED))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(sub)

	# Gap avant boutons
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, ThemeManager.scaled_i(28))
	root.add_child(gap2)

	# ── BOUTONS ─────────────────────────────────────────────
	var menu := VBoxContainer.new()
	menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu.add_theme_constant_override("separation", ThemeManager.scaled_i(14))
	root.add_child(menu)

	_add_menu_btn(menu, "play",  Color(0.15, 0.40, 0.95), "Jouer",         _on_play,    true)
	_add_menu_btn(menu, "gear",  ThemeManager.ACCENT,      "Options",       _on_options,  false)
	_add_menu_btn(menu, "book",  Color("#F59E0B"),          "Règles du jeu", _on_rules,   false)
	_add_menu_btn(menu, "bars",  ThemeManager.SUCCESS,      "Scores",        _on_scores,  false)
	_add_menu_btn(menu, "quit",  ThemeManager.ERROR,        "Quitter",       _on_quit,    false)

	# ── PROFIL ACTIF (en bas) ───────────────────────────────
	var gap3 := Control.new()
	gap3.custom_minimum_size = Vector2(0, ThemeManager.scaled_i(16))
	root.add_child(gap3)

	var prof_wrap := CenterContainer.new()
	prof_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(prof_wrap)

	var prof_panel := PanelContainer.new()
	var pp := ThemeManager.scaled_i(10)
	prof_panel.add_theme_stylebox_override("panel",
			ThemeManager.sbox(Color(ThemeManager.SURFACE.r, ThemeManager.SURFACE.g,
					ThemeManager.SURFACE.b, 0.70),
					ThemeManager.scaled_i(20),
					ThemeManager.scaled_i(18), ThemeManager.scaled_i(18),
					ThemeManager.scaled_i(10), ThemeManager.scaled_i(10),
					ThemeManager.BORDER_2, 1))
	prof_wrap.add_child(prof_panel)

	var prof_row := HBoxContainer.new()
	prof_row.add_theme_constant_override("separation", ThemeManager.scaled_i(8))
	prof_panel.add_child(prof_row)

	# Petite icône utilisateur
	var user_ic := _MenuIconDrawer.new()
	user_ic.icon_name = "user"
	user_ic.color = ThemeManager.TEXT_DIM
	var uisz := ThemeManager.scaled_i(20)
	user_ic.custom_minimum_size = Vector2(uisz, uisz)
	user_ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	user_ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prof_row.add_child(user_ic)

	var pf_lbl := Label.new()
	pf_lbl.text = "Profil actif : "
	pf_lbl.add_theme_color_override("font_color", ThemeManager.TEXT_DIM)
	pf_lbl.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_SMALL))
	pf_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prof_row.add_child(pf_lbl)

	var pf_name := Label.new()
	pf_name.text = ProfileManager.current_profile
	pf_name.add_theme_color_override("font_color", ThemeManager.ACCENT)
	pf_name.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_SMALL))
	pf_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prof_row.add_child(pf_name)
	ProfileManager.profile_changed.connect(func(n): pf_name.text = n)

# ── Bouton de menu ──────────────────────────────────────────
func _add_menu_btn(parent: Node, icon_name: String, icon_color: Color,
		label: String, cb: Callable, is_primary: bool) -> void:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var btn_h := ThemeManager.scaled_i(82)
	card.custom_minimum_size = Vector2(0, btn_h)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var radius := ThemeManager.scaled_i(16)
	var bg_color: Color
	var border_color: Color
	if is_primary:
		bg_color = Color(0.18, 0.44, 0.98)
		border_color = Color(0.30, 0.55, 1.0, 0.6)
	else:
		bg_color = ThemeManager.SURFACE
		border_color = ThemeManager.BORDER_2

	var style := ThemeManager.sbox(bg_color, radius,
			ThemeManager.scaled_i(14), ThemeManager.scaled_i(14),
			ThemeManager.scaled_i(10), ThemeManager.scaled_i(10),
			border_color, 2)
	card.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", ThemeManager.scaled_i(16))
	card.add_child(row)

	var sp_l := Control.new()
	sp_l.custom_minimum_size = Vector2(ThemeManager.scaled_i(4), 0)
	row.add_child(sp_l)

	# Icône — plus grande (56px)
	var icon_size := ThemeManager.scaled_i(56)
	var icon_tile := PanelContainer.new()
	icon_tile.custom_minimum_size = Vector2(icon_size, icon_size)
	icon_tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var icon_radius := ThemeManager.scaled_i(28) if is_primary else ThemeManager.scaled_i(12)
	icon_tile.add_theme_stylebox_override("panel",
			ThemeManager.sbox(icon_color, icon_radius, 0, 0, 0, 0,
					icon_color.lightened(0.20), 1))
	row.add_child(icon_tile)

	var icon_draw := _MenuIconDrawer.new()
	icon_draw.icon_name = icon_name
	icon_draw.color = Color.WHITE
	icon_draw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	icon_draw.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	icon_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_tile.add_child(icon_draw)

	# Label
	var text := Label.new()
	text.text = label
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	text.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_LARGE + 4))
	text.add_theme_color_override("font_color", Color.WHITE if is_primary else ThemeManager.TEXT)
	text.add_theme_font_override("font", ThemeDB.fallback_font)
	row.add_child(text)

	# Chevron ›
	var chevron := Label.new()
	chevron.text = "›"
	chevron.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	chevron.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chevron.custom_minimum_size  = Vector2(ThemeManager.scaled_i(32), 0)
	chevron.size_flags_vertical  = Control.SIZE_EXPAND_FILL
	chevron.add_theme_font_size_override("font_size", ThemeManager.scaled_i(44))
	chevron.add_theme_color_override("font_color",
			Color(1, 1, 1, 0.7) if is_primary else ThemeManager.TEXT_DIM)
	row.add_child(chevron)

	# Spacer droit
	var sp_r := Control.new()
	sp_r.custom_minimum_size = Vector2(ThemeManager.scaled_i(4), 0)
	row.add_child(sp_r)

	# Interaction : tap = activer, scroll = pas d'activation, maintien = effet visuel seulement
	var style_normal := style
	var style_pressed := ThemeManager.sbox(bg_color.darkened(0.15), radius,
			ThemeManager.scaled_i(14), ThemeManager.scaled_i(14),
			ThemeManager.scaled_i(10), ThemeManager.scaled_i(10),
			border_color, 2)
	var style_hover := ThemeManager.sbox(bg_color.lightened(0.06), radius,
			ThemeManager.scaled_i(14), ThemeManager.scaled_i(14),
			ThemeManager.scaled_i(10), ThemeManager.scaled_i(10),
			border_color.lightened(0.1), 2)

	var touch_data := {"start_pos": Vector2.ZERO, "touching": false, "dragged": false}

	card.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventScreenTouch:
			if ev.pressed:
				touch_data.start_pos = ev.position
				touch_data.touching = true
				touch_data.dragged = false
				card.add_theme_stylebox_override("panel", style_pressed)
			else:
				card.add_theme_stylebox_override("panel", style_normal)
				if touch_data.touching and not touch_data.dragged:
					# C'est un tap (pas de drag significatif)
					var dist: float = (ev as InputEventScreenTouch).position.distance_to(touch_data.start_pos)
					if dist < 20.0:
						# Flash lumineux rapide
						card.add_theme_stylebox_override("panel", style_hover)
						var tw := card.create_tween()
						tw.tween_interval(0.12)
						tw.tween_callback(func():
							card.add_theme_stylebox_override("panel", style_normal))
						AudioManager.play_sfx("click")
						cb.call()
				touch_data.touching = false
		elif ev is InputEventScreenDrag:
			if touch_data.touching:
				var dist: float = (ev as InputEventScreenDrag).position.distance_to(touch_data.start_pos)
				if dist > 15.0:
					touch_data.dragged = true
					card.add_theme_stylebox_override("panel", style_normal)
		elif ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				touch_data.start_pos = ev.position
				touch_data.touching = true
				touch_data.dragged = false
				card.add_theme_stylebox_override("panel", style_pressed)
			else:
				card.add_theme_stylebox_override("panel", style_normal)
				if touch_data.touching and not touch_data.dragged:
					card.add_theme_stylebox_override("panel", style_hover)
					var tw := card.create_tween()
					tw.tween_interval(0.12)
					tw.tween_callback(func():
						card.add_theme_stylebox_override("panel", style_normal))
					AudioManager.play_sfx("click")
					cb.call()
				touch_data.touching = false
		elif ev is InputEventMouseMotion and touch_data.touching:
			var dist: float = ev.position.distance_to(touch_data.start_pos)
			if dist > 15.0:
				touch_data.dragged = true
				card.add_theme_stylebox_override("panel", style_normal))

	parent.add_child(card)

# ── Callbacks ───────────────────────────────────────────────
func _on_play() -> void:
	SceneRouter.goto("res://scenes/GameScene.tscn")

func _on_options() -> void:
	SceneRouter.goto("res://scenes/OptionsScene.tscn")

func _on_rules() -> void:
	SceneRouter.goto("res://scenes/RulesScene.tscn")

func _on_scores() -> void:
	SceneRouter.goto("res://scenes/ScoresScene.tscn")

func _on_quit() -> void:
	_confirm_quit()

# ── Confirm quit ────────────────────────────────────────────
func _confirm_quit() -> void:
	if _quit_layer != null: return
	AudioManager.play_sfx("click")
	_quit_layer = CanvasLayer.new()
	_quit_layer.layer = 100
	add_child(_quit_layer)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.65)
	bg.anchor_right = 1.0; bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_quit_layer.add_child(bg)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.5; panel.anchor_right = 0.5
	panel.anchor_top  = 0.5; panel.anchor_bottom = 0.5
	var pw := ThemeManager.scaled_i(200)
	var ph := ThemeManager.scaled_i(100)
	panel.offset_left = -pw; panel.offset_right = pw
	panel.offset_top  = -ph; panel.offset_bottom = ph
	panel.add_theme_stylebox_override("panel",
			ThemeManager.make_panel_style(ThemeManager.SURFACE,
					ThemeManager.scaled_i(14), ThemeManager.BORDER_2, 2))
	_quit_layer.add_child(panel)

	var mc := MarginContainer.new()
	var pad := ThemeManager.scaled_i(20)
	mc.add_theme_constant_override("margin_left", pad)
	mc.add_theme_constant_override("margin_right", pad)
	mc.add_theme_constant_override("margin_top", pad)
	mc.add_theme_constant_override("margin_bottom", pad)
	panel.add_child(mc)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", ThemeManager.scaled_i(16))
	mc.add_child(vb)

	var l := Label.new()
	l.text = "Quitter le jeu ?"
	l.add_theme_color_override("font_color", ThemeManager.TEXT)
	l.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_MED))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(l)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", ThemeManager.scaled_i(12))
	vb.add_child(hb)

	var yes := _make_dialog_btn("✓  Oui", ThemeManager.ERROR, func(): get_tree().quit())
	yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(yes)

	var no := _make_dialog_btn("✗  Non", ThemeManager.SURFACE_2, func():
		_quit_layer.queue_free(); _quit_layer = null)
	no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(no)

func _make_dialog_btn(label: String, color: Color, cb: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(0, ThemeManager.scaled_i(50))
	b.add_theme_color_override("font_color", ThemeManager.TEXT)
	b.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_MED))
	var r := ThemeManager.scaled_i(10)
	b.add_theme_stylebox_override("normal",
			ThemeManager.make_button_style(color, r))
	b.add_theme_stylebox_override("hover",
			ThemeManager.make_button_style(color.lightened(0.1), r))
	b.add_theme_stylebox_override("pressed",
			ThemeManager.make_button_style(color.darkened(0.15), r))
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(func():
		AudioManager.play_sfx("click"); cb.call())
	return b

# ── Input ───────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_BACK:
			get_viewport().set_input_as_handled()
			_on_quit()
		elif event.keycode == KEY_F11 or event.keycode == KEY_F1:
			var w := DisplayServer.window_get_mode()
			if w == DisplayServer.WINDOW_MODE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			else:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_confirm_quit()

# ════════════════════════════════════════════════════════════
# Dessinateur d'abacus (boulier) vectoriel
# ════════════════════════════════════════════════════════════
class _AbacusDrawer extends Control:
	func _ready() -> void:
		resized.connect(queue_redraw)
		queue_redraw()

	func _draw() -> void:
		var sz := size
		if sz.x <= 0 or sz.y <= 0: return
		var pad := sz.x * 0.12
		var frame_w := sz.x - pad * 2
		var frame_h := sz.y - pad * 2
		var x0 := pad
		var y0 := pad

		# Cadre du boulier (bois)
		var wood := Color("#8B6914")
		var s := maxf(2.0, sz.x * 0.04)

		# Montants verticaux
		draw_line(Vector2(x0, y0), Vector2(x0, y0 + frame_h), wood, s * 1.2, true)
		draw_line(Vector2(x0 + frame_w, y0), Vector2(x0 + frame_w, y0 + frame_h), wood, s * 1.2, true)
		# Barres horizontales haut et bas
		draw_line(Vector2(x0, y0), Vector2(x0 + frame_w, y0), wood, s * 1.2, true)
		draw_line(Vector2(x0, y0 + frame_h), Vector2(x0 + frame_w, y0 + frame_h), wood, s * 1.2, true)

		# Tiges + billes
		var rows := 4
		var bead_colors := [
			Color("#E53935"),  # rouge
			Color("#FFB300"),  # jaune/orange
			Color("#43A047"),  # vert
			Color("#1E88E5"),  # bleu
		]
		var beads_per_row := [3, 4, 2, 5]
		var rod_y_start := y0 + frame_h * 0.15
		var rod_y_end   := y0 + frame_h * 0.85
		var rod_spacing := (rod_y_end - rod_y_start) / (rows - 1)

		for i in rows:
			var ry := rod_y_start + i * rod_spacing
			# Tige
			draw_line(Vector2(x0 + s, ry), Vector2(x0 + frame_w - s, ry),
					wood.darkened(0.2), s * 0.6, true)
			# Billes
			var n_beads: int = beads_per_row[i]
			var bead_r := minf(frame_w / 14.0, rod_spacing * 0.32)
			var bc: Color = bead_colors[i]
			# Les billes sont poussées vers la gauche
			for j in n_beads:
				var bx: float = x0 + s + bead_r * 1.3 + j * bead_r * 2.4
				draw_circle(Vector2(bx, ry), bead_r, bc)
				# Petit reflet
				draw_circle(Vector2(bx - bead_r * 0.3, ry - bead_r * 0.3),
						bead_r * 0.25, Color(1, 1, 1, 0.35))

# ════════════════════════════════════════════════════════════
# Dessinateur d'icônes de menu (play, gear, book, bars, quit, user)
# ════════════════════════════════════════════════════════════
class _MenuIconDrawer extends Control:
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
			"play":  _draw_play(c, r)
			"gear":  _draw_gear(c, r)
			"book":  _draw_book(c, r)
			"bars":  _draw_bars(c, r)
			"quit":  _draw_quit(c, r)
			"user":  _draw_user(c, r)

	func _stroke() -> float:
		return maxf(1.6, size.x * 0.06)

	func _draw_play(c: Vector2, r: float) -> void:
		# Triangle play dans un cercle
		var s := _stroke()
		# Cercle de fond
		draw_arc(c, r * 0.85, 0, TAU, 32, color, s * 1.5, true)
		# Triangle
		var a := r * 0.50
		var pts := PackedVector2Array([
			c + Vector2(-a * 0.55, -a),
			c + Vector2(a * 0.75, 0),
			c + Vector2(-a * 0.55, a),
		])
		draw_colored_polygon(pts, color)

	func _draw_gear(c: Vector2, r: float) -> void:
		var s := _stroke()
		# Cercle central
		var inner := r * 0.35
		var outer := r * 0.70
		draw_arc(c, inner, 0, TAU, 24, color, s, true)
		# Dents (8 dents)
		var teeth := 8
		for i in teeth:
			var angle := TAU * i / teeth
			var p1 := c + Vector2(cos(angle), sin(angle)) * (inner + s)
			var p2 := c + Vector2(cos(angle), sin(angle)) * outer
			draw_line(p1, p2, color, s * 1.8, true)
		# Cercle extérieur (connectant les dents)
		draw_arc(c, outer * 0.82, 0, TAU, 32, color, s * 0.8, true)

	func _draw_book(c: Vector2, r: float) -> void:
		var s := _stroke()
		var w := r * 1.40
		var h := r * 1.20
		# Couverture gauche
		var left := c.x - w * 0.5
		var right := c.x + w * 0.5
		var top := c.y - h * 0.5
		var bot := c.y + h * 0.5
		# Page gauche
		draw_line(Vector2(c.x, top), Vector2(left, top + h * 0.10), color, s, true)
		draw_line(Vector2(left, top + h * 0.10), Vector2(left, bot), color, s, true)
		draw_line(Vector2(left, bot), Vector2(c.x, bot - h * 0.05), color, s, true)
		# Page droite
		draw_line(Vector2(c.x, top), Vector2(right, top + h * 0.10), color, s, true)
		draw_line(Vector2(right, top + h * 0.10), Vector2(right, bot), color, s, true)
		draw_line(Vector2(right, bot), Vector2(c.x, bot - h * 0.05), color, s, true)
		# Reliure (trait central)
		draw_line(Vector2(c.x, top), Vector2(c.x, bot - h * 0.05), color, s * 0.8, true)

	func _draw_bars(c: Vector2, r: float) -> void:
		# 3 barres montantes (graphique)
		var bw := r * 0.32
		var gap := r * 0.12
		var base_y := c.y + r * 0.65
		var heights := [r * 0.60, r * 1.0, r * 1.35]
		var x0 := c.x - (bw * 3 + gap * 2) / 2.0
		for i in 3:
			var bx := x0 + i * (bw + gap)
			var h: float = heights[i]
			# Barre pleine avec coins arrondis du haut simulés
			draw_rect(Rect2(bx, base_y - h, bw, h), color)

	func _draw_quit(c: Vector2, r: float) -> void:
		var s := _stroke()
		# Porte (rectangle)
		var w := r * 1.10
		var h := r * 1.40
		var left := c.x - w * 0.50
		var top := c.y - h * 0.50
		draw_rect(Rect2(left, top, w * 0.70, h), color, false, s)
		# Flèche sortante (→)
		var ax := c.x + w * 0.10
		var ay := c.y
		var arrow_len := r * 0.60
		draw_line(Vector2(ax, ay), Vector2(ax + arrow_len, ay), color, s, true)
		# Pointe
		var tip := r * 0.22
		draw_line(Vector2(ax + arrow_len, ay),
				Vector2(ax + arrow_len - tip, ay - tip), color, s, true)
		draw_line(Vector2(ax + arrow_len, ay),
				Vector2(ax + arrow_len - tip, ay + tip), color, s, true)

	func _draw_user(c: Vector2, r: float) -> void:
		var s := _stroke()
		var head_r := r * 0.32
		var head_c := c + Vector2(0, -r * 0.28)
		draw_arc(head_c, head_r, 0, TAU, 24, color, s, true)
		var torso_r := r * 0.70
		var torso_c := c + Vector2(0, r * 0.95)
		draw_arc(torso_c, torso_r, PI, TAU, 24, color, s, true)
