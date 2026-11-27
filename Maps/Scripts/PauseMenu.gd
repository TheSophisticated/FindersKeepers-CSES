# PauseMenu.gd
# This script handles the in-game pause menu functionality

# Extends Control for UI elements
extends Control

const MatchExporter = preload("res://scripts/managers/MatchExporter.gd")

# Node references
@onready var settings_menu = $SettingsMenu  # Settings submenu
@onready var main_menu = $PauseContainer   # Main pause menu

# State variables
var is_paused := false         # Current pause state
var local_player: Node = null  # Reference to local player
var _controls_card: PanelContainer = null # Quick-reference controls overlay
var _export_btn: Button = null
var _export_status_label: Label = null
var _export_dialog: FileDialog = null

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
	
	# Setup focus neighbors on PauseContainer (including Export Match button)
	if has_node("PauseContainer"):
		_setup_pause_export_button()
		var cont_btn = $PauseContainer/Continue
		var sett_btn = $PauseContainer/Settings
		var back_btn = $PauseContainer/BackToMenu
		var quit_btn = $PauseContainer/Quit
		
		cont_btn.focus_neighbor_top = quit_btn.get_path()
		cont_btn.focus_neighbor_bottom = sett_btn.get_path()
		sett_btn.focus_neighbor_top = cont_btn.get_path()
		if _export_btn != null:
			sett_btn.focus_neighbor_bottom = _export_btn.get_path()
			_export_btn.focus_neighbor_top = sett_btn.get_path()
			_export_btn.focus_neighbor_bottom = back_btn.get_path()
			back_btn.focus_neighbor_top = _export_btn.get_path()
		else:
			sett_btn.focus_neighbor_bottom = back_btn.get_path()
			back_btn.focus_neighbor_top = sett_btn.get_path()
		back_btn.focus_neighbor_bottom = quit_btn.get_path()
		quit_btn.focus_neighbor_top = back_btn.get_path()
		quit_btn.focus_neighbor_bottom = cont_btn.get_path()
	
	# Setup focus neighbors in SettingsMenu (includes extended audio & graphics controls)
	if has_node("SettingsMenu/VBoxContainer"):
		_wire_settings_focus_chain($SettingsMenu/VBoxContainer)
	
	# Setup compact controls reference card
	_setup_controls_card()

	# Setup high-visibility focus indicator for gamepad
	_setup_focus_styling()

func _setup_pause_export_button() -> void:
	if _export_btn != null or not has_node("PauseContainer"):
		return
	var container := $PauseContainer
	_export_btn = Button.new()
	_export_btn.name = "ExportGameBtn"
	_export_btn.text = "Export Match (.txt)"
	_export_btn.pressed.connect(_on_export_game_pressed)

	_export_status_label = Label.new()
	_export_status_label.name = "ExportStatusLabel"
	_export_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_export_status_label.add_theme_font_size_override("font_size", 12)
	_export_status_label.add_theme_color_override("font_color", Color(0.76, 0.95, 0.78))
	_export_status_label.visible = false

	container.add_child(_export_btn)
	container.add_child(_export_status_label)
	var back_btn := container.get_node_or_null("BackToMenu")
	if back_btn != null:
		container.move_child(_export_btn, back_btn.get_index())
		container.move_child(_export_status_label, _export_btn.get_index() + 1)

func _on_export_game_pressed() -> void:
	if is_instance_valid(_export_dialog) and _export_dialog.visible:
		return
	_export_dialog = MatchExporter.open_save_dialog(self, GameManager, NetworkManager, _on_export_game_finished)

func _on_export_game_finished(result: Dictionary) -> void:
	_export_dialog = null
	if _export_status_label == null:
		return
	if bool(result.get("canceled", false)):
		return
	if bool(result.get("ok", false)):
		DisplayServer.clipboard_set(str(result.get("global_path", "")))
		_export_status_label.add_theme_color_override("font_color", Color(0.76, 0.95, 0.78))
		_export_status_label.text = "Saved %s (path copied)" % str(result.get("file_name", ""))
	else:
		_export_status_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))
		_export_status_label.text = "Export failed: %s" % str(result.get("error", ""))
	_export_status_label.visible = true

