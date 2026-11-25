extends Node3D
## Realistic Tactical MK-18 Carbine with procedural PBR geometry, holographic optic,
## weapon-mounted flashlight, real raycast laser sight, reciprocating bolt,
## brass shell ejection, realistic recoil/sway, and Bodycam free-aim inertia.

const ProjectileScript = preload("res://scripts/weapons/ballistic_projectile.gd")
const ShellScript = preload("res://scripts/weapons/shell_casing.gd")

signal fired(recoil_pitch: float, recoil_yaw: float)

# Weapon ballistics & handling
var mag_capacity: int = 30
var ammo_in_mag: int = 30
var reserve_mags: int = 4
var fire_rate: float = 0.092 # ~650 RPM
var full_auto: bool = false
var muzzle_velocity: float = 340.0
var bullet_damage: float = 42.0

var is_reloading: bool = false
var is_aiming: bool = false
var flashlight_on: bool = true
var laser_on: bool = false

var _fire_cooldown: float = 0.0
var _reload_timer: float = 0.0
var _recoil_offset: Vector3 = Vector3.ZERO
var _recoil_rot: Vector3 = Vector3.ZERO
var _sway_offset: Vector2 = Vector2.ZERO
var _free_aim_offset: Vector2 = Vector2.ZERO
var _bob_phase: float = 0.0
var _muzzle_flash_timer: float = 0.0

# Key transform targets (relative to Camera)
var hip_pos: Vector3 = Vector3(0.21, -0.22, -0.44)
var ads_pos: Vector3 = Vector3(0.0, -0.148, -0.34)
var sprint_pos: Vector3 = Vector3(0.14, -0.29, -0.37)
var reload_pos: Vector3 = Vector3(0.12, -0.36, -0.36)

# Internal nodes
var _weapon_pivot: Node3D
var _bolt_mesh: MeshInstance3D
var _mag_mesh: MeshInstance3D
var _mag_base_pos: Vector3 = Vector3(0, -0.105, -0.05)
var _draw_anim: float = 1.0 # Smooth weapon raise animation on spawn
var _reload_duration: float = 1.55
var _muzzle_point: Marker3D
var _ejection_port: Marker3D
var _flashlight: SpotLight3D
var _muzzle_light: OmniLight3D
var _muzzle_flash_mesh: MeshInstance3D
var _laser_beam: MeshInstance3D
var _laser_dot: MeshInstance3D
var _laser_ray: RayCast3D
var _smoke_particles: CPUParticles3D
var _owner_player: Node3D


func setup(player_node: Node3D) -> void:
	_owner_player = player_node


func _ready() -> void:
	position = hip_pos
	_build_weapon_model()


