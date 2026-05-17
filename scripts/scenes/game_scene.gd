extends Control
# ============================================================
# GAME SCENE — Gère les 5 modes. UI commune : barre du haut, panneau
# calcul, champ de réponse, clavier numérique tactile.
# ============================================================

# UI
var top_bar: PanelContainer
var top_label: Label
var top_right_label: Label
var calc_panel: PanelContainer
var calc_label: Label
var answer_input: LineEdit
var keypad_grid: GridContainer
var validate_btn: Button
var pause_btn: Button
var hint_label: Label
var voice_btn: Button
var anzan_label: Label   # gros nombre central anzan
var second_panel: PanelContainer
var second_label: Label

# Etat
var current_calc: Dictionary = {}
var question_start_ms: int = 0
var time_left: float = 0.0
var session_running: bool = false
var awaiting_input: bool = false

# Mode courant
var mode_handler: Node = null

# Effets
var shake_amount: Vector2 = Vector2.ZERO
var glow_alpha: float = 0.0
var glow_color: Color = ThemeManager.SUCCESS

# Pause overlay
var pause_overlay: Control = null

# Compte à rebours
var countdown_label: Label = null
var countdown_value: int = 0

func _ready() -> void:
	AudioManager.play_music("game")
	AudioManager.play_sfx("start")
	GameState.reset_session()
	_build_ui()
	_init_handler()
	set_process(true)
	set_process_input(true)

