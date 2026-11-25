extends CharacterBody3D
## Tactical Hostile AI with realistic vision (light/stealth aware), hearing,
## squad radio alerts, burst ballistics, procedural stride animation,
## localized headshot/body hitboxes, and physical elimination fall.

const ProjectileScript = preload("res://scripts/weapons/ballistic_projectile.gd")

enum State {
	PATROL,
	INVESTIGATE,
	COMBAT,
	RELOAD,
	DEAD,
}

var state: State = State.PATROL
var health: float = 100.0
var patrol_points: Array[Vector3] = []
var _patrol_idx: int = 0
var _last_known_pos: Vector3 = Vector3.ZERO
var _state_timer: float = 0.0
var _burst_remaining: int = 0
var _fire_timer: float = 0.0
var _mag_ammo: int = 24
var _strafe_dir: float = 1.0
var _strafe_timer: float = 2.0
var _walk_phase: float = 0.0
var _alerted_once: bool = false
var _dead_fall_dir: Vector3 = Vector3.BACK
var _dead_fall_progress: float = 0.0

var _nav_agent: NavigationAgent3D
var _body_root: Node3D
var _head_pivot: Node3D
var _left_leg: Node3D
var _right_leg: Node3D
var _arms_pivot: Node3D
var _muzzle_point: Marker3D
var _muzzle_light: OmniLight3D
var _headlamp: SpotLight3D
var _body_col: CollisionShape3D
var _muzzle_timer: float = 0.0


func _ready() -> void:
	add_to_group("hostiles")
	collision_layer = 1 << 2 # Layer 3: Enemy
	collision_mask = 1 | (1 << 1) | (1 << 2) | (1 << 3)

	_body_col = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.34
	cap.height = 1.78
	_body_col.shape = cap
	_body_col.position = Vector3(0, 0.89, 0)
	add_child(_body_col)

	_nav_agent = NavigationAgent3D.new()
	_nav_agent.path_desired_distance = 0.85
	_nav_agent.target_desired_distance = 1.1
	_nav_agent.radius = 0.42
	add_child(_nav_agent)

	_build_tactical_character()

	GameManager.register_hostile()
	GameManager.noise_emitted.connect(_on_noise_heard)

	if patrol_points.is_empty():
		patrol_points.append(global_position)
	_set_nav_target(patrol_points[0])


func _build_tactical_character() -> void:
	_body_root = Node3D.new()
	add_child(_body_root)

	var bdu_mat := StandardMaterial3D.new()
	bdu_mat.albedo_color = Color(0.14, 0.16, 0.14) # Dark tactical olive-charcoal BDU
	bdu_mat.roughness = 0.85

	var armor_mat := StandardMaterial3D.new()
	armor_mat.albedo_color = Color(0.08, 0.09, 0.10) # Ballistic plate carrier & helmet
	armor_mat.roughness = 0.55
	armor_mat.metallic = 0.15

	var visor_mat := StandardMaterial3D.new()
	visor_mat.albedo_color = Color(0.05, 0.07, 0.12)
	visor_mat.metallic = 0.75
	visor_mat.roughness = 0.15

	var gun_mat := StandardMaterial3D.new()
	gun_mat.albedo_color = Color(0.1, 0.1, 0.11)
	gun_mat.metallic = 0.8
	gun_mat.roughness = 0.35

	# Legs
	_left_leg = Node3D.new()
	_left_leg.position = Vector3(-0.14, 0.82, 0)
	_body_root.add_child(_left_leg)
	_make_part(_left_leg, Vector3(0.17, 0.82, 0.19), Vector3(0, -0.41, 0), bdu_mat)

	_right_leg = Node3D.new()
	_right_leg.position = Vector3(0.14, 0.82, 0)
	_body_root.add_child(_right_leg)
	_make_part(_right_leg, Vector3(0.17, 0.82, 0.19), Vector3(0, -0.41, 0), bdu_mat)

	# Torso + Ballistic Plate Carrier + Pouches
	_make_part(_body_root, Vector3(0.42, 0.56, 0.24), Vector3(0, 1.12, 0), bdu_mat)
	_make_part(_body_root, Vector3(0.46, 0.44, 0.29), Vector3(0, 1.15, 0), armor_mat)
	_make_part(_body_root, Vector3(0.32, 0.14, 0.08), Vector3(0, 1.03, -0.17), bdu_mat)

	# Head + Tactical Helmet + Visor + Dedicated Headshot Hitbox!
	_head_pivot = Node3D.new()
	_head_pivot.position = Vector3(0, 1.54, 0)
	_body_root.add_child(_head_pivot)
	_make_part(_head_pivot, Vector3(0.22, 0.24, 0.23), Vector3(0, 0.05, 0), bdu_mat)
	_make_part(_head_pivot, Vector3(0.26, 0.16, 0.28), Vector3(0, 0.12, 0.01), armor_mat)
	_make_part(_head_pivot, Vector3(0.21, 0.08, 0.05), Vector3(0, 0.06, -0.12), visor_mat)

	var head_hit := Area3D.new()
	head_hit.collision_layer = 1 << 2
	head_hit.collision_mask = 0
	head_hit.set_meta("is_head", true)
	var hs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.18
	hs.shape = sph
	hs.position = Vector3(0, 0.08, 0)
	head_hit.add_child(hs)
	_head_pivot.add_child(head_hit)

	# Helmet / Rifle Tactical Flashlight (visible sweeping through fog!)
	_headlamp = SpotLight3D.new()
	_headlamp.position = Vector3(0.11, 0.12, -0.16)
	_headlamp.light_color = Color(1.0, 0.92, 0.78)
	_headlamp.light_energy = 4.2
	_headlamp.light_volumetric_fog_energy = 2.0
	_headlamp.spot_range = 24.0
	_headlamp.spot_angle = 26.0
	_headlamp.shadow_enabled = false # Perf-friendly for multiple AI lights
	_head_pivot.add_child(_headlamp)

	# Arms & Assault Rifle
	_arms_pivot = Node3D.new()
	_arms_pivot.position = Vector3(0, 1.32, -0.05)
	_body_root.add_child(_arms_pivot)
	_make_part(_arms_pivot, Vector3(0.13, 0.13, 0.44), Vector3(0.25, -0.06, -0.18), bdu_mat)
	_make_part(_arms_pivot, Vector3(0.13, 0.13, 0.44), Vector3(-0.22, -0.08, -0.22), bdu_mat)
	# Rifle body + barrel
	_make_part(_arms_pivot, Vector3(0.06, 0.11, 0.68), Vector3(0.14, -0.06, -0.45), gun_mat)
	_make_part(_arms_pivot, Vector3(0.04, 0.18, 0.08), Vector3(0.14, -0.18, -0.42), gun_mat)

	_muzzle_point = Marker3D.new()
	_muzzle_point.position = Vector3(0.14, -0.05, -0.84)
	_arms_pivot.add_child(_muzzle_point)

	_muzzle_light = OmniLight3D.new()
	_muzzle_light.position = _muzzle_point.position
	_muzzle_light.light_color = Color(1.0, 0.72, 0.3)
	_muzzle_light.light_energy = 0.0
	_muzzle_light.omni_range = 8.0
	_arms_pivot.add_child(_muzzle_light)


