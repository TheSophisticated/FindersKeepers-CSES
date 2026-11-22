extends CanvasLayer

@onready var panel: PanelContainer = $PanelContainer
@onready var name_label: Label = $PanelContainer/VBoxContainer/NameLabel
@onready var description_label: Label = $PanelContainer/VBoxContainer/DescriptionLabel

var _is_showing: bool = false
var _fade_tween: Tween = null

func _ready() -> void:
	panel.visible = false
	panel.modulate.a = 0.0

func show_tooltip(card_name: String, card_description: String) -> void:
	name_label.text = card_name
	description_label.text = card_description
	if _is_showing:
		return
	_is_showing = true
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	panel.show()
	_fade_tween = create_tween()
	_fade_tween.tween_property(panel, "modulate:a", 1.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func hide_tooltip() -> void:
	if not _is_showing:
		return
	_is_showing = false
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(panel, "modulate:a", 0.0, 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_fade_tween.tween_callback(func():
		if is_instance_valid(panel) and not _is_showing:
			panel.hide()
	)
