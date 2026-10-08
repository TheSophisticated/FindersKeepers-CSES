# PauseMenu.gd
# This script handles the in-game pause menu functionality

# Extends Control for UI elements
extends Control

# Node references
@onready var settings_menu = $SettingsMenu  # Settings submenu
@onready var main_menu = $PauseContainer   # Main pause menu

# State variables
var is_paused := false         # Current pause state
var local_player: Node = null  # Reference to local player

# Called when node enters scene tree
func _ready():
	# Set to full screen size
	set_anchors_preset(Control.PRESET_FULL_RECT)
	set_offsets_preset(Control.PRESET_FULL_RECT)
	
	# Initial visibility - hidden by default
	visible = false
	settings_menu.visible = false
	main_menu.visible = false
	
	# Ensure menu processes input even when game is paused
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Find local player in scene
	find_local_player()
	
	# Connect settings controls
	if has_node("SettingsMenu/VBoxContainer/MouseSensitivity/Text/Sensitivity"):
		$SettingsMenu/VBoxContainer/MouseSensitivity/Text/Sensitivity.value_changed.connect(_on_sensitivity_changed)
	if has_node("SettingsMenu/VBoxContainer/ControllerSensitivity/Text/Sensitivity"):
		$SettingsMenu/VBoxContainer/ControllerSensitivity/Text/Sensitivity.value_changed.connect(_on_controller_sensitivity_changed)
	if has_node("SettingsMenu/VBoxContainer/FullScreenCheckButton"):
		$SettingsMenu/VBoxContainer/FullScreenCheckButton.toggled.connect(_on_fullscreen_toggled)
	if has_node("SettingsMenu/VBoxContainer/VsyncCheckBox"):
		$SettingsMenu/VBoxContainer/VsyncCheckBox.toggled.connect(_on_vsync_toggled)
	if has_node("SettingsMenu/VBoxContainer/ResOptionButton"):
		$SettingsMenu/VBoxContainer/ResOptionButton.item_selected.connect(_on_resolution_selected)
	
	# Initialize settings controls with saved values
	init_settings_controls()
	
	# Setup focus neighbors on PauseContainer
	if has_node("PauseContainer"):
		var cont_btn = $PauseContainer/Continue
		var sett_btn = $PauseContainer/Settings
		var back_btn = $PauseContainer/BackToMenu
		var quit_btn = $PauseContainer/Quit
		
		cont_btn.focus_neighbor_top = quit_btn.get_path()
		cont_btn.focus_neighbor_bottom = sett_btn.get_path()
		sett_btn.focus_neighbor_top = cont_btn.get_path()
		sett_btn.focus_neighbor_bottom = back_btn.get_path()
		back_btn.focus_neighbor_top = sett_btn.get_path()
		back_btn.focus_neighbor_bottom = quit_btn.get_path()
		quit_btn.focus_neighbor_top = back_btn.get_path()
		quit_btn.focus_neighbor_bottom = cont_btn.get_path()
	
	# Setup focus neighbors in SettingsMenu
	if has_node("SettingsMenu/VBoxContainer"):
		var p_res = $SettingsMenu/VBoxContainer/ResOptionButton
		var p_fs = $SettingsMenu/VBoxContainer/FullScreenCheckButton
		var p_vsync = $SettingsMenu/VBoxContainer/VsyncCheckBox
		var p_mouse = $SettingsMenu/VBoxContainer/MouseSensitivity/Text/Sensitivity
		var p_ctrl = $SettingsMenu/VBoxContainer/ControllerSensitivity/Text/Sensitivity
		var p_back = $SettingsMenu/VBoxContainer/SettingMenuBack

		p_res.focus_neighbor_top = p_back.get_path()
		p_res.focus_neighbor_bottom = p_fs.get_path()
		p_fs.focus_neighbor_top = p_res.get_path()
		p_fs.focus_neighbor_bottom = p_vsync.get_path()
		p_vsync.focus_neighbor_top = p_fs.get_path()
		p_vsync.focus_neighbor_bottom = p_mouse.get_path()
		p_mouse.focus_neighbor_top = p_vsync.get_path()
		p_mouse.focus_neighbor_bottom = p_ctrl.get_path()
		p_ctrl.focus_neighbor_top = p_mouse.get_path()
		p_ctrl.focus_neighbor_bottom = p_back.get_path()
		p_back.focus_neighbor_top = p_ctrl.get_path()
		p_back.focus_neighbor_bottom = p_res.get_path()

		p_mouse.focus_entered.connect(func(): p_mouse.get_parent().modulate = Color(1.0, 0.84, 0.0))
		p_mouse.focus_exited.connect(func(): p_mouse.get_parent().modulate = Color.WHITE)
		p_ctrl.focus_entered.connect(func(): p_ctrl.get_parent().modulate = Color(1.0, 0.84, 0.0))
		p_ctrl.focus_exited.connect(func(): p_ctrl.get_parent().modulate = Color.WHITE)
	
	# Setup high-visibility focus indicator for gamepad
	_setup_focus_styling()

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

