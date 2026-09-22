class_name TarotEffectController
extends Node

var target: Node
var active_effects:Dictionary = {}

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	target = get_parent()
	
	if target==null:
		push_error("TarotEffectController: No target found")

func apply_effect(effect: TarotEffect)->void:
	if effect == null :
		push_warning("TarotEffectController: Cannot apply a null effect")
		return 
	if effect.effect_id == &"":
		push_warning("TarotEffectController: Effect has no effect_id")
		return
	
	#Instant effects
	if effect.effect_type == TarotEffect.EffectType.INSTANT:
		effect.apply(target)
		return
	
	#Effect is already active 
	if active_effects.has(effect.effect_id):
		_handle_stack(effect)
		return
	
	#First Time
	effect.apply(target)
	
	var remaining_time: float = -1.0
	
	if effect.effect_type == TarotEffect.EffectType.TIMED:
		remaining_time = effect.duration
		
	active_effects[effect.effect_id] = {
		"effect":effect,
		"remaining":remaining_time,
		"stacks":1
	}
	
	print(
		"Effect Applied: ",
		effect.effect_id,
		" | Remaining: ",
		remaining_time,
		" | Stacks: 1"
	)
	
func _handle_stack(effect:TarotEffect)->void:
	var data: Dictionary = active_effects[effect.effect_id]
	
	match effect.stack_mode:
		TarotEffect.StackMode.NONE:
			return
		TarotEffect.StackMode.EXTEND_DURATION:
			data["remaining"]+=effect.duration
			print(
		"Effect Stacked: ",
		effect.effect_id,
		" | Remaining: ",
		data["remaining"],
		" | Stacks: ",
		data["stacks"]
	)
		TarotEffect.StackMode.REFRESH_DURATION:
			data["remaining"]=effect.duration
		TarotEffect.StackMode.ADDITIVE:
			effect.apply(target)
			data["stacks"]+=1

func remove_effect(effect_id:StringName)->void:
	if not active_effects.has(effect_id):
		return
	var data:Dictionary = active_effects[effect_id]
	var effect: TarotEffect = data["effect"]
	var stacks: int  = data["stacks"]
	
	for i in range(stacks):
		effect.remove(target)
	
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
