extends Node

## Central Horror Audio Manager for Finders Keepers.
## Runs globally as an Autoload singleton.
## Manages eerie background ambience, dynamic tension heartbeat, ritual stingers,
## 45-second heavy breathing clips, and non-invasively attaches PlayerAudioController.

# Preloaded / Loaded Horror Sounds
var SND_AMBIENCE: AudioStream = null
var SND_HEARTBEAT: AudioStream = null
var SND_RITUAL_DEPOSIT: AudioStream = null
var SND_PLAYER_ELIMINATED: AudioStream = null
var SND_BLOOD_SHRINE: AudioStream = null
var SND_TAROT_ACTIVATE: AudioStream = null
var SND_BREATHING: AudioStream = null
var SND_CHURCH_BELL: AudioStream = null

const PLAYER_AUDIO_CONTROLLER_SCRIPT = preload("res://Audio/Scripts/PlayerAudioController.gd")

# Players
var ambience_player: AudioStreamPlayer = null
var heartbeat_player: AudioStreamPlayer = null
var global_sfx_player: AudioStreamPlayer = null
var breathing_player: AudioStreamPlayer = null

# Breathing Timer (45 seconds)
var breathing_timer: Timer = null
const BREATHING_INTERVAL: float = 45.0

# Ambience fade
var target_ambience_volume: float = -4.0
var current_ambience_volume: float = -40.0
var is_ambience_playing: bool = false

# Heartbeat state
var is_heartbeat_active: bool = false

# Window focus mute state (keeps multi-instance local playtesting clean)
var _muted_by_focus_loss: bool = false
var _was_master_muted_before_blur: bool = false

func _load_sound(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		return load(path) as AudioStream
	return null

func _init() -> void:
	# Instantiate players early
	ambience_player = AudioStreamPlayer.new()
	ambience_player.name = "HorrorAmbiencePlayer"
	ambience_player.volume_db = -40.0
	ambience_player.finished.connect(_on_ambience_finished)

	heartbeat_player = AudioStreamPlayer.new()
	heartbeat_player.name = "HeartbeatTensionPlayer"
	heartbeat_player.volume_db = -40.0
	heartbeat_player.finished.connect(_on_heartbeat_finished)

	global_sfx_player = AudioStreamPlayer.new()
	global_sfx_player.name = "GlobalHorrorSFXPlayer"

	breathing_player = AudioStreamPlayer.new()
	breathing_player.name = "HeavyBreathingPlayer"
	breathing_player.volume_db = 2.0

	# Breathing timer
	breathing_timer = Timer.new()
	breathing_timer.name = "HeavyBreathingTimer"
	breathing_timer.wait_time = BREATHING_INTERVAL
	breathing_timer.one_shot = false
	breathing_timer.autostart = true
	breathing_timer.timeout.connect(_on_breathing_timer_timeout)

	# Load sounds
	SND_AMBIENCE = _load_sound("res://Audio/Ambience/horror_ambience.wav")
	SND_HEARTBEAT = _load_sound("res://Audio/Ambience/heartbeat.wav")
	SND_RITUAL_DEPOSIT = _load_sound("res://Audio/SFX/Ritual/ritual_deposit.wav")
	SND_PLAYER_ELIMINATED = _load_sound("res://Audio/SFX/Ritual/player_eliminated.wav")
	SND_BLOOD_SHRINE = _load_sound("res://Audio/SFX/Ritual/blood_shrine.wav")
	SND_TAROT_ACTIVATE = _load_sound("res://Audio/SFX/Ritual/tarot_activate.wav")
	SND_BREATHING = _find_breathing_clip()
	SND_CHURCH_BELL = _load_sound("res://Audio/SFX/Church/church_bell_creepy.mp3")

	if SND_AMBIENCE:
		ambience_player.stream = SND_AMBIENCE
	if SND_HEARTBEAT:
		heartbeat_player.stream = SND_HEARTBEAT
	if SND_BREATHING:
		breathing_player.stream = SND_BREATHING

func _enter_tree() -> void:
	_setup_audio_buses()

	if ambience_player and not ambience_player.is_inside_tree():
		ambience_player.bus = &"Ambience" if AudioServer.get_bus_index(&"Ambience") != -1 else &"Master"
		add_child(ambience_player)

	if heartbeat_player and not heartbeat_player.is_inside_tree():
		heartbeat_player.bus = &"Heartbeat" if AudioServer.get_bus_index(&"Heartbeat") != -1 else &"Master"
		add_child(heartbeat_player)

	if global_sfx_player and not global_sfx_player.is_inside_tree():
		global_sfx_player.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") != -1 else &"Master"
		add_child(global_sfx_player)

	if breathing_player and not breathing_player.is_inside_tree():
		breathing_player.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") != -1 else &"Master"
		add_child(breathing_player)

	if breathing_timer and not breathing_timer.is_inside_tree():
		add_child(breathing_timer)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Listen to tree node additions to dynamically attach PlayerAudioController
	get_tree().node_added.connect(_on_node_added)

	# Check for any players already existing in the tree
	_scan_for_existing_players()

	# Connect to GameManager signals safely
	_connect_game_manager_signals()

	# Start initial ambience and breathing timer
	start_ambience()
	if breathing_timer and breathing_timer.is_stopped():
		breathing_timer.start(BREATHING_INTERVAL)

func _setup_audio_buses() -> void:
	_ensure_bus("SFX", "Master", 0.0)
	_ensure_bus("Ambience", "Master", -4.0)
	_ensure_bus("Footsteps", "SFX", 0.0)
	_ensure_bus("Heartbeat", "Master", 0.0)

func _ensure_bus(bus_name: StringName, send_to: StringName, default_volume_db: float) -> void:
	if AudioServer.get_bus_index(bus_name) == -1:
		var idx = AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, send_to)
		AudioServer.set_bus_volume_db(idx, default_volume_db)

