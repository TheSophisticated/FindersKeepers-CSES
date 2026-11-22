# PlayerController.gd
# This script handles both local and remote player movement, including physics, camera, and networking

extends CharacterBody3D

# ===== EXPORTED SETTINGS =====
@export_category("Movement Settings")
@export var walk_speed := 10.0          # Normal movement speed
@export var sprint_speed := 15.0        # Sprinting speed
@export var jump_velocity := 15.0      # Jump force
@export var ground_acceleration := 22.0 # Acceleration on ground
@export var ground_deceleration := 30.0 # Deceleration on ground
@export var ground_turn_acceleration := 40.0 # Used when steering against current velocity, so direction changes don't slide
@export var air_control := 0.3         # Air movement control factor
@export var sprint_grace_time := 0.25  # Sprint still counts this long after release (A -> B thumb travel)
@export var slide_boost: float = 1.0   # Slide speed boost multiplier (boosted by Torso part)
@export var push_force: float = 14.0   # Player shove knockback strength (boosted by Hands part)
@export var reach_distance: float = 3.0 # Max player shove distance (boosted by Hands part)
@export var push_cooldown: float = 1.5  # Cooldown in seconds between shoves
@export var character_turn_speed := 12.0 # How quickly the visible character faces movement
@export var character_facing_yaw: float = PI # Replicated visual facing, relative to the player root

@export_category("Camera Settings")
@export var mouse_sensitivity := 0.01 # Mouse sensitivity
@export var controller_sensitivity := 3.0 # Controller stick look sensitivity (rad/s)
@export var camera_tilt_amount := 8.0  # Amount of camera tilt when strafing
@export var fov_normal := 80.0         # Normal field of view
@export var fov_sprint := 120.0        # Sprinting field of view
@export var sway_smoothness := 10.0    # Camera sway smoothing

@export_category("Network Settings")
@export var network_update_rate := 20.0 # Network updates per second
@export var interpolation_time := 0.12  # Network interpolation smoothing time

@export_category("Tarot Settings")
@export var tarot_capacity: int = 2     # Max tarot cards this player can carry

# ===== CONSTANTS =====
const GRAVITY_FORCE = 35.0            # Gravity strength
const POSITION_LERP_FACTOR = 0.3      # Position interpolation factor
const ROTATION_LERP_FACTOR = 0.5      # Rotation interpolation factor
const OCEAN_SURFACE_Y := 5.0          # World Y of the BoujieOcean plane
const WATER_FEET_OFFSET := 2.1        # Distance from Player origin to bottom of feet
const WATER_FLOAT_CENTER_Y := 4.85    # Buoyancy equilibrium Y so camera stays above water surface
const HELD_PART_BASE_POS := Vector3(0.0, 0.0, -2.0) # Base hold offset in front of camera

# ===== NODE REFERENCES =====
@onready var camera := $Camera3D # Player camera
var pitch = 0.0
@onready var head_position := $Camera3D/HeadPosition  # Hold point for picked-up objects
@onready var sync := $MultiplayerSynchronizer # Network sync component
@onready var effect_controller: TarotEffectController = $TarotEffectController #Effect controller component
@onready var interact_prompt: Label = $InteractPrompt/PromptLabel  # Interaction prompt label
@onready var animation_controller: Node = $AnimationController # Animation controller for character animations
@onready var flashlight : SpotLight3D = $Camera3D/Flashlight
@onready var timer : Timer = $Camera3D/Flashlight/Timer
@onready var tarot_tooltip = $TarotCardTooltip/CanvasLayer
@onready var tarot_notification = $EffectNotification/CanvasLayer

# ===== MOVEMENT STATE =====
enum MovementState { WALKING, SPRINTING, AIRBORNE }
var current_state = MovementState.WALKING
var is_moving := false                # Whether player is moving
var wish_dir := Vector3.ZERO          # Desired movement direction
var current_speed := 0.0              # Current movement speed
var was_on_floor := true              # Previous frame ground state
var speed_modifier: float = 1.0 # Used while using demon speed
var input_multiplier: float  = 1.0 # Used for inverting the controls while using hanged man
var knockback_velocity: Vector3 = Vector3.ZERO
var knockback_time_remaining: float = 0.0
var _push_cooldown_timer: float = 0.0
var _server_last_push_time: float = -10.0
var sprint_grace_timer := 0.0          # Time left in which a released sprint still counts
var air_speed := 0.0                   # Horizontal speed carried from takeoff
var is_sliding: bool = false           # Whether player is currently sliding
var slide_timer: float = 0.0           # Slide duration timer

# ===== JUMP VARIABLES =====
var jump_buffer_timer := 0.0          # Jump input buffer timer
var coyote_timer := 0.0               # Coyote time timer
var can_jump := true                  # Can player jump
var jump_count := 0                   # Current jump count
var jump_animation_name: StringName = &"jump_in_place"

# ===== CAMERA EFFECTS =====
var camera_tilt := 0.0                # Current camera tilt amount
var _base_camera_pos := Vector3.ZERO  # Cached standing camera local position
var _bob_phase := 0.0                 # Headbob sine phase
var _bob_offset := Vector2.ZERO       # Current smoothed headbob offset (x, y)
var _crouch_cam_offset := 0.0         # Vertical eye-height offset during crouch/slide
var _peak_fall_speed := 0.0           # Peak downward speed tracked while airborne
var _landing_dip := 0.0               # Tactile downward camera offset on touchdown
var _camera_shake_trauma := 0.0       # Decaying trauma [0..1] for knockback camera shake
var _carry_sway_time := 0.0           # Phase timer for carried body-part sway
var _base_flashlight_rot := Vector3.ZERO # Cached base rotation of player flashlight
var _flashlight_sway := Vector2.ZERO  # Handheld rotational lag offset (yaw, pitch)
var raw_input_dir := Vector2.ZERO     # Raw input direction
var vision_modifier: float  = 1.0
var render_distance_modifier: float = 1.0
@export var normal_render_distance: float  = 5000.0
var dark_moon_environment: Environment

# ===== NETWORK INTERPOLATION =====
var network_position_buffer = []      # Buffer for network positions
var network_rotation_buffer = []      # Buffer for network rotations
var network_timestamp_buffer = []     # Buffer for network timestamps
var last_network_update_time := 0.0   # Last network update time
var input_enabled: bool = true        # Whether input is enabled

## Body parts use this to identify their owner. Matches the network peer ID
## for the local player, and -1 for any player that has no authority.
var player_id: int = -1
@export var character_id: StringName = &"player_1":
	set(value):
		character_id = value
		if is_node_ready() and animation_controller != null:
			animation_controller.set_character_by_id(value)

