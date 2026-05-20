extends Control
# ============================================================
# OPTIONS — Refonte complète :
# • Header non rogné, dimensions généreuses, layout aéré.
# • Cartes/sections plus grandes, icônes vectorielles propres.
# • Toggle « switch » pour la section Contraintes & confort.
# • Checkboxes grosses (≈2× la taille du texte), labels cliquables.
# • Dropdown réel qui déroule un PopupMenu.
# • Spinbox propre +/− avec valeur orange.
# ============================================================

const SYMBOLS_TEXT := ["1","2","3","4","5","6","7","8","9","+","−","×","÷","="]

var scroll: ScrollContainer
var content_vb: VBoxContainer
var _save_btn: Button = null
var _lockable_bodies: Array = []
var _mode_dd: OptionButton = null
var _pre_audio_audio_enabled: bool = false
var _pre_audio_voice_input: bool = false

# Scroll inertie + détection tap/drag ──────────────────────
var _scroll_velocity: float = 0.0
var _is_touching: bool = false
var _touch_drag_dist: float = 0.0
var _touch_history: Array = []  # [{t:int, y:float}] derniers 80 ms

# Fond animé : symboles flottants ───────────────────────────
var _symbols: Array = []

func _ready() -> void:
	anchor_right  = 1.0
	anchor_bottom = 1.0
	_build_ui()
	_init_background()
	set_process(true)

# ── Fond animé ──────────────────────────────────────────────
func _init_background() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in 36:
		var sz := get_viewport_rect().size
		_symbols.append({
			"pos":  Vector2(rng.randf() * sz.x, rng.randf() * sz.y),
			"vel":  Vector2(rng.randf_range(-8, 8), rng.randf_range(-12, -3)),
			"char": SYMBOLS_TEXT[rng.randi() % SYMBOLS_TEXT.size()],
			"alpha": rng.randf_range(0.05, 0.14),
			"size": rng.randf_range(18, 40),
		})

func _process(delta: float) -> void:
	var sz := get_viewport_rect().size
	for s in _symbols:
		s.pos += s.vel * delta
		if s.pos.y < -50:       s.pos.y = sz.y + 50
		if s.pos.y > sz.y + 50: s.pos.y = -50
		if s.pos.x < -50:       s.pos.x = sz.x + 50
		if s.pos.x > sz.x + 50: s.pos.x = -50
	queue_redraw()
	if not _is_touching and absf(_scroll_velocity) > 1.0:
		scroll.scroll_vertical -= int(_scroll_velocity * delta)
		_scroll_velocity = lerpf(_scroll_velocity, 0.0, 2.0 * delta)

func _draw() -> void:
	var sz := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, sz), ThemeManager.BG)
	# Grille discrète
	var gc := Color(ThemeManager.BORDER.r, ThemeManager.BORDER.g, ThemeManager.BORDER.b, 0.10)
	var step := 80
	for x in range(0, int(sz.x), step):
		draw_line(Vector2(x, 0), Vector2(x, sz.y), gc, 1)
	for y in range(0, int(sz.y), step):
		draw_line(Vector2(0, y), Vector2(sz.x, y), gc, 1)
	# Symboles flottants
	var f := ThemeDB.fallback_font
	for s in _symbols:
		var c := ThemeManager.TEXT; c.a = s.alpha
		draw_string(f, s.pos, s.char, HORIZONTAL_ALIGNMENT_LEFT, -1, int(s.size), c)

# ── Layout principal ────────────────────────────────────────
func _build_ui() -> void:
	var hdr_h := ThemeManager.scaled_i(ThemeManager.HEADER_HEIGHT)
	var pad   := ThemeManager.scaled_i(14)

	# === EN-TÊTE (HBoxContainer avec marge) ===
	var header_mc := MarginContainer.new()
	header_mc.anchor_left = 0.0; header_mc.anchor_right = 1.0
	header_mc.anchor_top  = 0.0; header_mc.anchor_bottom = 0.0
	header_mc.offset_bottom = hdr_h
	header_mc.add_theme_constant_override("margin_left",   pad)
	header_mc.add_theme_constant_override("margin_right",  pad)
	header_mc.add_theme_constant_override("margin_top",    0)
	header_mc.add_theme_constant_override("margin_bottom", 0)
	add_child(header_mc)

	var header_hb := HBoxContainer.new()
	header_hb.add_theme_constant_override("separation", ThemeManager.scaled_i(8))
	header_mc.add_child(header_hb)

	# Bouton retour (gauche, taille fixe)
	var back := _make_back_btn()
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(func():
		AudioManager.play_sfx("back")
		SceneRouter.goto("res://scenes/MainMenu.tscn"))
	header_hb.add_child(back)

	# Titre centré (occupe toute la place restante)
	var title := Label.new()
	title.text = "Options"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", ThemeManager.TEXT)
	title.add_theme_font_size_override("font_size",
			ThemeManager.scaled_i(ThemeManager.FONT_TITLE))
	title.add_theme_font_override("font", ThemeDB.fallback_font)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header_hb.add_child(title)

	# Bouton enregistrer (orange, droite) — visible uniquement si profil non verrouillé
	_save_btn = Button.new()
	_save_btn.text = "💾  Enregistrer"
	_save_btn.custom_minimum_size = Vector2(ThemeManager.scaled_i(170), ThemeManager.scaled_i(46))
	_save_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sv_r  := ThemeManager.scaled_i(10)
	var sv_col := Color(0.95, 0.50, 0.05)
	_save_btn.add_theme_color_override("font_color", Color.WHITE)
	_save_btn.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_MED))
	_save_btn.add_theme_stylebox_override("normal",  ThemeManager.sbox(sv_col, sv_r, ThemeManager.scaled_i(10), ThemeManager.scaled_i(10), ThemeManager.scaled_i(6), ThemeManager.scaled_i(6)))
	_save_btn.add_theme_stylebox_override("hover",   ThemeManager.sbox(sv_col, sv_r, ThemeManager.scaled_i(10), ThemeManager.scaled_i(10), ThemeManager.scaled_i(6), ThemeManager.scaled_i(6)))
	_save_btn.add_theme_stylebox_override("focus",   ThemeManager.sbox(sv_col, sv_r, ThemeManager.scaled_i(10), ThemeManager.scaled_i(10), ThemeManager.scaled_i(6), ThemeManager.scaled_i(6)))
	_save_btn.add_theme_stylebox_override("pressed", ThemeManager.sbox(sv_col.darkened(0.20), sv_r))
	_save_btn.pressed.connect(func():
		ProfileManager.lock_and_save(ProfileManager.current_profile)
		_save_btn.visible = false
		_apply_profile_lock())
	_save_btn.visible = not ProfileManager.is_locked(ProfileManager.current_profile)
	header_hb.add_child(_save_btn)

	ProfileManager.profile_changed.connect(func(_n):
		if not is_instance_valid(_save_btn): return
		_save_btn.visible = not ProfileManager.is_locked(ProfileManager.current_profile)
		_apply_profile_lock())

	# === ZONE SCROLLABLE ===
	scroll = ScrollContainer.new()
	scroll.anchor_left = 0.0; scroll.anchor_right  = 1.0
	scroll.anchor_top  = 0.0; scroll.anchor_bottom = 1.0
	scroll.offset_top    = hdr_h
	scroll.offset_left   = pad
	scroll.offset_right  = -pad
	scroll.offset_bottom = -pad
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	content_vb = VBoxContainer.new()
	content_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_vb.add_theme_constant_override("separation",
			ThemeManager.scaled_i(ThemeManager.SECTION_GAP))
	scroll.add_child(content_vb)

	# === SECTIONS ===
	_build_section_profil()
	_build_section_mode()
	_build_section_operations()
	_build_section_operands()
	_build_section_sizes()
	_build_section_constraints()
	_build_section_audio()
	_build_section_music()
	_build_section_display()

	# Marge de bas (pour ne pas coller le dernier élément au bord)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, ThemeManager.scaled_i(20))
	content_vb.add_child(spacer)

	_apply_profile_lock()

# ── Helpers de cartes ───────────────────────────────────────
func _card() -> PanelContainer:
	var pc := PanelContainer.new()
	var pad := ThemeManager.scaled_i(ThemeManager.PADDING_CARD)
	pc.add_theme_stylebox_override("panel",
			ThemeManager.sbox(ThemeManager.SURFACE,
					ThemeManager.scaled_i(ThemeManager.RADIUS_CARD),
					pad, pad, pad, pad,
					ThemeManager.BORDER_2, 2))
	return pc

# Crée une carte « section » avec en-tête (icône + titre + flèche repliable)
# et renvoie le VBoxContainer où l'on ajoute les champs.
func _section(icon_name: String, title: String,
		accent: Color = ThemeManager.ACCENT, lockable: bool = false) -> VBoxContainer:
	var card := _card()
	content_vb.add_child(card)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation",
			ThemeManager.scaled_i(ThemeManager.SPACING_MD))
	card.add_child(outer)

	# Header de section : icône + titre + flèche ▼/▲
	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation",
			ThemeManager.scaled_i(ThemeManager.SPACING_MD))
	hdr.mouse_filter = Control.MOUSE_FILTER_STOP
	hdr.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	outer.add_child(hdr)

	var icon_box := _make_section_icon(icon_name, accent)
	hdr.add_child(icon_box)

	var lbl := Label.new()
	lbl.text = title
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	lbl.clip_text = true
	lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	lbl.add_theme_color_override("font_color", ThemeManager.TEXT)
	lbl.add_theme_font_size_override("font_size",
			ThemeManager.scaled_i(ThemeManager.FONT_LARGE))
	lbl.add_theme_font_override("font", ThemeDB.fallback_font)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hdr.add_child(lbl)

	# Flèche repliable ▼ / ▲
	var arrow := Label.new()
	arrow.text = "▼"
	arrow.add_theme_color_override("font_color", ThemeManager.TEXT_DIM)
	arrow.add_theme_font_size_override("font_size",
			ThemeManager.scaled_i(ThemeManager.FONT_MED))
	arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arrow.custom_minimum_size = Vector2(ThemeManager.scaled_i(32), 0)
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hdr.add_child(arrow)

	# Petit séparateur après le header
	var sep := HSeparator.new()
	sep.add_theme_stylebox_override("separator",
			ThemeManager.make_hsep_style(ThemeManager.BORDER))
	outer.add_child(sep)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation",
			ThemeManager.scaled_i(ThemeManager.SPACING_SM))
	outer.add_child(body)

	if lockable:
		_lockable_bodies.append(body)

	# Tap sur le header → toggle le body + le séparateur (release uniquement pour éviter scroll accidentel)
	hdr.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and not ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			if _touch_drag_dist > 20.0:
				return
			body.visible = not body.visible
			sep.visible = body.visible
			arrow.text = "▼" if body.visible else "▶"
			AudioManager.play_sfx("click"))

	return body

