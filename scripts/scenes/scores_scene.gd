extends Control
# ============================================================
# SCORES — Historique + meilleurs du jour + graphique.
# ============================================================

var current_mode: int = GameState.Mode.CONTRE_LA_MONTRE
var clear_pending_ms: int = 0
var graph_node: Control
var table_container: VBoxContainer
var mode_label: Label
var profile_label: Label
var daily_best_label: Label
var _scroll: ScrollContainer

func _ready() -> void:
	current_mode = GameState.options.mode
	_build_ui()
	_refresh_all()

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = ThemeManager.BG
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	add_child(bg)

	var title := Label.new()
	title.text = "📊  Scores & Historique"
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

	# Sélecteurs
	var sel_panel := PanelContainer.new()
	sel_panel.add_theme_stylebox_override("panel", ThemeManager.make_panel_style(ThemeManager.SURFACE, 10))
	vb.add_child(sel_panel)
	var sel_hb := HBoxContainer.new()
	sel_hb.add_theme_constant_override("separation", 8)
	sel_panel.add_child(sel_hb)

	sel_hb.add_child(_make_btn("◀", ThemeManager.SURFACE_2, func(): _cycle_mode(-1)))
	mode_label = Label.new()
	mode_label.text = GameState.MODE_NAMES[current_mode]
	mode_label.add_theme_color_override("font_color", ThemeManager.ACCENT_2)
	mode_label.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_MED))
	mode_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sel_hb.add_child(mode_label)
	sel_hb.add_child(_make_btn("▶", ThemeManager.SURFACE_2, func(): _cycle_mode(1)))

	# Profil
	var prof_panel := PanelContainer.new()
	prof_panel.add_theme_stylebox_override("panel", ThemeManager.make_panel_style(ThemeManager.SURFACE, 10))
	vb.add_child(prof_panel)
	var prof_hb := HBoxContainer.new()
	prof_hb.add_theme_constant_override("separation", 8)
	prof_panel.add_child(prof_hb)

	prof_hb.add_child(_make_btn("◀", ThemeManager.SURFACE_2, func(): _cycle_profile(-1)))
	profile_label = Label.new()
	profile_label.text = "Profil : %s" % ProfileManager.current_profile
	profile_label.add_theme_color_override("font_color", ThemeManager.TEXT)
	profile_label.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_MED))
	profile_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	profile_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prof_hb.add_child(profile_label)
	prof_hb.add_child(_make_btn("▶", ThemeManager.SURFACE_2, func(): _cycle_profile(1)))

	# Meilleur du jour
	var best_panel := PanelContainer.new()
	best_panel.add_theme_stylebox_override("panel", ThemeManager.make_panel_style(ThemeManager.SURFACE_2, 10))
	vb.add_child(best_panel)
	daily_best_label = Label.new()
	daily_best_label.text = ""
	daily_best_label.add_theme_color_override("font_color", ThemeManager.SUCCESS)
	daily_best_label.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_LARGE))
	daily_best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	best_panel.add_child(daily_best_label)

	# Graphique
	var graph_panel := PanelContainer.new()
	graph_panel.add_theme_stylebox_override("panel", ThemeManager.make_panel_style(ThemeManager.SURFACE, 10))
	vb.add_child(graph_panel)
	var graph_vb := VBoxContainer.new()
	graph_panel.add_child(graph_vb)
	var graph_title := Label.new()
	graph_title.text = "Progression (meilleurs du jour)"
	graph_title.add_theme_color_override("font_color", ThemeManager.ACCENT)
	graph_title.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_SMALL))
	graph_vb.add_child(graph_title)
	graph_node = ScoreGraph.new()
	graph_node.custom_minimum_size = Vector2(0, 220)
	graph_vb.add_child(graph_node)

	# Table d'historique
	var table_panel := PanelContainer.new()
	table_panel.add_theme_stylebox_override("panel", ThemeManager.make_panel_style(ThemeManager.SURFACE, 10))
	vb.add_child(table_panel)
	var table_vb := VBoxContainer.new()
	table_vb.add_theme_constant_override("separation", 4)
	table_panel.add_child(table_vb)

	var hdr_lbl := Label.new()
	hdr_lbl.text = "Historique des sessions"
	hdr_lbl.add_theme_color_override("font_color", ThemeManager.ACCENT)
	hdr_lbl.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_SMALL))
	table_vb.add_child(hdr_lbl)

	# En-têtes de table
	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 8)
	table_vb.add_child(hdr)
	_hdr_cell(hdr, "Date", 3)
	_hdr_cell(hdr, "Niv.", 1)
	_hdr_cell(hdr, "Calc.", 1)
	_hdr_cell(hdr, "Bons", 1)
	_hdr_cell(hdr, "Exact.", 1)
	_hdr_cell(hdr, "Score", 1)

	table_container = VBoxContainer.new()
	table_container.add_theme_constant_override("separation", 2)
	table_vb.add_child(table_container)

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

	var clear_btn := _make_btn("🗑  Effacer", ThemeManager.ERROR, func(): _on_clear())
	clear_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(clear_btn)

	var back := _make_btn("← Retour", ThemeManager.SURFACE_2, func():
		SceneRouter.back("res://scenes/MainMenu.tscn")
	)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(back)

func _hdr_cell(parent: Node, text: String, weight: int) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", ThemeManager.ACCENT)
	l.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_SMALL))
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

func _make_btn(label: String, color: Color, cb: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(0, 56)
	b.add_theme_color_override("font_color", ThemeManager.TEXT)
	b.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_SMALL))
	b.add_theme_stylebox_override("normal", ThemeManager.make_button_style(color, 10))
	b.add_theme_stylebox_override("hover",  ThemeManager.make_button_style(color.lightened(0.1), 10))
	b.add_theme_stylebox_override("pressed",ThemeManager.make_button_style(color.darkened(0.15), 10))
	b.pressed.connect(func():
		AudioManager.play_sfx("click")
		cb.call()
	)
	return b

