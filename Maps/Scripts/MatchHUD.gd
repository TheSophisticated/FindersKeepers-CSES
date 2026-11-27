# MatchHUD.gd
# Handles the in-game HUD displaying match timer, part sacrifice counts,
# announcements, the Blood Shrine voting modal, and the Game Over victory screen.
class_name MatchHUD
extends Control
 
@onready var timer_label: Label = $TopBar/TimerLabel
@onready var score_label: Label = $TopBar/ScoreLabel
@onready var banner_label: Label = $BannerContainer/BannerLabel
@onready var banner_timer: Timer = $BannerContainer/BannerTimer
 
# Blood Shrine UI elements
@onready var shrine_modal: Panel = $BloodShrineModal
@onready var shrine_accept_btn: Button = $BloodShrineModal/VBoxContainer/ButtonHBox/AcceptBtn
@onready var shrine_decline_btn: Button = $BloodShrineModal/VBoxContainer/ButtonHBox/DeclineBtn
@onready var shrine_status_label: Label = $BloodShrineModal/VBoxContainer/StatusLabel
 
# Game Over UI elements
@onready var game_over_panel: Panel = $GameOverPanel
@onready var winner_label: Label = $GameOverPanel/VBoxContainer/WinnerLabel
@onready var menu_btn: Button = $GameOverPanel/VBoxContainer/MenuBtn
 
 
@onready var player_legend_rows: VBoxContainer = $PlayerLegend/LegendVBox/LegendRows
 
const MinimapUIScript = preload("res://Maps/Scripts/MinimapUI.gd")
const MatchExporter = preload("res://scripts/managers/MatchExporter.gd")

var local_parts_lost: int = 0
var _banner_tween: Tween = null
var _panic_vignette: ColorRect = null
var _panic_vignette_mat: ShaderMaterial = null
var _panic_phase: float = 0.0
var _last_time_remaining: float = 300.0
var _spectator_banner: PanelContainer = null
var _debug_overlay_label: Label = null
var _debug_refresh_accum: float = 0.0
var _minimap: Control = null
var _export_btn: Button = null
var _export_status_label: Label = null
 
func _ready() -> void:
	# Hide overlays initially
	if shrine_modal:
		shrine_modal.visible = false
	if game_over_panel:
		game_over_panel.visible = false
	if banner_label:
		banner_label.visible = false
 
	# Connect buttons
	if shrine_accept_btn and not shrine_accept_btn.pressed.is_connected(_on_shrine_accept):
		shrine_accept_btn.pressed.connect(_on_shrine_accept)
	if shrine_decline_btn and not shrine_decline_btn.pressed.is_connected(_on_shrine_decline):
		shrine_decline_btn.pressed.connect(_on_shrine_decline)
	if menu_btn and not menu_btn.pressed.is_connected(_on_menu_pressed):
		menu_btn.pressed.connect(_on_menu_pressed)
	if banner_timer and not banner_timer.timeout.is_connected(_on_banner_timeout):
		banner_timer.timeout.connect(_on_banner_timeout)
	
	if shrine_accept_btn and shrine_decline_btn:
		shrine_accept_btn.focus_neighbor_right = shrine_decline_btn.get_path()
		shrine_accept_btn.focus_neighbor_left = shrine_decline_btn.get_path()
		shrine_decline_btn.focus_neighbor_left = shrine_accept_btn.get_path()
		shrine_decline_btn.focus_neighbor_right = shrine_accept_btn.get_path()
 
	_setup_panic_vignette()
	_setup_minimap()
	_setup_spectator_banner()
	_setup_debug_overlay()
	_setup_game_over_export_ui()
	_setup_focus_styling()

func _setup_game_over_export_ui() -> void:
	if game_over_panel == null or _export_btn != null:
		return
	var vbox := game_over_panel.get_node_or_null("VBoxContainer") as VBoxContainer
	if vbox == null:
		return
	game_over_panel.offset_top = -185.0
	game_over_panel.offset_bottom = 185.0

	_export_btn = Button.new()
	_export_btn.name = "ExportMatchBtn"
	_export_btn.custom_minimum_size = Vector2(200, 36)
	_export_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_export_btn.text = "Export Match (.txt)"
	_export_btn.pressed.connect(_on_export_match_pressed)

	_export_status_label = Label.new()
	_export_status_label.name = "ExportStatusLabel"
	_export_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_export_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_export_status_label.add_theme_font_size_override("font_size", 12)
	_export_status_label.add_theme_color_override("font_color", Color(0.76, 0.95, 0.78))
	_export_status_label.visible = false

	vbox.add_child(_export_btn)
	vbox.add_child(_export_status_label)
	if menu_btn != null:
		vbox.move_child(_export_btn, menu_btn.get_index())
		vbox.move_child(_export_status_label, _export_btn.get_index() + 1)
		_export_btn.focus_neighbor_bottom = menu_btn.get_path()
		_export_btn.focus_neighbor_top = menu_btn.get_path()
		menu_btn.focus_neighbor_top = _export_btn.get_path()
		menu_btn.focus_neighbor_bottom = _export_btn.get_path()

