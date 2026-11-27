# Lobby.gd
# Pre-match waiting room shown between the main menu and the game.
# The host waits here for players to join and starts the match;
# clients wait here until the host starts.

extends Control

@onready var title_label: Label = $Panel/VBoxContainer/Title
@onready var status_label: Label = $Panel/VBoxContainer/Status
@onready var count_label: Label = $Panel/VBoxContainer/PlayerCount
@onready var player_list: VBoxContainer = $Panel/VBoxContainer/PlayerList
@onready var start_btn: Button = $Panel/VBoxContainer/Buttons/Start
@onready var leave_btn: Button = $Panel/VBoxContainer/Buttons/Leave
@onready var previous_character_btn: Button = $Panel/VBoxContainer/CharacterPicker/PreviousCharacter
@onready var next_character_btn: Button = $Panel/VBoxContainer/CharacterPicker/NextCharacter
@onready var character_name_label: Label = $Panel/VBoxContainer/CharacterPicker/CharacterName
@onready var character_preview: Control = $Panel/VBoxContainer/CharacterPreview
@onready var preview_stage: Node3D = $Panel/VBoxContainer/CharacterPreview/Viewport/PreviewStage
@onready var preview_camera: Camera3D = $Panel/VBoxContainer/CharacterPreview/Viewport/PreviewStage/Camera3D

const CHARACTER_CATALOG: CharacterCatalog = preload("res://Models/characters/Definitions/CharacterCatalog.tres")

var _dots_time := 0.0
var _selected_character_index := 0
var _character_selection_ready := false
var _preview_model: Node3D
var _preview_pivot: Node3D
var _preview_character_id: StringName = &""
var _dragging_preview := false
var _player_name_input: LineEdit = null
var _player_name_hint: Label = null

# Called when the node enters the scene tree
func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	multiplayer.peer_connected.connect(_on_peers_changed)
	multiplayer.peer_disconnected.connect(_on_peers_changed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	start_btn.pressed.connect(_on_start_pressed)
	leave_btn.pressed.connect(_on_leave_pressed)
	previous_character_btn.pressed.connect(_on_previous_character_pressed)
	next_character_btn.pressed.connect(_on_next_character_pressed)
	if character_preview:
		character_preview.mouse_filter = Control.MOUSE_FILTER_STOP
		character_preview.gui_input.connect(_on_preview_gui_input)
	NetworkManager.character_selections_changed.connect(_on_character_selections_changed)
	NetworkManager.player_names_changed.connect(_on_player_names_changed)
	if Settings != null and Settings.has_signal("input_device_changed"):
		Settings.input_device_changed.connect(_on_input_device_changed)

	_setup_player_name_row()

	var current_id := NetworkManager.get_local_character_id()
	for i in CHARACTER_CATALOG.characters.size():
		if CHARACTER_CATALOG.characters[i].character_id == current_id:
			_selected_character_index = i
			break
	_refresh_character_selection()
	NetworkManager.request_character_selections()
	NetworkManager.request_player_names()

	var is_host := multiplayer.is_server()
	title_label.text = "Hosting Game" if is_host else "Joined Game"
	start_btn.visible = is_host
	leave_btn.text = "Cancel" if is_host else "Leave"
	if is_host:
		_setup_host_ip_row()

	_setup_focus_styling()
	if is_host:
		start_btn.grab_focus()
	else:
		leave_btn.grab_focus()

	_refresh()

# Animate the trailing dots on the status message
func _process(delta: float) -> void:
	_dots_time += delta
	var dots := ".".repeat(int(_dots_time * 2.0) % 4)
	var base := "Waiting for players to join" if multiplayer.is_server() else "Waiting for host to start the match"
	status_label.text = base + dots
	if is_instance_valid(_preview_pivot) and not _dragging_preview:
		_preview_pivot.rotate_y(delta * 0.35)

func _on_preview_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging_preview = event.pressed
	elif event is InputEventMouseMotion and _dragging_preview and is_instance_valid(_preview_pivot):
		_preview_pivot.rotate_y(event.relative.x * 0.015)

func _unhandled_input(event: InputEvent) -> void:
	if _player_name_input != null and _player_name_input.has_focus():
		if event.is_action_pressed("ui_cancel"):
			_player_name_input.release_focus()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		_on_leave_pressed()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		var focus_owner := get_viewport().gui_get_focus_owner()
		var on_action_buttons := (focus_owner == start_btn or focus_owner == leave_btn)
		if event.physical_keycode in [KEY_A, KEY_Q] or (event.physical_keycode == KEY_LEFT and not on_action_buttons):
			_on_previous_character_pressed()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode in [KEY_D, KEY_E] or (event.physical_keycode == KEY_RIGHT and not on_action_buttons):
			_on_next_character_pressed()
			get_viewport().set_input_as_handled()

func _setup_player_name_row() -> void:
	var vbox := get_node_or_null("Panel/VBoxContainer") as VBoxContainer
	if vbox == null or vbox.get_node_or_null("PlayerNameRow") != null:
		return
	var panel := get_node_or_null("Panel") as Control
	if panel != null:
		panel.offset_top = -350.0
		panel.offset_bottom = 350.0
	vbox.add_theme_constant_override("separation", 10)

	var row := HBoxContainer.new()
	row.name = "PlayerNameRow"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)

	var lbl := Label.new()
	lbl.text = "Your Name:"
	lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))

	_player_name_input = LineEdit.new()
	_player_name_input.name = "PlayerNameInput"
	_player_name_input.custom_minimum_size = Vector2(210, 32)
	_player_name_input.max_length = Settings.MAX_PLAYER_NAME_LENGTH if Settings != null else 16
	_player_name_input.placeholder_text = "Default (Player #)"
	_player_name_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	var saved_name := ""
	if Settings != null:
		saved_name = Settings.sanitize_player_name(str(Settings.settings.get("player_name", "")))
	_player_name_input.text = saved_name
	_player_name_input.text_changed.connect(_on_player_name_changed)
	_player_name_input.text_submitted.connect(_on_player_name_submitted)
	_player_name_input.focus_exited.connect(_on_player_name_focus_exited)

	_player_name_hint = Label.new()
	_player_name_hint.name = "PlayerNameHint"
	_player_name_hint.text = "(Keyboard only)"
	_player_name_hint.add_theme_font_size_override("font_size", 12)
	_player_name_hint.add_theme_color_override("font_color", Color(0.72, 0.68, 0.62))

	row.add_child(lbl)
	row.add_child(_player_name_input)
	row.add_child(_player_name_hint)
	vbox.add_child(row)
	if count_label != null:
		vbox.move_child(row, count_label.get_index() + 1)

	_apply_input_device_to_name_field(Settings != null and Settings.is_using_controller)

