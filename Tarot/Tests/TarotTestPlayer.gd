class_name TarotTestPlayer
extends Node

@export var normal_speed:float = 5.0

var current_speed:float
@onready var effect_controller: TarotEffectController = $TarotEffectController

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	current_speed = normal_speed
	
	print("Tarot Test Player")
	print("normal speed :",normal_speed)
	print("Press space to use Demon Speed")

func apply_speed_modifier(multiplier:float)->void:
	current_speed = normal_speed*1.5
	
	print("Demon Speed Applied")
	print("Current Speed : ",current_speed)

func remove_speed_modifier(multiplier:float)->void:
	current_speed = normal_speed
	print("Demon Speed Removed")
	print("Current Speed : ",current_speed)

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.pressed and not event.echo and event.keycode == KEY_SPACE:
			_use_demon_speed()

func _use_demon_speed()->void:
	var demon_speed_effect:TarotEffect = preload(
		"res://Tarot/Cards/Effects/DemonSpeedEffect.tres"
	)
	
	effect_controller.apply_effect(demon_speed_effect)
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
