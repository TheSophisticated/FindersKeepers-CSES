# This script extends Node3D, making it a 3D scene root
extends Node3D

@onready var world: Node = $SubViewportContainer/SubViewport/WorldObjects
@onready var spawn_points: Node = $SubViewportContainer/SubViewport/SpawnPoints
@onready var tod: TimeOfDay = $SubViewportContainer/SubViewport/Sky3D/TimeOfDay
@onready var player_spawner: MultiplayerSpawner = $MultiplayerSpawner

var nextSpawnIdx : int = 0;

# Max time the host waits for every client to finish loading the map before
# starting without the stragglers (they are spawned when they report in).
const PEER_LOAD_TIMEOUT := 20.0
var _match_running := false

# Called when the node enters the scene tree
func _enter_tree():
	# Connect multiplayer signals if multiplayer is available
	if multiplayer != null:
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)

func get_game_time() -> String:
	if tod:
		return tod.game_time
	return ""

# Called when the node is ready
func _ready():
	player_spawner.spawn_function = _create_player_from_spawn_data

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

	# If this is the server, wait for every client to load the map, then spawn
	# all players and start the match. Spawning before a client has this scene
	# loaded means the MultiplayerSpawner replication never reaches that client.
	if multiplayer != null && multiplayer.is_server():
		_start_match_when_peers_loaded()
	elif multiplayer != null and multiplayer.has_multiplayer_peer():
		# Tell the host our map is loaded and we can be spawned
		NetworkManager.report_game_loaded.rpc_id(1)

func _all_peers_loaded() -> bool:
	for peer_id in multiplayer.get_peers():
		if not NetworkManager.loaded_peers.has(peer_id):
			return false
	return true

func _start_match_when_peers_loaded() -> void:
	var waited := 0.0
	while not _all_peers_loaded() and waited < PEER_LOAD_TIMEOUT:
		await get_tree().process_frame
		if not is_inside_tree():
			return
		waited += get_process_delta_time()
	if not _all_peers_loaded():
		push_warning("GameMode: starting before every client finished loading")

	spawn_player(multiplayer.get_unique_id())
	for peer_id in NetworkManager.loaded_peers.keys():
		spawn_player(peer_id)
	GameManager.start_match()
	_match_running = true
	# Ensure MatchHUD is present under CanvasLayer
	if has_node("CanvasLayer"):
		var canvas = $CanvasLayer
		# Remove any existing MatchHUD
		var old = canvas.get_node_or_null("MatchHUD")
		if old:
			old.queue_free()
		# Instantiate a fresh MatchHUD (which includes CompassUI from the tscn)
		var hud_scene = load("res://Maps/MatchHUD.tscn")
		if hud_scene:
			var hud = hud_scene.instantiate()
			hud.name = "MatchHUD"
			canvas.add_child(hud)
	print("Match Started")

# Called on the host by NetworkManager when a client reports its map is loaded.
# Clients that report before the match starts are spawned by
# _start_match_when_peers_loaded; this handles late joiners and stragglers.
func on_peer_loaded(peer_id: int) -> void:
	if not multiplayer.is_server() or not _match_running:
		return
	spawn_player(peer_id)
	# Respawn body parts for all currently registered players
	if GameManager.body_part_spawner != null:
		GameManager.body_part_spawner.spawn_objects()

func _on_spell_center_deposited(collector: Node, part: Node) -> void:
	if collector == null or not collector.is_multiplayer_authority():
		return

	var victim_id: int = part.get("owner_id") if (part and part.get("owner_id") != null) else -1
	var part_type: int = part.get("part_type") if (part and part.get("part_type") != null) else 0

	GameManager.request_deposit_part.rpc_id(1, part_type, victim_id)

# Called when a peer disconnects
func _on_peer_disconnected(peer_id: int):
	remove_player(peer_id)

# Spawns a player for the given peer_id
func spawn_player(peer_id: int):
	if world.has_node("Player_" + str(peer_id)):
		return

	if GameManager:
		GameManager.register_player(peer_id, "Player_" + str(peer_id))

	var spawnPos : Vector3= get_next_spawn_position(nextSpawnIdx)
	var character_id: StringName = NetworkManager.get_character_id_for_peer(peer_id)
	var player := player_spawner.spawn({
		"peer_id": peer_id,
		"character_id": character_id,
		"position": spawnPos
	})
	if player == null:
		push_error("GameMode: failed to spawn player %d" % peer_id)


func _create_player_from_spawn_data(data: Variant) -> Node:
	if not data is Dictionary:
		push_error("GameMode: invalid player spawn data")
		return null
	var player_scene := load("res://Player/_Player.tscn") as PackedScene
	if player_scene == null:
		push_error("GameMode: failed to load player scene")
		return null
	var player := player_scene.instantiate()
	var peer_id := int(data.get("peer_id", 1))
	player.name = "Player_" + str(peer_id)
	player.set_multiplayer_authority(peer_id)
	player.character_id = StringName(data.get("character_id", &"player_1"))
	player.position = data.get("position", Vector3.ZERO)
	return player

func get_next_spawn_position(idx : int):
	if spawn_points:
		var points = spawn_points.get_children()
		if points.size() > 0:
			nextSpawnIdx += 1
			return points[idx].global_position
	return Vector3(0, 10, 0)

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