# ============================================================
# UI BUILD
# ============================================================
func _build_ui() -> void:
	var vp  := get_viewport_rect().size
	var vw  := vp.x
	var vh  := vp.y
	var hm  := maxf(16.0, vw * 0.04)
	var top_h := maxf(60.0, vh * 0.07)

	# Fond
	var bg := ColorRect.new()
	bg.color = ThemeManager.BG
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Barre supérieure — pleine largeur
	top_bar = PanelContainer.new()
	top_bar.anchor_left = 0.0
	top_bar.anchor_right = 1.0
	top_bar.offset_top = 0
	top_bar.offset_bottom = top_h
	top_bar.add_theme_stylebox_override("panel", ThemeManager.make_panel_style(ThemeManager.SURFACE, 0))
	add_child(top_bar)

	var top_hb := HBoxContainer.new()
	top_hb.add_theme_constant_override("separation", 28)
	top_bar.add_child(top_hb)

	pause_btn = Button.new()
	pause_btn.text = "‖"
	pause_btn.custom_minimum_size = Vector2(maxf(64.0, top_h), 0)
	pause_btn.add_theme_color_override("font_color", ThemeManager.TEXT)
	pause_btn.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_LARGE))
	pause_btn.add_theme_stylebox_override("normal", ThemeManager.make_button_style(ThemeManager.SURFACE_2, 12))
	pause_btn.add_theme_stylebox_override("hover",  ThemeManager.make_button_style(ThemeManager.BORDER, 12))
	pause_btn.pressed.connect(_on_pause)
	top_hb.add_child(pause_btn)

	top_label = Label.new()
	top_label.add_theme_color_override("font_color", ThemeManager.TEXT)
	top_label.add_theme_font_size_override("font_size", ThemeManager.scaled_i(int(ThemeManager.FONT_MED * 1.8)))
	top_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_hb.add_child(top_label)

	top_right_label = Label.new()
	top_right_label.add_theme_color_override("font_color", ThemeManager.ACCENT_2)
	top_right_label.add_theme_font_size_override("font_size", ThemeManager.scaled_i(int(ThemeManager.FONT_LARGE * 1.35)))
	top_right_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var chrono_pad := Control.new()
	chrono_pad.custom_minimum_size = Vector2(24, 0)
	top_hb.add_child(top_right_label)
	top_hb.add_child(chrono_pad)

	# Panneau calcul — premier tiers de l'écran (sous la barre)
	var calc_top := top_h + vh * 0.02
	var calc_bot := top_h + vh * 0.30
	calc_panel = PanelContainer.new()
	calc_panel.anchor_left = 0.0
	calc_panel.anchor_right = 1.0
	calc_panel.offset_left = hm
	calc_panel.offset_right = -hm
	calc_panel.offset_top = calc_top
	calc_panel.offset_bottom = calc_bot
	calc_panel.add_theme_stylebox_override("panel", ThemeManager.make_panel_style(ThemeManager.SURFACE, 18))
	add_child(calc_panel)

	var calc_vb := VBoxContainer.new()
	calc_vb.add_theme_constant_override("separation", 8)
	calc_panel.add_child(calc_vb)

	var hdr := Label.new()
	hdr.text = "Calculez mentalement :"
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hdr.add_theme_color_override("font_color", ThemeManager.TEXT_DIM)
	hdr.add_theme_font_size_override("font_size", ThemeManager.scaled_i(int(ThemeManager.FONT_SMALL * 1.25)))
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	calc_vb.add_child(hdr)

	calc_label = Label.new()
	calc_label.text = ""
	calc_label.add_theme_color_override("font_color", ThemeManager.TEXT)
	calc_label.add_theme_font_size_override("font_size", ThemeManager.scaled_i(72))
	calc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	calc_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	calc_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	calc_vb.add_child(calc_label)

	# Label anzan (caché par défaut, superposé au panneau calcul)
	anzan_label = Label.new()
	anzan_label.text = ""
	anzan_label.add_theme_color_override("font_color", ThemeManager.ACCENT)
	anzan_label.add_theme_font_size_override("font_size", ThemeManager.scaled_i(180))
	anzan_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	anzan_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	anzan_label.anchor_left = 0.0
	anzan_label.anchor_right = 1.0
	anzan_label.offset_top = calc_top
	anzan_label.offset_bottom = calc_bot
	anzan_label.visible = false
	add_child(anzan_label)

	# Panneau mode infernal — juste sous le panneau calcul
	var second_top := calc_bot + vh * 0.01
	var second_bot := second_top + vh * 0.09
	second_panel = PanelContainer.new()
	second_panel.anchor_left = 0.0
	second_panel.anchor_right = 1.0
	second_panel.offset_left = hm
	second_panel.offset_right = -hm
	second_panel.offset_top = second_top
	second_panel.offset_bottom = second_bot
	second_panel.add_theme_stylebox_override("panel", ThemeManager.make_panel_style(ThemeManager.ACCENT_2.darkened(0.5), 18))
	second_panel.visible = false
	add_child(second_panel)
	second_label = Label.new()
	second_label.text = "???? ="
	second_label.add_theme_color_override("font_color", ThemeManager.ACCENT_2)
	second_label.add_theme_font_size_override("font_size", ThemeManager.scaled_i(56))
	second_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	second_panel.add_child(second_label)

	# Champ de réponse + bouton valider (+ bouton vocal si mode audio)
	var ans_top := vh * 0.49
	var ans_bot := vh * 0.62
	var ans_row := HBoxContainer.new()
	ans_row.anchor_left = 0.0
	ans_row.anchor_right = 1.0
	ans_row.offset_left = hm
	ans_row.offset_right = -hm
	ans_row.offset_top = ans_top
	ans_row.offset_bottom = ans_bot
	ans_row.add_theme_constant_override("separation", 10)
	add_child(ans_row)

	answer_input = LineEdit.new()
	answer_input.virtual_keyboard_enabled = false
	answer_input.placeholder_text = "Réponse"
	answer_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	answer_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	answer_input.add_theme_font_size_override("font_size", ThemeManager.scaled_i(48))
	answer_input.add_theme_color_override("font_color", ThemeManager.TEXT)
	var sb := ThemeManager.make_panel_style(ThemeManager.SURFACE_2, 12)
	answer_input.add_theme_stylebox_override("normal", sb)
	answer_input.add_theme_stylebox_override("focus",  ThemeManager.make_panel_style(ThemeManager.ACCENT.darkened(0.3), 12))
	answer_input.text_submitted.connect(_on_submit)
	ans_row.add_child(answer_input)

	var backspace_btn := Button.new()
	backspace_btn.text = "⌫"
	backspace_btn.custom_minimum_size = Vector2(104, 0)
	backspace_btn.add_theme_color_override("font_color", ThemeManager.TEXT)
	backspace_btn.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_LARGE))
	backspace_btn.add_theme_stylebox_override("normal",  ThemeManager.make_button_style(ThemeManager.ERROR.darkened(0.3), 12))
	backspace_btn.add_theme_stylebox_override("hover",   ThemeManager.make_button_style(ThemeManager.ERROR.darkened(0.1), 12))
	backspace_btn.add_theme_stylebox_override("pressed", ThemeManager.make_button_style(ThemeManager.ERROR.darkened(0.5), 12))
	backspace_btn.pressed.connect(func(): _on_keypad("⌫"))
	ans_row.add_child(backspace_btn)

	# Bouton micro — dans la même rangée que la réponse
	voice_btn = Button.new()
	voice_btn.text = "🎤"
	voice_btn.custom_minimum_size = Vector2(80, 0)
	voice_btn.add_theme_color_override("font_color", ThemeManager.TEXT)
	voice_btn.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_LARGE))
	voice_btn.add_theme_stylebox_override("normal", ThemeManager.make_button_style(ThemeManager.ACCENT, 40))
	voice_btn.add_theme_stylebox_override("hover",  ThemeManager.make_button_style(ThemeManager.ACCENT.lightened(0.1), 40))
	voice_btn.add_theme_stylebox_override("pressed",ThemeManager.make_button_style(ThemeManager.ERROR, 40))
	voice_btn.visible = GameState.options.voice_input or GameState.options.mode == GameState.Mode.AUDIO
	voice_btn.button_down.connect(_on_voice_down)
	voice_btn.button_up.connect(_on_voice_up)
	ans_row.add_child(voice_btn)
	VoiceManager.stt_result.connect(_on_stt_result)
	VoiceManager.tts_finished.connect(_on_tts_finished)

	# Clavier numérique tactile — ancré en bas, taille proportionnelle
	var kpad_top := vh * 0.64
	var kpad_bot := vh * 0.98
	var kpad_w   := vw - hm * 2.0
	var kpad_h   := kpad_bot - kpad_top
	var btn_h    := maxf(48.0, (kpad_h - 8.0 * 3.0) / 4.0)
	var btn_w    := maxf(80.0, (kpad_w - 8.0 * 2.0) / 3.0)

	keypad_grid = GridContainer.new()
	keypad_grid.columns = 3
	keypad_grid.anchor_left = 0.0
	keypad_grid.anchor_right = 1.0
	keypad_grid.offset_left = hm
	keypad_grid.offset_right = -hm
	keypad_grid.offset_top = kpad_top
	keypad_grid.offset_bottom = kpad_bot
	keypad_grid.add_theme_constant_override("h_separation", 8)
	keypad_grid.add_theme_constant_override("v_separation", 8)
	add_child(keypad_grid)

	for k in ["7","8","9","4","5","6","1","2","3","-","0","✓"]:
		var b := Button.new()
		b.text = k
		b.custom_minimum_size = Vector2(btn_w, btn_h)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_vertical   = Control.SIZE_EXPAND_FILL
		b.add_theme_color_override("font_color", ThemeManager.TEXT)
		b.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_LARGE))
		var col := ThemeManager.SURFACE_2
		if k == "✓": col = ThemeManager.SUCCESS
		b.add_theme_stylebox_override("normal",  ThemeManager.make_button_style(col, 12))
		b.add_theme_stylebox_override("hover",   ThemeManager.make_button_style(col.lightened(0.1), 12))
		b.add_theme_stylebox_override("pressed", ThemeManager.make_button_style(col.darkened(0.2), 12))
		var key: String = k
		b.pressed.connect(func(): _on_keypad(key))
		if k == "✓": validate_btn = b
		keypad_grid.add_child(b)

	# Hint
	hint_label = Label.new()
	hint_label.anchor_left = 0.0
	hint_label.anchor_right = 1.0
	hint_label.anchor_top = 1.0
	hint_label.anchor_bottom = 1.0
	hint_label.offset_left = 16
	hint_label.offset_top = -32
	hint_label.offset_bottom = -8
	hint_label.text = "Entrée : valider — ‖ : pause"
	hint_label.add_theme_color_override("font_color", ThemeManager.TEXT_DIM)
	hint_label.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_SMALL))
	add_child(hint_label)

