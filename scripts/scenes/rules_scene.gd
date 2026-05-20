extends Control
# ============================================================
# RULES — Page d'aide / règles du jeu.
# Header fixe + flèche retour, icônes vectorielles, bordures.
# ============================================================

const RULES_DATA := [
	{
		"title": "But du jeu",
		"icon":  "target",
		"body":  "Calcul Mental est un entraînement au calcul mental qui propose 5 modes différents. Chaque mode mesure ta rapidité et ta précision pour calculer un score, sauvegardé dans ton profil."
	},
	{
		"title": "Mode 1 — Contre-la-montre",
		"icon":  "clock",
		"body":  "Tu as un temps limité (par défaut 60 s) pour résoudre un maximum de calculs corrects. Le timer descend en haut de l'écran. À zéro, la session se termine."
	},
	{
		"title": "Mode 2 — Série chronométrée",
		"icon":  "hourglass",
		"body":  "Tu dois résoudre un nombre fixe de calculs (par défaut 20). Le timer mesure le temps total. Objectif : terminer vite avec un maximum de bonnes réponses."
	},
	{
		"title": "Mode 3 — Flash Anzan",
		"icon":  "flash",
		"body":  "Une suite de nombres est affichée un à un (avec un bip). Tu dois mémoriser leur somme. Plus le niveau augmente, plus la vitesse est rapide. À la fin de la série, tu saisis la somme."
	},
	{
		"title": "Mode 4 — Mode audio",
		"icon":  "mic",
		"body":  "Le calcul est lu par synthèse vocale. Tu réponds vocalement en appuyant sur le bouton micro 🎤. Le jeu reconnaît automatiquement le nombre. Option « masquer le calcul » disponible pour un vrai entraînement auditif."
	},
	{
		"title": "Mode 5 — Calcul Infernal (n-back)",
		"icon":  "brain",
		"body":  "Les calculs défilent automatiquement. Tu réponds au calcul d'il y a N tours (par défaut 2). Mode très exigeant en mémoire de travail. Le tempo est réglable (Lent / Moyen / Rapide)."
	},
	{
		"title": "Comment jouer",
		"icon":  "gamepad",
		"body":  "Saisis ta réponse avec le clavier numérique tactile au bas de l'écran. Appuie sur ✓ ou Entrée pour valider. Le bouton ‖ met le jeu en pause. Tu peux activer la voix pour entendre le calcul (touche Q pour répéter)."
	},
	{
		"title": "Options utiles",
		"icon":  "gear",
		"body":  "Dans Options, tu peux choisir les opérations (+ − × ÷), la taille des nombres (unités → centaines de milliers), les contraintes (résultat positif, division entière, sans retenue…), la voix, la musique, et créer plusieurs profils avec leurs propres réglages."
	},
	{
		"title": "Conseils d'entraînement",
		"icon":  "bulb",
		"body":  "Commence par des calculs simples (additions à 2 chiffres) pour gagner en vitesse. Augmente la difficulté progressivement. Le mode Flash Anzan développe la mémoire de travail ; le mode Audio renforce le calcul sans support visuel. Joue régulièrement pour suivre ta progression dans Scores."
	},
]

# Fond animé
var _symbols: Array = []
const SYMBOLS_TEXT := ["1","2","3","4","5","6","7","8","9","+","−","×","÷","="]
var _scroll: ScrollContainer
var _scroll_velocity: float = 0.0
var _is_touching: bool = false
var _touch_history: Array = []

