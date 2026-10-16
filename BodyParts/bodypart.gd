class_name BodyPart
extends RigidBody3D

## Base class for all collectible Body Parts.
## Inherits from Area3D to provide trigger-based detection when a player enters its collision zone.

# ===== SIGNALS =====
## Emitted when this body part is successfully collected by a player
signal part_collected(collector: Node, owner_id: int, part_type: PartType)

# ===== ENUMS =====
enum PartType {
	HEAD,
	HANDS,
	TORSO,
	LEGS
}

# ===== EXPORTED VARIABLES =====
@export_group("Body Part Properties")
## The specific type of body part (HEAD, HANDS, TORSO, LEGS)
@export var part_type: PartType = PartType.HEAD

## The network peer ID or player index of the player who originally owns this body part
@export var owner_id: int = -1

@export_group("References")
## Optional direct reference to the GameManager node. If null, will attempt to find a node named "GameManager" or in group "GameManager".
@export var game_manager: Node = null

## Reference to a TarotCard (Resource or Object) associated with this BodyPart.
## This object is not rendered, but used to apply corresponding buffs/effects on collection.
@export var associated_tarot_card: Resource = null

# ===== STATE VARIABLES =====
## Safety flag to prevent duplicate collections across frames/ticks
var is_collected: bool = false

## True while a player is carrying this part. Blocks Area3D detection so the
## carrier can never trigger it, and is cleared when the part is deposited.
var is_carried: bool = false


## Collection now happens at the Spell Center. Set true to restore the legacy
## collect-on-walk-into behaviour.
@export var auto_collect_on_touch: bool = false

@export var part_color : Color = Color.WHITE:
	set(value):
		part_color = value
		_apply_color()

# ===== COLLISION CONFIGURATION =====
# Recommended Layer Setup:
# Collision Layer 4: Interactables / BodyParts
# Collision Mask: Layer 1 (Floor) + Layer 2 (Player)
const DEFAULT_COLLISION_LAYER: int = 8  # 1 << 3 (Layer 4)
const DEFAULT_COLLISION_MASK: int = 3   # 1 | 2 (Layer 1 Floor + Layer 2 Player)


@export_group("Visual Model")
@export var character_folder: String = "Player1"



func _load_part_visual() -> void:
	var part_name: String
	var model_scale: Vector3
	var model_position: Vector3
	var collision_radius: float

	match part_type:
		PartType.HEAD:
			part_name = "head"
			model_scale = Vector3(1.6, 1.6, 1.6)
			model_position = Vector3(-0.03, -2.788, 0.085)
			collision_radius = 0.4

		PartType.HANDS:
			part_name = "hands"
			model_scale = Vector3(0.6,0.6,0.6)
			model_position = Vector3(0.0, -0.83,0.1)
			collision_radius = 0.5

		PartType.TORSO:
			part_name = "torso"
			model_scale = Vector3(0.6,0.6,0.6)
			model_position = Vector3(0,-0.944, 0.133)
			collision_radius = 0.5

		PartType.LEGS:
			part_name = "legs"
			model_scale = Vector3(0.5,0.5,0.5)
			model_position = Vector3(-0.035, -0.494, 0.12)
			collision_radius = 0.5

		_:
			push_error("Invalid body part type: " + str(part_type))
			return

	var model_path := "res://Models/characters/SplitParts/%s/%s_fixed.tscn" % [
		character_folder,
		part_name
	]

	var packed_model := load(model_path) as PackedScene
	if packed_model == null:
		push_error("Could not load body-part model: " + model_path)
		return

	# Remove existing visual children while preserving physics
	# and multiplayer nodes.
	for child in get_children():
		if child is CollisionShape3D \
		or child is MultiplayerSynchronizer:
			continue

		remove_child(child)
		child.free()

	# Instance the selected model.
	var model := packed_model.instantiate()
	model.name = "PartVisualModel"
	model.position = model_position
	model.scale = model_scale
	add_child(model)

	# Disable imported static colliders inside the visual model.
	for node in model.find_children("*", "StaticBody3D", true, false):
		node.collision_layer = 0
		node.collision_mask = 0

	# Configure the collision shape.
	var collision := get_node_or_null("CollisionShape3D") as CollisionShape3D
	print("BodyPart position: ", global_position)
	print("Collider position: ", collision.global_position)
	print("Collider radius: ", collision.shape.radius)

	if collision != null:
		if collision.shape is SphereShape3D:
			# Duplicate the resource so other body parts
			# don't accidentally share a modified shape.
			var sphere := collision.shape.duplicate() as SphereShape3D
			sphere.radius = collision_radius
			sphere.margin = 0.04
			collision.shape = sphere
		else:
			push_warning(
				"CollisionShape3D must use SphereShape3D "
				+ "for radius settings."
			)
	else:
		push_warning("CollisionShape3D was not found.")