# ============================================================
# HANDLER PAR MODE
# ============================================================
func _init_handler() -> void:
	var m = GameState.options.mode
	match m:
		GameState.Mode.CONTRE_LA_MONTRE:
			mode_handler = load("res://scripts/game_modes/mode_chrono.gd").new()
		GameState.Mode.SERIE_CHRONO:
			mode_handler = load("res://scripts/game_modes/mode_serie.gd").new()
		GameState.Mode.FLASH_ANZAN:
			mode_handler = load("res://scripts/game_modes/mode_anzan.gd").new()
		GameState.Mode.AUDIO:
			mode_handler = load("res://scripts/game_modes/mode_audio.gd").new()
		GameState.Mode.INFERNAL:
			mode_handler = load("res://scripts/game_modes/mode_infernal.gd").new()
	mode_handler.scene = self
	add_child(mode_handler)
	mode_handler.start()

# ============================================================
# INPUT
# ============================================================
func _input(event: InputEvent) -> void:
	if pause_overlay != null: return
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_BACK:
			get_viewport().set_input_as_handled()
			_on_pause()
		elif event.keycode == KEY_SPACE:
			_on_pause()
		elif event.keycode == KEY_Q:
			if mode_handler and mode_handler.has_method("repeat_audio"):
				mode_handler.repeat_audio()