func _on_export_match_pressed() -> void:
	var result: Dictionary = MatchExporter.export_match_to_text_file(GameManager, NetworkManager)
	if _export_status_label == null:
		return
	if bool(result.get("ok", false)):
		var gpath: String = str(result.get("global_path", ""))
		DisplayServer.clipboard_set(gpath)
		_export_status_label.add_theme_color_override("font_color", Color(0.76, 0.95, 0.78))
		_export_status_label.text = "Exported: %s (full path copied)" % str(result.get("file_name", ""))
	else:
		_export_status_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.45))
		_export_status_label.text = "Export failed: %s" % str(result.get("error", "Unknown error"))
	_export_status_label.visible = true

func _setup_minimap() -> void:
	if _minimap != null or get_node_or_null("MinimapUI") != null:
		return
	_minimap = MinimapUIScript.new()
	add_child(_minimap)
	# Place above PanicVignette (index 0) and below modal overlays
	move_child(_minimap, 1)

func _setup_debug_overlay() -> void:
	_debug_overlay_label = Label.new()
	_debug_overlay_label.name = "DebugPerfOverlay"
	_debug_overlay_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_debug_overlay_label.offset_left = -220.0
	_debug_overlay_label.offset_right = -20.0
	_debug_overlay_label.offset_top = 62.0
	_debug_overlay_label.offset_bottom = 86.0
	_debug_overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_debug_overlay_label.add_theme_font_size_override("font_size", 13)
	_debug_overlay_label.add_theme_color_override("font_color", Color(0.75, 1.0, 0.78, 0.9))
	_debug_overlay_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_debug_overlay_label.visible = false
	add_child(_debug_overlay_label)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F3:
		if _debug_overlay_label != null:
			_debug_overlay_label.visible = not _debug_overlay_label.visible
			if _debug_overlay_label.visible:
				_update_debug_overlay()
			get_viewport().set_input_as_handled()

func _update_debug_overlay() -> void:
	if _debug_overlay_label == null:
		return
	var fps := Engine.get_frames_per_second()
	var ping_text := "OFFLINE"
	if multiplayer != null and multiplayer.has_multiplayer_peer():
		if multiplayer.is_server():
			ping_text = "HOST"
		elif multiplayer.multiplayer_peer is ENetMultiplayerPeer:
			var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
			var server_peer := enet.get_peer(1)
			if server_peer != null:
				var rtt := int(server_peer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))
				ping_text = "%dms" % rtt
	_debug_overlay_label.text = "FPS: %d  |  Ping: %s" % [fps, ping_text]

func _setup_spectator_banner() -> void:
	_spectator_banner = PanelContainer.new()
	_spectator_banner.name = "SpectatorBanner"
	_spectator_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_spectator_banner.offset_left = -290.0
	_spectator_banner.offset_right = 290.0
	_spectator_banner.offset_top = -125.0
	_spectator_banner.offset_bottom = -78.0
	_spectator_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spectator_banner.visible = false

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.14, 0.03, 0.04, 0.88)
	style.set_border_width_all(2)
	style.border_color = Color(0.85, 0.2, 0.2, 0.9)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	_spectator_banner.add_theme_stylebox_override("panel", style)

	var lbl := Label.new()
	lbl.name = "SpectatorLabel"
	lbl.text = "YOU WERE SACRIFICED — WATCHING REMAINING SURVIVORS"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.4, 0.35))
	_spectator_banner.add_child(lbl)
	add_child(_spectator_banner)

func _setup_panic_vignette() -> void:
	_panic_vignette = ColorRect.new()
	_panic_vignette.name = "PanicVignette"
	_panic_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panic_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panic_vignette.visible = false

	var vignette_shader := Shader.new()
	vignette_shader.code = """
shader_type canvas_item;
uniform float intensity : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 centered = UV - vec2(0.5);
	float dist = length(centered) * 1.45;
	float edge = smoothstep(0.42, 1.02, dist);
	COLOR = vec4(0.65, 0.04, 0.06, edge * intensity);
}
"""
	_panic_vignette_mat = ShaderMaterial.new()
	_panic_vignette_mat.shader = vignette_shader
	_panic_vignette_mat.set_shader_parameter("intensity", 0.0)
	_panic_vignette.material = _panic_vignette_mat
	add_child(_panic_vignette)
	move_child(_panic_vignette, 0)