func _process(delta: float) -> void:
	# Smoothly fade ambience volume
	if is_ambience_playing and ambience_player and current_ambience_volume < target_ambience_volume:
		current_ambience_volume = lerp(current_ambience_volume, target_ambience_volume, delta * 1.5)
		ambience_player.volume_db = current_ambience_volume

func _notification(what: int) -> void:
	var master_idx := AudioServer.get_bus_index(&"Master")
	if master_idx == -1:
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if not _muted_by_focus_loss:
			_was_master_muted_before_blur = AudioServer.is_bus_mute(master_idx)
			AudioServer.set_bus_mute(master_idx, true)
			_muted_by_focus_loss = true
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		if _muted_by_focus_loss:
			_muted_by_focus_loss = false
			var settings_node := get_node_or_null("/root/Settings")
			if settings_node and settings_node.has_method("apply_audio_settings"):
				settings_node.apply_audio_settings()
			else:
				AudioServer.set_bus_mute(master_idx, _was_master_muted_before_blur)

func start_ambience() -> void:
	if SND_AMBIENCE == null or ambience_player == null or not is_inside_tree():
		return
	is_ambience_playing = true
	current_ambience_volume = -40.0
	ambience_player.volume_db = current_ambience_volume
	ambience_player.play()

func _on_ambience_finished() -> void:
	if is_ambience_playing and ambience_player and is_inside_tree():
		ambience_player.play()

func _on_heartbeat_finished() -> void:
	if is_heartbeat_active and heartbeat_player and is_inside_tree():
		heartbeat_player.play()

# ===== 45-SECOND HEAVY BREATHING SYSTEM =====

func _on_breathing_timer_timeout() -> void:
	play_heavy_breathing()

func play_heavy_breathing() -> void:
	# Check if the user placed or replaced their own breathing clip
	var clip := _find_breathing_clip()
	if clip == null:
		return

	if breathing_player and is_inside_tree():
		breathing_player.stream = clip
		breathing_player.volume_db = randf_range(1.0, 3.0)
		breathing_player.pitch_scale = randf_range(0.96, 1.04)
		breathing_player.play()
		print("[AudioManager] Played 45s heavy breathing audio clip.")

func _find_breathing_clip() -> AudioStream:
	var potential_paths: Array[String] = [
		"res://Audio/SFX/Player/heavy_breathing.mp3",
		"res://Audio/SFX/Player/heavy_breathing.wav",
		"res://Audio/heavy_breathing.mp3",
		"res://Audio/heavy_breathing.wav",
		"res://Audio/Ambience/heavy_breathing.mp3",
		"res://Audio/Ambience/heavy_breathing.wav",
		"res://Audio/heavy_breathing_clip.mp3",
		"res://Audio/heavy_breathing_clip.wav",
	]

	for path in potential_paths:
		if ResourceLoader.exists(path):
			var s = load(path) as AudioStream
			if s != null:
				return s

	return null

func play_church_bell() -> void:
	if SND_CHURCH_BELL and global_sfx_player and is_inside_tree():
		global_sfx_player.stream = SND_CHURCH_BELL
		global_sfx_player.volume_db = -2.0
		global_sfx_player.play()
		print("[AudioManager] Played creepy church bell toll.")

# ===== PLAYER & EVENT MANAGEMENT =====

func _connect_game_manager_signals() -> void:
	var gm = get_node_or_null("/root/GameManager")
	if gm == null:
		return

	if gm.has_signal("match_state_changed"):
		gm.match_state_changed.connect(_on_match_state_changed)
	if gm.has_signal("match_timer_updated"):
		gm.match_timer_updated.connect(_on_match_timer_updated)
	if gm.has_signal("part_deposited_broadcast"):
		gm.part_deposited_broadcast.connect(_on_part_deposited)
	if gm.has_signal("player_eliminated"):
		gm.player_eliminated.connect(_on_player_eliminated)
	if gm.has_signal("blood_shrine_prompt_started"):
		gm.blood_shrine_prompt_started.connect(_on_blood_shrine_prompt)
	if gm.has_signal("blood_shrine_resolved"):
		gm.blood_shrine_resolved.connect(_on_blood_shrine_resolved)

