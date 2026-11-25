extends Node3D
## Realistic ballistic projectile with muzzle velocity, gravity drop, drag,
## swept raycast collision, surface-reactive impacts, and rigidbody impulse.

var velocity: Vector3 = Vector3.ZERO
var damage: float = 38.0
var shooter: Node = null
var shooter_tag: String = "player"
var drag_coeff: float = 0.0008
var max_life: float = 2.6
var _age: float = 0.0
var _tracer: MeshInstance3D


func setup(start_pos: Vector3, direction: Vector3, speed: float, dmg: float, owner_node: Node, tag: String = "player") -> void:
	global_position = start_pos
	velocity = direction.normalized() * speed
	damage = dmg
	shooter = owner_node
	shooter_tag = tag


func _ready() -> void:
	# Subtle ballistic tracer streak
	_tracer = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.012, 0.012, 0.75)
	_tracer.mesh = box
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.88, 0.58, 0.85)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.78, 0.38)
	mat.emission_energy_multiplier = 4.0 if shooter_tag == "enemy" else 2.2
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_tracer.material_override = mat
	add_child(_tracer)
	if velocity.length_squared() > 0.01:
		look_at(global_position + velocity, Vector3.UP)


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= max_life:
		queue_free()
		return

	var prev_pos: Vector3 = global_position
	# Realistic ballistic gravity & aerodynamic drag
	velocity.y -= 9.81 * delta
	velocity *= maxf(0.0, 1.0 - drag_coeff * velocity.length() * delta)
	var next_pos: Vector3 = prev_pos + velocity * delta

	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(prev_pos, next_pos)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	# Collide with World(1), Player(2), Enemy(3), Props(4)
	query.collision_mask = 1 | (1 << 1) | (1 << 2) | (1 << 3)
	if is_instance_valid(shooter) and shooter is CollisionObject3D:
		query.exclude = [shooter.get_rid()]

	var hit: Dictionary = space.intersect_ray(query)
	if not hit.is_empty():
		_handle_impact(hit)
		queue_free()
		return

	global_position = next_pos
	if velocity.length_squared() > 0.1:
		look_at(global_position + velocity, Vector3.UP)


func _handle_impact(hit: Dictionary) -> void:
	var hit_pos: Vector3 = hit["position"]
	var hit_normal: Vector3 = hit["normal"]
	var collider: Object = hit["collider"]

	var surface: String = "concrete"
	if collider is Node:
		if collider.has_meta("surface"):
			surface = str(collider.get_meta("surface"))

		# Damage Player
		if collider == GameManager.player and shooter_tag != "player":
			GameManager.apply_damage_to_player(damage)
			AudioManager.play_3d("impact_flesh", hit_pos, -4.0, 0.1, 20.0)
			return

		# Damage Enemy (supports head/body hitboxes)
		if collider.has_method("take_ballistic_hit"):
			collider.take_ballistic_hit(damage, hit_pos, velocity.normalized(), false)
			if shooter_tag == "player":
				GameManager.enemy_hit.emit(false)
			_spawn_impact_fx(hit_pos, hit_normal, "flesh")
			return
		elif collider.get_parent() and collider.get_parent().has_method("take_ballistic_hit"):
			var is_head: bool = collider.has_meta("is_head") and bool(collider.get_meta("is_head"))
			collider.get_parent().take_ballistic_hit(damage, hit_pos, velocity.normalized(), is_head)
			if shooter_tag == "player":
				GameManager.enemy_hit.emit(is_head)
			_spawn_impact_fx(hit_pos, hit_normal, "flesh")
			return

		# Interactive shootable lights / breaker / barrels
		if collider.has_method("on_shot"):
			collider.on_shot(hit_pos, velocity.normalized())

		# Physical impulse on RigidBody3D props (crates, barrels, cans)
		if collider is RigidBody3D:
			var impulse: Vector3 = velocity.normalized() * clampf(damage * 0.28, 4.0, 18.0)
			collider.apply_impulse(impulse, hit_pos - collider.global_position)

	# Broadcast bullet crack/impact sound so nearby AI reacts/takes cover!
	if shooter_tag == "player":
		GameManager.emit_noise(hit_pos, 18.0, "bullet_impact")

	_spawn_impact_fx(hit_pos, hit_normal, surface)


func _spawn_impact_fx(pos: Vector3, normal: Vector3, surface: String) -> void:
	var root := get_tree().current_scene
	if root == null:
		return

	# Sound
	var sfx_key := "impact_concrete"
	if surface == "metal":
		sfx_key = "impact_metal"
	elif surface == "flesh":
		sfx_key = "impact_flesh"
	AudioManager.play_3d(sfx_key, pos, -8.0, 0.14, 34.0)

	# Bullet hole mark (for static/world surfaces)
	if surface != "flesh":
		var mark := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(0.065, 0.065)
		mark.mesh = quad
		var dmat := StandardMaterial3D.new()
		dmat.albedo_color = Color(0.05, 0.05, 0.05, 0.88) if surface != "metal" else Color(0.12, 0.12, 0.14, 0.9)
		dmat.roughness = 0.95
		dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		dmat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mark.material_override = dmat
		root.add_child(mark)
		mark.global_position = pos + normal * 0.008
		var up_vec := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
		mark.look_at(mark.global_position + normal, up_vec)
		# Auto-cleanup old bullet marks
		var timer := root.get_tree().create_timer(35.0)
		timer.timeout.connect(func():
			if is_instance_valid(mark):
				mark.queue_free()
		)

	# Impact particles (sparks for metal, dust puff for concrete, mist for flesh)
	var fx := CPUParticles3D.new()
	fx.one_shot = true
	fx.explosiveness = 0.92
	fx.amount = 14 if surface == "metal" else 10
	fx.lifetime = 0.35 if surface == "metal" else 0.55
	fx.direction = normal
	fx.spread = 48.0
	fx.initial_velocity_min = 2.5 if surface == "metal" else 1.2
	fx.initial_velocity_max = 7.5 if surface == "metal" else 3.8
	fx.gravity = Vector3(0, -9.8, 0) if surface == "metal" else Vector3(0, -2.5, 0)

	var pmesh := BoxMesh.new()
	pmesh.size = Vector3(0.014, 0.014, 0.045) if surface == "metal" else Vector3(0.045, 0.045, 0.045)
	fx.mesh = pmesh

	var pmat := StandardMaterial3D.new()
	if surface == "metal":
		pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pmat.albedo_color = Color(1.0, 0.78, 0.32)
		pmat.emission_enabled = true
		pmat.emission = Color(1.0, 0.7, 0.2)
		pmat.emission_energy_multiplier = 5.0
	elif surface == "flesh":
		pmat.albedo_color = Color(0.45, 0.04, 0.04, 0.85)
		pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	else:
		pmat.albedo_color = Color(0.58, 0.56, 0.52, 0.72)
		pmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pmat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	fx.material_override = pmat

	root.add_child(fx)
	fx.global_position = pos + normal * 0.02
	fx.emitting = true

	var t := root.get_tree().create_timer(1.2)
	t.timeout.connect(func():
		if is_instance_valid(fx):
			fx.queue_free()
	)
