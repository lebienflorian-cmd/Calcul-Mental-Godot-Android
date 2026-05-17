extends Control
# ============================================================
# MAIN MENU — Boutons : Jouer, Options, Règles, Scores, Quitter.
# Fond animé : chiffres flottants + grille.
# ============================================================

var _bg_node: Node2D
var _title_label: Label
var _progress_panel: PanelContainer

# Particules de fond
var _symbols: Array = []  # {pos: Vector2, vel: Vector2, char: String, alpha: float, size: float}
const SYMBOLS_TEXT := ["1","2","3","4","5","6","7","8","9","+","−","×","÷","="]
var _bg_style: int = 0  # 0 = fusion, 1 = bokeh
var _scan_pos: float = 0.0
var _quit_layer: CanvasLayer = null

func _ready() -> void:
	AudioManager.play_music("menu")
	_build_ui()
	_init_background()
	set_process(true)

func _build_ui() -> void:
	var vp  := get_viewport_rect().size
	var vw  := vp.x
	var margin := maxf(20.0, vw * 0.05)
	# Conteneur principal pleine largeur
	var root := VBoxContainer.new()
	root.anchor_left = 0.0
	root.anchor_right = 1.0
	root.anchor_top = 0.0
	root.anchor_bottom = 1.0
	root.offset_left = margin
	root.offset_right = -margin
	root.offset_top = 120
	root.offset_bottom = -80
	root.add_theme_constant_override("separation", 14)
	add_child(root)

	# Titre
	_title_label = Label.new()
	_title_label.text = "🧮  Calcul Mental"
	_title_label.add_theme_color_override("font_color", ThemeManager.TEXT)
	_title_label.add_theme_font_size_override("font_size", ThemeManager.scaled_i(int(ThemeManager.FONT_TITLE * 3.0)))
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_title_label)

	# Espacement
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 48)
	root.add_child(spacer)

	# Boutons principaux
	_add_menu_button(root, "▶  Jouer",          ThemeManager.ACCENT,   _on_play)
	_add_menu_button(root, "⚙  Options",        ThemeManager.SURFACE_2, _on_options)
	_add_menu_button(root, "📖  Règles du jeu", ThemeManager.SURFACE_2, _on_rules)
	_add_menu_button(root, "📊  Scores",        ThemeManager.SURFACE_2, _on_scores)
	_add_menu_button(root, "✕  Quitter",        ThemeManager.SURFACE_2, _on_quit)

	# Profil affiché en bas
	var prof := Label.new()
	prof.text = "Profil : %s" % ProfileManager.current_profile
	prof.add_theme_color_override("font_color", ThemeManager.TEXT_DIM)
	prof.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_SMALL))
	prof.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(prof)
	ProfileManager.profile_changed.connect(func(n): prof.text = "Profil : %s" % n)

	# Bouton "changer fond" en haut à droite
	var bg_btn := Button.new()
	bg_btn.text = "✦"
	bg_btn.size = Vector2(56, 56)
	bg_btn.position = Vector2(get_viewport_rect().size.x - 72, 16)
	bg_btn.add_theme_color_override("font_color", ThemeManager.TEXT)
	bg_btn.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_MED))
	bg_btn.tooltip_text = "Changer le fond animé"
	var sb := ThemeManager.make_button_style(ThemeManager.SURFACE_2, 28)
	bg_btn.add_theme_stylebox_override("normal", sb)
	bg_btn.add_theme_stylebox_override("hover", ThemeManager.make_button_style(ThemeManager.BORDER, 28))
	bg_btn.add_theme_stylebox_override("pressed", ThemeManager.make_button_style(ThemeManager.ACCENT, 28))
	bg_btn.pressed.connect(_on_toggle_bg)
	add_child(bg_btn)

