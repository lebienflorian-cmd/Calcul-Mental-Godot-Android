extends Control
# ============================================================
# END SCENE — Résultats d'une session : score, détails, table des réponses.
# ============================================================

var stats: Dictionary = {}
var saved_today: int = 0
var was_new_best: bool = false
var slow_percent: int = 20
var _scroll: ScrollContainer

func _ready() -> void:
	stats = GameState.compute_final_stats()
	saved_today = ScoreManager.get_daily_best(stats.mode)
	# Sauvegarder la session
	ScoreManager.add_session(stats)
	# Mettre à jour le meilleur du jour
	was_new_best = ScoreManager.set_daily_best_if_better(stats.mode, stats.score)
	if was_new_best:
		AudioManager.play_sfx("save")
	_build_ui()

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = ThemeManager.BG
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	add_child(bg)

	var title := Label.new()
	title.text = "🏁  Résultats"
	title.add_theme_color_override("font_color", ThemeManager.TEXT)
	title.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_TITLE))
	title.anchor_left = 0.0
	title.anchor_right = 1.0
	title.offset_left = 16
	title.offset_right = -16
	title.offset_top = 16
	title.offset_bottom = 80
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	# Scroll principal
	_scroll = ScrollContainer.new()
	_scroll.anchor_right = 1.0
	_scroll.anchor_bottom = 1.0
	_scroll.offset_top = 90
	_scroll.offset_bottom = -90
	_scroll.offset_left = 20
	_scroll.offset_right = -20
	add_child(_scroll)

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 14)
	_scroll.add_child(vb)

	_build_summary_panel(vb)
	_build_slow_filter(vb)
	_build_answers_table(vb)

	# Boutons bas
	var bottom := HBoxContainer.new()
	bottom.anchor_left = 0.0
	bottom.anchor_right = 1.0
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.offset_left = 20
	bottom.offset_right = -20
	bottom.offset_top = -76
	bottom.offset_bottom = -16
	bottom.add_theme_constant_override("separation", 12)
	add_child(bottom)

	var replay := _make_btn("↻  Rejouer", ThemeManager.ACCENT, func():
		SceneRouter.goto("res://scenes/GameScene.tscn")
	)
	replay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(replay)

	var options := _make_btn("⚙  Options", ThemeManager.SURFACE_2, func():
		SceneRouter.goto("res://scenes/OptionsScene.tscn")
	)
	options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(options)

	var menu := _make_btn("🏠  Menu", ThemeManager.SURFACE_2, func():
		SceneRouter.goto("res://scenes/MainMenu.tscn")
	)
	menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(menu)

# ---- Panneau résumé ----
func _build_summary_panel(parent: Node) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", ThemeManager.make_panel_style(ThemeManager.SURFACE, 14))
	parent.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)

	# Gros score
	var score_lbl := Label.new()
	score_lbl.text = "Score : %d" % stats.score
	score_lbl.add_theme_color_override("font_color", ThemeManager.ACCENT_2)
	score_lbl.add_theme_font_size_override("font_size", ThemeManager.scaled_i(72))
	score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(score_lbl)

	if was_new_best:
		var nb := Label.new()
		nb.text = "★  Nouveau meilleur du jour !"
		nb.add_theme_color_override("font_color", ThemeManager.SUCCESS)
		nb.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_MED))
		nb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(nb)

	# Grille de stats
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 8)
	vb.add_child(grid)

	_add_stat(grid, "Mode",         GameState.MODE_NAMES[stats.mode])
	_add_stat(grid, "Exactitude",   "%.0f %%" % (stats.accuracy * 100.0))
	_add_stat(grid, "Bonnes",       "%d / %d" % [stats.correct, stats.total])
	_add_stat(grid, "Durée",        "%.1f s" % stats.elapsed)
	_add_stat(grid, "Temps moyen",  "%.2f s" % stats.avg_time)
	_add_stat(grid, "Niveau",       str(stats.level))
	_add_stat(grid, "Meilleur jour",str(max(saved_today, stats.score)))