func _scan_for_existing_players() -> void:
	for player_node in get_tree().get_nodes_in_group("player"):
		_attach_player_audio_controller(player_node)

func _on_node_added(node: Node) -> void:
	if node is CharacterBody3D and (node.is_in_group("player") or node.name.begins_with("Player")):
		call_deferred("_attach_player_audio_controller", node)

func _attach_player_audio_controller(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if not node is CharacterBody3D:
		return
	if node.has_node("PlayerAudioController"):
		return

	var audio_controller = Node3D.new()
	audio_controller.name = "PlayerAudioController"
	audio_controller.set_script(PLAYER_AUDIO_CONTROLLER_SCRIPT)
	node.add_child(audio_controller)
	print("AudioManager: Attached PlayerAudioController to ", node.name)

# ===== GAME EVENT HANDLERS =====

func _on_match_state_changed(new_state) -> void:
	var gm = get_node_or_null("/root/GameManager")
	if gm and "MatchState" in gm:
		if new_state == gm.MatchState.IN_PROGRESS:
			target_ambience_volume = -3.0
			if not is_ambience_playing:
				start_ambience()
			if breathing_timer and breathing_timer.is_stopped():
				breathing_timer.start(BREATHING_INTERVAL)
		elif new_state == gm.MatchState.GAME_OVER:
			is_heartbeat_active = false
			if heartbeat_player:
				heartbeat_player.stop()
			target_ambience_volume = -12.0

func _on_match_timer_updated(time_remaining: float) -> void:
	# Heartbeat tension system under 60 seconds
	if heartbeat_player == null:
		return

	if time_remaining <= 60.0 and time_remaining > 0.0:
		if not is_heartbeat_active:
			is_heartbeat_active = true
			if SND_HEARTBEAT and is_inside_tree() and not heartbeat_player.playing:
				heartbeat_player.play()

		# Progressively raise volume & heart rate pitch as time expires
		var factor: float = clamp((60.0 - time_remaining) / 60.0, 0.0, 1.0)
		heartbeat_player.volume_db = lerp(-14.0, 4.0, factor)

		# Pitch from 1.0 (75 BPM) to 1.38 (panic rate)
		if time_remaining < 30.0:
			var panic_factor: float = (30.0 - time_remaining) / 30.0
			heartbeat_player.pitch_scale = lerp(1.0, 1.38, panic_factor)
		else:
			heartbeat_player.pitch_scale = 1.0
	else:
		if is_heartbeat_active:
			is_heartbeat_active = false
			heartbeat_player.stop()

func _on_part_deposited(_depositor_id: int, _victim_id: int, _part_type: int) -> void:
	# Play ominous ritual deposit stinger
	play_sfx(SND_RITUAL_DEPOSIT, 4.0, randf_range(0.97, 1.03))

func _on_player_eliminated(_peer_id: int, _player_name: String) -> void:
	# Play horrifying death knell & distant screech
	play_sfx(SND_PLAYER_ELIMINATED, 5.0, randf_range(0.96, 1.02))

func _on_blood_shrine_prompt() -> void:
	# Demonic pact stinger
	play_sfx(SND_BLOOD_SHRINE, 4.0, 1.0)

func _on_blood_shrine_resolved(accepted: bool) -> void:
	if accepted:
		play_sfx(SND_TAROT_ACTIVATE, 3.5, 0.92)

# ===== PUBLIC PLAY HELPER METHODS =====

func play_sfx(stream: AudioStream, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	if stream == null or not is_inside_tree():
		return
	var p = AudioStreamPlayer.new()
	p.stream = stream
	p.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") != -1 else &"Master"
	p.volume_db = volume_db
	p.pitch_scale = pitch_scale
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()

func play_spatial_sfx(stream: AudioStream, global_pos: Vector3, volume_db: float = 0.0, pitch_scale: float = 1.0, max_dist: float = 45.0) -> void:
	if stream == null or not is_inside_tree():
		return
	var player3d = AudioStreamPlayer3D.new()
	player3d.stream = stream
	player3d.bus = &"SFX" if AudioServer.get_bus_index(&"SFX") != -1 else &"Master"
	player3d.volume_db = volume_db
	player3d.pitch_scale = pitch_scale
	player3d.max_distance = max_dist
	player3d.unit_size = 4.0
	add_child(player3d)
	player3d.global_position = global_pos
	player3d.finished.connect(player3d.queue_free)
	player3d.play()
