extends Node

## Central match manager and authoritative game state controller.
## Runs globally as an autoload singleton. The host/server acts as the authority
## for match timers, rule enforcement, player eliminations, and victory conditions.


# ==============================================================================
# ENUMS & CONSTANTS
# ==============================================================================

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

const MATCH_DURATION_SECONDS: float = 300.0    # 6 minutes total round duration
const BLOOD_SHRINE_TRIGGER_TIME: float = 180.0 # Triggers halfway through (at 3:00)
const SHRINE_PENALTY_SECONDS: float = 20.0     # Time stripped if players accept the deal


# ==============================================================================
# SIGNALS
# UI, player controllers, audio, and VFX systems connect to these events.
# ==============================================================================

signal match_state_changed(new_state: MatchState)
signal match_timer_updated(time_remaining: float)
signal part_deposited_broadcast(depositor_id: int, victim_id: int, part_type: BodyPartType)
signal player_eliminated(peer_id: int, player_name: String)
signal blood_shrine_prompt_started()
signal blood_shrine_resolved(accepted: bool)
signal game_over_announced(winner_id: int, winner_name: String)


# ==============================================================================
# STATE VARIABLES
# ==============================================================================

var current_state: MatchState = MatchState.WAITING_FOR_PLAYERS
var time_remaining: float = MATCH_DURATION_SECONDS
var shrine_event_triggered: bool = false
var tarot_card_spawner : Node = null
var body_part_spawner : Node = null

## Dictionary tracking all connected players and their match progress.
## Key: peer_id (int)
## Value: Dictionary containing stats, alive status, and sacrificed parts.
var players: Dictionary = {}

## Reference to Tarot Card Spawner Object

# ==============================================================================
# ENGINE CALLBACKS
# ==============================================================================

func _ready() -> void:
	# Keep the frame-by-frame loop paused until the match is formally launched.
	set_process(false)


func _process(delta: float) -> void:
	# Only the host should count down time to prevent clients from drifting out of sync.
	if not multiplayer.is_server():
		return

	if current_state == MatchState.IN_PROGRESS or current_state == MatchState.BLOOD_SHRINE_ACTIVE:
		time_remaining -= delta
		
		# Frequently sync the authoritative time to all peers.
		sync_timer.rpc(time_remaining)

		# Trigger the Blood Shrine voting event when we cross the 3-minute threshold.
		if not shrine_event_triggered and time_remaining <= (MATCH_DURATION_SECONDS - BLOOD_SHRINE_TRIGGER_TIME):
			shrine_event_triggered = true
			trigger_blood_shrine()

		# End the round when time runs out.
		if time_remaining <= 0.0:
			time_remaining = 0.0
			end_match_by_timeout()


# ==============================================================================
# LOBBY & MATCH LIFECYCLE
# ==============================================================================

## Registers a player into the match tracker when they connect.
func register_player(peer_id: int, player_name: String) -> void:
	if not multiplayer.is_server():
		return

	# Automatically assign one of the 4 colors based on join order.
	var assigned_color: PlayerColor = players.size() as PlayerColor

	players[peer_id] = {
		"peer_id": peer_id,
		"name": player_name,
		"color": assigned_color,
		"is_alive": true,
		"parts_lost": [],        # Stores BodyPartType entries deposited against this player
		"parts_deposited": 0,    # Number of opponent parts this player has sacrificed
		"voted_shrine": false,   # Tracks participation in the Blood Shrine poll
		"voted_yes": false       # The player's actual vote
	}
	print("Registered %s (Peer ID: %d) with color %s" % [player_name, peer_id, assigned_color])


## Starts the round. Called by the lobby host once all players are ready.
func start_match() -> void:
	if not multiplayer.is_server():
		return

	time_remaining = MATCH_DURATION_SECONDS
	shrine_event_triggered = false
	current_state = MatchState.IN_PROGRESS
	set_process(true)
	
	#Spawn Tarot Cards
	if tarot_card_spawner != null:
		tarot_card_spawner.spawn_objects()
		
	#Spawn Body Parts
	if body_part_spawner != null:
		body_part_spawner.spawn_objects()
	
	# Broadcast initial player roster and match start to everyone.
	sync_match_start.rpc(players)


@rpc("authority", "call_local", "reliable")
func sync_match_start(server_players: Dictionary) -> void:
	players = server_players
	current_state = MatchState.IN_PROGRESS
	match_state_changed.emit(current_state)