func _setup_controls_card() -> void:
	if _controls_card != null:
		return
	_controls_card = PanelContainer.new()
	_controls_card.name = "ControlsReferenceCard"
	_controls_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	_controls_card.offset_left = 28.0
	_controls_card.offset_top = -150.0
	_controls_card.offset_right = 310.0
	_controls_card.offset_bottom = 150.0
	_controls_card.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.07, 0.04, 0.06, 0.86)
	card_style.set_border_width_all(2)
	card_style.border_color = Color(0.55, 0.22, 0.24, 0.85)
	card_style.set_corner_radius_all(6)
	card_style.set_content_margin_all(12)
	_controls_card.add_theme_stylebox_override("panel", card_style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	var title := Label.new()
	title.name = "HeaderLabel"
	title.text = "CONTROLS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.84, 0.35))
	vbox.add_child(title)

	var bindings := [
		["WASD / L-Stick", "Move"],
		["Shift / RT", "Sprint"],
		["C / Ctrl (Sprint)", "Slide"],
		["Space / A", "Jump"],
		["E / X", "Pick Up / Drop"],
		["Q / B", "Shove Player"],
		["1 / 2 (LB / RB)", "Use Tarot Card"],
		["F / Y", "Toggle Torch"],
		["M", "Minimap Zoom"],
		["Esc / P / Start", "Pause"]
	]
	for pair in bindings:
		var row := HBoxContainer.new()
		var key_lbl := Label.new()
		key_lbl.text = pair[0]
		key_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		key_lbl.add_theme_font_size_override("font_size", 13)
		key_lbl.add_theme_color_override("font_color", Color(0.95, 0.88, 0.72))
		var act_lbl := Label.new()
		act_lbl.text = pair[1]
		act_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		act_lbl.add_theme_font_size_override("font_size", 13)
		act_lbl.add_theme_color_override("font_color", Color(0.78, 0.78, 0.82))
		row.add_child(key_lbl)
		row.add_child(act_lbl)
		vbox.add_child(row)

	_controls_card.add_child(vbox)
	_controls_card.visible = false
	add_child(_controls_card)

func _collect_focusable_controls(node: Node, out: Array[Control]) -> void:
	for child in node.get_children():
		if child is BaseButton or child is Slider:
			var ctrl := child as Control
			if ctrl.visible and ctrl.focus_mode != Control.FOCUS_NONE:
				out.append(ctrl)
		else:
			_collect_focusable_controls(child, out)

func _wire_settings_focus_chain(vbox: VBoxContainer) -> void:
	var controls: Array[Control] = []
	_collect_focusable_controls(vbox, controls)
	var count := controls.size()
	if count == 0:
		return
	for i in range(count):
		var curr := controls[i]
		var prev := controls[posmod(i - 1, count)]
		var next := controls[posmod(i + 1, count)]
		curr.focus_neighbor_top = prev.get_path()
		curr.focus_neighbor_bottom = next.get_path()
		if curr is Slider:
			var parent_ctrl := curr.get_parent() as Control
			if parent_ctrl != null:
				curr.focus_entered.connect(func(): parent_ctrl.modulate = Color(1.0, 0.84, 0.0))
				curr.focus_exited.connect(func(): parent_ctrl.modulate = Color.WHITE)

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
		var m_slider: HSlider = $SettingsMenu/VBoxContainer/MouseSensitivity/Text/Sensitivity
		m_slider.value = Settings.settings.get("mouse_sensitivity", 0.002) * 1000
		_attach_slider_value_label(m_slider, "%.1f")
	
	# Controller sensitivity slider
	if has_node("SettingsMenu/VBoxContainer/ControllerSensitivity/Text/Sensitivity"):
		var c_slider: HSlider = $SettingsMenu/VBoxContainer/ControllerSensitivity/Text/Sensitivity
		c_slider.value = Settings.settings.get("controller_sensitivity", 3.0)
		_attach_slider_value_label(c_slider, "%.1f")
	
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
		# Add the screen's native resolution first, then deduplicated common presets
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

	_setup_extended_settings_ui()

func _setup_extended_settings_ui() -> void:
	var settings_panel := get_node_or_null("SettingsMenu") as Panel
	var vbox := get_node_or_null("SettingsMenu/VBoxContainer") as VBoxContainer
	if settings_panel == null or vbox == null:
		return
	if vbox.get_node_or_null("AudioSectionHeader") != null:
		return

	settings_panel.offset_top = -100.0
	settings_panel.offset_bottom = 100.0
	vbox.offset_top = -155.0
	vbox.offset_bottom = 255.0

	var back_btn := vbox.get_node_or_null("SettingMenuBack")

	var audio_hdr := Label.new()
	audio_hdr.name = "AudioSectionHeader"
	audio_hdr.text = "Audio Settings"
	audio_hdr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(audio_hdr)

	_add_volume_slider(vbox, "MasterVolumeRow", "Master Volume", "master_volume", 1.0)
	_add_volume_slider(vbox, "SFXVolumeRow", "SFX Volume", "sfx_volume", 1.0)
	_add_volume_slider(vbox, "AmbienceVolumeRow", "Ambience Volume", "ambience_volume", 1.0)

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

	var ssao_chk := CheckBox.new()
	ssao_chk.name = "SSAOCheckBox"
	ssao_chk.text = "Ambient Occlusion (SSAO)"
	ssao_chk.button_pressed = bool(Settings.settings.get("ssao_enabled", true))
	ssao_chk.toggled.connect(func(on: bool):
		Settings.set_setting("ssao_enabled", on)
	)
	vbox.add_child(ssao_chk)

	var ssr_chk := CheckBox.new()
	ssr_chk.name = "SSRCheckBox"
	ssr_chk.text = "Screen-Space Reflections (SSR)"
	ssr_chk.button_pressed = bool(Settings.settings.get("ssr_enabled", false))
	ssr_chk.toggled.connect(func(on: bool):
		Settings.set_setting("ssr_enabled", on)
	)
	vbox.add_child(ssr_chk)

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

func _attach_slider_value_label(slider: HSlider, fmt: String = "%.1f") -> void:
	var parent := slider.get_parent()
	if parent == null or parent.get_node_or_null("ValueLabel") != null:
		return
	var val_lbl := Label.new()
	val_lbl.name = "ValueLabel"
	val_lbl.custom_minimum_size = Vector2(44, 0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.text = fmt % slider.value
	slider.value_changed.connect(func(v: float):
		val_lbl.text = fmt % v
	)
	parent.add_child(val_lbl)

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
	slider.custom_minimum_size = Vector2(160, 18)
	var val_lbl := Label.new()
	val_lbl.name = "ValueLabel"
	val_lbl.custom_minimum_size = Vector2(44, 0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.text = "%d%%" % int(round(slider.value * 100.0))
	slider.value_changed.connect(func(val: float):
		val_lbl.text = "%d%%" % int(round(val * 100.0))
		Settings.set_setting(setting_key, val)
	)
	row.add_child(lbl)
	row.add_child(slider)
	row.add_child(val_lbl)
	parent_vbox.add_child(row)

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
	# Let the Save File Dialog handle Escape/Cancel without unpausing the game
	if is_instance_valid(_export_dialog) and _export_dialog.visible:
		return
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
		if _export_status_label != null:
			_export_status_label.visible = false
		if _controls_card:
			_controls_card.visible = true
		
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
		if _controls_card:
			_controls_card.visible = false
		
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
	if _controls_card:
		_controls_card.visible = false
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
	NetworkManager.leave_session()
	# get_tree().change_scene_to_file("res://MainMenu/MainMenu.tscn")

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
	if _controls_card:
		_controls_card.visible = true
	if has_node("PauseContainer/Settings"):
		$PauseContainer/Settings.grab_focus()
