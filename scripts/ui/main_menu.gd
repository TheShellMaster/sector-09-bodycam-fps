extends Node3D
## Dedicated Welcome Screen / Main Menu with live animated 3D background diorama,
## Level Selection Cards, Full Game Settings Panel, and Controls Overview.

const SettingsPanelScript = preload("res://scripts/ui/settings_panel.gd")

var _cam_pivot: Node3D
var _main_panel: PanelContainer
var _levels_panel: PanelContainer
var _controls_panel: PanelContainer
var _settings_panel: PanelContainer
var _lamp_light: OmniLight3D


func _ready() -> void:
	# Allow --bench flag to jump straight into gameplay benchmark
	if OS.get_cmdline_args().has("--bench"):
		get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
		return

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	GameManager.is_paused = false
	GameManager.show_title_on_boot = false
	GameManager.apply_audio_and_display_settings()

	_build_3d_backdrop()
	_build_ui()


func _build_3d_backdrop() -> void:
	# Atmospheric low-cost 3D tactical courtyard backdrop
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var smat := ProceduralSkyMaterial.new()
	smat.sky_top_color = Color(0.03, 0.05, 0.08)
	smat.sky_horizon_color = Color(0.11, 0.15, 0.21)
	smat.ground_bottom_color = Color(0.02, 0.03, 0.04)
	smat.ground_horizon_color = Color(0.08, 0.10, 0.13)
	sky.sky_material = smat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.28, 0.34, 0.42)
	env.ambient_light_energy = 0.55
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = 0.042
	env.fog_light_color = Color(0.10, 0.14, 0.19)
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 32, 0)
	sun.light_color = Color(0.65, 0.76, 0.95)
	sun.light_energy = 0.65
	add_child(sun)

	# Wet asphalt floor
	var floor_mat := StandardMaterial3D.new()
	if ResourceLoader.exists("res://assets/textures/asphalt_wet_albedo.png"):
		floor_mat.albedo_texture = load("res://assets/textures/asphalt_wet_albedo.png")
		floor_mat.normal_enabled = true
		floor_mat.normal_texture = load("res://assets/textures/asphalt_wet_normal.png")
		floor_mat.roughness_texture = load("res://assets/textures/asphalt_wet_roughness.png")
		floor_mat.uv1_scale = Vector3(12, 12, 1)
	floor_mat.roughness = 0.52
	_add_mesh(Vector3(38, 0.2, 38), Vector3(0, -0.1, 0), floor_mat)

	# Industrial concrete walls & containers silhouette
	var conc_mat := StandardMaterial3D.new()
	if ResourceLoader.exists("res://assets/textures/concrete_wall_albedo.png"):
		conc_mat.albedo_texture = load("res://assets/textures/concrete_wall_albedo.png")
		conc_mat.normal_enabled = true
		conc_mat.normal_texture = load("res://assets/textures/concrete_wall_normal.png")
		conc_mat.uv1_scale = Vector3(4, 2, 1)
	var metal_mat := StandardMaterial3D.new()
	if ResourceLoader.exists("res://assets/textures/rusty_metal_albedo.png"):
		metal_mat.albedo_texture = load("res://assets/textures/rusty_metal_albedo.png")
		metal_mat.normal_enabled = true
		metal_mat.normal_texture = load("res://assets/textures/rusty_metal_normal.png")
		metal_mat.metallic = 0.65
		metal_mat.albedo_color = Color(0.45, 0.55, 0.68)

	_add_mesh(Vector3(24, 6.5, 0.6), Vector3(0, 3.25, -10), conc_mat)
	_add_mesh(Vector3(6.0, 2.8, 2.5), Vector3(-4.5, 1.4, -4.5), metal_mat, 16.0)
	_add_mesh(Vector3(6.0, 2.8, 2.5), Vector3(5.2, 1.4, -5.8), metal_mat, -22.0)
	_add_mesh(Vector3(2.8, 1.0, 0.6), Vector3(1.2, 0.5, -1.8), conc_mat, 12.0)

	# Warm streetlamp glow
	_lamp_light = OmniLight3D.new()
	_lamp_light.position = Vector3(2.8, 5.2, -3.5)
	_lamp_light.light_color = Color(1.0, 0.76, 0.44)
	_lamp_light.light_energy = 5.5
	_lamp_light.omni_range = 18.0
	add_child(_lamp_light)

	# Gentle rain streaks
	var rain := CPUParticles3D.new()
	rain.position = Vector3(0, 9.0, -3.0)
	rain.amount = 90
	rain.lifetime = 0.7
	rain.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain.emission_box_extents = Vector3(9.0, 0.5, 9.0)
	rain.direction = Vector3(0.08, -1.0, 0.0)
	rain.initial_velocity_min = 16.0
	rain.initial_velocity_max = 20.0
	var rm := BoxMesh.new()
	rm.size = Vector3(0.012, 0.38, 0.012)
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.albedo_color = Color(0.72, 0.80, 0.92, 0.28)
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.material = rmat
	rain.mesh = rm
	add_child(rain)

	# Orbiting camera
	_cam_pivot = Node3D.new()
	_cam_pivot.position = Vector3(0.5, 1.8, -3.5)
	add_child(_cam_pivot)
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 1.4, 8.2)
	cam.rotation_degrees.x = -8.0
	cam.fov = 68.0
	cam.current = true
	_cam_pivot.add_child(cam)


