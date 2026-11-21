class_name TarotEffectController
extends Node

var target: Node
var active_effects:Dictionary = {}

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	target = get_parent()

	if target==null:
		push_error("TarotEffectController: No target found")

func _get_targets(effect: TarotEffect)->Array[Node]:
	var targets: Array[Node] = []
	match effect.target_mode:
		TarotEffect.TargetMode.SELF:
			targets.append(target)
		TarotEffect.TargetMode.ALL_PLAYERS:
			targets = get_tree().get_nodes_in_group("player")
		TarotEffect.TargetMode.OPPONENTS:
			for player in get_tree().get_nodes_in_group("player"):
				if player != target:
					targets.append(player)
			# Fallback for solo testing / practice when no opponents exist in the match
			if targets.is_empty() and is_instance_valid(target):
				targets.append(target)
		TarotEffect.TargetMode.SINGLE_PLAYER:
			push_warning("NOT IMPLEMENTED YET")

	return targets

func apply_effect(effect: TarotEffect)->bool:
	if effect == null :
		push_warning("TarotEffectController: Cannot apply a null effect")
		return false
	if effect.effect_id == &"":
		push_warning("TarotEffectController: Effect has no effect_id")
		return false

	var targets: Array[Node] = _get_targets(effect)

	if targets.is_empty():
		push_warning("TarotEffectController : No valid targets found for "+str(effect.effect_id))
		return false

	#Instant effects
	if effect.effect_type == TarotEffect.EffectType.INSTANT:
		for current_target in targets:
			if is_instance_valid(current_target):
				effect.apply(current_target)
				_notify_target(current_target, effect.applied_message)

		return true

	#Effect is already active
	if active_effects.has(effect.effect_id):
		return _handle_stack(effect)

	#First Time
	for current_target in targets:
		if is_instance_valid(current_target):
			effect.apply(current_target)
			_notify_target(current_target, effect.applied_message)


	var remaining_time: float = -1.0

	if effect.effect_type == TarotEffect.EffectType.TIMED:
		remaining_time = effect.duration

	active_effects[effect.effect_id] = {
		"effect":effect,
		"remaining":remaining_time,
		"stacks":1,
		"targets":targets
	}

	print(
		"Effect Applied: ",
		effect.effect_id,
		" | Remaining: ",
		remaining_time,
		" | Stacks: 1"
	)
	return true

func _handle_stack(effect:TarotEffect)->bool:
	var data: Dictionary = active_effects[effect.effect_id]

	match effect.stack_mode:
		TarotEffect.StackMode.NONE:
			return false
		TarotEffect.StackMode.EXTEND_DURATION:
			data["remaining"]+=effect.duration
			print("Effect Stacked: ",effect.effect_id," | Remaining: ",data["remaining"]," | Stacks: ",data["stacks"])
			return true
		TarotEffect.StackMode.REFRESH_DURATION:
			data["remaining"]=effect.duration
			return true
		TarotEffect.StackMode.ADDITIVE:
			var targets: Array[Node] = data["targets"]
			for current_target in targets:
				if is_instance_valid(current_target):
					effect.apply(current_target)
					_notify_target(current_target, effect.applied_message)
			data["stacks"]+=1
			return true
	return false

func remove_effect(effect_id:StringName)->void:
	if not active_effects.has(effect_id):
		return
	var data:Dictionary = active_effects[effect_id]
	var effect: TarotEffect = data["effect"]
	var stacks: int  = data["stacks"]
	var targets:Array[Node] = data["targets"]

	for current_target in targets:
		if not is_instance_valid(current_target):
			continue
		for i in range(stacks):
			effect.remove(current_target)
		_notify_target(current_target, effect.expired_message)

	active_effects.erase(effect_id)
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	for effect_id in active_effects.keys():
		var data: Dictionary = active_effects[effect_id]

		if data["remaining"] < 0.0:
			continue

		data["remaining"]-=delta

		if data["remaining"] <= 0.0:
			print("Effect Expired: ", effect_id)
			remove_effect(effect_id)


func _notify_target(current_target: Node, message: String) -> void:
	if message.is_empty():
		return

	if is_instance_valid(current_target) and current_target.has_method("show_tarot_notification"):
		current_target.show_tarot_notification(message)
