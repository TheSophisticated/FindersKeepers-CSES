class_name TarotPickup
extends Area3D

@export var card:TarotCard

func collect(player:Node)->bool:
	if card==null:
		push_warning("TarotPicckup : No Tarot Card assigned")
		return false
	
	if player == null:
		push_warning("TarotPickup : recieved a null player")
		return false
	
	if not player.has_method("add_tarot_card"):
		push_warning("Player cannot receive Tarot cards.")
		return false
	
	var added: bool = player.add_tarot_card(card)
	if not added:
		return false
	queue_free()
	return true

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
