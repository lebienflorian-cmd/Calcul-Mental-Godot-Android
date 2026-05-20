extends Control
# ============================================================
# GAME SCENE — Gère les 5 modes. UI commune : barre du haut, panneau
# calcul, champ de réponse, clavier numérique tactile.
# ============================================================

# UI
var top_label: Label
var top_right_label: Label
var calc_panel: PanelContainer
var calc_renderer: MathRenderer
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
var _mic_active: bool = false
var _voice_was_active: bool = false   # mic was active when last answer was submitted
var _q_timer_armed: bool = false
var _auto_submit_timer: float = -1.0

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

# Effets visuels
var _neon_sweep: NeonSweep = null
var _symbols_bg: SymbolsBg = null
var _bokeh_bg: BokehBg = null

func _ready() -> void:
	AudioManager.play_music("game")
	AudioManager.play_sfx("start")
	GameState.reset_session()
	_build_ui()
	_init_handler()
	set_process(true)
	set_process_input(true)
	GameState.options_changed.connect(func():
		if is_instance_valid(_neon_sweep):
			# Ne pas écraser la visibilité si un flash est en cours
			if _neon_sweep._flash_time_left <= 0:
				_neon_sweep.visible = bool(GameState.options.show_neon)
		var _bg_type := str(GameState.options.game_bg)
		var _par_on  := bool(GameState.options.show_parallax)
		if is_instance_valid(_symbols_bg):
			_symbols_bg.visible = _par_on and (_bg_type == "rects" or _bg_type == "rects_colors")
			_symbols_bg.with_colors = (_bg_type == "rects_colors")
		if is_instance_valid(_bokeh_bg):
			_bokeh_bg.visible = _par_on and (_bg_type == "bokeh"))

