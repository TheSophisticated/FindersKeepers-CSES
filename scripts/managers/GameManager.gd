extends Node

## Central match manager and authoritative game state controller.
## Runs globally as an autoload singleton. The host/server acts as the authority
## for match timers, rule enforcement, player eliminations, and victory conditions.


# ENUMS & CONSTANTS
enum MatchState {
	WAITING_FOR_PLAYERS, ## Lobby phase before the match officially begins
	IN_PROGRESS,         ## Normal gameplay loop
	BLOOD_SHRINE_ACTIVE, ## Active mid-match voting event
	GAME_OVER            ## Match concluded, awaiting restart or return to lobby
}

enum PlayerColor {
	RED,
	BLUE,
	GREEN,
	YELLOW
}

enum BodyPartType {
	HEAD,
	HANDS,
	TORSO,
	LEGS
}

const MIN_PLAYERS: int = 2
const MAX_PLAYERS: int = 4

const MATCH_DURATION_SECONDS: float = 360.0    # 6 minutes total round duration
const BLOOD_SHRINE_TRIGGER_TIME: float = 180.0 # Triggers halfway through (at 3:00)
const SHRINE_PENALTY_SECONDS: float = 20.0     # Time stripped if players accept the deal
const TIMER_SYNC_INTERVAL: float = 0.5         # Sync timer over network twice a second



# SIGNALS
# UI, player controllers, audio, and VFX systems connect to these events.

signal match_state_changed(new_state: MatchState)
signal match_timer_updated(time_remaining: float)
signal part_deposited_broadcast(depositor_id: int, victim_id: int, part_type: BodyPartType)
signal player_eliminated(peer_id: int, player_name: String)
signal player_connection_status_changed(peer_id: int, is_connected: bool)
signal blood_shrine_prompt_started()
signal blood_shrine_resolved(accepted: bool)
signal game_over_announced(winner_id: int, winner_name: String)
signal active_parts_manifest_generated(parts_list: Array)



# STATE VARIABLES

var current_state: MatchState = MatchState.WAITING_FOR_PLAYERS
var time_remaining: float = MATCH_DURATION_SECONDS
var shrine_event_triggered: bool = false
var timer_sync_accumulator: float = 0.0

## Dictionary tracking all connected players and their match progress.
## Key: peer_id (int) -> Value: Dictionary
var players: Dictionary = {}

## Master list of all active body parts in the current match.
## Generated based on the active player count (2 to 4 players).
var active_body_parts: Array[Dictionary] = []



# ENGINE CALLBACKS

func _ready() -> void:
	# Keep the frame-by-frame loop paused until the match is formally launched.
	set_process(false)
	
	# Listen for network disconnection events
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func _process(delta: float) -> void:
	# Only the host should count down time to prevent clients from drifting out of sync.
	if not multiplayer.is_server():
		return

	if current_state == MatchState.IN_PROGRESS or current_state == MatchState.BLOOD_SHRINE_ACTIVE:
		time_remaining -= delta
		timer_sync_accumulator += delta
		
		# Throttled timer sync to avoid packet flooding
		if timer_sync_accumulator >= TIMER_SYNC_INTERVAL:
			timer_sync_accumulator = 0.0
			sync_timer.rpc(time_remaining)

		# Trigger the Blood Shrine voting event when we cross the 3-minute threshold.
		if not shrine_event_triggered and time_remaining <= (MATCH_DURATION_SECONDS - BLOOD_SHRINE_TRIGGER_TIME):
			shrine_event_triggered = true
			trigger_blood_shrine()

		# End the round when time runs out.
		if time_remaining <= 0.0:
			time_remaining = 0.0
			sync_timer.rpc(0.0)
			end_match_by_timeout()



# LOBBY & PLAYER LIFECYCLE

## Registers a player into the match tracker when they connect in the lobby.
func register_player(peer_id: int, player_name: String) -> void:
	if not multiplayer.is_server():
		return

	if players.size() >= MAX_PLAYERS:
		push_warning("Cannot register %s. Lobby is full." % player_name)
		return

	# Automatically assign one of the 4 colors based on join order.
	var assigned_color: PlayerColor = players.size() as PlayerColor

	players[peer_id] = {
		"peer_id": peer_id,
		"name": player_name,
		"color": assigned_color,
		"is_alive": true,
		"is_connected": true,    # Tracks if the player is actively in the match
		"parts_lost": [],        # Stores BodyPartType entries deposited against this player
		"parts_deposited": 0,    # Number of opponent parts this player has sacrificed
		"voted_shrine": false,   # Tracks participation in the Blood Shrine poll
		"voted_yes": false       # The player's actual vote
	}
	print("Registered %s (Peer ID: %d) with color %s" % [player_name, peer_id, assigned_color])


