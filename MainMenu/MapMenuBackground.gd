extends Control

## Displays the lightweight main menu backdrop artwork instead of instantiating
## the full 254 MB GameMode.tscn world in the main menu.

const MENU_BG_TEXTURE_PATH := "res://main-menu1.png"

var _bg_rect: TextureRect = null
var _pulse_time: float = 0.0


func _ready() -> void:
	_bg_rect = TextureRect.new()
	_bg_rect.name = "MenuArtworkBackground"
	_bg_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(MENU_BG_TEXTURE_PATH):
		_bg_rect.texture = load(MENU_BG_TEXTURE_PATH) as Texture2D
	add_child(_bg_rect)


func _process(delta: float) -> void:
	if _bg_rect == null:
		return
	_pulse_time += delta
	# Subtle atmospheric brightness pulse for horror mood
	var b := 0.94 + 0.06 * sin(_pulse_time * 0.9)
	_bg_rect.modulate = Color(b, b * 0.98, b * 0.98, 1.0)

