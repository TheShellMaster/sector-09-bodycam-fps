extends Node
## Global state, realism configuration, tactical event log, and sensory noise bus.

signal noise_emitted(position: Vector3, radius: float, source_tag: String)
signal event_logged(text: String, level: String)
signal settings_changed()
signal mission_updated()
signal player_damaged(health: float, max_health: float)
signal player_died()
signal interact_prompt_changed(prompt: String)
signal mag_status_displayed(status_text: String)
signal enemy_hit(is_headshot: bool)

enum WeatherPreset {
	RAIN_STORM,
	OVERCAST_DUSK,
	FOGGY_NIGHT,
	DAWN_CLEAR,
}

# Realism & Visual Settings
var graphics_preset: int = 1 # 0 = Performance, 1 = Balanced (Recommended), 2 = High
var barrel_strength: float = 0.0 # Adjustable in Settings (0% = max FPS on integrated GPUs)
var mouse_sensitivity: float = 0.0022
var invert_y: bool = false
var base_fov: float = 82.0
var show_crosshair: bool = true
var show_help_hints: bool = true
var nvg_enabled: bool = false
var master_volume: float = 0.85
var ambience_volume: float = 0.55
var fullscreen: bool = false
var vsync_enabled: bool = true
var weather_preset: WeatherPreset = WeatherPreset.RAIN_STORM
var time_of_day: float = 19.6
var day_cycle_speed: float = 0.015
var power_grid_online: bool = true
var show_title_on_boot: bool = false
var intel_position: Vector3 = Vector3.ZERO

# Runtime player / mission state
var player: Node3D = null
var player_indoors: bool = false
var player_health: float = 100.0
var player_max_health: float = 100.0
var player_stamina: float = 100.0
var player_bpm: float = 72.0
var player_flashlight_on: bool = true
var player_laser_on: bool = false
var is_paused: bool = false

var hostiles_total: int = 0
var hostiles_alive: int = 0
var intel_secured: bool = false
var mission_completed: bool = false

# Multi-level progression
var current_level_index: int = 0
const LEVEL_NAMES: Array[String] = [
	"NIV. 01 // SECTOR 09 — COUR & ENTREPÔT",
	"NIV. 02 // SECTOR 14 — DOCKS & CONTENEURS",
	"NIV. 03 // SECTOR 21 — BUNKER SOUTERRAIN",
]

var weather_controller: Node = null
var hud: CanvasLayer = null


func load_level(index: int) -> void:
	current_level_index = clampi(index, 0, LEVEL_NAMES.size() - 1)
	reset_mission_state()
	get_tree().reload_current_scene()


func next_level() -> void:
	load_level((current_level_index + 1) % LEVEL_NAMES.size())


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_settings()
	apply_audio_and_display_settings()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("audio", "ambience_volume", ambience_volume)
	cfg.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("controls", "invert_y", invert_y)
	cfg.set_value("controls", "base_fov", base_fov)
	cfg.set_value("controls", "show_crosshair", show_crosshair)
	cfg.set_value("graphics", "preset", graphics_preset)
	cfg.set_value("graphics", "barrel_strength", barrel_strength)
	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("display", "vsync_enabled", vsync_enabled)
	cfg.save("user://settings.cfg")


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") != OK:
		return
	master_volume = float(cfg.get_value("audio", "master_volume", master_volume))
	ambience_volume = float(cfg.get_value("audio", "ambience_volume", ambience_volume))
	mouse_sensitivity = float(cfg.get_value("controls", "mouse_sensitivity", mouse_sensitivity))
	invert_y = bool(cfg.get_value("controls", "invert_y", invert_y))
	base_fov = float(cfg.get_value("controls", "base_fov", base_fov))
	show_crosshair = bool(cfg.get_value("controls", "show_crosshair", show_crosshair))
	graphics_preset = int(cfg.get_value("graphics", "preset", graphics_preset))
	barrel_strength = float(cfg.get_value("graphics", "barrel_strength", barrel_strength))
	fullscreen = bool(cfg.get_value("display", "fullscreen", fullscreen))
	vsync_enabled = bool(cfg.get_value("display", "vsync_enabled", vsync_enabled))


func apply_audio_and_display_settings() -> void:
	var master_idx := AudioServer.get_bus_index("Master")
	if master_idx >= 0:
		AudioServer.set_bus_volume_db(master_idx, linear_to_db(maxf(master_volume, 0.0001)))
		AudioServer.set_bus_mute(master_idx, master_volume <= 0.01)
	var amb_idx := AudioServer.get_bus_index("Ambience")
	if amb_idx >= 0:
		AudioServer.set_bus_volume_db(amb_idx, linear_to_db(maxf(ambience_volume, 0.0001)) - 6.0)
		AudioServer.set_bus_mute(amb_idx, ambience_volume <= 0.01)

	if DisplayServer.get_name() != "headless":
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)
		DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED
		)


func emit_noise(pos: Vector3, radius: float, source_tag: String = "player") -> void:
	noise_emitted.emit(pos, radius, source_tag)


func log_event(msg: String, level: String = "INFO") -> void:
	event_logged.emit(msg, level)


func register_hostile() -> void:
	hostiles_total += 1
	hostiles_alive += 1
	mission_updated.emit()


func on_hostile_eliminated() -> void:
	hostiles_alive = maxi(0, hostiles_alive - 1)
	log_event("HOSTILE NEUTRALIZED (%d REMAINING)" % hostiles_alive, "WARN")
	_check_mission_complete()
	mission_updated.emit()


func on_intel_secured() -> void:
	if intel_secured:
		return
	intel_secured = true
	log_event("ENCRYPTED INTEL SECURED // DATA UPLOADED", "OK")
	_check_mission_complete()
	mission_updated.emit()


func _check_mission_complete() -> void:
	if intel_secured and hostiles_alive == 0 and not mission_completed:
		mission_completed = true
		log_event("SECTOR 09 CLEARED // MISSION ACCOMPLISHED", "OK")


func apply_damage_to_player(amount: float) -> void:
	if player_health <= 0.0:
		return
	player_health = maxf(0.0, player_health - amount)
	player_bpm = minf(165.0, player_bpm + 28.0)
	player_damaged.emit(player_health, player_max_health)
	if player_health <= 0.0:
		log_event("OFFICER DOWN // SIGNAL LOST", "CRIT")
		player_died.emit()


func reset_mission_state() -> void:
	player_health = player_max_health
	player_stamina = 100.0
	player_bpm = 72.0
	hostiles_total = 0
	hostiles_alive = 0
	intel_secured = false
	mission_completed = false
	power_grid_online = true
	is_paused = false
	get_tree().paused = false


func set_paused(paused: bool) -> void:
	is_paused = paused
	get_tree().paused = paused
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED


func cycle_weather_preset() -> void:
	var next_idx: int = (int(weather_preset) + 1) % 4
	weather_preset = next_idx as WeatherPreset
	match weather_preset:
		WeatherPreset.RAIN_STORM:
			time_of_day = 20.2
			log_event("WEATHER: RAIN STORM // NIGHTFALL", "INFO")
		WeatherPreset.OVERCAST_DUSK:
			time_of_day = 18.4
			log_event("WEATHER: OVERCAST DUSK", "INFO")
		WeatherPreset.FOGGY_NIGHT:
			time_of_day = 23.2
			log_event("WEATHER: DENSE FOG // NIGHT", "INFO")
		WeatherPreset.DAWN_CLEAR:
			time_of_day = 7.4
			log_event("WEATHER: GOLDEN DAWN", "INFO")
	settings_changed.emit()


func notify_settings_changed() -> void:
	settings_changed.emit()
