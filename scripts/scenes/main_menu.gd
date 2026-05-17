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
	var vp := get_viewport_rect().size
	var vw := vp.x
	var margin := maxf(20.0, vw * 0.05)
	var safe_top := maxi(60, int(DisplayServer.screen_get_usable_rect().position.y + 24.0))

	# Conteneur principal pleine largeur
	var root := VBoxContainer.new()
	root.anchor_left = 0.0
	root.anchor_right = 1.0
	root.anchor_top = 0.0
	root.anchor_bottom = 1.0
	root.offset_left = margin
	root.offset_right = -margin
	root.offset_top = safe_top
	root.offset_bottom = -24
	add_child(root)

	# Bloc centré verticalement
	var center_block := VBoxContainer.new()
	center_block.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	center_block.add_theme_constant_override("separation", 12)
	root.add_child(center_block)

	# HEADER BLOCK
	var icon_bg := PanelContainer.new()
	icon_bg.custom_minimum_size = Vector2(96, 96)
	icon_bg.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon_bg.add_theme_stylebox_override("panel", ThemeManager.make_panel_style(ThemeManager.SURFACE, 20))
	center_block.add_child(icon_bg)

	var icon_label := Label.new()
	icon_label.text = "🧮"
	icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_label.add_theme_font_size_override("font_size", 96)
	icon_bg.add_child(icon_label)

	var title_row := HBoxContainer.new()
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	title_row.add_theme_constant_override("separation", 8)
	center_block.add_child(title_row)

	var title_calcul := Label.new()
	title_calcul.text = "Calcul"
	title_calcul.add_theme_color_override("font_color", ThemeManager.TEXT)
	title_calcul.add_theme_font_size_override("font_size", ThemeManager.scaled_i(56))
	title_calcul.add_theme_font_override("font", ThemeDB.fallback_font)
	title_row.add_child(title_calcul)

	var title_mental := Label.new()
	title_mental.text = "Mental"
	title_mental.add_theme_color_override("font_color", ThemeManager.ACCENT)
	title_mental.add_theme_font_size_override("font_size", ThemeManager.scaled_i(56))
	title_mental.add_theme_font_override("font", ThemeDB.fallback_font)
	title_row.add_child(title_mental)

	var subtitle := Label.new()
	subtitle.text = "Entraîne ta rapidité et ta précision"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", ThemeManager.TEXT_DIM)
	subtitle.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_SMALL))
	center_block.add_child(subtitle)

	var subtitle_gap := Control.new()
	subtitle_gap.custom_minimum_size = Vector2(0, 32)
	center_block.add_child(subtitle_gap)

	# MENU ITEMS en cartes
	_add_menu_card(center_block, "▶", Color(1, 1, 1, 0.15), "Jouer", _on_play, true)
	_add_menu_card(center_block, "⚙", ThemeManager.ACCENT, "Options", _on_options, false)
	_add_menu_card(center_block, "📖", Color("#F59E0B"), "Règles du jeu", _on_rules, false)
	_add_menu_card(center_block, "📊", ThemeManager.SUCCESS, "Scores", _on_scores, false)
	_add_menu_card(center_block, "⏻", ThemeManager.ERROR, "Quitter", _on_quit, false)

	# Profil affiché en bas (pill)
	var prof_panel := PanelContainer.new()
	prof_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var prof_bg := Color(ThemeManager.SURFACE_2.r, ThemeManager.SURFACE_2.g, ThemeManager.SURFACE_2.b, 0.5)
	var prof_style := ThemeManager.make_panel_style(prof_bg, 20)
	prof_panel.add_theme_stylebox_override("panel", prof_style)
	prof_panel.add_theme_constant_override("margin_left", 12)
	prof_panel.add_theme_constant_override("margin_right", 12)
	prof_panel.add_theme_constant_override("margin_top", 8)
	prof_panel.add_theme_constant_override("margin_bottom", 8)
	center_block.add_child(prof_panel)

	var prof_row := HBoxContainer.new()
	prof_row.add_theme_constant_override("separation", 6)
	prof_panel.add_child(prof_row)

	var prof_icon := Label.new()
	prof_icon.text = "👤"
	prof_icon.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_SMALL))
	prof_row.add_child(prof_icon)

	var prof_prefix := Label.new()
	prof_prefix.text = "Profil actif : "
	prof_prefix.add_theme_color_override("font_color", ThemeManager.TEXT_DIM)
	prof_prefix.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_SMALL))
	prof_row.add_child(prof_prefix)

	var prof_name := Label.new()
	prof_name.text = ProfileManager.current_profile
	prof_name.add_theme_color_override("font_color", ThemeManager.ACCENT)
	prof_name.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_SMALL))
	prof_row.add_child(prof_name)
	ProfileManager.profile_changed.connect(func(n): prof_name.text = n)