# ============================================================
# UI BUILD
# ============================================================
func _build_ui() -> void:
	var vp  := get_viewport_rect().size
	var vw  := vp.x
	var vh  := vp.y
	var hm  := maxf(16.0, vw * 0.04)
	var sc  := ThemeManager.ui_scale

	# Fond
	var bg := ColorRect.new()
	bg.color = ThemeManager.BG
	bg.anchor_right = 1.0; bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Fonds animés (derrière tous les éléments UI)
	var _bg_init_type := str(GameState.options.game_bg)
	var _par_init := bool(GameState.options.show_parallax)

	_symbols_bg = SymbolsBg.new()
	_symbols_bg.with_colors = (_bg_init_type == "rects_colors")
	_symbols_bg.visible = _par_init and (_bg_init_type == "rects" or _bg_init_type == "rects_colors")
	add_child(_symbols_bg)

	_bokeh_bg = BokehBg.new()
	_bokeh_bg.visible = _par_init and (_bg_init_type == "bokeh")
	add_child(_bokeh_bg)

	# ── BARRE SUPÉRIEURE (pas de fond, éléments posés) ──────
	var top_y := maxf(12.0, vh * 0.018)

	# Bouton pause — plus gros, conteneur sombre avec contour
	pause_btn = Button.new()
	pause_btn.text = "❚❚"
	var pause_sz := ThemeManager.scaled_i(64)
	pause_btn.custom_minimum_size = Vector2(pause_sz, pause_sz)
	pause_btn.anchor_left = 0.0; pause_btn.anchor_top = 0.0
	pause_btn.offset_left = hm
	pause_btn.offset_top = top_y
	pause_btn.add_theme_color_override("font_color", ThemeManager.TEXT)
	pause_btn.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_LARGE))
	var pr := ThemeManager.scaled_i(16)
	pause_btn.add_theme_stylebox_override("normal",
			ThemeManager.sbox(ThemeManager.SURFACE_2, pr, 0, 0, 0, 0,
					ThemeManager.BORDER_2, 2))
	pause_btn.add_theme_stylebox_override("hover",
			ThemeManager.sbox(ThemeManager.SURFACE_2, pr, 0, 0, 0, 0,
					ThemeManager.BORDER_2, 2))
	pause_btn.add_theme_stylebox_override("focus",
			ThemeManager.sbox(ThemeManager.SURFACE_2, pr, 0, 0, 0, 0,
					ThemeManager.BORDER_2, 2))
	pause_btn.add_theme_stylebox_override("pressed",
			ThemeManager.sbox(ThemeManager.SURFACE_2.darkened(0.1), pr))
	pause_btn.pressed.connect(_on_pause)
	_wire_tap_flash(pause_btn,
		ThemeManager.sbox(ThemeManager.SURFACE_2, pr, 0, 0, 0, 0, ThemeManager.BORDER_2, 2),
		ThemeManager.sbox(ThemeManager.SURFACE_3.lightened(0.2), pr, 0, 0, 0, 0, ThemeManager.ACCENT, 2))
	add_child(pause_btn)

	# Chrono (conteneur arrondi à droite, contour orange/visible)
	var is_serie: bool = (GameState.options.mode == GameState.Mode.SERIE_CHRONO)
	var is_flash: bool = (GameState.options.mode == GameState.Mode.FLASH_ANZAN)
	var chrono_panel := PanelContainer.new()
	chrono_panel.anchor_left = 1.0; chrono_panel.anchor_right = 1.0
	chrono_panel.anchor_top = 0.0
	var cp_w := ThemeManager.scaled_i(112)
	var cp_h := pause_sz
	if is_serie:
		cp_w = ThemeManager.scaled_i(112)
		cp_h = ThemeManager.scaled_i(80)
	elif is_flash:
		cp_w = ThemeManager.scaled_i(150)
	var chrono_right_margin := hm + ThemeManager.scaled_i(6)
	chrono_panel.offset_left = -chrono_right_margin - cp_w
	chrono_panel.offset_right = -chrono_right_margin
	chrono_panel.offset_top = top_y
	chrono_panel.offset_bottom = top_y + cp_h
	chrono_panel.add_theme_stylebox_override("panel",
			ThemeManager.sbox(ThemeManager.SURFACE_2, ThemeManager.scaled_i(20),
					ThemeManager.scaled_i(10), ThemeManager.scaled_i(10),
					ThemeManager.scaled_i(6),  ThemeManager.scaled_i(6),
					Color(ThemeManager.ACCENT_2.r, ThemeManager.ACCENT_2.g,
							ThemeManager.ACCENT_2.b, 0.45), 2))
	add_child(chrono_panel)

	if is_serie:
		# Mode série : VBox avec score en haut + chrono en bas
		var chrono_vb := VBoxContainer.new()
		chrono_vb.add_theme_constant_override("separation", ThemeManager.scaled_i(2))
		chrono_vb.alignment = BoxContainer.ALIGNMENT_CENTER
		chrono_panel.add_child(chrono_vb)

		# Ligne 1 : ⏱ + score (0/20)
		top_right_label = Label.new()
		top_right_label.add_theme_color_override("font_color", ThemeManager.ACCENT_2)
		top_right_label.add_theme_font_size_override("font_size",
				ThemeManager.scaled_i(ThemeManager.FONT_MED))
		top_right_label.add_theme_font_override("font", ThemeDB.fallback_font)
		top_right_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		top_right_label.clip_text = true
		chrono_vb.add_child(top_right_label)

		# Le handler de série met tout dans top_right_label.text.
		# On va surveiller dans _process et séparer les lignes.
	else:
		var chrono_row := HBoxContainer.new()
		chrono_row.add_theme_constant_override("separation", ThemeManager.scaled_i(4))
		chrono_row.alignment = BoxContainer.ALIGNMENT_CENTER
		chrono_panel.add_child(chrono_row)

		var chrono_icon := Label.new()
		chrono_icon.text = "⏱"
		chrono_icon.add_theme_color_override("font_color", ThemeManager.ACCENT_2)
		chrono_icon.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_SMALL))
		chrono_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		chrono_row.add_child(chrono_icon)

		top_right_label = Label.new()
		top_right_label.add_theme_color_override("font_color", ThemeManager.ACCENT_2)
		top_right_label.add_theme_font_size_override("font_size",
				ThemeManager.scaled_i(ThemeManager.FONT_SMALL))
		top_right_label.add_theme_font_override("font", ThemeDB.fallback_font)
		top_right_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		top_right_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		top_right_label.clip_text = true
		top_right_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		top_right_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chrono_row.add_child(top_right_label)

	# Label mode — centré entre pause et chrono
	top_label = Label.new()
	var label_left := hm + pause_sz + ThemeManager.scaled_i(8)
	var label_right := chrono_right_margin + cp_w + ThemeManager.scaled_i(8)
	top_label.anchor_left = 0.0; top_label.anchor_right = 1.0
	top_label.offset_left = label_left; top_label.offset_right = -label_right
	top_label.offset_top = top_y
	top_label.offset_bottom = top_y + pause_sz
	top_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_label.add_theme_color_override("font_color", ThemeManager.TEXT)
	top_label.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_MED))
	top_label.clip_text = true
	top_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_label)

	# ── PANNEAU CALCUL ──────────────────────────────────────
	var calc_top := top_y + pause_sz + vh * 0.025
	var calc_bot := calc_top + vh * 0.26
	calc_panel = PanelContainer.new()
	calc_panel.anchor_left = 0.0; calc_panel.anchor_right = 1.0
	calc_panel.offset_left = hm; calc_panel.offset_right = -hm
	calc_panel.offset_top = calc_top; calc_panel.offset_bottom = calc_bot
	# Fond plus sombre avec bordure subtile
	calc_panel.add_theme_stylebox_override("panel",
			ThemeManager.sbox(ThemeManager.SURFACE,
					ThemeManager.scaled_i(18),
					ThemeManager.scaled_i(16), ThemeManager.scaled_i(16),
					ThemeManager.scaled_i(14), ThemeManager.scaled_i(14),
					ThemeManager.BORDER_2, 2))
	add_child(calc_panel)

	var calc_vb := VBoxContainer.new()
	calc_vb.add_theme_constant_override("separation", ThemeManager.scaled_i(12))
	calc_panel.add_child(calc_vb)

	# Spacer pour pousser "Calculez mentalement" plus bas
	var calc_sp := Control.new()
	calc_sp.custom_minimum_size = Vector2(0, ThemeManager.scaled_i(4))
	calc_vb.add_child(calc_sp)

	var hdr := Label.new()
	hdr.text = "Calculez mentalement"
	hdr.add_theme_color_override("font_color", ThemeManager.TEXT_DIM)
	hdr.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_SMALL))
	hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	calc_vb.add_child(hdr)

	calc_renderer = MathRenderer.new()
	calc_renderer.font_size = ThemeManager.scaled_i(108)
	calc_renderer.text_color = ThemeManager.TEXT
	calc_renderer.op_color = ThemeManager.TEXT_DIM
	calc_renderer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	calc_renderer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	calc_vb.add_child(calc_renderer)

	# Lueur néon autour du panneau de calcul
	_neon_sweep = NeonSweep.new()
	_neon_sweep.panel_rect = Rect2(Vector2(hm, calc_top), Vector2(vw - 2.0 * hm, calc_bot - calc_top))
	_neon_sweep.visible = bool(GameState.options.show_neon)
	add_child(_neon_sweep)

	# Label anzan (caché par défaut)
	anzan_label = Label.new()
	anzan_label.text = ""
	anzan_label.add_theme_color_override("font_color", ThemeManager.ACCENT)
	anzan_label.add_theme_font_size_override("font_size", ThemeManager.scaled_i(180))
	anzan_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	anzan_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	anzan_label.anchor_left = 0.0; anzan_label.anchor_right = 1.0
	anzan_label.offset_top = calc_top; anzan_label.offset_bottom = calc_bot
	anzan_label.visible = false
	add_child(anzan_label)

	# Panneau infernal
	var second_top := calc_bot + vh * 0.01
	var second_bot := second_top + vh * 0.09
	second_panel = PanelContainer.new()
	second_panel.anchor_left = 0.0; second_panel.anchor_right = 1.0
	second_panel.offset_left = hm; second_panel.offset_right = -hm
	second_panel.offset_top = second_top; second_panel.offset_bottom = second_bot
	second_panel.add_theme_stylebox_override("panel",
			ThemeManager.sbox(ThemeManager.ACCENT_2.darkened(0.5),
					ThemeManager.scaled_i(18),
					ThemeManager.scaled_i(14), ThemeManager.scaled_i(14),
					ThemeManager.scaled_i(8),  ThemeManager.scaled_i(8),
					ThemeManager.BORDER_2, 1))
	second_panel.visible = false
	add_child(second_panel)
	second_label = Label.new()
	second_label.text = "???? ="
	second_label.add_theme_color_override("font_color", ThemeManager.ACCENT_2)
	second_label.add_theme_font_size_override("font_size", ThemeManager.scaled_i(56))
	second_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	second_panel.add_child(second_label)

	# ── CHAMP DE RÉPONSE + BACKSPACE ────────────────────────
	var ans_gap := vh * 0.140        # espace calcul → réponse
	var kpad_ans_gap := vh * 0.02   # espace réponse → touches
	var ans_top := calc_bot + ans_gap
	var ans_h   := ThemeManager.scaled_i(135)
	var ans_row := HBoxContainer.new()
	ans_row.anchor_left = 0.0; ans_row.anchor_right = 1.0
	ans_row.offset_left = hm; ans_row.offset_right = -hm
	ans_row.offset_top = ans_top; ans_row.offset_bottom = ans_top + ans_h
	ans_row.add_theme_constant_override("separation", ThemeManager.scaled_i(10))
	add_child(ans_row)

	answer_input = LineEdit.new()
	answer_input.virtual_keyboard_enabled = false
	answer_input.placeholder_text = "Réponse"
	answer_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	answer_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	answer_input.add_theme_font_size_override("font_size", ThemeManager.scaled_i(40))
	answer_input.add_theme_color_override("font_color", ThemeManager.TEXT)
	answer_input.add_theme_color_override("font_placeholder_color",
			Color(ThemeManager.TEXT.r, ThemeManager.TEXT.g, ThemeManager.TEXT.b, 0.4))
	var ans_r := ThemeManager.scaled_i(14)
	var ans_pad := ThemeManager.scaled_i(14)
	answer_input.add_theme_stylebox_override("normal",
			ThemeManager.sbox(Color(0.08, 0.14, 0.28), ans_r,
					ans_pad, ans_pad, ans_pad, ans_pad,
					Color(0.25, 0.45, 0.85, 0.6), 2))
	answer_input.add_theme_stylebox_override("focus",
			ThemeManager.sbox(Color(0.10, 0.18, 0.35), ans_r,
					ans_pad, ans_pad, ans_pad, ans_pad,
					ThemeManager.ACCENT, 2))
	answer_input.text_submitted.connect(_on_submit)
	ans_row.add_child(answer_input)

	# Bouton backspace — carré, même hauteur que le champ
	var backspace_btn := Button.new()
	backspace_btn.text = "⌫"
	backspace_btn.custom_minimum_size = Vector2(ans_h, ans_h)
	backspace_btn.add_theme_color_override("font_color", ThemeManager.TEXT)
	backspace_btn.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_LARGE))
	var bs_r := ThemeManager.scaled_i(12)
	backspace_btn.add_theme_stylebox_override("normal",
			ThemeManager.sbox(ThemeManager.ERROR.darkened(0.30), bs_r, 0, 0, 0, 0,
					ThemeManager.ERROR.darkened(0.05), 2))
	backspace_btn.add_theme_stylebox_override("hover",
			ThemeManager.sbox(ThemeManager.ERROR.darkened(0.30), bs_r, 0, 0, 0, 0,
					ThemeManager.ERROR.darkened(0.05), 2))
	backspace_btn.add_theme_stylebox_override("focus",
			ThemeManager.sbox(ThemeManager.ERROR.darkened(0.30), bs_r, 0, 0, 0, 0,
					ThemeManager.ERROR.darkened(0.05), 2))
	backspace_btn.add_theme_stylebox_override("pressed",
			ThemeManager.sbox(ThemeManager.ERROR.darkened(0.45), bs_r))
	backspace_btn.pressed.connect(func(): _on_keypad("⌫"))
	_wire_tap_flash(backspace_btn,
		ThemeManager.sbox(ThemeManager.ERROR.darkened(0.30), bs_r, 0, 0, 0, 0, ThemeManager.ERROR.darkened(0.05), 2),
		ThemeManager.sbox(ThemeManager.ERROR.lightened(0.15), bs_r, 0, 0, 0, 0, ThemeManager.ERROR.lightened(0.1), 2))
	backspace_btn.visible = int(GameState.options.mode) != GameState.Mode.AUDIO
	ans_row.add_child(backspace_btn)

	# Bouton micro
	voice_btn = Button.new()
	voice_btn.text = ""
	var _mic_icon := _MicIcon.new()
	_mic_icon.anchor_right = 1.0; _mic_icon.anchor_bottom = 1.0
	_mic_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	voice_btn.add_child(_mic_icon)
	voice_btn.custom_minimum_size = Vector2(ans_h, ans_h)
	voice_btn.add_theme_color_override("font_color", ThemeManager.TEXT)
	voice_btn.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_LARGE))
	voice_btn.add_theme_stylebox_override("normal",
			ThemeManager.sbox(ThemeManager.ACCENT, ThemeManager.scaled_i(30)))
	voice_btn.add_theme_stylebox_override("hover",
			ThemeManager.sbox(ThemeManager.ACCENT, ThemeManager.scaled_i(30)))
	voice_btn.add_theme_stylebox_override("focus",
			ThemeManager.sbox(ThemeManager.ACCENT, ThemeManager.scaled_i(30)))
	voice_btn.add_theme_stylebox_override("pressed",
			ThemeManager.sbox(ThemeManager.ERROR, ThemeManager.scaled_i(30)))
	voice_btn.visible = bool(GameState.options.voice_input) or int(GameState.options.mode) == GameState.Mode.AUDIO
	voice_btn.pressed.connect(func(): set_mic_active(not _mic_active))
	ans_row.add_child(voice_btn)
	VoiceManager.stt_result.connect(_on_stt_result)
	VoiceManager.stt_partial.connect(_on_stt_partial)
	VoiceManager.tts_finished.connect(_on_tts_finished)
	VoiceManager.tts_started.connect(_on_tts_started)

	# ── CLAVIER NUMÉRIQUE ───────────────────────────────────
	var is_audio_mode: bool = int(GameState.options.mode) == GameState.Mode.AUDIO
	var kpad_gap := ThemeManager.scaled_i(12)
	var kpad_top := ans_top + ans_h + kpad_ans_gap
	var kpad_bot := vh * 0.945

	keypad_grid = GridContainer.new()
	keypad_grid.columns = 3
	keypad_grid.anchor_left = 0.0; keypad_grid.anchor_right = 1.0
	keypad_grid.offset_left = hm; keypad_grid.offset_right = -hm
	keypad_grid.offset_top = kpad_top; keypad_grid.offset_bottom = kpad_bot
	keypad_grid.add_theme_constant_override("h_separation", kpad_gap)
	keypad_grid.add_theme_constant_override("v_separation", kpad_gap)
	keypad_grid.visible = not is_audio_mode
	add_child(keypad_grid)

	var kpad_w := vw - hm * 2.0
	var btn_w := maxf(80.0, (kpad_w - kpad_gap * 2.0) / 3.0)
	var btn_h := maxf(48.0, ((kpad_bot - kpad_top) - kpad_gap * 3.0) / 4.0)
	var key_r := ThemeManager.scaled_i(12)
	# Bordure des touches plus visible
	var key_border_col := Color(ThemeManager.BORDER_2.r, ThemeManager.BORDER_2.g,
			ThemeManager.BORDER_2.b, 1.0).lightened(0.15)

	for k in ["7","8","9","4","5","6","1","2","3","-","0","✓"]:
		var b := Button.new()
		b.text = k
		b.custom_minimum_size = Vector2(btn_w, btn_h)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_vertical   = Control.SIZE_EXPAND_FILL
		b.add_theme_color_override("font_color", ThemeManager.TEXT)
		b.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_LARGE + 2))
		b.add_theme_font_override("font", ThemeDB.fallback_font)

		var key_bg: Color
		var kb: Color
		if k == "✓":
			key_bg = ThemeManager.SUCCESS
			kb = ThemeManager.SUCCESS.lightened(0.25)
		else:
			key_bg = ThemeManager.SURFACE_2
			kb = key_border_col

		b.add_theme_stylebox_override("normal",
				ThemeManager.sbox(key_bg, key_r,
						ThemeManager.scaled_i(4), ThemeManager.scaled_i(4),
						ThemeManager.scaled_i(4), ThemeManager.scaled_i(4),
						kb, 2))
		b.add_theme_stylebox_override("hover",
				ThemeManager.sbox(key_bg, key_r,
						ThemeManager.scaled_i(4), ThemeManager.scaled_i(4),
						ThemeManager.scaled_i(4), ThemeManager.scaled_i(4),
						kb, 2))
		b.add_theme_stylebox_override("focus",
				ThemeManager.sbox(key_bg, key_r,
						ThemeManager.scaled_i(4), ThemeManager.scaled_i(4),
						ThemeManager.scaled_i(4), ThemeManager.scaled_i(4),
						kb, 2))
		b.add_theme_stylebox_override("pressed",
				ThemeManager.sbox(key_bg.darkened(0.15), key_r,
						ThemeManager.scaled_i(4), ThemeManager.scaled_i(4),
						ThemeManager.scaled_i(4), ThemeManager.scaled_i(4),
						kb.darkened(0.2), 2))

		var key: String = k
		b.pressed.connect(func(): _on_keypad(key))
		if k == "✓": validate_btn = b
		var _flash_bg: Color = key_bg.lightened(0.20)
		var _flash_kb: Color = kb.lightened(0.15)
		_wire_tap_flash(b,
			ThemeManager.sbox(key_bg, key_r, ThemeManager.scaled_i(4), ThemeManager.scaled_i(4), ThemeManager.scaled_i(4), ThemeManager.scaled_i(4), kb, 2),
			ThemeManager.sbox(_flash_bg, key_r, ThemeManager.scaled_i(4), ThemeManager.scaled_i(4), ThemeManager.scaled_i(4), ThemeManager.scaled_i(4), _flash_kb, 2))
		keypad_grid.add_child(b)

	# ── BOUTONS MODE AUDIO (Répéter / Passer) ───────────────────
	if is_audio_mode:
		var audio_vb := VBoxContainer.new()
		audio_vb.anchor_left = 0.0; audio_vb.anchor_right = 1.0
		audio_vb.offset_left = hm; audio_vb.offset_right = -hm
		audio_vb.offset_top = kpad_top; audio_vb.offset_bottom = kpad_bot
		audio_vb.add_theme_constant_override("separation", kpad_gap)
		add_child(audio_vb)

		var ab_r := ThemeManager.scaled_i(18)

		var repeat_btn := Button.new()
		repeat_btn.text = "🔁  Répéter"
		repeat_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		repeat_btn.add_theme_color_override("font_color", ThemeManager.TEXT)
		repeat_btn.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_LARGE))
		repeat_btn.add_theme_font_override("font", ThemeDB.fallback_font)
		repeat_btn.add_theme_stylebox_override("normal",
				ThemeManager.sbox(ThemeManager.ACCENT.darkened(0.25), ab_r,
						0, 0, 0, 0, ThemeManager.ACCENT.darkened(0.05), 2))
		repeat_btn.add_theme_stylebox_override("hover",
				ThemeManager.sbox(ThemeManager.ACCENT.darkened(0.25), ab_r,
						0, 0, 0, 0, ThemeManager.ACCENT.darkened(0.05), 2))
		repeat_btn.add_theme_stylebox_override("focus",
				ThemeManager.sbox(ThemeManager.ACCENT.darkened(0.25), ab_r,
						0, 0, 0, 0, ThemeManager.ACCENT.darkened(0.05), 2))
		repeat_btn.add_theme_stylebox_override("pressed",
				ThemeManager.sbox(ThemeManager.ACCENT.darkened(0.40), ab_r))
		repeat_btn.pressed.connect(func():
			AudioManager.play_sfx("click")
			if mode_handler and mode_handler.has_method("repeat_audio"):
				mode_handler.repeat_audio())
		_wire_tap_flash(repeat_btn,
			ThemeManager.sbox(ThemeManager.ACCENT.darkened(0.25), ab_r, 0, 0, 0, 0, ThemeManager.ACCENT.darkened(0.05), 2),
			ThemeManager.sbox(ThemeManager.ACCENT.lightened(0.20), ab_r, 0, 0, 0, 0, ThemeManager.ACCENT.lightened(0.15), 2))
		audio_vb.add_child(repeat_btn)

		var skip_btn := Button.new()
		skip_btn.text = "⏭  Passer"
		skip_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		skip_btn.add_theme_color_override("font_color", ThemeManager.TEXT)
		skip_btn.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_LARGE))
		skip_btn.add_theme_font_override("font", ThemeDB.fallback_font)
		skip_btn.add_theme_stylebox_override("normal",
				ThemeManager.sbox(ThemeManager.SURFACE_2, ab_r,
						0, 0, 0, 0, ThemeManager.BORDER_2, 2))
		skip_btn.add_theme_stylebox_override("hover",
				ThemeManager.sbox(ThemeManager.SURFACE_2, ab_r,
						0, 0, 0, 0, ThemeManager.BORDER_2, 2))
		skip_btn.add_theme_stylebox_override("focus",
				ThemeManager.sbox(ThemeManager.SURFACE_2, ab_r,
						0, 0, 0, 0, ThemeManager.BORDER_2, 2))
		skip_btn.add_theme_stylebox_override("pressed",
				ThemeManager.sbox(ThemeManager.SURFACE_2.darkened(0.15), ab_r))
		skip_btn.pressed.connect(func():
			AudioManager.play_sfx("click")
			_on_submit(""))
		_wire_tap_flash(skip_btn,
			ThemeManager.sbox(ThemeManager.SURFACE_2, ab_r, 0, 0, 0, 0, ThemeManager.BORDER_2, 2),
			ThemeManager.sbox(ThemeManager.SURFACE_3.lightened(0.25), ab_r, 0, 0, 0, 0, ThemeManager.ACCENT, 2))
		audio_vb.add_child(skip_btn)

	# ── HINT EN BAS (Valider : ✓ | Pause : ‖) ──────────────
	hint_label = Label.new()
	hint_label.anchor_left = 0.0; hint_label.anchor_right = 1.0
	hint_label.anchor_top = 1.0; hint_label.anchor_bottom = 1.0
	hint_label.offset_left = hm; hint_label.offset_right = -hm
	hint_label.offset_top = -ThemeManager.scaled_i(32)
	hint_label.offset_bottom = -ThemeManager.scaled_i(8)
	hint_label.text = "⊘ Valider : ✓   |   Pause : ‖"
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_color_override("font_color", ThemeManager.TEXT_DIM)
	hint_label.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_TINY))
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
	if GameState.options.auto_validate and awaiting_input:
		_auto_submit_timer = maxf(0.1, float(GameState.options.auto_validate_delay))

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
func show_calc(expr: String, hide: bool = false, tree: Dictionary = {}) -> void:
	if hide:
		calc_renderer.fallback_text = "🔊 Calcul N°%d" % (GameState.session.answers.size() + 1)
		calc_renderer.expr_tree = {}
	else:
		calc_renderer.fallback_text = expr
		calc_renderer.expr_tree = tree
	var _dm := 0
	if bool(GameState.options.show_column):
		_dm = 2
	elif bool(GameState.options.show_fractions):
		_dm = 1
	calc_renderer.display_mode = _dm
	calc_renderer.font_size = ThemeManager.scaled_i(108)
	calc_renderer.queue_redraw()
	answer_input.text = ""
	answer_input.grab_focus()
	awaiting_input = true
	question_start_ms = Time.get_ticks_msec()
	_q_timer_armed = GameState.options.max_time_per_q > 0
	if bool(GameState.options.voice_input) and int(GameState.options.mode) != GameState.Mode.AUDIO and _voice_was_active:
		set_mic_active(true)
	calc_panel.scale = Vector2(0.9, 0.9)
	var tw := create_tween()
	tw.tween_property(calc_panel, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK)

