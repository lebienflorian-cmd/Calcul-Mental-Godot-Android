extends Control
# ============================================================
# SCORES — Historique + meilleurs du jour + graphique.
# Refonte : header fixe, dropdowns, cartes avec icônes, bordures.
# ============================================================

var current_mode: int = GameState.Mode.CONTRE_LA_MONTRE
var clear_pending_ms: int = 0
var graph_node: Control
var table_container: VBoxContainer
var mode_dd: OptionButton
var profile_dd: OptionButton
var daily_best_label: Label
var daily_best_score: Label
var _scroll: ScrollContainer
var _scroll_velocity: float = 0.0
var _is_touching: bool = false
var _touch_history: Array = []

# Fond animé
var _symbols: Array = []
const SYMBOLS_TEXT := ["1","2","3","4","5","6","7","8","9","+","−","×","÷","="]

func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	current_mode = GameState.options.mode
	_build_ui()
	_refresh_all()
	_init_background()
	set_process(true)

# ── Fond animé ──────────────────────────────────────────────
func _init_background() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in 30:
		var sz := get_viewport_rect().size
		_symbols.append({
			"pos": Vector2(rng.randf() * sz.x, rng.randf() * sz.y),
			"vel": Vector2(rng.randf_range(-6, 6), rng.randf_range(-10, -2)),
			"char": SYMBOLS_TEXT[rng.randi() % SYMBOLS_TEXT.size()],
			"alpha": rng.randf_range(0.05, 0.13),
			"size": rng.randf_range(16, 36),
		})

func _process(delta: float) -> void:
	var sz := get_viewport_rect().size
	for s in _symbols:
		s.pos += s.vel * delta
		if s.pos.y < -50:       s.pos.y = sz.y + 50
		if s.pos.y > sz.y + 50: s.pos.y = -50
		if s.pos.x < -50:       s.pos.x = sz.x + 50
		if s.pos.x > sz.x + 50: s.pos.x = -50
	if not _is_touching and absf(_scroll_velocity) > 1.0:
		_scroll.scroll_vertical -= int(_scroll_velocity * delta)
		_scroll_velocity = lerpf(_scroll_velocity, 0.0, 2.0 * delta)
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

# ── Layout ──────────────────────────────────────────────────
func _build_ui() -> void:
	var hdr_h := ThemeManager.scaled_i(ThemeManager.HEADER_HEIGHT)
	var pad := ThemeManager.scaled_i(14)

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

	# Titre centré
	var title := Label.new()
	title.text = "Scores"
	title.anchor_left = 0.0; title.anchor_right = 1.0
	title.anchor_top = 0.0;  title.anchor_bottom = 1.0
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", ThemeManager.TEXT)
	title.add_theme_font_size_override("font_size",
			ThemeManager.scaled_i(ThemeManager.FONT_TITLE))
	title.add_theme_font_override("font", ThemeDB.fallback_font)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(title)

	# === ZONE SCROLLABLE ===
	_scroll = ScrollContainer.new()
	_scroll.anchor_left = 0.0; _scroll.anchor_right = 1.0
	_scroll.anchor_top  = 0.0; _scroll.anchor_bottom = 1.0
	_scroll.offset_top = hdr_h; _scroll.offset_left = pad
	_scroll.offset_right = -pad; _scroll.offset_bottom = 0
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation",
			ThemeManager.scaled_i(ThemeManager.SECTION_GAP))
	_scroll.add_child(vb)

	# ── Dropdown mode de jeu ────────────────────────────────
	_build_mode_selector(vb)

	# ── Dropdown profil ─────────────────────────────────────
	_build_profile_selector(vb)

	# ── Meilleur du jour ────────────────────────────────────
	_build_daily_best(vb)

	# ── Progression (graphique) ─────────────────────────────
	_build_graph(vb)

	# ── Historique des sessions ─────────────────────────────
	_build_history(vb)

	# ── Boutons bas (Effacer + Retour) ──────────────────────
	_build_bottom_buttons(vb)

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, ThemeManager.scaled_i(20))
	vb.add_child(spacer)

