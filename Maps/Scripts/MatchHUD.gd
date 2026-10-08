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

var local_deposits: int = 0

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
		
		# Initial timer display
		_on_match_timer_updated(GameManager.time_remaining)
	
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
	var my_id: int = multiplayer.get_unique_id()
	if depositor_id == my_id or (my_id <= 1 and depositor_id <= 1):
		if GameManager and GameManager.players.has(depositor_id):
			local_deposits = GameManager.players[depositor_id]["parts_deposited"]
		else:
			local_deposits += 1
		_update_score_display()
	
	var part_names: Array[String] = ["Head", "Hands", "Torso", "Legs"]
	var p_name: String = part_names[part_type] if part_type >= 0 and part_type < part_names.size() else "Body Part"
	var dep_name: String = GameManager.get_player_color(depositor_id) if (GameManager and GameManager.players.has(depositor_id)) else ("Player " + str(depositor_id))
	
	_show_banner("%s sacrificed a %s!" % [dep_name, p_name])

func _update_score_display() -> void:
	var my_id: int = multiplayer.get_unique_id()
	if GameManager and GameManager.players.has(my_id):
		local_deposits = GameManager.players[my_id]["parts_deposited"]
	elif GameManager and GameManager.players.has(1):
		local_deposits = GameManager.players[1]["parts_deposited"]
	if score_label:
		score_label.text = "Sacrifices: %d" % local_deposits

func _on_player_eliminated(peer_id: int, player_name: String) -> void:
	_show_banner("ELIMINATED: %s was completely sacrificed!" % player_name, Color(1.0, 0.3, 0.3))

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
func _on_shrine_prompt_started() -> void:
	if shrine_modal:
		shrine_modal.visible = true
		shrine_accept_btn.disabled = false
		shrine_decline_btn.disabled = false
		shrine_status_label.text = ""
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if shrine_accept_btn:
		shrine_accept_btn.grab_focus()

func _on_shrine_accept() -> void:
	if shrine_accept_btn:
		shrine_accept_btn.disabled = true
	if shrine_decline_btn:
		shrine_decline_btn.disabled = true
	shrine_status_label.text = "Accepted! Waiting for other players..."
	GameManager.submit_shrine_vote(true)

func _on_shrine_decline() -> void:
	if shrine_accept_btn:
		shrine_accept_btn.disabled = true
	if shrine_decline_btn:
		shrine_decline_btn.disabled = true
	shrine_status_label.text = "Declined! Waiting for other players..."
	GameManager.submit_shrine_vote(false)

func _on_shrine_resolved(accepted: bool) -> void:
	if shrine_modal:
		shrine_modal.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if accepted:
		_show_banner("The Blood Deal was accepted! -20s from match clock.", Color(0.9, 0.2, 0.2))
	else:
		_show_banner("The Blood Deal was rejected by the players.", Color(0.7, 0.7, 0.7))

# ===== GAME OVER =====
func _on_game_over(winner_id: int, winner_name: String) -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if game_over_panel:
		game_over_panel.visible = true
		if winner_label:
			if winner_id == -1:
				winner_label.text = "Game Over!\nMatch ended in a Draw!"
			else:
				var is_local_winner: bool = (winner_id == multiplayer.get_unique_id())
				if is_local_winner:
					winner_label.text = "VICTORY!\nYou survived and sacrificed the most parts!"
				else:
					winner_label.text = "GAME OVER\nWinner: %s" % winner_name
	if menu_btn:
		menu_btn.grab_focus()

func _on_menu_pressed() -> void:
	get_tree().change_scene_to_file("res://MainMenu/MainMenu.tscn")
