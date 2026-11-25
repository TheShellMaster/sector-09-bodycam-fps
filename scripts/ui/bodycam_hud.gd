extends CanvasLayer
## Authentic Axon-style Bodycam HUD, Fast Post-Processing Driver,
## Main Menu on First Launch, Live FPS & Objective Distance, Hitmarker,
## Pause/Settings & Multi-Level Selector.

const BodycamShader = preload("res://shaders/bodycam_post.gdshader")
const SettingsPanelScript = preload("res://scripts/ui/settings_panel.gd")

var _post_rect: ColorRect
var _post_mat: ShaderMaterial

var _stamp_label: Label
var _rec_dot: ColorRect
var _event_log_label: Label
var _interact_label: Label
var _mag_label: Label
var _help_panel: PanelContainer
var _crosshair_dot: ColorRect
var _hitmarker_label: Label
var _mission_banner: PanelContainer
var _mission_banner_label: Label
var _pause_menu: PanelContainer
var _settings_panel: PanelContainer
var _pause_title: Label
var _pause_resume_btn: Button
var _death_overlay: PanelContainer

var _event_lines: Array[String] = []
var _mag_timer: float = 0.0
var _hitmarker_timer: float = 0.0
var _shutter_flash: float = 0.0
var _damage_vignette: float = 0.0


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
	GameManager.enemy_hit.connect(_on_enemy_hit)

	_sync_shader_settings()
	_on_event_logged(GameManager.LEVEL_NAMES[GameManager.current_level_index], "INFO")
	_on_event_logged("OBJECTIF: ÉLIMINER HOSTILES & SÉCURISER L'INTEL", "INFO")

	# Open cleanly into the Main Menu on initial game launch (unless --bench mode)
	if GameManager.show_title_on_boot and not OS.get_cmdline_args().has("--bench"):
		GameManager.show_title_on_boot = false
		_pause_title.text = "SECTOR 09 // BODYCAM"
		_pause_resume_btn.text = "▶ JOUER LA MISSION"
		_toggle_pause(true)


func _build_post_processing() -> void:
	_post_rect = ColorRect.new()
	_post_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_post_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_post_mat = ShaderMaterial.new()
	_post_mat.shader = BodycamShader
	_post_rect.material = _post_mat
	add_child(_post_rect)