# ── Sélecteur de mode ───────────────────────────────────────
func _build_mode_selector(parent: Node) -> void:
	var card := _card()
	parent.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", ThemeManager.scaled_i(14))
	card.add_child(row)

	# Icône chrono
	var icon := _icon_circle("⏱", ThemeManager.ACCENT)
	row.add_child(icon)

	# Texte + dropdown
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	row.add_child(col)

	var lbl := Label.new()
	lbl.text = "Mode de jeu"
	lbl.add_theme_color_override("font_color", ThemeManager.TEXT_DIM)
	lbl.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_SMALL))
	col.add_child(lbl)

	var mode_names: Array = Array(GameState.MODE_NAMES.values())
	mode_dd = _make_dropdown(mode_names, current_mode)
	mode_dd.item_selected.connect(func(idx: int):
		current_mode = idx
		_refresh_all())
	col.add_child(mode_dd)

# ── Sélecteur de profil ─────────────────────────────────────
func _build_profile_selector(parent: Node) -> void:
	var card := _card()
	parent.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", ThemeManager.scaled_i(14))
	card.add_child(row)

	var icon := _icon_circle("👤", ThemeManager.ACCENT)
	row.add_child(icon)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	row.add_child(col)

	var lbl := Label.new()
	lbl.text = "Profil"
	lbl.add_theme_color_override("font_color", ThemeManager.TEXT_DIM)
	lbl.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_SMALL))
	col.add_child(lbl)

	var profiles: Array = ProfileManager.list_profiles()
	var cur_idx := 0
	for i in profiles.size():
		if profiles[i] == ProfileManager.current_profile:
			cur_idx = i; break
	profile_dd = _make_dropdown(profiles, cur_idx)
	profile_dd.item_selected.connect(func(idx: int):
		var plist: Array = ProfileManager.list_profiles()
		if idx >= 0 and idx < plist.size():
			ProfileManager.switch_to(plist[idx])
			_refresh_all())
	col.add_child(profile_dd)

# ── Meilleur du jour ────────────────────────────────────────
func _build_daily_best(parent: Node) -> void:
	var card := PanelContainer.new()
	var cpad := ThemeManager.scaled_i(ThemeManager.PADDING_CARD)
	card.add_theme_stylebox_override("panel",
			ThemeManager.sbox(Color(0.05, 0.18, 0.08),
					ThemeManager.scaled_i(ThemeManager.RADIUS_CARD),
					cpad, cpad, cpad, cpad,
					ThemeManager.SUCCESS, 2))
	parent.add_child(card)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", ThemeManager.scaled_i(14))
	card.add_child(row)

	# Étoile dans un cercle vert
	var star_sz := ThemeManager.scaled_i(54)
	var star_panel := PanelContainer.new()
	star_panel.custom_minimum_size = Vector2(star_sz, star_sz)
	star_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	star_panel.add_theme_stylebox_override("panel",
			ThemeManager.sbox(ThemeManager.SUCCESS.darkened(0.2),
					ThemeManager.scaled_i(27), 0, 0, 0, 0,
					ThemeManager.SUCCESS.lightened(0.1), 2))
	row.add_child(star_panel)

	var star := Label.new()
	star.text = "★"
	star.add_theme_color_override("font_color", Color.WHITE)
	star.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_LARGE))
	star.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	star.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	star.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	star.size_flags_vertical = Control.SIZE_EXPAND_FILL
	star_panel.add_child(star)

	# Texte
	var txt_vb := VBoxContainer.new()
	txt_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	txt_vb.add_theme_constant_override("separation", 2)
	row.add_child(txt_vb)

	daily_best_label = Label.new()
	daily_best_label.text = "MEILLEUR DU JOUR"
	daily_best_label.add_theme_color_override("font_color", ThemeManager.SUCCESS)
	daily_best_label.add_theme_font_size_override("font_size",
			ThemeManager.scaled_i(ThemeManager.FONT_SMALL))
	txt_vb.add_child(daily_best_label)

	daily_best_score = Label.new()
	daily_best_score.text = "Meilleur du jour : 0"
	daily_best_score.add_theme_color_override("font_color", ThemeManager.TEXT)
	daily_best_score.add_theme_font_size_override("font_size",
			ThemeManager.scaled_i(ThemeManager.FONT_MED))
	daily_best_score.add_theme_font_override("font", ThemeDB.fallback_font)
	txt_vb.add_child(daily_best_score)