func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	_build_ui()
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
	# Scroll inertie
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
	header.anchor_bottom = 0.0
	header.offset_bottom = hdr_h
	add_child(header)

	# Bouton retour ←
	var back := Button.new()
	back.text = "‹"
	var bsz := ThemeManager.scaled_i(56)
	back.custom_minimum_size = Vector2(bsz, bsz)
	back.anchor_left = 0.0; back.anchor_top = 0.0
	back.offset_left = pad
	back.offset_top = (hdr_h - bsz) / 2
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
	title.text = "Règles du jeu"
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
	_scroll.offset_top    = hdr_h
	_scroll.offset_left   = pad
	_scroll.offset_right  = -pad
	_scroll.offset_bottom = 0
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation",
			ThemeManager.scaled_i(ThemeManager.SECTION_GAP))
	_scroll.add_child(vb)

	for section in RULES_DATA:
		_add_section(vb, section.title, section.body, section.icon)

	# Spacer en bas
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, ThemeManager.scaled_i(20))
	vb.add_child(spacer)

# ── Section : carte avec icône + titre + corps ──────────────
func _add_section(parent: Node, stitle: String, body: String, icon_name: String) -> void:
	var card := PanelContainer.new()
	var cpad := ThemeManager.scaled_i(ThemeManager.PADDING_CARD)
	card.add_theme_stylebox_override("panel",
			ThemeManager.sbox(ThemeManager.SURFACE,
					ThemeManager.scaled_i(ThemeManager.RADIUS_CARD),
					cpad, cpad, cpad, cpad,
					ThemeManager.BORDER_2, 2))
	parent.add_child(card)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",
			ThemeManager.scaled_i(ThemeManager.SPACING_MD))
	card.add_child(row)

	# Icône circulaire à gauche
	var icon_sz := ThemeManager.scaled_i(54)
	var icon_wrap := PanelContainer.new()
	icon_wrap.custom_minimum_size = Vector2(icon_sz, icon_sz)
	icon_wrap.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var bg := Color(ThemeManager.ACCENT.r, ThemeManager.ACCENT.g,
			ThemeManager.ACCENT.b, 0.15)
	icon_wrap.add_theme_stylebox_override("panel",
			ThemeManager.sbox(bg, ThemeManager.scaled_i(27), 0, 0, 0, 0,
					ThemeManager.ACCENT, 2))
	row.add_child(icon_wrap)

	var icon_draw := _RulesIconDrawer.new()
	icon_draw.icon_name = icon_name
	icon_draw.color = ThemeManager.ACCENT
	icon_draw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	icon_draw.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	icon_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_wrap.add_child(icon_draw)

	# Texte (titre + corps)
	var text_vb := VBoxContainer.new()
	text_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_vb.add_theme_constant_override("separation",
			ThemeManager.scaled_i(ThemeManager.SPACING_SM))
	row.add_child(text_vb)

	var lbl_title := Label.new()
	lbl_title.text = stitle
	lbl_title.add_theme_color_override("font_color", ThemeManager.ACCENT)
	lbl_title.add_theme_font_size_override("font_size",
			ThemeManager.scaled_i(ThemeManager.FONT_MED))
	lbl_title.add_theme_font_override("font", ThemeDB.fallback_font)
	text_vb.add_child(lbl_title)

	var lbl_body := Label.new()
	lbl_body.text = body
	lbl_body.add_theme_color_override("font_color", ThemeManager.TEXT_DIM)
	lbl_body.add_theme_font_size_override("font_size",
			ThemeManager.scaled_i(ThemeManager.FONT_SMALL))
	lbl_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_vb.add_child(lbl_body)