# ===== LOOK-AT DETECTION =====
var look_at_ray: RayCast3D            # Raycast for detecting objects in front of player
var pickup_assist_cast: ShapeCast3D   # Wider sweep so near misses still pick up
## How far (in meters) the aim can miss a pickup and still grab it. Raise for easier pickups.
const PICKUP_ASSIST_RADIUS := 0.5
var held_object: Node3D = null        # Currently held interactable object
var held_body_part: BodyPart = null   # Body part being carried, deposited at the spell center
var hovered_body_part: BodyPart = null # Body part which is being hovered
var _reticle_dot: ColorRect = null    # Central retro crosshair dot

func show_tarot_notification(message: String) -> void:
	print("Notification requested: ", message)
	if not is_multiplayer_authority():
		return
	tarot_notification.show_notification(message)


func _process(delta):
	# Update controller camera look (local player only)
	if is_multiplayer_authority() and input_enabled:
		process_controller_look(delta)

	# Hover identification is local to this player
	if not is_multiplayer_authority():
		return

	if _push_cooldown_timer > 0.0:
		_push_cooldown_timer = maxf(_push_cooldown_timer - delta, 0.0)

	var current_hovered_part: BodyPart = null
	var ray_hit = look_at_ray.get_collider() if look_at_ray and look_at_ray.is_colliding() else null
	var pickup_target = _get_pickup_target()
	var is_hovering_actionable := false

	if not held_object and not held_body_part and (ray_hit != null or pickup_target != null):
		# Show Tarot tooltip for a directly targeted or assisted Tarot pickup.
		var tarot_target: TarotPickup = null

		if ray_hit is TarotPickup:
			tarot_target = ray_hit
		elif pickup_target is TarotPickup:
			tarot_target = pickup_target

		if tarot_target != null and tarot_target.card != null:
			tarot_tooltip.show_tooltip(
				tarot_target.card.card_name,
				tarot_target.card.description
			)
		else:
			tarot_tooltip.hide_tooltip()

		# Track hovered body parts.
		if pickup_target is BodyPart:
			current_hovered_part = pickup_target as BodyPart
		elif ray_hit is BodyPart:
			current_hovered_part = ray_hit as BodyPart

		# Preserve existing interaction prompts with contextual labels.
		if interact_prompt:
			if ray_hit is CharacterBody3D and ray_hit.is_in_group("player"):
				var is_in_range := global_position.distance_to(ray_hit.global_position) <= reach_distance
				if is_in_range:
					if _push_cooldown_timer > 0.0:
						interact_prompt.text = "[Q] / [B] — Push (%.1fs)" % _push_cooldown_timer
						is_hovering_actionable = false
					else:
						interact_prompt.text = "[Q] / [B] — Push Player"
						is_hovering_actionable = true
					interact_prompt.visible = true
				else:
					interact_prompt.text = ""
					interact_prompt.visible = false
					is_hovering_actionable = false
			elif current_hovered_part != null:
				var part_names := ["Head", "Hands", "Torso", "Legs"]
				var p_idx := clampi(int(current_hovered_part.part_type), 0, 3)
				if current_hovered_part.owner_id == player_id:
					interact_prompt.text = "Your Own %s — Defend It!" % part_names[p_idx]
					interact_prompt.visible = true
					is_hovering_actionable = false
				else:
					interact_prompt.text = "[E] / [X] — Steal %s" % _format_body_part_label(current_hovered_part)
					interact_prompt.visible = true
					is_hovering_actionable = true
			elif tarot_target != null and tarot_target.card != null:
				if _has_empty_tarot_slot():
					interact_prompt.text = "[E] / [X] — Take %s" % tarot_target.card.card_name
					interact_prompt.visible = true
					is_hovering_actionable = true
				else:
					interact_prompt.text = "Tarot Slots Full (Use [1] or [2] first)"
					interact_prompt.visible = true
					is_hovering_actionable = false
			else:
				interact_prompt.text = "[E] / [X] — Interact"
				interact_prompt.visible = pickup_target != null
				is_hovering_actionable = (pickup_target != null)
	else:
		if interact_prompt:
			if held_body_part != null:
				interact_prompt.text = "Carrying %s — Deliver to Church Altar | [E] Drop" % _format_body_part_label(held_body_part)
				interact_prompt.visible = true
			else:
				interact_prompt.visible = false
		tarot_tooltip.hide_tooltip()

	if _reticle_dot:
		_reticle_dot.color = Color(1.0, 0.3, 0.25, 0.95) if is_hovering_actionable else Color(1.0, 0.96, 0.85, 0.55)
		_reticle_dot.scale = Vector2(1.5, 1.5) if is_hovering_actionable else Vector2.ONE

	# Hide the previously hovered body part.
	if hovered_body_part != current_hovered_part:
		if is_instance_valid(hovered_body_part):
			hovered_body_part.set_owner_label_visible(false)

		hovered_body_part = current_hovered_part

	# Show the label on the newly hovered body part.
	if is_instance_valid(hovered_body_part):
		hovered_body_part.set_owner_label_visible(true)

func process_controller_look(delta: float) -> void:
	var look_dir = Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look_dir.length_squared() > 0.001:
		rotate_y(-look_dir.x * controller_sensitivity * delta)
		if camera:
			pitch = clamp(pitch - look_dir.y * controller_sensitivity * delta, deg_to_rad(-89), deg_to_rad(89))
			camera.rotation.x = pitch
		_flashlight_sway.x = clampf(_flashlight_sway.x + look_dir.x * controller_sensitivity * delta * 0.45, -0.075, 0.075)
		_flashlight_sway.y = clampf(_flashlight_sway.y + look_dir.y * controller_sensitivity * delta * 0.45, -0.075, 0.075)

func _enter_tree():
	# Set multiplayer authority based on name
	if name.contains("_"):
		var peer_id = name.get_slice("_", 1).to_int()
		set_multiplayer_authority(peer_id)
		player_id = peer_id
		if sync:
			sync.set_multiplayer_authority(peer_id)
			sync.replication_interval = 1.0 / network_update_rate



