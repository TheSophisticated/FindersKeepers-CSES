@tool
class_name Chandelier
extends Node3D

## Emitted whenever the chandelier switches on or off.
signal light_changed(is_on: bool)

## Master state. Assigning this updates every bulb.
@export var is_on := true:
	set(value):
		if is_on == value:
			return
		is_on = value
		_refresh()

## Energy each bulb reaches when lit.
## Energy each bulb reaches when lit.
@export var energy := 1.0:
	set(value):
		energy = value
		_refresh()

## Colour of every bulb. Change the swatch to retint the whole chandelier.
@export var tint := Color(1.0, 0.82, 0.55):
	set(value):
		tint = value
		_refresh()
		
		
		
var _lights: Array[Light3D] = []

func _ready() -> void:
	_lights.assign(find_children("*", "Light3D", true, false))
	print("ready chandelier")
	_refresh()


## ===== PUBLIC INTERFACE =====

## Turns the chandelier on or off. Callable on any peer.
func set_light(on: bool) -> void:
	if multiplayer.is_server():
		_set_light.rpc(on)
	else:
		_set_light.rpc_id(1, on)

## Returns true while the chandelier is lit.
func is_light_on() -> bool:
	return is_on

## Flips the chandelier between on and off.
func toggle_light() -> void:
	if multiplayer.is_server():
		_toggle.rpc()
	else:
		_toggle.rpc_id(1)


## ===== INTERNAL =====

@rpc("authority", "call_local", "reliable")
func _set_light(on: bool) -> void:
	is_on = on
	light_changed.emit(is_on)

@rpc("authority", "call_local", "reliable")
func _toggle() -> void:
	is_on = not is_on
	light_changed.emit(is_on)

func _refresh() -> void:
	# Also runs during scene load, before _ready() has collected the bulbs.
	if _lights.is_empty():
		return
	var target := energy if is_on else 0.0
	for bulb in _lights:
		bulb.light_energy = target
		bulb.light_color = tint