# ── Input ───────────────────────────────────────────────────
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
# Classe interne : icônes vectorielles pour les règles
# ════════════════════════════════════════════════════════════
class _RulesIconDrawer extends Control:
	var icon_name: String = ""
	var color: Color = Color.WHITE

	func _ready() -> void:
		resized.connect(queue_redraw)
		queue_redraw()

	func _draw() -> void:
		var sz := size
		if sz.x <= 0 or sz.y <= 0: return
		var c := Vector2(sz.x / 2.0, sz.y / 2.0)
		var r: float = minf(sz.x, sz.y) / 2.0

		match icon_name:
			"target":    _draw_target(c, r)
			"clock":     _draw_clock(c, r)
			"hourglass": _draw_hourglass(c, r)
			"flash":     _draw_flash(c, r)
			"mic":       _draw_mic(c, r)
			"brain":     _draw_brain(c, r)
			"gamepad":   _draw_gamepad(c, r)
			"gear":      _draw_gear(c, r)
			"bulb":      _draw_bulb(c, r)

	func _stroke() -> float:
		return maxf(1.6, size.x * 0.06)

	# ── Target (cible) ─────────────────────────────────────
	func _draw_target(c: Vector2, r: float) -> void:
		var s := _stroke()
		draw_arc(c, r * 0.80, 0, TAU, 32, color, s, true)
		draw_arc(c, r * 0.50, 0, TAU, 24, color, s, true)
		draw_circle(c, r * 0.18, color)
		# Croix
		draw_line(c + Vector2(0, -r * 0.92), c + Vector2(0, r * 0.92), color, s * 0.7, true)
		draw_line(c + Vector2(-r * 0.92, 0), c + Vector2(r * 0.92, 0), color, s * 0.7, true)

	# ── Clock (chrono) ─────────────────────────────────────
	func _draw_clock(c: Vector2, r: float) -> void:
		var s := _stroke()
		draw_arc(c, r * 0.80, 0, TAU, 32, color, s, true)
		draw_line(c, c + Vector2(0, -r * 0.50), color, s, true)
		draw_line(c, c + Vector2(r * 0.38, 0), color, s, true)
		# Bouton du haut
		draw_line(c + Vector2(-r * 0.18, -r * 0.88),
				c + Vector2(r * 0.18, -r * 0.88), color, s, true)

	# ── Hourglass (sablier) ────────────────────────────────
	func _draw_hourglass(c: Vector2, r: float) -> void:
		var s := _stroke()
		var h := r * 0.85
		var w := r * 0.55
		# Barres haut et bas
		draw_line(c + Vector2(-w, -h), c + Vector2(w, -h), color, s * 1.2, true)
		draw_line(c + Vector2(-w,  h), c + Vector2(w,  h), color, s * 1.2, true)
		# Diagonales (forme X)
		draw_line(c + Vector2(-w * 0.85, -h + s), c + Vector2(0, 0), color, s, true)
		draw_line(c + Vector2( w * 0.85, -h + s), c + Vector2(0, 0), color, s, true)
		draw_line(c + Vector2(-w * 0.85,  h - s), c + Vector2(0, 0), color, s, true)
		draw_line(c + Vector2( w * 0.85,  h - s), c + Vector2(0, 0), color, s, true)
		# Sable (petit triangle en bas)
		var sand := PackedVector2Array([
			c + Vector2(-w * 0.40, h - s),
			c + Vector2( w * 0.40, h - s),
			c + Vector2(0, h * 0.15),
		])
		draw_colored_polygon(sand, Color(color.r, color.g, color.b, 0.3))

	# ── Flash (éclair) ─────────────────────────────────────
	func _draw_flash(c: Vector2, r: float) -> void:
		var pts := PackedVector2Array([
			c + Vector2( r * 0.10, -r * 0.85),
			c + Vector2(-r * 0.30, -r * 0.05),
			c + Vector2( r * 0.08, -r * 0.05),
			c + Vector2(-r * 0.15,  r * 0.85),
			c + Vector2( r * 0.35,  r * 0.05),
			c + Vector2(-r * 0.05,  r * 0.05),
		])
		draw_colored_polygon(pts, color)

	# ── Mic (microphone) ───────────────────────────────────
	func _draw_mic(c: Vector2, r: float) -> void:
		var s := _stroke()
		var w := r * 0.45
		var top_y := c.y - r * 0.70
		var bot_y := c.y + r * 0.10
		draw_rect(Rect2(c.x - w / 2.0, top_y + w / 2.0, w, bot_y - top_y - w), color)
		draw_circle(Vector2(c.x, top_y + w / 2.0), w / 2.0, color)
		draw_circle(Vector2(c.x, bot_y - w / 2.0 + w), w / 2.0, color)
		draw_arc(c + Vector2(0, r * 0.10), r * 0.55,
				deg_to_rad(20), deg_to_rad(160), 16, color, s, true)
		draw_line(c + Vector2(0, r * 0.45), c + Vector2(0, r * 0.80), color, s, true)
		draw_line(c + Vector2(-r * 0.30, r * 0.80),
				c + Vector2( r * 0.30, r * 0.80), color, s, true)

	# ── Brain (cerveau / n-back) ───────────────────────────
	func _draw_brain(c: Vector2, r: float) -> void:
		var s := _stroke()
		# Cercle + lettre "n" à l'intérieur
		draw_arc(c, r * 0.80, 0, TAU, 32, color, s, true)
		var f := ThemeDB.fallback_font
		var fs := int(r * 1.0)
		draw_string(f, c + Vector2(-r * 0.28, r * 0.35), "n",
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)

	# ── Gamepad (clavier / comment jouer) ──────────────────
	func _draw_gamepad(c: Vector2, r: float) -> void:
		var s := _stroke()
		var w := r * 1.50
		var h := r * 1.0
		var x := c.x - w / 2.0
		var y := c.y - h / 2.0
		draw_rect(Rect2(x, y, w, h), color, false, s)
		# Grille 3×2 de touches
		var cols := 3; var rows := 2
		var cw := w / cols; var ch := h / rows
		for i in rows:
			for j in cols:
				var kx := x + j * cw + cw * 0.15
				var ky := y + i * ch + ch * 0.15
				var kw := cw * 0.70; var kh := ch * 0.70
				draw_rect(Rect2(kx, ky, kw, kh), color, false, s * 0.7)

	# ── Gear (engrenage / options) ─────────────────────────
	func _draw_gear(c: Vector2, r: float) -> void:
		var s := _stroke()
		var inner := r * 0.35
		var outer := r * 0.70
		draw_arc(c, inner, 0, TAU, 24, color, s, true)
		var teeth := 8
		for i in teeth:
			var angle := TAU * i / teeth
			var p1 := c + Vector2(cos(angle), sin(angle)) * (inner + s)
			var p2 := c + Vector2(cos(angle), sin(angle)) * outer
			draw_line(p1, p2, color, s * 1.8, true)
		draw_arc(c, outer * 0.82, 0, TAU, 32, color, s * 0.8, true)

	# ── Bulb (ampoule / conseils) ──────────────────────────
	func _draw_bulb(c: Vector2, r: float) -> void:
		var s := _stroke()
		# Ampoule (cercle + col)
		var bulb_r := r * 0.55
		draw_arc(c + Vector2(0, -r * 0.15), bulb_r, 0, TAU, 32, color, s, true)
		# Col
		var col_w := r * 0.30
		var col_top := c.y + bulb_r * 0.55
		var col_bot := c.y + r * 0.70
		draw_line(c + Vector2(-col_w, col_top), c + Vector2(-col_w, col_bot), color, s, true)
		draw_line(c + Vector2( col_w, col_top), c + Vector2( col_w, col_bot), color, s, true)
		# Lignes horizontales du col
		draw_line(c + Vector2(-col_w, col_bot), c + Vector2(col_w, col_bot), color, s, true)
		draw_line(c + Vector2(-col_w * 0.8, col_bot - r * 0.12),
				c + Vector2( col_w * 0.8, col_bot - r * 0.12), color, s * 0.7, true)
		# Rayons
		for i in 4:
			var angle := -PI / 2 + PI * 0.25 * (i - 1.5)
			var p1 := c + Vector2(0, -r * 0.15) + Vector2(cos(angle), sin(angle)) * (bulb_r + s * 2)
			var p2 := c + Vector2(0, -r * 0.15) + Vector2(cos(angle), sin(angle)) * (bulb_r + r * 0.22)
			draw_line(p1, p2, color, s * 0.8, true)
