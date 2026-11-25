extends Node3D
## Main Scene Bootstrap: Instantiates Weather/Day-Night, Multi-Level Builder,
## Realistic Bodycam Player, and Axon Bodycam HUD.
## Supports `--bench` CLI flag to measure real startup latency and live GPU FPS.

const WeatherScript = preload("res://scripts/environment/weather_cycle.gd")
const LevelBuilderScript = preload("res://scripts/world/level_builder.gd")
const PlayerScript = preload("res://scripts/player/bodycam_player.gd")
const HudScript = preload("res://scripts/ui/bodycam_hud.gd")

var _bench_mode: bool = false
var _bench_elapsed: float = 0.0
var _bench_frames: int = 0
var _boot_ms: int = 0


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	GameManager.reset_mission_state()

	# 1. Weather, Atmospheric Sky, ACES & Fast Fog
	var weather := Node3D.new()
	weather.name = "WeatherCycle"
	weather.set_script(WeatherScript)
	add_child(weather)

	# 2. Current Tactical Level (Sector 09 / 14 / 21)
	var level := Node3D.new()
	level.name = "LevelWorld"
	level.set_script(LevelBuilderScript)
	add_child(level)
	level.build_level(GameManager.current_level_index, weather)

	# 3. Realistic First-Person Bodycam Player
	var player := CharacterBody3D.new()
	player.name = "BodycamPlayer"
	player.set_script(PlayerScript)
	player.position = level.player_spawn
	player.rotation.y = level.player_spawn_yaw
	add_child(player)

	# 4. Axon Bodycam Post-Processing & Tactical HUD
	var hud := CanvasLayer.new()
	hud.name = "BodycamHUD"
	hud.set_script(HudScript)
	add_child(hud)

	_boot_ms = Time.get_ticks_msec() - t0
	if OS.get_cmdline_args().has("--bench"):
		_bench_mode = true
		print("BENCH_BOOT_MS=%d" % _boot_ms)


func _process(delta: float) -> void:
	if not _bench_mode:
		return
	_bench_elapsed += delta
	_bench_frames += 1
	if _bench_elapsed >= 3.0:
		var avg_fps := float(_bench_frames) / maxf(_bench_elapsed, 0.001)
		print("BENCH_AVG_FPS=%.1f (frames=%d, elapsed=%.2fs)" % [avg_fps, _bench_frames, _bench_elapsed])
		get_tree().quit(0)