func _ready():
	add_to_group("player")
	print("Player Spawns at: ", global_position)
	dark_moon_environment = Environment.new()
	dark_moon_environment.background_mode = Environment.BG_COLOR
	dark_moon_environment.background_color = Color.BLACK
	# Setup for local player
	if is_multiplayer_authority():
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		if camera:
			_base_camera_pos = camera.position
			camera.far = normal_render_distance
			camera.current = true
		if flashlight:
			_base_flashlight_rot = flashlight.rotation
		if interact_prompt:
			interact_prompt.text = "[E] / [X] — Interact"
			_setup_reticle()
		var settings_node = get_node_or_null("/root/Settings")
		if settings_node and "settings" in settings_node:
			mouse_sensitivity = settings_node.settings.get("mouse_sensitivity", 0.002)
			controller_sensitivity = settings_node.settings.get("controller_sensitivity", 3.0)
	elif camera:
		# Godot makes the first Camera3D that enters a viewport current, so a
		# remote player spawned before ours would otherwise hijack our view.
		camera.current = false
		if has_node("InteractPrompt"):
			$InteractPrompt.visible = false
	current_speed = walk_speed
	tarot_cards.resize(tarot_capacity)
	if is_multiplayer_authority():
		var starting_card: TarotCard = load("res://Tarot/Cards/Definitions/DemonSpeed.tres")
		if starting_card != null:
			add_tarot_card(starting_card)
	# Set up look-at raycast as child of camera
	look_at_ray = RayCast3D.new()
	look_at_ray.name = "LookAtDetector"
	look_at_ray.enabled = true
	look_at_ray.collide_with_areas = true
	look_at_ray.collision_mask = 1 | 8  # Layer 1 (interactables) + Layer 4 (BodyParts)
	look_at_ray.target_position = Vector3(0, 0, -10)  # 10 units forward
	look_at_ray.add_exception(self)
	if camera:
		camera.add_child(look_at_ray)

	# Sphere sweep along the same line so pickups don't need pixel-perfect aim
	pickup_assist_cast = ShapeCast3D.new()
	pickup_assist_cast.name = "PickupAssistCast"
	pickup_assist_cast.enabled = true
	pickup_assist_cast.collide_with_areas = true
	pickup_assist_cast.collision_mask = look_at_ray.collision_mask
	var assist_shape := SphereShape3D.new()
	assist_shape.radius = PICKUP_ASSIST_RADIUS
	pickup_assist_cast.shape = assist_shape
	pickup_assist_cast.target_position = look_at_ray.target_position
	pickup_assist_cast.max_results = 16
	pickup_assist_cast.add_exception(self)
	if camera:
		camera.add_child(pickup_assist_cast)

	GameManager.player_eliminated.connect(_on_player_eliminated)

	# Initialize animations
	if animation_controller and animation_controller.has_method("setup"):
		animation_controller.default_character_id = character_id
		animation_controller.setup(self)

func _setup_reticle() -> void:
	if not has_node("InteractPrompt"):
		return
	var prompt_layer: CanvasLayer = $InteractPrompt
	_reticle_dot = ColorRect.new()
	_reticle_dot.name = "ReticleDot"
	_reticle_dot.custom_minimum_size = Vector2(4, 4)
	_reticle_dot.size = Vector2(4, 4)
	_reticle_dot.pivot_offset = Vector2(2, 2)
	_reticle_dot.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_reticle_dot.offset_left = -2
	_reticle_dot.offset_top = -2
	_reticle_dot.offset_right = 2
	_reticle_dot.offset_bottom = 2
	_reticle_dot.color = Color(1.0, 0.96, 0.85, 0.55)
	_reticle_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt_layer.add_child(_reticle_dot)

# ===== INPUT HANDLING =====
func _input(event):
	if not input_enabled or not is_multiplayer_authority():
		return

	# Mouse look
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * mouse_sensitivity)
		if camera:
			pitch = clamp(pitch - event.relative.y * mouse_sensitivity, deg_to_rad(-89), deg_to_rad(89))
			camera.rotation.x = pitch
		_flashlight_sway.x = clampf(_flashlight_sway.x + event.relative.x * mouse_sensitivity * 0.45, -0.075, 0.075)
		_flashlight_sway.y = clampf(_flashlight_sway.y + event.relative.y * mouse_sensitivity * 0.45, -0.075, 0.075)

	# Jump input buffering
	if event.is_action_pressed("jump"):
		jump_buffer_timer = 0.15

	# Push player input
	if event.is_action_pressed("push_player"):
		if _push_cooldown_timer > 0.0:
			return
		var target := _get_push_target()
		if target:
			_push_cooldown_timer = push_cooldown
			request_push_player.rpc_id(1, target.get_path())
			print("[Push] Target: ", target.name)
		else:
			print("[Push] No valid player target")

	# Interact input
	if event.is_action_pressed("interact"):
		print("[Player] Interact triggered. held_object: ", held_object != null, ", held_body_part: ", held_body_part != null)
		if held_object:
			drop_object.rpc() ##TODO: Add Validation Checks here
		elif held_body_part:
			drop_body_part.rpc()
		else:
			var hit_node = _get_pickup_target()
			if hit_node == null:
				print("[Player] No pickup target in range")
				return
			print("[Player] Pickup target: ", hit_node.name, " (", hit_node.get_class(), ")")
			if hit_node is TarotPickup:
				hit_node.collect.rpc(self.get_path())
			elif hit_node is BodyPart:
				pick_up_body_part.rpc(hit_node.get_path())
			elif hit_node.is_in_group("interactable"):
				request_pick_up.rpc_id(1, hit_node.get_path())

	# Tarot slots
	if event.is_action_pressed("tarot_slot_1"):
		trigger_tarot_slot(0)
	elif event.is_action_pressed("tarot_slot_2"):
		trigger_tarot_slot(1)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_3 and tarot_capacity >= 3:
			trigger_tarot_slot(2)
		elif event.physical_keycode == KEY_4 and tarot_capacity >= 4:
			trigger_tarot_slot(3)
		
	if event.is_action_pressed("flashlight"):
		set_flashlight.rpc(not flashlight.visible)

func trigger_tarot_slot(slot_index: int) -> void:
	if not input_enabled or not is_multiplayer_authority():
		return
	if slot_index < 0 or slot_index >= tarot_cards.size():
		return
	if tarot_cards[slot_index] == null:
		show_tarot_notification("Tarot Slot %d is empty" % (slot_index + 1))
		return
	use_tarot_card.rpc(slot_index)
# ===== Flashlight =====
@rpc("authority", "reliable", "call_local")
func set_flashlight(on : bool):
	print("Flashlight was Turned ", on)
	flashlight.visible = on


# ===== TAROT INVENTORY =====
signal tarot_card_added(card: TarotCard, slot: int)  # Emitted when a card fills a slot
signal tarot_card_removed(slot: int)
signal tarot_capacity_changed(new_capacity: int)