func _add_stat(parent: Node, label: String, value: String) -> void:
	var l := Label.new()
	l.text = label
	l.add_theme_color_override("font_color", ThemeManager.TEXT_DIM)
	l.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_SMALL))
	parent.add_child(l)
	var v := Label.new()
	v.text = value
	v.add_theme_color_override("font_color", ThemeManager.TEXT)
	v.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_MED))
	parent.add_child(v)

# ---- Filtre lent ----
func _build_slow_filter(parent: Node) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", ThemeManager.make_panel_style(ThemeManager.SURFACE, 10))
	parent.add_child(panel)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	panel.add_child(hb)
	var l := Label.new()
	l.text = "Top % réponses les plus lentes :"
	l.add_theme_color_override("font_color", ThemeManager.TEXT)
	l.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_SMALL))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(l)
	hb.add_child(_make_btn("▼", ThemeManager.SURFACE_2, func():
		slow_percent = max(5, slow_percent - 5)
		_refresh_table()
	))
	var v := Label.new()
	v.name = "ValueLabel"
	v.text = "%d %%" % slow_percent
	v.add_theme_color_override("font_color", ThemeManager.ACCENT_2)
	v.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_MED))
	v.custom_minimum_size = Vector2(70, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hb.add_child(v)
	hb.add_child(_make_btn("▲", ThemeManager.SURFACE_2, func():
		slow_percent = min(100, slow_percent + 5)
		_refresh_table()
	))

# ---- Table des réponses ----
var _table_container: VBoxContainer = null

func _build_answers_table(parent: Node) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", ThemeManager.make_panel_style(ThemeManager.SURFACE, 10))
	parent.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)

	# Header
	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 8)
	vb.add_child(hdr)
	_hdr_cell(hdr, "Calcul", 3)
	_hdr_cell(hdr, "Réponse", 1)
	_hdr_cell(hdr, "Donnée", 1)
	_hdr_cell(hdr, "Temps", 1)

	_table_container = VBoxContainer.new()
	_table_container.add_theme_constant_override("separation", 2)
	vb.add_child(_table_container)
	_refresh_table()

func _hdr_cell(parent: Node, text: String, weight: int) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", ThemeManager.ACCENT)
	l.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_SMALL))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_stretch_ratio = float(weight)
	parent.add_child(l)

func _refresh_table() -> void:
	# Met à jour le label pourcent dans le filtre
	var lbls := find_children("ValueLabel", "Label", true, false)
	for l in lbls:
		l.text = "%d %%" % slow_percent
	if _table_container == null: return
	for c in _table_container.get_children():
		c.queue_free()

	var answers = GameState.session.answers
	# Calcul du seuil "top X% lent"
	var correct_times: Array = []
	for a in answers:
		if a.ok: correct_times.append(a.time_ms)
	correct_times.sort()
	correct_times.reverse()  # plus lent en premier
	var n_slow := int(ceil(float(correct_times.size()) * float(slow_percent) / 100.0))
	var threshold: int = correct_times[n_slow - 1] if n_slow > 0 and correct_times.size() >= n_slow else 999999999

	for a in answers:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
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

func _row_cell(parent: Node, text: String, color: Color, weight: int) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_SMALL))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_stretch_ratio = float(weight)
	parent.add_child(l)

func _fmt_num(n) -> String:
	if n == null: return "—"
	if n is float and n == int(n):
		return str(int(n))
	return str(n)

func _make_btn(label: String, color: Color, cb: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(0, 56)
	b.add_theme_color_override("font_color", ThemeManager.TEXT)
	b.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_MED))
	b.add_theme_stylebox_override("normal", ThemeManager.make_button_style(color, 10))
	b.add_theme_stylebox_override("hover",  ThemeManager.make_button_style(color.lightened(0.1), 10))
	b.add_theme_stylebox_override("pressed",ThemeManager.make_button_style(color.darkened(0.15), 10))
	b.pressed.connect(func():
		AudioManager.play_sfx("click")
		cb.call()
	)
	return b

func _input(event: InputEvent) -> void:
	if event is InputEventScreenDrag:
		_scroll.scroll_vertical -= int(event.relative.y)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_BACK:
			get_viewport().set_input_as_handled()
			SceneRouter.goto("res://scenes/MainMenu.tscn")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		SceneRouter.goto("res://scenes/MainMenu.tscn")
