extends Control
# ============================================================
# END SCENE — Résultats : score, stats détaillées, table.
# Refonte : header, étoile, stats en 2 colonnes avec icônes,
# dropdown slow_percent, boutons d'action stylés.
# ============================================================

var stats: Dictionary = {}
var saved_today: int = 0
var was_new_best: bool = false
var slow_percent: int = 20
var _scroll: ScrollContainer
var _scroll_velocity: float = 0.0
var _is_touching: bool = false
var _touch_history: Array = []
var _table_container: VBoxContainer = null
var _slow_dd: OptionButton

func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	stats = GameState.compute_final_stats()
	saved_today = ScoreManager.get_daily_best(stats.mode)
	ScoreManager.add_session(stats)
	was_new_best = ScoreManager.set_daily_best_if_better(stats.mode, stats.score)
	if was_new_best:
		AudioManager.play_sfx("save")
	_build_ui()
	set_process(true)

func _build_ui() -> void:
	var hdr_h := ThemeManager.scaled_i(ThemeManager.HEADER_HEIGHT)
	var pad := ThemeManager.scaled_i(14)

	# Fond
	var bg := ColorRect.new()
	bg.color = ThemeManager.BG
	bg.anchor_right = 1.0; bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# === EN-TÊTE ===
	var header := Control.new()
	header.anchor_left = 0.0; header.anchor_right = 1.0
	header.custom_minimum_size = Vector2(0, hdr_h)
	header.anchor_bottom = 0.0; header.offset_bottom = hdr_h
	add_child(header)

	# Bouton retour
	var back := Button.new()
	back.text = "‹"
	var bsz := ThemeManager.scaled_i(56)
	back.custom_minimum_size = Vector2(bsz, bsz)
	back.anchor_left = 0.0; back.anchor_top = 0.0
	back.offset_left = pad; back.offset_top = (hdr_h - bsz) / 2
	back.add_theme_color_override("font_color", ThemeManager.TEXT)
	back.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_TITLE))
	var r := ThemeManager.scaled_i(10)
	back.add_theme_stylebox_override("normal",  ThemeManager.sbox(Color(0,0,0,0), r))
	back.add_theme_stylebox_override("hover",   ThemeManager.sbox(Color(1,1,1,0.07), r))
	back.add_theme_stylebox_override("pressed", ThemeManager.sbox(Color(1,1,1,0.12), r))
	back.pressed.connect(func():
		AudioManager.play_sfx("back")
		SceneRouter.goto("res://scenes/MainMenu.tscn"))
	header.add_child(back)

	# Titre centré : drapeau + "Résultats"
	var title_row := HBoxContainer.new()
	title_row.anchor_left = 0.0; title_row.anchor_right = 1.0
	title_row.anchor_top = 0.0; title_row.anchor_bottom = 1.0
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	title_row.add_theme_constant_override("separation", ThemeManager.scaled_i(10))
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(title_row)

	var flag := Label.new()
	flag.text = "🏁"
	flag.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_TITLE))
	flag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_row.add_child(flag)

	var title := Label.new()
	title.text = "Résultats"
	title.add_theme_color_override("font_color", ThemeManager.TEXT)
	title.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_TITLE))
	title.add_theme_font_override("font", ThemeDB.fallback_font)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_row.add_child(title)

	# === ZONE SCROLLABLE ===
	_scroll = ScrollContainer.new()
	_scroll.anchor_left = 0.0; _scroll.anchor_right = 1.0
	_scroll.anchor_top = 0.0; _scroll.anchor_bottom = 1.0
	_scroll.offset_top = hdr_h; _scroll.offset_left = pad
	_scroll.offset_right = -pad; _scroll.offset_bottom = 0
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation",
			ThemeManager.scaled_i(ThemeManager.SECTION_GAP))
	_scroll.add_child(vb)

	_build_summary_card(vb)
	_build_slow_filter(vb)
	_build_answers_table(vb)
	_build_action_buttons(vb)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, ThemeManager.scaled_i(20))
	vb.add_child(spacer)