var tarot_cards: Array[TarotCard] = []  # Fixed-size slots, empty slots hold null

func _has_empty_tarot_slot() -> bool:
	for card in tarot_cards:
		if card == null:
			return true
	return false

# Stores a card in the first empty slot. Returns true if it fit.

@rpc("any_peer", "call_local", "reliable")
func add_tarot_card(card: TarotCard) -> bool:
	if card == null:
		push_warning("Cannot add a null Tarot card.")
		return false

	for i in range(tarot_cards.size()):
		if tarot_cards[i] == null:
			tarot_cards[i] = card
			print("Picked up Tarot Card: ", card.card_name, " | Slot: ", i)
			tarot_card_added.emit(card, i)
			return true

	print("Tarot inventory full.")
	show_tarot_notification("Tarot inventory full!")
	return false

# Server-granted card (e.g. Blood Shrine reward). Uses the first empty slot,
# or overwrites slot 1 when the inventory is full.
@rpc("any_peer", "call_local", "reliable")
func grant_tarot_card(card_path: String) -> void:
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id != 1 and not (sender_id == 0 and multiplayer.is_server()):
		return

	var card := load(card_path) as TarotCard
	if card == null:
		push_warning("Cannot grant Tarot card, failed to load: " + card_path)
		return

	if add_tarot_card(card):
		return

	tarot_cards[0] = card
	print("Granted Tarot Card: ", card.card_name, " | Replaced Slot: 0")
	tarot_card_added.emit(card, 0)

@rpc("any_peer", "call_local", "reliable")
func use_tarot_card(slot_index: int)->void:
	if slot_index < 0 or slot_index >= tarot_cards.size():
		push_warning("Invalid Tarot Card slot: "+str(slot_index))
		return

	var card: TarotCard = tarot_cards[slot_index]

	if card == null:
		push_warning("Tarot slot is empty: "+str(slot_index))
		return

	if card.effect == null:
		push_warning("Tarot card has no effect: "+card.card_name)
		return

	print("Using Tarot card ",card.card_name)

	var applied: bool = effect_controller.apply_effect(card.effect)

	if not applied:
		print("Could not apply Tarot Card: ",card.card_name)
		return

	tarot_cards[slot_index] = null
	tarot_card_removed.emit(slot_index)
	print("removed tarot cards : ",card.card_name," | Inventory: ",tarot_cards.size(),"/",tarot_capacity)

@rpc("any_peer", "call_remote", "reliable")
func teleport_to(new_position: Vector3) -> void:
	var sender_id := multiplayer.get_remote_sender_id()

	if multiplayer.is_server():
		if sender_id != 0:
			return
	else:
		if sender_id != 1:
			return

	global_position = new_position
	velocity = Vector3.ZERO
	print("Teleported ", name, " to ", new_position)

func _apply_tower_knockback_local(
	direction: Vector3,
	strength: float,
	duration: float
) -> void:
	if not is_multiplayer_authority():
		return

	knockback_velocity = direction.normalized() * strength
	knockback_time_remaining = duration
	_camera_shake_trauma = clampf(_camera_shake_trauma + 0.65, 0.0, 1.0)

	if held_body_part != null:
		drop_body_part.rpc()

	print("Tower knockback applied to ", name)


@rpc("any_peer", "call_remote", "reliable")
func apply_tower_knockback(
	direction: Vector3,
	strength: float,
	duration: float
) -> void:
	var sender_id := multiplayer.get_remote_sender_id()

	# Only the server (peer ID 1) can trigger knockback.
	if sender_id != 1:
		return

	_apply_tower_knockback_local(direction, strength, duration)

func _is_pickable(node) -> bool:
	return node is TarotPickup or node is BodyPart or (node is Node and node.is_in_group("interactable"))

## Returns the pickup the player is aiming at. An exact ray hit wins; otherwise
## the closest pickup to the aim line inside the assist sphere sweep is used.
func _get_pickup_target() -> Node3D:
	if not look_at_ray:
		return null

	var ray_hit = look_at_ray.get_collider() if look_at_ray.is_colliding() else null
	if _is_pickable(ray_hit):
		return ray_hit as Node3D

	if not pickup_assist_cast or not pickup_assist_cast.is_colliding():
		return null

	var origin := look_at_ray.global_position
	var forward := -look_at_ray.global_transform.basis.z
	# Don't grab things hidden behind whatever the ray is blocked by
	var max_distance := INF
	if ray_hit != null:
		max_distance = origin.distance_to(look_at_ray.get_collision_point()) + PICKUP_ASSIST_RADIUS

	var best: Node3D = null
	var best_offset := INF
	for i in pickup_assist_cast.get_collision_count():
		var node := pickup_assist_cast.get_collider(i) as Node3D
		if node == null or not _is_pickable(node):
			continue
		var to_node := node.global_position - origin
		var along := to_node.dot(forward)
		if along < 0.0 or along > max_distance:
			continue
		var offset := (to_node - forward * along).length()
		if offset < best_offset:
			best_offset = offset
			best = node
	return best

func _get_push_target() -> CharacterBody3D:
	if not look_at_ray or not look_at_ray.is_colliding():
		return null

	var hit_node := look_at_ray.get_collider()

	# Only push a player directly hit by the look-at ray.
	if not hit_node is CharacterBody3D:
		return null

	if not hit_node.is_in_group("player"):
		return null

	# The target must be within reach_distance units.
	if global_position.distance_to(hit_node.global_position) > reach_distance:
		return null

	return hit_node

func apply_hands_buff(push_force_multiplier: float, reach_distance_boost: float) -> void:
	push_force *= push_force_multiplier
	reach_distance += reach_distance_boost
	if look_at_ray:
		look_at_ray.target_position.z = minf(look_at_ray.target_position.z, -reach_distance)
	if pickup_assist_cast and look_at_ray:
		pickup_assist_cast.target_position = look_at_ray.target_position
	print("Applied Hands Buff: push_force=", push_force, " reach_distance=", reach_distance)

func apply_torso_buff(extra_tarot_slots: int, slide_boost_multiplier: float) -> void:
	slide_boost *= slide_boost_multiplier
	if extra_tarot_slots > 0:
		tarot_capacity += extra_tarot_slots
		tarot_cards.resize(tarot_capacity)
		tarot_capacity_changed.emit(tarot_capacity)
	print("Applied Torso Buff: tarot_capacity=", tarot_capacity, " slide_boost=", slide_boost)

