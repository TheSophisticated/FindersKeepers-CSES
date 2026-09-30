class_name DemonSpeedEffect
extends TarotEffect

@export_group("Demon Speed")
@export_range(1.0,3.0,0.05) var speed_multiplier:float = 1.5

func apply(target:Node)->void:
	if target.has_method("apply_speed_modifier"):
		target.apply_speed_modifier(speed_multiplier)
	else:
		push_warning("Target does not implement apply_speed_modifier()")

func remove(target:Node)->void:
	if target.has_method("remove_speed_modifier"):
		target.remove_speed_modifier(speed_multiplier)
	else:
		push_warning("Target does not implement remove_speed_modifier()")
