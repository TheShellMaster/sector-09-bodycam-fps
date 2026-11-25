extends Node3D
## Optimized Atmospheric Sky, Day/Night Cycle, Depth Fog, ACES Tonemapping,
## Lightweight 3D Rain, Lightning/Thunder, and Wetness Controller.
## Tuned for 60 FPS on Linux OpenGL 3.3 (Intel/AMD/NVIDIA) & Vulkan.

var world_env: WorldEnvironment
var env: Environment
var sky_mat: ProceduralSkyMaterial
var sun_light: DirectionalLight3D
var rain_particles: CPUParticles3D

var outdoor_wet_materials: Array[StandardMaterial3D] = []
var street_lights: Array[Node3D] = []

var _lightning_timer: float = 18.0
var _lightning_flash: float = 0.0


func _ready() -> void:
	GameManager.weather_controller = self
	_setup_environment()
	_setup_sun()
	_setup_rain()
	GameManager.settings_changed.connect(_apply_graphics_and_weather)
	_apply_graphics_and_weather()


func _setup_environment() -> void:
	world_env = WorldEnvironment.new()
	env = Environment.new()

	var sky := Sky.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.06, 0.09, 0.14)
	sky_mat.sky_horizon_color = Color(0.16, 0.20, 0.26)
	sky_mat.ground_bottom_color = Color(0.04, 0.05, 0.06)
	sky_mat.ground_horizon_color = Color(0.12, 0.14, 0.17)
	sky_mat.sun_angle_max = 18.0
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky

	# ACES Filmic tonemapping (fast & photorealistic in both OpenGL 3.3 & Vulkan)
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.15
	env.tonemap_white = 4.5

	# Readable ambient light so dark corners stay atmospheric, never pitch-black
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.38, 0.46)
	env.ambient_light_energy = 0.55

	# Fast Hardware Exponential Depth Fog (works everywhere at 60 FPS!)
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = Color(0.16, 0.20, 0.26)
	env.fog_light_energy = 0.85
	env.fog_density = 0.022
	env.fog_sky_affect = 0.55

	# Subtle physical bloom
	env.glow_enabled = true
	env.glow_intensity = 0.28
	env.glow_strength = 0.65
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.15

	env.adjustment_enabled = true
	env.adjustment_contrast = 1.07
	env.adjustment_saturation = 0.94

	world_env.environment = env
	add_child(world_env)


func _setup_sun() -> void:
	sun_light = DirectionalLight3D.new()
	sun_light.shadow_enabled = true
	sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun_light.directional_shadow_max_distance = 45.0
	sun_light.shadow_bias = 0.06
	sun_light.shadow_normal_bias = 1.6
	add_child(sun_light)


func _setup_rain() -> void:
	rain_particles = CPUParticles3D.new()
	rain_particles.amount = 110
	rain_particles.lifetime = 0.65
	rain_particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	rain_particles.emission_box_extents = Vector3(12.0, 1.0, 12.0)
	rain_particles.direction = Vector3(0.08, -1.0, 0.04)
	rain_particles.spread = 2.0
	rain_particles.initial_velocity_min = 18.0
	rain_particles.initial_velocity_max = 22.0
	rain_particles.gravity = Vector3(0.0, -9.8, 0.0)

	var rmesh := BoxMesh.new()
	rmesh.size = Vector3(0.012, 0.42, 0.012)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.75, 0.82, 0.92, 0.30)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmesh.material = mat
	rain_particles.mesh = rmesh
	add_child(rain_particles)