func _on_input_device_changed(using_controller: bool) -> void:
	_apply_input_device_to_name_field(using_controller)

func _apply_input_device_to_name_field(using_controller: bool) -> void:
	if _player_name_input == null:
		return
	if using_controller:
		if _player_name_input.has_focus():
			_player_name_input.release_focus()
			if multiplayer.is_server() and start_btn != null and start_btn.visible:
				start_btn.grab_focus()
			elif leave_btn != null:
				leave_btn.grab_focus()
		_player_name_input.editable = false
		_player_name_input.focus_mode = Control.FOCUS_NONE
		_player_name_input.modulate = Color(0.68, 0.68, 0.72, 0.65)
		if _player_name_hint != null:
			_player_name_hint.text = "(Keyboard only)"
			_player_name_hint.visible = true
	else:
		_player_name_input.editable = true
		# Click-only focus keeps gamepad D-pad/stick from ever focusing this field
		_player_name_input.focus_mode = Control.FOCUS_CLICK
		_player_name_input.modulate = Color.WHITE
		if _player_name_hint != null:
			_player_name_hint.visible = false

func _on_player_name_changed(new_text: String) -> void:
	if Settings != null and Settings.is_using_controller:
		return
	var clean := Settings.sanitize_player_name(new_text) if Settings != null else new_text.strip_edges().substr(0, 16)
	NetworkManager.set_local_player_name(clean)

func _on_player_name_submitted(new_text: String) -> void:
	if _player_name_input != null:
		_player_name_input.release_focus()
	_commit_player_name(new_text)

func _on_player_name_focus_exited() -> void:
	if _player_name_input != null:
		_commit_player_name(_player_name_input.text)

func _commit_player_name(raw_text: String) -> void:
	if Settings != null and Settings.is_using_controller:
		return
	var clean := Settings.sanitize_player_name(raw_text) if Settings != null else raw_text.strip_edges().substr(0, 16)
	if _player_name_input != null and _player_name_input.text != clean:
		_player_name_input.text = clean
	if Settings != null:
		Settings.set_setting("player_name", clean)
	NetworkManager.set_local_player_name(clean)

func _on_player_names_changed(_names: Dictionary) -> void:
	if is_inside_tree():
		_refresh()