func _process(delta: float) -> void:
	if _debug_overlay_label != null and _debug_overlay_label.visible:
		_debug_refresh_accum += delta
		if _debug_refresh_accum >= 0.5:
			_debug_refresh_accum = 0.0
			_update_debug_overlay()

	var is_game_over := GameManager != null and GameManager.current_state == GameManager.MatchState.GAME_OVER
	var in_panic := not is_game_over and _last_time_remaining <= 60.0 and _last_time_remaining > 0.0
	if in_panic:
		var factor := clampf((60.0 - _last_time_remaining) / 60.0, 0.0, 1.0)
		var pulse_speed := lerpf(2.6, 6.0, factor)
		_panic_phase += delta * pulse_speed
		var pulse := 0.5 + 0.5 * sin(_panic_phase)
		if _panic_vignette and _panic_vignette_mat:
			_panic_vignette.visible = true
			var intensity := lerpf(0.14, 0.52, factor) * (0.65 + 0.35 * pulse)
			_panic_vignette_mat.set_shader_parameter("intensity", intensity)
		if timer_label and _last_time_remaining <= 15.0:
			timer_label.pivot_offset = timer_label.size * 0.5
			var s := 1.0 + 0.08 * pulse
			timer_label.scale = Vector2(s, s)
		elif timer_label:
			timer_label.scale = Vector2.ONE
	else:
		if _panic_vignette:
			_panic_vignette.visible = false
		if timer_label and timer_label.scale != Vector2.ONE:
			timer_label.scale = Vector2.ONE
 
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
 
	# Connect to GameManager signals
	if GameManager:
		GameManager.match_timer_updated.connect(_on_match_timer_updated)
		GameManager.part_deposited_broadcast.connect(_on_part_deposited)
		GameManager.player_eliminated.connect(_on_player_eliminated)
		GameManager.blood_shrine_prompt_started.connect(_on_shrine_prompt_started)
		GameManager.blood_shrine_resolved.connect(_on_shrine_resolved)
		GameManager.game_over_announced.connect(_on_game_over)
		GameManager.match_state_changed.connect(_on_match_state_changed)
		GameManager.player_roster_updated.connect(_update_player_legend)
		
		# Initial timer display
		_on_match_timer_updated(GameManager.time_remaining)
		if GameManager.current_state == GameManager.MatchState.IN_PROGRESS:
			_update_player_legend()
	
	_update_score_display()
 
func _on_match_timer_updated(time_remaining: float) -> void:
	_last_time_remaining = maxf(0.0, time_remaining)
	if not timer_label:
		return
	var total_seconds: int = int(max(0.0, time_remaining))
	var minutes: int = total_seconds / 60
	var seconds: int = total_seconds % 60
	timer_label.text = "%02d:%02d" % [minutes, seconds]
	
	# Turn red under 60 seconds
	if total_seconds <= 60:
		timer_label.add_theme_color_override("font_color", Color(1.0, 0.25, 0.25))
	else:
		timer_label.add_theme_color_override("font_color", Color.WHITE)
 
func _on_part_deposited(depositor_id: int, victim_id: int, part_type: int) -> void:
	_update_score_display()
	_update_player_legend()
	
	var part_names: Array[String] = ["Head", "Hands", "Torso", "Legs"]
	var p_name: String = part_names[part_type] if part_type >= 0 and part_type < part_names.size() else "Body Part"
	var dep_name: String = _display_name(depositor_id, GameManager.get_player_color(depositor_id) if (GameManager and GameManager.players.has(depositor_id)) else ("Player " + str(depositor_id)))
	var vic_name: String = _display_name(victim_id, "Player " + str(victim_id))
	
	_show_banner("%s sacrificed %s's %s!" % [dep_name, vic_name, p_name], Color(1.0, 0.78, 0.3))
 
func _update_score_display() -> void:
	var my_id: int = multiplayer.get_unique_id()
	var my_deposited: int = 0
	if GameManager and GameManager.players.has(my_id):
		local_parts_lost = GameManager.players[my_id]["parts_lost"].size()
		my_deposited = int(GameManager.players[my_id].get("parts_deposited", 0))
	if score_label:
		score_label.text = "Your Parts Lost: %d/4   |   Parts Sacrificed: %d" % [local_parts_lost, my_deposited]
 