func _apply_graphics_and_weather() -> void:
	match GameManager.graphics_preset:
		0: # Performance (Ultra Fluide — Intel HD / PC Portable)
			sun_light.shadow_enabled = false
			env.glow_enabled = false
			rain_particles.amount = 80
			get_viewport().scaling_3d_scale = 0.72
		1: # Équilibré (Recommandé — Fluide + Ombres)
			sun_light.shadow_enabled = true
			env.glow_enabled = false
			rain_particles.amount = 120
			get_viewport().scaling_3d_scale = 0.85
		2: # Haut (Ombres + Bloom + Pluie Dense)
			sun_light.shadow_enabled = true
			env.glow_enabled = true
			rain_particles.amount = 240
			get_viewport().scaling_3d_scale = 1.0

	var is_raining := GameManager.weather_preset == GameManager.WeatherPreset.RAIN_STORM
	rain_particles.emitting = is_raining

	match GameManager.weather_preset:
		GameManager.WeatherPreset.RAIN_STORM:
			env.fog_density = 0.022
			env.fog_light_color = Color(0.14, 0.18, 0.24)
			sky_mat.sky_top_color = Color(0.05, 0.07, 0.11)
			sky_mat.sky_horizon_color = Color(0.14, 0.18, 0.24)
		GameManager.WeatherPreset.OVERCAST_DUSK:
			env.fog_density = 0.014
			env.fog_light_color = Color(0.28, 0.24, 0.24)
			sky_mat.sky_top_color = Color(0.12, 0.14, 0.22)
			sky_mat.sky_horizon_color = Color(0.45, 0.30, 0.25)
		GameManager.WeatherPreset.FOGGY_NIGHT:
			env.fog_density = 0.036
			env.fog_light_color = Color(0.12, 0.15, 0.20)
			sky_mat.sky_top_color = Color(0.03, 0.04, 0.07)
			sky_mat.sky_horizon_color = Color(0.10, 0.13, 0.18)
		GameManager.WeatherPreset.DAWN_CLEAR:
			env.fog_density = 0.008
			env.fog_light_color = Color(0.55, 0.48, 0.42)
			sky_mat.sky_top_color = Color(0.22, 0.36, 0.58)
			sky_mat.sky_horizon_color = Color(0.72, 0.56, 0.42)

	# Dynamic specular wetness on outdoor asphalt & concrete!
	for mat in outdoor_wet_materials:
		if is_instance_valid(mat):
			if is_raining:
				mat.roughness = 0.55
				mat.metallic_specular = 0.72
			else:
				mat.roughness = 0.88
				mat.metallic_specular = 0.42

	_update_celestial_lighting()


func _process(delta: float) -> void:
	if get_tree().paused:
		return

	GameManager.time_of_day = fmod(GameManager.time_of_day + GameManager.day_cycle_speed * delta, 24.0)
	_update_celestial_lighting()

	if is_instance_valid(GameManager.player):
		rain_particles.global_position = GameManager.player.global_position + Vector3(0.0, 11.5, 0.0)

	if GameManager.weather_preset == GameManager.WeatherPreset.RAIN_STORM:
		_lightning_timer -= delta
		if _lightning_timer <= 0.0:
			_trigger_lightning()
			_lightning_timer = randf_range(16.0, 32.0)

	if _lightning_flash > 0.0:
		_lightning_flash = maxf(0.0, _lightning_flash - delta * 4.5)
		sun_light.light_energy += _lightning_flash * 3.5
		if GameManager.hud and GameManager.hud.has_method("trigger_shutter_flash"):
			GameManager.hud.trigger_shutter_flash(_lightning_flash * 0.4)


func _update_celestial_lighting() -> void:
	var h: float = GameManager.time_of_day
	var sun_angle_rad: float = ((h - 6.0) / 24.0) * TAU
	var elevation: float = sin(sun_angle_rad) * 1.15
	var azimuth: float = cos(sun_angle_rad) * 0.8 + 0.6

	var is_night: bool = elevation < 0.05
	if not is_night:
		sun_light.rotation = Vector3(-maxf(elevation, 0.12), azimuth, 0.0)
		var day_factor := clampf(elevation * 1.4, 0.0, 1.0)
		sun_light.light_color = Color(1.0, 0.68, 0.44).lerp(Color(0.96, 0.98, 1.0), day_factor)
		var storm_dim := 0.55 if GameManager.weather_preset == GameManager.WeatherPreset.RAIN_STORM else 1.0
		sun_light.light_energy = lerpf(0.7, 1.9, day_factor) * storm_dim
		env.ambient_light_energy = lerpf(0.55, 0.92, day_factor)
	else:
		sun_light.rotation = Vector3(-0.62, -0.85, 0.0)
		sun_light.light_color = Color(0.58, 0.70, 0.92)
		sun_light.light_energy = 0.45
		env.ambient_light_energy = 0.48

	var lamps_on := (h >= 17.5 or h <= 7.0) and GameManager.power_grid_online
	for l in street_lights:
		if is_instance_valid(l):
			l.visible = lamps_on


func _trigger_lightning() -> void:
	_lightning_flash = 1.0
	var delay := randf_range(0.6, 1.9)
	var t := get_tree().create_timer(delay)
	t.timeout.connect(func():
		AudioManager.play_2d("thunder", -6.0 if GameManager.player_indoors else -1.5, 0.12, &"Ambience")
	)
