

# This script extends Node3D, making it a 3D scene root
extends Node3D

@onready var world: Node = $SubViewportContainer/SubViewport/WorldObjects
@onready var spawn_points: Node = $SubViewportContainer/SubViewport/SpawnPoints
@onready var tod: TimeOfDay = $SubViewportContainer/SubViewport/Sky3D/TimeOfDay



# Called when the node enters the scene tree
func _enter_tree():
	# Connect multiplayer signals if multiplayer is available
	if multiplayer != null:
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)

# Called when the node is ready
func _ready():
	print("GameMode ready")
	

	# Must happen here, not the Inspector — TimeOfDay._ready() forces 18:30
	tod.set_time(17, 0, 0)      # hour, minute, second
	tod.minutes_per_day = 5.0   # one full cycle per 5 real minutes = one match
	tod.pause()

	
	# If running standalone (e.g. F6) without an active peer, initialize local server peer
	if multiplayer != null and not multiplayer.has_multiplayer_peer():
		var peer = ENetMultiplayerPeer.new()
		var err = peer.create_server(7000, 4)
		if err == OK:
			multiplayer.multiplayer_peer = peer
			print("GameMode: Initialized local standalone server peer")
		else:
			print("GameMode: Could not create local server peer, error: ", err)

	# Attach MatchHUD under CanvasLayer if not already present
	if has_node("CanvasLayer") and not has_node("CanvasLayer/MatchHUD"):
		var hud_scene = load("res://Maps/MatchHUD.tscn")
		if hud_scene:
			var hud = hud_scene.instantiate()
			hud.name = "MatchHUD"
			$CanvasLayer.add_child(hud)
	
	# Connect to SpellCenter.part_deposited signal as a rock-solid failsafe
	var spell_center = world.get_node_or_null("SpellCenter")
	if spell_center and not spell_center.part_deposited.is_connected(_on_spell_center_deposited):
		spell_center.part_deposited.connect(_on_spell_center_deposited)
		print("GameMode: Connected to SpellCenter.part_deposited")

	# If this is the server, spawn the host player
	if multiplayer != null && multiplayer.is_server():
		spawn_player(multiplayer.get_unique_id())
		GameManager.start_match()
		print("Match Started")

func _on_spell_center_deposited(collector: Node, part: Node) -> void:
	print("GameMode: SpellCenter deposit event triggered by ", collector.name if collector else "unknown")
	if collector == null or  not collector.is_multiplayer_authority():
		return
	#var depositor_id: int = 1
	#if collector:
		#if collector.get("player_id") != null and collector.player_id > 0:
			#depositor_id = collector.player_id
		#elif collector.name.contains("_"):
			#depositor_id = collector.name.get_slice("_", 1).to_int()

	var victim_id: int = part.get("owner_id") if (part and part.get("owner_id") != null) else -1
	var part_type: int = part.get("part_type") if (part and part.get("part_type") != null) else 0

	GameManager.request_deposit_part.rpc_id(1, part_type, victim_id)

	## 1. Update GameManager state
	#if GameManager:
		#if not GameManager.players.has(depositor_id):
			#GameManager.register_player(depositor_id, "Player_" + str(depositor_id))
		#if GameManager.players.has(depositor_id):
			#GameManager.players[depositor_id]["parts_deposited"] += 1
			#print("GameMode: Incremented GameManager parts_deposited to ", GameManager.players[depositor_id]["parts_deposited"])
		#
		## Broadcast or emit directly
		#if GameManager.has_method("broadcast_part_deposit"):
			#GameManager.broadcast_part_deposit(depositor_id, victim_id, part_type)
		#elif GameManager.has_signal("part_deposited_broadcast"):
			#GameManager.part_deposited_broadcast.emit(depositor_id, victim_id, part_type)
#
	## 2. Directly notify MatchHUD
	#var hud = $CanvasLayer.get_node_or_null("MatchHUD")
	#if hud and hud.has_method("_on_part_deposited"):
		#hud._on_part_deposited(depositor_id, victim_id, part_type)

# Called when a new peer connects
func _on_peer_connected(peer_id: int):
	# Only the server handles player spawning
	if multiplayer.is_server():
		print("Peer connected to GameMode: ", peer_id)
		spawn_player(peer_id)

# Called when a peer disconnects
func _on_peer_disconnected(peer_id: int):
	print("Peer disconnected from GameMode: ", peer_id)
	remove_player(peer_id)

# Spawns a player for the given peer_id
func spawn_player(peer_id: int):
	if world.has_node("Player_" + str(peer_id)):
		return

	# Register player into authoritative match state
	if GameManager:
		GameManager.register_player(peer_id, "Player_" + str(peer_id))

	var player_scene = load("res://Player/_Player.tscn")
	var player = player_scene.instantiate()
	player.name = "Player_" + str(peer_id)

	world.add_child(player, true)
	player.global_position = get_random_spawn_position()

	print("Spawned player: ", player.name)

func remove_player(peer_id: int):
	var player = world.get_node_or_null("Player_" + str(peer_id))
	if player:
		player.queue_free()
		print("Removed player: ", peer_id)

func get_random_spawn_position() -> Vector3:
	if spawn_points:
		var points = spawn_points.get_children()
		if points.size() > 0:
			return points[randi() % points.size()].global_position
	return Vector3(0, 1, 0)
