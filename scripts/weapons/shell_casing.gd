extends RigidBody3D
## Physically simulated ejected brass shell casing with realistic acoustic bounce.

var _has_clinked: bool = false
var _life: float = 12.0


func _ready() -> void:
	collision_layer = 1 << 5 # Layer 6: Shells
	collision_mask = 1 | (1 << 3) # World + Props
	mass = 0.012
	contact_monitor = true
	max_contacts_reported = 2
	continuous_cd = true

	var phys := PhysicsMaterial.new()
	phys.bounce = 0.42
	phys.friction = 0.65
	physics_material_override = phys

	var mesh_inst := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.0045
	cyl.bottom_radius = 0.0048
	cyl.height = 0.022
	cyl.radial_segments = 8
	mesh_inst.mesh = cyl
	mesh_inst.rotation_degrees.z = 90.0

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.86, 0.68, 0.28)
	mat.metallic = 0.92
	mat.roughness = 0.26
	mesh_inst.material_override = mat
	add_child(mesh_inst)

	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.005
	shape.height = 0.022
	col.shape = shape
	col.rotation_degrees.z = 90.0
	add_child(col)

	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()


func _on_body_entered(_body: Node) -> void:
	if not _has_clinked:
		_has_clinked = true
		AudioManager.play_3d("shell_casing", global_position, -18.0, 0.16, 14.0)