# ── Icônes vectorielles de section ──────────────────────────
# On dessine une icône simple dans un Control. Conteneur avec contour
# léger + fond transparent teinté pour rappeler l'image cible.
func _make_section_icon(name: String, color: Color) -> Control:
	var size := ThemeManager.scaled_i(ThemeManager.SECTION_ICON_BOX)
	var wrap := PanelContainer.new()
	wrap.custom_minimum_size = Vector2(size, size)
	wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bg := Color(color.r, color.g, color.b, 0.15)
	wrap.add_theme_stylebox_override("panel",
			ThemeManager.sbox(bg, ThemeManager.scaled_i(10), 0, 0, 0, 0,
					color, 2))
	var draw_ctrl := _IconDrawer.new()
	draw_ctrl.icon_name = name
	draw_ctrl.color = color
	draw_ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	draw_ctrl.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	draw_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(draw_ctrl)
	return wrap

# ── Section Profil ──────────────────────────────────────────
func _build_section_profil() -> void:
	var card := _card()
	content_vb.add_child(card)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation",
			ThemeManager.scaled_i(ThemeManager.SPACING_MD))
	card.add_child(vb)
	_lockable_bodies.append(vb)

	# Ligne du haut : icône utilisateur + "Profil actif" + nom
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation",
			ThemeManager.scaled_i(ThemeManager.SPACING_MD))
	vb.add_child(top)

	var icon := _make_section_icon("user", ThemeManager.ACCENT)
	top.add_child(icon)

	var nvb := VBoxContainer.new()
	nvb.add_theme_constant_override("separation", 2)
	nvb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nvb.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	top.add_child(nvb)

	var pa := Label.new()
	pa.text = "Profil actif"
	pa.add_theme_color_override("font_color", ThemeManager.ACCENT)
	pa.add_theme_font_size_override("font_size",
			ThemeManager.scaled_i(ThemeManager.FONT_SMALL))
	nvb.add_child(pa)

	# Dropdown de sélection du profil (filtré par mode courant)
	var profile_dd := _make_dropdown([], 0, func(idx):
		var fresh: Array = ProfileManager.list_profiles().filter(func(p: String) -> bool:
			return ProfileManager.get_profile_mode(p) == int(GameState.options.mode))
		if idx >= 0 and idx < fresh.size():
			ProfileManager.switch_to(fresh[idx]))
	profile_dd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	profile_dd.clip_text = true
	nvb.add_child(profile_dd)

	var _refresh_profile_dd := func():
		if not is_instance_valid(profile_dd): return
		var filtered: Array = ProfileManager.list_profiles().filter(func(p: String) -> bool:
			return ProfileManager.get_profile_mode(p) == int(GameState.options.mode))
		profile_dd.clear()
		var sel_idx := -1
		for i in filtered.size():
			profile_dd.add_item(filtered[i], i)
			if filtered[i] == ProfileManager.current_profile:
				sel_idx = i
		if sel_idx >= 0:
			profile_dd.select(sel_idx)

	_refresh_profile_dd.call()
	GameState.options_changed.connect(_refresh_profile_dd, CONNECT_DEFERRED)
	ProfileManager.profile_changed.connect(func(_n): _refresh_profile_dd.call())

	# Rangée de 3 boutons (Nouveau / Renommer / Supprimer) avec icônes
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",
			ThemeManager.scaled_i(ThemeManager.SPACING_SM))
	vb.add_child(row)

	var nb := _make_icon_btn("plus", "Nouveau", ThemeManager.ACCENT, func():
		_modal_text("Nom du nouveau profil", "", func(n):
			if ProfileManager.create_profile(n): ProfileManager.switch_to(n)),
		true)
	nb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(nb)

	var rb := _make_icon_btn("pencil", "Renommer", ThemeManager.SURFACE_2, func():
		var cur_name := ProfileManager.current_profile
		if cur_name == ProfileManager.DEFAULT_PROFILE:
			_toast("Le profil par défaut ne peut pas être renommé")
			return
		_modal_text("Nouveau nom", cur_name, func(n):
			ProfileManager.rename_profile(cur_name, n)),
		true)
	rb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(rb)

	var db := _make_icon_btn("trash", "Supprimer", ThemeManager.ERROR, func():
		if ProfileManager.current_profile == ProfileManager.DEFAULT_PROFILE:
			_toast("Le profil par défaut ne peut pas être supprimé")
			return
		if ProfileManager.delete_profile(ProfileManager.current_profile):
			_toast("Profil supprimé"),
		true)
	db.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(db)

# ── Section Mode de jeu ─────────────────────────────────────
func _build_section_mode() -> void:
	var s := _section("clock", "Mode de jeu")

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",
			ThemeManager.scaled_i(ThemeManager.SPACING_SM))
	row.custom_minimum_size = Vector2(0, ThemeManager.scaled_i(ThemeManager.FIELD_ROW_HEIGHT))
	s.add_child(row)

	var lbl := Label.new()
	lbl.text = "Mode"
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", ThemeManager.TEXT)
	lbl.add_theme_font_size_override("font_size",
			ThemeManager.scaled_i(ThemeManager.FONT_MED))
	row.add_child(lbl)

	var mode_names: Array = Array(GameState.MODE_NAMES.values())
	var dd := _make_dropdown(mode_names, GameState.options.mode, func(idx):
		var was_audio := int(GameState.options.mode) == GameState.Mode.AUDIO
		GameState.set_option("mode", idx)
		if idx == GameState.Mode.AUDIO and not was_audio:
			_pre_audio_audio_enabled = bool(GameState.options.audio_enabled)
			_pre_audio_voice_input   = bool(GameState.options.voice_input)
			GameState.set_option("audio_enabled", true)
			GameState.set_option("voice_input",   true)
		elif was_audio and idx != GameState.Mode.AUDIO:
			GameState.set_option("audio_enabled", _pre_audio_audio_enabled)
			GameState.set_option("voice_input",   _pre_audio_voice_input))
	# x1.3 plus large pour ne pas rogner le texte
	dd.custom_minimum_size.x = ThemeManager.scaled_i(300)
	dd.clip_text = true
	GameState.options_changed.connect(func():
		if is_instance_valid(dd):
			dd.set_meta("set_index", GameState.options.mode))
	row.add_child(dd)
	_mode_dd = dd

	# Champs spécifiques au mode (rebâtis quand le mode change)
	var dyn := VBoxContainer.new()
	dyn.add_theme_constant_override("separation",
			ThemeManager.scaled_i(ThemeManager.SPACING_SM))
	s.add_child(dyn)
	var refresh := func():
		for c in dyn.get_children(): c.queue_free()
		_build_mode_specific_fields(dyn)
	refresh.call()
	GameState.options_changed.connect(refresh, CONNECT_DEFERRED)

func _build_mode_specific_fields(parent: Node) -> void:
	match GameState.options.mode:
		GameState.Mode.CONTRE_LA_MONTRE:
			_add_int_field(parent, "Durée", "duration_sec", 10, 600, 10, "s")
		GameState.Mode.SERIE_CHRONO, GameState.Mode.AUDIO:
			_add_int_field(parent, "Nombre de calculs", "target_count", 5, 200, 5)
		GameState.Mode.FLASH_ANZAN:
			_add_int_field(parent, "Nombres / série", "flash_count", 3, 30, 1)
			_add_int_field(parent, "Nombre de séries", "flash_series", 1, 20, 1)
			_add_enum_field(parent, "Difficulté", "anzan_level",
					["Très lent", "Lent", "Moyen", "Rapide", "Très rapide"])
		GameState.Mode.INFERNAL:
			_add_int_field(parent, "N (n-back)", "infernal_n", 1, 6, 1)
			_add_int_field(parent, "Durée", "infernal_duration", 30, 600, 30, "s")
			_add_enum_field(parent, "Tempo", "infernal_tempo",
					["Lent", "Moyen", "Rapide", "Très rapide", "Extrême"])

# ── Section Opérations (cases à cocher) ─────────────────────
func _build_section_operations() -> void:
	var s := _section("calc", "Opérations", ThemeManager.ACCENT, true)
	_add_check_row(s, "Addition",               "op_add",  "+")
	_add_check_row(s, "Soustraction",           "op_sub",  "−")
	_add_check_row(s, "Multiplication",         "op_mul",  "×")
	_add_check_row(s, "Division",               "op_div",  "÷")
	var _idx_mix_ops := s.get_child_count()
	_add_check_row(s, "Mélanger les opérations","mix_ops", "⇄")
	_bind_group_vis(s, _idx_mix_ops, func():
		var n := 0
		for k in ["op_add","op_sub","op_mul","op_div"]:
			if GameState.options[k]: n += 1
		return n >= 2)

# ── Section Opérandes ───────────────────────────────────────
func _build_section_operands() -> void:
	var s := _section("blocks", "Nombre d'opérandes", ThemeManager.ACCENT, true)
	_add_int_field(s, "Min", "operand_min", 2, 6, 1)
	var hb_min := s.get_child(s.get_child_count() - 1) as HBoxContainer
	var plus_min := hb_min.get_child(3) as Button
	_add_int_field(s, "Max", "operand_max", 2, 6, 1)
	var hb_max := s.get_child(s.get_child_count() - 1) as HBoxContainer
	var minus_max := hb_max.get_child(1) as Button
	var _update_spinners := func():
		var eq: bool = int(GameState.options.operand_min) >= int(GameState.options.operand_max)
		plus_min.disabled = eq
		minus_max.disabled = eq
	_update_spinners.call()
	GameState.options_changed.connect(_update_spinners)

