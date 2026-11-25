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

enum WeatherPreset {
	RAIN_STORM,
	OVERCAST_DUSK,
	FOGGY_NIGHT,
	DAWN_CLEAR,
}

# Realism & Visual Settings
var graphics_preset: int = 1 # 0 = Performance, 1 = High (SSR+SSAO+SSIL+VolFog), 2 = Ultra (+SDFGI)
var barrel_strength: float = 0.115
var mouse_sensitivity: float = 0.0022
var base_fov: float = 84.0
var show_crosshair: bool = false
var show_help_hints: bool = true
var nvg_enabled: bool = false
var weather_preset: WeatherPreset = WeatherPreset.RAIN_STORM
var time_of_day: float = 19.6 # 19:36 dusk/rainy evening — dramatic puddles & volumetric streetlamps!
var day_cycle_speed: float = 0.015 # Hours per second (gentle living cycle)
var power_grid_online: bool = true

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
