extends Node3D
## Dynamic Physical Sky, Day/Night Cycle, Volumetric Fog, AgX Tonemapping,
## Real-time Rain Particles, Lightning/Thunder, and Surface Wetness Controller.

var world_env: WorldEnvironment
var env: Environment
var sky_mat: PhysicalSkyMaterial
var sun_light: DirectionalLight3D
var rain_particles: GPUParticles3D

var outdoor_wet_materials: Array[StandardMaterial3D] = []
var street_lights: Array[Light3D] = []

var _lightning_timer: float = 14.0
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
	sky_mat = PhysicalSkyMaterial.new()
	sky_mat.rayleigh_coefficient = 2.2
	sky_mat.mie_coefficient = 0.012
	sky_mat.mie_eccentricity = 0.82
	sky_mat.turbidity = 14.0
	sky_mat.ground_color = Color(0.06, 0.07, 0.08)
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky

	# AgX Filmic Tonemapping (Godot 4.4 native photorealistic filmic curve!)
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.08
	env.tonemap_white = 6.0

	# Ambient & reflections
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.72
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY

	# Screen-Space Realism (SSR for wet puddles, SSAO, SSIL)
	env.ssr_enabled = true
	env.ssr_max_steps = 64
	env.ssr_fade_in = 0.12
	env.ssr_fade_out = 1.8
	env.ssr_depth_tolerance = 0.25

	env.ssao_enabled = true
	env.ssao_radius = 1.15
	env.ssao_intensity = 1.85
	env.ssao_power = 1.6

	env.ssil_enabled = true
	env.ssil_radius = 4.5
	env.ssil_intensity = 0.85

	# Volumetric Fog (gives streetlamps & weapon flashlight physical light shafts!)
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.022
	env.volumetric_fog_albedo = Color(0.45, 0.50, 0.56)
	env.volumetric_fog_emission = Color(0.01, 0.014, 0.02)
	env.volumetric_fog_anisotropy = 0.62
	env.volumetric_fog_length = 85.0
	env.volumetric_fog_sky_affect = 0.45

	# Subtle physical bloom
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_strength = 0.75
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.25
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT

	# Subtle cinematic color grading
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 0.94

	world_env.environment = env
	add_child(world_env)


func _setup_sun() -> void:
	sun_light = DirectionalLight3D.new()
	sun_light.shadow_enabled = true
	sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun_light.directional_shadow_max_distance = 120.0
	sun_light.shadow_bias = 0.03
	sun_light.shadow_normal_bias = 1.4
	sun_light.light_angular_distance = 1.2
	add_child(sun_light)


func _setup_rain() -> void:
	rain_particles = GPUParticles3D.new()
	rain_particles.amount = 2200
	rain_particles.lifetime = 0.85
	rain_particles.visibility_aabb = AABB(Vector3(-24, -14, -24), Vector3(48, 28, 48))

	var pmat := ParticleProcessMaterial.new()
	pmat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pmat.emission_box_extents = Vector3(18.0, 1.5, 18.0)
	pmat.direction = Vector3(0.12, -1.0, 0.06)
	pmat.spread = 3.5
	pmat.initial_velocity_min = 18.0
	pmat.initial_velocity_max = 24.0
	pmat.gravity = Vector3(0.0, -9.8, 0.0)
	rain_particles.process_material = pmat

	var rmesh := BoxMesh.new()
	rmesh.size = Vector3(0.011, 0.48, 0.011)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.72, 0.78, 0.88, 0.28)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	rmesh.material = mat
	rain_particles.draw_pass_1 = rmesh

	add_child(rain_particles)


