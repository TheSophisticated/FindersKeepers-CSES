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

# ===== COLLISION CONFIGURATION =====
# Recommended Layer Setup:
# Collision Layer 4: Interactables / BodyParts
# Collision Mask: Layer 1 (Floor) + Layer 2 (Player)
const DEFAULT_COLLISION_LAYER: int = 8  # 1 << 3 (Layer 4)
const DEFAULT_COLLISION_MASK: int = 3   # 1 | 2 (Layer 1 Floor + Layer 2 Player)

func _ready() -> void:
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