func _on_keypad(k: String) -> void:
	AudioManager.play_sfx("click")
	if k == "⌫":
		if answer_input.text.length() > 0:
			answer_input.text = answer_input.text.substr(0, answer_input.text.length() - 1)
	elif k == "✓":
		_on_submit(answer_input.text)
		return
	elif k == "-":
		if not answer_input.text.begins_with("-"):
			answer_input.text = "-" + answer_input.text
		else:
			answer_input.text = answer_input.text.substr(1)
	else:
		answer_input.text += k
	answer_input.caret_column = answer_input.text.length()

# ============================================================
# SOUMISSION
# ============================================================
func _on_submit(_text: String) -> void:
	if not awaiting_input: return
	if mode_handler and mode_handler.has_method("handle_submit"):
		mode_handler.handle_submit(answer_input.text)

# ============================================================
# API utilisée par les handlers de mode
# ============================================================
func show_calc(expr: String, hide: bool = false) -> void:
	if hide:
		calc_label.text = "🔊 Calcul N°%d" % (GameState.session.answers.size() + 1)
	else:
		calc_label.text = expr
	answer_input.text = ""
	answer_input.grab_focus()
	awaiting_input = true
	question_start_ms = Time.get_ticks_msec()
	# Petit zoom d'apparition
	calc_panel.scale = Vector2(0.9, 0.9)
	var tw := create_tween()
	tw.tween_property(calc_panel, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK)

func feedback(ok: bool) -> void:
	awaiting_input = false
	if ok:
		AudioManager.play_sfx("correct")
		_pulse_glow(ThemeManager.SUCCESS)
	else:
		AudioManager.play_sfx("error")
		_shake_panel()
		_pulse_glow(ThemeManager.ERROR)

func _pulse_glow(c: Color) -> void:
	glow_color = c
	glow_alpha = 1.0
	var tw := create_tween()
	tw.tween_property(self, "glow_alpha", 0.0, 0.6)

