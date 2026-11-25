extends StaticBody3D
## Interactive & Destructible World Objects:
## - "breaker": Cuts/restores warehouse electrical grid (interact OR shoot!)
## - "intel": Encrypted tactical laptop objective
## - "ammo": Tactical ammo resupply crate
## - "lamp": Shootable hanging industrial lamp

@export var kind: String = "intel"
var _used: bool = false
var linked_lights: Array[Light3D] = []
var linked_emissives: Array[MeshInstance3D] = []


func _ready() -> void:
	collision_layer = 1 | (1 << 4) # World + Interactable
	collision_mask = 0


func get_prompt() -> String:
	if _used and kind != "breaker":
		return ""
	match kind:
		"intel":
			return "[E / V] SECURE ENCRYPTED INTEL"
		"breaker":
			return "[E / V] %s WAREHOUSE POWER GRID" % ("CUT" if GameManager.power_grid_online else "RESTORE")
		"ammo":
			return "[E / V] RESUPPLY 5.56mm MAGAZINES"
	return ""


func interact(player: Node) -> void:
	if _used and kind != "breaker":
		return
	match kind:
		"intel":
			_used = true
			AudioManager.play_2d("radio_squelch", -4.0, 0.04)
			GameManager.on_intel_secured()
			GameManager.interact_prompt_changed.emit("")
			# Turn laptop screen green to show upload complete
			for m in linked_emissives:
				if is_instance_valid(m) and m.material_override is StandardMaterial3D:
					var sm: StandardMaterial3D = m.material_override
					sm.emission = Color(0.1, 0.95, 0.35)
		"breaker":
			_toggle_power()
		"ammo":
			_used = true
			if player.get("_weapon") != null:
				player._weapon.reserve_mags = mini(player._weapon.reserve_mags + 3, 7)
			AudioManager.play_2d("weapon_reload", -7.0, 0.08)
			GameManager.mag_status_displayed.emit("RESUPPLIED +3 SPARE MAGAZINES")
			GameManager.log_event("AMMUNITION RESUPPLIED", "OK")
			GameManager.interact_prompt_changed.emit("")


func on_shot(hit_pos: Vector3, _dir: Vector3) -> void:
	if kind == "breaker" and GameManager.power_grid_online:
		_toggle_power()
		AudioManager.play_3d("impact_metal", hit_pos, -2.0, 0.1, 35.0)
	elif kind == "lamp" and not _used:
		_used = true
		AudioManager.play_3d("impact_metal", hit_pos, -4.0, 0.15, 30.0)
		for l in linked_lights:
			if is_instance_valid(l):
				l.visible = false
		for m in linked_emissives:
			if is_instance_valid(m) and m.material_override is StandardMaterial3D:
				m.material_override.emission_enabled = false
		GameManager.log_event("LIGHT FIXTURE DESTROYED", "INFO")


func _toggle_power() -> void:
	GameManager.power_grid_online = not GameManager.power_grid_online
	AudioManager.play_3d("flashlight_click", global_position, -2.0, 0.2, 28.0)
	for l in linked_lights:
		if is_instance_valid(l):
			l.visible = GameManager.power_grid_online
	for m in linked_emissives:
		if is_instance_valid(m) and m.material_override is StandardMaterial3D:
			m.material_override.emission_enabled = GameManager.power_grid_online
	var state_str := "ONLINE" if GameManager.power_grid_online else "OFFLINE // BLACKOUT"
	GameManager.log_event("SECTOR 09 POWER GRID: %s" % state_str, "WARN")
	GameManager.emit_noise(global_position, 20.0, "power_cut")
	GameManager.interact_prompt_changed.emit(get_prompt())
