extends SubViewportContainer
## Runtime controls for how the 3D world is rendered into the window.
##
## The world renders into the child SubViewport and this container upscales
## it to fill its rect. Inspector knobs:
##   pixel_size        - how many screen pixels make one rendered pixel.
##                       1 = native resolution, 2 = half-res chunky pixels, ...
##                       (this is the container's built-in "stretch_shrink")
##   nearest_filter    - crisp pixel squares (on) vs smooth upscaling (off)
##   lock_aspect_ratio - render at a fixed aspect instead of the window's
##   aspect_ratio      - the aspect to render at when locked (e.g. 16 x 9)
##
## All changes apply instantly, even while the game is running.

@export_group("Pixelation")
@export_range(1, 16, 1) var pixel_size: int = 1:
	set(value):
		pixel_size = clampi(value, 1, 16)
		_apply()

@export var nearest_filter: bool = true:
	set(value):
		nearest_filter = value
		_apply()

@export_group("Aspect Ratio")
@export var lock_aspect_ratio: bool = false:
	set(value):
		lock_aspect_ratio = value
		_apply()

@export var aspect_ratio: Vector2 = Vector2(16, 9):
	set(value):
		aspect_ratio = value
		_apply()

var _last_render_size := Vector2i.ZERO


func _ready():
	# Editor preview: leave the scene layout untouched.
	if Engine.is_editor_hint():
		return
	_apply()
	if not get_window().size_changed.is_connected(_on_window_size_changed):
		get_window().size_changed.connect(_on_window_size_changed)


func _on_window_size_changed() -> void:
	_apply()


func _apply() -> void:
	# Values can be assigned before the node enters the tree (scene load) or
	# from the editor inspector; neither should resize anything.
	if Engine.is_editor_hint() or not is_inside_tree():
		return
	var window_size := get_window().size
	if window_size.x < 2 or window_size.y < 2:
		return

	# Pixelation: with stretch enabled the container renders its SubViewport at
	# (container size / stretch_shrink) and upscales it to fill its rect, so
	# stretch_shrink is exactly "screen pixels per rendered pixel".
	stretch = true
	stretch_shrink = pixel_size
	texture_filter = (
		CanvasItem.TEXTURE_FILTER_NEAREST
		if nearest_filter
		else CanvasItem.TEXTURE_FILTER_LINEAR
	)

	# Aspect ratio: fit the container into the window at the target aspect,
	# centered (black bars), or let it fill the whole window. The SubViewport's
	# render resolution follows the container automatically.
	var rect := Rect2(Vector2.ZERO, Vector2(window_size.x, window_size.y))
	if lock_aspect_ratio and aspect_ratio.x > 0.0 and aspect_ratio.y > 0.0:
		var target_aspect := aspect_ratio.x / aspect_ratio.y
		var window_aspect := float(window_size.x) / float(window_size.y)
		if window_aspect > target_aspect:
			# Window is wider than the target: match the height.
			rect.size.y = float(window_size.y)
			rect.size.x = rect.size.y * target_aspect
		else:
			# Window is taller than the target: match the width.
			rect.size.x = float(window_size.x)
			rect.size.y = rect.size.x / target_aspect
		rect.position = (Vector2(window_size.x, window_size.y) - rect.size) / 2.0
		# Absolute rect: all four anchors pinned to the top-left corner.
		anchor_left = 0.0
		anchor_top = 0.0
		anchor_right = 0.0
		anchor_bottom = 0.0
		offset_left = rect.position.x
		offset_top = rect.position.y
		offset_right = rect.position.x + rect.size.x
		offset_bottom = rect.position.y + rect.size.y
	else:
		# Fill the window: anchors stretched to all four edges, zero offsets.
		anchor_left = 0.0
		anchor_top = 0.0
		anchor_right = 1.0
		anchor_bottom = 1.0
		offset_left = 0.0
		offset_top = 0.0
		offset_right = 0.0
		offset_bottom = 0.0

	# Report the effective render resolution whenever it changes.
	var render_size := Vector2i(int(rect.size.x) / pixel_size, int(rect.size.y) / pixel_size)
	if render_size != _last_render_size:
		_last_render_size = render_size
		print("RenderScaler: window %dx%d -> render %dx%d (pixel_size=%d, aspect=%s)" % [
			window_size.x, window_size.y, render_size.x, render_size.y,
			pixel_size, "locked" if lock_aspect_ratio else "window"
		])