# ── Graphique ───────────────────────────────────────────────
func _build_graph(parent: Node) -> void:
	var card := _card()
	parent.add_child(card)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", ThemeManager.scaled_i(12))
	card.add_child(vb)

	# Header avec icône
	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", ThemeManager.scaled_i(10))
	vb.add_child(hdr)

	var icon := _icon_circle("📈", ThemeManager.ACCENT)
	hdr.add_child(icon)

	var lbl := Label.new()
	lbl.text = "Progression"
	lbl.add_theme_color_override("font_color", ThemeManager.TEXT)
	lbl.add_theme_font_size_override("font_size",
			ThemeManager.scaled_i(ThemeManager.FONT_MED))
	lbl.add_theme_font_override("font", ThemeDB.fallback_font)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hdr.add_child(lbl)

	graph_node = ScoreGraph.new()
	graph_node.custom_minimum_size = Vector2(0, ThemeManager.scaled_i(180))
	vb.add_child(graph_node)

# ── Historique ──────────────────────────────────────────────
func _build_history(parent: Node) -> void:
	var card := _card()
	parent.add_child(card)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", ThemeManager.scaled_i(10))
	card.add_child(vb)

	# Header avec icône
	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", ThemeManager.scaled_i(10))
	vb.add_child(hdr)

	var icon := _icon_circle("🕐", ThemeManager.ACCENT)
	hdr.add_child(icon)

	var lbl := Label.new()
	lbl.text = "Historique des sessions"
	lbl.add_theme_color_override("font_color", ThemeManager.TEXT)
	lbl.add_theme_font_size_override("font_size",
			ThemeManager.scaled_i(ThemeManager.FONT_MED))
	lbl.add_theme_font_override("font", ThemeDB.fallback_font)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hdr.add_child(lbl)

	# Séparateur
	var sep := HSeparator.new()
	sep.add_theme_stylebox_override("separator",
			ThemeManager.make_hsep_style(
					Color(ThemeManager.BORDER.r, ThemeManager.BORDER.g,
							ThemeManager.BORDER.b, 0.35)))
	sep.add_theme_constant_override("separation", 0)
	vb.add_child(sep)

	# En-têtes de colonnes
	var col_hdr := HBoxContainer.new()
	col_hdr.add_theme_constant_override("separation", 4)
	vb.add_child(col_hdr)
	_hdr_cell(col_hdr, "Date", 3)
	_hdr_cell(col_hdr, "Niv.", 1)
	_hdr_cell(col_hdr, "Calc.", 1)
	_hdr_cell(col_hdr, "Bons", 1)
	_hdr_cell(col_hdr, "Exact.", 1)
	_hdr_cell(col_hdr, "Score", 1)

	table_container = VBoxContainer.new()
	table_container.add_theme_constant_override("separation", 2)
	vb.add_child(table_container)

# ── Boutons bas ─────────────────────────────────────────────
func _build_bottom_buttons(parent: Node) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", ThemeManager.scaled_i(12))
	parent.add_child(row)

	var clear_btn := _action_btn("🗑", "Effacer", ThemeManager.ERROR, func(): _on_clear())
	clear_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(clear_btn)

	var back_btn := _action_btn("←", "Retour", ThemeManager.SURFACE_2, func():
		SceneRouter.goto("res://scenes/MainMenu.tscn"))
	back_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(back_btn)

# ════════════════════════════════════════════════════════════
# HELPERS
# ════════════════════════════════════════════════════════════

