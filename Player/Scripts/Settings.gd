# Settings.gd
extends Node

var settings := {
	"mouse_sensitivity": 0.002,
	"controller_sensitivity": 3.0,
	"resolution": Vector2i(1280, 960),
	"fullscreen": false,
	"vsync": true,
	"master_volume": 1.0,
	"sfx_volume": 1.0,
	"ambience_volume": 1.0,
	"shadow_quality": 2,
	"sdfgi_enabled": false,
	"ssao_enabled": true,
	"ssr_enabled": false
}

func _ready():
	# Apply settings on startup
	load_settings()

func save_settings():
	var file = FileAccess.open("user://settings.dat", FileAccess.WRITE)
	if file:
		file.store_var(settings)
		file.close()

func load_settings():
	if FileAccess.file_exists("user://settings.dat"):
		var file = FileAccess.open("user://settings.dat", FileAccess.READ)
		if file:
			var loaded_settings = file.get_var()
			if loaded_settings and loaded_settings is Dictionary:
				for key in loaded_settings:
					settings[key] = loaded_settings[key]
			file.close()
	apply_settings()

func apply_settings():
	# Apply display settings
	if settings.get("fullscreen", false):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		get_window().size = settings.get("resolution", Vector2i(1280, 960))
		center_window()
	
	if settings.get("vsync", true):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	
	# Apply audio, graphics, and sensitivity settings
	apply_audio_settings()
	apply_graphics_settings()
	apply_sensitivity()

func apply_audio_settings():
	_set_bus_linear_volume(&"Master", float(settings.get("master_volume", 1.0)))
	_set_bus_linear_volume(&"SFX", float(settings.get("sfx_volume", 1.0)))
	_set_bus_linear_volume(&"Ambience", float(settings.get("ambience_volume", 1.0)))

func _set_bus_linear_volume(bus_name: StringName, linear_val: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	var clamped := clampf(linear_val, 0.0, 1.0)
	AudioServer.set_bus_mute(idx, clamped <= 0.005)
	if clamped > 0.005:
		AudioServer.set_bus_volume_db(idx, linear_to_db(clamped))

func apply_graphics_settings():
	var shadow_q: int = clampi(int(settings.get("shadow_quality", 2)), 0, 5)
	RenderingServer.directional_soft_shadow_filter_set_quality(shadow_q as RenderingServer.ShadowQuality)
	RenderingServer.positional_soft_shadow_filter_set_quality(shadow_q as RenderingServer.ShadowQuality)
	
	if get_tree() and get_tree().root:
		_apply_env_recursive(get_tree().root)

func _apply_env_recursive(node: Node) -> void:
	if node is WorldEnvironment and node.environment != null:
		var env: Environment = node.environment
		env.sdfgi_enabled = bool(settings.get("sdfgi_enabled", false))
		env.ssao_enabled = bool(settings.get("ssao_enabled", true))
		env.ssr_enabled = bool(settings.get("ssr_enabled", false))
		env.ssil_enabled = bool(settings.get("sdfgi_enabled", false))
	for child in node.get_children():
		_apply_env_recursive(child)

func apply_sensitivity():
	if get_tree():
		for player in get_tree().get_nodes_in_group("player"):
			if player.is_multiplayer_authority():
				player.mouse_sensitivity = settings.get("mouse_sensitivity", 0.002)
				if "controller_sensitivity" in player:
					player.controller_sensitivity = settings.get("controller_sensitivity", 3.0)

func center_window():
	var screen_size = DisplayServer.screen_get_size()
	var window_size = get_window().size
	get_window().position = (screen_size - window_size) / 2

func set_setting(key: String, value):
	settings[key] = value
	save_settings()
	
	# Apply the relevant subsystem
	if key in ["resolution", "fullscreen", "vsync"]:
		apply_settings()
	elif key in ["mouse_sensitivity", "controller_sensitivity"]:
		apply_sensitivity()
	elif key in ["master_volume", "sfx_volume", "ambience_volume"]:
		apply_audio_settings()
	elif key in ["shadow_quality", "sdfgi_enabled", "ssao_enabled", "ssr_enabled"]:
		apply_graphics_settings()