func _ready() -> void:
	# Prevent body parts from pushing the player back through
	# rigid-body collision response.
	lock_rotation = false
	_load_part_visual()
	# Configure default collision layer and mask if not overridden in inspector
	if collision_layer == 1 and collision_mask == 1:
		collision_layer = DEFAULT_COLLISION_LAYER
		collision_mask = DEFAULT_COLLISION_MASK
	
	set_carried(false)

	if auto_collect_on_touch:
		body_entered.connect(_on_body_entered)

## Toggles carried state. While carried, the RigidBody3D is frozen so it
## stays at the camera position without physics simulation.
func set_carried(carried: bool) -> void:
	is_carried = carried
	if carried:
		freeze = true
	else:
		freeze = false

func _on_body_entered(body: Node) -> void:
	# Ensure the colliding body is a player character and not the owner
	if is_collected or is_carried:
		return
	if not body is CharacterBody3D:
		return
	# The owning player cannot claim their own part via touch.
	# owner_id defaults to -1, which means "unowned", so only a real
	# matching id is treated as the owner. Godot 4's get() takes one argument
	# and returns null when the property is absent.
	if owner_id >= 0 and body.get("player_id") == owner_id:
		return
	
	collect(body)

## Main collection method. Called by the Spell Center after a successful
## deposit, or by _on_body_entered when auto_collect_on_touch is enabled.
func collect(collector: Node) -> void:
	if is_collected or is_carried:
		return
	is_collected = true
	print("Body part collected! Type: ", part_type, " Owner ID: ", owner_id, " Collector: ", collector.name)
	
	# Phase 3 & 4: Update counts, apply tarot card effects, and notify GameManager
	updateCount(collector)
	
	# Emit signal for external listeners (UI, Audio, visual effects)
	emit_signal("part_collected", collector, owner_id, part_type)
	
	# Remove node from scene
	queue_free()

## Phase 3 & 4: Updates collection counts on player & GameManager, and triggers TarotCard effects
func updateCount(collector: Node) -> void:
	# 1. Locate GameManager if not explicitly set
	var gm := game_manager
	if gm == null:
		if get_tree().has_group("GameManager"):
			gm = get_tree().get_first_node_in_group("GameManager")
		elif get_tree().root.has_node("GameManager"):
			gm = get_tree().root.get_node("GameManager")
	
	# 2. Communicate with GameManager if present
	if gm != null:
		if gm.has_method("on_body_part_collected"):
			gm.call("on_body_part_collected", collector, owner_id, part_type, associated_tarot_card)
		elif gm.has_method("update_count"):
			gm.call("update_count", collector, owner_id, part_type)
	
	# 3. Update collector player stats if player exposes helper methods
	if collector.has_method("on_body_part_collected"):
		collector.call("on_body_part_collected", owner_id, part_type)
	elif collector.has_method("update_collected_count"):
		collector.call("update_collected_count", part_type)
		
	# 4. Apply TarotCard effect directly if present and GameManager hasn't already handled it
	if associated_tarot_card != null:
		if associated_tarot_card.has_method("apply_effect"):
			associated_tarot_card.call("apply_effect", collector)
		elif associated_tarot_card.has_method("apply"):
			associated_tarot_card.call("apply", collector)

#Handle Body Part Colors
func _apply_color() -> void:
	var mesh := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if mesh == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = part_color
	mesh.material_override = mat