func _card() -> PanelContainer:
	var pc := PanelContainer.new()
	var cpad := ThemeManager.scaled_i(ThemeManager.PADDING_CARD)
	pc.add_theme_stylebox_override("panel",
			ThemeManager.sbox(ThemeManager.SURFACE,
					ThemeManager.scaled_i(ThemeManager.RADIUS_CARD),
					cpad, cpad, cpad, cpad,
					ThemeManager.BORDER_2, 2))
	return pc

func _icon_circle(emoji: String, color: Color) -> PanelContainer:
	var sz := ThemeManager.scaled_i(44)
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(sz, sz)
	pc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bg := Color(color.r, color.g, color.b, 0.15)
	pc.add_theme_stylebox_override("panel",
			ThemeManager.sbox(bg, ThemeManager.scaled_i(22), 0, 0, 0, 0,
					color, 2))
	var lbl := Label.new()
	lbl.text = emoji
	lbl.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_MED))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pc.add_child(lbl)
	return pc

func _make_dropdown(choices: Array, initial_idx: int) -> OptionButton:
	var ob := OptionButton.new()
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ob.clip_text = true
	ob.add_theme_color_override("font_color", ThemeManager.TEXT)
	ob.add_theme_font_size_override("font_size",
			ThemeManager.scaled_i(ThemeManager.FONT_MED))
	var rr := ThemeManager.scaled_i(10)
	ob.add_theme_stylebox_override("normal",
			ThemeManager.sbox(Color(0,0,0,0), rr))
	ob.add_theme_stylebox_override("hover",
			ThemeManager.sbox(Color(1,1,1,0.05), rr))
	ob.add_theme_stylebox_override("focus",
			ThemeManager.sbox(Color(0,0,0,0), rr))
	# Popup style
	var pop := ob.get_popup()
	pop.add_theme_color_override("font_color", ThemeManager.TEXT)
	pop.add_theme_font_size_override("font_size",
			ThemeManager.scaled_i(ThemeManager.FONT_MED))
	pop.add_theme_stylebox_override("panel",
			ThemeManager.sbox(ThemeManager.SURFACE_2, rr,
					ThemeManager.scaled_i(8), ThemeManager.scaled_i(8),
					ThemeManager.scaled_i(8), ThemeManager.scaled_i(8),
					ThemeManager.BORDER_2, 1))
	pop.add_theme_stylebox_override("hover",
			ThemeManager.sbox(ThemeManager.ACCENT, ThemeManager.scaled_i(6),
					ThemeManager.scaled_i(8), ThemeManager.scaled_i(8),
					ThemeManager.scaled_i(4), ThemeManager.scaled_i(4)))
	for i in choices.size():
		ob.add_item(str(choices[i]), i)
	if initial_idx >= 0 and initial_idx < choices.size():
		ob.select(initial_idx)
	return ob

func _action_btn(icon_text: String, label: String, color: Color,
		cb: Callable) -> Button:
	var btn := Button.new()
	btn.text = ""
	btn.custom_minimum_size = Vector2(0, ThemeManager.scaled_i(60))
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var rr := ThemeManager.scaled_i(14)
	btn.add_theme_stylebox_override("normal",
			ThemeManager.sbox(color, rr,
					ThemeManager.scaled_i(14), ThemeManager.scaled_i(14),
					ThemeManager.scaled_i(8),  ThemeManager.scaled_i(8),
					color.lightened(0.15), 2))
	btn.add_theme_stylebox_override("hover",
			ThemeManager.sbox(color.lightened(0.08), rr,
					ThemeManager.scaled_i(14), ThemeManager.scaled_i(14),
					ThemeManager.scaled_i(8),  ThemeManager.scaled_i(8),
					color.lightened(0.25), 2))
	btn.add_theme_stylebox_override("pressed",
			ThemeManager.sbox(color.darkened(0.15), rr))
	# Contenu centré
	var center := CenterContainer.new()
	center.anchor_right = 1.0; center.anchor_bottom = 1.0
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(center)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", ThemeManager.scaled_i(10))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(row)
	var ic := Label.new()
	ic.text = icon_text
	ic.add_theme_color_override("font_color", Color.WHITE)
	ic.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_MED))
	ic.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(ic)
	var lbl := Label.new()
	lbl.text = label
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_MED))
	lbl.add_theme_font_override("font", ThemeDB.fallback_font)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl)
	btn.pressed.connect(func():
		AudioManager.play_sfx("click"); cb.call())
	return btn

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