func _setup_focus_styling() -> void:
	var focus_box := StyleBoxFlat.new()
	focus_box.draw_center = false
	focus_box.set_border_width_all(2)
	focus_box.border_color = Color(1.0, 0.84, 0.0, 1.0)
	focus_box.set_corner_radius_all(4)
	for btn in find_children("*", "Button", true, false):
		btn.add_theme_stylebox_override("focus", focus_box)

func _get_local_lan_ip() -> String:
	var fallback := "127.0.0.1"
	for addr in IP.get_local_addresses():
		if ":" in addr or addr.begins_with("127.") or addr.begins_with("169.254."):
			continue
		if addr.begins_with("192.168.") or addr.begins_with("10."):
			return addr
		if fallback == "127.0.0.1":
			fallback = addr
	return fallback

func _setup_host_ip_row() -> void:
	var vbox := get_node_or_null("Panel/VBoxContainer") as VBoxContainer
	if vbox == null or vbox.get_node_or_null("HostIPRow") != null:
		return
	var host_ip := _get_local_lan_ip()
	var row := HBoxContainer.new()
	row.name = "HostIPRow"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)

	var ip_label := Label.new()
	ip_label.text = "LAN IP: %s" % host_ip
	ip_label.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))

	var copy_btn := Button.new()
	copy_btn.name = "CopyIPButton"
	copy_btn.text = "Copy IP"
	copy_btn.pressed.connect(func():
		DisplayServer.clipboard_set(host_ip)
		copy_btn.text = "Copied!"
		var timer := get_tree().create_timer(1.5)
		timer.timeout.connect(func():
			if is_instance_valid(copy_btn):
				copy_btn.text = "Copy IP"
		)
	)

	row.add_child(ip_label)
	row.add_child(copy_btn)
	vbox.add_child(row)
	if status_label != null:
		vbox.move_child(row, status_label.get_index() + 1)

func _on_peers_changed(_id: int) -> void:
	if not is_inside_tree():
		return
	_refresh()

# Rebuild the player count and roster from the current set of connected peers
func _refresh() -> void:
	# With server relay (the default), every peer sees all other peers
	var ids: Array = [multiplayer.get_unique_id()]
	ids.append_array(multiplayer.get_peers())
	ids.sort()

	count_label.text = "Players joined: %d / %d" % [ids.size(), GameManager.MAX_PLAYERS]

	for child in player_list.get_children():
		child.queue_free()
	for i in ids.size():
		var id: int = ids[i]
		var entry := Label.new()
		entry.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var custom_name := NetworkManager.get_player_name_for_peer(id)
		entry.text = custom_name if not custom_name.is_empty() else ("Player %d" % (i + 1))
		if id == 1:
			entry.text += " (Host)"
		if id == multiplayer.get_unique_id():
			entry.text += " - You"
		var selected_character_id: StringName = NetworkManager.player_character_selections.get(id, &"")
		var selected_definition := CHARACTER_CATALOG.get_character(selected_character_id)
		if selected_definition != null:
			entry.text += " — " + selected_definition.display_name
		if i < GameManager.PLAYER_COLOR_VALUES.size():
			entry.modulate = GameManager.PLAYER_COLOR_VALUES[i].lightened(0.3)
		player_list.add_child(entry)

func _on_start_pressed() -> void:
	start_btn.disabled = true
	NetworkManager.start_game()

func _on_leave_pressed() -> void:
	NetworkManager.leave_session()


func _on_previous_character_pressed() -> void:
	_select_character(_selected_character_index - 1)


func _on_next_character_pressed() -> void:
	_select_character(_selected_character_index + 1)


func _select_character(index: int) -> void:
	var count := CHARACTER_CATALOG.characters.size()
	if count == 0 or not _character_selection_ready:
		return
	var direction := -1 if index < _selected_character_index else 1
	var candidate_index := _find_available_character_index(index, direction)
	if candidate_index < 0 or candidate_index == _selected_character_index:
		return
	_selected_character_index = candidate_index
	_refresh_character_selection()
	NetworkManager.select_local_character(CHARACTER_CATALOG.characters[_selected_character_index].character_id)


func _refresh_character_selection() -> void:
	if CHARACTER_CATALOG.characters.is_empty():
		character_name_label.text = "No characters available"
		previous_character_btn.disabled = true
		next_character_btn.disabled = true
		return
	var definition: CharacterDefinition = CHARACTER_CATALOG.characters[_selected_character_index]
	character_name_label.text = definition.display_name
	_update_character_preview(definition)
	previous_character_btn.disabled = not _character_selection_ready or _find_available_character_index(_selected_character_index - 1, -1) == _selected_character_index
	next_character_btn.disabled = not _character_selection_ready or _find_available_character_index(_selected_character_index + 1, 1) == _selected_character_index


