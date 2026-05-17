extends Control
# ============================================================
# OPTIONS — Toutes les options du jeu en sections repliables.
# Sauvegarde dans le profil courant.
# ============================================================

var scroll: ScrollContainer
var content_vb: VBoxContainer

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = ThemeManager.BG
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	add_child(bg)

	# Titre
	var title := Label.new()
	title.text = "⚙  Options"
	title.add_theme_color_override("font_color", ThemeManager.TEXT)
	title.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_TITLE))
	title.anchor_left = 0.0
	title.anchor_right = 1.0
	title.offset_left = 16
	title.offset_right = -16
	title.offset_top = 16
	title.offset_bottom = 110
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	# Scroll
	scroll = ScrollContainer.new()
	scroll.anchor_right = 1.0
	scroll.anchor_bottom = 1.0
	scroll.offset_top = 120
	scroll.offset_bottom = -110
	scroll.offset_left = 20
	scroll.offset_right = -20
	add_child(scroll)

	content_vb = VBoxContainer.new()
	content_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_vb.add_theme_constant_override("separation", 14)
	scroll.add_child(content_vb)

	_build_section_profil()
	_build_section_mode()
	_build_section_operations()
	_build_section_operands()
	_build_section_sizes()
	_build_section_constraints()
	_build_section_audio()
	_build_section_music()
	_build_section_display()

	# Boutons bas (fixes)
	var bottom := HBoxContainer.new()
	bottom.anchor_left = 0.0
	bottom.anchor_right = 1.0
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.offset_left = 20
	bottom.offset_right = -20
	bottom.offset_top = -106
	bottom.offset_bottom = -12
	bottom.add_theme_constant_override("separation", 12)
	add_child(bottom)

	var save_btn := _make_btn("💾  Enregistrer", ThemeManager.SUCCESS, func():
		ProfileManager.save_current_options()
		AudioManager.play_sfx("save")
		_toast("Options enregistrées")
	)
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_btn.custom_minimum_size = Vector2(0, 80)
	bottom.add_child(save_btn)

	var back_btn := _make_btn("← Retour", ThemeManager.SURFACE_2, func():
		AudioManager.play_sfx("back")
		SceneRouter.goto("res://scenes/MainMenu.tscn")
	)
	back_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back_btn.custom_minimum_size = Vector2(0, 80)
	bottom.add_child(back_btn)

# ============================================================
# Sections
# ============================================================
func _section(title: String) -> VBoxContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", ThemeManager.make_panel_style(ThemeManager.SURFACE, 12))
	content_vb.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	pc.add_child(vb)
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_color_override("font_color", ThemeManager.ACCENT)
	lbl.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_MED))
	vb.add_child(lbl)
	return vb

func _build_section_profil() -> void:
	var s := _section("Profil")
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	s.add_child(hb)
	var prev := _make_btn("◀", ThemeManager.SURFACE_2, func(): _cycle_profile(-1))
	hb.add_child(prev)
	var name_lbl := Label.new()
	name_lbl.text = ProfileManager.current_profile
	name_lbl.add_theme_color_override("font_color", ThemeManager.TEXT)
	name_lbl.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_MED))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(name_lbl)
	ProfileManager.profile_changed.connect(func(n): name_lbl.text = n)
	var next := _make_btn("▶", ThemeManager.SURFACE_2, func(): _cycle_profile(1))
	hb.add_child(next)

	var hb2 := HBoxContainer.new()
	hb2.add_theme_constant_override("separation", 8)
	s.add_child(hb2)
	hb2.add_child(_make_btn("+ Nouveau", ThemeManager.ACCENT, func(): _modal_text("Nom du nouveau profil", "", func(name):
		if ProfileManager.create_profile(name):
			ProfileManager.switch_to(name)
	)))
	hb2.add_child(_make_btn("✎ Renommer", ThemeManager.SURFACE_2, func(): _modal_text("Nouveau nom", ProfileManager.current_profile, func(name):
		var old := ProfileManager.current_profile
		ProfileManager.rename_profile(old, name)
	)))
	hb2.add_child(_make_btn("🗑 Supprimer", ThemeManager.ERROR, func():
		if ProfileManager.delete_profile(ProfileManager.current_profile):
			_toast("Profil supprimé")
	))

