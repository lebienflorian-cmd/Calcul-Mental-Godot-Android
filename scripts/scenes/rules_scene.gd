extends Control
# ============================================================
# RULES — Page d'aide / règles du jeu.
# ============================================================

const RULES_TEXT := [
	{
		"title": "But du jeu",
		"body": "Calcul Mental est un entraînement au calcul mental qui propose 5 modes différents. Chaque mode mesure ta rapidité et ta précision pour calculer un score, sauvegardé dans ton profil."
	},
	{
		"title": "Mode 1 — Contre-la-montre",
		"body": "Tu as un temps limité (par défaut 60 s) pour résoudre un maximum de calculs corrects. Le timer descend en haut de l'écran. À zéro, la session se termine."
	},
	{
		"title": "Mode 2 — Série chronométrée",
		"body": "Tu dois résoudre un nombre fixe de calculs (par défaut 20). Le timer mesure le temps total. Objectif : terminer vite avec un maximum de bonnes réponses."
	},
	{
		"title": "Mode 3 — Flash Anzan",
		"body": "Une suite de nombres est affichée un à un (avec un bip). Tu dois mémoriser leur somme. Plus le niveau augmente, plus la vitesse est rapide. À la fin de la série, tu saisis la somme."
	},
	{
		"title": "Mode 4 — Mode audio",
		"body": "Le calcul est lu par synthèse vocale. Tu réponds vocalement en appuyant sur le bouton micro 🎤. Le jeu reconnaît automatiquement le nombre. Option « masquer le calcul » disponible pour un vrai entraînement auditif."
	},
	{
		"title": "Mode 5 — Calcul Infernal (n-back)",
		"body": "Les calculs défilent automatiquement. Tu réponds au calcul d'il y a N tours (par défaut 2). Mode très exigeant en mémoire de travail. Le tempo est réglable (Lent / Moyen / Rapide)."
	},
	{
		"title": "Comment jouer",
		"body": "Saisis ta réponse avec le clavier numérique tactile au bas de l'écran. Appuie sur ✓ ou Entrée pour valider. Le bouton ‖ met le jeu en pause. Tu peux activer la voix pour entendre le calcul (touche Q pour répéter)."
	},
	{
		"title": "Options utiles",
		"body": "Dans Options, tu peux choisir les opérations (+ − × ÷), la taille des nombres (unités → centaines de milliers), les contraintes (résultat positif, division entière, sans retenue…), la voix, la musique, et créer plusieurs profils avec leurs propres réglages."
	},
	{
		"title": "Conseils d'entraînement",
		"body": "Commence par des calculs simples (additions à 2 chiffres) pour gagner en vitesse. Augmente la difficulté progressivement. Le mode Flash Anzan développe la mémoire de travail ; le mode Audio renforce le calcul sans support visuel. Joue régulièrement pour suivre ta progression dans Scores."
	},
]

var _scroll: ScrollContainer

func _ready() -> void:
	_build_ui()

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = ThemeManager.BG
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	add_child(bg)

	var title := Label.new()
	title.text = "📖  Règles du jeu"
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

	for section in RULES_TEXT:
		_add_section(vb, section.title, section.body)

	# Bouton retour
	var back := Button.new()
	back.text = "← Retour"
	back.custom_minimum_size = Vector2(180, 60)
	back.anchor_left = 1.0
	back.anchor_right = 1.0
	back.anchor_top = 1.0
	back.anchor_bottom = 1.0
	back.offset_left = -200
	back.offset_top = -76
	back.offset_right = -20
	back.offset_bottom = -16
	back.add_theme_color_override("font_color", ThemeManager.TEXT)
	back.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_MED))
	back.add_theme_stylebox_override("normal", ThemeManager.make_button_style(ThemeManager.SURFACE_2, 10))
	back.add_theme_stylebox_override("hover",  ThemeManager.make_button_style(ThemeManager.BORDER, 10))
	back.pressed.connect(func():
		AudioManager.play_sfx("back")
		SceneRouter.goto("res://scenes/MainMenu.tscn")
	)
	add_child(back)

func _add_section(parent: Node, title: String, body: String) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", ThemeManager.make_panel_style(ThemeManager.SURFACE, 12))
	parent.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)

	var lbl_title := Label.new()
	lbl_title.text = title
	lbl_title.add_theme_color_override("font_color", ThemeManager.ACCENT)
	lbl_title.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_MED))
	vb.add_child(lbl_title)

	var lbl_body := Label.new()
	lbl_body.text = body
	lbl_body.add_theme_color_override("font_color", ThemeManager.TEXT_DIM)
	lbl_body.add_theme_font_size_override("font_size", ThemeManager.scaled_i(ThemeManager.FONT_SMALL))
	lbl_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(lbl_body)

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
