extends Node3D
## Modular PBR Multi-Level Builder for SECTOR 09 // BODYCAM
## Builds 3 distinct photorealistic tactical levels with full PBR materials,
## real-time lighting, volumetric streetlamps, physical RigidBody3D props,
## interactive objectives (Intel Laptop, Power Breaker, Ammo Crate),
## NavigationMesh baking, and patrolling Tactical AI squads.

const InteractableScript = preload("res://scripts/world/interactable.gd")
const AIScript = preload("res://scripts/ai/tactical_ai.gd")

var _mats: Dictionary = {}
var _warehouse_lights: Array[Light3D] = []
var _warehouse_emissives: Array[MeshInstance3D] = []
var _flicker_lights: Array[Light3D] = []
var _nav_region: NavigationRegion3D
var _world_geom: Node3D
var _weather: Node3D

var player_spawn: Vector3 = Vector3(0.0, 0.2, 22.0)
var player_spawn_yaw: float = 0.0


func build_level(level_idx: int, weather_node: Node3D) -> void:
	_weather = weather_node
	_init_pbr_materials()

	_nav_region = NavigationRegion3D.new()
	add_child(_nav_region)
	_world_geom = Node3D.new()
	_nav_region.add_child(_world_geom)

	match level_idx:
		0:
			GameManager.weather_preset = GameManager.WeatherPreset.RAIN_STORM
			GameManager.time_of_day = 20.1
			_build_level_1_warehouse()
		1:
			GameManager.weather_preset = GameManager.WeatherPreset.FOGGY_NIGHT
			GameManager.time_of_day = 22.8
			_build_level_2_docks()
		_:
			GameManager.weather_preset = GameManager.WeatherPreset.OVERCAST_DUSK
			GameManager.time_of_day = 23.5
			_build_level_3_bunker()

	GameManager.notify_settings_changed()
	_bake_navigation()


func _process(_delta: float) -> void:
	# Subtle realistic fluorescent/sodium tube micro-flicker
	if not GameManager.power_grid_online:
		return
	var t := Time.get_ticks_msec() * 0.001
	for i in range(_flicker_lights.size()):
		var l := _flicker_lights[i]
		if is_instance_valid(l) and l.visible:
			var n := sin(t * 27.0 + float(i) * 4.3) * sin(t * 7.3 + float(i))
			l.light_energy = 1.4 if n < -0.78 else 4.2


func _init_pbr_materials() -> void:
	_mats["asphalt"] = _load_pbr("asphalt_wet", Vector3(22, 22, 1), true, 0.05)
	_mats["concrete"] = _load_pbr("concrete_wall", Vector3(3, 2, 1), true, 0.0)
	_mats["concrete_large"] = _load_pbr("concrete_wall", Vector3(12, 4, 1), true, 0.0)
	_mats["brick"] = _load_pbr("brick_industrial", Vector3(6, 3, 1), false, 0.0)
	_mats["metal"] = _load_pbr("rusty_metal", Vector3(2.5, 2.0, 1), false, 0.72)
	_mats["wood"] = _load_pbr("wood_crate", Vector3(1.0, 1.0, 1), false, 0.0)
	_mats["floor_indoor"] = _load_pbr("warehouse_floor", Vector3(10, 10, 1), false, 0.08)
	_mats["hazard"] = _load_pbr("hazard_stripe", Vector3(4, 1, 1), false, 0.05)

	# Colored painted shipping container variants
	var cont_blue: StandardMaterial3D = _mats["metal"].duplicate()
	cont_blue.albedo_color = Color(0.32, 0.45, 0.62)
	_mats["container_blue"] = cont_blue

	var cont_red: StandardMaterial3D = _mats["metal"].duplicate()
	cont_red.albedo_color = Color(0.65, 0.28, 0.24)
	_mats["container_red"] = cont_red

	var cont_olive: StandardMaterial3D = _mats["metal"].duplicate()
	cont_olive.albedo_color = Color(0.36, 0.44, 0.34)
	_mats["container_olive"] = cont_olive

	var dark_steel := StandardMaterial3D.new()
	dark_steel.albedo_color = Color(0.14, 0.15, 0.17)
	dark_steel.metallic = 0.85
	dark_steel.roughness = 0.38
	_mats["dark_steel"] = dark_steel


