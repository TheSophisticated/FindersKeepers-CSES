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
 
var local_parts_lost: int = 0
 
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
 
# Roster names are "Player_<peer_id>"; show the player number ("Player 2") instead.
func _display_name(peer_id: int, fallback: String) -> String:
	if GameManager:
		var number: int = GameManager.get_player_display_number(peer_id)
		if number != -1:
			return "Player %d" % number
	return fallback
 
func _show_banner(text: String, color: Color = Color.WHITE) -> void:
	if banner_label:
		banner_label.text = text
		banner_label.add_theme_color_override("font_color", color)
		banner_label.visible = true
		if banner_timer:
			banner_timer.start(3.5)
 
func _on_banner_timeout() -> void:
	if banner_label:
		banner_label.visible = false
 
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
	var local_player := _get_local_player()
	if local_player and local_player.has_method("set_input_enabled"):
		local_player.set_input_enabled(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if game_over_panel:
		game_over_panel.visible = true
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
		label.text = "P%d" % display_number
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
 