func _add_menu_button(parent: Node, label: String, color: Color, cb: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(0, 160)
	b.add_theme_color_override("font_color", ThemeManager.TEXT)
	b.add_theme_font_size_override("font_size", ThemeManager.scaled_i(int(ThemeManager.FONT_LARGE * 2.2)))
	b.add_theme_stylebox_override("normal",  ThemeManager.make_button_style(color, 12))
	b.add_theme_stylebox_override("hover",   ThemeManager.make_button_style(color.lightened(0.1), 12))
	b.add_theme_stylebox_override("pressed", ThemeManager.make_button_style(color.darkened(0.15), 12))
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(func():
		AudioManager.play_sfx("click")
		cb.call()
	)
	parent.add_child(b)
	return b

# ---- Callbacks ----
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

func _on_toggle_bg() -> void:
	_bg_style = (_bg_style + 1) % 2
	AudioManager.play_sfx("step")
	if _bg_style == 1:
		_symbols.clear()
		_init_bokeh()

# ---- Fond animé ----
func _init_background() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in 36:
		var sz := get_viewport_rect().size
		_symbols.append({
			"pos": Vector2(rng.randf() * sz.x, rng.randf() * sz.y),
			"vel": Vector2(rng.randf_range(-8, 8), rng.randf_range(-12, -3)),
			"char": SYMBOLS_TEXT[rng.randi() % SYMBOLS_TEXT.size()],
			"alpha": rng.randf_range(0.10, 0.30),
			"size": rng.randf_range(20, 48),
		})

func _init_bokeh() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var sz := get_viewport_rect().size
	for i in 22:
		_symbols.append({
			"pos": Vector2(rng.randf() * sz.x, rng.randf() * sz.y),
			"vel": Vector2(rng.randf_range(-5, 5), rng.randf_range(-5, 5)),
			"char": "●",
			"alpha": rng.randf_range(0.08, 0.18),
			"size": rng.randf_range(60, 140),
		})

func _process(delta: float) -> void:
	var sz := get_viewport_rect().size
	for s in _symbols:
		s.pos += s.vel * delta
		if s.pos.y < -50: s.pos.y = sz.y + 50
		if s.pos.y > sz.y + 50: s.pos.y = -50
		if s.pos.x < -50: s.pos.x = sz.x + 50
		if s.pos.x > sz.x + 50: s.pos.x = -50
	_scan_pos += delta * 80.0
	if _scan_pos > get_viewport_rect().size.x + 200:
		_scan_pos = -200
	queue_redraw()

func _draw() -> void:
	var sz := get_viewport_rect().size
	# Fond
	draw_rect(Rect2(Vector2.ZERO, sz), ThemeManager.BG)
	# Grille semi-transparente (fusion)
	if _bg_style == 0:
		var step := 60
		var col := Color(ThemeManager.BORDER.r, ThemeManager.BORDER.g, ThemeManager.BORDER.b, 0.15)
		for x in range(0, int(sz.x), step):
			draw_line(Vector2(x, 0), Vector2(x, sz.y), col, 1)
		for y in range(0, int(sz.y), step):
			draw_line(Vector2(0, y), Vector2(sz.x, y), col, 1)
	# Symboles
	var f := ThemeDB.fallback_font
	for s in _symbols:
		var c := ThemeManager.ACCENT if _bg_style == 1 else ThemeManager.TEXT
		c.a = s.alpha
		if _bg_style == 1:
			# Bokeh : cercles
			draw_circle(s.pos, s.size * 0.5, c)
		else:
			draw_string(f, s.pos, s.char, HORIZONTAL_ALIGNMENT_LEFT, -1, int(s.size), c)
	# Balayage lumineux
	if _bg_style == 0:
		var rect := Rect2(_scan_pos - 80, 0, 160, sz.y)
		var grad := Color(ThemeManager.ACCENT.r, ThemeManager.ACCENT.g, ThemeManager.ACCENT.b, 0.04)
		draw_rect(rect, grad)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_BACK:
			get_viewport().set_input_as_handled()
			_on_quit()
		elif event.keycode == KEY_F11 or event.keycode == KEY_F1:
			_toggle_fullscreen()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_confirm_quit()

func _confirm_quit() -> void:
	if _quit_layer != null: return
	AudioManager.play_sfx("click")
	_quit_layer = CanvasLayer.new()
	_quit_layer.layer = 100
	add_child(_quit_layer)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.65)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_quit_layer.add_child(bg)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -200
	panel.offset_right = 200
	panel.offset_top = -100
	panel.offset_bottom = 100
	panel.add_theme_stylebox_override("panel", ThemeManager.make_panel_style(ThemeManager.SURFACE, 14))
	_quit_layer.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	panel.add_child(vb)
	var l := Label.new()
	l.text = "Quitter le jeu ?"
	l.add_theme_color_override("font_color", ThemeManager.TEXT)
	l.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_MED))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(l)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	vb.add_child(hb)
	var yes := _add_menu_button(hb, "✓  Oui", ThemeManager.ERROR, func(): get_tree().quit())
	yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var no := _add_menu_button(hb, "✗  Non", ThemeManager.SURFACE_2, func():
		_quit_layer.queue_free()
		_quit_layer = null
	)
	no.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _toggle_fullscreen() -> void:
	var w := DisplayServer.window_get_mode()
	if w == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