func _build_weapon_model() -> void:
	_weapon_pivot = Node3D.new()
	add_child(_weapon_pivot)

	# Load PBR tactical polymer textures if available
	var poly_mat := StandardMaterial3D.new()
	poly_mat.albedo_color = Color(0.15, 0.16, 0.17)
	poly_mat.metallic = 0.25
	poly_mat.roughness = 0.56
	if ResourceLoader.exists("res://assets/textures/tactical_polymer_albedo.png"):
		poly_mat.albedo_texture = load("res://assets/textures/tactical_polymer_albedo.png")
		poly_mat.normal_enabled = true
		poly_mat.normal_texture = load("res://assets/textures/tactical_polymer_normal.png")
		poly_mat.roughness_texture = load("res://assets/textures/tactical_polymer_roughness.png")
		poly_mat.uv1_scale = Vector3(3.0, 3.0, 3.0)

	var metal_mat := StandardMaterial3D.new()
	metal_mat.albedo_color = Color(0.11, 0.12, 0.13)
	metal_mat.metallic = 0.85
	metal_mat.roughness = 0.34

	var fde_mat := StandardMaterial3D.new()
	fde_mat.albedo_color = Color(0.32, 0.28, 0.21) # Flat Dark Earth rail/stock accents
	fde_mat.metallic = 0.1
	fde_mat.roughness = 0.68

	# Upper & lower receiver
	_add_box(_weapon_pivot, Vector3(0.052, 0.068, 0.28), Vector3(0, 0, 0), metal_mat)
	# Rail handguard (M-LOK quad rail style)
	_add_box(_weapon_pivot, Vector3(0.056, 0.058, 0.28), Vector3(0, 0.008, -0.27), fde_mat)
	# Top Picatinny rail
	_add_box(_weapon_pivot, Vector3(0.026, 0.012, 0.52), Vector3(0, 0.042, -0.14), metal_mat)
	# Barrel + Tactical Suppressor/Flash hider
	var barrel := MeshInstance3D.new()
	var bcyl := CylinderMesh.new()
	bcyl.top_radius = 0.011
	bcyl.bottom_radius = 0.012
	bcyl.height = 0.24
	barrel.mesh = bcyl
	barrel.rotation_degrees.x = 90.0
	barrel.position = Vector3(0, 0.01, -0.49)
	barrel.material_override = metal_mat
	_weapon_pivot.add_child(barrel)

	var supp := MeshInstance3D.new()
	var scyl := CylinderMesh.new()
	scyl.top_radius = 0.021
	scyl.bottom_radius = 0.021
	scyl.height = 0.16
	supp.mesh = scyl
	supp.rotation_degrees.x = 90.0
	supp.position = Vector3(0, 0.01, -0.58)
	supp.material_override = poly_mat
	_weapon_pivot.add_child(supp)

	# Curved tactical magazine (animated during reload!)
	_mag_mesh = _add_box(_weapon_pivot, Vector3(0.036, 0.16, 0.072), _mag_base_pos, poly_mat)
	_mag_mesh.rotation_degrees.x = 12.0

	# Pistol grip & Stock
	var grip := _add_box(_weapon_pivot, Vector3(0.036, 0.11, 0.045), Vector3(0, -0.075, 0.095), poly_mat)
	grip.rotation_degrees.x = -22.0
	_add_box(_weapon_pivot, Vector3(0.042, 0.085, 0.21), Vector3(0, -0.005, 0.23), fde_mat)

	# Reciprocating bolt carrier (visible on right side)
	_bolt_mesh = _add_box(_weapon_pivot, Vector3(0.014, 0.022, 0.085), Vector3(0.025, 0.012, -0.01), metal_mat)

	# Holographic Optic (EOTech EXPS3 style) aligned at Y = +0.148 for crisp ADS
	var optic_root := Node3D.new()
	optic_root.position = Vector3(0, 0.092, -0.04)
	_weapon_pivot.add_child(optic_root)
	# Optic base + side hood + top hood
	_add_box(optic_root, Vector3(0.048, 0.022, 0.09), Vector3(0, -0.032, 0), metal_mat)
	_add_box(optic_root, Vector3(0.007, 0.056, 0.075), Vector3(-0.024, 0.006, 0), metal_mat)
	_add_box(optic_root, Vector3(0.007, 0.056, 0.075), Vector3(0.024, 0.006, 0), metal_mat)
	_add_box(optic_root, Vector3(0.054, 0.007, 0.075), Vector3(0, 0.034, 0), metal_mat)

	# Glowing red holographic reticle dot (only bright when looking straight through!)
	var reticle := MeshInstance3D.new()
	var rquad := QuadMesh.new()
	rquad.size = Vector2(0.0042, 0.0042)
	reticle.mesh = rquad
	reticle.position = Vector3(0, 0.008, -0.01)
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.albedo_color = Color(1.0, 0.12, 0.08, 0.95)
	rmat.emission_enabled = true
	rmat.emission = Color(1.0, 0.08, 0.05)
	rmat.emission_energy_multiplier = 6.0
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.no_depth_test = false
	reticle.material_override = rmat
	optic_root.add_child(reticle)

	# Side-mounted PEQ-15 Laser Module & Tactical Flashlight body
	_add_box(_weapon_pivot, Vector3(0.028, 0.028, 0.11), Vector3(0.038, 0.012, -0.31), fde_mat)
	_add_box(_weapon_pivot, Vector3(0.024, 0.024, 0.095), Vector3(-0.036, 0.008, -0.33), metal_mat)

	# Tactical Weapon Flashlight (fast non-shadow SpotLight3D for steady 60 FPS)
	_flashlight = SpotLight3D.new()
	_flashlight.position = Vector3(-0.036, 0.008, -0.39)
	_flashlight.light_color = Color(0.95, 0.97, 1.0)
	_flashlight.light_energy = 6.2
	_flashlight.spot_range = 38.0
	_flashlight.spot_attenuation = 1.25
	_flashlight.spot_angle = 32.0
	_flashlight.spot_angle_attenuation = 1.7
	_flashlight.shadow_enabled = false
	_weapon_pivot.add_child(_flashlight)

	# Real RayCast Laser Sight
	_laser_ray = RayCast3D.new()
	_laser_ray.position = Vector3(0.038, 0.012, -0.37)
	_laser_ray.target_position = Vector3(0, 0, -65.0)
	_laser_ray.collision_mask = 1 | (1 << 2) | (1 << 3)
	_weapon_pivot.add_child(_laser_ray)

	_laser_beam = MeshInstance3D.new()
	var lcyl := CylinderMesh.new()
	lcyl.top_radius = 0.0014
	lcyl.bottom_radius = 0.0014
	lcyl.height = 1.0
	_laser_beam.mesh = lcyl
	_laser_beam.rotation_degrees.x = 90.0
	var lmat := StandardMaterial3D.new()
	lmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lmat.albedo_color = Color(1.0, 0.08, 0.08, 0.35)
	lmat.emission_enabled = true
	lmat.emission = Color(1.0, 0.05, 0.05)
	lmat.emission_energy_multiplier = 4.5
	lmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_laser_beam.material_override = lmat
	_laser_beam.visible = false
	_weapon_pivot.add_child(_laser_beam)

	_laser_dot = MeshInstance3D.new()
	var dot_s := SphereMesh.new()
	dot_s.radius = 0.018
	dot_s.height = 0.036
	_laser_dot.mesh = dot_s
	var dot_mat := StandardMaterial3D.new()
	dot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot_mat.albedo_color = Color(1.0, 0.12, 0.08)
	dot_mat.emission_enabled = true
	dot_mat.emission = Color(1.0, 0.05, 0.05)
	dot_mat.emission_energy_multiplier = 12.0
	_laser_dot.material_override = dot_mat
	_laser_dot.top_level = true
	_laser_dot.visible = false
	_weapon_pivot.add_child(_laser_dot)

	# Muzzle & Ejection port markers
	_muzzle_point = Marker3D.new()
	_muzzle_point.position = Vector3(0, 0.01, -0.68)
	_weapon_pivot.add_child(_muzzle_point)

	_ejection_port = Marker3D.new()
	_ejection_port.position = Vector3(0.036, 0.015, -0.01)
	_weapon_pivot.add_child(_ejection_port)

	# Muzzle Flash light & star quad
	_muzzle_light = OmniLight3D.new()
	_muzzle_light.position = _muzzle_point.position + Vector3(0, 0, -0.06)
	_muzzle_light.light_color = Color(1.0, 0.72, 0.35)
	_muzzle_light.light_energy = 0.0
	_muzzle_light.omni_range = 11.0
	_weapon_pivot.add_child(_muzzle_light)

	_muzzle_flash_mesh = MeshInstance3D.new()
	var fquad := QuadMesh.new()
	fquad.size = Vector2(0.18, 0.18)
	_muzzle_flash_mesh.mesh = fquad
	_muzzle_flash_mesh.position = _muzzle_point.position + Vector3(0, 0, -0.04)
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.albedo_color = Color(1.0, 0.85, 0.45, 0.9)
	fmat.emission_enabled = true
	fmat.emission = Color(1.0, 0.72, 0.25)
	fmat.emission_energy_multiplier = 8.0
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_muzzle_flash_mesh.material_override = fmat
	_muzzle_flash_mesh.visible = false
	_weapon_pivot.add_child(_muzzle_flash_mesh)

	# Muzzle gunpowder smoke puff
	_smoke_particles = CPUParticles3D.new()
	_smoke_particles.position = _muzzle_point.position
	_smoke_particles.one_shot = true
	_smoke_particles.explosiveness = 0.85
	_smoke_particles.amount = 8
	_smoke_particles.lifetime = 0.65
	_smoke_particles.direction = Vector3(0, 0.3, -1.0)
	_smoke_particles.spread = 28.0
	_smoke_particles.initial_velocity_min = 0.5
	_smoke_particles.initial_velocity_max = 1.6
	_smoke_particles.gravity = Vector3(0, 0.45, 0)
	var smesh := SphereMesh.new()
	smesh.radius = 0.032
	smesh.height = 0.064
	_smoke_particles.mesh = smesh
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.75, 0.76, 0.78, 0.24)
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_smoke_particles.material_override = smat
	_weapon_pivot.add_child(_smoke_particles)


