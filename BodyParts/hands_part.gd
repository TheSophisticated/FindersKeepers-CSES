class_name HandsPart
extends BodyPart

## Hands body part child class.
## Applies Hands Buff on collection: Higher Push Force and Reach Distance.

@export var push_force_multiplier: float = 1.25
@export var reach_distance_boost: float = 1.5

func _init() -> void:
	part_type = PartType.HANDS

func updateCount(collector: Node) -> void:
	# Call super implementation for base collection logic and GameManager communication
	super.updateCount(collector)
	
	# Apply specific Hands buff to collector if supported
	if collector.has_method("apply_hands_buff"):
		collector.call("apply_hands_buff", push_force_multiplier, reach_distance_boost)
	else:
		if "push_force" in collector:
			collector.push_force *= push_force_multiplier
		if "reach_distance" in collector:
			collector.reach_distance += reach_distance_boost
		print("Applied Hands Buff: Higher push force & reach distance")
