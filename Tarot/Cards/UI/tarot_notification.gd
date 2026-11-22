
extends CanvasLayer

@onready var panel: PanelContainer = $PanelContainer
@onready var message_label: Label = $PanelContainer/MessageLabel

var notification_timer: Timer
var _fade_tween: Tween = null

func _ready() -> void:
	hide()

	notification_timer = Timer.new()
	notification_timer.one_shot = true
	notification_timer.wait_time = 3.0
	add_child(notification_timer)
	notification_timer.timeout.connect(_fade_out)

func show_notification(message: String) -> void:
	message_label.text = message
	notification_timer.start()
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	if panel:
		panel.modulate.a = 0.0
	show()
	if panel:
		_fade_tween = create_tween()
		_fade_tween.tween_property(panel, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _fade_out() -> void:
	if not visible:
		return
	if panel == null:
		hide()
		return
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(panel, "modulate:a", 0.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_fade_tween.tween_callback(hide)