func _build_bodycam_overlay() -> void:
	# Top-right AXON BODY 4 Timestamp, FPS & Mission Telemetry
	var tr_box := HBoxContainer.new()
	tr_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tr_box.offset_left = -450
	tr_box.offset_top = 18
	tr_box.offset_right = -20
	tr_box.offset_bottom = 120
	tr_box.alignment = BoxContainer.ALIGNMENT_END
	tr_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tr_box)

	_rec_dot = ColorRect.new()
	_rec_dot.custom_minimum_size = Vector2(11, 11)
	_rec_dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_rec_dot.color = Color(0.95, 0.14, 0.12)
	tr_box.add_child(_rec_dot)

	_stamp_label = Label.new()
	_stamp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_stamp_label.add_theme_font_size_override("font_size", 14)
	_stamp_label.add_theme_color_override("font_color", Color(0.94, 0.96, 0.98, 0.94))
	_stamp_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_stamp_label.add_theme_constant_override("shadow_offset_x", 1)
	_stamp_label.add_theme_constant_override("shadow_offset_y", 1)
	tr_box.add_child(_stamp_label)

	# Top-left Event Log
	_event_log_label = Label.new()
	_event_log_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_event_log_label.offset_left = 20
	_event_log_label.offset_top = 18
	_event_log_label.offset_right = 540
	_event_log_label.offset_bottom = 200
	_event_log_label.add_theme_font_size_override("font_size", 13)
	_event_log_label.add_theme_color_override("font_color", Color(0.86, 0.94, 0.88, 0.9))
	_event_log_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_event_log_label.add_theme_constant_override("shadow_offset_x", 1)
	_event_log_label.add_theme_constant_override("shadow_offset_y", 1)
	_event_log_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_event_log_label)

	# Center Interact Prompt
	_interact_label = Label.new()
	_interact_label.set_anchors_preset(Control.PRESET_CENTER)
	_interact_label.offset_left = -240
	_interact_label.offset_top = 68
	_interact_label.offset_right = 240
	_interact_label.offset_bottom = 108
	_interact_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_interact_label.add_theme_font_size_override("font_size", 16)
	_interact_label.add_theme_color_override("font_color", Color(1.0, 0.94, 0.72, 0.96))
	_interact_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	_interact_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_interact_label)

	# Bottom-right Diegetic Magazine Check Toast
	_mag_label = Label.new()
	_mag_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_mag_label.offset_left = -430
	_mag_label.offset_top = -65
	_mag_label.offset_right = -20
	_mag_label.offset_bottom = -22
	_mag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_mag_label.add_theme_font_size_override("font_size", 15)
	_mag_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.78, 0.95))
	_mag_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	_mag_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_mag_label)

	# Subtle tactical center dot (toggle [G])
	_crosshair_dot = ColorRect.new()
	_crosshair_dot.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair_dot.offset_left = -2.0
	_crosshair_dot.offset_top = -2.0
	_crosshair_dot.offset_right = 2.0
	_crosshair_dot.offset_bottom = 2.0
	_crosshair_dot.color = Color(1.0, 1.0, 1.0, 0.65)
	_crosshair_dot.visible = GameManager.show_crosshair
	_crosshair_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_crosshair_dot)

	# Crisp Hitmarker (flashes white on body hit, red on headshot)
	_hitmarker_label = Label.new()
	_hitmarker_label.set_anchors_preset(Control.PRESET_CENTER)
	_hitmarker_label.offset_left = -20
	_hitmarker_label.offset_top = -18
	_hitmarker_label.offset_right = 20
	_hitmarker_label.offset_bottom = 18
	_hitmarker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hitmarker_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hitmarker_label.text = "✕"
	_hitmarker_label.add_theme_font_size_override("font_size", 22)
	_hitmarker_label.visible = false
	_hitmarker_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hitmarker_label)

	# Bottom-left Toggleable Controls Guide ([H])
	_help_panel = PanelContainer.new()
	_help_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_help_panel.offset_left = 18
	_help_panel.offset_top = -148
	_help_panel.offset_right = 415
	_help_panel.offset_bottom = -16
	_help_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = Color(0.04, 0.05, 0.06, 0.56)
	pstyle.set_border_width_all(1)
	pstyle.border_color = Color(0.5, 0.58, 0.62, 0.35)
	pstyle.set_content_margin_all(9)
	_help_panel.add_theme_stylebox_override("panel", pstyle)
	add_child(_help_panel)

	var hlbl := Label.new()
	hlbl.text = "COMMANDES (AZERTY & QWERTY):\n[ZQSD/WASD] Déplacer | [Shift] Sprint | [Ctrl/C] Accroupir\n[A/E] Pencher | [Clic G/D] Tirer / Viser | [X] Semi/Auto\n[R] Recharger | [B] Chargeur | [F] Lampe | [L] Laser\n[N] IR | [T] Météo | [E/V] Interagir | [H] Aide | [ESC] Menu"
	hlbl.add_theme_font_size_override("font_size", 11)
	hlbl.add_theme_color_override("font_color", Color(0.86, 0.92, 0.94, 0.9))
	_help_panel.add_child(hlbl)


