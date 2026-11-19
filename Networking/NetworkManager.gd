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
 
const LOBBY_SCENE = "res://MainMenu/Lobby.tscn"
## Keep the full map scene and its resources resident from application startup.
const GAME_MODE_SCENE: PackedScene = preload("res://Maps/GameMode.tscn")
var match_started := false  # Set once the host leaves the lobby and starts the match
var loaded_peers := {}  # Server only: client peer IDs whose GameMode scene has finished loading
var player_character_selections: Dictionary = {}
const CHARACTER_CATALOG: CharacterCatalog = preload("res://Models/characters/Definitions/CharacterCatalog.tres")
const DEFAULT_CHARACTER_ID: StringName = &"player_1"
 
# Signals
signal player_update_received(peer_id, position, velocity, rotation, camera_rotation)
signal character_selections_changed(selections: Dictionary)
 
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
	match_started = false
	player_character_selections.clear()
	player_character_selections[1] = DEFAULT_CHARACTER_ID
	GameManager.reset_state()
	start_host_discovery()
	load_lobby()
	
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
	player_character_selections.clear()
	GameManager.reset_state()
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
		get_tree().change_scene_to_packed(GAME_MODE_SCENE)
 
# Load the pre-match lobby where players gather before the host starts
func load_lobby():
	get_tree().change_scene_to_file(LOBBY_SCENE)
 
# Called by the host from the lobby: moves every connected peer into the match
func start_game():
	if not multiplayer.is_server():
		return
	match_started = true
	loaded_peers.clear()
	rpc_start_game.rpc()
 
# Sent by the host to all peers (including itself) to leave the lobby for the match
@rpc("authority", "call_local", "reliable")
func rpc_start_game():
	load_game_world()
 
# Leave the current session (host or client) and return to the main menu
func leave_session():
	if discovery_timer:
		discovery_timer.queue_free()
		discovery_timer = null
	discovery_peer.close()
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	match_started = false
	loaded_peers.clear()
	player_character_selections.clear()
	GameManager.reset_state()
	get_tree().change_scene_to_file("res://MainMenu/MainMenu.tscn")


func get_local_character_id() -> StringName:
	return player_character_selections.get(multiplayer.get_unique_id(), DEFAULT_CHARACTER_ID)


func get_character_id_for_peer(peer_id: int) -> StringName:
	return player_character_selections.get(peer_id, DEFAULT_CHARACTER_ID)


func is_character_available(character_id: StringName, peer_id: int) -> bool:
	for selected_peer_id in player_character_selections:
		if int(selected_peer_id) != peer_id and player_character_selections[selected_peer_id] == character_id:
			return false
	return true


func select_local_character(character_id: StringName) -> void:
	if CHARACTER_CATALOG.get_character(character_id) == null:
		return
	var peer_id := multiplayer.get_unique_id()
	if not is_character_available(character_id, peer_id):
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		rpc_submit_character_selection.rpc_id(1, character_id)
		return
	player_character_selections[peer_id] = character_id
	_broadcast_character_selections()


func request_character_selections() -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		rpc_request_character_selections.rpc_id(1)
	elif multiplayer.is_server():
		character_selections_changed.emit(player_character_selections.duplicate())


func _assign_character_if_needed(peer_id: int) -> void:
	if player_character_selections.has(peer_id):
		return
	for definition in CHARACTER_CATALOG.characters:
		if is_character_available(definition.character_id, peer_id):
			player_character_selections[peer_id] = definition.character_id
			return


func _broadcast_character_selections() -> void:
	var selections := player_character_selections.duplicate()
	character_selections_changed.emit(selections)
	if multiplayer.is_server() and multiplayer.has_multiplayer_peer():
		rpc_sync_character_selections.rpc(selections)


@rpc("any_peer", "reliable")
func rpc_request_character_selections() -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	_assign_character_if_needed(peer_id)
	rpc_sync_character_selections.rpc_id(peer_id, player_character_selections.duplicate())


@rpc("authority", "call_remote", "reliable")
func rpc_sync_character_selections(selections: Dictionary) -> void:
	player_character_selections = selections.duplicate()
	character_selections_changed.emit(player_character_selections.duplicate())


@rpc("any_peer", "call_remote", "reliable")
func rpc_submit_character_selection(character_id: StringName) -> void:
	if not multiplayer.is_server() or CHARACTER_CATALOG.get_character(character_id) == null:
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if is_character_available(character_id, peer_id):
		player_character_selections[peer_id] = character_id
		_broadcast_character_selections()
	else:
		rpc_sync_character_selections.rpc_id(peer_id, player_character_selections.duplicate())
 
# Remote procedure call to load game world on clients
@rpc("any_peer", "call_local", "reliable")
func rpc_load_game_world():
	# Only server can tell clients to load game
	if multiplayer.is_server():
		load_game_world()
 
# Called when a new peer connects
func _on_peer_connected(id):
	print("Player connected: ", id)
	if multiplayer.is_server():
		var p = peer.get_peer(id)
		if p:
			p.set_timeout(32, 600000, 900000)
		_assign_character_if_needed(id)
		_broadcast_character_selections()
	# Late joiners go straight into a running match; otherwise they wait in the lobby
	if multiplayer.is_server() and match_started:
		rpc_start_game.rpc_id(id)
 
# Called when a peer disconnects
func _on_peer_disconnected(id):
	print("Player disconnected: ", id)
	loaded_peers.erase(id)
	if multiplayer.is_server() and player_character_selections.erase(id):
		_broadcast_character_selections()
	# Remove player from game if in game scene
	var game_scene = get_tree().current_scene
	if game_scene and game_scene.has_method("remove_player"):
		game_scene.remove_player(id)
 
# Sent by a client once its GameMode scene is ready. This lives on the autoload
# rather than on GameMode so the host always receives it, even if the host is
# still loading the map (an RPC to a node that doesn't exist yet is dropped).
@rpc("any_peer", "reliable")
func report_game_loaded():
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	loaded_peers[id] = true
	var game_scene = get_tree().current_scene
	if game_scene and game_scene.has_method("on_peer_loaded"):
		game_scene.on_peer_loaded(id)
 
# Called when successfully connected to server
func _on_connected_to_server():
	print("Successfully connected to server")
	
	var p = peer.get_peer(1)
	if p:
		p.set_timeout(32, 600000, 900000)
	load_lobby()
 
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
 