# ── Section Taille des nombres (chips) ──────────────────────
func _build_section_sizes() -> void:
	var s := _section("bars", "Taille des nombres", ThemeManager.ACCENT, false)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", ThemeManager.scaled_i(8))
	flow.add_theme_constant_override("v_separation", ThemeManager.scaled_i(8))
	s.add_child(flow)
	_add_chip(flow, "Unité(s) (0–9)",        "size_units")
	_add_chip(flow, "Dizaines (10–99)",       "size_tens")
	_add_chip(flow, "Centaines (100–999)",    "size_hundreds")
	_add_chip(flow, "Milliers (1k–9k)",       "size_thousands")
	_add_chip(flow, "Dizaines de milliers",   "size_tenk")
	_add_chip(flow, "Centaines de milliers",  "size_hundk")
	var _idx_mix_sizes := s.get_child_count()
	_add_check_row(s, "Mélanger les tailles", "mix_sizes")
	_bind_group_vis(s, _idx_mix_sizes, func():
		var n := 0
		for k in ["size_units","size_tens","size_hundreds","size_thousands","size_tenk","size_hundk"]:
			if GameState.options[k]: n += 1
		return n >= 2)

# ── Section Contraintes & confort (TOGGLES SWITCH) ──────────
func _build_section_constraints() -> void:
	var s := _section("shield", "Contraintes & confort", ThemeManager.ACCENT, true)
	_add_toggle_row(s, "Résultat toujours positif",   "positive_only", "plus")
	_add_toggle_row(s, "Autoriser nombres négatifs",  "allow_negative","minus")
	_add_toggle_row(s, "Uniquement nombres négatifs", "only_negative", "minus")
	_add_toggle_row(s, "Division à résultat entier",  "integer_div",   "divide")
	_add_toggle_row(s, "Addition sans retenue",       "add_no_carry",  "plus")
	_add_toggle_row(s, "Soustraction sans emprunt",   "sub_no_borrow", "minus")
	_add_toggle_row(s, "Parenthèses",                 "parentheses",   "parens")
	_add_toggle_row(s, "Limiter tables de multiplication", "limit_tables", "multiply")
	var _idx_tables_max := s.get_child_count()
	_add_int_field(s,  "Tables jusqu'à N",                  "tables_max", 2, 20, 1)
	_bind_group_vis(s, _idx_tables_max, func(): return bool(GameState.options.limit_tables))
	_add_int_field(s,  "Temps max / question",              "max_time_per_q", 0, 60, 1, "s")
	_add_toggle_row(s, "Limiter le résultat",         "limit_result",  "plus")
	var _idx_result_max := s.get_child_count()
	_add_int_field(s,  "Résultat ≤",                  "result_max", 10, 100000, 10)
	_bind_group_vis(s, _idx_result_max, func(): return bool(GameState.options.limit_result))
	_add_toggle_row(s, "Répéter jusqu'à réussite",    "repeat_until_ok", "")

# ── Sections Audio / Musique / Affichage ────────────────────
func _build_section_audio() -> void:
	var s := _section("mic", "Audio & voix", ThemeManager.ACCENT, true)
	_add_toggle_row(s, "Lecture vocale du calcul", "audio_enabled")
	var _idx_tts_lang := s.get_child_count()
	_add_enum_field(s, "Langue voix système",      "tts_lang",  ["fr", "en"])
	_bind_group_vis(s, _idx_tts_lang, func(): return bool(GameState.options.audio_enabled))
	_add_toggle_row(s, "Réponse vocale (micro)",   "voice_input")
	var _idx_stt := s.get_child_count()
	_add_enum_field(s, "Langue de réponse",        "stt_lang",  ["fr", "en"])
	_add_float_field(s, "Timing réponse",           "stt_delay", -2.0, 10.0, 0.1, "s")
	_bind_group_vis(s, _idx_stt, func(): return bool(GameState.options.voice_input))
	_add_toggle_row(s, "Masquer le calcul",        "hide_calc")
	_add_toggle_row(s, "Validation automatique",   "auto_validate")
	var _idx_av_delay := s.get_child_count()
	_add_float_field(s, "Délai validation auto",   "auto_validate_delay", 0.1, 10.0, 0.1, "s")
	_bind_group_vis(s, _idx_av_delay, func(): return bool(GameState.options.auto_validate))

func _build_section_music() -> void:
	var s := _section("note", "Musique", ThemeManager.ACCENT, true)
	_add_toggle_row(s, "Musique d'ambiance", "music_enabled")
	var _idx_music_vol := s.get_child_count()
	_add_int_field(s,  "Volume musique",     "music_volume", 0, 100, 5, "%")
	_bind_group_vis(s, _idx_music_vol, func(): return bool(GameState.options.music_enabled))
	_add_toggle_row(s, "Bruitages",          "sfx_enabled")
	var _idx_sfx_vol := s.get_child_count()
	_add_int_field(s,  "Volume bruitages",   "sfx_volume",   0, 100, 5, "%")
	_bind_group_vis(s, _idx_sfx_vol, func(): return bool(GameState.options.sfx_enabled))

func _build_section_display() -> void:
	var s := _section("screen", "Affichage", ThemeManager.ACCENT, true)
	_add_toggle_row(s, "Lumière verte continue", "show_neon")
	_add_toggle_row(s, "Lumière verte si correct", "green_correct")

	var _idx_fractions := s.get_child_count()
	_add_toggle_row(s, "Afficher en fractions (÷)", "show_fractions")
	_bind_group_vis(s, _idx_fractions, func(): return bool(GameState.options.op_div), "show_fractions")

	var _idx_column := s.get_child_count()
	_add_toggle_row(s, "Notation colonne (+/−/×)", "show_column")
	var _column_cond := func() -> bool:
		var cnt := (1 if bool(GameState.options.op_add) else 0) \
				+ (1 if bool(GameState.options.op_sub) else 0) \
				+ (1 if bool(GameState.options.op_mul) else 0) \
				+ (1 if bool(GameState.options.op_div) else 0)
		return cnt == 1 and (bool(GameState.options.op_add) or bool(GameState.options.op_sub) or bool(GameState.options.op_mul))
	_bind_group_vis(s, _idx_column, _column_cond, "show_column")

	# Fond de jeu avec libellés lisibles
	_add_subtle_sep(s)
	var bg_hb := HBoxContainer.new()
	bg_hb.custom_minimum_size = Vector2(0, ThemeManager.scaled_i(ThemeManager.FIELD_ROW_HEIGHT))
	bg_hb.add_theme_constant_override("separation", ThemeManager.scaled_i(8))
	s.add_child(bg_hb)
	var bg_lbl := Label.new()
	bg_lbl.text = "Fond de jeu"
	bg_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bg_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bg_lbl.add_theme_color_override("font_color", ThemeManager.TEXT)
	bg_lbl.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_MED))
	bg_hb.add_child(bg_lbl)
	var _bg_labels := ["Aucun", "Symboles", "Symboles + couleurs", "Bokeh"]
	var _bg_values := ["none", "rects", "rects_colors", "bokeh"]
	var _bg_cur: int = max(0, _bg_values.find(str(GameState.options.game_bg)))
	var bg_dd := _make_dropdown(_bg_labels, _bg_cur, func(idx):
		GameState.set_option("game_bg", _bg_values[idx]))
	bg_hb.add_child(bg_dd)

# ════════════════════════════════════════════════════════════
# WIDGETS
# ════════════════════════════════════════════════════════════

# ── Checkbox (carrée bleue) + label cliquable + symbole droite
func _add_check_row(parent: Node, label: String, opt_key: String,
		right_sym: String = "") -> void:
	_add_subtle_sep(parent)
	var row := _make_clickable_row()
	row.custom_minimum_size = Vector2(0, ThemeManager.scaled_i(ThemeManager.FIELD_ROW_HEIGHT))
	parent.add_child(row)

	var check := _make_checkbox(GameState.options[opt_key])
	row.add_child(check)

	var lbl := Label.new()
	lbl.text = label
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	lbl.clip_text = true
	lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_color_override("font_color", ThemeManager.TEXT)
	lbl.add_theme_font_size_override("font_size",
			ThemeManager.scaled_i(ThemeManager.FONT_MED))
	row.add_child(lbl)

	if right_sym != "":
		var sym := Label.new()
		sym.text = right_sym
		sym.add_theme_color_override("font_color", ThemeManager.TEXT_DIM)
		sym.add_theme_font_size_override("font_size",
				ThemeManager.scaled_i(ThemeManager.FONT_MED + 4))
		sym.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		sym.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sym.custom_minimum_size  = Vector2(ThemeManager.scaled_i(32), 0)
		sym.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(sym)

	# Clic sur TOUTE la ligne → toggle (la coche, le label, la marge)
	# On agit au RELÂCHEMENT pour distinguer tap (drag_dist < 20) du scroll.
	row.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and not ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			if _touch_drag_dist > 20.0:
				return
			var nv: bool = not GameState.options[opt_key]
			GameState.set_option(opt_key, nv)
			_update_checkbox(check, nv)
			AudioManager.play_sfx("click"))
	GameState.options_changed.connect(func():
		if is_instance_valid(check):
			_update_checkbox(check, bool(GameState.options[opt_key])), CONNECT_DEFERRED)

