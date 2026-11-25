extends PanelContainer
## Reusable Full Game Settings Panel (Audio, Controls, Graphics, Display, Bodycam)
## Used seamlessly in BOTH the Main Menu and the in-game Pause Menu!

signal closed()


func _ready() -> void:
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.05, 0.06, 0.08, 0.96)
	st.set_border_width_all(2)
	st.border_color = Color(0.32, 0.46, 0.56, 0.9)
	st.corner_radius_top_left = 6
	st.corner_radius_top_right = 6
	st.corner_radius_bottom_left = 6
	st.corner_radius_bottom_right = 6
	st.set_content_margin_all(22)
	add_theme_stylebox_override("panel", st)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(540, 440)
	add_child(scroll)

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 10)
	scroll.add_child(vb)

	var title := Label.new()
	title.text = "⚙ RÉGLAGES DU JEU"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	vb.add_child(title)

	# ---- AUDIO ----
	_add_section(vb, "AUDIO")
	_add_slider_row(vb, "Volume Principal", 0.0, 100.0, 1.0, GameManager.master_volume * 100.0, "%d%%", func(v: float):
		GameManager.master_volume = v / 100.0
		GameManager.apply_audio_and_display_settings()
	)
	_add_slider_row(vb, "Volume Ambiance (Pluie / Vent)", 0.0, 100.0, 1.0, GameManager.ambience_volume * 100.0, "%d%%", func(v: float):
		GameManager.ambience_volume = v / 100.0
		GameManager.apply_audio_and_display_settings()
	)

	# ---- CONTROLES ----
	_add_section(vb, "CONTRÔLES & CAMÉRA")
	_add_slider_row(vb, "Sensibilité Souris", 0.4, 3.0, 0.05, GameManager.mouse_sensitivity / 0.0022, "%.2fx", func(v: float):
		GameManager.mouse_sensitivity = v * 0.0022
		GameManager.save_settings()
	)
	_add_slider_row(vb, "Champ de Vision (FOV)", 65.0, 105.0, 1.0, GameManager.base_fov, "%d°", func(v: float):
		GameManager.base_fov = v
		GameManager.notify_settings_changed()
		GameManager.save_settings()
	)
	_add_toggle_row(vb, "Inverser Axe Y (Souris)", GameManager.invert_y, func(on: bool):
		GameManager.invert_y = on
		GameManager.save_settings()
	)
	_add_toggle_row(vb, "Réticule Central", GameManager.show_crosshair, func(on: bool):
		GameManager.show_crosshair = on
		GameManager.notify_settings_changed()
		GameManager.save_settings()
	)

	# ---- AFFICHAGE & GRAPHIQUES ----
	_add_section(vb, "AFFICHAGE & GRAPHIQUES")

	var gfx_row := HBoxContainer.new()
	vb.add_child(gfx_row)
	var gfx_lbl := Label.new()
	gfx_lbl.text = "Qualité Graphique"
	gfx_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gfx_row.add_child(gfx_lbl)
	var gfx_opt := OptionButton.new()
	gfx_opt.add_item("Performance (Ultra Fluide)")
	gfx_opt.add_item("Équilibré (Recommandé)")
	gfx_opt.add_item("Haut (Ombres + Bloom)")
	gfx_opt.selected = GameManager.graphics_preset
	gfx_opt.item_selected.connect(func(idx: int):
		GameManager.graphics_preset = idx
		GameManager.notify_settings_changed()
		GameManager.save_settings()
	)
	gfx_row.add_child(gfx_opt)

	_add_slider_row(vb, "Effet Objectif Bodycam (Fisheye)", 0.0, 100.0, 5.0, GameManager.barrel_strength / 0.14 * 100.0, "%d%%", func(v: float):
		GameManager.barrel_strength = (v / 100.0) * 0.14
		GameManager.notify_settings_changed()
		GameManager.save_settings()
	)
	_add_toggle_row(vb, "Mode Plein Écran", GameManager.fullscreen, func(on: bool):
		GameManager.fullscreen = on
		GameManager.apply_audio_and_display_settings()
		GameManager.save_settings()
	)
	_add_toggle_row(vb, "Synchronisation Verticale (V-Sync)", GameManager.vsync_enabled, func(on: bool):
		GameManager.vsync_enabled = on
		GameManager.apply_audio_and_display_settings()
		GameManager.save_settings()
	)

	# Close button
	var sep := HSeparator.new()
	vb.add_child(sep)
	var btn_close := Button.new()
	btn_close.text = "✓ ENREGISTRER & FERMER"
	btn_close.custom_minimum_size = Vector2(0, 38)
	btn_close.pressed.connect(func():
		AudioManager.play_2d("ui_click", -8.0, 0.02)
		GameManager.save_settings()
		closed.emit()
	)
	vb.add_child(btn_close)


func _add_section(parent: VBoxContainer, text: String) -> void:
	var l := Label.new()
	l.text = "— " + text + " —"
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.55, 0.78, 0.92))
	parent.add_child(l)


func _add_slider_row(parent: VBoxContainer, label_txt: String, min_v: float, max_v: float, step_v: float, init_v: float, fmt: String, cb: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = label_txt
	lbl.custom_minimum_size = Vector2(240, 0)
	row.add_child(lbl)

	var sl := HSlider.new()
	sl.min_value = min_v
	sl.max_value = max_v
	sl.step = step_v
	sl.value = init_v
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sl)

	var val_lbl := Label.new()
	val_lbl.custom_minimum_size = Vector2(64, 0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.text = fmt % init_v
	row.add_child(val_lbl)

	sl.value_changed.connect(func(val: float):
		val_lbl.text = fmt % val
		cb.call(val)
	)


func _add_toggle_row(parent: VBoxContainer, label_txt: String, init_val: bool, cb: Callable) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = label_txt
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)

	var chk := CheckButton.new()
	chk.button_pressed = init_val
	chk.toggled.connect(func(on: bool):
		AudioManager.play_2d("ui_click", -10.0, 0.03)
		cb.call(on)
	)
	row.add_child(chk)
