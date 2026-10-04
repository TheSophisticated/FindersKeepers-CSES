extends Node3D

## Room-level wrapper, so callers don't need to know where the fixture is
## instanced. Everything here forwards to the chandelier underneath.

## Emitted when the chandelier switches on or off.
signal light_changed(is_on: bool)

## Path to the chandelier, relative to this node.
@export var chandelier_path: NodePath = ^"Chandelier_01_4k"

@onready var chandelier: Chandelier = get_node(chandelier_path)

func _ready() -> void:
	chandelier.light_changed.connect(_on_light_changed)

## Turns the chandelier on or off.
func set_light(on: bool) -> void:
	chandelier.set_light(on)

## Returns true while the chandelier is lit.
func is_light_on() -> bool:
	return chandelier.is_light_on()

## Flips the chandelier between on and off.
func toggle_light() -> void:
	chandelier.toggle_light()

func _on_light_changed(on: bool) -> void:
	light_changed.emit(on)
	
