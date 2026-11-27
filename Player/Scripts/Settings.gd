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
	"ssr_enabled": false,
	"last_direct_ip": "",
	"player_name": "",
	"skin_tone": "default",
	"hair_style": "default"
}

signal input_device_changed(using_controller: bool)
var is_using_controller: bool = false

const MAX_PLAYER_NAME_LENGTH := 16

const BODY_FONT_PATH := "res://Assets/Fonts/HorrorBodySerif.ttf"
const TITLE_FONT_PATH := "res://Assets/Fonts/HorrorDisplayTitle.ttf"
const ACCENT_FONT_PATH := "res://Assets/Fonts/HorrorAccent.ttf"

var body_font: Font = null
var title_font: Font = null
var accent_font: Font = null

func _ready():
	_init_custom_fonts()
	# Apply settings on startup
	load_settings()

func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed:
		_set_using_controller(true)
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.25:
		_set_using_controller(true)
	elif event is InputEventKey and event.pressed:
		_set_using_controller(false)
	elif event is InputEventMouseButton and event.pressed:
		_set_using_controller(false)

func _set_using_controller(using_ctrl: bool) -> void:
	if is_using_controller == using_ctrl:
		return
	is_using_controller = using_ctrl
	input_device_changed.emit(is_using_controller)

static func sanitize_player_name(raw_name: String) -> String:
	var cleaned := ""
	var prev_space := false
	for i in range(raw_name.length()):
		var code := raw_name.unicode_at(i)
		# Keep printable ASCII and basic letters/numbers; strip control/newline chars
		if code < 32 or code == 127:
			continue
		var ch := raw_name.substr(i, 1)
		if ch == " " or ch == "\t":
			if not prev_space and not cleaned.is_empty():
				cleaned += " "
				prev_space = true
		else:
			cleaned += ch
			prev_space = false
	cleaned = cleaned.strip_edges()
	if cleaned.length() > MAX_PLAYER_NAME_LENGTH:
		cleaned = cleaned.substr(0, MAX_PLAYER_NAME_LENGTH).strip_edges()
	return cleaned

func _load_font_safe(res_path: String) -> Font:
	var ff := FontFile.new()
	var global_path := ProjectSettings.globalize_path(res_path)
	if FileAccess.file_exists(global_path) and ff.load_dynamic_font(global_path) == OK:
		return ff
	if FileAccess.file_exists(res_path) and ff.load_dynamic_font(res_path) == OK:
		return ff
	if ResourceLoader.exists(res_path):
		var loaded = load(res_path)
		if loaded is Font:
			return loaded
	return null

func _init_custom_fonts() -> void:
	body_font = _load_font_safe(BODY_FONT_PATH)
	title_font = _load_font_safe(TITLE_FONT_PATH)
	accent_font = _load_font_safe(ACCENT_FONT_PATH)

	if body_font != null:
		var proj_theme := ThemeDB.get_project_theme()
		if proj_theme != null:
			proj_theme.default_font = body_font
		var def_theme := ThemeDB.get_default_theme()
		if def_theme != null:
			def_theme.default_font = body_font

	if get_tree():
		if not get_tree().node_added.is_connected(_on_tree_node_added):
			get_tree().node_added.connect(_on_tree_node_added)
		if get_tree().root:
			_apply_fonts_recursive(get_tree().root)

func _on_tree_node_added(node: Node) -> void:
	_apply_font_to_single_node(node)

func _apply_fonts_recursive(node: Node) -> void:
	_apply_font_to_single_node(node)
	for child in node.get_children():
		_apply_fonts_recursive(child)

func _apply_font_to_single_node(node: Node) -> void:
	if body_font == null:
		return
	if node is Control:
		var ctrl := node as Control
		var n_name := String(ctrl.name)
		var is_title := n_name in [
			"Title", "TitleLabel", "HeaderLabel", "TimerLabel", "BannerLabel",
			"WinnerLabel", "NameLabel", "MessageLabel", "CharacterName",
			"AudioSectionHeader", "GraphicsSectionHeader"
		]
		var target_font: Font = title_font if (is_title and title_font != null) else body_font
		if ctrl is Label or ctrl is Button or ctrl is LineEdit or ctrl is RichTextLabel:
			ctrl.add_theme_font_override("font", target_font)
		if ctrl is RichTextLabel:
			ctrl.add_theme_font_override("normal_font", body_font)
			if title_font != null:
				ctrl.add_theme_font_override("bold_font", title_font)
		if ctrl is Label:
			ctrl.add_theme_color_override("font_shadow_color", Color(0.03, 0.01, 0.02, 0.9))
			ctrl.add_theme_constant_override("shadow_offset_x", 1)
			ctrl.add_theme_constant_override("shadow_offset_y", 2)
	elif node is Label3D:
		var lbl3d := node as Label3D
		lbl3d.font = title_font if title_font != null else body_font

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
