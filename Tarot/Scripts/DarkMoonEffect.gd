class_name DarkMoonEffect
extends TarotEffect

@export_group("Dark Moon")
@export var fov_multiplier: float = 0.7
@export var render_distance_multiplier: float = 0.5

func apply(target:Node)->void:
	if target.has_method("apply_vision_modifier"):
		target.apply_vision_modifier(fov_multiplier)
	else:
		push_warning("DarkMoonEffect: Target does not implement apply_vision_modifier()")

	if target.has_method("apply_render_distance_modifier"):
		target.apply_render_distance_modifier(render_distance_multiplier)
	else:
		push_warning("DarkMoonEffect: Target does not implement apply_render_distance_modifier()")

func remove(target:Node)->void:
	if target.has_method("remove_vision_modifier"):
		target.remove_vision_modifier(fov_multiplier)
	else:
		push_warning("DarkMoonEffect: Target does not implement remove_vision_modifier()")

	if target.has_method("remove_render_distance_modifier"):
		target.remove_render_distance_modifier(render_distance_multiplier)
	else:
		push_warning("DarkMoonEffect: Target does not implement remove_render_distance_modifier()")