func _cycle_profile(dir: int) -> void:
	var list = ProfileManager.list_profiles()
	if list.is_empty(): return
	var i = list.find(ProfileManager.current_profile)
	i = (i + dir + list.size()) % list.size()
	ProfileManager.switch_to(list[i])

func _build_section_mode() -> void:
	var s := _section("Mode de jeu")
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	s.add_child(hb)
	hb.add_child(_make_btn("◀", ThemeManager.SURFACE_2, func(): _cycle_mode(-1)))
	var lbl := Label.new()
	lbl.text = GameState.MODE_NAMES[GameState.options.mode]
	lbl.add_theme_color_override("font_color", ThemeManager.ACCENT_2)
	lbl.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_MED))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(lbl)
	GameState.options_changed.connect(func():
		lbl.text = GameState.MODE_NAMES[GameState.options.mode]
	)
	hb.add_child(_make_btn("▶", ThemeManager.SURFACE_2, func(): _cycle_mode(1)))

	# Champs dépendants du mode
	var dyn := VBoxContainer.new()
	dyn.add_theme_constant_override("separation", 8)
	s.add_child(dyn)
	var refresh := func():
		for c in dyn.get_children(): c.queue_free()
		_build_mode_specific_fields(dyn)
	refresh.call()
	GameState.options_changed.connect(refresh)

func _cycle_mode(dir: int) -> void:
	var m: int = GameState.options.mode
	m = (m + dir + 5) % 5
	GameState.set_option("mode", m)

func _build_mode_specific_fields(parent: Node) -> void:
	var m = GameState.options.mode
	match m:
		GameState.Mode.CONTRE_LA_MONTRE:
			_add_int_field(parent, "Durée (s)", "duration_sec", 10, 600, 10)
		GameState.Mode.SERIE_CHRONO, GameState.Mode.AUDIO:
			_add_int_field(parent, "Nombre de calculs", "target_count", 5, 200, 5)
		GameState.Mode.FLASH_ANZAN:
			_add_int_field(parent, "Nombres par série", "flash_count", 3, 30, 1)
			_add_int_field(parent, "Nombre de séries",  "flash_series", 1, 20, 1)
		GameState.Mode.INFERNAL:
			_add_int_field(parent, "N (n-back)",   "infernal_n", 1, 6, 1)
			_add_int_field(parent, "Durée (s)",    "infernal_duration", 30, 600, 30)
			_add_enum_field(parent, "Tempo", "infernal_tempo", ["Lent", "Moyen", "Rapide"])

func _build_section_operations() -> void:
	var s := _section("Opérations")
	_add_bool_field(s, "Addition +",          "op_add")
	_add_bool_field(s, "Soustraction −",      "op_sub")
	_add_bool_field(s, "Multiplication ×",    "op_mul")
	_add_bool_field(s, "Division ÷",          "op_div")
	_add_bool_field(s, "Mélanger les opérations dans un calcul", "mix_ops")

func _build_section_operands() -> void:
	var s := _section("Nombre d'opérandes")
	_add_int_field(s, "Min", "operand_min", 2, 6, 1)
	_add_int_field(s, "Max", "operand_max", 2, 6, 1)

func _build_section_sizes() -> void:
	var s := _section("Taille des nombres")
	_add_bool_field(s, "Unités (0–9)",                "size_units")
	_add_bool_field(s, "Dizaines (10–99)",             "size_tens")
	_add_bool_field(s, "Centaines (100–999)",          "size_hundreds")
	_add_bool_field(s, "Milliers (1 000–9 999)",       "size_thousands")
	_add_bool_field(s, "Dizaines de milliers",         "size_tenk")
	_add_bool_field(s, "Centaines de milliers",        "size_hundk")
	_add_bool_field(s, "Mélanger les tailles",         "mix_sizes")