func apply_speed_modifier(multiplier: float)->void:
	speed_modifier *= multiplier

	print("Speed modifier applied: ",multiplier," | current modifier  : ",speed_modifier)

func remove_speed_modifier(multiplier: float)->void:
	if multiplier == 0.0:
		return
	speed_modifier /= multiplier

	print("speed modifier removed : ",multiplier , " | current modifier : ",speed_modifier)


func apply_vision_modifier(multiplier: float)->void:
	vision_modifier *= multiplier
	camera.environment = dark_moon_environment
	print("vison modifier applied : ",multiplier, " | current modifier ",vision_modifier)

func remove_vision_modifier(multiplier: float)->void:
	if multiplier == 0.0:
		return
	vision_modifier /= multiplier
	print("vison modifier removed : ",multiplier, " | current modifier ",vision_modifier)
	if is_equal_approx(vision_modifier,1.0):
		print("Restoring camera environment: null ")
		camera.environment = null

func apply_render_distance_modifier(multiplier: float)->void:
	render_distance_modifier *= multiplier
	camera.far = normal_render_distance*render_distance_modifier

	print("Render distance modifier applied : ",multiplier," | Far : ",camera.far)

func remove_render_distance_modifier(multiplier: float)->void:
	if multiplier == 0.0:
		return
	render_distance_modifier /= multiplier
	if is_equal_approx(render_distance_modifier, 1.0):
		render_distance_modifier = 1.0
	if camera:
		camera.far = normal_render_distance * render_distance_modifier

	print("render distance modifier removed : ", multiplier, " | Far : ", camera.far if camera else 0.0)

func apply_input_modifier(multiplier:float)->void:
	input_multiplier  *= multiplier
	print("Input modifier applied ",multiplier," | current modifier : ",input_multiplier)

func remove_input_modifier(multiplier: float)->void:
	if multiplier == 0.0:
		return
	input_multiplier /= multiplier
	print("Input modifier removed ",multiplier," | current modifier : ",input_multiplier)

@rpc("any_peer", "call_local", "reliable")
func request_push_player(target_path: NodePath) -> void:
	if not multiplayer.is_server():
		return

	var sender_id := multiplayer.get_remote_sender_id()

	# Resolve the host's local request.
	if sender_id == 0:
		sender_id = 1

	# The request must come from this player.
	if sender_id != player_id:
		return

	if target_path.is_empty():
		return

	var target := get_node_or_null(target_path)

	if target == null or not is_instance_valid(target):
		return

	if target == self:
		return

	if not target is CharacterBody3D:
		return

	if not target.is_in_group("player"):
		return

	# Validate the distance on the server.
	if global_position.distance_to(target.global_position) > reach_distance:
		return

	# Enforce server-side shove cooldown to prevent spam.
	var now_sec := Time.get_ticks_msec() / 1000.0
	if now_sec - _server_last_push_time < (push_cooldown - 0.1):
		return
	_server_last_push_time = now_sec

	# Push away from the requesting player.
	var direction :Vector3 = target.global_position - global_position
	direction.y = 0.0

	if direction.length_squared() < 0.001:
		direction = -global_transform.basis.z

	direction = direction.normalized()

	var target_peer_id := target.get_multiplayer_authority()

	if target_peer_id == 1:
		target._apply_tower_knockback_local(direction, push_force, 0.45)
	else:
		target.rpc_id(
			target_peer_id,
			"apply_tower_knockback",
			direction,
			push_force,
			0.45
		)

	print("[Push] ", name, " pushed ", target.name)

# ===== PICKUP / DROP =====
@rpc("any_peer", "call_local", "reliable")
func request_pick_up(target: NodePath) -> void:
	if not multiplayer.is_server():
		return

	if target.is_empty():
		print("Empty Node Path!")
		return

	var id = multiplayer.get_remote_sender_id();
	##Adjust for Host Calling the Function
	if id == 0:
		id = 1;

	##Verify request from the Same Player
	if id != player_id:
		return

	##Check if Player is already holding an object
	if held_object != null:
		return

	##Check if that object exists or is not held by someone else
	if get_node_or_null(target) == null:
		return

	pick_up_object.rpc(target)

@rpc("any_peer", "call_local", "reliable")
func pick_up_object(targetPath: NodePath) -> void:
	if multiplayer.get_remote_sender_id() != 1 && multiplayer.get_remote_sender_id() != 0:
		return

	var target = get_node_or_null(targetPath)
	if target == null:
		print("NULL Target")
		return

	held_object = target
	if target is CSGBox3D:
		target.use_collision = false

	target.reparent(head_position, true)
	target.position = Vector3(0, 0, -2)
	print("Picked up: ", target.name)

@rpc("any_peer", "call_local", "reliable")
func drop_object() -> void:
	if not held_object:
		return
	if held_object is CSGBox3D:
		held_object.use_collision = true
	held_object.reparent(get_parent(), true)
	held_object = null
	print("Dropped object")

# ===== BODY PART CARRY =====
# Carries a body part to the spell center. No buffs, progress or removal
# happen here; that all waits for deposit_body_part().

func _format_body_part_label(part: BodyPart) -> String:
	var part_names := ["Head", "Hands", "Torso", "Legs"]
	var p_idx := clampi(int(part.part_type), 0, 3)
	var owner_name := GameManager.get_player_display_name(part.owner_id) if GameManager else "Player %d" % part.owner_id
	if owner_name == "Unknown":
		owner_name = "Player %d" % part.owner_id
	return "%s's %s" % [owner_name, part_names[p_idx]]

@rpc("any_peer", "call_local", "reliable")
func pick_up_body_part(partPath : NodePath) -> void:
	var part := get_node_or_null(partPath)
	if part == null:
		print("Part is NULL! FAILED")
		return

	if part.owner_id == player_id:
		print("You cant pick up your own parts!")
		show_tarot_notification("You can't pick up your own body part!")
		return

	if held_body_part != null or held_object != null:
		print("[Player] pick_up_body_part aborted: hands full")
		return
	if part.is_collected or part.is_carried:
		print("[Player] pick_up_body_part aborted: part already collected or carried")
		return

	held_body_part = part
	part.set_carried(true)
	part.reparent(head_position, true)
	part.position = HELD_PART_BASE_POS
	part.part_collected.connect(_on_part_collected)
	print("[Player] SUCCESS: Carrying body part: ", part.name)

# Called by the spell center. Hands the part to BodyPart.collect(), which is
# where progress, buffs and removal finally happen.

