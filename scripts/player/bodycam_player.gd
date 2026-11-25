extends CharacterBody3D
## Realistic First-Person Bodycam Controller
## Momentum-based locomotion, gait-synced surface footsteps, Q/E lean with wall check,
## stamina & BPM physiology, indoor/outdoor acoustic detection, and tactical weapon rig.

const WeaponScript = preload("res://scripts/weapons/tactical_weapon.gd")

@export var walk_speed: float = 3.2
@export var sprint_speed: float = 5.65
@export var crouch_speed: float = 1.75
@export var ads_speed: float = 2.05
@export var jump_velocity: float = 4.4
@export var ground_accel: float = 10.5
@export var ground_decel: float = 11.5

var _head_pivot: Node3D
var _lean_pivot: Node3D
var _camera: Camera3D
var _weapon: Node3D
var _standing_col: CollisionShape3D
var _floor_ray: RayCast3D
var _ceiling_ray: RayCast3D
var _interact_ray: RayCast3D
var _lean_left_ray: RayCast3D
var _lean_right_ray: RayCast3D

var _pitch: float = 0.0
var _lean_amount: float = 0.0
var _crouch_blend: float = 0.0
var _step_distance: float = 0.0
var _bob_time: float = 0.0
var _was_on_floor: bool = true
var _land_dip: float = 0.0
var _damage_punch: Vector3 = Vector3.ZERO
var _camera_recoil_pitch: float = 0.0
var _camera_recoil_yaw: float = 0.0
var _current_interactable: Node = null
var _is_dead: bool = false

const STAND_EYE_HEIGHT: float = 1.62
const CROUCH_EYE_HEIGHT: float = 1.02