func _build_pause_menu() -> void:
	_pause_menu = PanelContainer.new()
	_pause_menu.set_anchors_preset(Control.PRESET_CENTER)
	_pause_menu.offset_left = -280
	_pause_menu.offset_top = -255
	_pause_menu.offset_right = 280
	_pause_menu.offset_bottom = 255
	_pause_menu.visible = false
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.05, 0.06, 0.08, 0.93)
	st.set_border_width_all(2)
	st.border_color = Color(0.32, 0.44, 0.52, 0.85)
	st.set_content_margin_all(20)
	_pause_menu.add_theme_stylebox_override("panel", st)
	add_child(_pause_menu)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 9)
	_pause_menu.add_child(vb)

	_pause_title = Label.new()
	_pause_title.text = "SECTOR 09 // MENU PAUSE"
	_pause_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_title.add_theme_font_size_override("font_size", 22)
	vb.add_child(_pause_title)

	_pause_resume_btn = Button.new()
	_pause_resume_btn.text = "▶ REPRENDRE LA MISSION"
	_pause_resume_btn.custom_minimum_size = Vector2(0, 38)
	_pause_resume_btn.pressed.connect(func():
		_pause_title.text = "SECTOR 09 // MENU PAUSE"
		_pause_resume_btn.text = "▶ REPRENDRE LA MISSION"
		_toggle_pause(false)
	)
	vb.add_child(_pause_resume_btn)

	var lvl_hdr := Label.new()
	lvl_hdr.text = "— CHOISIR UN NIVEAU —"
	lvl_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lvl_hdr.add_theme_font_size_override("font_size", 13)
	vb.add_child(lvl_hdr)

	for i in range(GameManager.LEVEL_NAMES.size()):
		var lb := Button.new()
		lb.text = GameManager.LEVEL_NAMES[i]
		var idx := i
		lb.pressed.connect(func():
			GameManager.show_title_on_boot = false
			GameManager.load_level(idx)
		)
		vb.add_child(lb)

	var set_hdr := Label.new()
	set_hdr.text = "— PARAMÈTRES GRAPHIQUES & BODYCAM —"
	set_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	set_hdr.add_theme_font_size_override("font_size", 13)
	vb.add_child(set_hdr)

	var btn_settings := Button.new()
	btn_settings.text = "⚙ RÉGLAGES DU JEU (Audio / Souris / FOV / Graphismes)"
	btn_settings.pressed.connect(func():
		AudioManager.play_2d("ui_click", -8.0, 0.02)
		_pause_menu.visible = false
		_settings_panel.visible = true
	)
	vb.add_child(btn_settings)

	var btn_weather := Button.new()
	btn_weather.text = "☁ Changer Météo / Heure"
	btn_weather.pressed.connect(func(): GameManager.cycle_weather_preset())
	vb.add_child(btn_weather)

	var btn_menu := Button.new()
	btn_menu.text = "← RETOUR AU MENU PRINCIPAL"
	btn_menu.pressed.connect(func():
		GameManager.set_paused(false)
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
	)
	vb.add_child(btn_menu)

	var btn_quit := Button.new()
	btn_quit.text = "✕ QUITTER LE JEU"
	btn_quit.pressed.connect(func(): get_tree().quit())
	vb.add_child(btn_quit)

	# Embedded full Settings Panel inside Pause Menu
	_settings_panel = PanelContainer.new()
	_settings_panel.set_script(SettingsPanelScript)
	_settings_panel.set_anchors_preset(Control.PRESET_CENTER)
	_settings_panel.offset_left = -300
	_settings_panel.offset_top = -255
	_settings_panel.offset_right = 300
	_settings_panel.offset_bottom = 255
	_settings_panel.visible = false
	_settings_panel.closed.connect(func():
		_settings_panel.visible = false
		_pause_menu.visible = true
	)
	add_child(_settings_panel)


func _build_death_and_victory_overlays() -> void:
	_mission_banner = PanelContainer.new()
	_mission_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_mission_banner.offset_left = -310
	_mission_banner.offset_top = 80
	_mission_banner.offset_right = 310
	_mission_banner.offset_bottom = 185
	_mission_banner.visible = false
	var vst := StyleBoxFlat.new()
	vst.bg_color = Color(0.05, 0.14, 0.08, 0.90)
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
	_mission_banner_label.add_theme_font_size_override("font_size", 16)
	vvb.add_child(_mission_banner_label)
	var btn_next := Button.new()
	btn_next.text = "▶ PASSER AU NIVEAU SUIVANT"
	btn_next.pressed.connect(func(): GameManager.next_level())
	vvb.add_child(btn_next)

	_death_overlay = PanelContainer.new()
	_death_overlay.set_anchors_preset(Control.PRESET_CENTER)
	_death_overlay.offset_left = -240
	_death_overlay.offset_top = -90
	_death_overlay.offset_right = 240
	_death_overlay.offset_bottom = 90
	_death_overlay.visible = false
	var dst := StyleBoxFlat.new()
	dst.bg_color = Color(0.14, 0.02, 0.02, 0.92)
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
	dlbl.add_theme_font_size_override("font_size", 18)
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
	if not paused and is_instance_valid(_settings_panel):
		_settings_panel.visible = false