func _load_pbr(prefix: String, uv_scale: Vector3, is_outdoor_wet: bool, metallic: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.uv1_scale = uv_scale
	# Standard UV mapping (3x faster than triplanar on integrated GPUs!)
	mat.uv1_triplanar = false
	mat.metallic = metallic
	var base := "res://assets/textures/" + prefix
	if ResourceLoader.exists(base + "_albedo.png"):
		mat.albedo_texture = load(base + "_albedo.png")
	if ResourceLoader.exists(base + "_normal.png"):
		mat.normal_enabled = true
		mat.normal_texture = load(base + "_normal.png")
		mat.normal_scale = 1.1
	if ResourceLoader.exists(base + "_roughness.png"):
		mat.roughness_texture = load(base + "_roughness.png")
	if is_outdoor_wet and _weather != null:
		_weather.outdoor_wet_materials.append(mat)
	return mat


# ============================================================================
# LEVEL 1: SECTOR 09 — RAIN-SLICKED COURTYARD & ABANDONED WAREHOUSE
# ============================================================================
func _build_level_1_warehouse() -> void:
	player_spawn = Vector3(0.0, 0.2, 23.5)
	player_spawn_yaw = 0.0

	# Main wet asphalt ground (64m x 64m)
	_add_static_box(Vector3(64, 0.6, 64), Vector3(0, -0.3, 0), _mats["asphalt"], "asphalt")

	# Perimeter concrete security walls
	_add_static_box(Vector3(64, 5.5, 0.8), Vector3(0, 2.75, 31.6), _mats["concrete_large"], "concrete")
	_add_static_box(Vector3(64, 5.5, 0.8), Vector3(0, 2.75, -31.6), _mats["concrete_large"], "concrete")
	_add_static_box(Vector3(0.8, 5.5, 64), Vector3(-31.6, 2.75, 0), _mats["concrete_large"], "concrete")
	_add_static_box(Vector3(0.8, 5.5, 64), Vector3(31.6, 2.75, 0), _mats["concrete_large"], "concrete")

	# Guard Booth near spawn
	_add_static_box(Vector3(3.6, 0.2, 3.6), Vector3(-7.5, 0.1, 20.5), _mats["concrete"], "concrete")
	_add_static_box(Vector3(3.6, 3.0, 0.25), Vector3(-7.5, 1.5, 18.8), _mats["brick"], "concrete")
	_add_static_box(Vector3(0.25, 3.0, 3.6), Vector3(-9.2, 1.5, 20.5), _mats["brick"], "concrete")
	_add_static_box(Vector3(3.8, 0.25, 3.8), Vector3(-7.5, 3.1, 20.5), _mats["metal"], "metal")
	_add_indoor_lamp(Vector3(-7.5, 2.85, 20.5), Color(0.85, 0.96, 1.0), 3.6, true)

	# Outdoor Tactical Cover: Concrete Jersey Barriers & Shipping Containers
	_add_jersey_barrier(Vector3(-3.5, 0, 14.5), 12.0)
	_add_jersey_barrier(Vector3(4.2, 0, 13.0), -8.0)
	_add_jersey_barrier(Vector3(0.0, 0, 6.0), 4.0)
	_add_shipping_container(Vector3(-12.0, 0, 10.5), 18.0, "container_red")
	_add_shipping_container(Vector3(12.5, 0, 11.5), -14.0, "container_blue")
	_add_shipping_container(Vector3(16.0, 0, 2.0), 82.0, "container_olive")

	# Outdoor Sodium-Vapor Streetlamps (dramatic volumetric cones + wet asphalt SSR!)
	_add_streetlamp(Vector3(-14.0, 0, 19.5), 90.0)
	_add_streetlamp(Vector3(14.0, 0, 18.5), -90.0)
	_add_streetlamp(Vector3(-16.5, 0, 3.5), 90.0)
	_add_streetlamp(Vector3(17.5, 0, -4.0), -90.0)

	# ---- MAIN INDUSTRIAL WAREHOUSE (z = -2 to -26, x = -14 to +14, height = 7.6m) ----
	_add_static_box(Vector3(28.0, 0.16, 24.0), Vector3(0, 0.08, -14.0), _mats["floor_indoor"], "concrete")
	# Roof
	_add_static_box(Vector3(28.8, 0.4, 24.8), Vector3(0, 7.6, -14.0), _mats["metal"], "metal")
	# Back wall (north z=-26)
	_add_static_box(Vector3(28.0, 7.6, 0.5), Vector3(0, 3.8, -26.0), _mats["brick"], "concrete")
	# Side walls (west x=-14, east x=14) with side breach doorway on west!
	_add_static_box(Vector3(0.5, 7.6, 13.0), Vector3(-14.0, 3.8, -19.5), _mats["brick"], "concrete")
	_add_static_box(Vector3(0.5, 7.6, 8.0), Vector3(-14.0, 3.8, -6.0), _mats["brick"], "concrete")
	_add_static_box(Vector3(0.5, 4.4, 3.0), Vector3(-14.0, 5.4, -11.5), _mats["brick"], "concrete") # Door header
	_add_static_box(Vector3(0.5, 7.6, 24.0), Vector3(14.0, 3.8, -14.0), _mats["brick"], "concrete")

	# Front wall (z=-2) with wide Roll-Up Loading Bay Door (gap x = -4..+4) + side door (x = 9..11.2)
	_add_static_box(Vector3(10.0, 7.6, 0.5), Vector3(-9.0, 3.8, -2.0), _mats["concrete"], "concrete")
	_add_static_box(Vector3(5.0, 7.6, 0.5), Vector3(6.5, 3.8, -2.0), _mats["concrete"], "concrete")
	_add_static_box(Vector3(2.8, 7.6, 0.5), Vector3(12.6, 3.8, -2.0), _mats["concrete"], "concrete")
	_add_static_box(Vector3(8.0, 3.2, 0.5), Vector3(0.0, 6.0, -2.0), _mats["metal"], "metal") # Roll-up shutter top
	_add_static_box(Vector3(2.2, 4.4, 0.5), Vector3(10.1, 5.4, -2.0), _mats["concrete"], "concrete")
	# Hazard stripe threshold at entrance
	_add_static_box(Vector3(8.2, 0.05, 1.0), Vector3(0.0, 0.17, -2.0), _mats["hazard"], "concrete")

	# Concrete Structural Pillars inside warehouse
	for px in [-6.5, 6.5]:
		for pz in [-8.5, -16.5]:
			_add_static_box(Vector3(0.75, 7.6, 0.75), Vector3(px, 3.8, pz), _mats["concrete"], "concrete")

	# Interior Mezzanine / Upper Tactical Office (y = 3.6, back-right corner)
	_add_static_box(Vector3(12.0, 0.28, 9.0), Vector3(7.6, 3.6, -21.2), _mats["metal"], "metal")
	# Mezzanine railing
	_add_static_box(Vector3(12.0, 1.05, 0.14), Vector3(7.6, 4.25, -16.8), _mats["dark_steel"], "metal")
	_add_static_box(Vector3(0.14, 1.05, 6.0), Vector3(1.65, 4.25, -22.7), _mats["dark_steel"], "metal")
	# Walkable Industrial Ramp/Stairs up to Mezzanine (from x = -3.5 to +1.65 along z = -18.2)
	_add_ramp_stairs(Vector3(-3.2, 0.16, -18.2), Vector3(1.65, 3.6, -18.2), 2.1)

	# Warehouse Overhead Hanging Lamps (linked to Power Breaker!)
	_add_indoor_lamp(Vector3(-6.0, 6.6, -9.0), Color(1.0, 0.88, 0.70), 4.6, false)
	_add_indoor_lamp(Vector3(6.0, 6.6, -9.0), Color(0.82, 0.92, 1.0), 4.4, true)
	_add_indoor_lamp(Vector3(-6.0, 6.6, -19.0), Color(1.0, 0.85, 0.68), 4.4, false)
	_add_indoor_lamp(Vector3(7.5, 6.6, -21.0), Color(0.84, 0.94, 1.0), 4.8, false)

	# Interior tactical cover (wooden crates, steel barrels, forklifts/pallets)
	_add_crate_stack(Vector3(-3.0, 0.16, -9.5))
	_add_crate_stack(Vector3(4.5, 0.16, -12.5))
	_add_crate_stack(Vector3(-9.5, 0.16, -18.0))
	_add_physics_barrel(Vector3(-1.2, 0.65, -7.0), Color(0.62, 0.18, 0.15))
	_add_physics_barrel(Vector3(5.8, 0.65, -6.5), Color(0.18, 0.36, 0.56))
	_add_physics_barrel(Vector3(-8.0, 0.65, -13.5), Color(0.22, 0.25, 0.22))
	_add_physics_crate(Vector3(1.8, 0.55, -11.5))
	_add_physics_crate(Vector3(-5.2, 0.55, -15.5))

	# Interactive Objects
	_add_power_breaker(Vector3(-13.65, 1.5, -8.0), 90.0) # Inside west wall near side breach
	_add_intel_laptop(Vector3(9.8, 3.74, -22.5)) # On mezzanine office table!
	_add_ammo_crate(Vector3(-6.8, 0.2, 20.5)) # Inside guard booth near spawn!

	# Spawn 5 Tactical AI Hostiles with distinct patrol routes
	_spawn_ai(Vector3(-4.0, 0.2, 3.0), [Vector3(-6.5, 0.2, 3.0), Vector3(5.5, 0.2, 3.0)])
	_spawn_ai(Vector3(-8.5, 0.2, -8.5), [Vector3(-9.5, 0.2, -6.0), Vector3(-9.5, 0.2, -16.0)])
	_spawn_ai(Vector3(3.5, 0.2, -10.5), [Vector3(2.0, 0.2, -8.0), Vector3(8.5, 0.2, -14.0)])
	_spawn_ai(Vector3(-5.5, 0.2, -22.0), [Vector3(-9.0, 0.2, -22.5), Vector3(1.0, 0.2, -22.5)])
	_spawn_ai(Vector3(7.5, 3.85, -19.5), [Vector3(5.0, 3.85, -19.0), Vector3(11.0, 3.85, -22.0)])


# ============================================================================
# LEVEL 2: SECTOR 14 — FOGGY NIGHT SHIPPING DOCKS & CONTAINER MAZE
# ============================================================================
func _build_level_2_docks() -> void:
	player_spawn = Vector3(0.0, 0.2, 26.0)
	player_spawn_yaw = 0.0

	_add_static_box(Vector3(72, 0.6, 72), Vector3(0, -0.3, 0), _mats["asphalt"], "asphalt")
	# Perimeter walls
	_add_static_box(Vector3(72, 6.0, 0.8), Vector3(0, 3.0, 35.6), _mats["concrete_large"], "concrete")
	_add_static_box(Vector3(72, 6.0, 0.8), Vector3(0, 3.0, -35.6), _mats["concrete_large"], "concrete")
	_add_static_box(Vector3(0.8, 6.0, 72), Vector3(-35.6, 3.0, 0), _mats["concrete_large"], "concrete")
	_add_static_box(Vector3(0.8, 6.0, 72), Vector3(35.6, 3.0, 0), _mats["concrete_large"], "concrete")

	# Shipping Container CQB Labyrinth (double-stacked for dramatic silhouettes in fog!)
	var containers: Array = [
		[Vector3(-8.5, 0, 16.0), 0.0, "container_blue", true],
		[Vector3(8.5, 0, 15.0), 5.0, "container_red", false],
		[Vector3(-16.0, 0, 6.0), 90.0, "container_olive", true],
		[Vector3(-2.5, 0, 6.5), 90.0, "container_red", false],
		[Vector3(11.0, 0, 5.0), 86.0, "container_blue", true],
		[Vector3(-10.5, 0, -4.5), 4.0, "container_blue", false],
		[Vector3(3.5, 0, -5.0), -6.0, "container_olive", true],
		[Vector3(17.5, 0, -6.5), 90.0, "container_red", false],
		[Vector3(-17.0, 0, -15.5), 90.0, "container_red", true],
		[Vector3(-2.0, 0, -16.0), 0.0, "container_blue", false],
		[Vector3(12.0, 0, -17.0), 12.0, "container_olive", true],
	]
	for c in containers:
		_add_shipping_container(c[0], c[1], c[2])
		if c[3]:
			_add_shipping_container(c[0] + Vector3(0, 2.9, 0), c[1] + 2.0, "container_olive")

	# Concrete barriers & physical barrels
	for bp in [Vector3(0, 0, 19), Vector3(-9, 0, 10), Vector3(5, 0, 1), Vector3(-5, 0, -10), Vector3(7, 0, -12)]:
		_add_jersey_barrier(bp, randf_range(-20.0, 20.0))
	for i in range(6):
		_add_physics_barrel(Vector3(randf_range(-14, 14), 0.65, randf_range(-18, 18)), Color(0.55, 0.22, 0.16))

	# Command Office Shed at north end (z = -27)
	_add_static_box(Vector3(12.0, 0.2, 8.0), Vector3(0, 0.1, -27.0), _mats["floor_indoor"], "concrete")
	_add_static_box(Vector3(12.4, 0.3, 8.4), Vector3(0, 4.1, -27.0), _mats["metal"], "metal")
	_add_static_box(Vector3(12.0, 4.0, 0.4), Vector3(0, 2.0, -31.0), _mats["concrete"], "concrete")
	_add_static_box(Vector3(0.4, 4.0, 8.0), Vector3(-6.0, 2.0, -27.0), _mats["concrete"], "concrete")
	_add_static_box(Vector3(0.4, 4.0, 8.0), Vector3(6.0, 2.0, -27.0), _mats["concrete"], "concrete")
	_add_static_box(Vector3(4.5, 4.0, 0.4), Vector3(-3.75, 2.0, -23.0), _mats["concrete"], "concrete")
	_add_static_box(Vector3(4.5, 4.0, 0.4), Vector3(3.75, 2.0, -23.0), _mats["concrete"], "concrete")
	_add_indoor_lamp(Vector3(0, 3.6, -27.0), Color(0.85, 0.96, 1.0), 4.6, true)

	# Tall Floodlights cutting through thick fog
	_add_streetlamp(Vector3(-20.0, 0, 20.0), 65.0)
	_add_streetlamp(Vector3(20.0, 0, 18.0), -65.0)
	_add_streetlamp(Vector3(-22.0, 0, -2.0), 90.0)
	_add_streetlamp(Vector3(22.0, 0, -4.0), -90.0)
	_add_streetlamp(Vector3(0.0, 0, -20.0), 0.0)

	_add_intel_laptop(Vector3(0.0, 0.22, -29.0))
	_add_power_breaker(Vector3(-5.6, 1.5, -24.5), 90.0)
	_add_ammo_crate(Vector3(4.5, 0.15, 23.0))

	# 7 Tactical Hostiles patrolling container alleys
	_spawn_ai(Vector3(-6.0, 0.2, 11.0), [Vector3(-12.0, 0.2, 11.0), Vector3(4.0, 0.2, 11.0)])
	_spawn_ai(Vector3(6.0, 0.2, 1.0), [Vector3(2.0, 0.2, 1.0), Vector3(15.0, 0.2, 1.0)])
	_spawn_ai(Vector3(-12.0, 0.2, -1.0), [Vector3(-12.0, 0.2, 2.0), Vector3(-12.0, 0.2, -10.0)])
	_spawn_ai(Vector3(0.0, 0.2, -11.0), [Vector3(-8.0, 0.2, -11.0), Vector3(9.0, 0.2, -11.0)])
	_spawn_ai(Vector3(14.0, 0.2, -13.0), [Vector3(14.0, 0.2, -8.0), Vector3(14.0, 0.2, -22.0)])
	_spawn_ai(Vector3(-9.0, 0.2, -22.0), [Vector3(-14.0, 0.2, -22.0), Vector3(-3.0, 0.2, -22.0)])
	_spawn_ai(Vector3(2.5, 0.2, -26.5), [Vector3(-2.5, 0.2, -26.5), Vector3(3.5, 0.2, -26.5)])


# ============================================================================
# LEVEL 3: SECTOR 21 — UNDERGROUND CONCRETE BUNKER FACILITY
# ============================================================================
func _build_level_3_bunker() -> void:
	player_spawn = Vector3(0.0, 0.2, 22.0)
	player_spawn_yaw = 0.0

	# Full enclosed brutalist concrete underground bunker (44m x 54m, ceiling at 4.6m)
	_add_static_box(Vector3(44, 0.6, 54), Vector3(0, -0.3, 0), _mats["floor_indoor"], "concrete")
	_add_static_box(Vector3(44, 0.6, 54), Vector3(0, 4.9, 0), _mats["concrete_large"], "concrete")
	_add_static_box(Vector3(44, 5.2, 0.8), Vector3(0, 2.4, 26.6), _mats["concrete_large"], "concrete")
	_add_static_box(Vector3(44, 5.2, 0.8), Vector3(0, 2.4, -26.6), _mats["concrete_large"], "concrete")
	_add_static_box(Vector3(0.8, 5.2, 54), Vector3(-21.6, 2.4, 0), _mats["concrete_large"], "concrete")
	_add_static_box(Vector3(0.8, 5.2, 54), Vector3(21.6, 2.4, 0), _mats["concrete_large"], "concrete")

	# Sector dividing walls with tactical breach doorways
	# First bulkhead (z = 14) — center & side corridors
	_add_static_box(Vector3(12.0, 4.6, 0.5), Vector3(-12.0, 2.3, 14.0), _mats["concrete"], "concrete")
	_add_static_box(Vector3(12.0, 4.6, 0.5), Vector3(12.0, 2.3, 14.0), _mats["concrete"], "concrete")
	_add_static_box(Vector3(6.0, 4.6, 0.5), Vector3(0.0, 2.3, 14.0), _mats["hazard"], "concrete")

	# Central Reactor / Server Hall dividers (z = 0 and z = -12)
	_add_static_box(Vector3(0.5, 4.6, 18.0), Vector3(-8.5, 2.3, 2.0), _mats["concrete"], "concrete")
	_add_static_box(Vector3(0.5, 4.6, 18.0), Vector3(8.5, 2.3, 2.0), _mats["concrete"], "concrete")
	_add_static_box(Vector3(14.0, 4.6, 0.5), Vector3(0.0, 2.3, -12.0), _mats["concrete"], "concrete")

	# Server Racks & Pillars inside central hall
	for sx in [-4.0, 4.0]:
		for sz in [6.0, -2.0, -8.0]:
			_add_static_box(Vector3(1.1, 2.8, 2.2), Vector3(sx, 1.4, sz), _mats["dark_steel"], "metal")
	_add_crate_stack(Vector3(-15.0, 0.0, 4.0))
	_add_crate_stack(Vector3(14.5, 0.0, -3.0))
	_add_jersey_barrier(Vector3(0.0, 0.0, 2.0), 0.0)
	_add_jersey_barrier(Vector3(-14.0, 0.0, -14.0), 30.0)
	_add_jersey_barrier(Vector3(14.0, 0.0, -14.0), -30.0)

	# Atmospheric Emergency Red & Cold White Bunker Lights
	_add_indoor_lamp(Vector3(0.0, 4.3, 20.0), Color(0.8, 0.92, 1.0), 3.6, false)
	_add_indoor_lamp(Vector3(-14.5, 4.3, 6.0), Color(1.0, 0.25, 0.18), 3.2, true)
	_add_indoor_lamp(Vector3(14.5, 4.3, 6.0), Color(1.0, 0.25, 0.18), 3.2, false)
	_add_indoor_lamp(Vector3(0.0, 4.3, 2.0), Color(0.78, 0.90, 1.0), 4.0, true)
	_add_indoor_lamp(Vector3(-14.0, 4.3, -16.0), Color(0.85, 0.92, 1.0), 3.4, false)
	_add_indoor_lamp(Vector3(14.0, 4.3, -16.0), Color(1.0, 0.35, 0.22), 3.4, true)
	_add_indoor_lamp(Vector3(0.0, 4.3, -21.0), Color(0.45, 0.85, 1.0), 4.2, false)

	_add_power_breaker(Vector3(-8.1, 1.5, 11.0), 90.0)
	_add_intel_laptop(Vector3(0.0, 0.05, -22.5))
	_add_ammo_crate(Vector3(-3.5, 0.05, 22.0))

	# 8 CQB Tactical Hostiles
	_spawn_ai(Vector3(-14.0, 0.2, 8.0), [Vector3(-14.0, 0.2, 11.0), Vector3(-14.0, 0.2, -6.0)])
	_spawn_ai(Vector3(14.0, 0.2, 8.0), [Vector3(14.0, 0.2, 11.0), Vector3(14.0, 0.2, -6.0)])
	_spawn_ai(Vector3(0.0, 0.2, 5.0), [Vector3(-2.0, 0.2, 8.0), Vector3(2.0, 0.2, -4.0)])
	_spawn_ai(Vector3(-3.0, 0.2, -7.0), [Vector3(-6.0, 0.2, -6.0), Vector3(6.0, 0.2, -6.0)])
	_spawn_ai(Vector3(-15.0, 0.2, -16.0), [Vector3(-16.0, 0.2, -10.0), Vector3(-10.0, 0.2, -22.0)])
	_spawn_ai(Vector3(15.0, 0.2, -16.0), [Vector3(16.0, 0.2, -10.0), Vector3(10.0, 0.2, -22.0)])
	_spawn_ai(Vector3(-4.0, 0.2, -20.0), [Vector3(-7.0, 0.2, -18.0), Vector3(4.0, 0.2, -18.0)])
	_spawn_ai(Vector3(4.0, 0.2, -22.0), [Vector3(6.0, 0.2, -23.0), Vector3(-4.0, 0.2, -23.0)])


# ============================================================================
# ARCHITECTURAL & PROP PRIMITIVES
# ============================================================================

func _add_static_box(sz: Vector3, pos: Vector3, mat: Material, surface: String = "concrete", rot_y_deg: float = 0.0) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	sb.position = pos
	sb.rotation_degrees.y = rot_y_deg
	sb.set_meta("surface", surface)

	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.material_override = mat
	sb.add_child(mi)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = sz
	col.shape = shape
	sb.add_child(col)

	_world_geom.add_child(sb)
	return sb


func _add_shipping_container(pos: Vector3, rot_y_deg: float, mat_key: String) -> void:
	_add_static_box(Vector3(6.2, 2.85, 2.55), pos + Vector3(0, 1.425, 0), _mats[mat_key], "metal", rot_y_deg)


func _add_jersey_barrier(pos: Vector3, rot_y_deg: float) -> void:
	_add_static_box(Vector3(2.8, 1.08, 0.65), pos + Vector3(0, 0.54, 0), _mats["concrete"], "concrete", rot_y_deg)


func _add_crate_stack(pos: Vector3) -> void:
	_add_static_box(Vector3(1.4, 1.2, 1.4), pos + Vector3(0, 0.6, 0), _mats["wood"], "wood", 6.0)
	_add_static_box(Vector3(1.2, 1.0, 1.2), pos + Vector3(1.45, 0.5, 0.25), _mats["wood"], "wood", -11.0)
	_add_static_box(Vector3(1.0, 0.95, 1.0), pos + Vector3(0.35, 1.67, 0.08), _mats["wood"], "wood", 18.0)


func _add_physics_crate(pos: Vector3) -> void:
	var rb := RigidBody3D.new()
	rb.collision_layer = 1 << 3
	rb.collision_mask = 1 | (1 << 1) | (1 << 2) | (1 << 3)
	rb.mass = 18.0
	rb.position = pos
	rb.set_meta("surface", "wood")
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.85, 0.85, 0.85)
	mi.mesh = bm
	mi.material_override = _mats["wood"]
	rb.add_child(mi)
	var col := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.85, 0.85, 0.85)
	col.shape = sh
	rb.add_child(col)
	add_child(rb)