## Handles peer disconnects gracefully while preserving their parts in the arena.
func _on_peer_disconnected(disconnected_peer_id: int) -> void:
	# Only the server should process authoritative disconnections
	if not multiplayer.is_server():
		return

	if not players.has(disconnected_peer_id):
		return

	var player_name: String = players[disconnected_peer_id]["name"]
	print("Player disconnected: %s (ID: %d)" % [player_name, disconnected_peer_id])

	if current_state == MatchState.WAITING_FOR_PLAYERS:
		# If still in the lobby, cleanly remove them
		players.erase(disconnected_peer_id)
	else:
		# If the match is active, mark disconnected and eliminate their player character.
		# Their entry in 'players' and body parts on the map remain intact so others can collect them.
		players[disconnected_peer_id]["is_connected"] = false
		players[disconnected_peer_id]["is_alive"] = false
		
		broadcast_player_connection_change.rpc(disconnected_peer_id, false)
		broadcast_player_elimination.rpc(disconnected_peer_id)
		
		# If Blood Shrine poll was waiting on this player, evaluate without them
		if current_state == MatchState.BLOOD_SHRINE_ACTIVE:
			evaluate_shrine_votes()

		# Check if only one connected survivor remains
		check_last_player_standing()


@rpc("authority", "call_local", "reliable")
func broadcast_player_connection_change(peer_id: int, is_connected: bool) -> void:
	player_connection_status_changed.emit(peer_id, is_connected)


## Starts the round. Called by the lobby host once all players are ready.
func start_match() -> void:
	if not multiplayer.is_server():
		return

	if players.size() < MIN_PLAYERS:
		push_warning("Cannot start match. Minimum %d players required." % MIN_PLAYERS)
		return

	time_remaining = MATCH_DURATION_SECONDS
	timer_sync_accumulator = 0.0
	shrine_event_triggered = false
	current_state = MatchState.IN_PROGRESS
	
	# Generate only the body parts corresponding to currently connected players
	generate_active_body_parts()
	
	set_process(true)
	
	# Broadcast initial player roster and match start to everyone.
	sync_match_start.rpc(players, active_body_parts)


@rpc("authority", "call_local", "reliable")
func sync_match_start(server_players: Dictionary, server_active_parts: Array) -> void:
	players = server_players
	active_body_parts.assign(server_active_parts)
	current_state = MatchState.IN_PROGRESS
	match_state_changed.emit(current_state)
	active_parts_manifest_generated.emit(active_body_parts)


@rpc("authority", "call_local", "unreliable")
func sync_timer(server_time: float) -> void:
	time_remaining = server_time
	match_timer_updated.emit(server_time)



# DYNAMIC BODY PART GENERATION (2-4 PLAYERS)

## Builds the manifest of body parts to spawn.
## Only parts belonging to connected players are created (8, 12, or 16 parts total).
func generate_active_body_parts() -> void:
	active_body_parts.clear()
	
	var all_part_types: Array[BodyPartType] = [
		BodyPartType.HEAD,
		BodyPartType.HANDS,
		BodyPartType.TORSO,
		BodyPartType.LEGS
	]

	for pid: int in players.keys():
		var p_color: PlayerColor = players[pid]["color"]
		
		for part_type: BodyPartType in all_part_types:
			var part_record: Dictionary = {
				"part_id": "part_%d_%d" % [pid, part_type],
				"owner_peer_id": pid,
				"owner_color": p_color,
				"part_type": part_type,
				"is_deposited": false
			}
			active_body_parts.append(part_record)

	print("Generated %d active body parts for %d players." % [active_body_parts.size(), players.size()])


## Helper function to check if a specific part is valid in this match.
## Remains valid even if the owner disconnected, until sacrificed at the altar.
func is_part_valid(owner_peer_id: int, part_type: int) -> bool:
	if not players.has(owner_peer_id):
		return false
	return not (part_type in players[owner_peer_id]["parts_lost"])



# BODY PART SACRIFICE & ELIMINATION

## Triggered when a player interacts with the central altar to deposit a collected body part.
## The server validates the action before updating scores and notifying clients.
@rpc("any_peer", "call_local", "reliable")
func request_deposit_part(part_type: int, victim_id: int) -> void:
	if not multiplayer.is_server():
		return

	# Handle both remote callers and local host caller (sender_id == 0 means host)
	var depositor_id: int = multiplayer.get_remote_sender_id()
	if depositor_id == 0:
		depositor_id = multiplayer.get_unique_id()
	
	# Ensure depositor is connected and alive, and victim is a valid match entry
	if not players.has(depositor_id) or not players.has(victim_id):
		return
	if not players[depositor_id]["is_alive"]:
		return

	# Prevent duplicate deposits if the part was already sacrificed
	var victim_parts_lost: Array = players[victim_id]["parts_lost"]
	if part_type in victim_parts_lost:
		return

	# Record the sacrifice and award the point to the depositor
	victim_parts_lost.append(part_type)
	players[depositor_id]["parts_deposited"] += 1
	
	# Mark the part as deposited in the active manifest
	for part_entry in active_body_parts:
		if part_entry["owner_peer_id"] == victim_id and part_entry["part_type"] == part_type:
			part_entry["is_deposited"] = true
			break

	# Broadcast deposit event so clients can play animations, SFX, and update HUDs
	broadcast_part_deposit.rpc(depositor_id, victim_id, part_type)

	# When all 4 parts (Head, Hands, Torso, Legs) are deposited, the victim is fully eliminated
	if victim_parts_lost.size() >= 4:
		eliminate_player(victim_id)