# ── Toggle « switch » (style iOS) + label cliquable + petite icône
func _add_toggle_row(parent: Node, label: String, opt_key: String,
		left_icon: String = "") -> void:
	_add_subtle_sep(parent)
	var row := _make_clickable_row()
	row.custom_minimum_size = Vector2(0, ThemeManager.scaled_i(ThemeManager.FIELD_ROW_HEIGHT))
	parent.add_child(row)

	# Petite icône à gauche (cercle avec + ou −)
	if left_icon != "":
		var ic := _IconDrawer.new()
		ic.icon_name = left_icon
		ic.color = ThemeManager.TEXT_DIM
		ic.bg_circle = true
		var s := ThemeManager.scaled_i(26)
		ic.custom_minimum_size = Vector2(s, s)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(ic)

	var lbl := Label.new()
	lbl.text = label
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	lbl.clip_text = true
	lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_color_override("font_color", ThemeManager.TEXT)
	lbl.add_theme_font_size_override("font_size",
			ThemeManager.scaled_i(ThemeManager.FONT_MED))
	row.add_child(lbl)

	var sw := _make_switch(GameState.options[opt_key])
	row.add_child(sw)

	row.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and not ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			if _touch_drag_dist > 20.0:
				return
			var nv: bool = not GameState.options[opt_key]
			GameState.set_option(opt_key, nv)
			_update_switch(sw, nv)
			AudioManager.play_sfx("click"))
	GameState.options_changed.connect(func():
		if is_instance_valid(sw):
			_update_switch(sw, bool(GameState.options[opt_key])), CONNECT_DEFERRED)

# ── Champ entier : Label  [−] [val] [+] [suffix]
func _add_int_field(parent: Node, label: String, opt_key: String,
		mn: int, mx: int, step: int, suffix: String = "") -> void:
	_add_subtle_sep(parent)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", ThemeManager.scaled_i(8))
	hb.custom_minimum_size = Vector2(0, ThemeManager.scaled_i(ThemeManager.FIELD_ROW_HEIGHT))
	parent.add_child(hb)

	var lbl := Label.new()
	lbl.text = label
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", ThemeManager.TEXT)
	lbl.add_theme_font_size_override("font_size",
			ThemeManager.scaled_i(ThemeManager.FONT_MED))
	hb.add_child(lbl)

	var minus := _make_spin_btn("−")
	hb.add_child(minus)

	# Fond sombre entre les boutons − et + (englobe la valeur)
	var val_bg := PanelContainer.new()
	val_bg.add_theme_stylebox_override("panel",
			ThemeManager.sbox(ThemeManager.SURFACE_2,
					ThemeManager.scaled_i(8), 0, 0, 0, 0,
					ThemeManager.BORDER_2, 1))
	val_bg.custom_minimum_size = Vector2(
			ThemeManager.scaled_i(ThemeManager.SPIN_VALUE_WIDTH), 0)
	hb.add_child(val_bg)

	var vl := Label.new()
	vl.text = str(GameState.options[opt_key])
	vl.add_theme_color_override("font_color", ThemeManager.ACCENT_2)
	vl.add_theme_font_size_override("font_size",
			ThemeManager.scaled_i(ThemeManager.FONT_LARGE))
	vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	vl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vl.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	val_bg.add_child(vl)

	var plus := _make_spin_btn("+")
	hb.add_child(plus)

	if suffix != "":
		var sf := Label.new()
		sf.text = suffix
		sf.add_theme_color_override("font_color", ThemeManager.TEXT_DIM)
		sf.add_theme_font_size_override("font_size",
				ThemeManager.scaled_i(ThemeManager.FONT_MED))
		sf.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		sf.custom_minimum_size = Vector2(ThemeManager.scaled_i(20), 0)
		hb.add_child(sf)

	minus.pressed.connect(func():
		var v: int = clamp(GameState.options[opt_key] - step, mn, mx)
		GameState.set_option(opt_key, v); vl.text = str(v)
		AudioManager.play_sfx("click"))
	plus.pressed.connect(func():
		var v: int = clamp(GameState.options[opt_key] + step, mn, mx)
		GameState.set_option(opt_key, v); vl.text = str(v)
		AudioManager.play_sfx("click"))
	GameState.options_changed.connect(func():
		if is_instance_valid(vl):
			vl.text = str(int(GameState.options[opt_key])), CONNECT_DEFERRED)
	var _spin_press_ms := [0]
	val_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	val_bg.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventScreenTouch:
			if ev.pressed:
				_spin_press_ms[0] = Time.get_ticks_msec()
			elif Time.get_ticks_msec() - _spin_press_ms[0] < 500 and _touch_drag_dist < 15.0:
				_open_spin_modal(opt_key, mn, mx, false, vl)
		elif ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				_spin_press_ms[0] = Time.get_ticks_msec()
			elif Time.get_ticks_msec() - _spin_press_ms[0] < 500 and _touch_drag_dist < 15.0:
				_open_spin_modal(opt_key, mn, mx, false, vl))

# ── Champ décimal : Label  [−] [val] [+] [suffix]
func _add_float_field(parent: Node, label: String, opt_key: String,
		mn: float, mx: float, step: float, suffix: String = "") -> void:
	_add_subtle_sep(parent)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", ThemeManager.scaled_i(8))
	hb.custom_minimum_size = Vector2(0, ThemeManager.scaled_i(ThemeManager.FIELD_ROW_HEIGHT))
	parent.add_child(hb)

	var lbl := Label.new()
	lbl.text = label
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", ThemeManager.TEXT)
	lbl.add_theme_font_size_override("font_size",
			ThemeManager.scaled_i(ThemeManager.FONT_MED))
	hb.add_child(lbl)

	var minus := _make_spin_btn("−")
	hb.add_child(minus)

	var val_bg := PanelContainer.new()
	val_bg.add_theme_stylebox_override("panel",
			ThemeManager.sbox(ThemeManager.SURFACE_2,
					ThemeManager.scaled_i(8), 0, 0, 0, 0,
					ThemeManager.BORDER_2, 1))
	val_bg.custom_minimum_size = Vector2(
			ThemeManager.scaled_i(ThemeManager.SPIN_VALUE_WIDTH), 0)
	hb.add_child(val_bg)

	var vl := Label.new()
	vl.text = "%.1f" % float(GameState.options[opt_key])
	vl.add_theme_color_override("font_color", ThemeManager.ACCENT_2)
	vl.add_theme_font_size_override("font_size",
			ThemeManager.scaled_i(ThemeManager.FONT_LARGE))
	vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	vl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vl.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	val_bg.add_child(vl)

	var plus := _make_spin_btn("+")
	hb.add_child(plus)

	if suffix != "":
		var sf := Label.new()
		sf.text = suffix
		sf.add_theme_color_override("font_color", ThemeManager.TEXT_DIM)
		sf.add_theme_font_size_override("font_size",
				ThemeManager.scaled_i(ThemeManager.FONT_MED))
		sf.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		sf.custom_minimum_size = Vector2(ThemeManager.scaled_i(20), 0)
		hb.add_child(sf)

	minus.pressed.connect(func():
		var v: float = snappedf(clamp(float(GameState.options[opt_key]) - step, mn, mx), step)
		GameState.set_option(opt_key, v); vl.text = "%.1f" % v
		AudioManager.play_sfx("click"))
	plus.pressed.connect(func():
		var v: float = snappedf(clamp(float(GameState.options[opt_key]) + step, mn, mx), step)
		GameState.set_option(opt_key, v); vl.text = "%.1f" % v
		AudioManager.play_sfx("click"))
	GameState.options_changed.connect(func():
		if is_instance_valid(vl):
			vl.text = "%.1f" % float(GameState.options[opt_key]), CONNECT_DEFERRED)
	var _spin_press_ms_f := [0]
	val_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	val_bg.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventScreenTouch:
			if ev.pressed:
				_spin_press_ms_f[0] = Time.get_ticks_msec()
			elif Time.get_ticks_msec() - _spin_press_ms_f[0] < 500 and _touch_drag_dist < 15.0:
				_open_spin_modal(opt_key, mn, mx, true, vl)
		elif ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				_spin_press_ms_f[0] = Time.get_ticks_msec()
			elif Time.get_ticks_msec() - _spin_press_ms_f[0] < 500 and _touch_drag_dist < 15.0:
				_open_spin_modal(opt_key, mn, mx, true, vl))

# ── Champ enum : Label  [dropdown]
func _add_enum_field(parent: Node, label: String, opt_key: String,
		choices: Array) -> void:
	_add_subtle_sep(parent)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", ThemeManager.scaled_i(8))
	hb.custom_minimum_size = Vector2(0, ThemeManager.scaled_i(ThemeManager.FIELD_ROW_HEIGHT))
	parent.add_child(hb)

	var lbl := Label.new()
	lbl.text = label
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.vertical_alignment    = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", ThemeManager.TEXT)
	lbl.add_theme_font_size_override("font_size",
			ThemeManager.scaled_i(ThemeManager.FONT_MED))
	hb.add_child(lbl)

	var cur = GameState.options[opt_key]
	var idx := 0
	if cur is int:
		idx = clamp(cur, 0, choices.size() - 1)
	elif cur is String:
		idx = choices.find(cur)
		if idx < 0: idx = 0

	var dd := _make_dropdown(choices, idx, func(new_idx):
		_apply_enum(opt_key, choices, new_idx))
	hb.add_child(dd)

func _apply_enum(opt_key: String, choices: Array, idx: int) -> void:
	var cur = GameState.options[opt_key]
	if cur is int: GameState.set_option(opt_key, idx)
	else:          GameState.set_option(opt_key, choices[idx])

# ── Chip (Unités (0–9), Dizaines…) ──────────────────────────
func _add_chip(parent: Node, label: String, opt_key: String) -> void:
	var radius := ThemeManager.scaled_i(ThemeManager.RADIUS_CHIP)
	var st_on  := ThemeManager.sbox(ThemeManager.ACCENT,    radius, 14, 16, 10, 10)
	var st_off := ThemeManager.sbox(ThemeManager.SURFACE_2, radius, 14, 16, 10, 10,
			ThemeManager.BORDER_2, 1)

	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel",
			st_on if GameState.options[opt_key] else st_off)
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(pc)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", ThemeManager.scaled_i(8))
	pc.add_child(row)

	# Mini-checkbox dans le chip (✓ blanc visible quand actif)
	var cbox := _make_mini_check(GameState.options[opt_key])
	cbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(cbox)

	var tl := Label.new()
	tl.text = label
	tl.add_theme_color_override("font_color", ThemeManager.TEXT)
	tl.add_theme_font_size_override("font_size",
			ThemeManager.scaled_i(ThemeManager.FONT_MED))
	tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(tl)

	pc.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and not ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			if _touch_drag_dist > 20.0:
				return
			var nv: bool = not GameState.options[opt_key]
			GameState.set_option(opt_key, nv)
			pc.add_theme_stylebox_override("panel", st_on if nv else st_off)
			_update_mini_check(cbox, nv)
			AudioManager.play_sfx("click"))
	GameState.options_changed.connect(func():
		if is_instance_valid(pc):
			var val: bool = bool(GameState.options[opt_key])
			pc.add_theme_stylebox_override("panel", st_on if val else st_off)
			_update_mini_check(cbox, val), CONNECT_DEFERRED)