# Initialize settings controls with current values
func init_settings_controls():
	# Mouse sensitivity slider
	if has_node("SettingsMenu/VBoxContainer/MouseSensitivity/Text/Sensitivity"):
		$SettingsMenu/VBoxContainer/MouseSensitivity/Text/Sensitivity.value = Settings.settings.get("mouse_sensitivity", 0.002) * 1000
	
	# Controller sensitivity slider
	if has_node("SettingsMenu/VBoxContainer/ControllerSensitivity/Text/Sensitivity"):
		$SettingsMenu/VBoxContainer/ControllerSensitivity/Text/Sensitivity.value = Settings.settings.get("controller_sensitivity", 3.0)
	
	# Fullscreen toggle
	if has_node("SettingsMenu/VBoxContainer/FullScreenCheckButton"):
		$SettingsMenu/VBoxContainer/FullScreenCheckButton.button_pressed = Settings.settings.get("fullscreen", false)
	
	# VSync toggle
	if has_node("SettingsMenu/VBoxContainer/VsyncCheckBox"):
		$SettingsMenu/VBoxContainer/VsyncCheckBox.button_pressed = Settings.settings.get("vsync", true)
	
	# Resolution dropdown
	if has_node("SettingsMenu/VBoxContainer/ResOptionButton"):
		var res_option = $SettingsMenu/VBoxContainer/ResOptionButton
		res_option.clear()
		# Add the screen's native resolution first so any display can render 1:1
		var screen_res := DisplayServer.screen_get_size()
		var screen_res_str := str(screen_res.x) + "x" + str(screen_res.y)
		res_option.add_item(screen_res_str)
		# Add common resolution options
		res_option.add_item("1152x648")
		res_option.add_item("1280x720")
		res_option.add_item("1366x768")
		res_option.add_item("1920x1080")
		
		# Set current resolution from settings
		var current_res = Settings.settings.get("resolution", Vector2i(1280, 960))
		var current_res_str = str(current_res.x) + "x" + str(current_res.y)
		for i in range(res_option.item_count):
			if res_option.get_item_text(i) == current_res_str:
				res_option.selected = i
				break

# Find the local player in the scene
func find_local_player():
	# Search all player nodes in the "player" group
	for player in get_tree().get_nodes_in_group("player"):
		if player.is_multiplayer_authority():  # Check if local player
			local_player = player
			print("Found local player: ", player.name)
			break

# Handle input events
func _input(event):
	# Process pause and ui_cancel (B button)
	if event.is_action_pressed("pause"):
		if settings_menu.visible:
			# If in settings, go back to main pause menu
			_on_setting_menu_back_pressed()
			get_viewport().set_input_as_handled()
		else:
			# Toggle pause menu state
			toggle_pause_menu()
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and is_paused:
		if settings_menu.visible:
			_on_setting_menu_back_pressed()
			get_viewport().set_input_as_handled()
		else:
			toggle_pause_menu()
			get_viewport().set_input_as_handled()