@rpc("authority", "call_local", "reliable")
func broadcast_part_deposit(depositor_id: int, victim_id: int, part_type: int) -> void:
	part_deposited_broadcast.emit(depositor_id, victim_id, part_type as BodyPartType)


func eliminate_player(victim_id: int) -> void:
	if not players.has(victim_id) or not players[victim_id]["is_alive"]:
		return
		
	players[victim_id]["is_alive"] = false
	broadcast_player_elimination.rpc(victim_id)
	check_last_player_standing()


@rpc("authority", "call_local", "reliable")
func broadcast_player_elimination(victim_id: int) -> void:
	var victim_name: String = players[victim_id]["name"] if players.has(victim_id) else "Unknown"
	player_eliminated.emit(victim_id, victim_name)



# BLOOD SHRINE EVENT (MID-MATCH 3:00 MARK)

## Initiates the voting phase where players decide whether to accept powerful power-ups
## in exchange for losing 20 seconds from the global match clock.
func trigger_blood_shrine() -> void:
	current_state = MatchState.BLOOD_SHRINE_ACTIVE
	
	for pid in players:
		players[pid]["voted_shrine"] = false
		players[pid]["voted_yes"] = false
		
	broadcast_shrine_prompt.rpc()


@rpc("authority", "call_local", "reliable")
func broadcast_shrine_prompt() -> void:
	blood_shrine_prompt_started.emit()


## Receives an individual player's vote on whether to accept the Blood Shrine offer.
@rpc("any_peer", "call_local", "reliable")
func submit_shrine_vote(accepted: bool) -> void:
	if not multiplayer.is_server():
		return

	# Handle both remote callers and local host caller (sender_id == 0 means host)
	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()

	if not players.has(sender_id) or not players[sender_id]["is_alive"] or not players[sender_id]["is_connected"]:
		return

	players[sender_id]["voted_shrine"] = true
	players[sender_id]["voted_yes"] = accepted
	
	evaluate_shrine_votes()


func evaluate_shrine_votes() -> void:
	var total_connected_alive: int = 0
	var total_votes: int = 0
	var yes_votes: int = 0

	for pid in players:
		# Only require votes from players who are currently connected and alive
		if players[pid]["is_alive"] and players[pid]["is_connected"]:
			total_connected_alive += 1
			if players[pid]["voted_shrine"]:
				total_votes += 1
				if players[pid]["voted_yes"]:
					yes_votes += 1

	# Once all active connected survivors have voted, calculate the outcome
	if total_votes >= total_connected_alive and total_connected_alive > 0:
		var majority_accepted: bool = yes_votes > (total_connected_alive / 2.0)
		
		if majority_accepted:
			time_remaining = max(0.0, time_remaining - SHRINE_PENALTY_SECONDS)

		current_state = MatchState.IN_PROGRESS
		broadcast_shrine_result.rpc(majority_accepted)


@rpc("authority", "call_local", "reliable")
func broadcast_shrine_result(accepted: bool) -> void:
	blood_shrine_resolved.emit(accepted)



# WIN CONDITIONS & GAME OVER

## Checks if only one connected, surviving player remains during an active match.
func check_last_player_standing() -> void:
	# Only evaluate win conditions if the game is actually active
	if current_state != MatchState.IN_PROGRESS and current_state != MatchState.BLOOD_SHRINE_ACTIVE:
		return

	var active_survivors: Array = []
	for pid in players:
		if players[pid]["is_alive"] and players[pid]["is_connected"]:
			active_survivors.append(pid)

	if active_survivors.size() == 1:
		conclude_match(active_survivors[0])
	elif active_survivors.size() == 0:
		conclude_match(-1) # Tie / mutual elimination


## Fallback win condition: if time runs out, the player who deposited the most parts wins.
func end_match_by_timeout() -> void:
	if current_state != MatchState.IN_PROGRESS and current_state != MatchState.BLOOD_SHRINE_ACTIVE:
		return

	var top_score: int = -1
	var leading_player_id: int = -1

	for pid in players:
		if players[pid]["is_connected"] and players[pid]["parts_deposited"] > top_score:
			top_score = players[pid]["parts_deposited"]
			leading_player_id = pid

	conclude_match(leading_player_id)


func conclude_match(winner_id: int) -> void:
	current_state = MatchState.GAME_OVER
	set_process(false)
	
	var winner_name: String = "No one (Tie)"
	if winner_id != -1 and players.has(winner_id):
		winner_name = players[winner_id]["name"]
		
	broadcast_game_over.rpc(winner_id, winner_name)


@rpc("authority", "call_local", "reliable")
func broadcast_game_over(winner_id: int, winner_name: String) -> void:
	current_state = MatchState.GAME_OVER
	game_over_announced.emit(winner_id, winner_name)