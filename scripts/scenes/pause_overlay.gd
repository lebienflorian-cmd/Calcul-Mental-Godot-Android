extends Control

signal resumed
signal quitted
signal replayed

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var vp := get_viewport_rect().size
	var pw := min(vp.x * 0.94, 1600.0)
	var ph := min(vp.y * 0.90, 1800.0)

	# Fond sombre
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.75)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	add_child(bg)

	# Panneau central
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -pw * 0.5
	panel.offset_right = pw * 0.5
	panel.offset_top = -ph * 0.5
	panel.offset_bottom = ph * 0.5
	panel.add_theme_stylebox_override("panel", ThemeManager.make_panel_style(ThemeManager.SURFACE, 18))
	add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	panel.add_child(vb)

	var title := Label.new()
	title.text = "⏸  PAUSE"
	title.add_theme_color_override("font_color", ThemeManager.TEXT)
	title.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_TITLE * 4))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)

	var music_cb := CheckBox.new()
	music_cb.text = "Musique"
	music_cb.button_pressed = GameState.options.music_enabled
	music_cb.add_theme_color_override("font_color", ThemeManager.TEXT)
	music_cb.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_MED * 4))
	music_cb.toggled.connect(func(p: bool):
		GameState.set_option("music_enabled", p)
		if p: AudioManager.play_music("game")
		else: AudioManager.stop_music()
	)
	vb.add_child(music_cb)

	var sfx_cb := CheckBox.new()
	sfx_cb.text = "Bruitages"
	sfx_cb.button_pressed = GameState.options.sfx_enabled
	sfx_cb.add_theme_color_override("font_color", ThemeManager.TEXT)
	sfx_cb.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_MED * 4))
	sfx_cb.toggled.connect(func(p: bool): GameState.set_option("sfx_enabled", p))
	vb.add_child(sfx_cb)

	var sep := Control.new()
	sep.custom_minimum_size = Vector2(0, 12)
	vb.add_child(sep)

	_add_button(vb, "▶  Continuer", ThemeManager.SUCCESS,  func(): emit_signal("resumed"))
	_add_button(vb, "↻  Rejouer",  ThemeManager.ACCENT,   func(): emit_signal("replayed"))
	_add_button(vb, "✕  Quitter",  ThemeManager.ERROR,    func(): emit_signal("quitted"))

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_BACK or event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			emit_signal("resumed")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		emit_signal("resumed")

func _add_button(parent: Node, label: String, color: Color, cb: Callable) -> void:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(0, 288)
	b.add_theme_color_override("font_color", ThemeManager.TEXT)
	b.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_LARGE * 4))
	b.add_theme_stylebox_override("normal", ThemeManager.make_button_style(color, 12))
	b.add_theme_stylebox_override("hover",  ThemeManager.make_button_style(color.lightened(0.1), 12))
	b.add_theme_stylebox_override("pressed",ThemeManager.make_button_style(color.darkened(0.15), 12))
	b.pressed.connect(func():
		AudioManager.play_sfx("click")
		cb.call()
	)
	parent.add_child(b)