@rpc("any_peer", "call_local", "reliable")
func deposit_body_part() -> void:

	if held_body_part == null:
		print("[Player] deposit_body_part aborted: held_body_part is null")
		return

	print("[Player] Calling held_body_part.collect() for: ", held_body_part.name)
	held_body_part.set_carried(false)
	held_body_part.collect(self)
	held_body_part = null
	print("[Player] SUCCESS: Deposited body part")

# Returns a carried part to the world without collecting it.
@rpc("any_peer", "call_local", "reliable")
func drop_body_part() -> void:
	if not held_body_part:
		return

	held_body_part.set_carried(false)
	held_body_part.part_collected.disconnect(_on_part_collected)
	held_body_part.reparent(get_parent(), true)
	held_body_part = null
	print("Dropped body part")

# Clears the held reference if the part is collected by any other means.
func _on_part_collected(_collector: Node, _owner_id: int, _part_type: int) -> void:
	held_body_part = null

var _net_send_accumulator: float = 0.0

# ===== PHYSICS PROCESS =====
func _physics_process(delta):
	if not input_enabled:
		velocity = Vector3.ZERO
		return

	if is_multiplayer_authority():
		# Local player movement
		process_local_movement(delta)
		move_and_slide()
		update_character_facing(delta)
		_net_send_accumulator += delta
		var send_interval := 1.0 / maxf(network_update_rate, 5.0)
		if _net_send_accumulator >= send_interval:
			_net_send_accumulator = fmod(_net_send_accumulator, send_interval)
			send_network_update()
		update_camera_effects(delta)
	else:
		# Remote player movement interpolation
		process_remote_movement(delta)
		update_remote_character_facing(delta)

# ===== LOCAL MOVEMENT =====
func process_local_movement(delta):
	# Get input direction
	raw_input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")*input_multiplier
	is_moving = raw_input_dir.length() > 0.1
	wish_dir = (transform.basis * Vector3(raw_input_dir.x, 0, raw_input_dir.y)).normalized()

	# Handle jumping
	handle_jump_mechanics(delta)

	# Update movement state
	update_movement_state(delta)
	# Calculate movement
	handle_movement(delta)

	# Apply gravity
	apply_gravity(delta)

# ===== JUMP MECHANICS =====
func handle_jump_mechanics(delta):
	# Update timers
	jump_buffer_timer = max(jump_buffer_timer - delta, 0)
	# Holding jump keeps re-jumping on every landing
	if Input.is_action_pressed("jump"):
		jump_buffer_timer = max(jump_buffer_timer, 0.15)
	if Input.is_action_pressed("sprint"):
		sprint_grace_timer = sprint_grace_time
	else:
		sprint_grace_timer = max(sprint_grace_timer - delta, 0)

	# Coyote time - allows jumping shortly after leaving ground
	if is_on_floor():
		coyote_timer = 0.1
		if not was_on_floor:
			can_jump = true
			jump_count = 0
			air_speed = 0.0
			if _peak_fall_speed > 5.0:
				_landing_dip = -clampf(_peak_fall_speed * 0.014, 0.06, 0.28)
			_peak_fall_speed = 0.0
	else:
		coyote_timer = max(coyote_timer - delta, 0)
		if velocity.y < 0.0:
			_peak_fall_speed = maxf(_peak_fall_speed, -velocity.y)

	was_on_floor = is_on_floor()

	# Perform jump if conditions met
	if jump_buffer_timer > 0 and can_jump and (is_on_floor() or coyote_timer > 0):
		perform_jump()

func perform_jump():
	# Use the same in-place jump for standing, walking, and running jumps.
	jump_animation_name = &"jump_in_place"
	velocity.y = jump_velocity
	# Carry takeoff momentum into the air (also chains held-jump hops)
	air_speed = Vector2(velocity.x, velocity.z).length()
	jump_buffer_timer = 0
	can_jump = false
	coyote_timer = 0
	jump_count += 1

# ===== MOVEMENT STATES =====
func update_movement_state(delta: float = 0.0):
	if is_on_floor():
		var wants_sprint: bool = (Input.is_action_pressed("sprint") or sprint_grace_timer > 0) and is_moving and raw_input_dir.y < 0
		var wants_crouch: bool = Input.is_action_pressed("crouch")

		if wants_crouch:
			# If sprinting forward and pressing crouch -> SLIDE!
			if wants_sprint or is_sliding:
				if not is_sliding:
					is_sliding = true
					slide_timer = 0.65
				slide_timer = max(slide_timer - delta, 0.0)
				if slide_timer > 0.0:
					current_state = MovementState.SPRINTING
					var boost_factor = 1.35 * slide_boost * (0.6 + 0.4 * (slide_timer / 0.65))
					current_speed = sprint_speed * speed_modifier * boost_factor
				else:
					is_sliding = false
					current_state = MovementState.WALKING
					current_speed = walk_speed * 0.6 * speed_modifier
			else:
				is_sliding = false
				slide_timer = 0.0
				current_state = MovementState.WALKING
				current_speed = walk_speed * 0.6 * speed_modifier
		else:
			is_sliding = false
			slide_timer = 0.0
			if wants_sprint:
				current_state = MovementState.SPRINTING
				current_speed = sprint_speed * speed_modifier
			else:
				current_state = MovementState.WALKING
				current_speed = walk_speed * speed_modifier
	else:
		is_sliding = false
		current_state = MovementState.AIRBORNE

	_play_movement_animation()

func _play_movement_animation() -> void:
	if not animation_controller or not animation_controller.has_method("play_walk"):
		return
	var locomotion_animation: StringName = &""
	match current_state:
		MovementState.WALKING:
			if not is_moving:
				animation_controller.play_idle()
				return
			if Input.is_action_pressed("crouch"):
				locomotion_animation = &"crouch_walk"
			elif absf(raw_input_dir.x) > absf(raw_input_dir.y) + 0.1:
				locomotion_animation = &"strafe_left" if raw_input_dir.x < 0.0 else &"strafe_right"
			elif raw_input_dir.y > 0.1:
				locomotion_animation = &"walk_back"
			else:
				locomotion_animation = &"walk"
		MovementState.SPRINTING:
			if is_sliding or Input.is_action_pressed("crouch"):
				locomotion_animation = &"crouch_walk"
			else:
				locomotion_animation = &"run"
		MovementState.AIRBORNE:
			if velocity.y > 0:
				animation_controller.play_jump(jump_animation_name)
			elif animation_controller.has_method("is_jump_animation_playing") and animation_controller.is_jump_animation_playing():
				# Let the selected jump clip finish through the descending part.
				pass
			else:
				animation_controller.play_fall()
			return

	if animation_controller.has_method("play_state"):
		animation_controller.play_state(locomotion_animation)