# ── Carte résumé : étoile + score + stats en grille 2 col ───
func _build_summary_card(parent: Node) -> void:
	var card := _card()
	parent.add_child(card)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", ThemeManager.scaled_i(12))
	card.add_child(vb)

	# Étoile dans un cercle vert (gros)
	var star_wrap := CenterContainer.new()
	star_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(star_wrap)

	var star_sz := ThemeManager.scaled_i(72)
	var star_panel := PanelContainer.new()
	star_panel.custom_minimum_size = Vector2(star_sz, star_sz)
	star_panel.add_theme_stylebox_override("panel",
			ThemeManager.sbox(Color(0.05, 0.18, 0.08),
					ThemeManager.scaled_i(36), 0, 0, 0, 0,
					ThemeManager.SUCCESS, 2))
	star_wrap.add_child(star_panel)
	var star := Label.new()
	star.text = "★"
	star.add_theme_color_override("font_color", ThemeManager.SUCCESS)
	star.add_theme_font_size_override("font_size", ThemeManager.scaled_i(40))
	star.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	star.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	star.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	star.size_flags_vertical = Control.SIZE_EXPAND_FILL
	star_panel.add_child(star)

	# Score : grand
	var score_lbl := Label.new()
	score_lbl.text = "Score : %d" % stats.score
	score_lbl.add_theme_color_override("font_color", ThemeManager.ACCENT_2)
	score_lbl.add_theme_font_size_override("font_size", ThemeManager.scaled_i(56))
	score_lbl.add_theme_font_override("font", ThemeDB.fallback_font)
	score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(score_lbl)

	# Nouveau meilleur du jour (toujours affiché si vrai)
	if was_new_best:
		var nb := Label.new()
		nb.text = "★  Nouveau meilleur du jour !"
		nb.add_theme_color_override("font_color", ThemeManager.SUCCESS)
		nb.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_MED))
		nb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(nb)

	# Séparateur
	var sep := HSeparator.new()
	sep.add_theme_stylebox_override("separator",
			ThemeManager.make_hsep_style(
					Color(ThemeManager.BORDER.r, ThemeManager.BORDER.g,
							ThemeManager.BORDER.b, 0.40)))
	vb.add_child(sep)

	# Grille de stats en 2 colonnes, chacune avec icône + label + valeur
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", ThemeManager.scaled_i(20))
	grid.add_theme_constant_override("v_separation", ThemeManager.scaled_i(14))
	vb.add_child(grid)

	_add_stat_with_icon(grid, "⏱", ThemeManager.ACCENT,        "Mode",         GameState.MODE_NAMES[stats.mode])
	_add_stat_with_icon(grid, "👤", ThemeManager.ACCENT,        "Profil",       ProfileManager.get_current())
	_add_stat_with_icon(grid, "◎", ThemeManager.ACCENT,        "Exactitude",   "%.0f %%" % (stats.accuracy * 100.0))
	_add_stat_with_icon(grid, "✓", ThemeManager.SUCCESS,       "Bonnes",       "%d / %d" % [stats.correct, stats.total])
	_add_stat_with_icon(grid, "⏲", ThemeManager.ACCENT,        "Temps moyen",  "%.2f s" % stats.avg_time)
	_add_stat_with_icon(grid, "▌", ThemeManager.ACCENT,        "Niveau",       str(stats.level))
	_add_stat_with_icon(grid, "🏆", ThemeManager.ACCENT_2,     "Meilleur jour", str(max(saved_today, stats.score)))
	_add_stat_with_icon(grid, "⏱", ThemeManager.ACCENT,        "Durée",        "%.1f s" % stats.elapsed)
	if stats.get("difficulty", "") != "":
		_add_stat_with_icon(grid, "⚡", ThemeManager.WARNING, "Difficulté", stats.difficulty)

func _add_stat_with_icon(parent: Node, icon: String, icon_color: Color,
		label: String, value: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", ThemeManager.scaled_i(10))
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(row)

	# Icône (texte coloré sans cercle pour rester léger)
	var ic := Label.new()
	ic.text = icon
	ic.add_theme_color_override("font_color", icon_color)
	ic.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_LARGE))
	ic.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ic.custom_minimum_size = Vector2(ThemeManager.scaled_i(32), 0)
	ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(ic)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	row.add_child(col)

	var lbl := Label.new()
	lbl.text = label
	lbl.add_theme_color_override("font_color", ThemeManager.TEXT_DIM)
	lbl.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_SMALL))
	col.add_child(lbl)

	var val := Label.new()
	val.text = value
	val.add_theme_color_override("font_color", ThemeManager.TEXT)
	val.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_MED))
	val.add_theme_font_override("font", ThemeDB.fallback_font)
	col.add_child(val)