# ────────────────────────────────────────────────────────────
# CHECKBOX (carrée grosse, bleue quand cochée)
# ────────────────────────────────────────────────────────────
func _make_checkbox(active: bool) -> PanelContainer:
	var pc := PanelContainer.new()
	var sz := ThemeManager.scaled_i(ThemeManager.CHECKBOX_SIZE)
	pc.custom_minimum_size = Vector2(sz, sz)
	pc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_update_checkbox(pc, active)

	var cc := CenterContainer.new()
	pc.add_child(cc)
	var cl := Label.new()
	cl.name = "Check"
	cl.text = "✓" if active else ""
	cl.add_theme_color_override("font_color", Color.WHITE)
	cl.add_theme_font_size_override("font_size",
			ThemeManager.scaled_i(ThemeManager.FONT_MED))
	cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(cl)
	return pc

func _update_checkbox(pc: PanelContainer, active: bool) -> void:
	var radius := ThemeManager.scaled_i(8)
	if active:
		pc.add_theme_stylebox_override("panel",
				ThemeManager.sbox(ThemeManager.ACCENT, radius))
	else:
		pc.add_theme_stylebox_override("panel",
				ThemeManager.sbox(ThemeManager.SURFACE_2, radius, 0,0,0,0,
						ThemeManager.BORDER_2, 1))
	# Met à jour la coche si elle existe déjà
	var cc := pc.get_child(0) if pc.get_child_count() > 0 else null
	if cc and cc.get_child_count() > 0:
		var lbl := cc.get_child(0) as Label
		if lbl: lbl.text = "✓" if active else ""

func _make_mini_check(active: bool) -> PanelContainer:
	var pc := PanelContainer.new()
	var sz := ThemeManager.scaled_i(22)
	pc.custom_minimum_size = Vector2(sz, sz)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_update_mini_check(pc, active)
	var cc := CenterContainer.new(); pc.add_child(cc)
	var lbl := Label.new()
	lbl.text = "✓" if active else ""
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_font_size_override("font_size", ThemeManager.scaled_i(14))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(lbl)
	return pc

func _update_mini_check(pc: PanelContainer, active: bool) -> void:
	var r := ThemeManager.scaled_i(6)
	if active:
		pc.add_theme_stylebox_override("panel",
				ThemeManager.sbox(ThemeManager.ACCENT.lightened(0.05), r))
	else:
		pc.add_theme_stylebox_override("panel",
				ThemeManager.sbox(Color(1,1,1,0.15), r, 0,0,0,0,
						Color(1,1,1,0.3), 1))
	if pc.get_child_count() > 0:
		var cc := pc.get_child(0)
		if cc and cc.get_child_count() > 0:
			var lbl := cc.get_child(0) as Label
			if lbl: lbl.text = "✓" if active else ""

# ────────────────────────────────────────────────────────────
# SWITCH (toggle ovale) — Control custom qui se redessine.
# ────────────────────────────────────────────────────────────
func _make_switch(active: bool) -> Control:
	var sw := _SwitchDrawer.new()
	sw.active = active
	sw.custom_minimum_size = Vector2(
			ThemeManager.scaled_i(ThemeManager.SWITCH_WIDTH),
			ThemeManager.scaled_i(ThemeManager.SWITCH_HEIGHT))
	sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return sw

func _update_switch(sw: Control, active: bool) -> void:
	if sw is _SwitchDrawer:
		(sw as _SwitchDrawer).active = active
		sw.queue_redraw()

# ────────────────────────────────────────────────────────────
# BOUTONS +/− (spin)
# ────────────────────────────────────────────────────────────
func _make_spin_btn(txt: String) -> Button:
	var b := Button.new()
	b.text = txt
	var s := ThemeManager.scaled_i(ThemeManager.SPIN_BTN_SIZE)
	b.custom_minimum_size = Vector2(s, s)
	b.add_theme_color_override("font_color", ThemeManager.TEXT)
	b.add_theme_font_size_override("font_size",
			ThemeManager.scaled_i(ThemeManager.FONT_LARGE))
	var r := ThemeManager.scaled_i(10)
	b.add_theme_stylebox_override("normal",
			ThemeManager.sbox(ThemeManager.SURFACE_2, r, 0,0,0,0,
					ThemeManager.BORDER_2, 1))
	b.add_theme_stylebox_override("hover",
			ThemeManager.sbox(ThemeManager.SURFACE_2, r, 0,0,0,0,
					ThemeManager.BORDER_2, 1))
	b.add_theme_stylebox_override("focus",
			ThemeManager.sbox(ThemeManager.SURFACE_2, r, 0,0,0,0,
					ThemeManager.BORDER_2, 1))
	b.add_theme_stylebox_override("pressed",
			ThemeManager.sbox(ThemeManager.SURFACE_2.darkened(0.10), r))
	return b

# Bouton retour « ‹ »
func _make_back_btn() -> Button:
	var b := Button.new()
	b.text = "‹"
	var s := ThemeManager.scaled_i(56)
	b.custom_minimum_size = Vector2(s, s)
	b.add_theme_color_override("font_color", ThemeManager.TEXT)
	b.add_theme_font_size_override("font_size",
			ThemeManager.scaled_i(ThemeManager.FONT_TITLE))
	var r := ThemeManager.scaled_i(10)
	b.add_theme_stylebox_override("normal",  ThemeManager.sbox(Color(0,0,0,0), r))
	b.add_theme_stylebox_override("hover",   ThemeManager.sbox(Color(1,1,1,0.07), r))
	b.add_theme_stylebox_override("pressed", ThemeManager.sbox(Color(1,1,1,0.12), r))
	return b

# Bouton à icône + texte : un PanelContainer stylé qui couvre un Button
# transparent au-dessus pour la gestion des évènements.
func _make_icon_btn(icon: String, label: String, color: Color,
		cb: Callable, compact: bool = false) -> Control:
	var root := Control.new()
	var btn_h := ThemeManager.scaled_i(46 if compact else 54)
	root.custom_minimum_size = Vector2(0, btn_h)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var r     := ThemeManager.scaled_i(ThemeManager.RADIUS_BTN)
	var pad_x := ThemeManager.scaled_i(6 if compact else 14)
	var pad_y := ThemeManager.scaled_i(6 if compact else 10)
	var font_sz := ThemeManager.scaled_i(ThemeManager.FONT_SMALL if compact else ThemeManager.FONT_MED)
	var st_normal  := ThemeManager.sbox(color, r, pad_x, pad_x, pad_y, pad_y)
	var st_hover   := ThemeManager.sbox(color.lightened(0.10), r, pad_x, pad_x, pad_y, pad_y)
	var st_pressed := ThemeManager.sbox(color.darkened(0.15), r, pad_x, pad_x, pad_y, pad_y)

	var pc := PanelContainer.new()
	pc.anchor_right = 1.0; pc.anchor_bottom = 1.0
	pc.add_theme_stylebox_override("panel", st_normal)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(pc)

	# Conteneur centré (icône + label)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(center)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", ThemeManager.scaled_i(8))
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(hb)

	var ic := _IconDrawer.new()
	ic.icon_name = icon
	ic.color = Color.WHITE
	var isz := ThemeManager.scaled_i(18 if compact else 22)
	ic.custom_minimum_size = Vector2(isz, isz)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(ic)

	var lbl := Label.new()
	lbl.text = label
	lbl.add_theme_color_override("font_color", ThemeManager.TEXT)
	lbl.add_theme_font_size_override("font_size", font_sz)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.clip_text = true
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(lbl)

	# Button invisible par-dessus pour les events
	var btn := Button.new()
	btn.anchor_right = 1.0; btn.anchor_bottom = 1.0
	btn.flat = true
	btn.add_theme_stylebox_override("normal",  ThemeManager.sbox(Color(0,0,0,0), r))
	btn.add_theme_stylebox_override("hover",   ThemeManager.sbox(Color(0,0,0,0), r))
	btn.add_theme_stylebox_override("pressed", ThemeManager.sbox(Color(0,0,0,0), r))
	btn.add_theme_stylebox_override("focus",   ThemeManager.sbox(Color(0,0,0,0), r))
	root.add_child(btn)

	# Échange du stylebox selon l'état
	btn.mouse_entered.connect(func(): pc.add_theme_stylebox_override("panel", st_hover))
	btn.mouse_exited.connect(func():  pc.add_theme_stylebox_override("panel", st_normal))
	btn.button_down.connect(func():   pc.add_theme_stylebox_override("panel", st_pressed))
	btn.button_up.connect(func():
		# Repasse en hover si toujours survolé, sinon normal
		var is_h := btn.get_global_rect().has_point(btn.get_global_mouse_position())
		pc.add_theme_stylebox_override("panel", st_hover if is_h else st_normal))

	if cb.is_valid():
		btn.pressed.connect(func(): AudioManager.play_sfx("click"); cb.call())
	return root