func feedback(ok: bool) -> void:
	awaiting_input = false
	_auto_submit_timer = -1.0
	if bool(GameState.options.voice_input) and int(GameState.options.mode) != GameState.Mode.AUDIO:
		_voice_was_active = _mic_active
		set_mic_active(false)
	if ok:
		AudioManager.play_sfx("correct")
		_pulse_glow(ThemeManager.SUCCESS)
		if bool(GameState.options.green_correct) and is_instance_valid(_neon_sweep):
			_neon_sweep.trigger_flash()
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

var _last_second_text: String = ""

func _process(delta: float) -> void:
	# Glow autour du panneau
	if glow_alpha > 0:
		queue_redraw()
	# Alignement de second_label selon préfixe [
	if second_label and second_label.text != _last_second_text:
		_last_second_text = second_label.text
		if second_label.text.begins_with("["):
			second_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		else:
			second_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Timer par question : auto-soumission si max_time_per_q dépassé
	if _q_timer_armed and awaiting_input:
		var elapsed := (Time.get_ticks_msec() - question_start_ms) / 1000.0
		time_left = GameState.options.max_time_per_q - elapsed
		if time_left <= 0.0:
			_q_timer_armed = false
			_on_submit(answer_input.text)
	# Validation automatique après 1.5 s sans activité clavier
	if _auto_submit_timer >= 0.0 and awaiting_input:
		_auto_submit_timer -= delta
		if _auto_submit_timer <= 0.0:
			_auto_submit_timer = -1.0
			if GameState.options.auto_validate and awaiting_input:
				_on_submit(answer_input.text)

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
	# Positionner le label exactement sur le calc_panel (centré dedans)
	if calc_panel:
		var r := calc_panel.get_rect()
		countdown_label.anchor_left = 0.0; countdown_label.anchor_right = 0.0
		countdown_label.anchor_top = 0.0; countdown_label.anchor_bottom = 0.0
		countdown_label.offset_left = r.position.x
		countdown_label.offset_right = r.position.x + r.size.x
		countdown_label.offset_top = r.position.y
		countdown_label.offset_bottom = r.position.y + r.size.y
	else:
		countdown_label.anchor_left = 0.5; countdown_label.anchor_right = 0.5
		countdown_label.anchor_top = 0.5; countdown_label.anchor_bottom = 0.5
		countdown_label.offset_left = -120; countdown_label.offset_right = 120
		countdown_label.offset_top = -120; countdown_label.offset_bottom = 120
	countdown_label.add_theme_color_override("font_color", ThemeManager.ACCENT_2)
	countdown_label.add_theme_font_size_override("font_size", ThemeManager.scaled_i(160))
	countdown_label.add_theme_font_override("font", ThemeDB.fallback_font)
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(countdown_label)
	for v in [3, 2, 1]:
		countdown_label.text = str(v)
		countdown_label.scale = Vector2(1.5, 1.5)
		countdown_label.pivot_offset = countdown_label.size / 2.0
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
func set_mic_active(active: bool) -> void:
	_mic_active = active
	var r := ThemeManager.scaled_i(30)
	if active:
		VoiceManager.start_listening()
		voice_btn.add_theme_stylebox_override("normal",
				ThemeManager.sbox(ThemeManager.ERROR, r))
		voice_btn.add_theme_stylebox_override("hover",
				ThemeManager.sbox(ThemeManager.ERROR, r))
		voice_btn.add_theme_stylebox_override("focus",
				ThemeManager.sbox(ThemeManager.ERROR, r))
	else:
		VoiceManager.stop_listening()
		voice_btn.add_theme_stylebox_override("normal",
				ThemeManager.sbox(ThemeManager.ACCENT, r))
		voice_btn.add_theme_stylebox_override("hover",
				ThemeManager.sbox(ThemeManager.ACCENT, r))
		voice_btn.add_theme_stylebox_override("focus",
				ThemeManager.sbox(ThemeManager.ACCENT, r))