func _ready() -> void:
	collision_layer = 1 << 1 # Layer 2: Player
	collision_mask = 1 | (1 << 2) | (1 << 3) # World + Enemy + Props

	# Capsule collider
	_standing_col = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.34
	cap.height = 1.82
	_standing_col.shape = cap
	_standing_col.position = Vector3(0, 0.91, 0)
	add_child(_standing_col)

	# Head & Lean hierarchy
	_head_pivot = Node3D.new()
	_head_pivot.position = Vector3(0, STAND_EYE_HEIGHT, 0)
	add_child(_head_pivot)

	_lean_pivot = Node3D.new()
	_head_pivot.add_child(_lean_pivot)

	# Bodycam wide-angle Camera3D
	_camera = Camera3D.new()
	_camera.fov = GameManager.base_fov
	_camera.near = 0.04
	_camera.far = 260.0
	_camera.current = true
	_lean_pivot.add_child(_camera)

	# Tactical Weapon attached to camera
	_weapon = Node3D.new()
	_weapon.set_script(WeaponScript)
	_weapon.setup(self)
	_camera.add_child(_weapon)
	_weapon.fired.connect(_on_weapon_fired)

	# Floor surface raycast (for footsteps)
	_floor_ray = RayCast3D.new()
	_floor_ray.position = Vector3(0, 0.3, 0)
	_floor_ray.target_position = Vector3(0, -0.65, 0)
	_floor_ray.collision_mask = 1 | (1 << 3)
	add_child(_floor_ray)

	# Ceiling raycast (indoor warehouse acoustic reverb & rain occlusion!)
	_ceiling_ray = RayCast3D.new()
	_ceiling_ray.position = Vector3(0, 1.5, 0)
	_ceiling_ray.target_position = Vector3(0, 16.0, 0)
	_ceiling_ray.collision_mask = 1
	add_child(_ceiling_ray)

	# Interact raycast
	_interact_ray = RayCast3D.new()
	_interact_ray.target_position = Vector3(0, 0, -2.8)
	_interact_ray.collision_mask = (1 << 4) | 1 # Interactable + World
	_interact_ray.collide_with_areas = true
	_camera.add_child(_interact_ray)

	# Lean wall-check raycasts
	_lean_left_ray = RayCast3D.new()
	_lean_left_ray.target_position = Vector3(-0.55, 0, 0)
	_lean_left_ray.collision_mask = 1
	_head_pivot.add_child(_lean_left_ray)

	_lean_right_ray = RayCast3D.new()
	_lean_right_ray.target_position = Vector3(0.55, 0, 0)
	_lean_right_ray.collision_mask = 1
	_head_pivot.add_child(_lean_right_ray)

	GameManager.player = self
	GameManager.player_damaged.connect(_on_player_damaged)
	GameManager.player_died.connect(_on_player_died)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if _is_dead or GameManager.is_paused:
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens: float = GameManager.mouse_sensitivity * (0.62 if _weapon.is_aiming else 1.0)
		var y_sign: float = 1.0 if GameManager.invert_y else -1.0
		rotate_y(-event.relative.x * sens)
		_pitch = clampf(_pitch + y_sign * event.relative.y * sens, deg_to_rad(-84.0), deg_to_rad(84.0))
		_weapon.add_look_sway(event.relative)

	if event.is_action_pressed("reload"):
		_weapon.start_reload()
	elif event.is_action_pressed("flashlight"):
		_weapon.toggle_flashlight()
	elif event.is_action_pressed("laser"):
		_weapon.toggle_laser()
	elif event.is_action_pressed("mag_check"):
		_weapon.check_magazine()
	elif event.is_action_pressed("fire_mode"):
		_weapon.toggle_fire_mode()
	elif event.is_action_pressed("nvg_toggle"):
		GameManager.nvg_enabled = not GameManager.nvg_enabled
		AudioManager.play_2d("bodycam_beep", -8.0, 0.04)
		GameManager.log_event("IR / NIGHT VISION: %s" % ("ENGAGED" if GameManager.nvg_enabled else "OFF"), "INFO")
		GameManager.notify_settings_changed()
	elif event.is_action_pressed("cycle_weather"):
		GameManager.cycle_weather_preset()
		AudioManager.play_2d("bodycam_beep", -10.0, 0.05)
	elif event.is_action_pressed("interact") or (event.is_action_pressed("lean_right") and _current_interactable != null):
		if _current_interactable != null and _current_interactable.has_method("interact"):
			_current_interactable.interact(self)


