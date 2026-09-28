class_name TorsoPart
extends BodyPart

## Torso body part child class.
## Applies Torso Buff on collection: Ability to carry 1 extra Tarot Card / Sliding Boost Increase.

@export var extra_tarot_slots: int = 1
@export var slide_boost_multiplier: float = 1.2

func _init() -> void:
	part_type = PartType.TORSO

func updateCount(collector: Node) -> void:
	# Call super implementation for base collection logic and GameManager communication
	super.updateCount(collector)
	
	# Apply specific Torso buff to collector if supported
	if collector.has_method("apply_torso_buff"):
		collector.call("apply_torso_buff", extra_tarot_slots, slide_boost_multiplier)
	else:
		if "max_tarot_slots" in collector:
			collector.max_tarot_slots += extra_tarot_slots
		if "slide_boost" in collector:
			collector.slide_boost *= slide_boost_multiplier
		print("Applied Torso Buff: +1 Tarot Card Slot & Sliding Boost Increase")