# Toggle pause menu visibility and game state
func toggle_pause_menu():
	is_paused = !is_paused
	visible = is_paused
	
	if is_paused:
		if not local_player:
			find_local_player()
		
		# Pause local player - disable input
		if local_player and local_player.has_method("set_input_enabled"):
			local_player.set_input_enabled(false)
		
		# Show pause menu
		main_menu.visible = true
		settings_menu.visible = false
		
		# Focus continue button for gamepad navigation
		if has_node("PauseContainer/Continue"):
			$PauseContainer/Continue.grab_focus()
		
		# Show mouse cursor
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		# Resume local player - enable input
		if local_player and local_player.has_method("set_input_enabled"):
			local_player.set_input_enabled(true)
		
		# Hide settings menu if open
		settings_menu.visible = false
		
		# Hide mouse cursor (capture for FPS controls)
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

# Continue button pressed
func _on_continue_pressed():
	print("Continue pressed")
	toggle_pause_menu()  # Unpause game

# Settings button pressed
func _on_settings_pressed():
	print("Settings pressed")
	main_menu.visible = false
	settings_menu.visible = true  # Show settings submenu
	if has_node("SettingsMenu/VBoxContainer/SettingMenuBack"):
		$SettingsMenu/VBoxContainer/SettingMenuBack.grab_focus()

# Back to menu button pressed
func _on_back_to_menu_pressed():
	print("Back to menu pressed")
	# Disconnect from multiplayer if connected
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer.close()
	
	# Re-enable player input
	if local_player and local_player.has_method("set_input_enabled"):
		local_player.set_input_enabled(true)
	
	# Show mouse cursor
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	# Load main menu scene
	get_tree().change_scene_to_file("res://MainMenu/MainMenu.tscn")

# Quit button pressed
func _on_quit_pressed():
	print("Quit pressed")
	get_tree().quit()  # Quit game

# Mouse sensitivity changed
func _on_sensitivity_changed(value):
	print("Sensitivity changed: ", value)
	# Convert slider value (e.g., 2) to sensitivity (0.002)
	var new_sensitivity = value / 1000.0
	Settings.set_setting("mouse_sensitivity", new_sensitivity)

# Fullscreen toggle changed
func _on_fullscreen_toggled(toggled_on):
	print("Fullscreen toggled: ", toggled_on)
	Settings.set_setting("fullscreen", toggled_on)

# VSync toggle changed
func _on_vsync_toggled(toggled_on):
	print("VSync toggled: ", toggled_on)
	Settings.set_setting("vsync", toggled_on)

# Resolution selection changed
func _on_resolution_selected(index):
	print("Resolution selected: ", index)
	if not has_node("SettingsMenu/VBoxContainer/ResOptionButton"):
		return
	
	# Get selected resolution text (e.g., "1920x1080")
	var res_option = $SettingsMenu/VBoxContainer/ResOptionButton
	var res_text = res_option.get_item_text(index)
	var res_parts = res_text.split("x")
	if res_parts.size() == 2:
		# Convert to Vector2i and save
		var new_res = Vector2i(res_parts[0].to_int(), res_parts[1].to_int())
		Settings.set_setting("resolution", new_res)

# Controller sensitivity changed
func _on_controller_sensitivity_changed(value):
	print("Controller sensitivity changed: ", value)
	Settings.set_setting("controller_sensitivity", value)

# Settings back button pressed
func _on_setting_menu_back_pressed():
	print("Settings back pressed")
	settings_menu.visible = false
	main_menu.visible = true  # Return to main pause menu
	if has_node("PauseContainer/Settings"):
		$PauseContainer/Settings.grab_focus()