func _on_player_eliminated(peer_id: int, player_name: String) -> void:
	_update_score_display()
	_update_player_legend()
	_show_banner("ELIMINATED: %s was completely sacrificed!" % _display_name(peer_id, player_name), Color(1.0, 0.3, 0.3))
	if peer_id == multiplayer.get_unique_id() and _spectator_banner != null:
		_spectator_banner.visible = true
 
# Shows the player's synced custom name or falls back to "Player N".
func _display_name(peer_id: int, fallback: String) -> String:
	if GameManager:
		var dname: String = GameManager.get_player_display_name(peer_id)
		if dname != "Unknown":
			return dname
	return fallback
 
func _show_banner(text: String, color: Color = Color.WHITE) -> void:
	if banner_label:
		if _banner_tween and _banner_tween.is_valid():
			_banner_tween.kill()
		banner_label.text = text
		banner_label.add_theme_color_override("font_color", color)
		banner_label.modulate.a = 0.0
		banner_label.visible = true
		_banner_tween = create_tween()
		_banner_tween.tween_property(banner_label, "modulate:a", 1.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		if banner_timer:
			banner_timer.start(3.5)
 
func _on_banner_timeout() -> void:
	if banner_label and banner_label.visible:
		if _banner_tween and _banner_tween.is_valid():
			_banner_tween.kill()
		_banner_tween = create_tween()
		_banner_tween.tween_property(banner_label, "modulate:a", 0.0, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_banner_tween.tween_callback(func():
			if is_instance_valid(banner_label):
				banner_label.visible = false
		)
 
# ===== BLOOD SHRINE EVENT =====
func _get_local_player() -> Node:
	for player in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(player) and player.is_multiplayer_authority():
			return player
	return null

func _is_pause_menu_open() -> bool:
	var parent := get_parent()
	if parent != null:
		for child in parent.get_children():
			if child.get("is_paused") == true:
				return true
	return false

func _on_shrine_prompt_started() -> void:
	if shrine_modal:
		shrine_modal.visible = true
		shrine_accept_btn.disabled = false
		shrine_decline_btn.disabled = false
		shrine_status_label.text = ""
	var local_player := _get_local_player()
	if local_player and local_player.has_method("set_input_enabled"):
		local_player.set_input_enabled(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if shrine_accept_btn:
		shrine_accept_btn.grab_focus()
 
func _on_shrine_accept() -> void:
	if shrine_accept_btn:
		shrine_accept_btn.disabled = true
	if shrine_decline_btn:
		shrine_decline_btn.disabled = true
	shrine_status_label.text = "Accepted! Waiting for other players..."
	GameManager.submit_shrine_vote.rpc(true)
 
func _on_shrine_decline() -> void:
	if shrine_accept_btn:
		shrine_accept_btn.disabled = true
	if shrine_decline_btn:
		shrine_decline_btn.disabled = true
	shrine_status_label.text = "Declined! Waiting for other players..."
	GameManager.submit_shrine_vote.rpc(false)
 
func _on_shrine_resolved(accepted: bool) -> void:
	if shrine_modal:
		shrine_modal.visible = false
	var game_over := GameManager != null and GameManager.current_state == GameManager.MatchState.GAME_OVER
	if not _is_pause_menu_open() and not game_over:
		var local_player := _get_local_player()
		var my_id := multiplayer.get_unique_id()
		var is_alive := true
		if GameManager and GameManager.players.has(my_id):
			is_alive = bool(GameManager.players[my_id].get("is_alive", true))
		if local_player and is_alive and local_player.has_method("set_input_enabled"):
			local_player.set_input_enabled(true)
		elif is_alive:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if accepted:
		_show_banner("The Blood Deal was accepted! -20s from match clock.", Color(0.9, 0.2, 0.2))
	else:
		_show_banner("The Blood Deal was rejected by the players.", Color(0.7, 0.7, 0.7))
 
# ===== GAME OVER =====
func _on_game_over(winner_id: int, winner_name: String) -> void:
	if _spectator_banner != null:
		_spectator_banner.visible = false
	if _minimap != null:
		_minimap.visible = false
	var local_player := _get_local_player()
	if local_player and local_player.has_method("set_input_enabled"):
		local_player.set_input_enabled(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if game_over_panel:
		game_over_panel.visible = true
		if _export_status_label != null:
			_export_status_label.visible = false
		if winner_label:
			var summary := ""
			if winner_id == -1:
				summary = "GAME OVER — DRAW!"
			else:
				var is_local_winner: bool = (winner_id == multiplayer.get_unique_id())
				if is_local_winner:
					summary = "VICTORY!\nYou survived and conquered the ritual!"
				else:
					summary = "GAME OVER\nWinner: %s" % _display_name(winner_id, winner_name)
			if GameManager and not GameManager.players.is_empty():
				summary += "\n\n— Match Summary —"
				var pids: Array = GameManager.players.keys()
				pids.sort()
				for pid in pids:
					var pdata: Dictionary = GameManager.players[pid]
					var pname := _display_name(pid, str(pid))
					var dep_cnt := int(pdata.get("parts_deposited", 0))
					var lost_cnt: int = (pdata.get("parts_lost", []) as Array).size()
					var status_str := "ALIVE" if bool(pdata.get("is_alive", true)) else "SACRIFICED"
					summary += "\n%s: %d Sacrificed | %d/4 Parts Lost (%s)" % [pname, dep_cnt, lost_cnt, status_str]
			winner_label.text = summary
	if menu_btn:
		menu_btn.grab_focus()
 
func _on_menu_pressed() -> void:
	print("Menu Button Pressed After Game End!")
	NetworkManager.leave_session()
 
 
func _update_player_legend() -> void:
	if player_legend_rows == null or GameManager == null:
		return
 
	for child in player_legend_rows.get_children():
		child.queue_free()
 
	var player_ids: Array = GameManager.players.keys()
	player_ids.sort()
 
	var local_id: int = multiplayer.get_unique_id()
	const PART_CODES: Array[String] = ["H", "A", "T", "L"]
	const PART_TOOLTIPS: Array[String] = ["Head", "Arms/Hands", "Torso", "Legs"]
 
	for peer_id in player_ids:
		var player_data: Dictionary = GameManager.players[peer_id]
		var display_number: int = GameManager.get_player_display_number(peer_id)
		var color_index: int = clampi(int(player_data.get("color", 0)), 0, GameManager.PLAYER_COLOR_VALUES.size() - 1)
		var player_color: Color = GameManager.PLAYER_COLOR_VALUES[color_index]
		var parts_lost: Array = player_data.get("parts_lost", [])
		var is_alive: bool = bool(player_data.get("is_alive", true))
		var deposited_count: int = int(player_data.get("parts_deposited", 0))
 
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 5)
		var color_swatch := ColorRect.new()
		color_swatch.color = player_color if is_alive else Color(0.35, 0.1, 0.1, 0.8)
		color_swatch.custom_minimum_size = Vector2(12, 12)
		row.add_child(color_swatch)
 
		var label := Label.new()
		var custom_name: String = str(player_data.get("display_name", "")).strip_edges()
		if custom_name.is_empty():
			label.text = "P%d" % display_number
		else:
			label.text = custom_name if custom_name.length() <= 10 else (custom_name.substr(0, 9) + "…")
		if peer_id == local_id:
			label.text += " (YOU)"
		if not is_alive:
			label.text += " [DEAD]"
			label.add_theme_color_override("font_color", Color(0.75, 0.3, 0.3))
		else:
			label.add_theme_color_override("font_color", player_color.lightened(0.35))
		row.add_child(label)

		# Retro Body Part Silhouette Badges: [H] [A] [T] [L]
		for part_idx in range(4):
			var badge := Label.new()
			var is_lost := (part_idx in parts_lost)
			badge.text = "[✕]" if is_lost else ("[%s]" % PART_CODES[part_idx])
			badge.tooltip_text = "%s (%s)" % [PART_TOOLTIPS[part_idx], "Sacrificed" if is_lost else "Intact"]
			badge.add_theme_font_size_override("font_size", 11)
			if is_lost:
				badge.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2, 0.65))
			else:
				badge.add_theme_color_override("font_color", Color(0.85, 0.95, 0.85, 0.95))
			row.add_child(badge)

		if deposited_count > 0:
			var score_badge := Label.new()
			score_badge.text = "★%d" % deposited_count
			score_badge.add_theme_font_size_override("font_size", 11)
			score_badge.add_theme_color_override("font_color", Color(1.0, 0.84, 0.25))
			row.add_child(score_badge)
 
		player_legend_rows.add_child(row)
 
func _on_match_state_changed(new_state: GameManager.MatchState) -> void:
	if new_state == GameManager.MatchState.IN_PROGRESS:
		_update_score_display()
		_update_player_legend()
 
