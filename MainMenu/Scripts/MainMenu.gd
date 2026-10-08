# UIController.gd
# This script handles the game's user interface including main menu and settings

# Extends Control node for UI elements
extends Control

# Called when the node enters the scene tree
func _ready():
	# Load saved settings
	Settings.load_settings()
	
	# Set initial visibility of panels
	$MenuPanel.show()
	$SettingsMenu.hide()
	
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
		
		# Populate resolution dropdown with common options
		res_option.clear()
		# Add the screen's native resolution first so any display can render 1:1
		var screen_res := DisplayServer.screen_get_size()
		var screen_res_str := str(screen_res.x) + "x" + str(screen_res.y)
		res_option.add_item(screen_res_str)
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

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and $SettingsMenu.visible:
		_on_setting_menu_back_pressed()
		get_viewport().set_input_as_handled()

# Called when Host button is pressed
func _on_host_pressed():
	$MenuPanel/VBoxContainer/Host.disabled = true  # Disable button while attempting
	if NetworkManager.host_game() == false:  # Wait for host attempt
		$MenuPanel/VBoxContainer/Host.disabled = false  # Re-enable if failed

# Called when Join button is pressed
func _on_join_pressed():
	$MenuPanel/VBoxContainer/Join.disabled = true  # Disable button while attempting
	if !NetworkManager.start_host_search():  # Try to join (default to localhost)
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
	$MenuPanel/VBoxContainer/Host.disabled = false
	$MenuPanel/VBoxContainer/Join.disabled = false