func _cycle_mode(dir: int) -> void:
	current_mode = (current_mode + dir + 5) % 5
	mode_label.text = GameState.MODE_NAMES[current_mode]
	_refresh_all()

func _cycle_profile(dir: int) -> void:
	var list = ProfileManager.list_profiles()
	if list.is_empty(): return
	var i = list.find(ProfileManager.current_profile)
	i = (i + dir + list.size()) % list.size()
	ProfileManager.switch_to(list[i])
	profile_label.text = "Profil : %s" % ProfileManager.current_profile
	_refresh_all()

func _on_clear() -> void:
	var now := Time.get_ticks_msec()
	if clear_pending_ms == 0 or now - clear_pending_ms > 2000:
		clear_pending_ms = now
		_toast("Êtes-vous sûr ? Recliquez pour confirmer.")
		return
	# Confirmation
	clear_pending_ms = 0
	ScoreManager.clear_scores_for_mode(current_mode)
	_toast("Scores effacés.")
	_refresh_all()

func _refresh_all() -> void:
	# Daily best
	var best := ScoreManager.get_daily_best(current_mode)
	daily_best_label.text = "★ Meilleur du jour : %d" % best
	# Graphique
	graph_node.points = ScoreManager.daily_bests_history(current_mode)
	graph_node.queue_redraw()
	# Table
	for c in table_container.get_children():
		c.queue_free()
	var sessions = ScoreManager.sessions_for_mode(current_mode)
	# Tri date desc
	sessions.sort_custom(func(a, b): return str(a.date) > str(b.date))
	# Limit affichage
	var limit = min(sessions.size(), 100)
	for i in limit:
		var s = sessions[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		table_container.add_child(row)
		_row_cell(row, str(s.get("date", "—")),                                    ThemeManager.TEXT, 3)
		_row_cell(row, str(s.get("level", 0)),                                      ThemeManager.TEXT_DIM, 1)
		_row_cell(row, str(s.get("calculations", s.get("total", "?"))),             ThemeManager.TEXT_DIM, 1)
		_row_cell(row, str(s.get("correct", 0)),                                    ThemeManager.SUCCESS, 1)
		_row_cell(row, "%.0f%%" % (float(s.get("accuracy", 0.0)) * 100.0),          ThemeManager.TEXT_DIM, 1)
		_row_cell(row, str(s.get("score", 0)),                                      ThemeManager.ACCENT_2, 1)

func _toast(msg: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 60
	add_child(layer)
	var pc := PanelContainer.new()
	pc.anchor_left = 0.5
	pc.anchor_right = 0.5
	pc.anchor_bottom = 1.0
	pc.offset_left = -180
	pc.offset_right = 180
	pc.offset_top = -130
	pc.offset_bottom = -70
	pc.add_theme_stylebox_override("panel", ThemeManager.make_panel_style(ThemeManager.WARNING.darkened(0.3), 10))
	layer.add_child(pc)
	var l := Label.new()
	l.text = msg
	l.add_theme_color_override("font_color", ThemeManager.TEXT)
	l.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_SMALL))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pc.add_child(l)
	var tw := create_tween()
	tw.tween_interval(1.8)
	tw.tween_property(pc, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func(): layer.queue_free())

func _input(event: InputEvent) -> void:
	if event is InputEventScreenDrag:
		_scroll.scroll_vertical -= int(event.relative.y)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_BACK:
			get_viewport().set_input_as_handled()
			SceneRouter.back("res://scenes/MainMenu.tscn")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		SceneRouter.back("res://scenes/MainMenu.tscn")

# ============================================================
# Sous-classe : graphique simple
# ============================================================
class ScoreGraph extends Control:
	var points: Array = []  # [{date, score}]

	func _draw() -> void:
		var sz := size
		# Fond
		draw_rect(Rect2(Vector2.ZERO, sz), ThemeManager.SURFACE_2, true)
		if points.size() == 0:
			var f := ThemeDB.fallback_font
			draw_string(f, Vector2(sz.x * 0.5 - 80, sz.y * 0.5), "Aucune donnée",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 18, ThemeManager.TEXT_DIM)
			return
		var max_score := 0
		for p in points:
			if int(p.score) > max_score: max_score = int(p.score)
		if max_score == 0: max_score = 100
		# Lignes horizontales
		for i in range(0, 5):
			var y := sz.y - 10 - (sz.y - 30) * float(i) / 4.0
			draw_line(Vector2(40, y), Vector2(sz.x - 10, y), Color(ThemeManager.BORDER.r, ThemeManager.BORDER.g, ThemeManager.BORDER.b, 0.4), 1)
		# Points et lignes
		var n := points.size()
		var step: float = (sz.x - 50) / float(max(1, n - 1)) if n > 1 else 0.0
		var prev := Vector2.ZERO
		for i in n:
			var p = points[i]
			var x: float = 40.0 + float(i) * step
			var y := sz.y - 10 - (sz.y - 30) * float(int(p.score)) / float(max_score)
			if i > 0:
				draw_line(prev, Vector2(x, y), ThemeManager.ACCENT, 2)
			draw_circle(Vector2(x, y), 5, ThemeManager.ACCENT_2)
			prev = Vector2(x, y)
		# Échelle
		var fnt := ThemeDB.fallback_font
		draw_string(fnt, Vector2(4, 14), str(max_score),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ThemeManager.TEXT_DIM)
		draw_string(fnt, Vector2(4, sz.y - 4), "0",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ThemeManager.TEXT_DIM)