# ===== MOVEMENT CALCULATION =====
func _get_water_submerge_depth() -> float:
	return maxf(0.0, (OCEAN_SURFACE_Y + 0.15) - (global_position.y - WATER_FEET_OFFSET))

func handle_movement(delta):
	var water_depth := _get_water_submerge_depth()
	var is_in_deep_water := global_position.y < (WATER_FLOAT_CENTER_Y + 0.35)
	var water_speed_scale := clampf(1.0 - (water_depth / 2.6) * 0.45, 0.55, 1.0)
	var effective_speed := current_speed * water_speed_scale

	if is_on_floor() or is_in_deep_water:
		# Ground or wading/treading water movement
		var current_vel = Vector2(velocity.x, velocity.z)
		var target_vel = Vector2(wish_dir.x, wish_dir.z) * effective_speed

		if wish_dir.length() > 0:
			# Snap harder when the new direction points away from where we're sliding
			var accel := ground_acceleration
			if current_vel.dot(target_vel) < 0.0:
				accel = ground_turn_acceleration
			if water_depth > 0.2:
				accel *= 0.75
			current_vel = current_vel.move_toward(target_vel, accel * delta)
		else:
			var decel := ground_deceleration * (0.8 if water_depth > 0.2 else 1.0)
			current_vel = current_vel.move_toward(Vector2.ZERO, decel * delta)

		velocity.x = current_vel.x
		velocity.z = current_vel.y
	else:
		# Air movement
		var current_vel = Vector2(velocity.x, velocity.z)
		var target_vel = Vector2(wish_dir.x, wish_dir.z) * max(effective_speed, air_speed * water_speed_scale)

		if wish_dir.length() > 0:
			current_vel = current_vel.move_toward(target_vel, ground_acceleration * air_control * delta)
			velocity.x = current_vel.x
			velocity.z = current_vel.y
	if knockback_time_remaining > 0.0:
		velocity.x = knockback_velocity.x
		velocity.z = knockback_velocity.z

		knockback_time_remaining -= delta
		knockback_velocity = knockback_velocity.move_toward(
			Vector3.ZERO, 20.0 * delta
		)
	else:
		knockback_velocity = Vector3.ZERO

func apply_gravity(delta):
	var water_depth := _get_water_submerge_depth()
	# Deep water buoyancy: float at chest/shoulder height so camera never clips underwater
	if global_position.y < WATER_FLOAT_CENTER_Y + 0.15:
		var bob_offset := sin(Time.get_ticks_msec() * 0.0028) * 0.07
		var target_y := WATER_FLOAT_CENTER_Y + bob_offset
		var depth_err := target_y - global_position.y
		var target_vy := clampf(depth_err * 6.5, -3.5, 5.5)
		if Input.is_action_pressed("jump") and global_position.y <= WATER_FLOAT_CENTER_Y + 0.2:
			target_vy = maxf(target_vy, 4.8)
		velocity.y = lerpf(velocity.y, target_vy, clampf(delta * 8.0, 0.0, 1.0))
		return

	if not is_on_floor():
		var grav_scale := 0.55 if water_depth > 0.5 else 1.0
		velocity.y -= GRAVITY_FORCE * grav_scale * delta

# ===== CAMERA EFFECTS =====
func update_camera_effects(delta):
	if not camera: return

	# Camera tilt when strafing or sliding
	var target_tilt = 0.0
	if is_sliding:
		target_tilt = -raw_input_dir.x * camera_tilt_amount + (3.5 if raw_input_dir.x >= 0.0 else -3.5)
	elif is_moving and is_on_floor():
		target_tilt = -raw_input_dir.x * camera_tilt_amount

	camera_tilt = lerp(camera_tilt, target_tilt, delta * sway_smoothness)
	var shake_roll := 0.0
	var shake_pitch := 0.0
	if _camera_shake_trauma > 0.001:
		_camera_shake_trauma = maxf(_camera_shake_trauma - delta * 1.9, 0.0)
		var shake := _camera_shake_trauma * _camera_shake_trauma
		shake_roll = deg_to_rad(randf_range(-4.5, 4.5) * shake)
		shake_pitch = deg_to_rad(randf_range(-3.0, 3.0) * shake)
	camera.rotation.x = clampf(pitch + shake_pitch, deg_to_rad(-89), deg_to_rad(89))
	camera.rotation.z = deg_to_rad(camera_tilt) + shake_roll

	# FOV changes when sprinting
	var target_fov := fov_normal
	if current_state == MovementState.SPRINTING and raw_input_dir.y < 0:
		target_fov = fov_sprint

	target_fov *= vision_modifier

	camera.fov = lerp(camera.fov,target_fov,delta*5.0)

	# Speed-scaled sinusoidal headbob while moving on ground
	var horiz_speed := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and horiz_speed > 0.5 and not is_sliding:
		var bob_freq := clampf(horiz_speed * 0.85, 4.5, 13.5)
		_bob_phase += delta * bob_freq
		var bob_amp := 0.045
		if current_state == MovementState.SPRINTING:
			bob_amp = 0.075
		elif Input.is_action_pressed("crouch"):
			bob_amp = 0.025
		var target_bob := Vector2(
			cos(_bob_phase * 0.5) * bob_amp * 0.55,
			sin(_bob_phase) * bob_amp
		)
		_bob_offset = _bob_offset.lerp(target_bob, clampf(delta * 10.0, 0.0, 1.0))
	else:
		_bob_offset = _bob_offset.lerp(Vector2.ZERO, clampf(delta * 8.0, 0.0, 1.0))

	# Smooth eye-height drop during crouch and slide
	var target_crouch_offset := 0.0
	if is_sliding:
		target_crouch_offset = -0.65
	elif is_on_floor() and Input.is_action_pressed("crouch"):
		target_crouch_offset = -0.45
	_crouch_cam_offset = lerpf(_crouch_cam_offset, target_crouch_offset, clampf(delta * 12.0, 0.0, 1.0))

	# Smoothly recover landing dip back to standing eye height
	_landing_dip = lerpf(_landing_dip, 0.0, clampf(delta * 11.0, 0.0, 1.0))

	camera.position = _base_camera_pos + Vector3(_bob_offset.x, _bob_offset.y + _crouch_cam_offset + _landing_dip, 0.0)

	# Subtle walk and breathing sway on carried body part
	if is_instance_valid(held_body_part) and held_body_part.get_parent() == head_position:
		var moving_on_ground := is_on_floor() and horiz_speed > 0.5
		_carry_sway_time += delta * (clampf(horiz_speed * 0.75, 4.5, 11.0) if moving_on_ground else 1.8)
		var sway_x := (0.06 if moving_on_ground else 0.012) * cos(_carry_sway_time * 0.5)
		var sway_y := (0.045 if moving_on_ground else 0.015) * sin(_carry_sway_time)
		var target_hold_pos := HELD_PART_BASE_POS + Vector3(sway_x, sway_y, 0.0)
		held_body_part.position = held_body_part.position.lerp(target_hold_pos, clampf(delta * 10.0, 0.0, 1.0))

	# Handheld rotational lag sway on player flashlight
	if flashlight:
		_flashlight_sway = _flashlight_sway.lerp(Vector2.ZERO, clampf(delta * 9.0, 0.0, 1.0))
		flashlight.rotation = _base_flashlight_rot + Vector3(_flashlight_sway.y, _flashlight_sway.x, 0.0)

