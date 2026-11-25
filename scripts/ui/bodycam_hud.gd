extends CanvasLayer
## Authentic Axon-style Bodycam HUD, Post-Processing Shader Driver,
## Diegetic Tactical Event Log, Pause/Realism Settings & Level Selector Menu.

const BodycamShader = preload("res://shaders/bodycam_post.gdshader")

var _post_rect: ColorRect
var _post_mat: ShaderMaterial

var _stamp_label: Label
var _rec_dot: ColorRect
var _event_log_label: Label
var _interact_label: Label
var _mag_label: Label
var _help_panel: PanelContainer
var _crosshair_dot: ColorRect
var _mission_banner: PanelContainer
var _mission_banner_label: Label
var _pause_menu: PanelContainer
var _death_overlay: PanelContainer

var _event_lines: Array[String] = []
var _mag_timer: float = 0.0
var _shutter_flash: float = 0.0
var _damage_vignette: float = 0.0
var _rain_lens: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	GameManager.hud = self

	_build_post_processing()
	_build_bodycam_overlay()
	_build_pause_menu()
	_build_death_and_victory_overlays()

	GameManager.event_logged.connect(_on_event_logged)
	GameManager.interact_prompt_changed.connect(_on_interact_changed)
	GameManager.mag_status_displayed.connect(_on_mag_status)
	GameManager.player_damaged.connect(_on_player_damaged)
	GameManager.player_died.connect(_on_player_died)
	GameManager.mission_updated.connect(_on_mission_updated)
	GameManager.settings_changed.connect(_sync_shader_settings)

	_sync_shader_settings()
	_on_event_logged(GameManager.LEVEL_NAMES[GameManager.current_level_index], "INFO")
	_on_event_logged("OBJECTIVE: ELIMINATE HOSTILES & SECURE INTEL", "INFO")


func _build_post_processing() -> void:
	_post_rect = ColorRect.new()
	_post_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_post_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_post_mat = ShaderMaterial.new()
	_post_mat.shader = BodycamShader
	_post_rect.material = _post_mat
	add_child(_post_rect)