func _make_part(parent: Node3D, sz: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _physics_process(delta: float) -> void:
	if _muzzle_timer > 0.0:
		_muzzle_timer -= delta
		if _muzzle_timer <= 0.0:
			_muzzle_light.light_energy = 0.0

	if state == State.DEAD:
		if _dead_fall_progress < 1.0:
			_dead_fall_progress = minf(1.0, _dead_fall_progress + delta * 3.4)
			var ease_p := 1.0 - pow(1.0 - _dead_fall_progress, 3.0)
			_body_root.rotation.x = ease_p * deg_to_rad(86.0)
			_body_root.position.y = lerpf(0.0, 0.15, ease_p)
		return

	if not is_on_floor():
		velocity.y -= 11.0 * delta

	var can_see_player := _check_player_visibility()

	match state:
		State.PATROL:
			if can_see_player:
				_enter_combat(GameManager.player.global_position)
			else:
				_process_patrol(delta)

		State.INVESTIGATE:
			if can_see_player:
				_enter_combat(GameManager.player.global_position)
			else:
				_process_investigate(delta)

		State.COMBAT:
			_process_combat(delta, can_see_player)

		State.RELOAD:
			_state_timer -= delta
			velocity.x = lerpf(velocity.x, 0.0, delta * 6.0)
			velocity.z = lerpf(velocity.z, 0.0, delta * 6.0)
			if _state_timer <= 0.0:
				_mag_ammo = 24
				state = State.COMBAT

	move_and_slide()
	_animate_body(delta)


func _process_patrol(delta: float) -> void:
	if patrol_points.size() <= 1:
		velocity.x = lerpf(velocity.x, 0.0, delta * 5.0)
		velocity.z = lerpf(velocity.z, 0.0, delta * 5.0)
		# Gentle guard scan left/right
		_head_pivot.rotation.y = sin(Time.get_ticks_msec() * 0.0008 + float(get_instance_id() % 10)) * 0.55
		return

	var target := patrol_points[_patrol_idx]
	if global_position.distance_to(target) < 1.35:
		_state_timer += delta
		velocity.x = lerpf(velocity.x, 0.0, delta * 6.0)
		velocity.z = lerpf(velocity.z, 0.0, delta * 6.0)
		if _state_timer > 2.4:
			_state_timer = 0.0
			_patrol_idx = (_patrol_idx + 1) % patrol_points.size()
			_set_nav_target(patrol_points[_patrol_idx])
	else:
		_move_along_nav(1.75, delta)


func _process_investigate(delta: float) -> void:
	_state_timer -= delta
	if global_position.distance_to(_last_known_pos) > 2.2:
		_move_along_nav(2.65, delta)
	else:
		velocity.x = lerpf(velocity.x, 0.0, delta * 6.0)
		velocity.z = lerpf(velocity.z, 0.0, delta * 6.0)
		_head_pivot.rotation.y = sin(Time.get_ticks_msec() * 0.0025) * 0.85

	if _state_timer <= 0.0:
		state = State.PATROL
		_set_nav_target(patrol_points[_patrol_idx])


func _process_combat(delta: float, can_see: bool) -> void:
	if not is_instance_valid(GameManager.player) or GameManager.player_health <= 0.0:
		state = State.PATROL
		return

	var p_pos := GameManager.player.global_position
	if can_see:
		_last_known_pos = p_pos
		_state_timer = 7.5
		_face_point(p_pos, delta * 7.5)

		var dist := global_position.distance_to(p_pos)
		_strafe_timer -= delta
		if _strafe_timer <= 0.0:
			_strafe_dir = -1.0 if randf() < 0.5 else 1.0
			_strafe_timer = randf_range(1.4, 2.8)

		# Tactical spacing + lateral strafing
		var move_dir := Vector3.ZERO
		var right := global_transform.basis.x
		var forward := -global_transform.basis.z
		if dist > 18.0:
			move_dir = forward + right * _strafe_dir * 0.45
		elif dist < 7.0:
			move_dir = -forward * 0.6 + right * _strafe_dir * 0.8
		else:
			move_dir = right * _strafe_dir * 0.75

		move_dir = move_dir.normalized()
		velocity.x = lerpf(velocity.x, move_dir.x * 2.2, delta * 5.0)
		velocity.z = lerpf(velocity.z, move_dir.z * 2.2, delta * 5.0)

		# Controlled burst fire
		_fire_timer -= delta
		if _fire_timer <= 0.0:
			if _mag_ammo <= 0:
				state = State.RELOAD
				_state_timer = 2.1
				AudioManager.play_3d("weapon_reload", global_position, -10.0, 0.08, 25.0)
				return
			if _burst_remaining <= 0:
				_burst_remaining = randi_range(2, 4)
			_fire_at_player()
			_burst_remaining -= 1
			_fire_timer = 0.13 if _burst_remaining > 0 else randf_range(0.75, 1.45)
	else:
		# Advance cautiously toward last known position
		_state_timer -= delta
		_set_nav_target(_last_known_pos)
		_move_along_nav(3.15, delta)
		if _state_timer <= 0.0:
			state = State.INVESTIGATE
			_state_timer = 8.0


func _fire_at_player() -> void:
	_mag_ammo -= 1
	var target_pos := GameManager.player.global_position + Vector3(0.0, 1.32, 0.0)
	var dir := (target_pos - _muzzle_point.global_position).normalized()
	# Realistic human rifle spread (deadly if you stand still in the open, survivable with cover/lean!)
	var spread := 0.048
	dir = (dir + Vector3(
		randf_range(-spread, spread),
		randf_range(-spread * 0.7, spread * 0.7),
		randf_range(-spread, spread)
	)).normalized()

	var root := get_tree().current_scene
	if root:
		var proj := Node3D.new()
		proj.set_script(ProjectileScript)
		root.add_child(proj)
		proj.setup(_muzzle_point.global_position, dir, 220.0, 14.0, self, "enemy")

	_muzzle_light.light_energy = 6.5
	_muzzle_timer = 0.055
	AudioManager.play_3d("shot_indoor", _muzzle_point.global_position, -5.0, 0.1, 65.0)


func _check_player_visibility() -> bool:
	if not is_instance_valid(GameManager.player) or GameManager.player_health <= 0.0:
		return false
	var eye_pos := global_position + Vector3(0, 1.58, 0)
	var player_target := GameManager.player.global_position + Vector3(0, 1.25, 0)
	var to_player := player_target - eye_pos
	var dist := to_player.length()

	# Light-aware detection range (flashlight or laser gives away position in dark!)
	var max_vision := 24.0
	if GameManager.player_flashlight_on or GameManager.player_laser_on:
		max_vision = 36.0
	elif not GameManager.power_grid_online:
		max_vision = 14.0
	if dist > max_vision:
		return false

	var forward := -global_transform.basis.z
	var angle := rad_to_deg(forward.angle_to(to_player.normalized()))
	var fov_half := 72.0 if state == State.COMBAT else 56.0
	if angle > fov_half and dist > 3.2:
		return false

	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(eye_pos, player_target)
	query.collision_mask = 1 | (1 << 1) # World + Player
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	if not hit.is_empty() and hit["collider"] == GameManager.player:
		return true
	return false


func _on_noise_heard(pos: Vector3, radius: float, source_tag: String) -> void:
	if state == State.DEAD:
		return
	var d := global_position.distance_to(pos)
	if d > radius:
		return
	if source_tag == "gunshot" or source_tag == "bullet_impact":
		_last_known_pos = pos
		if state != State.COMBAT:
			state = State.INVESTIGATE
			_state_timer = 11.0
			_set_nav_target(pos)
			if not _alerted_once:
				_alerted_once = true
				AudioManager.play_3d("ai_alert", global_position, -7.0, 0.08, 40.0)
	elif d < radius * 0.75 and state == State.PATROL:
		_last_known_pos = pos
		state = State.INVESTIGATE
		_state_timer = 7.0
		_set_nav_target(pos)


func _enter_combat(target_pos: Vector3) -> void:
	state = State.COMBAT
	_last_known_pos = target_pos
	_state_timer = 8.0
	if not _alerted_once:
		_alerted_once = true
		AudioManager.play_3d("ai_alert", global_position, -4.0, 0.06, 48.0)
		GameManager.log_event("CONTACT // HOSTILE ENGAGING", "WARN")
		# Alert nearby squadmates via radio!
		for ally in get_tree().get_nodes_in_group("hostiles"):
			if ally != self and is_instance_valid(ally) and ally.has_method("receive_squad_alert"):
				if global_position.distance_to(ally.global_position) < 28.0:
					ally.receive_squad_alert(target_pos)


func receive_squad_alert(target_pos: Vector3) -> void:
	if state == State.DEAD or state == State.COMBAT:
		return
	_last_known_pos = target_pos
	state = State.INVESTIGATE
	_state_timer = 12.0
	_set_nav_target(target_pos)


func take_ballistic_hit(damage: float, _hit_pos: Vector3, hit_dir: Vector3, is_headshot: bool) -> void:
	if state == State.DEAD:
		return
	var mult := 2.6 if is_headshot else 1.0
	health -= damage * mult
	if is_headshot:
		GameManager.log_event("HEADSHOT CONFIRMED", "WARN")

	if health <= 0.0:
		_die(hit_dir)
	else:
		if is_instance_valid(GameManager.player):
			_enter_combat(GameManager.player.global_position)


func _die(hit_dir: Vector3) -> void:
	state = State.DEAD
	_dead_fall_dir = hit_dir
	velocity = Vector3.ZERO
	_body_col.set_deferred("disabled", true)
	collision_layer = 0
	collision_mask = 0
	_headlamp.light_energy = 0.8
	GameManager.on_hostile_eliminated()


func _set_nav_target(pos: Vector3) -> void:
	_nav_agent.target_position = pos


func _move_along_nav(speed: float, delta: float) -> void:
	var next_pos: Vector3 = _nav_agent.get_next_path_position()
	var dir := (next_pos - global_position)
	dir.y = 0.0
	if dir.length_squared() < 0.04:
		dir = (_nav_agent.target_position - global_position)
		dir.y = 0.0
	if dir.length_squared() > 0.04:
		dir = dir.normalized()
		velocity.x = lerpf(velocity.x, dir.x * speed, delta * 6.5)
		velocity.z = lerpf(velocity.z, dir.z * speed, delta * 6.5)
		_face_point(global_position + dir, delta * 6.0)
	else:
		velocity.x = lerpf(velocity.x, 0.0, delta * 6.0)
		velocity.z = lerpf(velocity.z, 0.0, delta * 6.0)


func _face_point(world_pt: Vector3, weight: float) -> void:
	var dir := world_pt - global_position
	dir.y = 0.0
	if dir.length_squared() < 0.001:
		return
	var target_yaw := atan2(-dir.x, -dir.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(weight, 0.0, 1.0))


func _animate_body(delta: float) -> void:
	var spd := Vector2(velocity.x, velocity.z).length()
	if spd > 0.25:
		_walk_phase += delta * spd * 3.4
		_left_leg.rotation.x = sin(_walk_phase) * 0.55
		_right_leg.rotation.x = -sin(_walk_phase) * 0.55
		_body_root.position.y = absf(sin(_walk_phase)) * 0.045
	else:
		_left_leg.rotation.x = lerpf(_left_leg.rotation.x, 0.0, delta * 8.0)
		_right_leg.rotation.x = lerpf(_right_leg.rotation.x, 0.0, delta * 8.0)
		_body_root.position.y = lerpf(_body_root.position.y, 0.0, delta * 8.0)

	# Raise weapon in combat
	var aim_pitch := 0.08 if state == State.COMBAT else -0.22
	_arms_pivot.rotation.x = lerpf(_arms_pivot.rotation.x, aim_pitch, delta * 7.0)