func _update_character_preview(definition: CharacterDefinition) -> void:
	if definition.character_id == _preview_character_id:
		return
	_preview_character_id = definition.character_id
	if is_instance_valid(_preview_pivot):
		_preview_pivot.queue_free()
		_preview_pivot = null
		_preview_model = null
	var packed_model := definition.get_model_scene()
	if packed_model == null:
		return
	_preview_pivot = Node3D.new()
	_preview_pivot.name = "CharacterPreviewPivot"
	_preview_pivot.position = Vector3(0.0, 1.0, 0.0)
	preview_stage.add_child(_preview_pivot)
	_preview_model = packed_model.instantiate() as Node3D
	if _preview_model == null:
		push_warning("Character preview could not instance '%s'" % definition.display_name)
		return
	_preview_model.name = "CharacterPreviewModel"
	_preview_model.position.y = definition.vertical_offset
	_preview_model.scale = definition.model_scale
	_preview_model.rotation.y = 0.0
	_preview_pivot.add_child(_preview_model)
	call_deferred("_frame_preview_model")


func _frame_preview_model() -> void:
	if not is_instance_valid(_preview_model) or not is_instance_valid(preview_camera):
		return
	var visual_nodes: Array[VisualInstance3D] = []
	_collect_preview_visuals(_preview_model, visual_nodes)
	var has_bounds := false
	var model_bounds := AABB()
	for visual in visual_nodes:
		var world_bounds: AABB = visual.global_transform * visual.get_aabb()
		if has_bounds:
			model_bounds = model_bounds.merge(world_bounds)
		else:
			model_bounds = world_bounds
			has_bounds = true
	if not has_bounds:
		preview_camera.position = Vector3(0.0, 1.0, 3.0)
		preview_camera.look_at(Vector3(0.0, 1.0, 0.0))
		return

	var bounds_center := model_bounds.get_center()
	_preview_model.position -= Vector3(bounds_center.x, bounds_center.y - 1.0, bounds_center.z)
	var half_fov := deg_to_rad(preview_camera.fov * 0.5)
	var vertical_distance := model_bounds.size.y * 0.5 / tan(half_fov)
	var viewport_size := preview_camera.get_viewport().get_visible_rect().size
	var aspect_ratio := viewport_size.x / viewport_size.y if viewport_size.y > 0.0 else 320.0 / 220.0
	var half_horizontal_fov := atan(tan(half_fov) * aspect_ratio)
	var horizontal_distance := model_bounds.size.x * 0.5 / tan(half_horizontal_fov)
	var camera_distance := maxf(vertical_distance, horizontal_distance) * 1.2
	preview_camera.position = Vector3(0.0, 1.0, maxf(camera_distance, 1.6))
	preview_camera.look_at(Vector3(0.0, 1.0, 0.0))


func _collect_preview_visuals(node: Node, visuals: Array[VisualInstance3D]) -> void:
	if node is VisualInstance3D:
		visuals.append(node as VisualInstance3D)
	for child in node.get_children():
		_collect_preview_visuals(child, visuals)


func _find_available_character_index(start_index: int, direction: int) -> int:
	var count := CHARACTER_CATALOG.characters.size()
	if count == 0:
		return -1
	for step in range(count):
		var candidate_index := posmod(start_index + direction * step, count)
		var character_id: StringName = CHARACTER_CATALOG.characters[candidate_index].character_id
		if NetworkManager.is_character_available(character_id, multiplayer.get_unique_id()):
			return candidate_index
	return -1


func _on_character_selections_changed(_selections: Dictionary) -> void:
	_character_selection_ready = true
	var current_id := NetworkManager.get_local_character_id()
	for i in CHARACTER_CATALOG.characters.size():
		if CHARACTER_CATALOG.characters[i].character_id == current_id:
			_selected_character_index = i
			break
	_refresh_character_selection()
	_refresh()

func _on_server_disconnected() -> void:
	print("Host closed the lobby")
	NetworkManager.leave_session()

func _exit_tree() -> void:
	if Settings != null and Settings.has_signal("input_device_changed") and Settings.input_device_changed.is_connected(_on_input_device_changed):
		Settings.input_device_changed.disconnect(_on_input_device_changed)
	if NetworkManager != null and NetworkManager.player_names_changed.is_connected(_on_player_names_changed):
		NetworkManager.player_names_changed.disconnect(_on_player_names_changed)
	if NetworkManager != null and NetworkManager.character_selections_changed.is_connected(_on_character_selections_changed):
		NetworkManager.character_selections_changed.disconnect(_on_character_selections_changed)
