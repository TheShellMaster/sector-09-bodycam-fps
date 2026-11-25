extends Node
## Spatial 3D & 2D Audio Manager with indoor/outdoor acoustic bus routing.

var _streams: Dictionary = {}
var _rain_player: AudioStreamPlayer
var _wind_player: AudioStreamPlayer
var _heartbeat_player: AudioStreamPlayer
var _hb_timer: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_preload_all_audio()
	_setup_ambience_players()


func _preload_all_audio() -> void:
	var files: Array[String] = [
		"shot_outdoor.wav",
		"shot_indoor.wav",
		"step_concrete_1.wav",
		"step_concrete_2.wav",
		"step_concrete_3.wav",
		"step_puddle_1.wav",
		"step_puddle_2.wav",
		"step_metal_1.wav",
		"step_metal_2.wav",
		"step_wood_1.wav",
		"step_wood_2.wav",
		"shell_casing.wav",
		"dry_fire.wav",
		"flashlight_click.wav",
		"weapon_reload.wav",
		"impact_concrete.wav",
		"impact_metal.wav",
		"impact_flesh.wav",
		"ambience_rain.wav",
		"ambience_wind.wav",
		"thunder.wav",
		"radio_squelch.wav",
		"ai_alert.wav",
		"bodycam_beep.wav",
		"heartbeat.wav",
	]
	for f in files:
		var path := "res://assets/audio/" + f
		if ResourceLoader.exists(path):
			var stream = load(path)
			if stream:
				_streams[f.get_basename()] = stream


func _setup_ambience_players() -> void:
	_rain_player = AudioStreamPlayer.new()
	_rain_player.bus = &"Ambience"
	_rain_player.volume_db = -10.0
	add_child(_rain_player)
	if _streams.has("ambience_rain"):
		var s: AudioStreamWAV = _streams["ambience_rain"].duplicate()
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = int(s.data.size() / 2)
		_rain_player.stream = s
		_rain_player.play()

	_wind_player = AudioStreamPlayer.new()
	_wind_player.bus = &"Ambience"
	_wind_player.volume_db = -14.0
	add_child(_wind_player)
	if _streams.has("ambience_wind"):
		var w: AudioStreamWAV = _streams["ambience_wind"].duplicate()
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = int(w.data.size() / 2)
		_wind_player.stream = w
		_wind_player.play()

	_heartbeat_player = AudioStreamPlayer.new()
	_heartbeat_player.bus = &"UI"
	_heartbeat_player.volume_db = -24.0
	if _streams.has("heartbeat"):
		_heartbeat_player.stream = _streams["heartbeat"]
	add_child(_heartbeat_player)


func _process(delta: float) -> void:
	if get_tree().paused:
		return

	# Dynamic indoor/outdoor muffling of rain & wind
	var is_raining: bool = GameManager.weather_preset == GameManager.WeatherPreset.RAIN_STORM
	var target_rain_db: float = -80.0
	if is_raining:
		target_rain_db = -21.0 if GameManager.player_indoors else -9.0
	_rain_player.volume_db = lerpf(_rain_player.volume_db, target_rain_db, delta * 3.0)

	var target_wind_db: float = -24.0 if GameManager.player_indoors else -14.0
	_wind_player.volume_db = lerpf(_wind_player.volume_db, target_wind_db, delta * 3.0)

	# Physiological heartbeat when injured or high BPM
	var stress: float = clampf((GameManager.player_bpm - 105.0) / 55.0, 0.0, 1.0)
	var injury: float = clampf(1.0 - GameManager.player_health / GameManager.player_max_health, 0.0, 1.0)
	var hb_intensity: float = maxf(stress * 0.6, injury)
	if hb_intensity > 0.12 and _heartbeat_player.stream != null:
		_hb_timer -= delta
		if _hb_timer <= 0.0:
			_heartbeat_player.volume_db = lerpf(-26.0, -7.0, hb_intensity)
			_heartbeat_player.pitch_scale = lerpf(0.95, 1.25, hb_intensity)
			_heartbeat_player.play()
			_hb_timer = clampf(60.0 / maxf(GameManager.player_bpm, 60.0), 0.38, 1.05)


func play_2d(key: String, volume_db: float = 0.0, pitch_var: float = 0.05, bus_name: StringName = &"UI") -> void:
	if not _streams.has(key):
		return
	var p := AudioStreamPlayer.new()
	p.stream = _streams[key]
	p.volume_db = volume_db
	p.pitch_scale = randf_range(1.0 - pitch_var, 1.0 + pitch_var)
	p.bus = bus_name
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


func play_3d(key: String, world_pos: Vector3, volume_db: float = 0.0, pitch_var: float = 0.06, max_dist: float = 55.0, force_indoor: bool = false) -> void:
	if not _streams.has(key):
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = _streams[key]
	p.volume_db = volume_db
	p.pitch_scale = randf_range(1.0 - pitch_var, 1.0 + pitch_var)
	p.max_distance = max_dist
	p.unit_size = 6.5
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.bus = &"SFX_Indoor" if (force_indoor or GameManager.player_indoors) else &"SFX_Outdoor"
	var root := get_tree().current_scene
	if root == null:
		p.queue_free()
		return
	root.add_child(p)
	p.global_position = world_pos
	p.finished.connect(p.queue_free)
	p.play()


func play_footstep(surface: String, world_pos: Vector3, is_sprint: bool, is_crouch: bool) -> void:
	var key := "step_concrete_%d" % randi_range(1, 3)
	match surface:
		"puddle":
			key = "step_puddle_%d" % randi_range(1, 2)
		"metal":
			key = "step_metal_%d" % randi_range(1, 2)
		"wood":
			key = "step_wood_%d" % randi_range(1, 2)
	var vol: float = -8.0 if is_sprint else (-18.0 if is_crouch else -12.5)
	play_3d(key, world_pos, vol, 0.12, 22.0)