func _build_bodycam_overlay() -> void:
	# Top-right Authentic AXON BODY 4 Timestamp & Telemetry
	var tr_box := HBoxContainer.new()
	tr_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tr_box.offset_left = -410
	tr_box.offset_top = 20
	tr_box.offset_right = -24
	tr_box.offset_bottom = 110
	tr_box.alignment = BoxContainer.ALIGNMENT_END
	tr_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tr_box)

	_rec_dot = ColorRect.new()
	_rec_dot.custom_minimum_size = Vector2(12, 12)
	_rec_dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_rec_dot.color = Color(0.95, 0.14, 0.12)
	tr_box.add_child(_rec_dot)

	_stamp_label = Label.new()
	_stamp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_stamp_label.add_theme_font_size_override("font_size", 15)
	_stamp_label.add_theme_color_override("font_color", Color(0.94, 0.96, 0.98, 0.92))
	_stamp_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_stamp_label.add_theme_constant_override("shadow_offset_x", 1)
	_stamp_label.add_theme_constant_override("shadow_offset_y", 1)
	tr_box.add_child(_stamp_label)

	# Top-left Event Log & Mission Telemetry
	_event_log_label = Label.new()
	_event_log_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_event_log_label.offset_left = 24
	_event_log_label.offset_top = 20
	_event_log_label.offset_right = 560
	_event_log_label.offset_bottom = 220
	_event_log_label.add_theme_font_size_override("font_size", 14)
	_event_log_label.add_theme_color_override("font_color", Color(0.86, 0.93, 0.88, 0.88))
	_event_log_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_event_log_label.add_theme_constant_override("shadow_offset_x", 1)
	_event_log_label.add_theme_constant_override("shadow_offset_y", 1)
	_event_log_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_event_log_label)

	# Center Interact Prompt
	_interact_label = Label.new()
	_interact_label.set_anchors_preset(Control.PRESET_CENTER)
	_interact_label.offset_left = -240
	_interact_label.offset_top = 75
	_interact_label.offset_right = 240
	_interact_label.offset_bottom = 115
	_interact_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_interact_label.add_theme_font_size_override("font_size", 17)
	_interact_label.add_theme_color_override("font_color", Color(1.0, 0.94, 0.72, 0.96))
	_interact_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	_interact_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_interact_label)

	# Bottom-right Diegetic Magazine Check Toast
	_mag_label = Label.new()
	_mag_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_mag_label.offset_left = -430
	_mag_label.offset_top = -70
	_mag_label.offset_right = -24
	_mag_label.offset_bottom = -28
	_mag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_mag_label.add_theme_font_size_override("font_size", 16)
	_mag_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.78, 0.95))
	_mag_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	_mag_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_mag_label)

	# Optional minimal 3x3px dot crosshair (OFF by default for pure Bodycam realism — toggle [G])
	_crosshair_dot = ColorRect.new()
	_crosshair_dot.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair_dot.offset_left = -1.5
	_crosshair_dot.offset_top = -1.5
	_crosshair_dot.offset_right = 1.5
	_crosshair_dot.offset_bottom = 1.5
	_crosshair_dot.color = Color(1.0, 1.0, 1.0, 0.55)
	_crosshair_dot.visible = GameManager.show_crosshair
	_crosshair_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_crosshair_dot)

	# Bottom-left Toggleable Tactical Controls Guide ([H])
	_help_panel = PanelContainer.new()
	_help_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_help_panel.offset_left = 20
	_help_panel.offset_top = -175
	_help_panel.offset_right = 430
	_help_panel.offset_bottom = -18
	_help_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = Color(0.04, 0.05, 0.06, 0.52)
	pstyle.set_border_width_all(1)
	pstyle.border_color = Color(0.5, 0.58, 0.62, 0.35)
	pstyle.set_content_margin_all(10)
	_help_panel.add_theme_stylebox_override("panel", pstyle)
	add_child(_help_panel)

	var hlbl := Label.new()
	hlbl.text = "COMMANDES TACTIQUES (AZERTY & QWERTY):\n[ZQSD/WASD] Déplacer  |  [Shift] Sprint  |  [Ctrl/C] Accroupir\n[A/E] Pencher  |  [Clic G/D] Tirer / Viser  |  [X] Semi/Auto\n[R] Recharger  |  [B] Chargeur  |  [F] Lampe  |  [L] Laser\n[N] Vision IR  |  [T] Météo  |  [G] Point  |  [H] Aide  |  [ESC] Menu"
	hlbl.add_theme_font_size_override("font_size", 12)
	hlbl.add_theme_color_override("font_color", Color(0.85, 0.9, 0.92, 0.88))
	_help_panel.add_child(hlbl)


