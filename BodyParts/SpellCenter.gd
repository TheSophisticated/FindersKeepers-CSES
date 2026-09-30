# SpellCenter.gd
# Central ritual station. A player deposits the body part they are carrying
# by walking into this area; that is the only point where BodyPart.collect()
# runs, so progress, buffs and removal happen here and nowhere else.

class_name SpellCenter
extends Area3D

## Emitted after a body part is successfully deposited.
signal part_deposited(collector: Node, part: Node)

func _ready() -> void:
	# The player is a CharacterBody3D, so body_entered is the signal to use.
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	# Only the player exposes deposit_body_part(); anything else is ignored.
	if not body.has_method("deposit_body_part"):
		return

	var part = body.get("held_body_part")
	if part == null:
		return  # player is not carrying a body part

	body.deposit_body_part()
	part_deposited.emit(body, part)
	print("Spell Center received a body part from: ", body.name)