@rpc("authority", "call_local", "unreliable")
func sync_timer(server_time: float) -> void:
	time_remaining = server_time
	match_timer_updated.emit(server_time)


# ==============================================================================
# BODY PART SACRIFICE & ELIMINATION
# ==============================================================================

## Triggered when a player interacts with the central altar to deposit a collected body part.
## The server validates the action before updating scores and notifying clients.
@rpc("any_peer", "call_local", "reliable")
func request_deposit_part(part_type: int, victim_id: int) -> void:
	if not multiplayer.is_server():
		return

	var depositor_id: int = multiplayer.get_remote_sender_id()
	
	# Basic validation: ensure both players exist and depositor is still alive.
	if not players.has(depositor_id) or not players.has(victim_id):
		return
	if not players[depositor_id]["is_alive"]:
		return

	# Prevent duplicate deposits if the part was already sacrificed.
	var victim_parts_lost: Array = players[victim_id]["parts_lost"]
	if part_type in victim_parts_lost:
		return

	# Record the sacrifice.
	victim_parts_lost.append(part_type)
	players[depositor_id]["parts_deposited"] += 1

	# Broadcast deposit event so clients can play animations, SFX, and update HUDs.
	broadcast_part_deposit.rpc(depositor_id, victim_id, part_type)

	# When all 4 parts (Head, Hands, Torso, Legs) are deposited, the victim is eliminated.
	if victim_parts_lost.size() >= 4:
		eliminate_player(victim_id)


@rpc("authority", "call_local", "reliable")
func broadcast_part_deposit(depositor_id: int, victim_id: int, part_type: int) -> void:
	part_deposited_broadcast.emit(depositor_id, victim_id, part_type as BodyPartType)


func eliminate_player(victim_id: int) -> void:
	players[victim_id]["is_alive"] = false
	broadcast_player_elimination.rpc(victim_id)
	check_last_player_standing()


@rpc("authority", "call_local", "reliable")
func broadcast_player_elimination(victim_id: int) -> void:
	var victim_name: String = players[victim_id]["name"] if players.has(victim_id) else "Unknown"
	player_eliminated.emit(victim_id, victim_name)


# ==============================================================================
# BLOOD SHRINE EVENT (MID-MATCH 3:00 MARK)
# ==============================================================================

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

	var sender_id: int = multiplayer.get_remote_sender_id()
	if not players.has(sender_id) or not players[sender_id]["is_alive"]:
		return

	players[sender_id]["voted_shrine"] = true
	players[sender_id]["voted_yes"] = accepted
	
	evaluate_shrine_votes()


func evaluate_shrine_votes() -> void:
	var total_alive: int = 0
	var total_votes: int = 0
	var yes_votes: int = 0

	for pid in players:
		if players[pid]["is_alive"]:
			total_alive += 1
			if players[pid]["voted_shrine"]:
				total_votes += 1
				if players[pid]["voted_yes"]:
					yes_votes += 1

	# Once all active survivors have voted, calculate the outcome.
	if total_votes >= total_alive and total_alive > 0:
		var majority_accepted: bool = yes_votes > (total_alive / 2.0)
		
		if majority_accepted:
			# Deduct time penalty if more than half of alive players agreed.
			time_remaining = max(0.0, time_remaining - SHRINE_PENALTY_SECONDS)

		# Resume normal match state and notify clients of the outcome.
		current_state = MatchState.IN_PROGRESS
		broadcast_shrine_result.rpc(majority_accepted)


@rpc("authority", "call_local", "reliable")
func broadcast_shrine_result(accepted: bool) -> void:
	blood_shrine_resolved.emit(accepted)


# ==============================================================================
# WIN CONDITIONS & GAME OVER
# ==============================================================================

## Checks if only one surviving player remains.
func check_last_player_standing() -> void:
	var active_survivors: Array = []
	for pid in players:
		if players[pid]["is_alive"]:
			active_survivors.append(pid)

	if active_survivors.size() == 1:
		conclude_match(active_survivors[0])
	elif active_survivors.size() == 0:
		conclude_match(-1) # Tie / mutual elimination


## Fallback win condition: if time runs out, the player who deposited the most parts wins.
func end_match_by_timeout() -> void:
	var top_score: int = -1
	var leading_player_id: int = -1

	for pid in players:
		if players[pid]["is_alive"] and players[pid]["parts_deposited"] > top_score:
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


#============================
# RESTART MATCH
# ==========================