func _add_menu_card(parent: Node, icon_emoji: String, icon_bg_color: Color, label: String, cb: Callable, is_primary: bool) -> Button:
	var card := Button.new()
	card.custom_minimum_size = Vector2(0, 78)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.alignment = HORIZONTAL_ALIGNMENT_LEFT
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.add_theme_constant_override("h_separation", 12)
	card.add_theme_constant_override("content_margin_left", 16)
	card.add_theme_constant_override("content_margin_right", 16)
	card.add_theme_constant_override("content_margin_top", 8)
	card.add_theme_constant_override("content_margin_bottom", 8)

	var base_color := ThemeManager.ACCENT if is_primary else ThemeManager.SURFACE_2
	var hover_color := base_color.lightened(0.08)
	var pressed_color := base_color.darkened(0.12)

	var base_style := ThemeManager.make_button_style(base_color, 16)
	base_style.border_width_left = 1
	base_style.border_width_top = 1
	base_style.border_width_right = 1
	base_style.border_width_bottom = 1
	base_style.border_color = ThemeManager.BORDER

	var hover_style := ThemeManager.make_button_style(hover_color, 16)
	hover_style.border_width_left = 1
	hover_style.border_width_top = 1
	hover_style.border_width_right = 1
	hover_style.border_width_bottom = 1
	hover_style.border_color = ThemeManager.BORDER

	var pressed_style := ThemeManager.make_button_style(pressed_color, 16)
	pressed_style.border_width_left = 1
	pressed_style.border_width_top = 1
	pressed_style.border_width_right = 1
	pressed_style.border_width_bottom = 1
	pressed_style.border_color = ThemeManager.BORDER

	card.add_theme_stylebox_override("normal", base_style)
	card.add_theme_stylebox_override("hover", hover_style)
	card.add_theme_stylebox_override("pressed", pressed_style)

	var content := HBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(content)

	var tile := PanelContainer.new()
	tile.custom_minimum_size = Vector2(52, 52)
	var tile_style := ThemeManager.make_panel_style(icon_bg_color, 14)
	tile.add_theme_stylebox_override("panel", tile_style)
	content.add_child(tile)

	var tile_label := Label.new()
	tile_label.text = icon_emoji
	tile_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tile_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tile_label.add_theme_font_size_override("font_size", 28)
	tile.add_child(tile_label)

	var title := Label.new()
	title.text = label
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_LARGE))
	title.add_theme_color_override("font_color", Color.WHITE if is_primary else ThemeManager.TEXT)
	content.add_child(title)

	var chevron := Label.new()
	chevron.text = "›"
	chevron.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_MED))
	chevron.add_theme_color_override("font_color", Color.WHITE if is_primary else ThemeManager.TEXT_DIM)
	chevron.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	content.add_child(chevron)

	card.pressed.connect(func():
		AudioManager.play_sfx("click")
		cb.call()
	)
	parent.add_child(card)
	return card

func _add_menu_button(parent: Node, label: String, color: Color, cb: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(0, 64)
	b.add_theme_color_override("font_color", ThemeManager.TEXT)
	b.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_LARGE))
	b.add_theme_stylebox_override("normal", ThemeManager.make_button_style(color, 12))
	b.add_theme_stylebox_override("hover", ThemeManager.make_button_style(color.lightened(0.1), 12))
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
