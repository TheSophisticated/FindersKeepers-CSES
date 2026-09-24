class_name TarotTestPlayer
extends Node

@onready var tarot_pickup_1: TarotPickup = $"../TarotPickup"
@onready var tarot_pickup_2: TarotPickup = $"../TarotPickup2"

@export var normal_speed:float = 5.0
@export var tarot_capacity: int = 2

var current_speed:float
var tarot_cards: Array[TarotCard] = []

@onready var effect_controller: TarotEffectController = $TarotEffectController

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	current_speed = normal_speed
	tarot_cards.resize(tarot_capacity)

	print("Tarot Test Player")
	print("normal speed :", normal_speed)

	print("Press E to pick up Tarot")
	print("Press 1 to use slot 0")
	print("Press 2 to use slot 1")

func apply_speed_modifier(multiplier:float)->void:
	current_speed = normal_speed*multiplier
	
	print("Demon Speed Applied")
	print("Current Speed : ",current_speed)

func remove_speed_modifier(multiplier:float)->void:
	current_speed = normal_speed
	print("Demon Speed Removed")
	print("Current Speed : ",current_speed)

func add_tarot_card(card: TarotCard) -> bool:
	if card == null:
		push_warning("Cannot add a null Tarot card.")
		return false

	for i in range(tarot_cards.size()):
		if tarot_cards[i] == null:
			tarot_cards[i] = card

			print(
				"Picked up Tarot Card: ",
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
		push_warning("Tarot slot is empty: " + str(slot_index))
		return

	if card.effect == null:
		push_warning("Tarot card has no effect: " + card.card_name)
		return

	print("Using Tarot Card: ", card.card_name)

	effect_controller.apply_effect(card.effect)

	tarot_cards[slot_index] = null

	print(
		"Removed Tarot Card: ",
		card.card_name,
		" | Inventory: ",
		tarot_cards.size(),
		"/",
		tarot_capacity
	)

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.pressed and not event.echo:
			if event.keycode == KEY_1:
				use_tarot_card(0)
			elif event.keycode == KEY_2:
				use_tarot_card(1)
			elif event.keycode == KEY_E:
				collect_test_pickup(tarot_pickup_1)
			elif event.keycode == KEY_R:
				collect_test_pickup(tarot_pickup_2)

func collect_test_pickup(pickup: TarotPickup) -> void:
	if pickup == null:
		push_warning("Tarot Pickup not found ")
		return 
	if not pickup.collect(self):
		print("could not collect tarot pickup")