# ── Filtre slow % (avec dropdown) ───────────────────────────
func _build_slow_filter(parent: Node) -> void:
	var card := _card()
	parent.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", ThemeManager.scaled_i(12))
	card.add_child(row)

	var lbl := Label.new()
	lbl.text = "Top % réponses les plus lentes"
	lbl.add_theme_color_override("font_color", ThemeManager.TEXT)
	lbl.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_MED))
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lbl)

	# Dropdown pour le pourcentage
	var choices: Array = [5, 10, 15, 20, 25, 30, 40, 50, 75, 100]
	var labels: Array = []
	for c in choices: labels.append("%d %%" % c)
	var idx := choices.find(slow_percent)
	if idx < 0: idx = 3  # 20%

	_slow_dd = OptionButton.new()
	_slow_dd.custom_minimum_size = Vector2(ThemeManager.scaled_i(110),
			ThemeManager.scaled_i(46))
	_slow_dd.clip_text = true
	_slow_dd.add_theme_color_override("font_color", ThemeManager.ACCENT_2)
	_slow_dd.add_theme_font_size_override("font_size",
			ThemeManager.scaled_i(ThemeManager.FONT_MED))
	_slow_dd.add_theme_font_override("font", ThemeDB.fallback_font)
	var rr := ThemeManager.scaled_i(10)
	var dpx := ThemeManager.scaled_i(14)
	var dpx_r := ThemeManager.scaled_i(36)
	_slow_dd.add_theme_stylebox_override("normal",
			ThemeManager.sbox(ThemeManager.SURFACE_2, rr,
					dpx, dpx_r, ThemeManager.scaled_i(6), ThemeManager.scaled_i(6),
					ThemeManager.BORDER_2, 1))
	_slow_dd.add_theme_stylebox_override("hover",
			ThemeManager.sbox(ThemeManager.SURFACE_3, rr,
					dpx, dpx_r, ThemeManager.scaled_i(6), ThemeManager.scaled_i(6),
					ThemeManager.BORDER_2, 1))
	_slow_dd.add_theme_stylebox_override("focus",
			ThemeManager.sbox(Color(0,0,0,0), rr))
	var pop := _slow_dd.get_popup()
	pop.add_theme_color_override("font_color", ThemeManager.TEXT)
	pop.add_theme_font_size_override("font_size",
			ThemeManager.scaled_i(ThemeManager.FONT_MED))
	pop.add_theme_stylebox_override("panel",
			ThemeManager.sbox(ThemeManager.SURFACE_2, rr,
					ThemeManager.scaled_i(8), ThemeManager.scaled_i(8),
					ThemeManager.scaled_i(8), ThemeManager.scaled_i(8),
					ThemeManager.BORDER_2, 1))
	pop.add_theme_stylebox_override("hover",
			ThemeManager.sbox(ThemeManager.ACCENT, rr,
					ThemeManager.scaled_i(8), ThemeManager.scaled_i(8),
					ThemeManager.scaled_i(4), ThemeManager.scaled_i(4)))
	for i in choices.size():
		_slow_dd.add_item(labels[i], i)
	_slow_dd.select(idx)
	_slow_dd.item_selected.connect(func(i: int):
		slow_percent = choices[i]
		_refresh_table())
	row.add_child(_slow_dd)

# ── Table des réponses ──────────────────────────────────────
func _build_answers_table(parent: Node) -> void:
	var card := _card()
	parent.add_child(card)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", ThemeManager.scaled_i(10))
	card.add_child(vb)

	# En-tête de colonnes
	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", ThemeManager.scaled_i(8))
	vb.add_child(hdr)
	_hdr_cell(hdr, "Calcul", 3)
	_hdr_cell(hdr, "Réponse", 1)
	_hdr_cell(hdr, "Donnée", 1)
	_hdr_cell(hdr, "Temps", 1)

	# Séparateur
	var sep := HSeparator.new()
	sep.add_theme_stylebox_override("separator",
			ThemeManager.make_hsep_style(
					Color(ThemeManager.BORDER.r, ThemeManager.BORDER.g,
							ThemeManager.BORDER.b, 0.35)))
	sep.add_theme_constant_override("separation", 0)
	vb.add_child(sep)

	_table_container = VBoxContainer.new()
	_table_container.add_theme_constant_override("separation", ThemeManager.scaled_i(4))
	vb.add_child(_table_container)
	_refresh_table()

