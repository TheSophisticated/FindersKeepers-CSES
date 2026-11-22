# UIController.gd
# This script handles the game's user interface including main menu and settings

# Extends Control node for UI elements
extends Control

var _direct_ip_input: LineEdit = null
var _status_label: Label = null


func _hide_old_3d_menu() -> void:
	# The map viewport now provides the full menu backdrop. Hide the old 3D set
	# so its camera and props cannot show through around the new background.
	var old_world := get_parent().get_node_or_null("WorldObjects")
	if old_world:
		for child in old_world.get_children():
			if child is Node3D:
				child.visible = false
			if child is Camera3D:
				child.current = false

# Called when the node enters the scene tree
func _ready():
	add_to_group("ui")
	_hide_old_3d_menu()

	# Load saved settings
	Settings.load_settings()
	
	# Set initial visibility of panels
	$MenuPanel.show()
	$SettingsMenu.hide()
	
	_setup_direct_ip_and_status_ui()
	_setup_extended_settings_ui()
	_play_start_menu_blur_transition()
	
	# Connect main menu buttons with safety checks to prevent duplicate connections
	if not $MenuPanel/VBoxContainer/Host.pressed.is_connected(_on_host_pressed):
		$MenuPanel/VBoxContainer/Host.pressed.connect(_on_host_pressed)
	
	if not $MenuPanel/VBoxContainer/Join.pressed.is_connected(_on_join_pressed):
		$MenuPanel/VBoxContainer/Join.pressed.connect(_on_join_pressed)
	
	if not $MenuPanel/VBoxContainer/Settings.pressed.is_connected(_on_settings_pressed):
		$MenuPanel/VBoxContainer/Settings.pressed.connect(_on_settings_pressed)
	
	if not $MenuPanel/VBoxContainer/Quit.pressed.is_connected(_on_quit_pressed):
		$MenuPanel/VBoxContainer/Quit.pressed.connect(_on_quit_pressed)
	
	# Connect settings menu back button
	if not $SettingsMenu/VBoxContainer/SettingMenuBack.pressed.is_connected(_on_setting_menu_back_pressed):
		$SettingsMenu/VBoxContainer/SettingMenuBack.pressed.connect(_on_setting_menu_back_pressed)
	
	# Connect and initialize mouse sensitivity setting
	if has_node("SettingsMenu/VBoxContainer/MouseSensitivity/Text/Sensitivity"):
		var sensitivity_slider = $SettingsMenu/VBoxContainer/MouseSensitivity/Text/Sensitivity
		if not sensitivity_slider.value_changed.is_connected(_on_sensitivity_changed):
			sensitivity_slider.value_changed.connect(_on_sensitivity_changed)
		# Convert sensitivity setting to slider value (assuming stored as 0.002)
		sensitivity_slider.value = Settings.settings.get("mouse_sensitivity", 0.002) * 1000
	
	# Connect and initialize controller sensitivity setting
	if has_node("SettingsMenu/VBoxContainer/ControllerSensitivity/Text/Sensitivity"):
		var ctrl_slider = $SettingsMenu/VBoxContainer/ControllerSensitivity/Text/Sensitivity
		if not ctrl_slider.value_changed.is_connected(_on_controller_sensitivity_changed):
			ctrl_slider.value_changed.connect(_on_controller_sensitivity_changed)
		ctrl_slider.value = Settings.settings.get("controller_sensitivity", 3.0)
	
	# Connect and initialize fullscreen setting
	if has_node("SettingsMenu/VBoxContainer/FullScreenCheckButton"):
		var fullscreen_check = $SettingsMenu/VBoxContainer/FullScreenCheckButton
		if not fullscreen_check.toggled.is_connected(_on_fullscreen_toggled):
			fullscreen_check.toggled.connect(_on_fullscreen_toggled)
		fullscreen_check.button_pressed = Settings.settings.get("fullscreen", false)
	
	# Connect and initialize vsync setting
	if has_node("SettingsMenu/VBoxContainer/VsyncCheckBox"):
		var vsync_check = $SettingsMenu/VBoxContainer/VsyncCheckBox
		if not vsync_check.toggled.is_connected(_on_vsync_toggled):
			vsync_check.toggled.connect(_on_vsync_toggled)
		vsync_check.button_pressed = Settings.settings.get("vsync", true)
	
	# Connect and initialize resolution setting
	if has_node("SettingsMenu/VBoxContainer/ResOptionButton"):
		var res_option = $SettingsMenu/VBoxContainer/ResOptionButton
		if not res_option.item_selected.is_connected(_on_resolution_selected):
			res_option.item_selected.connect(_on_resolution_selected)
		
		# Populate resolution dropdown with native + common options (deduplicated)
		res_option.clear()
		var screen_res := DisplayServer.screen_get_size()
		var screen_res_str := str(screen_res.x) + "x" + str(screen_res.y)
		var res_choices: Array[String] = [screen_res_str]
		for preset in ["1152x648", "1280x720", "1366x768", "1920x1080"]:
			if not (preset in res_choices):
				res_choices.append(preset)
		for choice in res_choices:
			res_option.add_item(choice)
		
		# Set current resolution from settings
		var current_res = Settings.settings.get("resolution", Vector2i(1280, 960))
		var current_res_str = str(current_res.x) + "x" + str(current_res.y)
		for i in range(res_option.item_count):
			if res_option.get_item_text(i) == current_res_str:
				res_option.selected = i
				break
	
	# Setup visual focus indicator for gamepad navigation
	_setup_focus_styling()
	
	# Setup focus neighbors for clean navigation loop
	var join_btn = $MenuPanel/VBoxContainer/Join
	var host_btn = $MenuPanel/VBoxContainer/Host
	var settings_btn = $MenuPanel/VBoxContainer/Settings
	var quit_btn = $MenuPanel/VBoxContainer/Quit
	
	join_btn.focus_neighbor_top = quit_btn.get_path()
	join_btn.focus_neighbor_bottom = host_btn.get_path()
	host_btn.focus_neighbor_top = join_btn.get_path()
	host_btn.focus_neighbor_bottom = settings_btn.get_path()
	settings_btn.focus_neighbor_top = host_btn.get_path()
	settings_btn.focus_neighbor_bottom = quit_btn.get_path()
	quit_btn.focus_neighbor_top = settings_btn.get_path()
	quit_btn.focus_neighbor_bottom = join_btn.get_path()

	# Setup focus neighbors in SettingsMenu
	if has_node("SettingsMenu/VBoxContainer"):
		var res_option = $SettingsMenu/VBoxContainer/ResOptionButton
		var fs_check = $SettingsMenu/VBoxContainer/FullScreenCheckButton
		var vsync_check = $SettingsMenu/VBoxContainer/VsyncCheckBox
		var mouse_slider = $SettingsMenu/VBoxContainer/MouseSensitivity/Text/Sensitivity
		var ctrl_slider = $SettingsMenu/VBoxContainer/ControllerSensitivity/Text/Sensitivity
		var settings_back_btn = $SettingsMenu/VBoxContainer/SettingMenuBack

		res_option.focus_neighbor_top = settings_back_btn.get_path()
		res_option.focus_neighbor_bottom = fs_check.get_path()
		fs_check.focus_neighbor_top = res_option.get_path()
		fs_check.focus_neighbor_bottom = vsync_check.get_path()
		vsync_check.focus_neighbor_top = fs_check.get_path()
		vsync_check.focus_neighbor_bottom = mouse_slider.get_path()
		mouse_slider.focus_neighbor_top = vsync_check.get_path()
		mouse_slider.focus_neighbor_bottom = ctrl_slider.get_path()
		ctrl_slider.focus_neighbor_top = mouse_slider.get_path()
		ctrl_slider.focus_neighbor_bottom = settings_back_btn.get_path()
		settings_back_btn.focus_neighbor_top = ctrl_slider.get_path()
		settings_back_btn.focus_neighbor_bottom = res_option.get_path()

		mouse_slider.focus_entered.connect(func(): mouse_slider.get_parent().modulate = Color(1.0, 0.84, 0.0))
		mouse_slider.focus_exited.connect(func(): mouse_slider.get_parent().modulate = Color.WHITE)
		ctrl_slider.focus_entered.connect(func(): ctrl_slider.get_parent().modulate = Color(1.0, 0.84, 0.0))
		ctrl_slider.focus_exited.connect(func(): ctrl_slider.get_parent().modulate = Color.WHITE)
	
	# Initial gamepad focus on the first button (Join)
	join_btn.grab_focus()

