class_name HangedManEffect
extends TarotEffect

func apply(target:Node)->void:
	if target.has_method("apply_input_modifier"):
		target.apply_input_modifier(-1.0)
	else:
		push_warning("HangedManEffect: Target does not implement apply_input_modifier()")

func remove(target:Node)->void:
	if target.has_method("remove_input_modifier"):
		target.remove_input_modifier(-1.0)
	else:
		push_warning("HangedManEffect: Target does not implement remove_input_modifier()")	