func _add_box(parent: Node3D, sz: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func add_look_sway(mouse_rel: Vector2) -> void:
	var mult := 0.28 if is_aiming else 1.0
	_sway_offset.x = clampf(_sway_offset.x - mouse_rel.x * 0.00055 * mult, -0.055, 0.055)
	_sway_offset.y = clampf(_sway_offset.y + mouse_rel.y * 0.00045 * mult, -0.045, 0.045)
	# Bodycam / Unrecord free-aim deadzone feel when hip-firing
	if not is_aiming:
		_free_aim_offset.x = clampf(_free_aim_offset.x + mouse_rel.x * 0.0006, -0.095, 0.095)
		_free_aim_offset.y = clampf(_free_aim_offset.y + mouse_rel.y * 0.0006, -0.07, 0.07)


func update_weapon(delta: float, move_speed: float, is_sprinting: bool, is_crouching: bool, bpm: float) -> void:
	_fire_cooldown = maxf(0.0, _fire_cooldown - delta)

	# Reload state machine
	if is_reloading:
		_reload_timer -= delta
		if _reload_timer <= 0.0:
			is_reloading = false
			if reserve_mags > 0:
				reserve_mags -= 1
				ammo_in_mag = mag_capacity
				GameManager.mag_status_displayed.emit("MAGAZINE RELOADED // FULL (%d RDS)" % ammo_in_mag)
				GameManager.log_event("WEAPON RELOADED", "INFO")

	# Muzzle flash decay
	if _muzzle_flash_timer > 0.0:
		_muzzle_flash_timer -= delta
		if _muzzle_flash_timer <= 0.0:
			_muzzle_light.light_energy = 0.0
			_muzzle_flash_mesh.visible = false

	# Bolt return spring
	_bolt_mesh.position.z = lerpf(_bolt_mesh.position.z, -0.01, delta * 28.0)

	# Recoil & sway spring recovery
	_recoil_offset = _recoil_offset.lerp(Vector3.ZERO, delta * 13.0)
	_recoil_rot = _recoil_rot.lerp(Vector3.ZERO, delta * 11.5)
	_sway_offset = _sway_offset.lerp(Vector2.ZERO, delta * 8.5)
	var free_aim_decay := 12.0 if is_aiming else 4.2
	_free_aim_offset = _free_aim_offset.lerp(Vector2.ZERO, delta * free_aim_decay)

	# Organic breathing + walking weapon bob
	var breath_rate := clampf(bpm / 45.0, 1.3, 3.2)
	var t := Time.get_ticks_msec() * 0.001
	var breath_amp := 0.0018 if is_aiming else 0.0042
	if is_crouching:
		breath_amp *= 0.65
	var breath := Vector3(
		sin(t * breath_rate * 0.8) * breath_amp,
		cos(t * breath_rate * 1.6) * breath_amp * 1.2,
		0.0
	)

	var bob := Vector3.ZERO
	if move_speed > 0.25:
		_bob_phase += delta * (11.5 if is_sprinting else 7.8)
		var bamp := (0.0035 if is_aiming else 0.014) * clampf(move_speed / 4.0, 0.2, 1.5)
		bob = Vector3(cos(_bob_phase) * bamp, absf(sin(_bob_phase)) * bamp * 1.15, 0.0)

	# Draw / Equip raise animation on spawn
	if _draw_anim > 0.0:
		_draw_anim = maxf(0.0, _draw_anim - delta * 2.4)

	# Target weapon pose + 4-stage keyframed tactical reload animation!
	var target_pos: Vector3 = hip_pos
	var target_rot: Vector3 = Vector3(
		-_free_aim_offset.y * 0.85,
		-_free_aim_offset.x * 1.05,
		-_sway_offset.x * 1.9
	)
	var target_mag_pos: Vector3 = _mag_base_pos
	var target_bolt_z: float = -0.01

	if is_reloading:
		var prog: float = clampf(1.0 - (_reload_timer / _reload_duration), 0.0, 1.0)
		if prog < 0.25:
			# Stage 1: Tilt rifle & release old magazine downward
			var u := prog / 0.25
			target_pos = hip_pos.lerp(Vector3(0.11, -0.24, -0.35), u)
			target_rot = Vector3(0.24 * u, 0.36 * u, -0.62 * u)
			target_mag_pos = _mag_base_pos + Vector3(0.0, -0.26 * u, 0.02 * u)
		elif prog < 0.55:
			# Stage 2: Bring fresh magazine up into magwell
			var u := (prog - 0.25) / 0.30
			target_pos = Vector3(0.11, -0.24, -0.35)
			target_rot = Vector3(0.24, 0.36, -0.62)
			target_mag_pos = _mag_base_pos + Vector3(0.0, lerpf(-0.28, 0.0, u), 0.0)
		elif prog < 0.80:
			# Stage 3: Magazine slap bump + pull charging handle / bolt back
			var u := (prog - 0.55) / 0.25
			var slap := sin(minf(u * 2.5, 1.0) * PI) * 0.024
			target_pos = Vector3(0.13, -0.22 + slap, -0.36)
			target_rot = Vector3(0.18 + slap * 2.0, 0.28, -0.45)
			target_bolt_z = lerpf(-0.01, 0.065, u)
		else:
			# Stage 4: Slam bolt forward & return rifle smoothly to ready
			var u := (prog - 0.80) / 0.20
			target_pos = Vector3(0.13, -0.22, -0.36).lerp(hip_pos, u)
			target_rot = Vector3(0.18, 0.28, -0.45).lerp(Vector3.ZERO, u)
			target_bolt_z = -0.01
	elif is_sprinting and not is_aiming:
		target_pos = sprint_pos
		target_rot = Vector3(-0.26, 0.52, 0.30)
	elif is_aiming:
		target_pos = ads_pos
		target_rot = Vector3(0.0, 0.0, -_sway_offset.x * 0.6)

	# Apply smooth weapon draw-in curve
	if _draw_anim > 0.0:
		var ease_d := _draw_anim * _draw_anim
		target_pos += Vector3(0.05 * ease_d, -0.28 * ease_d, 0.12 * ease_d)
		target_rot += Vector3(-0.55 * ease_d, 0.25 * ease_d, 0.15 * ease_d)

	_mag_mesh.position = _mag_mesh.position.lerp(target_mag_pos, delta * 18.0)
	if is_reloading:
		_bolt_mesh.position.z = lerpf(_bolt_mesh.position.z, target_bolt_z, delta * 24.0)

	var final_pos := target_pos + _recoil_offset + breath + bob + Vector3(_sway_offset.x, _sway_offset.y, 0.0)
	var final_rot := target_rot + _recoil_rot

	position = position.lerp(final_pos, delta * 15.0)
	rotation = rotation.lerp(final_rot, delta * 15.0)

	# Update Flashlight & Laser Sight
	_flashlight.visible = flashlight_on
	_update_laser()


func _update_laser() -> void:
	if not laser_on or is_reloading:
		_laser_beam.visible = false
		_laser_dot.visible = false
		return

	_laser_ray.force_raycast_update()
	_laser_beam.visible = true
	var start_local := _laser_ray.position
	var dist := 60.0
	if _laser_ray.is_colliding():
		var hit_p := _laser_ray.get_collision_point()
		dist = _laser_ray.global_position.distance_to(hit_p)
		_laser_dot.visible = true
		_laser_dot.global_position = hit_p + _laser_ray.get_collision_normal() * 0.015
	else:
		_laser_dot.visible = false

	_laser_beam.scale = Vector3(1.0, dist, 1.0)
	_laser_beam.position = start_local + Vector3(0, 0, -dist * 0.5)


func try_fire(wants_fire_just_pressed: bool, wants_fire_held: bool) -> void:
	if is_reloading or _fire_cooldown > 0.0:
		return
	var should_shoot: bool = wants_fire_held if full_auto else wants_fire_just_pressed
	if not should_shoot:
		return

	if ammo_in_mag <= 0:
		if wants_fire_just_pressed:
			AudioManager.play_2d("dry_fire", -6.0, 0.08, &"SFX_Outdoor")
			GameManager.mag_status_displayed.emit("CLICK // MAGAZINE EMPTY — PRESS [R]")
			_fire_cooldown = 0.22
		return

	_execute_shot()


func _execute_shot() -> void:
	ammo_in_mag -= 1
	_fire_cooldown = fire_rate

	# Converge muzzle shot accurately toward camera aim point
	var cam := get_viewport().get_camera_3d()
	var dir: Vector3 = -_muzzle_point.global_transform.basis.z
	if cam != null:
		var cam_from: Vector3 = cam.global_position
		var cam_fwd: Vector3 = -cam.global_transform.basis.z
		var aim_target: Vector3 = cam_from + cam_fwd * 100.0
		var space := get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(cam_from + cam_fwd * 0.35, aim_target)
		q.collision_mask = 1 | (1 << 2) | (1 << 3)
		q.collide_with_areas = true
		var h := space.intersect_ray(q)
		if not h.is_empty():
			aim_target = h["position"]
		dir = (aim_target - _muzzle_point.global_position).normalized()
	var spread := 0.0015 if is_aiming else 0.0085
	dir = (dir + Vector3(
		randf_range(-spread, spread),
		randf_range(-spread, spread),
		randf_range(-spread, spread)
	)).normalized()

	var root := get_tree().current_scene
	if root:
		var proj := Node3D.new()
		proj.set_script(ProjectileScript)
		root.add_child(proj)
		proj.setup(_muzzle_point.global_position, dir, muzzle_velocity, bullet_damage, _owner_player, "player")

		# Eject physical spinning brass shell casing!
		var shell := RigidBody3D.new()
		shell.set_script(ShellScript)
		root.add_child(shell)
		shell.global_position = _ejection_port.global_position
		shell.global_rotation = _ejection_port.global_rotation
		var eject_dir := _ejection_port.global_transform.basis.x * randf_range(1.6, 2.5) \
			+ _ejection_port.global_transform.basis.y * randf_range(0.9, 1.5) \
			+ _ejection_port.global_transform.basis.z * randf_range(-0.4, 0.4)
		shell.linear_velocity = eject_dir
		shell.angular_velocity = Vector3(randf_range(-18, 18), randf_range(-18, 18), randf_range(-18, 18))

	# Recoil physics (muzzle climb + rearward impulse + bolt blowback)
	var r_mult := 0.62 if is_aiming else 1.0
	_recoil_offset += Vector3(randf_range(-0.006, 0.006), 0.005, 0.048) * r_mult
	_recoil_rot += Vector3(randf_range(0.06, 0.095), randf_range(-0.025, 0.025), randf_range(-0.04, 0.04)) * r_mult
	_bolt_mesh.position.z = 0.045

	# Muzzle flash & gunpowder smoke
	_muzzle_light.light_energy = 8.5
	_muzzle_flash_mesh.visible = true
	_muzzle_flash_mesh.rotation.z = randf() * TAU
	_muzzle_flash_timer = 0.042
	_smoke_particles.restart()
	_smoke_particles.emitting = true

	# Audio (indoor warehouse echo vs outdoor crack!)
	var shot_key := "shot_indoor" if GameManager.player_indoors else "shot_outdoor"
	AudioManager.play_3d(shot_key, _muzzle_point.global_position, -2.0, 0.06, 85.0)
	GameManager.emit_noise(global_position, 52.0, "gunshot")

	if GameManager.hud and GameManager.hud.has_method("trigger_shutter_flash"):
		GameManager.hud.trigger_shutter_flash(0.55)

	fired.emit(randf_range(0.015, 0.026) * r_mult, randf_range(-0.01, 0.01) * r_mult)


func start_reload() -> void:
	if is_reloading or ammo_in_mag >= mag_capacity:
		return
	if reserve_mags <= 0:
		GameManager.mag_status_displayed.emit("NO SPARE MAGAZINES LEFT")
		return
	is_reloading = true
	_reload_timer = 1.62
	AudioManager.play_2d("weapon_reload", -5.0, 0.03, &"SFX_Outdoor")
	GameManager.emit_noise(global_position, 9.0, "reload")
	GameManager.mag_status_displayed.emit("RELOADING...")


func toggle_flashlight() -> void:
	flashlight_on = not flashlight_on
	GameManager.player_flashlight_on = flashlight_on
	AudioManager.play_2d("flashlight_click", -8.0, 0.05)
	GameManager.log_event("TACTICAL LIGHT: %s" % ("ON" if flashlight_on else "OFF"), "INFO")


func toggle_laser() -> void:
	laser_on = not laser_on
	GameManager.player_laser_on = laser_on
	AudioManager.play_2d("flashlight_click", -10.0, 0.08)
	GameManager.log_event("PEQ-15 LASER: %s" % ("ACTIVE" if laser_on else "STANDBY"), "INFO")


func toggle_fire_mode() -> void:
	full_auto = not full_auto
	AudioManager.play_2d("dry_fire", -11.0, 0.1)
	var mode_str := "FULL AUTO" if full_auto else "SEMI-AUTO"
	GameManager.mag_status_displayed.emit("SELECTOR: %s" % mode_str)


func check_magazine() -> void:
	var ratio := float(ammo_in_mag) / float(mag_capacity)
	var desc := "EMPTY"
	if ratio >= 0.95:
		desc = "FULL (~30)"
	elif ratio >= 0.65:
		desc = "HEAVY (~2/3)"
	elif ratio >= 0.35:
		desc = "HALF (~1/2)"
	elif ammo_in_mag > 0:
		desc = "LIGHT (<10)"
	AudioManager.play_2d("dry_fire", -13.0, 0.1)
	GameManager.mag_status_displayed.emit("MAG CHECK: %s  |  SPARE MAGS: %d" % [desc, reserve_mags])