func _build_pause_menu() -> void:
	_pause_menu = PanelContainer.new()
	_pause_menu.set_anchors_preset(Control.PRESET_CENTER)
	_pause_menu.offset_left = -290
	_pause_menu.offset_top = -255
	_pause_menu.offset_right = 290
	_pause_menu.offset_bottom = 255
	_pause_menu.visible = false
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.05, 0.06, 0.08, 0.92)
	st.set_border_width_all(2)
	st.border_color = Color(0.32, 0.42, 0.48, 0.85)
	st.set_content_margin_all(22)
	_pause_menu.add_theme_stylebox_override("panel", st)
	add_child(_pause_menu)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	_pause_menu.add_child(vb)

	var title := Label.new()
	title.text = "SECTOR 09 // MENU TACTIQUE & RÉALISME"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	vb.add_child(title)

	# Resume button
	var btn_resume := Button.new()
	btn_resume.text = "▶ REPRENDRE LA MISSION"
	btn_resume.pressed.connect(func(): _toggle_pause(false))
	vb.add_child(btn_resume)

	# Level Selector Section
	var lvl_hdr := Label.new()
	lvl_hdr.text = "— SÉLECTION DU NIVEAU —"
	lvl_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lvl_hdr.add_theme_font_size_override("font_size", 14)
	vb.add_child(lvl_hdr)

	for i in range(GameManager.LEVEL_NAMES.size()):
		var lb := Button.new()
		lb.text = GameManager.LEVEL_NAMES[i]
		var idx := i
		lb.pressed.connect(func():
			GameManager.load_level(idx)
		)
		vb.add_child(lb)

	# Realism Settings Section
	var set_hdr := Label.new()
	set_hdr.text = "— PARAMÈTRES GRAPHIQUES & BODYCAM —"
	set_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	set_hdr.add_theme_font_size_override("font_size", 14)
	vb.add_child(set_hdr)

	# Graphics Preset button
	var btn_gfx := Button.new()
	var update_gfx_txt := func():
		var names := ["PERFORMANCE (SSAO + VolFog)", "HAUT (SSR + SSAO + SSIL + VolFog)", "ULTRA (+ SDFGI Temps Réel)"]
		btn_gfx.text = "Qualité Graphique : " + names[GameManager.graphics_preset]
	update_gfx_txt.call()
	btn_gfx.pressed.connect(func():
		GameManager.graphics_preset = (GameManager.graphics_preset + 1) % 3
		update_gfx_txt.call()
		GameManager.notify_settings_changed()
	)
	vb.add_child(btn_gfx)

	# Weather cycle button
	var btn_weather := Button.new()
	btn_weather.text = "Changer Météo / Heure (Orage / Crépuscule / Brouillard / Aube)"
	btn_weather.pressed.connect(func():
		GameManager.cycle_weather_preset()
	)
	vb.add_child(btn_weather)

	# Fisheye toggle
	var btn_fish := Button.new()
	var update_fish := func():
		btn_fish.text = "Distorsion Objectif Bodycam (Fisheye) : %s" % ("ACTIVE" if GameManager.barrel_strength > 0.01 else "OFF")
	update_fish.call()
	btn_fish.pressed.connect(func():
		GameManager.barrel_strength = 0.0 if GameManager.barrel_strength > 0.01 else 0.115
		update_fish.call()
		GameManager.notify_settings_changed()
	)
	vb.add_child(btn_fish)

	# Quit button
	var btn_quit := Button.new()
	btn_quit.text = "✕ QUITTER LE JEU"
	btn_quit.pressed.connect(func(): get_tree().quit())
	vb.add_child(btn_quit)


func _build_death_and_victory_overlays() -> void:
	# Mission Complete Banner
	_mission_banner = PanelContainer.new()
	_mission_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_mission_banner.offset_left = -310
	_mission_banner.offset_top = 85
	_mission_banner.offset_right = 310
	_mission_banner.offset_bottom = 195
	_mission_banner.visible = false
	var vst := StyleBoxFlat.new()
	vst.bg_color = Color(0.05, 0.14, 0.08, 0.88)
	vst.set_border_width_all(2)
	vst.border_color = Color(0.28, 0.85, 0.45, 0.9)
	vst.set_content_margin_all(14)
	_mission_banner.add_theme_stylebox_override("panel", vst)
	add_child(_mission_banner)

	var vvb := VBoxContainer.new()
	_mission_banner.add_child(vvb)
	_mission_banner_label = Label.new()
	_mission_banner_label.text = "SECTEUR NETTOYÉ // INTEL SÉCURISÉ — MISSION ACCOMPLIE"
	_mission_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mission_banner_label.add_theme_font_size_override("font_size", 17)
	vvb.add_child(_mission_banner_label)
	var btn_next := Button.new()
	btn_next.text = "▶ PASSER AU NIVEAU SUIVANT"
	btn_next.pressed.connect(func(): GameManager.next_level())
	vvb.add_child(btn_next)

	# Officer Down Overlay
	_death_overlay = PanelContainer.new()
	_death_overlay.set_anchors_preset(Control.PRESET_CENTER)
	_death_overlay.offset_left = -240
	_death_overlay.offset_top = -95
	_death_overlay.offset_right = 240
	_death_overlay.offset_bottom = 95
	_death_overlay.visible = false
	var dst := StyleBoxFlat.new()
	dst.bg_color = Color(0.14, 0.02, 0.02, 0.9)
	dst.set_border_width_all(2)
	dst.border_color = Color(0.85, 0.18, 0.16, 0.9)
	dst.set_content_margin_all(18)
	_death_overlay.add_theme_stylebox_override("panel", dst)
	add_child(_death_overlay)

	var dvb := VBoxContainer.new()
	dvb.add_theme_constant_override("separation", 12)
	_death_overlay.add_child(dvb)
	var dlbl := Label.new()
	dlbl.text = "OFFICER DOWN // BODYCAM SIGNAL LOST"
	dlbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dlbl.add_theme_font_size_override("font_size", 19)
	dvb.add_child(dlbl)
	var btn_retry := Button.new()
	btn_retry.text = "↻ RECOMMENCER LE NIVEAU"
	btn_retry.pressed.connect(func(): GameManager.load_level(GameManager.current_level_index))
	dvb.add_child(btn_retry)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if GameManager.player_health > 0.0:
			_toggle_pause(not GameManager.is_paused)
	elif event.is_action_pressed("toggle_help"):
		GameManager.show_help_hints = not GameManager.show_help_hints
		_help_panel.visible = GameManager.show_help_hints
	elif event.is_action_pressed("toggle_crosshair"):
		GameManager.show_crosshair = not GameManager.show_crosshair
		_crosshair_dot.visible = GameManager.show_crosshair


