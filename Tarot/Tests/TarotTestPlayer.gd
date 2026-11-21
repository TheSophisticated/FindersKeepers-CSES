
class_name TarotTestPlayer
extends Node3D

@export var normal_fov: float = 75.0
@export var normal_render_distance: float = 100.0
@export var input_enabled: bool = true
@export var normal_speed: float = 5.0
@export var tarot_capacity: int = 2

# Camera is a sibling of the player in the test scene.
@onready var camera: Camera3D = get_node_or_null("../Camera3D")
@onready var effect_controller: TarotEffectController = get_node_or_null("TarotEffectController")

var current_speed: float
var tarot_cards: Array = []


func _ready() -> void:
	add_to_group("player")

	current_speed = normal_speed
	tarot_cards.resize(tarot_capacity)

	if camera != null:
		camera.fov = normal_fov
		camera.far = normal_render_distance
	else:
		push_warning("TarotTestPlayer: Camera3D not found at ../Camera3D")

	if effect_controller == null:
		push_warning("TarotTestPlayer: TarotEffectController not found")

	print("Tarot Test Player: ", name)
	print("WASD: Move")
	print("E: Collect first Tarot pickup")
	print("R: Collect second Tarot pickup")
	print("1: Use Tarot slot 0")
	print("2: Use Tarot slot 1")
	print("Escape: Release mouse")


func _process(delta: float) -> void:
	if not input_enabled:
		return

	var direction := Vector3.ZERO

	if Input.is_key_pressed(KEY_W):
		direction.z -= 1.0
	if Input.is_key_pressed(KEY_S):
		direction.z += 1.0
	if Input.is_key_pressed(KEY_A):
		direction.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		direction.x += 1.0

	if direction != Vector3.ZERO:
		global_position += direction.normalized() * current_speed * delta


func _input(event: InputEvent) -> void:
	if not input_enabled:
		return

	if event.is_action_pressed("tarot_slot_1"):
		use_tarot_card(0)
	elif event.is_action_pressed("tarot_slot_2"):
		use_tarot_card(1)
	elif event.is_action_pressed("interact"):
		collect_test_pickup("../TarotPickup")

	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

			KEY_1:
				use_tarot_card(0)

			KEY_2:
				use_tarot_card(1)

			KEY_E:
				collect_test_pickup("../TarotPickup")

			KEY_R:
				collect_test_pickup("../TarotPickup2")


func collect_test_pickup(pickup_path: NodePath) -> void:
	var pickup := get_node_or_null(pickup_path) as TarotPickup

	if not is_instance_valid(pickup):
		print("Tarot pickup is missing or has already been collected.")
		return

	if not pickup.collect(get_path()):
		print("Could not collect Tarot pickup.")


func add_tarot_card(card: TarotCard) -> bool:
	if card == null:
		push_warning("Cannot add a null Tarot card.")
		return false

	for i in range(tarot_cards.size()):
		if tarot_cards[i] == null:
			tarot_cards[i] = card

			print(
				"Picked up Tarot: ",
				card.card_name,
				" | Slot: ",
				i
			)
			return true

	print("Tarot inventory full.")
	return false


func use_tarot_card(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= tarot_cards.size():
		push_warning("Invalid Tarot card slot: " + str(slot_index))
		return

	var card: TarotCard = tarot_cards[slot_index]

	if card == null:
		print("Tarot slot is empty: ", slot_index)
		return

	if card.effect == null:
		push_warning("Tarot card has no effect: " + card.card_name)
		return

	if effect_controller == null:
		push_warning("TarotEffectController is missing.")
		return

	print("Using Tarot card: ", card.card_name)

	effect_controller.apply_effect(card.effect)
	tarot_cards[slot_index] = null

	print("Removed Tarot card from slot ", slot_index)


func apply_speed_modifier(multiplier: float) -> void:
	current_speed = normal_speed * multiplier
	print("Demon Speed applied. Current speed: ", current_speed)


func remove_speed_modifier(_multiplier: float) -> void:
	current_speed = normal_speed
	print("Demon Speed removed. Current speed: ", current_speed)


func apply_vision_modifier(multiplier: float) -> void:
	if camera == null:
		return

	camera.fov = normal_fov * multiplier
	print("Dark Moon applied. FOV: ", camera.fov)


func remove_vision_modifier(_multiplier: float) -> void:
	if camera == null:
		return

	camera.fov = normal_fov
	print("Dark Moon removed. FOV: ", camera.fov)


func apply_render_distance_modifier(multiplier: float) -> void:
	if camera == null:
		return

	camera.far = normal_render_distance * multiplier
	print("Render distance reduced: ", camera.far)


func remove_render_distance_modifier(_multiplier: float) -> void:
	if camera == null:
		return

	camera.far = normal_render_distance
	print("Render distance restored: ", camera.far)


func teleport_to(new_position: Vector3) -> void:
	global_position = new_position
	print("TEST: ", name, " teleported to ", new_position)
