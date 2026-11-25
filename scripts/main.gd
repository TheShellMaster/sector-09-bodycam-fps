extends Node3D
## Main Scene Bootstrap: Instantiates Weather/Day-Night, Multi-Level Builder,
## Realistic Bodycam Player, and Axon Bodycam HUD.

const WeatherScript = preload("res://scripts/environment/weather_cycle.gd")
const LevelBuilderScript = preload("res://scripts/world/level_builder.gd")
const PlayerScript = preload("res://scripts/player/bodycam_player.gd")
const HudScript = preload("res://scripts/ui/bodycam_hud.gd")


func _ready() -> void:
	GameManager.reset_mission_state()

	# 1. Weather, Physical Sky, AgX & Volumetric Fog
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