func _physics_process(delta: float) -> void:
	if _is_dead:
		# Bodycam falls sideways when officer is downed
		_head_pivot.position.y = lerpf(_head_pivot.position.y, 0.25, delta * 4.0)
		_lean_pivot.rotation.z = lerpf(_lean_pivot.rotation.z, 1.15, delta * 4.0)
		return

	# Indoor detection for warehouse reverb & rain-on-lens occlusion
	GameManager.player_indoors = _ceiling_ray.is_colliding()

	# Input movement vector
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var wish_dir := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	var is_crouching: bool = Input.is_action_pressed("crouch")
	var wants_aim: bool = Input.is_action_pressed("aim") and not bool(_weapon.is_reloading)
	var can_sprint: bool = Input.is_action_pressed("sprint") and input_dir.y < -0.25 and not is_crouching and not wants_aim and GameManager.player_stamina > 8.0
	var is_sprinting: bool = can_sprint and wish_dir.length_squared() > 0.1

	_weapon.is_aiming = wants_aim

	# Stamina & Heart Rate (BPM) simulation
	if is_sprinting:
		GameManager.player_stamina = maxf(0.0, GameManager.player_stamina - 22.0 * delta)
		GameManager.player_bpm = lerpf(GameManager.player_bpm, 142.0, delta * 1.4)
	else:
		var regen := 16.0 if wish_dir.length() < 0.1 else 9.0
		GameManager.player_stamina = minf(100.0, GameManager.player_stamina + regen * delta)
		var base_bpm := 72.0 + (1.0 - GameManager.player_health / GameManager.player_max_health) * 45.0
		GameManager.player_bpm = lerpf(GameManager.player_bpm, base_bpm, delta * 0.6)

	# Slow physiological health stabilization if not critically bleeding
	if GameManager.player_health > 15.0 and GameManager.player_health < GameManager.player_max_health:
		GameManager.player_health = minf(GameManager.player_max_health, GameManager.player_health + 1.2 * delta)

	# Gravity & Jump
	if not is_on_floor():
		velocity.y -= 11.2 * delta
	elif Input.is_action_just_pressed("jump") and not is_crouching and GameManager.player_stamina > 12.0:
		velocity.y = jump_velocity
		GameManager.player_stamina = maxf(0.0, GameManager.player_stamina - 10.0)

	# Horizontal speed & realistic inertia
	var target_speed := walk_speed
	if is_crouching:
		target_speed = crouch_speed
	elif is_sprinting:
		target_speed = sprint_speed
	elif wants_aim:
		target_speed = ads_speed

	var horiz_vel := Vector3(velocity.x, 0.0, velocity.z)
	var target_vel := wish_dir * target_speed
	var accel := ground_accel if wish_dir.length_squared() > 0.01 else ground_decel
	if not is_on_floor():
		accel *= 0.25
	horiz_vel = horiz_vel.lerp(target_vel, clampf(accel * delta, 0.0, 1.0))
	velocity.x = horiz_vel.x
	velocity.z = horiz_vel.z

	var prev_y_vel := velocity.y
	move_and_slide()

	# Landing impact thud & bodycam dip
	if is_on_floor() and not _was_on_floor and prev_y_vel < -2.4:
		_land_dip = clampf(-prev_y_vel * 0.032, 0.04, 0.22)
		_trigger_footstep(true, false)
		GameManager.emit_noise(global_position, 14.0, "landing")
	_was_on_floor = is_on_floor()

	# Crouch collider & eye height smooth blend
	_crouch_blend = lerpf(_crouch_blend, 1.0 if is_crouching else 0.0, delta * 9.5)
	var cap: CapsuleShape3D = _standing_col.shape
	cap.height = lerpf(1.82, 1.18, _crouch_blend)
	_standing_col.position.y = cap.height * 0.5

	# Tactical Q/E Leaning with wall collision check
	var lean_target := 0.0
	if Input.is_action_pressed("lean_left") and not _lean_left_ray.is_colliding():
		lean_target = -1.0
	elif Input.is_action_pressed("lean_right") and _current_interactable == null and not _lean_right_ray.is_colliding():
		lean_target = 1.0
	_lean_amount = lerpf(_lean_amount, lean_target, delta * 9.0)

	# Realistic Bodycam Gait Headbob + Footstep Synchronization
	var flat_speed := Vector2(velocity.x, velocity.z).length()
	var bob_offset := Vector3.ZERO
	var bob_roll := 0.0
	if is_on_floor() and flat_speed > 0.25:
		var stride_len := 1.85 if is_sprinting else (1.25 if is_crouching else 1.55)
		_step_distance += flat_speed * delta
		_bob_time += delta * (11.5 if is_sprinting else (6.5 if is_crouching else 8.6))
		var amp := 0.042 if is_sprinting else (0.014 if is_crouching else 0.025)
		if wants_aim:
			amp *= 0.45
		bob_offset.y = sin(_bob_time * 2.0) * amp
		bob_offset.x = cos(_bob_time) * amp * 0.72
		bob_roll = cos(_bob_time) * (0.024 if is_sprinting else 0.011)
		if _step_distance >= stride_len:
			_step_distance = 0.0
			_trigger_footstep(is_sprinting, is_crouching)
	else:
		# Subtle idle breathing micro-motion (chest/helmet cam feel!)
		var t := Time.get_ticks_msec() * 0.001
		var b_rate := GameManager.player_bpm / 45.0
		bob_offset.y = sin(t * b_rate) * 0.0055
		bob_roll = cos(t * b_rate * 0.5) * 0.003

	_land_dip = lerpf(_land_dip, 0.0, delta * 9.0)
	_damage_punch = _damage_punch.lerp(Vector3.ZERO, delta * 7.5)
	_camera_recoil_pitch = lerpf(_camera_recoil_pitch, 0.0, delta * 10.0)
	_camera_recoil_yaw = lerpf(_camera_recoil_yaw, 0.0, delta * 10.0)

	# Apply head, lean, strafe tilt & camera recoil
	var eye_y := lerpf(STAND_EYE_HEIGHT, CROUCH_EYE_HEIGHT, _crouch_blend)
	_head_pivot.position = Vector3(0.0, eye_y - _land_dip, 0.0) + bob_offset

	var strafe_tilt := -input_dir.x * 0.022
	_lean_pivot.position.x = _lean_amount * 0.36
	_lean_pivot.rotation.z = -_lean_amount * 0.21 + bob_roll + strafe_tilt + _damage_punch.z
	_camera.rotation.x = clampf(_pitch + _camera_recoil_pitch + _damage_punch.x, deg_to_rad(-86.0), deg_to_rad(86.0))
	_camera.rotation.y = _camera_recoil_yaw + _damage_punch.y

	# Dynamic FOV (ADS zoom + sprint peripheral stretch)
	var target_fov: float = GameManager.base_fov
	if wants_aim:
		target_fov = GameManager.base_fov - 18.0
	elif is_sprinting:
		target_fov = GameManager.base_fov + 5.5
	_camera.fov = lerpf(_camera.fov, target_fov, delta * 10.0)

	# Weapon update & firing
	_weapon.update_weapon(delta, flat_speed, is_sprinting, is_crouching, GameManager.player_bpm)
	_weapon.try_fire(Input.is_action_just_pressed("fire"), Input.is_action_pressed("fire"))

	# Interactable detection
	_update_interact_prompt()