func _add_mesh(sz: Vector3, pos: Vector3, mat: Material, rot_y: float = 0.0) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.position = pos
	mi.rotation_degrees.y = rot_y
	mi.material_override = mat
	add_child(mi)


func _process(delta: float) -> void:
	if is_instance_valid(_cam_pivot):
		_cam_pivot.rotation.y = sin(Time.get_ticks_msec() * 0.00022) * 0.32
	if is_instance_valid(_lamp_light):
		var t := Time.get_ticks_msec() * 0.001
		_lamp_light.light_energy = 3.8 if sin(t * 21.0) * sin(t * 5.7) < -0.82 else 5.5


func _build_ui() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)

	# Left Tactical Glass Panel (Main Menu)
	_main_panel = PanelContainer.new()
	_main_panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_main_panel.offset_left = 48
	_main_panel.offset_top = 70
	_main_panel.offset_right = 470
	_main_panel.offset_bottom = -70
	_style_panel(_main_panel)
	ui.add_child(_main_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	_main_panel.add_child(vb)

	var badge := Label.new()
	badge.text = "● REC  //  AXON BODY 4  //  LINUX NATIVE"
	badge.add_theme_font_size_override("font_size", 12)
	badge.add_theme_color_override("font_color", Color(0.95, 0.25, 0.22))
	vb.add_child(badge)

	var title := Label.new()
	title.text = "SECTOR 09\nBODYCAM"
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	vb.add_child(title)

	var sub := Label.new()
	sub.text = "FPS Tactique Photoréaliste — 3 Opérations & IA Tactique"
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", Color(0.68, 0.76, 0.82))
	vb.add_child(sub)

	vb.add_child(HSeparator.new())

	_add_menu_button(vb, "▶  LANCER LA MISSION", true, func():
		GameManager.current_level_index = 0
		get_tree().change_scene_to_file("res://scenes/main.tscn")
	)
	_add_menu_button(vb, "🗺  CHOISIR UN NIVEAU (3 CARTES)", false, func():
		_show_subpanel(_levels_panel)
	)
	_add_menu_button(vb, "⚙  RÉGLAGES DU JEU", false, func():
		_show_subpanel(_settings_panel)
	)
	_add_menu_button(vb, "🎮  COMMANDES", false, func():
		_show_subpanel(_controls_panel)
	)
	_add_menu_button(vb, "✕  QUITTER", false, func():
		get_tree().quit()
	)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(spacer)

	var ver := Label.new()
	ver.text = "v1.1.0 OpenGL / Vulkan Linux x86_64  •  Open Source MIT"
	ver.add_theme_font_size_override("font_size", 12)
	ver.add_theme_color_override("font_color", Color(0.50, 0.58, 0.64))
	vb.add_child(ver)

	# ---- LEVEL SELECTION PANEL ----
	_levels_panel = PanelContainer.new()
	_levels_panel.set_anchors_preset(Control.PRESET_CENTER)
	_levels_panel.offset_left = -120
	_levels_panel.offset_top = -230
	_levels_panel.offset_right = 540
	_levels_panel.offset_bottom = 230
	_levels_panel.visible = false
	_style_panel(_levels_panel)
	ui.add_child(_levels_panel)

	var lvb := VBoxContainer.new()
	lvb.add_theme_constant_override("separation", 14)
	_levels_panel.add_child(lvb)

	var ltitle := Label.new()
	ltitle.text = "SÉLECTION DE L'OPÉRATION"
	ltitle.add_theme_font_size_override("font_size", 22)
	lvb.add_child(ltitle)

	var descs := [
		"Pluie nocturne • Cour industrielle & entrepôt sur 2 étages • 5 Hostiles IA • Disjoncteur sabotable.",
		"Brouillard dense • Labyrinthe de conteneurs & bureau nord • 7 Hostiles IA • Combat rapproché.",
		"Complexe souterrain brutaliste • Néons d'urgence & couloirs serrés • 8 Hostiles IA • Haute intensité.",
	]
	for i in range(GameManager.LEVEL_NAMES.size()):
		var card := PanelContainer.new()
		var cst := StyleBoxFlat.new()
		cst.bg_color = Color(0.09, 0.11, 0.14, 0.9)
		cst.set_border_width_all(1)
		cst.border_color = Color(0.32, 0.44, 0.52, 0.7)
		cst.set_content_margin_all(12)
		card.add_theme_stylebox_override("panel", cst)
		lvb.add_child(card)

		var cvb := VBoxContainer.new()
		cvb.add_theme_constant_override("separation", 6)
		card.add_child(cvb)

		var nl := Label.new()
		nl.text = GameManager.LEVEL_NAMES[i]
		nl.add_theme_font_size_override("font_size", 16)
		nl.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
		cvb.add_child(nl)

		var dl := Label.new()
		dl.text = descs[i]
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dl.add_theme_font_size_override("font_size", 13)
		dl.add_theme_color_override("font_color", Color(0.72, 0.78, 0.84))
		cvb.add_child(dl)

		var idx := i
		_add_menu_button(cvb, "▶ DÉPLOYER SUR CE SECTEUR", i == 0, func():
			GameManager.current_level_index = idx
			get_tree().change_scene_to_file("res://scenes/main.tscn")
		)

	_add_menu_button(lvb, "← FERMER", false, func(): _levels_panel.visible = false)

	# ---- CONTROLS PANEL ----
	_controls_panel = PanelContainer.new()
	_controls_panel.set_anchors_preset(Control.PRESET_CENTER)
	_controls_panel.offset_left = -80
	_controls_panel.offset_top = -220
	_controls_panel.offset_right = 520
	_controls_panel.offset_bottom = 220
	_controls_panel.visible = false
	_style_panel(_controls_panel)
	ui.add_child(_controls_panel)

	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 10)
	_controls_panel.add_child(cv)
	var ct := Label.new()
	ct.text = "COMMANDES TACTIQUES (AZERTY & QWERTY)"
	ct.add_theme_font_size_override("font_size", 20)
	cv.add_child(ct)
	var cbody := Label.new()
	cbody.text = "• ZQSD / WASD : Déplacement\n• Shift : Sprint tactique\n• Ctrl / C : S'accroupir\n• Espace : Sauter\n• A / E (ou Q / E) : Se pencher à gauche / droite\n• Clic Gauche / Clic Droit : Tirer / Viser (ADS)\n• R : Recharger   |   B : Vérifier chargeur   |   X : Semi / Auto\n• F : Lampe tactique   |   L : Laser PEQ-15   |   N : Vision Nocturne IR\n• E / V / Entrée : Interagir (Intel, Disjoncteur, Munitions)\n• T : Changer la météo   |   H : Aide HUD   |   ESC : Menu Pause"
	cbody.add_theme_font_size_override("font_size", 14)
	cbody.add_theme_color_override("font_color", Color(0.86, 0.90, 0.94))
	cv.add_child(cbody)
	_add_menu_button(cv, "← FERMER", false, func(): _controls_panel.visible = false)

	# ---- FULL SETTINGS PANEL ----
	_settings_panel = PanelContainer.new()
	_settings_panel.set_script(SettingsPanelScript)
	_settings_panel.set_anchors_preset(Control.PRESET_CENTER)
	_settings_panel.offset_left = -100
	_settings_panel.offset_top = -250
	_settings_panel.offset_right = 500
	_settings_panel.offset_bottom = 250
	_settings_panel.visible = false
	_settings_panel.closed.connect(func(): _settings_panel.visible = false)
	ui.add_child(_settings_panel)


