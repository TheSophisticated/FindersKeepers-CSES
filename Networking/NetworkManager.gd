# NetworkManager.gd
# This script handles all multiplayer networking functionality

# Extends Node to act as a network manager
extends Node

# Network constants
const PORT = 8910  # Default port for connections
const MAX_PLAYERS = 4  # Maximum allowed players
var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()  # ENet networking peer

const DISCOVERY_PORT = 8911
const DISCOVERY_MESSAGE = "FINDERS_KEEPERS_HOST"

var discovery_peer : PacketPeerUDP = PacketPeerUDP.new()
var listener_peer : PacketPeerUDP = PacketPeerUDP.new()

var discovery_timer : Timer
var discovery_listen_timer : Timer

# Signals
signal player_update_received(peer_id, position, velocity, rotation, camera_rotation)

# Called when the node enters the scene tree
func _ready():
	# Connect multiplayer signals
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	
	# Set physics interpolation for smoother movement
	Engine.physics_ticks_per_second = 60
	Engine.max_physics_steps_per_frame = 10
	
# Broadcast Host Message for Clients to listen
func _broadcast_host():
	var message = DISCOVERY_MESSAGE.to_utf8_buffer()
	discovery_peer.put_packet(message)
	
	print("Broadcasting Host")

func start_host_discovery():
	discovery_peer.set_broadcast_enabled(true)
	discovery_peer.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	
	discovery_timer = Timer.new()
	discovery_timer.wait_time = 1.5
	discovery_timer.timeout.connect(_broadcast_host)
	add_child(discovery_timer)
	discovery_timer.start()
	print("LAN Discovery started on PORT: " , DISCOVERY_PORT)

# Host a new game server
func host_game():
	# Create server with specified port and max players
	var error = peer.create_server(PORT, MAX_PLAYERS)
	if error:
		print("Host error: ", error)
		show_connection_error()
		return false
	
	# Set as multiplayer peer and load game world
	multiplayer.multiplayer_peer = peer
	print("Hosting game on port ", PORT)
	start_host_discovery()
	load_game_world()
	
	return true
	
	
#Make Client Listen for Host Broadcast
func start_host_search():
	var error = listener_peer.bind(DISCOVERY_PORT)
	
	if error != OK:
		print("Could not Listen for Hosts: ", error)
		return
		
	print("Listening for Host Broadcast")
	discovery_listen_timer = Timer.new()
	discovery_listen_timer.wait_time = 0.2
	discovery_listen_timer.timeout.connect(_check_for_host)
	add_child(discovery_listen_timer)
	
	discovery_listen_timer.start()
	
	return true

func _check_for_host():
	print("Listening for LAN Hosts")
	while listener_peer.get_available_packet_count() > 0:
		var packet = listener_peer.get_packet()
		var packet_content = packet.get_string_from_utf8()
		var sender_ip = listener_peer.get_packet_ip()	
		
		if packet_content == DISCOVERY_MESSAGE:
			print("Found Host at ", sender_ip)
			listener_peer.close()
			discovery_listen_timer.stop()
			join_game(sender_ip)
			return

# Join an existing game
func join_game(ip: String = "localhost"):
	# Create client connection to specified IP
	var error = peer.create_client(ip, PORT)
	if error:
		print("Join error: ", error)
		show_connection_error()
		return false
		
	# Set as multiplayer peer
	multiplayer.multiplayer_peer = peer
	print("Joining game at ", ip)
	return true

# Show connection error through UI
func show_connection_error():
	print("Failed to connect to server")
	get_tree().call_group("ui", "show_error", "Connection failed. Make sure host is running.")

# Load the game world scene
func load_game_world():
	# Only change scene if not already in game
	if get_tree().current_scene.name != "GameMode":
		get_tree().change_scene_to_file("res://Maps/GameMode.tscn")

# Remote procedure call to load game world on clients
@rpc("any_peer", "call_local", "reliable")
func rpc_load_game_world():
	# Only server can tell clients to load game
	if multiplayer.is_server():
		load_game_world()

# Called when a new peer connects
func _on_peer_connected(id):
	print("Player connected: ", id)
	# Server tells new client to load game world
	if multiplayer.is_server():
		rpc_load_game_world.rpc_id(id)

# Called when a peer disconnects
func _on_peer_disconnected(id):
	print("Player disconnected: ", id)
	# Remove player from game if in game scene
	var game_scene = get_tree().current_scene
	if game_scene and game_scene.has_method("remove_player"):
		game_scene.remove_player(id)

# Called when successfully connected to server
func _on_connected_to_server():
	print("Successfully connected to server")
	load_game_world()

# Called when connection attempt fails
func _on_connection_failed():
	print("Connection failed")
	show_connection_error()

# Send player state update to other peers
func send_player_update(position: Vector3, velocity: Vector3, rotation: Vector3, camera_rotation: Vector3):
	if multiplayer.multiplayer_peer:
		# Send update via RPC
		rpc("_receive_player_update", position, velocity, rotation, camera_rotation)

# Receive player updates from other peers
@rpc("unreliable_ordered", "any_peer")
func _receive_player_update(position: Vector3, velocity: Vector3, rotation: Vector3, camera_rotation: Vector3):
	# Get sender ID and emit signal with update data
	var sender_id = multiplayer.get_remote_sender_id()
	player_update_received.emit(sender_id, position, velocity, rotation, camera_rotation)