func _trigger_footstep(is_sprint: bool, is_crouch: bool) -> void:
	var surface := "concrete"
	if _floor_ray.is_colliding():
		var col := _floor_ray.get_collider()
		if col is Node and col.has_meta("surface"):
			surface = str(col.get_meta("surface"))
		# Rain creates wet puddle splashes outdoors on asphalt!
		if surface == "asphalt" and GameManager.weather_preset == GameManager.WeatherPreset.RAIN_STORM:
			surface = "puddle" if randf() < 0.55 else "concrete"
	AudioManager.play_footstep(surface, global_position, is_sprint, is_crouch)
	if is_sprint:
		GameManager.emit_noise(global_position, 16.0, "footstep_sprint")
	elif not is_crouch:
		GameManager.emit_noise(global_position, 6.5, "footstep_walk")


func _update_interact_prompt() -> void:
	var found: Node = null
	if _interact_ray.is_colliding():
		var c := _interact_ray.get_collider()
		if c is Node:
			if c.has_method("interact"):
				found = c
			elif c.get_parent() and c.get_parent().has_method("interact"):
				found = c.get_parent()
	if found != _current_interactable:
		_current_interactable = found
		if found != null and found.has_method("get_prompt"):
			GameManager.interact_prompt_changed.emit(found.get_prompt())
		else:
			GameManager.interact_prompt_changed.emit("")


func _on_weapon_fired(recoil_p: float, recoil_y: float) -> void:
	_pitch = clampf(_pitch + recoil_p * 0.65, deg_to_rad(-84.0), deg_to_rad(84.0))
	rotate_y(recoil_y * 0.55)
	_camera_recoil_pitch += recoil_p * 0.85
	_camera_recoil_yaw += recoil_y * 0.65


func _on_player_damaged(_hp: float, _max_hp: float) -> void:
	_damage_punch = Vector3(randf_range(-0.08, 0.08), randf_range(-0.06, 0.06), randf_range(-0.14, 0.14))


func _on_player_died() -> void:
	_is_dead = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