# ════════════════════════════════════════════════════════════
# LOGIQUE
# ════════════════════════════════════════════════════════════

func _on_clear() -> void:
	var now := Time.get_ticks_msec()
	if clear_pending_ms == 0 or now - clear_pending_ms > 2000:
		clear_pending_ms = now
		_toast("Êtes-vous sûr ? Recliquez pour confirmer.")
		return
	clear_pending_ms = 0
	ScoreManager.clear_scores_for_mode(current_mode)
	_toast("Scores effacés.")
	_refresh_all()

func _refresh_all() -> void:
	var best := ScoreManager.get_daily_best(current_mode)
	daily_best_score.text = "Meilleur du jour : %d" % best
	graph_node.points = ScoreManager.daily_bests_history(current_mode)
	graph_node.queue_redraw()
	for c in table_container.get_children():
		c.queue_free()
	var sessions = ScoreManager.sessions_for_mode(current_mode)
	sessions.sort_custom(func(a, b): return str(a.date) > str(b.date))
	var limit = min(sessions.size(), 100)
	if limit == 0:
		# Message "aucune session"
		var empty_vb := VBoxContainer.new()
		empty_vb.add_theme_constant_override("separation", ThemeManager.scaled_i(8))
		table_container.add_child(empty_vb)
		var sp := Control.new()
		sp.custom_minimum_size = Vector2(0, ThemeManager.scaled_i(20))
		empty_vb.add_child(sp)
		var ic := Label.new()
		ic.text = "📋"
		ic.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ic.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_TITLE))
		ic.add_theme_color_override("font_color", ThemeManager.TEXT_DIM)
		empty_vb.add_child(ic)
		var l1 := Label.new()
		l1.text = "Aucune session enregistrée"
		l1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l1.add_theme_color_override("font_color", ThemeManager.TEXT_DIM)
		l1.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_SMALL))
		empty_vb.add_child(l1)
		var l2 := Label.new()
		l2.text = "Vos sessions apparaîtront ici."
		l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l2.add_theme_color_override("font_color", ThemeManager.TEXT_DIM)
		l2.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_TINY))
		empty_vb.add_child(l2)
		return
	for i in limit:
		var s = sessions[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		table_container.add_child(row)
		_row_cell(row, str(s.get("date", "—")),                                    ThemeManager.TEXT, 3)
		_row_cell(row, str(s.get("level", 0)),                                      ThemeManager.TEXT_DIM, 1)
		_row_cell(row, str(s.get("calculations", s.get("total", "?"))),             ThemeManager.TEXT_DIM, 1)
		_row_cell(row, str(s.get("correct", 0)),                                    ThemeManager.SUCCESS, 1)
		_row_cell(row, "%.0f%%" % (float(s.get("accuracy", 0.0)) * 100.0),          ThemeManager.TEXT_DIM, 1)
		_row_cell(row, str(s.get("score", 0)),                                      ThemeManager.ACCENT_2, 1)

func _toast(msg: String) -> void:
	var layer := CanvasLayer.new(); layer.layer = 60; add_child(layer)
	var pc := PanelContainer.new()
	pc.anchor_left = 0.5; pc.anchor_right = 0.5; pc.anchor_bottom = 1.0
	var w := ThemeManager.scaled_i(320)
	pc.offset_left = -w / 2; pc.offset_right = w / 2
	pc.offset_top = -ThemeManager.scaled_i(130)
	pc.offset_bottom = -ThemeManager.scaled_i(70)
	pc.add_theme_stylebox_override("panel",
			ThemeManager.make_panel_style(ThemeManager.WARNING.darkened(0.3),
					ThemeManager.scaled_i(12)))
	layer.add_child(pc)
	var l := Label.new(); l.text = msg
	l.add_theme_color_override("font_color", ThemeManager.TEXT)
	l.add_theme_font_size_override("font_size",
			ThemeManager.scaled_i(ThemeManager.FONT_SMALL))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pc.add_child(l)
	var tw := create_tween()
	tw.tween_interval(1.8); tw.tween_property(pc, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func(): layer.queue_free())

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
		SceneRouter.goto("res://scenes/MainMenu.tscn")

# ════════════════════════════════════════════════════════════
# Graphique
# ════════════════════════════════════════════════════════════
class ScoreGraph extends Control:
	var points: Array = []

	func _draw() -> void:
		var sz := size
		draw_rect(Rect2(Vector2.ZERO, sz), ThemeManager.SURFACE_2, true)
		# Grille verticale subtile
		var gc := Color(ThemeManager.BORDER.r, ThemeManager.BORDER.g,
				ThemeManager.BORDER.b, 0.25)
		for i in range(1, 6):
			var x: float = sz.x * float(i) / 6.0
			draw_line(Vector2(x, 0), Vector2(x, sz.y), gc, 1)

		if points.size() == 0:
			# Icône + texte "Aucune donnée"
			var f := ThemeDB.fallback_font
			draw_string(f, Vector2(sz.x * 0.5 - 60, sz.y * 0.45), "📈",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 32, ThemeManager.TEXT_DIM)
			draw_string(f, Vector2(sz.x * 0.5 - 100, sz.y * 0.62),
				"Aucune donnée pour le moment",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, ThemeManager.TEXT_DIM)
			# Courbe décorative (vide)
			var deco := PackedVector2Array()
			for i in 20:
				var t: float = float(i) / 19.0
				deco.append(Vector2(
					sz.x * 0.05 + t * sz.x * 0.90,
					sz.y * 0.75 - sin(t * PI) * sz.y * 0.15))
			for i in deco.size() - 1:
				draw_line(deco[i], deco[i + 1],
						Color(ThemeManager.ACCENT.r, ThemeManager.ACCENT.g,
								ThemeManager.ACCENT.b, 0.15), 2, true)
			return

		var max_score := 0
		for p in points:
			if int(p.score) > max_score: max_score = int(p.score)
		if max_score == 0: max_score = 100

		# Lignes horizontales
		for i in range(0, 5):
			var y := sz.y - 10 - (sz.y - 30) * float(i) / 4.0
			draw_line(Vector2(40, y), Vector2(sz.x - 10, y), gc, 1)

		# Courbe + aire sous la courbe
		var n := points.size()
		var step: float = (sz.x - 50) / float(max(1, n - 1)) if n > 1 else 0.0
		var curve_pts := PackedVector2Array()
		for i in n:
			var p = points[i]
			var x: float = 40.0 + float(i) * step
			var y := sz.y - 10 - (sz.y - 30) * float(int(p.score)) / float(max_score)
			curve_pts.append(Vector2(x, y))

		# Aire sous la courbe (semi-transparent)
		if curve_pts.size() >= 2:
			var fill := PackedVector2Array()
			fill.append(Vector2(curve_pts[0].x, sz.y - 10))
			for pt in curve_pts:
				fill.append(pt)
			fill.append(Vector2(curve_pts[curve_pts.size() - 1].x, sz.y - 10))
			draw_colored_polygon(fill,
					Color(ThemeManager.ACCENT.r, ThemeManager.ACCENT.g,
							ThemeManager.ACCENT.b, 0.12))

		# Lignes
		for i in curve_pts.size() - 1:
			draw_line(curve_pts[i], curve_pts[i + 1], ThemeManager.ACCENT, 2, true)

		# Points
		for pt in curve_pts:
			draw_circle(pt, 5, ThemeManager.ACCENT_2)

		# Échelle
		var fnt := ThemeDB.fallback_font
		draw_string(fnt, Vector2(4, 14), str(max_score),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ThemeManager.TEXT_DIM)
		draw_string(fnt, Vector2(4, sz.y - 4), "0",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ThemeManager.TEXT_DIM)