func _play_start_menu_blur_transition() -> void:
	const TRANSITION_DURATION := 1.0

	# Play heavy breathing noise accompanying the 1-second wake-up transition
	if AudioManager and AudioManager.has_method("play_heavy_breathing"):
		AudioManager.play_heavy_breathing()
		if AudioManager.get("breathing_player") != null:
			var bp: AudioStreamPlayer = AudioManager.breathing_player
			var audio_tween := create_tween()
			audio_tween.tween_interval(TRANSITION_DURATION * 0.85)
			audio_tween.tween_property(bp, "volume_db", -32.0, 0.45)
			audio_tween.tween_callback(func():
				if is_instance_valid(bp):
					bp.stop()
					bp.volume_db = 2.0
			)

	# Full-screen multi-tap blur + dark eyelid vignette overlay
	var transition_layer := CanvasLayer.new()
	transition_layer.name = "StartMenuBlurTransitionLayer"
	transition_layer.layer = 100
	add_child(transition_layer)

	var overlay := ColorRect.new()
	overlay.name = "BlurTransitionRect"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var blur_shader := Shader.new()
	blur_shader.code = """
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float blur_amount : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = SCREEN_PIXEL_SIZE * (blur_amount * 14.0);
	float mip = blur_amount * 4.2;

	// 9-tap Gaussian-weighted multi-ring screen blur
	vec3 col = textureLod(screen_texture, uv, mip).rgb * 0.28;
	col += textureLod(screen_texture, uv + vec2(px.x, 0.0), mip).rgb * 0.12;
	col += textureLod(screen_texture, uv - vec2(px.x, 0.0), mip).rgb * 0.12;
	col += textureLod(screen_texture, uv + vec2(0.0, px.y), mip).rgb * 0.12;
	col += textureLod(screen_texture, uv - vec2(0.0, px.y), mip).rgb * 0.12;
	col += textureLod(screen_texture, uv + px * 0.75, mip).rgb * 0.06;
	col += textureLod(screen_texture, uv - px * 0.75, mip).rgb * 0.06;
	col += textureLod(screen_texture, uv + vec2(px.x, -px.y) * 0.75, mip).rgb * 0.06;
	col += textureLod(screen_texture, uv + vec2(-px.x, px.y) * 0.75, mip).rgb * 0.06;

	// Subtle dark wake-up vignette that clears as blur fades
	vec2 centered = uv - vec2(0.5);
	float vignette = clamp(dot(centered, centered) * 2.2 * blur_amount, 0.0, 0.92);
	float blackout = pow(blur_amount, 1.8) * 0.65;
	col *= (1.0 - max(vignette, blackout));

	COLOR = vec4(col, blur_amount);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = blur_shader
	mat.set_shader_parameter("blur_amount", 1.0)
	overlay.material = mat
	transition_layer.add_child(overlay)

	if has_node("MenuPanel"):
		$MenuPanel.modulate.a = 0.0

	var tween := create_tween().set_parallel(true)
	tween.tween_method(
		func(val: float):
			if is_instance_valid(mat):
				mat.set_shader_parameter("blur_amount", val),
		1.0,
		0.0,
		TRANSITION_DURATION
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	if has_node("MenuPanel"):
		tween.tween_property($MenuPanel, "modulate:a", 1.0, TRANSITION_DURATION)\
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	tween.chain().tween_callback(func():
		if is_instance_valid(transition_layer):
			transition_layer.queue_free()
	)

func _setup_focus_styling() -> void:
	var focus_box := StyleBoxFlat.new()
	focus_box.draw_center = false
	focus_box.border_width_left = 2
	focus_box.border_width_top = 2
	focus_box.border_width_right = 2
	focus_box.border_width_bottom = 2
	focus_box.border_color = Color(1.0, 0.84, 0.0, 1.0)
	focus_box.corner_radius_top_left = 4
	focus_box.corner_radius_top_right = 4
	focus_box.corner_radius_bottom_right = 4
	focus_box.corner_radius_bottom_left = 4
	for btn in find_children("*", "Button", true, false):
		btn.add_theme_stylebox_override("focus", focus_box)

func _setup_direct_ip_and_status_ui() -> void:
	var vbox := get_node_or_null("MenuPanel/VBoxContainer")
	if vbox == null:
		return
	var panel := get_node_or_null("MenuPanel") as Panel
	if panel:
		panel.offset_top = -182.0
		vbox.offset_bottom = 175.0

	if vbox.get_node_or_null("DirectIPInput") == null:
		_direct_ip_input = LineEdit.new()
		_direct_ip_input.name = "DirectIPInput"
		_direct_ip_input.placeholder_text = "Direct IP (empty = LAN)"
		_direct_ip_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
		_direct_ip_input.add_theme_font_size_override("font_size", 9)
		_direct_ip_input.text_submitted.connect(func(_t): _on_join_pressed())
		vbox.add_child(_direct_ip_input)
		vbox.move_child(_direct_ip_input, 0)

	if get_node_or_null("NetworkStatusLabel") == null:
		_status_label = Label.new()
		_status_label.name = "NetworkStatusLabel"
		_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_status_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		_status_label.offset_left = -320.0
		_status_label.offset_right = 320.0
		_status_label.offset_top = -310.0
		_status_label.offset_bottom = -280.0
		_status_label.add_theme_font_size_override("font_size", 16)
		_status_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
		_status_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		_status_label.add_theme_constant_override("shadow_offset_x", 1)
		_status_label.add_theme_constant_override("shadow_offset_y", 2)
		add_child(_status_label)


func _setup_extended_settings_ui() -> void:
	var settings_panel := get_node_or_null("SettingsMenu") as Panel
	var vbox := get_node_or_null("SettingsMenu/VBoxContainer") as VBoxContainer
	if settings_panel == null or vbox == null:
		return
	if vbox.get_node_or_null("AudioSectionHeader") != null:
		return

	# Expand panel vertically to comfortably house audio and graphics options
	settings_panel.offset_top = -82.0
	settings_panel.offset_bottom = 82.0
	vbox.offset_top = -140.0
	vbox.offset_bottom = 220.0

	var back_btn := vbox.get_node_or_null("SettingMenuBack")

	# --- Audio Section ---
	var audio_hdr := Label.new()
	audio_hdr.name = "AudioSectionHeader"
	audio_hdr.text = "Audio Settings"
	audio_hdr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(audio_hdr)

	_add_volume_slider(vbox, "MasterVolumeRow", "Master Volume", "master_volume", 1.0)
	_add_volume_slider(vbox, "SFXVolumeRow", "SFX Volume", "sfx_volume", 1.0)
	_add_volume_slider(vbox, "AmbienceVolumeRow", "Ambience Volume", "ambience_volume", 1.0)

	# --- Graphics Section ---
	var gfx_hdr := Label.new()
	gfx_hdr.name = "GraphicsSectionHeader"
	gfx_hdr.text = "Graphics & Performance"
	gfx_hdr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(gfx_hdr)

	var shadow_row := HBoxContainer.new()
	shadow_row.name = "ShadowQualityRow"
	var shadow_lbl := Label.new()
	shadow_lbl.text = "Shadows: "
	shadow_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var shadow_opt := OptionButton.new()
	shadow_opt.name = "ShadowQualityOption"
	shadow_opt.add_item("Hard (Fastest)", 0)
	shadow_opt.add_item("Soft Low (Balanced)", 2)
	shadow_opt.add_item("Soft Medium", 3)
	shadow_opt.add_item("Soft High", 4)
	var saved_sq := int(Settings.settings.get("shadow_quality", 2))
	for i in range(shadow_opt.item_count):
		if shadow_opt.get_item_id(i) == saved_sq:
			shadow_opt.selected = i
			break
	shadow_opt.item_selected.connect(func(idx: int):
		Settings.set_setting("shadow_quality", shadow_opt.get_item_id(idx))
	)
	shadow_row.add_child(shadow_lbl)
	shadow_row.add_child(shadow_opt)
	vbox.add_child(shadow_row)

	var sdfgi_chk := CheckBox.new()
	sdfgi_chk.name = "SDFGICheckBox"
	sdfgi_chk.text = "Global Illumination (SDFGI - Heavy)"
	sdfgi_chk.button_pressed = bool(Settings.settings.get("sdfgi_enabled", false))
	sdfgi_chk.toggled.connect(func(on: bool):
		Settings.set_setting("sdfgi_enabled", on)
	)
	vbox.add_child(sdfgi_chk)

	if back_btn:
		vbox.move_child(back_btn, vbox.get_child_count() - 1)


func _add_volume_slider(parent_vbox: VBoxContainer, node_name: String, label_text: String, setting_key: String, default_val: float) -> void:
	var row := HBoxContainer.new()
	row.name = node_name
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(140, 0)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = float(Settings.settings.get(setting_key, default_val))
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(180, 18)
	slider.value_changed.connect(func(val: float):
		Settings.set_setting(setting_key, val)
	)
	row.add_child(lbl)
	row.add_child(slider)
	parent_vbox.add_child(row)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and $SettingsMenu.visible:
		_on_setting_menu_back_pressed()
		get_viewport().set_input_as_handled()

# Called when Host button is pressed
func _on_host_pressed():
	if _status_label:
		_status_label.text = "Starting Host Server..."
		_status_label.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7))
	$MenuPanel/VBoxContainer/Host.disabled = true  # Disable button while attempting
	if NetworkManager.host_game() == false:  # Wait for host attempt
		$MenuPanel/VBoxContainer/Host.disabled = false  # Re-enable if failed

# Called when Join button is pressed
func _on_join_pressed():
	$MenuPanel/VBoxContainer/Join.disabled = true  # Disable button while attempting
	var target_ip := _direct_ip_input.text.strip_edges() if _direct_ip_input != null else ""
	if not target_ip.is_empty():
		if _status_label:
			_status_label.text = "Connecting to %s..." % target_ip
			_status_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
		if not NetworkManager.join_game(target_ip):
			$MenuPanel/VBoxContainer/Join.disabled = false
	else:
		if _status_label:
			_status_label.text = "Searching for LAN Host (5s)..."
			_status_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
		if !NetworkManager.start_host_search():  # Try to join via LAN discovery
			$MenuPanel/VBoxContainer/Join.disabled = false  # Re-enable if failed

# Called when Settings button is pressed
func _on_settings_pressed():
	$MenuPanel.hide()  # Hide main menu
	$SettingsMenu.show()  # Show settings menu
	$SettingsMenu/VBoxContainer/SettingMenuBack.grab_focus()

# Called when Quit button is pressed
func _on_quit_pressed():
	get_tree().quit()  # Quit the game

# Called when mouse sensitivity slider changes
func _on_sensitivity_changed(value):
	# Convert slider value (e.g., 2) to sensitivity (0.002)
	var new_sensitivity = value / 1000.0
	Settings.set_setting("mouse_sensitivity", new_sensitivity)

# Called when controller sensitivity slider changes
func _on_controller_sensitivity_changed(value):
	Settings.set_setting("controller_sensitivity", value)

# Called when fullscreen checkbox toggled
func _on_fullscreen_toggled(toggled_on):
	Settings.set_setting("fullscreen", toggled_on)

# Called when vsync checkbox toggled
func _on_vsync_toggled(toggled_on):
	Settings.set_setting("vsync", toggled_on)

# Called when resolution selection changes
func _on_resolution_selected(index):
	# Get selected resolution text (e.g., "1920x1080")
	var res_text = $SettingsMenu/VBoxContainer/ResOptionButton.get_item_text(index)
	var res_parts = res_text.split("x")
	if res_parts.size() == 2:
		# Convert to Vector2i and save
		var new_res = Vector2i(res_parts[0].to_int(), res_parts[1].to_int())
		Settings.set_setting("resolution", new_res)

# Called when back button in settings is pressed
func _on_setting_menu_back_pressed():
	$SettingsMenu.hide()  # Hide settings
	$MenuPanel.show()  # Show main menu
	$MenuPanel/VBoxContainer/Settings.grab_focus()

# Displays error messages and re-enables buttons
func show_error(message: String):
	print("Error: ", message)
	if _status_label:
		_status_label.text = message
		_status_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
	$MenuPanel/VBoxContainer/Host.disabled = false
	$MenuPanel/VBoxContainer/Join.disabled = false