func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	_rec_dot.visible = fmod(t, 1.2) < 0.65

	var h := int(floor(GameManager.time_of_day)) % 24
	var m := int(floor((GameManager.time_of_day - floor(GameManager.time_of_day)) * 60.0))
	var sec := int(floor(fmod(t, 60.0)))
	var zone_tag := "INT" if GameManager.player_indoors else "EXT"
	var ir_tag := " [IR]" if GameManager.nvg_enabled else ""
	var fps := int(Engine.get_frames_per_second())

	var intel_str := "SÉCURISÉ"
	if not GameManager.intel_secured and is_instance_valid(GameManager.player):
		var dist := int(GameManager.player.global_position.distance_to(GameManager.intel_position))
		intel_str = "%dm" % dist

	_stamp_label.text = "  AXON BODY 4 // REC%s  [%d FPS]\n2026-11-25  %02d:%02d:%02d  [%s]\nUNIT-09  |  BPM %03d  |  HP %03d%%\nHOSTILES: %d/%d  |  INTEL: %s" % [
		ir_tag, fps, h, m, sec, zone_tag,
		int(GameManager.player_bpm),
		int(GameManager.player_health),
		GameManager.hostiles_alive, GameManager.hostiles_total,
		intel_str
	]

	_shutter_flash = maxf(0.0, _shutter_flash - delta * 6.5)
	var hp_ratio := clampf(1.0 - GameManager.player_health / GameManager.player_max_health, 0.0, 1.0)
	_damage_vignette = lerpf(_damage_vignette, hp_ratio, delta * 5.0)

	_post_mat.set_shader_parameter("shutter_flash", _shutter_flash)
	_post_mat.set_shader_parameter("damage_amount", _damage_vignette)

	if _mag_timer > 0.0:
		_mag_timer -= delta
		if _mag_timer <= 0.0:
			_mag_label.text = ""

	if _hitmarker_timer > 0.0:
		_hitmarker_timer -= delta
		if _hitmarker_timer <= 0.0:
			_hitmarker_label.visible = false


func _sync_shader_settings() -> void:
	# Avoid expensive full-screen framebuffer copy unless IR/Fisheye explicitly active
	var need_post: bool = GameManager.nvg_enabled or GameManager.barrel_strength > 0.005
	_post_rect.visible = need_post
	_crosshair_dot.visible = GameManager.show_crosshair
	_post_mat.set_shader_parameter("barrel_strength", GameManager.barrel_strength)
	_post_mat.set_shader_parameter("nvg_amount", 1.0 if GameManager.nvg_enabled else 0.0)


func trigger_shutter_flash(amount: float) -> void:
	_shutter_flash = maxf(_shutter_flash, clampf(amount, 0.0, 1.0))


func _on_enemy_hit(is_headshot: bool) -> void:
	AudioManager.play_2d("hitmarker", -6.0 if is_headshot else -10.0, 0.06)
	_hitmarker_label.visible = true
	_hitmarker_label.add_theme_color_override("font_color", Color(1.0, 0.15, 0.12) if is_headshot else Color(1.0, 1.0, 1.0))
	_hitmarker_timer = 0.18 if is_headshot else 0.12


func _on_event_logged(text: String, level: String) -> void:
	var prefix := "[%s] " % level
	_event_lines.append(prefix + text)
	if _event_lines.size() > 5:
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
