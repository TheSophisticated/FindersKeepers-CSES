class_name HeadPart
extends BodyPart

## Head body part child class.
## Applies Head Buff on collection: Increased Render Distance and FOV.

@export var fov_boost: float = 10.0

func _init() -> void:
	part_type = PartType.HEAD

func updateCount(collector: Node) -> void:
	# Call super implementation for base collection logic and GameManager communication
	super.updateCount(collector)
	
	# Apply specific Head buff to collector if supported
	if collector.has_method("apply_head_buff"):
		collector.call("apply_head_buff", fov_boost)
	elif "fov_normal" in collector:
		collector.fov_normal += fov_boost
		print("Applied Head Buff: Increased FOV by ", fov_boost)