func _shake_panel() -> void:
	var orig := calc_panel.position
	var tw := create_tween()
	for i in 5:
		tw.tween_property(calc_panel, "position:x", orig.x + (-12 if i % 2 == 0 else 12), 0.04)
	tw.tween_property(calc_panel, "position:x", orig.x, 0.04)

func _process(delta: float) -> void:
	# Glow autour du panneau
	if glow_alpha > 0:
		queue_redraw()

func _draw() -> void:
	if glow_alpha > 0 and calc_panel:
		var r := calc_panel.get_rect()
		var col := glow_color
		col.a = glow_alpha * 0.4
		# Halo : plusieurs rects étendus
		for i in range(1, 8):
			var pad := i * 4
			var rect := Rect2(r.position - Vector2(pad, pad), r.size + Vector2(pad * 2, pad * 2))
			var c := col
			c.a = col.a / float(i)
			draw_rect(rect, c, false, 2)

# ============================================================
# PAUSE
# ============================================================
func _on_pause() -> void:
	if pause_overlay != null: return
	AudioManager.play_sfx("click")
	pause_overlay = load("res://scenes/PauseOverlay.tscn").instantiate()
	pause_overlay.resumed.connect(_on_resume)
	pause_overlay.quitted.connect(_on_quit_from_pause)
	pause_overlay.replayed.connect(_on_replay)
	add_child(pause_overlay)
	get_tree().paused = true

func _on_resume() -> void:
	get_tree().paused = false
	pause_overlay.queue_free()
	pause_overlay = null

func _on_quit_from_pause() -> void:
	get_tree().paused = false
	pause_overlay.queue_free()
	pause_overlay = null
	SceneRouter.goto("res://scenes/MainMenu.tscn")

func _on_replay() -> void:
	get_tree().paused = false
	pause_overlay.queue_free()
	pause_overlay = null
	SceneRouter.goto("res://scenes/GameScene.tscn")

# ============================================================
# FIN DE SESSION
# ============================================================
func end_session() -> void:
	session_running = false
	awaiting_input = false
	AudioManager.play_sfx("end")
	AudioManager.stop_music()
	SceneRouter.goto("res://scenes/EndScene.tscn")

# ============================================================
# COMPTE A REBOURS
# ============================================================
func show_countdown(on_done: Callable) -> void:
	countdown_label = Label.new()
	countdown_label.text = "3"
	countdown_label.anchor_left = 0.5
	countdown_label.anchor_right = 0.5
	countdown_label.anchor_top = 0.5
	countdown_label.anchor_bottom = 0.5
	countdown_label.offset_left = -100
	countdown_label.offset_right = 100
	countdown_label.offset_top = -100
	countdown_label.offset_bottom = 100
	countdown_label.add_theme_color_override("font_color", ThemeManager.ACCENT_2)
	countdown_label.add_theme_font_size_override("font_size", ThemeManager.scaled_i(200))
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(countdown_label)
	for v in [3, 2, 1]:
		countdown_label.text = str(v)
		countdown_label.scale = Vector2(1.5, 1.5)
		countdown_label.modulate.a = 1.0
		var tw := create_tween()
		tw.parallel().tween_property(countdown_label, "scale", Vector2.ONE, 0.8)
		tw.parallel().tween_property(countdown_label, "modulate:a", 0.0, 0.8)
		await tw.finished
	countdown_label.queue_free()
	countdown_label = null
	on_done.call()

# ============================================================
# VOIX
# ============================================================
func _on_voice_down() -> void:
	VoiceManager.start_listening()

func _on_voice_up() -> void:
	VoiceManager.stop_listening()

func _on_stt_result(text: String) -> void:
	var n = VoiceManager.text_to_number(text)
	if n != null:
		answer_input.text = str(n)
		if GameState.options.auto_validate or GameState.options.mode == GameState.Mode.AUDIO:
			_on_submit(answer_input.text)

func _on_tts_finished() -> void:
	if mode_handler and mode_handler.has_method("on_tts_done"):
		mode_handler.on_tts_done()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if pause_overlay != null: return
		_on_pause()