func _show_subpanel(target: Control) -> void:
	_levels_panel.visible = (target == _levels_panel)
	_controls_panel.visible = (target == _controls_panel)
	_settings_panel.visible = (target == _settings_panel)


func _style_panel(p: PanelContainer) -> void:
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.04, 0.055, 0.075, 0.90)
	st.set_border_width_all(2)
	st.border_color = Color(0.28, 0.42, 0.52, 0.82)
	st.corner_radius_top_left = 6
	st.corner_radius_top_right = 6
	st.corner_radius_bottom_left = 6
	st.corner_radius_bottom_right = 6
	st.set_content_margin_all(24)
	p.add_theme_stylebox_override("panel", st)


func _add_menu_button(parent: VBoxContainer, text: String, primary: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44 if primary else 38)
	b.add_theme_font_size_override("font_size", 16 if primary else 14)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.14, 0.34, 0.48, 0.95) if primary else Color(0.11, 0.14, 0.18, 0.9)
	st.set_border_width_all(1)
	st.border_color = Color(0.45, 0.72, 0.90, 0.95) if primary else Color(0.32, 0.40, 0.48, 0.65)
	st.corner_radius_top_left = 4
	st.corner_radius_top_right = 4
	st.corner_radius_bottom_left = 4
	st.corner_radius_bottom_right = 4
	var hov: StyleBoxFlat = st.duplicate()
	hov.bg_color = Color(0.20, 0.46, 0.64, 1.0) if primary else Color(0.18, 0.23, 0.30, 0.95)
	b.add_theme_stylebox_override("normal", st)
	b.add_theme_stylebox_override("hover", hov)
	b.add_theme_stylebox_override("pressed", hov)
	b.mouse_entered.connect(func(): AudioManager.play_2d("ui_hover", -16.0, 0.02))
	b.pressed.connect(func():
		AudioManager.play_2d("ui_click", -8.0, 0.02)
		cb.call()
	)
	parent.add_child(b)
	return b