func _hdr_cell(parent: Node, text: String, weight: int) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", ThemeManager.ACCENT)
	l.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_SMALL))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_stretch_ratio = float(weight)
	parent.add_child(l)

func _row_cell(parent: Node, text: String, color: Color, weight: int) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_SMALL))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_stretch_ratio = float(weight)
	parent.add_child(l)

func _refresh_table() -> void:
	if _table_container == null: return
	for c in _table_container.get_children():
		c.queue_free()
	var answers = GameState.session.answers

	if answers.is_empty():
		# Message "Aucune donnée à afficher" avec icône
		var empty_vb := VBoxContainer.new()
		empty_vb.add_theme_constant_override("separation", ThemeManager.scaled_i(8))
		_table_container.add_child(empty_vb)
		var sp := Control.new()
		sp.custom_minimum_size = Vector2(0, ThemeManager.scaled_i(20))
		empty_vb.add_child(sp)
		var ic := Label.new()
		ic.text = "📋"
		ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ic.add_theme_font_size_override("font_size",
				ThemeManager.scaled_i(ThemeManager.FONT_TITLE))
		ic.add_theme_color_override("font_color", ThemeManager.TEXT_DIM)
		empty_vb.add_child(ic)
		var l1 := Label.new()
		l1.text = "Aucune donnée à afficher"
		l1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l1.add_theme_color_override("font_color", ThemeManager.TEXT_DIM)
		l1.add_theme_font_size_override("font_size",
				ThemeManager.scaled_i(ThemeManager.FONT_MED))
		empty_vb.add_child(l1)
		var l2 := Label.new()
		l2.text = "Les réponses les plus lentes apparaîtront ici."
		l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l2.add_theme_color_override("font_color", ThemeManager.TEXT_DIM)
		l2.add_theme_font_size_override("font_size",
				ThemeManager.scaled_i(ThemeManager.FONT_TINY))
		empty_vb.add_child(l2)
		return

	# Calcul du seuil "top X% lent"
	var correct_times: Array = []
	for a in answers:
		if a.ok: correct_times.append(a.time_ms)
	correct_times.sort()
	correct_times.reverse()
	var n_slow := int(ceil(float(correct_times.size()) * float(slow_percent) / 100.0))
	var threshold: int = correct_times[n_slow - 1] if n_slow > 0 and correct_times.size() >= n_slow else 999999999

	for a in answers:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", ThemeManager.scaled_i(8))
		_table_container.add_child(row)
		var color := ThemeManager.SUCCESS if a.ok else ThemeManager.ERROR
		var marker := ""
		if a.ok and a.time_ms >= threshold and slow_percent < 100:
			color = ThemeManager.WARNING
			marker = " !"
		_row_cell(row, str(a.expr) + marker,        ThemeManager.TEXT, 3)
		_row_cell(row, str(_fmt_num(a.correct)),    ThemeManager.TEXT_DIM, 1)
		_row_cell(row, str(_fmt_num(a.given)),      color, 1)
		_row_cell(row, "%.2f s" % (a.time_ms / 1000.0), ThemeManager.TEXT_DIM, 1)

func _fmt_num(n) -> String:
	if n == null: return "—"
	if n is float and n == int(n):
		return str(int(n))
	return str(n)

# ── Boutons d'action en bas ─────────────────────────────────
func _build_action_buttons(parent: Node) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", ThemeManager.scaled_i(10))
	parent.add_child(row)

	# Bleu vif "primary"
	var replay_color := Color(0.18, 0.44, 0.98)
	var replay := _action_btn("↻", "Rejouer", replay_color, Color.WHITE,
			func(): SceneRouter.goto("res://scenes/GameScene.tscn"))
	replay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(replay)

	var options := _action_btn("⚙", "Options", ThemeManager.SURFACE_2, ThemeManager.TEXT,
			func(): SceneRouter.goto("res://scenes/OptionsScene.tscn"))
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(options)

	var menu := _action_btn("🏠", "Menu", ThemeManager.SURFACE_2, ThemeManager.TEXT,
			func(): SceneRouter.goto("res://scenes/MainMenu.tscn"))
	menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(menu)