# ────────────────────────────────────────────────────────────
# DROPDOWN — basé sur OptionButton natif (popup réel garanti).
# Le bouton expose set_meta("set_index", i) pour le sync externe.
# ────────────────────────────────────────────────────────────
func _make_dropdown(choices: Array, initial_idx: int, on_pick: Callable) -> OptionButton:
	var ob := OptionButton.new()
	var min_w := ThemeManager.scaled_i(230)
	var min_h := ThemeManager.scaled_i(52)
	ob.custom_minimum_size = Vector2(min_w, min_h)
	ob.size_flags_horizontal = Control.SIZE_EXPAND
	ob.alignment = HORIZONTAL_ALIGNMENT_LEFT
	ob.clip_text = true

	# Police
	ob.add_theme_color_override("font_color",         ThemeManager.TEXT)
	ob.add_theme_color_override("font_hover_color",   ThemeManager.TEXT)
	ob.add_theme_color_override("font_pressed_color", ThemeManager.TEXT)
	ob.add_theme_color_override("font_focus_color",   ThemeManager.TEXT)
	ob.add_theme_font_size_override("font_size",
			ThemeManager.scaled_i(ThemeManager.FONT_MED))

	# StyleBoxes du bouton (les marges droite laissent la place à la flèche
	# native de l'OptionButton)
	var r       := ThemeManager.scaled_i(10)
	var pad_l   := ThemeManager.scaled_i(16)
	var pad_r   := ThemeManager.scaled_i(40)
	var pad_y   := ThemeManager.scaled_i(8)
	var s_norm  := ThemeManager.sbox(ThemeManager.SURFACE_2, r,
			pad_l, pad_r, pad_y, pad_y, ThemeManager.BORDER_2, 1)
	var s_hover := ThemeManager.sbox(ThemeManager.SURFACE_3, r,
			pad_l, pad_r, pad_y, pad_y, ThemeManager.BORDER_2, 1)
	var s_press := ThemeManager.sbox(ThemeManager.SURFACE_2.darkened(0.1), r,
			pad_l, pad_r, pad_y, pad_y, ThemeManager.BORDER_2, 1)
	ob.add_theme_stylebox_override("normal",   s_norm)
	ob.add_theme_stylebox_override("hover",    s_hover)
	ob.add_theme_stylebox_override("pressed",  s_press)
	ob.add_theme_stylebox_override("focus",    ThemeManager.sbox(Color(0,0,0,0), r))

	# Style du popup
	var pop := ob.get_popup()
	pop.add_theme_color_override("font_color",       ThemeManager.TEXT)
	pop.add_theme_color_override("font_hover_color", Color.WHITE)
	pop.add_theme_font_size_override("font_size",
			ThemeManager.scaled_i(ThemeManager.FONT_MED))
	pop.add_theme_constant_override("v_separation", ThemeManager.scaled_i(6))
	pop.add_theme_stylebox_override("panel",
			ThemeManager.sbox(ThemeManager.SURFACE_2, r,
					ThemeManager.scaled_i(8), ThemeManager.scaled_i(8),
					ThemeManager.scaled_i(8), ThemeManager.scaled_i(8),
					ThemeManager.BORDER_2, 1))
	pop.add_theme_stylebox_override("hover",
			ThemeManager.sbox(ThemeManager.ACCENT, ThemeManager.scaled_i(8),
					ThemeManager.scaled_i(10), ThemeManager.scaled_i(10),
					ThemeManager.scaled_i(6),  ThemeManager.scaled_i(6)))

	# Items
	for i in choices.size():
		ob.add_item(str(choices[i]), i)
	if initial_idx >= 0 and initial_idx < choices.size():
		ob.select(initial_idx)

	ob.item_selected.connect(func(idx: int):
		AudioManager.play_sfx("click")
		if on_pick.is_valid(): on_pick.call(idx))

	# Sync externe : un Timer scrute set_meta("set_index", x).
	ob.set_meta("set_index", -1)
	var watcher := Timer.new()
	watcher.wait_time = 0.25
	watcher.autostart = true
	watcher.timeout.connect(func():
		var idx = ob.get_meta("set_index", -1)
		if typeof(idx) == TYPE_INT and idx >= 0 and idx < choices.size() \
				and idx != ob.get_selected_id():
			ob.select(idx)
			ob.set_meta("set_index", -1))
	ob.add_child(watcher)
	return ob

# ────────────────────────────────────────────────────────────
# Verrou profil : overlay sur sections non-mode quand le profil est verrouillé.
# ────────────────────────────────────────────────────────────
func _apply_profile_lock() -> void:
	var locked := ProfileManager.is_locked(ProfileManager.current_profile)
	for body in _lockable_bodies:
		if not is_instance_valid(body): continue
		var existing: Node = body.get_node_or_null("_LockOverlay")
		if locked and existing == null:
			var ov := _make_lock_overlay()
			ov.name = "_LockOverlay"
			body.add_child(ov)
		elif not locked and existing != null:
			existing.queue_free()
	# Le mode de jeu doit rester navigable même avec profil verrouillé.
	if is_instance_valid(_mode_dd):
		_mode_dd.disabled = false
		_mode_dd.modulate.a = 1.0

func _make_lock_overlay() -> Control:
	var ov := Control.new()
	ov.anchor_right = 1.0; ov.anchor_bottom = 1.0
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(ThemeManager.BG.r, ThemeManager.BG.g, ThemeManager.BG.b, 0.78)
	dim.anchor_right = 1.0; dim.anchor_bottom = 1.0
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_child(dim)
	var center := CenterContainer.new()
	center.anchor_right = 1.0; center.anchor_bottom = 1.0
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_child(center)
	var lbl := Label.new()
	lbl.text = "🔒  Options verrouillées"
	lbl.add_theme_color_override("font_color", ThemeManager.TEXT_DIM)
	lbl.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_SMALL))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(lbl)
	return ov

# ────────────────────────────────────────────────────────────
# Visibilité dynamique : cache/affiche les enfants [start_idx, end[
# en fonction de condition_fn chaque fois qu'options change.
# ────────────────────────────────────────────────────────────
func _bind_group_vis(parent: Node, start_idx: int, condition_fn: Callable, opt_to_clear: String = "") -> void:
	var end_idx := parent.get_child_count()
	var update_fn := func():
		if not is_instance_valid(parent): return
		var show: bool = condition_fn.call()
		for i in range(start_idx, end_idx):
			if i < parent.get_child_count():
				parent.get_child(i).visible = show
		if not show and opt_to_clear != "" and bool(GameState.options.get(opt_to_clear, false)):
			GameState.set_option(opt_to_clear, false)
	update_fn.call()
	GameState.options_changed.connect(update_fn, CONNECT_DEFERRED)

# ────────────────────────────────────────────────────────────
# Séparateur subtil entre lignes (ne s'ajoute pas si c'est le 1er enfant)
# ────────────────────────────────────────────────────────────
func _add_subtle_sep(parent: Node) -> void:
	if parent.get_child_count() > 0:
		var sep := HSeparator.new()
		sep.add_theme_stylebox_override("separator",
				ThemeManager.make_hsep_style(
						Color(ThemeManager.BORDER.r, ThemeManager.BORDER.g,
								ThemeManager.BORDER.b, 0.35)))
		sep.add_theme_constant_override("separation", 0)
		parent.add_child(sep)

# ────────────────────────────────────────────────────────────
# Ligne cliquable (avec hover discret)
# ────────────────────────────────────────────────────────────
func _make_clickable_row() -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation",
			ThemeManager.scaled_i(ThemeManager.SPACING_MD))
	hb.mouse_filter = Control.MOUSE_FILTER_STOP
	# On peut ajouter un fond hover via theme override de container ? Non,
	# HBoxContainer n'a pas de style. On laisse simple (curseur main).
	hb.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return hb

# ════════════════════════════════════════════════════════════
# NAVIGATION / INPUTS
# ════════════════════════════════════════════════════════════
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
			_touch_drag_dist = 0.0
			_touch_history.clear()
			_touch_history.append({"t": Time.get_ticks_msec(), "y": event.position.y})
		else:
			_is_touching = false
			_scroll_velocity = _calc_release_velocity()
			_touch_history.clear()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_touch_drag_dist = 0.0
	elif event is InputEventScreenDrag:
		var now: int = Time.get_ticks_msec()
		_touch_history.append({"t": now, "y": event.position.y})
		while _touch_history.size() > 1 and _touch_history[0].t < now - 80:
			_touch_history.pop_front()
		scroll.scroll_vertical -= int(event.relative.y)
		_touch_drag_dist += absf(event.relative.y)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE or event.keycode == KEY_BACK:
			get_viewport().set_input_as_handled()
			SceneRouter.goto("res://scenes/MainMenu.tscn")

func _exit_tree() -> void:
	# Disconnect all our lambdas from global signals to prevent stale-callback crashes
	for conn in GameState.options_changed.get_connections():
		if conn.callable.get_object() == self:
			GameState.options_changed.disconnect(conn.callable)
	for conn in ProfileManager.profile_changed.get_connections():
		if conn.callable.get_object() == self:
			ProfileManager.profile_changed.disconnect(conn.callable)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		AudioManager.play_sfx("back")
		SceneRouter.goto("res://scenes/MainMenu.tscn")

# ════════════════════════════════════════════════════════════
# MODAL & TOAST
# ════════════════════════════════════════════════════════════
func _modal_text(prompt: String, initial: String, on_ok: Callable) -> void:
	var layer := CanvasLayer.new(); layer.layer = 50; add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0,0,0,0.65)
	bg.anchor_right = 1.0; bg.anchor_bottom = 1.0
	layer.add_child(bg)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.5; panel.anchor_right = 0.5
	panel.anchor_top  = 0.5; panel.anchor_bottom = 0.5
	var w := ThemeManager.scaled_i(440)
	var h := ThemeManager.scaled_i(240)
	panel.offset_left = -w / 2; panel.offset_right = w / 2
	panel.offset_top  = -h / 2; panel.offset_bottom = h / 2
	panel.add_theme_stylebox_override("panel",
			ThemeManager.make_panel_style(ThemeManager.SURFACE,
					ThemeManager.scaled_i(ThemeManager.RADIUS_CARD),
					ThemeManager.BORDER, 1))
	layer.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation",
			ThemeManager.scaled_i(ThemeManager.SPACING_MD))
	panel.add_child(vb)
	# padding interne via un margin container
	var mc := MarginContainer.new()
	var pad := ThemeManager.scaled_i(20)
	mc.add_theme_constant_override("margin_left",   pad)
	mc.add_theme_constant_override("margin_right",  pad)
	mc.add_theme_constant_override("margin_top",    pad)
	mc.add_theme_constant_override("margin_bottom", pad)
	panel.remove_child(vb)
	panel.add_child(mc)
	mc.add_child(vb)

	var l := Label.new(); l.text = prompt
	l.add_theme_color_override("font_color", ThemeManager.TEXT)
	l.add_theme_font_size_override("font_size",
			ThemeManager.scaled_i(ThemeManager.FONT_MED))
	vb.add_child(l)

	var le := LineEdit.new(); le.text = initial
	le.custom_minimum_size = Vector2(0, ThemeManager.scaled_i(46))
	le.add_theme_font_size_override("font_size",
			ThemeManager.scaled_i(ThemeManager.FONT_MED))
	le.add_theme_color_override("font_color", ThemeManager.TEXT)
	le.add_theme_stylebox_override("normal",
			ThemeManager.sbox(ThemeManager.SURFACE_2, ThemeManager.scaled_i(8),
					ThemeManager.scaled_i(12), ThemeManager.scaled_i(12), 0, 0,
					ThemeManager.BORDER_2, 1))
	le.add_theme_stylebox_override("focus",
			ThemeManager.sbox(ThemeManager.SURFACE_2, ThemeManager.scaled_i(8),
					ThemeManager.scaled_i(12), ThemeManager.scaled_i(12), 0, 0,
					ThemeManager.ACCENT, 2))
	vb.add_child(le)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", ThemeManager.scaled_i(10))
	vb.add_child(hb)
	var ok := _make_icon_btn("plus", "OK", ThemeManager.SUCCESS, func():
		on_ok.call(le.text); layer.queue_free())
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(ok)
	var cancel := _make_icon_btn("cross", "Annuler", ThemeManager.SURFACE_2, func():
		layer.queue_free())
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(cancel)
	le.grab_focus()