func _toggle_pause(paused: bool) -> void:
	GameManager.set_paused(paused)
	_pause_menu.visible = paused


func _process(delta: float) -> void:
	# Blinking REC LED
	var t := Time.get_ticks_msec() * 0.001
	_rec_dot.visible = fmod(t, 1.2) < 0.65

	# Authentic Axon Body 4 live clock & telemetry
	var h := int(floor(GameManager.time_of_day)) % 24
	var m := int(floor((GameManager.time_of_day - floor(GameManager.time_of_day)) * 60.0))
	var sec := int(floor(fmod(t, 60.0)))
	var zone_tag := "INT" if GameManager.player_indoors else "EXT"
	var ir_tag := " [IR-NVG]" if GameManager.nvg_enabled else ""
	_stamp_label.text = "  AXON BODY 4 // REC%s\n2026-11-25  %02d:%02d:%02d  [%s]\nUNIT-09  |  BPM %03d  |  HP %03d%%\nHOSTILES: %d/%d  |  INTEL: %s" % [
		ir_tag, h, m, sec, zone_tag,
		int(GameManager.player_bpm),
		int(GameManager.player_health),
		GameManager.hostiles_alive, GameManager.hostiles_total,
		"OK" if GameManager.intel_secured else "PENDING"
	]

	# Shader dynamic effects
	_shutter_flash = maxf(0.0, _shutter_flash - delta * 6.5)
	var hp_ratio := clampf(1.0 - GameManager.player_health / GameManager.player_max_health, 0.0, 1.0)
	_damage_vignette = lerpf(_damage_vignette, hp_ratio, delta * 5.0)

	var target_rain := 0.85 if (GameManager.weather_preset == GameManager.WeatherPreset.RAIN_STORM and not GameManager.player_indoors) else 0.0
	_rain_lens = lerpf(_rain_lens, target_rain, delta * 1.8)

	_post_mat.set_shader_parameter("shutter_flash", _shutter_flash)
	_post_mat.set_shader_parameter("damage_amount", _damage_vignette)
	_post_mat.set_shader_parameter("rain_lens_amount", _rain_lens)

	if _mag_timer > 0.0:
		_mag_timer -= delta
		if _mag_timer <= 0.0:
			_mag_label.text = ""


func _sync_shader_settings() -> void:
	_post_mat.set_shader_parameter("barrel_strength", GameManager.barrel_strength)
	_post_mat.set_shader_parameter("nvg_amount", 1.0 if GameManager.nvg_enabled else 0.0)


func trigger_shutter_flash(amount: float) -> void:
	_shutter_flash = maxf(_shutter_flash, clampf(amount, 0.0, 1.0))


func _on_event_logged(text: String, level: String) -> void:
	var prefix := "[%s] " % level
	_event_lines.append(prefix + text)
	if _event_lines.size() > 6:
		_event_lines.pop_front()
	_event_log_label.text = "\n".join(_event_lines)


func _on_interact_changed(prompt: String) -> void:
	_interact_label.text = prompt


func _on_mag_status(status_text: String) -> void:
	_mag_label.text = status_text
	_mag_timer = 3.2


func _on_player_damaged(_hp: float, _max_hp: float) -> void:
	_damage_vignette = minf(1.0, _damage_vignette + 0.55)


func _on_player_died() -> void:
	_death_overlay.visible = true


func _on_mission_updated() -> void:
	if GameManager.mission_completed:
		_mission_banner.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
