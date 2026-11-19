# TarotInventoryUI.gd
# Displays the local player's tarot cards in the HUD slots.
# Read-only view of Player.tarot_cards; it never modifies the inventory.

extends Control

# Slot panels and their text labels, ordered left to right.
@onready var slot_panels: Array[Control] = [
	$HBoxContainer/Slot1,
	$HBoxContainer/Slot2,
]
@onready var slot_labels: Array[Label] = [
	$HBoxContainer/Slot1/Label,
	$HBoxContainer/Slot2/Label,
]

# Untyped so we can access the Player's tarot members dynamically.
var _player = null
var _slot_art: Array[TextureRect] = []
var _active_effects_label: Label = null

func _ready() -> void:
	for i in range(slot_panels.size()):
		var art := TextureRect.new()
		art.name = "CardArt"
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.modulate = Color(1, 1, 1, 0.72)
		slot_panels[i].add_child(art)
		slot_panels[i].move_child(art, 0)
		_slot_art.append(art)
		slot_labels[i].vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		slot_labels[i].add_theme_color_override("font_color", Color("fff3d5"))
		slot_labels[i].add_theme_color_override("font_shadow_color", Color(0.05, 0.02, 0.04, 0.95))
		slot_labels[i].add_theme_constant_override("shadow_offset_x", 1)
		slot_labels[i].add_theme_constant_override("shadow_offset_y", 2)

	_active_effects_label = Label.new()
	_active_effects_label.name = "ActiveEffectsStatus"
	_active_effects_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_active_effects_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_active_effects_label.offset_top = -26.0
	_active_effects_label.offset_bottom = -4.0
	_active_effects_label.add_theme_font_size_override("font_size", 13)
	_active_effects_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	_active_effects_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	_active_effects_label.add_theme_constant_override("shadow_offset_x", 1)
	_active_effects_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_active_effects_label)

	_try_bind_local_player()

# Players are spawned by GameMode, and a node's _ready() runs before its
# parent's, so the local player does not exist yet when this runs. Retry
# until it shows up (this also covers players that join later).

func _process(_delta : float ) -> void:
	if not is_instance_valid(_player):
		_try_bind_local_player()
		return
	_update_active_effects_display()

func _update_active_effects_display() -> void:
	if _active_effects_label == null or not is_instance_valid(_player):
		return
	var badges: PackedStringArray = []
	var ec = _player.get("effect_controller")
	if ec != null and "active_effects" in ec:
		for eid in ec.active_effects.keys():
			var edata: Dictionary = ec.active_effects[eid]
			var rem := float(edata.get("remaining", -1.0))
			if rem > 0.0:
				badges.append("%s (%.1fs)" % [String(eid).to_upper().replace("_", " "), rem])
	if float(_player.get("input_multiplier")) < 0.0 and not ("HANGED MAN" in " ".join(badges)):
		badges.append("INVERTED CONTROLS")
	if float(_player.get("vision_modifier")) < 0.9 and not ("DARK MOON" in " ".join(badges)):
		badges.append("BLINDED")
	_active_effects_label.text = " | ".join(badges)
	_active_effects_label.visible = not badges.is_empty()

func _try_bind_local_player() -> void:
	if is_instance_valid(_player):
		return

	var scene := get_tree().current_scene
	var world: Node = scene.get("world") if scene != null else null
	if world == null:
		return

	for child in world.get_children():
		# has_method filters out the floor/pickups, which also report
		# authority 1 and would otherwise match on the host.
		if child.has_method("add_tarot_card") and child.is_multiplayer_authority():
			_player = child
			_player.tarot_card_added.connect(_on_tarot_card_added)
			_player.tarot_card_removed.connect(_on_tarot_card_removed)
			refresh_slots()
			return


func _on_tarot_card_added(_card: TarotCard, _slot: int) -> void:
	refresh_slots()

func _on_tarot_card_removed(_slot: int)->void:
	refresh_slots()

# Redraws every slot from the player's inventory.
func refresh_slots() -> void:
	if not is_instance_valid(_player):
		return

	for i in range(slot_panels.size()):
		var card: TarotCard = null
		if i < _player.tarot_cards.size():
			card = _player.tarot_cards[i]

		var button_hint: String = "[1 / LB]" if i == 0 else "[2 / RB]"
		if card == null:
			_slot_art[i].texture = null
			slot_labels[i].text = button_hint
			slot_panels[i].modulate = Color(1, 1, 1, 0.4)
		else:
			_slot_art[i].texture = card.art
			_slot_art[i].modulate = Color(1, 1, 1, 1)
			slot_labels[i].text = "%s\n%s" % [button_hint, card.card_name]
			slot_panels[i].modulate = Color(1, 1, 1, 1)