func _open_spin_modal(opt_key: String, mn_v: float, mx_v: float, is_float: bool, vl: Label) -> void:
	var cur_str := "%.1f" % float(GameState.options[opt_key]) if is_float else str(int(GameState.options[opt_key]))
	var hint := "%.1f – %.1f" % [mn_v, mx_v] if is_float else "%d – %d" % [int(mn_v), int(mx_v)]
	var layer := CanvasLayer.new(); layer.layer = 50; add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0,0,0,0.65)
	bg.anchor_right = 1.0; bg.anchor_bottom = 1.0
	layer.add_child(bg)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5; panel.anchor_right = 0.5
	panel.anchor_top  = 0.5; panel.anchor_bottom = 0.5
	var w := ThemeManager.scaled_i(380); var h := ThemeManager.scaled_i(200)
	panel.offset_left = -w/2; panel.offset_right = w/2
	panel.offset_top  = -h/2; panel.offset_bottom = h/2
	panel.add_theme_stylebox_override("panel",
		ThemeManager.make_panel_style(ThemeManager.SURFACE, ThemeManager.scaled_i(ThemeManager.RADIUS_CARD), ThemeManager.BORDER, 1))
	layer.add_child(panel)
	var mc := MarginContainer.new()
	var pad := ThemeManager.scaled_i(20)
	mc.add_theme_constant_override("margin_left", pad); mc.add_theme_constant_override("margin_right", pad)
	mc.add_theme_constant_override("margin_top",  pad); mc.add_theme_constant_override("margin_bottom", pad)
	panel.add_child(mc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", ThemeManager.scaled_i(ThemeManager.SPACING_MD))
	mc.add_child(vb)
	var lbl := Label.new(); lbl.text = "Valeur (%s)" % hint
	lbl.add_theme_color_override("font_color", ThemeManager.TEXT)
	lbl.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_MED))
	vb.add_child(lbl)
	var le := LineEdit.new(); le.text = cur_str
	le.virtual_keyboard_enabled = true
	le.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	le.custom_minimum_size = Vector2(0, ThemeManager.scaled_i(46))
	le.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_LARGE))
	le.add_theme_color_override("font_color", ThemeManager.ACCENT_2)
	le.add_theme_stylebox_override("normal", ThemeManager.sbox(ThemeManager.SURFACE_2, ThemeManager.scaled_i(8), ThemeManager.scaled_i(12), ThemeManager.scaled_i(12), 0, 0, ThemeManager.BORDER_2, 1))
	le.add_theme_stylebox_override("focus",  ThemeManager.sbox(ThemeManager.SURFACE_2, ThemeManager.scaled_i(8), ThemeManager.scaled_i(12), ThemeManager.scaled_i(12), 0, 0, ThemeManager.ACCENT, 2))
	vb.add_child(le)
	var hb := HBoxContainer.new(); hb.add_theme_constant_override("separation", ThemeManager.scaled_i(10)); vb.add_child(hb)
	var apply_fn := func():
		if is_float:
			var v := snappedf(clamp(le.text.to_float(), mn_v, mx_v), 0.1)
			GameState.set_option(opt_key, v); vl.text = "%.1f" % v
		else:
			var v := int(clamp(le.text.to_float(), mn_v, mx_v))
			GameState.set_option(opt_key, v); vl.text = str(v)
		layer.queue_free()
	le.text_submitted.connect(func(_t): apply_fn.call())
	var ok := _make_icon_btn("plus", "OK", ThemeManager.SUCCESS, apply_fn, true)
	ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL; hb.add_child(ok)
	var cancel := _make_icon_btn("cross", "Annuler", ThemeManager.SURFACE_2, func(): layer.queue_free(), true)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL; hb.add_child(cancel)
	le.grab_focus()
	le.select_all()

func _toast(msg: String) -> void:
	var layer := CanvasLayer.new(); layer.layer = 60; add_child(layer)
	var pc := PanelContainer.new()
	pc.anchor_left = 0.5; pc.anchor_right = 0.5; pc.anchor_bottom = 1.0
	var w := ThemeManager.scaled_i(320)
	pc.offset_left = -w / 2; pc.offset_right = w / 2
	pc.offset_top = -ThemeManager.scaled_i(140); pc.offset_bottom = -ThemeManager.scaled_i(70)
	pc.add_theme_stylebox_override("panel",
			ThemeManager.make_panel_style(ThemeManager.ACCENT.darkened(0.25),
					ThemeManager.scaled_i(12)))
	layer.add_child(pc)
	var lbl := Label.new(); lbl.text = msg
	lbl.add_theme_color_override("font_color", ThemeManager.TEXT)
	lbl.add_theme_font_size_override("font_size",
			ThemeManager.scaled_i(ThemeManager.FONT_MED))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pc.add_child(lbl)
	var tw := create_tween()
	tw.tween_interval(1.6); tw.tween_property(pc, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func(): layer.queue_free())


# ════════════════════════════════════════════════════════════
# Classe interne : SwitchDrawer (toggle ovale custom)
# ════════════════════════════════════════════════════════════
class _SwitchDrawer extends Control:
	var active: bool = false

	func _ready() -> void:
		resized.connect(queue_redraw)
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if w <= 0 or h <= 0:
			return
		var radius := h / 2.0
		# Piste (capsule)
		var bg := ThemeManager.ACCENT if active else ThemeManager.SURFACE_3
		_draw_capsule(Vector2.ZERO, Vector2(w, h), bg)
		# Pastille
		var pad: float = maxf(2.0, h * 0.10)
		var k: float = h - pad * 2.0
		var kx: float = (w - k - pad) if active else pad
		draw_circle(Vector2(kx + k / 2.0, h / 2.0), k / 2.0, Color.WHITE)

	func _draw_capsule(pos: Vector2, sz: Vector2, col: Color) -> void:
		var r: float = sz.y / 2.0
		# Rectangle central
		draw_rect(Rect2(pos + Vector2(r, 0), Vector2(sz.x - 2 * r, sz.y)), col)
		# Deux demi-cercles
		draw_circle(pos + Vector2(r, r), r, col)
		draw_circle(pos + Vector2(sz.x - r, r), r, col)