func _build_section_constraints() -> void:
	var s := _section("Contraintes & confort")
	_add_bool_field(s, "Résultat toujours positif",         "positive_only")
	_add_bool_field(s, "Autoriser nombres négatifs",        "allow_negative")
	_add_bool_field(s, "Uniquement nombres négatifs",       "only_negative")
	_add_bool_field(s, "Division à résultat entier",        "integer_div")
	_add_bool_field(s, "Addition sans retenue",             "add_no_carry")
	_add_bool_field(s, "Soustraction sans emprunt",         "sub_no_borrow")
	_add_bool_field(s, "Parenthèses (sauf avec divisions)", "parentheses")
	_add_bool_field(s, "Limiter tables de multiplication",  "limit_tables")
	_add_int_field(s,  "Tables jusqu'à N",                  "tables_max", 2, 20, 1)
	_add_int_field(s,  "Temps max par question (s, 0=∞)",   "max_time_per_q", 0, 60, 1)
	_add_bool_field(s, "Limiter le résultat",               "limit_result")
	_add_int_field(s,  "Résultat ≤",                        "result_max", 10, 100000, 10)
	_add_bool_field(s, "Répéter jusqu'à réussite",          "repeat_until_ok")

func _build_section_audio() -> void:
	var s := _section("Audio & voix")
	_add_bool_field(s, "Audio (voix) — lecture du calcul",    "audio_enabled")
	_add_bool_field(s, "Réponse vocale (bouton micro)",       "voice_input")
	_add_enum_field(s, "Langue de dictée", "stt_lang", ["fr", "en"])
	_add_bool_field(s, "Masquer le calcul (audio only)",      "hide_calc")
	_add_bool_field(s, "Valider automatiquement la réponse",  "auto_validate")

func _build_section_music() -> void:
	var s := _section("Musique")
	_add_bool_field(s, "Musique d'ambiance", "music_enabled")
	_add_int_field(s, "Volume musique %",    "music_volume", 0, 100, 5)
	_add_bool_field(s, "Bruitages",          "sfx_enabled")
	_add_int_field(s, "Volume bruitages %",  "sfx_volume", 0, 100, 5)

func _build_section_display() -> void:
	var s := _section("Affichage")
	_add_bool_field(s, "Plein écran",                 "fullscreen")
	_add_bool_field(s, "Centrer les textes",          "center_text")
	_add_int_field(s,  "Décalage centrage (%)",       "center_offset", -50, 50, 5)
	_add_int_field(s,  "Taille police",               "font_size", 20, 100, 2)
	_add_bool_field(s, "Lumière verte si correct",    "green_correct")
	_add_enum_field(s, "Fond de jeu", "game_bg", ["rects_colors", "rects", "none"])

# ============================================================
# Widgets
# ============================================================
func _add_bool_field(parent: Node, label: String, opt_key: String) -> void:
	var cb := CheckBox.new()
	cb.text = label
	cb.button_pressed = GameState.options[opt_key]
	cb.add_theme_color_override("font_color", ThemeManager.TEXT)
	cb.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_SMALL))
	cb.toggled.connect(func(p): GameState.set_option(opt_key, p))
	parent.add_child(cb)

func _add_int_field(parent: Node, label: String, opt_key: String, mn: int, mx: int, step: int) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	parent.add_child(hb)
	var lbl := Label.new()
	lbl.text = label
	lbl.add_theme_color_override("font_color", ThemeManager.TEXT)
	lbl.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_SMALL))
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(lbl)
	var minus := _make_btn("▼", ThemeManager.SURFACE_2, Callable())
	minus.custom_minimum_size = Vector2(44, 0)
	hb.add_child(minus)
	var value_lbl := Label.new()
	value_lbl.text = str(GameState.options[opt_key])
	value_lbl.add_theme_color_override("font_color", ThemeManager.ACCENT_2)
	value_lbl.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_MED))
	value_lbl.custom_minimum_size = Vector2(80, 0)
	value_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hb.add_child(value_lbl)
	var plus := _make_btn("▲", ThemeManager.SURFACE_2, Callable())
	plus.custom_minimum_size = Vector2(44, 0)
	hb.add_child(plus)
	minus.pressed.connect(func():
		var v: int = GameState.options[opt_key]
		v = clamp(v - step, mn, mx)
		GameState.set_option(opt_key, v)
		value_lbl.text = str(v)
	)
	plus.pressed.connect(func():
		var v: int = GameState.options[opt_key]
		v = clamp(v + step, mn, mx)
		GameState.set_option(opt_key, v)
		value_lbl.text = str(v)
	)

