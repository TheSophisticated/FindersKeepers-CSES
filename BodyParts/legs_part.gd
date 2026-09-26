class_name LegsPart
extends BodyPart

## Legs body part child class.
## Applies Legs Buff on collection: Small permanent movement speed boost.

@export var speed_boost: float = 1.5

func _init() -> void:
	part_type = PartType.LEGS

func updateCount(collector: Node) -> void:
	# Call super implementation for base collection logic and GameManager communication
	super.updateCount(collector)
	
	# Apply specific Legs buff to collector if supported
	if collector.has_method("apply_legs_buff"):
		collector.call("apply_legs_buff", speed_boost)
	else:
		if "walk_speed" in collector:
			collector.walk_speed += speed_boost
		if "sprint_speed" in collector:
			collector.sprint_speed += speed_boost
		if "SPEED" in collector:
			collector.SPEED += speed_boost
		print("Applied Legs Buff: Permanent speed boost of ", speed_boost)