func _apply_graphics_and_weather() -> void:
	# Graphics presets
	match GameManager.graphics_preset:
		0: # Performance
			env.ssr_enabled = false
			env.ssil_enabled = false
			env.sdfgi_enabled = false
			env.ssao_enabled = true
			env.volumetric_fog_enabled = true
			rain_particles.amount = 900
		1: # High (Recommended)
			env.ssr_enabled = true
			env.ssil_enabled = true
			env.sdfgi_enabled = false
			env.ssao_enabled = true
			env.volumetric_fog_enabled = true
			rain_particles.amount = 2200
		2: # Ultra (+Real-Time SDFGI)
			env.ssr_enabled = true
			env.ssil_enabled = true
			env.sdfgi_enabled = true
			env.sdfgi_use_occlusion = true
			env.sdfgi_bounce_feedback = 0.55
			env.ssao_enabled = true
			env.volumetric_fog_enabled = true
			rain_particles.amount = 3000

	# Weather presets
	var is_raining := GameManager.weather_preset == GameManager.WeatherPreset.RAIN_STORM
	rain_particles.emitting = is_raining

	match GameManager.weather_preset:
		GameManager.WeatherPreset.RAIN_STORM:
			env.volumetric_fog_density = 0.025
			env.volumetric_fog_albedo = Color(0.38, 0.44, 0.52)
			sky_mat.turbidity = 22.0
		GameManager.WeatherPreset.OVERCAST_DUSK:
			env.volumetric_fog_density = 0.016
			env.volumetric_fog_albedo = Color(0.56, 0.48, 0.46)
			sky_mat.turbidity = 16.0
		GameManager.WeatherPreset.FOGGY_NIGHT:
			env.volumetric_fog_density = 0.048
			env.volumetric_fog_albedo = Color(0.32, 0.36, 0.42)
			sky_mat.turbidity = 26.0
		GameManager.WeatherPreset.DAWN_CLEAR:
			env.volumetric_fog_density = 0.009
			env.volumetric_fog_albedo = Color(0.75, 0.66, 0.56)
			sky_mat.turbidity = 6.5

	# Dynamic wetness on outdoor asphalt & concrete!
	for mat in outdoor_wet_materials:
		if is_instance_valid(mat):
			if is_raining:
				mat.roughness = 0.68
				mat.clearcoat_enabled = true
				mat.clearcoat = 0.45
				mat.clearcoat_roughness = 0.14
			else:
				mat.roughness = 0.92
				mat.clearcoat_enabled = false

	_update_celestial_lighting()


func _process(delta: float) -> void:
	if get_tree().paused:
		return

	# Gentle real-time 24h cycle
	GameManager.time_of_day = fmod(GameManager.time_of_day + GameManager.day_cycle_speed * delta, 24.0)
	_update_celestial_lighting()

	# Keep rain cloud centered above player
	if is_instance_valid(GameManager.player):
		rain_particles.global_position = GameManager.player.global_position + Vector3(0.0, 14.0, 0.0)

	# Lightning & delayed thunder during Rain Storm
	if GameManager.weather_preset == GameManager.WeatherPreset.RAIN_STORM:
		_lightning_timer -= delta
		if _lightning_timer <= 0.0:
			_trigger_lightning()
			_lightning_timer = randf_range(16.0, 34.0)

	if _lightning_flash > 0.0:
		_lightning_flash = maxf(0.0, _lightning_flash - delta * 4.5)
		sun_light.light_energy += _lightning_flash * 4.5
		if GameManager.hud and GameManager.hud.has_method("trigger_shutter_flash"):
			GameManager.hud.trigger_shutter_flash(_lightning_flash * 0.45)


func _update_celestial_lighting() -> void:
	var h: float = GameManager.time_of_day
	# Sun elevation: 6:00 sunrise (0 deg), 12:00 zenith (65 deg), 18:30 sunset (0 deg)
	var sun_angle_rad: float = ((h - 6.0) / 24.0) * TAU
	var elevation: float = sin(sun_angle_rad) * 1.15
	var azimuth: float = cos(sun_angle_rad) * 0.8 + 0.6

	var is_night: bool = elevation < 0.05
	if not is_night:
		sun_light.rotation = Vector3(-maxf(elevation, 0.06), azimuth, 0.0)
		var day_factor := clampf(elevation * 1.4, 0.0, 1.0)
		var warm := Color(1.0, 0.62, 0.38)
		var noon := Color(0.96, 0.98, 1.0)
		sun_light.light_color = warm.lerp(noon, day_factor)
		var storm_dim := 0.42 if GameManager.weather_preset == GameManager.WeatherPreset.RAIN_STORM else 1.0
		sun_light.light_energy = lerpf(0.55, 2.4, day_factor) * storm_dim
		env.ambient_light_energy = lerpf(0.35, 0.85, day_factor)
	else:
		# Cool bluish moonlight angle
		sun_light.rotation = Vector3(-0.62, -0.85, 0.0)
		sun_light.light_color = Color(0.52, 0.64, 0.86)
		sun_light.light_energy = 0.24 if GameManager.weather_preset == GameManager.WeatherPreset.RAIN_STORM else 0.34
		env.ambient_light_energy = 0.22

	# Auto-toggle streetlamps at dusk/night
	var lamps_on := (h >= 17.5 or h <= 7.0) and GameManager.power_grid_online
	for l in street_lights:
		if is_instance_valid(l):
			l.visible = lamps_on


func _trigger_lightning() -> void:
	_lightning_flash = 1.0
	var delay := randf_range(0.65, 2.1)
	var t := get_tree().create_timer(delay)
	t.timeout.connect(func():
		AudioManager.play_2d("thunder", -6.0 if GameManager.player_indoors else -1.5, 0.12, &"Ambience")
	)
