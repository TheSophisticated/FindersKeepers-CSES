

# This script extends Node3D, making it a 3D scene root
extends Node3D

@onready var world: Node = $SubViewportContainer/SubViewport/WorldObjects
@onready var spawn_points: Node = $SubViewportContainer/SubViewport/SpawnPoints

# Called when the node enters the scene tree
func _enter_tree():
	# Connect multiplayer signals if multiplayer is available
	if multiplayer != null:
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)

# Called when the node is ready
func _ready():
	print("GameMode ready")
	
	# If this is the server, spawn the host player
	if multiplayer != null && multiplayer.is_server():
		spawn_player(multiplayer.get_unique_id())
		GameManager.start_match()

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