# ── HELPERS ─────────────────────────────────────────────────
func _card() -> PanelContainer:
	var pc := PanelContainer.new()
	var cpad := ThemeManager.scaled_i(ThemeManager.PADDING_CARD)
	pc.add_theme_stylebox_override("panel",
			ThemeManager.sbox(ThemeManager.SURFACE,
					ThemeManager.scaled_i(ThemeManager.RADIUS_CARD),
					cpad, cpad, cpad, cpad,
					ThemeManager.BORDER_2, 2))
	return pc

func _action_btn(icon_text: String, label: String, color: Color,
		text_color: Color, cb: Callable) -> Button:
	var btn := Button.new()
	btn.text = ""
	btn.custom_minimum_size = Vector2(0, ThemeManager.scaled_i(62))
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var rr := ThemeManager.scaled_i(14)
	btn.add_theme_stylebox_override("normal",
			ThemeManager.sbox(color, rr,
					ThemeManager.scaled_i(10), ThemeManager.scaled_i(10),
					ThemeManager.scaled_i(8),  ThemeManager.scaled_i(8),
					color.lightened(0.15), 2))
	btn.add_theme_stylebox_override("hover",
			ThemeManager.sbox(color, rr,
					ThemeManager.scaled_i(10), ThemeManager.scaled_i(10),
					ThemeManager.scaled_i(8),  ThemeManager.scaled_i(8),
					color.lightened(0.15), 2))
	btn.add_theme_stylebox_override("focus",
			ThemeManager.sbox(color, rr,
					ThemeManager.scaled_i(10), ThemeManager.scaled_i(10),
					ThemeManager.scaled_i(8),  ThemeManager.scaled_i(8),
					color.lightened(0.15), 2))
	btn.add_theme_stylebox_override("pressed",
			ThemeManager.sbox(color.darkened(0.15), rr))
	var center := CenterContainer.new()
	center.anchor_right = 1.0; center.anchor_bottom = 1.0
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(center)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", ThemeManager.scaled_i(8))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(row)
	var ic := Label.new()
	ic.text = icon_text
	ic.add_theme_color_override("font_color", text_color)
	ic.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_MED))
	ic.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(ic)
	var lbl := Label.new()
	lbl.text = label
	lbl.add_theme_color_override("font_color", text_color)
	lbl.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_MED))
	lbl.add_theme_font_override("font", ThemeDB.fallback_font)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl)
	btn.pressed.connect(func():
		AudioManager.play_sfx("click"); cb.call())
	return btn

# ── Input ───────────────────────────────────────────────────
func _process(delta: float) -> void:
	if not _is_touching and absf(_scroll_velocity) > 1.0:
		_scroll.scroll_vertical -= int(_scroll_velocity * delta)
		_scroll_velocity = lerpf(_scroll_velocity, 0.0, 2.0 * delta)

func _calc_release_velocity() -> float:
	if _touch_history.size() < 2:
		return 0.0
	var oldest: Dictionary = _touch_history[0]
	var newest: Dictionary = _touch_history[-1]
	var dt_ms: int = newest.t - oldest.t
	if dt_ms < 8:
		return 0.0
	return (newest.y - oldest.y) / (float(dt_ms) * 0.001)

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_is_touching = true
			_scroll_velocity = 0.0
			_touch_history.clear()
			_touch_history.append({"t": Time.get_ticks_msec(), "y": event.position.y})
		else:
			_is_touching = false
			_scroll_velocity = _calc_release_velocity()
			_touch_history.clear()
	elif event is InputEventScreenDrag:
		var now: int = Time.get_ticks_msec()
		_touch_history.append({"t": now, "y": event.position.y})
		while _touch_history.size() > 1 and _touch_history[0].t < now - 80:
			_touch_history.pop_front()
		_scroll.scroll_vertical -= int(event.relative.y)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_BACK:
			get_viewport().set_input_as_handled()
			SceneRouter.goto("res://scenes/MainMenu.tscn")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		AudioManager.play_sfx("back")
		SceneRouter.goto("res://scenes/MainMenu.tscn")