func _add_physics_barrel(pos: Vector3, tint: Color) -> void:
	var rb := RigidBody3D.new()
	rb.collision_layer = 1 << 3
	rb.collision_mask = 1 | (1 << 1) | (1 << 2) | (1 << 3)
	rb.mass = 24.0
	rb.position = pos
	rb.set_meta("surface", "metal")
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.32
	cm.bottom_radius = 0.32
	cm.height = 1.05
	mi.mesh = cm
	var m: StandardMaterial3D = _mats["metal"].duplicate()
	m.albedo_color = tint
	mi.material_override = m
	rb.add_child(mi)
	var col := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.radius = 0.32
	sh.height = 1.05
	col.shape = sh
	rb.add_child(col)
	add_child(rb)


func _add_ramp_stairs(start_pt: Vector3, end_pt: Vector3, width: float) -> void:
	var steps := 14
	var delta := (end_pt - start_pt) / float(steps)
	for i in range(steps):
		var p := start_pt + delta * (float(i) + 0.5)
		var step_h := delta.y * (float(i) + 1.0)
		_add_static_box(Vector3(absf(delta.x) + 0.14, step_h, width), Vector3(p.x, start_pt.y + step_h * 0.5, p.z), _mats["metal"], "metal")


func _add_streetlamp(pos: Vector3, rot_y_deg: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation_degrees.y = rot_y_deg
	add_child(root)

	# Pole + Arm
	var pole := MeshInstance3D.new()
	var pcyl := CylinderMesh.new()
	pcyl.top_radius = 0.08
	pcyl.bottom_radius = 0.14
	pcyl.height = 7.2
	pole.mesh = pcyl
	pole.position = Vector3(0, 3.6, 0)
	pole.material_override = _mats["dark_steel"]
	root.add_child(pole)

	var arm := MeshInstance3D.new()
	var abox := BoxMesh.new()
	abox.size = Vector3(0.12, 0.12, 1.8)
	arm.mesh = abox
	arm.position = Vector3(0, 7.1, 0.85)
	arm.material_override = _mats["dark_steel"]
	root.add_child(arm)

	# Glowing sodium-vapor bulb
	var bulb := MeshInstance3D.new()
	var bmesh := BoxMesh.new()
	bmesh.size = Vector3(0.32, 0.1, 0.55)
	bulb.mesh = bmesh
	bulb.position = Vector3(0, 7.0, 1.65)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(1.0, 0.82, 0.52)
	bmat.emission_enabled = true
	bmat.emission = Color(1.0, 0.72, 0.35)
	bmat.emission_energy_multiplier = 7.0
	bulb.material_override = bmat
	root.add_child(bulb)

	# Volumetric-look translucent light cone + fast non-shadow SpotLight3D
	var cone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.25
	cm.bottom_radius = 3.2
	cm.height = 6.8
	cm.radial_segments = 12
	cone.mesh = cm
	cone.position = Vector3(0, 3.6, 1.65)
	var cmat := StandardMaterial3D.new()
	cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cmat.albedo_color = Color(1.0, 0.78, 0.48, 0.055)
	cmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	cmat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	cone.material_override = cmat
	root.add_child(cone)

	var spot := SpotLight3D.new()
	spot.position = Vector3(0, 6.9, 1.65)
	spot.rotation_degrees.x = -90.0
	spot.light_color = Color(1.0, 0.76, 0.44)
	spot.light_energy = 5.5
	spot.spot_range = 24.0
	spot.spot_angle = 55.0
	spot.spot_attenuation = 1.15
	spot.shadow_enabled = false
	spot.distance_fade_enabled = true
	spot.distance_fade_begin = 32.0
	spot.distance_fade_length = 12.0
	root.add_child(spot)
	if _weather != null:
		_weather.street_lights.append(spot)
		_weather.street_lights.append(cone)


func _add_indoor_lamp(pos: Vector3, tint: Color, energy: float, flicker: bool) -> void:
	var lamp_body := StaticBody3D.new()
	lamp_body.set_script(InteractableScript)
	lamp_body.kind = "lamp"
	lamp_body.position = pos
	add_child(lamp_body)

	var fixture := MeshInstance3D.new()
	var fbox := BoxMesh.new()
	fbox.size = Vector3(1.1, 0.12, 0.28)
	fixture.mesh = fbox
	var emat := StandardMaterial3D.new()
	emat.albedo_color = tint
	emat.emission_enabled = true
	emat.emission = tint
	emat.emission_energy_multiplier = 6.0
	fixture.material_override = emat
	lamp_body.add_child(fixture)

	var col := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(1.1, 0.25, 0.35)
	col.shape = sh
	lamp_body.add_child(col)

	var omni := OmniLight3D.new()
	omni.position = Vector3(0, -0.35, 0)
	omni.light_color = tint
	omni.light_energy = energy * 0.85
	omni.omni_range = 17.5
	omni.omni_attenuation = 1.25
	omni.shadow_enabled = false
	omni.distance_fade_enabled = true
	omni.distance_fade_begin = 28.0
	omni.distance_fade_length = 10.0
	lamp_body.add_child(omni)

	lamp_body.linked_lights.append(omni)
	lamp_body.linked_emissives.append(fixture)
	_warehouse_lights.append(omni)
	_warehouse_emissives.append(fixture)
	if flicker:
		_flicker_lights.append(omni)


func _add_power_breaker(pos: Vector3, rot_y_deg: float) -> void:
	var sb := StaticBody3D.new()
	sb.set_script(InteractableScript)
	sb.kind = "breaker"
	sb.position = pos
	sb.rotation_degrees.y = rot_y_deg
	sb.set_meta("surface", "metal")
	sb.linked_lights = _warehouse_lights
	sb.linked_emissives = _warehouse_emissives
	add_child(sb)

	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.55, 0.72, 0.22)
	box.mesh = bm
	box.material_override = _mats["hazard"]
	sb.add_child(box)

	var led := MeshInstance3D.new()
	var lbm := BoxMesh.new()
	lbm.size = Vector3(0.12, 0.08, 0.05)
	led.mesh = lbm
	led.position = Vector3(0, 0.18, 0.12)
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color(1.0, 0.2, 0.1)
	lmat.emission_enabled = true
	lmat.emission = Color(1.0, 0.15, 0.08)
	lmat.emission_energy_multiplier = 6.0
	led.material_override = lmat
	sb.add_child(led)
	sb.linked_emissives.append(led)

	var col := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.6, 0.8, 0.35)
	col.shape = sh
	sb.add_child(col)