func _on_stt_result(text: String) -> void:
	var t_low := text.to_lower().strip_edges()
	# Commandes vocales
	if "répète" in t_low or "répéter" in t_low or "repete" in t_low or "repeter" in t_low:
		if mode_handler and mode_handler.has_method("repeat_audio"):
			mode_handler.repeat_audio()
		return
	if "passe" in t_low or "passer" in t_low or "suivant" in t_low or "skip" in t_low:
		_on_submit("")
		return
	# Reconnaissance de nombre
	var n = VoiceManager.text_to_number(text)
	if n != null:
		answer_input.text = str(n)
		if GameState.options.auto_validate or GameState.options.mode == GameState.Mode.AUDIO:
			_on_submit(answer_input.text)

func _on_stt_partial(text: String) -> void:
	if not awaiting_input or not _mic_active: return
	var n = VoiceManager.text_to_number(text)
	answer_input.text = str(n) if n != null else text

func _on_tts_finished() -> void:
	if mode_handler and mode_handler.has_method("on_tts_done"):
		mode_handler.on_tts_done()

func _on_tts_started() -> void:
	if mode_handler and mode_handler.has_method("on_tts_started"):
		mode_handler.on_tts_started()

func _exit_tree() -> void:
	for conn in GameState.options_changed.get_connections():
		if conn.callable.get_object() == self:
			GameState.options_changed.disconnect(conn.callable)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if pause_overlay != null: return
		_on_pause()
	elif what == NOTIFICATION_PREDELETE:
		VoiceManager.shutdown_stt()

