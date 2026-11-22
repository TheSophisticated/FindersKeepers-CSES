# CompassUI.gd
# Screen-space directional compass pointing to the nearest available body part.
# Draws a simple arrow programmatically using CanvasItem._draw().

extends Control

class_name CompassUI

const FADE_FULL_DISTANCE: float = 25.0
const FADE_ZERO_DISTANCE: float = 10.0
const ALTAR_FADE_FULL_DISTANCE: float = 10.0
const ALTAR_FADE_ZERO_DISTANCE: float = 3.5

@onready var distance_label: Label = $DistanceLabel

var world_objects: Node = null
var spell_center: Node3D = null
var local_player_id: int = -1
var target_part: Node = null
var _targeting_altar: bool = false
var _arrow_color: Color = Color(1.0, 1.0, 1.0, 0.9)
var _last_angle: float = 0.0
var _current_angle: float = 0.0
var _angle_epsilon: float = 0.01  # ~0.5 degrees

func _ready() -> void:
	# Find WorldObjects node (same path as GameMode uses)
	var game_mode = get_tree().get_first_node_in_group("GameMode")
	if game_mode and game_mode.has_node("SubViewportContainer/SubViewport/WorldObjects"):
		world_objects = game_mode.get_node("SubViewportContainer/SubViewport/WorldObjects")
	else:
		# Fallback: search from root
		world_objects = get_node_or_null("/root/GameMode/SubViewportContainer/SubViewport/WorldObjects")

	# Get local player's peer ID
	local_player_id = multiplayer.get_unique_id()

	# Hide distance label (no exact distance display)
	if distance_label:
		distance_label.visible = false
	# Initially hidden
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(delta: float) -> void:
	if not world_objects:
		visible = false
		return

	# Find local player (the one with multiplayer authority)
	var local_player = _get_local_player()
	if not local_player or not local_player.camera:
		visible = false
		return

	# While carrying a body part, guide the player back to the Church Altar (SpellCenter)
	var held_part = local_player.get("held_body_part")
	if held_part != null and is_instance_valid(held_part):
		_targeting_altar = true
		target_part = _get_spell_center()
	else:
		_targeting_altar = false
		target_part = _find_nearest_valid_body_part(local_player)

	if target_part:
		var next_color := Color(1.0, 1.0, 1.0, 0.9)
		if _targeting_altar:
			next_color = Color(1.0, 0.22, 0.22, 0.95)
		elif target_part is BodyPart:
			var c: Color = (target_part as BodyPart).part_color.lightened(0.15)
			next_color = Color(c.r, c.g, c.b, 0.95)
		if not next_color.is_equal_approx(_arrow_color):
			_arrow_color = next_color
			queue_redraw()
		_update_compass(local_player, target_part)
		visible = true
	else:
		visible = false

func _get_spell_center() -> Node3D:
	if is_instance_valid(spell_center):
		return spell_center
	if world_objects:
		spell_center = world_objects.get_node_or_null("SpellCenter") as Node3D
	if spell_center == null and get_tree() and get_tree().root:
		spell_center = get_tree().root.find_child("SpellCenter", true, false) as Node3D
	return spell_center

func _get_local_player() -> Node:
	# Find the player node that has multiplayer authority (our local player)
	for player in get_tree().get_nodes_in_group("player"):
		if player.is_multiplayer_authority():
			return player
	return null

func _find_nearest_valid_body_part(player: Node) -> Node:
	var nearest: Node = null
	var nearest_dist_sq: float = INF

	if not world_objects:
		return null

	for child in world_objects.get_children():
		# Validate instance first before accessing properties
		if not is_instance_valid(child):
			continue
		if not (child is BodyPart):
			continue

		var part: BodyPart = child

		# Skip own body parts
		if part.owner_id == local_player_id:
			continue

		# Skip carried or collected parts
		if part.is_carried or part.is_collected:
			continue

		var dist_sq = player.global_position.distance_squared_to(part.global_position)
		if dist_sq < nearest_dist_sq:
			nearest_dist_sq = dist_sq
			nearest = part

	return nearest

func _update_compass(player: Node, target: Node) -> void:
	var camera = player.camera
	if not camera:
		return

	# Vector from camera to target (world space)
	var to_target = (target.global_position - camera.global_position).normalized()

	# Camera forward vector (Godot: -Z is forward)
	var forward = -camera.global_transform.basis.z

	# Project both vectors onto horizontal plane (XZ) for yaw-only compass
	to_target.y = 0
	forward.y = 0

	if to_target.length_squared() < 0.0001 or forward.length_squared() < 0.0001:
		return

	to_target = to_target.normalized()
	forward = forward.normalized()

	# Angle from forward to target (positive = right/clockwise)
	# atan2(x, z) gives angle from +Z axis; we want angle from forward to target.
	# In Godot 2D, positive rotation is clockwise. Forward = up on compass (0 rad).
	# Target to the right should give positive rotation.
	var target_angle = atan2(to_target.x, to_target.z)
	var forward_angle = atan2(forward.x, forward.z)
	var angle_diff = forward_angle - target_angle

	# Normalize to [-PI, PI]
	angle_diff = fmod(angle_diff + PI, 2 * PI) - PI

	# Only queue redraw if angle changed significantly
	if abs(angle_diff - _last_angle) > _angle_epsilon:
		_last_angle = angle_diff
		_current_angle = angle_diff
		queue_redraw()

	# Update fade based on distance to target (keep Altar visible closer)
	var distance = player.global_position.distance_to(target.global_position)
	var fade_full := ALTAR_FADE_FULL_DISTANCE if _targeting_altar else FADE_FULL_DISTANCE
	var fade_zero := ALTAR_FADE_ZERO_DISTANCE if _targeting_altar else FADE_ZERO_DISTANCE
	var alpha: float = 0.0
	if distance >= fade_full:
		alpha = 1.0
	elif distance <= fade_zero:
		alpha = 0.0
	else:
		alpha = (distance - fade_zero) / (fade_full - fade_zero)
	modulate.a = alpha

# Draw a simple arrow triangle programmatically
func _draw() -> void:
	var arrow_size = min(size.x, size.y) * 0.4
	var center = size / 2.0

	# Arrow points upward (0 radians = pointing up in screen space)
	# Points defined relative to center; we apply rotation manually
	var points = PackedVector2Array([
		Vector2(0, -arrow_size),           # Tip (up from center)
		Vector2(arrow_size * 0.6, arrow_size * 0.7),  # Bottom right
		Vector2(-arrow_size * 0.6, arrow_size * 0.7)  # Bottom left
	])

	# Rotate points around center by current angle
	var cos_a = cos(_current_angle)
	var sin_a = sin(_current_angle)
	for i in range(points.size()):
		var p = points[i]
		var rx = p.x * cos_a - p.y * sin_a
		var ry = p.x * sin_a + p.y * cos_a
		points[i] = Vector2(rx, ry) + center

	# Tinted arrow matching target owner color (or crimson for Church Altar)
	draw_polygon(points, [_arrow_color], [])

	# Optional: thin outline
	var outline_color = Color(0.0, 0.0, 0.0, 0.6)
	var outline_points = points.duplicate()
	outline_points.push_back(points[0])
	draw_polyline(outline_points, outline_color, 2.0)