func _add_intel_laptop(pos: Vector3) -> void:
	GameManager.intel_position = pos
	# Tactical table
	_add_static_box(Vector3(1.5, 0.82, 0.85), pos + Vector3(0, 0.41, 0), _mats["dark_steel"], "metal")

	var sb := StaticBody3D.new()
	sb.set_script(InteractableScript)
	sb.kind = "intel"
	sb.position = pos + Vector3(0, 0.86, 0)
	sb.set_meta("surface", "metal")
	add_child(sb)

	# Laptop base
	var base := MeshInstance3D.new()
	var bbm := BoxMesh.new()
	bbm.size = Vector3(0.46, 0.04, 0.34)
	base.mesh = bbm
	base.material_override = _mats["dark_steel"]
	sb.add_child(base)

	# Glowing tactical screen
	var screen := MeshInstance3D.new()
	var sbm := BoxMesh.new()
	sbm.size = Vector3(0.44, 0.30, 0.03)
	screen.mesh = sbm
	screen.position = Vector3(0, 0.16, -0.15)
	screen.rotation_degrees.x = -14.0
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.18, 0.65, 1.0)
	smat.emission_enabled = true
	smat.emission = Color(0.12, 0.62, 1.0)
	smat.emission_energy_multiplier = 5.5
	screen.material_override = smat
	sb.add_child(screen)
	sb.linked_emissives.append(screen)

	var glow := OmniLight3D.new()
	glow.position = Vector3(0, 0.25, 0.05)
	glow.light_color = Color(0.25, 0.72, 1.0)
	glow.light_energy = 1.8
	glow.omni_range = 4.0
	sb.add_child(glow)

	var col := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.65, 0.55, 0.55)
	col.shape = sh
	sb.add_child(col)