# ════════════════════════════════════════════════════════════
# Classe interne : dessinateur d'icônes vectorielles simples
# ════════════════════════════════════════════════════════════
class _IconDrawer extends Control:
	var icon_name: String = ""
	var color: Color = Color.WHITE
	var bg_circle: bool = false

	func _ready() -> void:
		resized.connect(queue_redraw)
		queue_redraw()

	func _draw() -> void:
		var sz := size
		if sz.x <= 0 or sz.y <= 0:
			return
		var c := Vector2(sz.x / 2.0, sz.y / 2.0)
		var r: float = minf(sz.x, sz.y) / 2.0

		if bg_circle:
			# Cercle de fond légèrement teinté
			var bgc := Color(color.r, color.g, color.b, 0.18)
			draw_circle(c, r, bgc)
			# Bordure
			draw_arc(c, r - 1, 0, TAU, 32, color, 1.5, true)

		match icon_name:
			"user":          _draw_user(c, r)
			"clock":         _draw_clock(c, r)
			"calc":          _draw_calc(c, r)
			"blocks":        _draw_blocks(c, r)
			"bars":          _draw_bars(c, r)
			"shield":        _draw_shield(c, r)
			"mic":           _draw_mic(c, r)
			"note":          _draw_note(c, r)
			"screen":        _draw_screen(c, r)
			"plus":          _draw_plus(c, r)
			"minus":         _draw_minus(c, r)
			"pencil":        _draw_pencil(c, r)
			"trash":         _draw_trash(c, r)
			"cross":         _draw_cross(c, r)
			"divide":        _draw_divide(c, r)
			"multiply":      _draw_multiply(c, r)
			"parens":        _draw_parens(c, r)

	# ── Primitives d'icônes ─────────────────────────────────
	func _stroke() -> float:
		return maxf(1.6, size.x * 0.08)

	func _draw_user(c: Vector2, r: float) -> void:
		var s := _stroke()
		# Tête : cercle plein avec contour
		var head_r := r * 0.32
		var head_c := c + Vector2(0, -r * 0.28)
		draw_arc(head_c, head_r, 0, TAU, 24, color, s, true)
		# Épaules/buste : demi-cercle ouvert vers le haut
		var torso_r := r * 0.70
		var torso_c := c + Vector2(0, r * 0.95)
		draw_arc(torso_c, torso_r, PI, TAU, 24, color, s, true)

	func _draw_clock(c: Vector2, r: float) -> void:
		var s := _stroke()
		draw_arc(c, r * 0.85, 0, TAU, 32, color, s, true)
		# Aiguilles
		draw_line(c, c + Vector2(0, -r * 0.55), color, s, true)
		draw_line(c, c + Vector2(r * 0.42, 0), color, s, true)
		# Petit bouton du haut
		draw_line(c + Vector2(-r * 0.18, -r * 0.95),
				c + Vector2(r * 0.18, -r * 0.95), color, s, true)

	func _draw_calc(c: Vector2, r: float) -> void:
		var s := _stroke()
		var w := r * 1.55; var h := r * 1.7
		var x := c.x - w/2; var y := c.y - h/2
		# Cadre
		draw_rect(Rect2(x, y, w, h), color, false, s)
		# Écran
		var sh := h * 0.30
		draw_rect(Rect2(x + w*0.10, y + h*0.10, w*0.80, sh), color, false, s * 0.9)
		# Touches : grille 3×3
		var by := y + h*0.50
		var bw := w*0.80; var bh := h*0.42
		var bx := x + w*0.10
		var cell_w := bw / 3.0; var cell_h := bh / 3.0
		for i in 3:
			for j in 3:
				var cx := bx + cell_w * j + cell_w/2
				var cy := by + cell_h * i + cell_h/2
				draw_circle(Vector2(cx, cy), r * 0.07, color)

	func _draw_blocks(c: Vector2, r: float) -> void:
		# Trois cubes empilés (1,2,3)
		var s := _stroke()
		var sz := r * 0.55
		# bottom-left
		var p1 := c + Vector2(-r*0.55, r*0.1)
		# bottom-right
		var p2 := c + Vector2(r*0.05,  r*0.1)
		# top-center
		var p3 := c + Vector2(-r*0.25, -r*0.55)
		for p in [p1, p2, p3]:
			draw_rect(Rect2(p, Vector2(sz, sz)), color, false, s)
		# chiffres
		var f := ThemeDB.fallback_font
		var fs := int(sz * 0.55)
		draw_string(f, p1 + Vector2(sz*0.30, sz*0.78), "1", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)
		draw_string(f, p2 + Vector2(sz*0.30, sz*0.78), "2", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)
		draw_string(f, p3 + Vector2(sz*0.30, sz*0.78), "3", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)

	func _draw_bars(c: Vector2, r: float) -> void:
		# Diagramme à barres : 3 barres montantes
		var s := _stroke()
		var bw := r * 0.30
		var base_y := c.y + r * 0.65
		var x0 := c.x - r * 0.75
		var heights := [r * 0.55, r * 0.95, r * 1.30]
		for i in 3:
			var x := x0 + i * (bw + r * 0.10)
			var h: float = heights[i]
			draw_rect(Rect2(x, base_y - h, bw, h), color)

	func _draw_shield(c: Vector2, r: float) -> void:
		var s := _stroke()
		# Forme bouclier (poly)
		var top := c + Vector2(0, -r * 0.85)
		var tl  := c + Vector2(-r * 0.75, -r * 0.55)
		var tr  := c + Vector2( r * 0.75, -r * 0.55)
		var bot := c + Vector2(0,  r * 0.85)
		var pts := PackedVector2Array([top, tr, c + Vector2(r * 0.55, r * 0.20), bot,
				c + Vector2(-r * 0.55, r * 0.20), tl, top])
		for i in pts.size() - 1:
			draw_line(pts[i], pts[i + 1], color, s, true)
		# Petit check à l'intérieur
		var p1 := c + Vector2(-r * 0.28, 0)
		var p2 := c + Vector2(-r * 0.05, r * 0.22)
		var p3 := c + Vector2(r * 0.32, -r * 0.20)
		draw_line(p1, p2, color, s, true)
		draw_line(p2, p3, color, s, true)

	func _draw_mic(c: Vector2, r: float) -> void:
		var s := _stroke()
		# Capsule : rectangle arrondi (rect central + 2 demi-cercles)
		var w := r * 0.55
		var top_y := c.y - r * 0.75
		var bot_y := c.y + r * 0.15
		var h := bot_y - top_y
		var x := c.x - w / 2.0
		# Rectangle plein
		draw_rect(Rect2(x, top_y + w/2.0, w, h - w), color)
		# Demi-cercles haut et bas
		draw_circle(Vector2(c.x, top_y + w/2.0), w/2.0, color)
		draw_circle(Vector2(c.x, bot_y - w/2.0), w/2.0, color)
		# Étrier (arc ouvert vers le haut)
		draw_arc(c + Vector2(0, r * 0.10), r * 0.65,
				deg_to_rad(20), deg_to_rad(160), 18, color, s, true)
		# Pied (trait vertical) + base
		draw_line(c + Vector2(0, r * 0.45), c + Vector2(0, r * 0.85), color, s, true)
		draw_line(c + Vector2(-r * 0.35, r * 0.85),
				c + Vector2( r * 0.35, r * 0.85), color, s, true)

	func _draw_note(c: Vector2, r: float) -> void:
		var s := _stroke()
		# Hampe
		draw_line(c + Vector2(r * 0.10, r * 0.55),
				c + Vector2(r * 0.10, -r * 0.75), color, s, true)
		# Drapeau
		draw_line(c + Vector2(r * 0.10, -r * 0.75),
				c + Vector2(r * 0.70, -r * 0.50), color, s, true)
		# Tête (cercle plein)
		draw_circle(c + Vector2(-r * 0.15, r * 0.55), r * 0.28, color)

	func _draw_screen(c: Vector2, r: float) -> void:
		var s := _stroke()
		var w := r * 1.55
		var h := r * 1.05
		# Écran (rectangle vide)
		draw_rect(Rect2(c.x - w / 2.0, c.y - h / 2.0 - r * 0.10, w, h),
				color, false, s)
		# Petit pied vertical
		draw_line(c + Vector2(0, c.y + h / 2.0 - r * 0.10 - c.y),
				c + Vector2(0, r * 0.85), color, s, true)
		# Base horizontale
		draw_line(c + Vector2(-r * 0.40, r * 0.85),
				c + Vector2( r * 0.40, r * 0.85), color, s, true)

	func _draw_plus(c: Vector2, r: float) -> void:
		var s := _stroke() * 1.1
		var a := r * 0.55
		draw_line(c + Vector2(-a, 0), c + Vector2(a, 0), color, s, true)
		draw_line(c + Vector2(0, -a), c + Vector2(0, a), color, s, true)

	func _draw_minus(c: Vector2, r: float) -> void:
		var s := _stroke() * 1.1
		var a := r * 0.55
		draw_line(c + Vector2(-a, 0), c + Vector2(a, 0), color, s, true)

	func _draw_cross(c: Vector2, r: float) -> void:
		var s := _stroke() * 1.1
		var a := r * 0.50
		draw_line(c + Vector2(-a, -a), c + Vector2(a, a), color, s, true)
		draw_line(c + Vector2(-a, a),  c + Vector2(a, -a), color, s, true)

	func _draw_pencil(c: Vector2, r: float) -> void:
		var s := _stroke()
		# Corps
		var p1 := c + Vector2(-r * 0.55, r * 0.55)
		var p2 := c + Vector2(r * 0.55, -r * 0.55)
		# Trait principal
		draw_line(p1, p2, color, s * 2.0, true)
		# Pointe (triangle)
		var tip := c + Vector2(-r * 0.75, r * 0.75)
		var b1  := c + Vector2(-r * 0.55, r * 0.40)
		var b2  := c + Vector2(-r * 0.40, r * 0.55)
		draw_line(tip, b1, color, s, true)
		draw_line(tip, b2, color, s, true)
		draw_line(b1, b2, color, s, true)

	func _draw_trash(c: Vector2, r: float) -> void:
		var s := _stroke()
		# Couvercle horizontal
		var lid_y := c.y - r * 0.45
		draw_line(Vector2(c.x - r * 0.80, lid_y),
				Vector2(c.x + r * 0.80, lid_y), color, s, true)
		# Anse (petit rectangle au-dessus du couvercle)
		draw_rect(Rect2(c.x - r * 0.25, lid_y - r * 0.22,
				r * 0.50, r * 0.20), color, false, s)
		# Bac trapézoïdal
		var top_l := Vector2(c.x - r * 0.62, lid_y + r * 0.05)
		var top_r := Vector2(c.x + r * 0.62, lid_y + r * 0.05)
		var bot_l := Vector2(c.x - r * 0.48, c.y + r * 0.80)
		var bot_r := Vector2(c.x + r * 0.48, c.y + r * 0.80)
		draw_line(top_l, bot_l, color, s, true)
		draw_line(bot_l, bot_r, color, s, true)
		draw_line(bot_r, top_r, color, s, true)
		# Stries internes (3 lignes verticales)
		for i in 3:
			var x: float = c.x - r * 0.30 + i * r * 0.30
			draw_line(Vector2(x, c.y - r * 0.10),
					Vector2(x, c.y + r * 0.55), color, s * 0.8, true)

	func _draw_divide(c: Vector2, r: float) -> void:
		# ÷ : barre horizontale + 2 points
		var s := _stroke() * 1.1
		var a := r * 0.55
		draw_line(c + Vector2(-a, 0), c + Vector2(a, 0), color, s, true)
		var dot_r := r * 0.12
		draw_circle(c + Vector2(0, -a * 0.70), dot_r, color)
		draw_circle(c + Vector2(0,  a * 0.70), dot_r, color)

	func _draw_multiply(c: Vector2, r: float) -> void:
		# × : croix
		var s := _stroke() * 1.1
		var a := r * 0.45
		draw_line(c + Vector2(-a, -a), c + Vector2(a, a), color, s, true)
		draw_line(c + Vector2(-a, a),  c + Vector2(a, -a), color, s, true)

	func _draw_parens(c: Vector2, r: float) -> void:
		# () : deux arcs de parenthèses
		var s := _stroke() * 1.1
		var h := r * 0.70
		# Parenthèse gauche (
		draw_arc(c + Vector2(-r * 0.15, 0), h, deg_to_rad(130), deg_to_rad(230), 16, color, s, true)
		# Parenthèse droite )
		draw_arc(c + Vector2(r * 0.15, 0), h, deg_to_rad(-50), deg_to_rad(50), 16, color, s, true)
