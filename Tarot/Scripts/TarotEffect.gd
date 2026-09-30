class_name TarotEffect
extends Resource

enum EffectType{
	INSTANT,
	TIMED,
	PERMANENT
}

enum StackMode{
	NONE,
	EXTEND_DURATION,
	REFRESH_DURATION,
	ADDITIVE
}

enum TargetMode {
	SELF,
	SINGLE_PLAYER,
	ALL_PLAYERS,
	OPPONENTS
}

@export_group("Identity")
@export var effect_id:StringName
@export var display_name:String

@export_group("Behaviour")
@export var effect_type:EffectType = EffectType.TIMED
@export_range(0.0,300.0,0.5) var duration:float=10.0
@export var stack_mode: StackMode = StackMode.EXTEND_DURATION
@export var target_mode:TargetMode = TargetMode.SELF

func apply(target:Node)->void:
	pass

func remove(target:Node)->void:
	pass