func _add_ammo_crate(pos: Vector3) -> void:
	var sb := StaticBody3D.new()
	sb.set_script(InteractableScript)
	sb.kind = "ammo"
	sb.position = pos + Vector3(0, 0.24, 0)
	sb.set_meta("surface", "metal")
	add_child(sb)

	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.75, 0.42, 0.45)
	box.mesh = bm
	box.material_override = _mats["container_olive"]
	sb.add_child(box)

	var col := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.85, 0.55, 0.55)
	col.shape = sh
	sb.add_child(col)


func _spawn_ai(spawn_pos: Vector3, waypoints: Array) -> void:
	var ai := CharacterBody3D.new()
	ai.set_script(AIScript)
	ai.position = spawn_pos
	var pts: Array[Vector3] = []
	for w in waypoints:
		pts.append(w)
	ai.patrol_points = pts
	add_child(ai)


func _bake_navigation() -> void:
	var nav_mesh := NavigationMesh.new()
	nav_mesh.cell_size = 0.25
	nav_mesh.cell_height = 0.25
	nav_mesh.agent_radius = 0.5
	nav_mesh.agent_height = 1.75
	nav_mesh.agent_max_climb = 0.5
	nav_mesh.agent_max_slope = 48.0
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	_nav_region.navigation_mesh = nav_mesh
	# Bake asynchronously on worker thread so level startup is INSTANT!
	_nav_region.bake_navigation_mesh(true)