# ===== NETWORK UPDATES =====
func send_network_update():
	# Send position/rotation update to other players
	rpc("_receive_network_update",
		global_position,
		velocity,
		rotation,
		Time.get_ticks_msec() / 1000.0)

@rpc("unreliable_ordered", "any_peer", "call_remote", 1)
func _receive_network_update(pos: Vector3, vel: Vector3, rot: Vector3, _sender_timestamp: float):
	if is_multiplayer_authority(): return

	var local_arrival_time := Time.get_ticks_msec() / 1000.0
	velocity = vel

	# Store update using local arrival time to avoid cross-machine uptime desync
	network_position_buffer.append(pos)
	network_rotation_buffer.append(rot)
	network_timestamp_buffer.append(local_arrival_time)

	# Maintain buffer size
	if network_position_buffer.size() > 8:
		network_position_buffer.pop_front()
		network_rotation_buffer.pop_front()
		network_timestamp_buffer.pop_front()

	last_network_update_time = local_arrival_time

# ===== REMOTE PLAYER INTERPOLATION =====
func process_remote_movement(delta):
	if network_position_buffer.is_empty():
		return
	if network_position_buffer.size() == 1:
		global_position = network_position_buffer[0]
		rotation = network_rotation_buffer[0]
		return

	var current_time = Time.get_ticks_msec() / 1000.0
	var render_time = current_time - interpolation_time

	# Find closest states for interpolation
	var prev_index = -1
	var next_index = -1

	for i in range(network_timestamp_buffer.size()):
		if network_timestamp_buffer[i] <= render_time:
			prev_index = i
		else:
			next_index = i
			break

	if next_index == -1:
		if network_timestamp_buffer.size() < 2: return
		prev_index = network_timestamp_buffer.size() - 2
		next_index = network_timestamp_buffer.size() - 1
	elif prev_index == -1:
		prev_index = 0
		next_index = 1

	# Calculate interpolation factor
	var prev_time = network_timestamp_buffer[prev_index]
	var next_time = network_timestamp_buffer[next_index]
	var time_diff = next_time - prev_time

	var t = 1.0 if time_diff < 0.001 else clamp((render_time - prev_time) / time_diff, 0.0, 1.0)

	# Interpolate position and yaw angle safely across -PI/PI wraparound
	var target_pos: Vector3 = network_position_buffer[prev_index].lerp(
		network_position_buffer[next_index], t)
	var prev_rot: Vector3 = network_rotation_buffer[prev_index]
	var next_rot: Vector3 = network_rotation_buffer[next_index]
	var target_rot := Vector3(
		lerp_angle(prev_rot.x, next_rot.x, t),
		lerp_angle(prev_rot.y, next_rot.y, t),
		lerp_angle(prev_rot.z, next_rot.z, t)
	)

	if not target_pos.is_finite() or not target_rot.is_finite():
		return

	# Apply with framerate-independent exponential smoothing
	var pos_weight := 1.0 - exp(-18.0 * delta)
	var rot_weight := 1.0 - exp(-22.0 * delta)
	global_position = global_position.lerp(target_pos, pos_weight)
	rotation.y = lerp_angle(rotation.y, target_rot.y, rot_weight)

func update_character_facing(delta: float) -> void:
	var model := animation_controller.character_node as Node3D if animation_controller else null
	if not is_instance_valid(model):
		return

	var travel_direction := Vector3(velocity.x, 0.0, velocity.z)
	if travel_direction.length_squared() < 0.004:
		return

	var local_direction := global_transform.basis.inverse() * travel_direction.normalized()
	var desired_facing_yaw: float
	if current_state == MovementState.WALKING \
		and not Input.is_action_pressed("crouch") \
		and absf(raw_input_dir.x) > absf(raw_input_dir.y) + 0.1:
		# Aim the selected strafe side (the arm at 3 or 9 o'clock) into travel.
		if raw_input_dir.x > 0.0:
			desired_facing_yaw = atan2(local_direction.z, -local_direction.x)
		else:
			desired_facing_yaw = atan2(-local_direction.z, local_direction.x)
	elif current_state == MovementState.WALKING \
		and not Input.is_action_pressed("crouch") \
		and raw_input_dir.y > 0.1:
		# Back-walk travels in the direction of the character's back (6 o'clock).
		desired_facing_yaw = atan2(-local_direction.x, -local_direction.z)
	else:
		# Forward walk, run, crouch-walk, and forward jump travel from the front.
		desired_facing_yaw = atan2(local_direction.x, local_direction.z)

	character_facing_yaw = desired_facing_yaw
	var turn_weight := 1.0 - exp(-character_turn_speed * delta)
	model.rotation.y = lerp_angle(model.rotation.y, character_facing_yaw, turn_weight)

func update_remote_character_facing(delta: float) -> void:
	var model := animation_controller.character_node as Node3D if animation_controller else null
	if not is_instance_valid(model):
		return
	var turn_weight := 1.0 - exp(-character_turn_speed * delta)
	model.rotation.y = lerp_angle(model.rotation.y, character_facing_yaw, turn_weight)

# ===== INPUT CONTROL =====
func set_input_enabled(enabled: bool):
	input_enabled = enabled
	if is_multiplayer_authority():
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if enabled else Input.MOUSE_MODE_VISIBLE)


# Hanlde Player Elimination
func _on_player_eliminated(peer_id : int, name : String) -> void:
	if peer_id != player_id:
		return
	set_input_enabled(false)
	if has_node("InteractPrompt"):
		$InteractPrompt.visible = false
	collision_layer = 0
	collision_mask = 0
	hide()