func _add_enum_field(parent: Node, label: String, opt_key: String, choices: Array) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	parent.add_child(hb)
	var lbl := Label.new()
	lbl.text = label
	lbl.add_theme_color_override("font_color", ThemeManager.TEXT)
	lbl.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_SMALL))
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(lbl)
	var current = GameState.options[opt_key]
	var idx := 0
	if current is int: idx = clamp(current, 0, choices.size() - 1)
	elif current is String:
		idx = choices.find(current)
		if idx < 0: idx = 0
	hb.add_child(_make_btn("◀", ThemeManager.SURFACE_2, func():
		idx = (idx - 1 + choices.size()) % choices.size()
		_apply_enum(opt_key, choices, idx)
		hb.get_child(2).text = str(choices[idx])
	))
	var val_lbl := Label.new()
	val_lbl.text = str(choices[idx])
	val_lbl.add_theme_color_override("font_color", ThemeManager.ACCENT_2)
	val_lbl.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_SMALL))
	val_lbl.custom_minimum_size = Vector2(120, 0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hb.add_child(val_lbl)
	hb.add_child(_make_btn("▶", ThemeManager.SURFACE_2, func():
		idx = (idx + 1) % choices.size()
		_apply_enum(opt_key, choices, idx)
		val_lbl.text = str(choices[idx])
	))

func _apply_enum(opt_key: String, choices: Array, idx: int) -> void:
	var cur = GameState.options[opt_key]
	if cur is int:
		GameState.set_option(opt_key, idx)
	else:
		GameState.set_option(opt_key, choices[idx])

func _make_btn(label: String, color: Color, cb: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(0, 48)
	b.add_theme_color_override("font_color", ThemeManager.TEXT)
	b.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_SMALL))
	b.add_theme_stylebox_override("normal", ThemeManager.make_button_style(color, 10))
	b.add_theme_stylebox_override("hover",  ThemeManager.make_button_style(color.lightened(0.1), 10))
	b.add_theme_stylebox_override("pressed",ThemeManager.make_button_style(color.darkened(0.15), 10))
	if cb.is_valid():
		b.pressed.connect(func():
			AudioManager.play_sfx("click")
			cb.call()
		)
	return b

# ============================================================
# Modal texte / Toast
# ============================================================
func _modal_text(prompt: String, initial: String, on_ok: Callable) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.65)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	layer.add_child(bg)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -220
	panel.offset_right = 220
	panel.offset_top = -110
	panel.offset_bottom = 110
	panel.add_theme_stylebox_override("panel", ThemeManager.make_panel_style(ThemeManager.SURFACE, 14))
	layer.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	var l := Label.new()
	l.text = prompt
	l.add_theme_color_override("font_color", ThemeManager.TEXT)
	l.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_MED))
	vb.add_child(l)
	var le := LineEdit.new()
	le.text = initial
	le.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_MED))
	vb.add_child(le)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	vb.add_child(hb)
	var ok := _make_btn("OK", ThemeManager.SUCCESS, func():
		on_ok.call(le.text)
		layer.queue_free()
	)
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(ok)
	var cancel := _make_btn("Annuler", ThemeManager.SURFACE_2, func(): layer.queue_free())
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(cancel)
	le.grab_focus()

func _input(event: InputEvent) -> void:
	if event is InputEventScreenDrag:
		scroll.scroll_vertical -= int(event.relative.y)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_BACK:
			get_viewport().set_input_as_handled()
			SceneRouter.goto("res://scenes/MainMenu.tscn")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		SceneRouter.goto("res://scenes/MainMenu.tscn")

func _toast(msg: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 60
	add_child(layer)
	var pc := PanelContainer.new()
	pc.anchor_left = 0.5
	pc.anchor_right = 0.5
	pc.anchor_bottom = 1.0
	pc.offset_left = -160
	pc.offset_right = 160
	pc.offset_top = -120
	pc.offset_bottom = -60
	pc.add_theme_stylebox_override("panel", ThemeManager.make_panel_style(ThemeManager.ACCENT.darkened(0.3), 10))
	layer.add_child(pc)
	var l := Label.new()
	l.text = msg
	l.add_theme_color_override("font_color", ThemeManager.TEXT)
	l.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_SMALL))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pc.add_child(l)
	var tw := create_tween()
	tw.tween_interval(1.6)
	tw.tween_property(pc, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func(): layer.queue_free())