# Bref flash visuel sur tap rapide (< 250 ms), rien sur maintien appuyé.
func _wire_tap_flash(btn: Button, st_normal: StyleBox, st_flash: StyleBox) -> void:
	var t0 := [0]
	btn.button_down.connect(func(): t0[0] = Time.get_ticks_msec())
	btn.button_up.connect(func():
		if not is_instance_valid(btn): return
		if Time.get_ticks_msec() - t0[0] < 250:
			btn.add_theme_stylebox_override("normal", st_flash)
			btn.add_theme_stylebox_override("hover",  st_flash)
			var tw := btn.create_tween()
			tw.tween_interval(0.10)
			tw.tween_callback(func():
				if is_instance_valid(btn):
					btn.add_theme_stylebox_override("normal", st_normal)
					btn.add_theme_stylebox_override("hover",  st_normal)))

# ── Icône microphone (dessinée, cross-platform) ─────────────
class _MicIcon extends Control:
	func _ready() -> void:
		resized.connect(queue_redraw)
		queue_redraw()
	func _draw() -> void:
		var s := minf(size.x, size.y)
		if s <= 0: return
		var c := Vector2(size.x * 0.5, size.y * 0.5)
		var r := s * 0.114
		var lw := maxf(1.5, s * 0.06)
		var col := Color.WHITE
		# Corps capsule (rectangle + demi-cercle du haut)
		draw_rect(Rect2(c.x - r, c.y - r * 1.4, r * 2, r * 1.9), col)
		draw_arc(Vector2(c.x, c.y - r * 1.4), r, 0, PI, 24, col, lw * 0.6, true)
		draw_arc(Vector2(c.x, c.y + r * 0.5), r, PI, TAU, 24, col, lw * 0.6, true)
		# Arc extérieur (oreille du micro)
		draw_arc(c + Vector2(0, -r * 0.45), r * 1.55, deg_to_rad(195), deg_to_rad(345), 24, col, lw)
		# Pied vertical + base horizontale
		var base_y := c.y + r * 1.1
		draw_line(Vector2(c.x, base_y), Vector2(c.x, base_y + r * 0.85), col, lw)
		draw_line(Vector2(c.x - r * 0.75, base_y + r * 0.85),
				  Vector2(c.x + r * 0.75, base_y + r * 0.85), col, lw)
