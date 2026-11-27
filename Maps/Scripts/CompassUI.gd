# CompassUI.gd
# Screen-space directional white arrow compass pointing to the nearest available body part
# (or back to the Church Altar while carrying a body part).
# Hardened for host and client multiplayer replication.

extends Control

class_name CompassUI

const FADE_FULL_DISTANCE: float = 18.0
const FADE_ZERO_DISTANCE: float = 2.0
const ALTAR_FADE_FULL_DISTANCE: float = 10.0
const ALTAR_FADE_ZERO_DISTANCE: float = 2.5

@onready var distance_label: Label = $DistanceLabel

var world_objects: Node = null
var spell_center: Node3D = null
var local_player_id: int = -1
var target_part: Node = null
var _targeting_altar: bool = false
var _arrow_color: Color = Color(1.0, 1.0, 1.0, 0.96)
var _accent_color: Color = Color(1.0, 1.0, 1.0, 0.0)
var _last_angle: float = 0.0
var _current_angle: float = 0.0
var _has_angle: bool = false
var _angle_epsilon: float = 0.005 # ~0.3 degrees


func _ready() -> void:
	_resolve_world_objects()
	_refresh_local_player_id(null)

	if distance_label:
		distance_label.visible = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _resolve_world_objects() -> void:
	if is_instance_valid(world_objects):
		return
	var game_mode = get_tree().get_first_node_in_group("GameMode")
	if game_mode and game_mode.has_node("SubViewportContainer/SubViewport/WorldObjects"):
		world_objects = game_mode.get_node("SubViewportContainer/SubViewport/WorldObjects")
		return
	world_objects = get_node_or_null("/root/GameMode/SubViewportContainer/SubViewport/WorldObjects")
	if world_objects == null and get_tree() and get_tree().current_scene:
		world_objects = get_tree().current_scene.find_child("WorldObjects", true, false)


func _refresh_local_player_id(local_player: Node) -> void:
	if is_instance_valid(local_player):
		var pid = local_player.get("player_id")
		if pid != null and int(pid) > 0:
			local_player_id = int(pid)
			return
	if multiplayer != null and multiplayer.has_multiplayer_peer():
		local_player_id = multiplayer.get_unique_id()


func _process(delta: float) -> void:
	if GameManager != null and GameManager.current_state == GameManager.MatchState.GAME_OVER:
		visible = false
		return

	_resolve_world_objects()

	var local_player := _get_local_player()
	if not is_instance_valid(local_player) or local_player.get("camera") == null:
		visible = false
		return

	_refresh_local_player_id(local_player)

	# Hide compass if local player has been eliminated (spectating)
	if GameManager != null and GameManager.players.has(local_player_id):
		if not bool(GameManager.players[local_player_id].get("is_alive", true)):
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

	if is_instance_valid(target_part):
		# Keep the iconic crisp white arrow for body parts (with a subtle owner-color base pip),
		# and shift to crimson when hauling a limb back to the Church Altar.
		var next_arrow := Color(1.0, 1.0, 1.0, 0.96)
		var next_accent := Color(1.0, 1.0, 1.0, 0.0)
		if _targeting_altar:
			next_arrow = Color(1.0, 0.25, 0.25, 0.96)
			next_accent = Color(1.0, 0.85, 0.35, 0.95)
		elif target_part is BodyPart:
			var pc: Color = (target_part as BodyPart).part_color.lightened(0.15)
			next_accent = Color(pc.r, pc.g, pc.b, 0.95)
		if not next_arrow.is_equal_approx(_arrow_color) or not next_accent.is_equal_approx(_accent_color):
			_arrow_color = next_arrow
			_accent_color = next_accent
			queue_redraw()
		_update_compass(local_player, target_part, delta)
		visible = true
	else:
		_has_angle = false
		visible = false


func _get_spell_center() -> Node3D:
	if is_instance_valid(spell_center):
		return spell_center
	if is_instance_valid(world_objects):
		spell_center = world_objects.get_node_or_null("SpellCenter") as Node3D
	if spell_center == null and get_tree() and get_tree().root:
		spell_center = get_tree().root.find_child("SpellCenter", true, false) as Node3D
	return spell_center


func _get_local_player() -> Node:
	for player in get_tree().get_nodes_in_group("player"):
		if is_instance_valid(player) and player.is_multiplayer_authority():
			return player
	return null


func _is_valid_target_part(part: BodyPart) -> bool:
	if not is_instance_valid(part) or not part.is_inside_tree():
		return false
	if not part.visible:
		return false
	if part.owner_id == local_player_id and local_player_id > 0:
		return false
	if part.is_carried or part.is_collected:
		return false
	# Verify against GameManager if part was already sacrificed
	if GameManager != null and part.owner_id > 0 and GameManager.players.has(part.owner_id):
		if not GameManager.is_part_valid(part.owner_id, part.part_type):
			return false
	return true


func _find_nearest_valid_body_part(player: Node) -> Node:
	var nearest: Node = null
	var nearest_dist_sq: float = INF
	var player_pos: Vector3 = (player as Node3D).global_position

	# Primary lookup: body_parts group (works reliably across host & replicated clients)
	for node in get_tree().get_nodes_in_group("body_parts"):
		if not (node is BodyPart):
			continue
		var part := node as BodyPart
		if not _is_valid_target_part(part):
			continue
		var dist_sq := player_pos.distance_squared_to(part.global_position)
		if dist_sq < nearest_dist_sq:
			nearest_dist_sq = dist_sq
			nearest = part

	# Fallback scan: direct WorldObjects children in case a part was spawned without group
	if nearest == null and is_instance_valid(world_objects):
		for child in world_objects.get_children():
			if not (child is BodyPart):
				continue
			var part := child as BodyPart
			if not _is_valid_target_part(part):
				continue
			var dist_sq := player_pos.distance_squared_to(part.global_position)
			if dist_sq < nearest_dist_sq:
				nearest_dist_sq = dist_sq
				nearest = part

	return nearest


func _update_compass(player: Node, target: Node, delta: float) -> void:
	var camera = player.camera
	if not is_instance_valid(camera):
		return

	var to_target: Vector3 = (target as Node3D).global_position - camera.global_position
	var forward: Vector3 = -camera.global_transform.basis.z

	to_target.y = 0.0
	forward.y = 0.0

	if to_target.length_squared() < 0.0001 or forward.length_squared() < 0.0001:
		return

	to_target = to_target.normalized()
	forward = forward.normalized()

	var target_angle := atan2(to_target.x, to_target.z)
	var forward_angle := atan2(forward.x, forward.z)
	var angle_diff := forward_angle - target_angle
	angle_diff = fmod(angle_diff + PI, 2.0 * PI) - PI

	if not _has_angle:
		_current_angle = angle_diff
		_has_angle = true
		_last_angle = _current_angle
		queue_redraw()
	else:
		_current_angle = lerp_angle(_current_angle, angle_diff, clampf(delta * 12.0, 0.0, 1.0))
		if abs(angle_difference(_current_angle, _last_angle)) > _angle_epsilon:
			_last_angle = _current_angle
			queue_redraw()

	var distance: float = (player as Node3D).global_position.distance_to((target as Node3D).global_position)
	var fade_full := ALTAR_FADE_FULL_DISTANCE if _targeting_altar else FADE_FULL_DISTANCE
	var fade_zero := ALTAR_FADE_ZERO_DISTANCE if _targeting_altar else FADE_ZERO_DISTANCE
	var alpha: float = 0.0
	if distance >= fade_full:
		alpha = 1.0
	elif distance <= fade_zero:
		alpha = 0.0
	else:
		# Keep the white arrow clearly visible (>= 0.28) until right on top of the limb
		alpha = lerpf(0.28, 1.0, (distance - fade_zero) / (fade_full - fade_zero))
	modulate.a = alpha


func _draw() -> void:
	var arrow_size := minf(size.x, size.y) * 0.42
	var center := size * 0.5

	var points := PackedVector2Array([
		Vector2(0.0, -arrow_size),
		Vector2(arrow_size * 0.62, arrow_size * 0.7),
		Vector2(0.0, arrow_size * 0.42),
		Vector2(-arrow_size * 0.62, arrow_size * 0.7)
	])

	var cos_a := cos(_current_angle)
	var sin_a := sin(_current_angle)
	for i in range(points.size()):
		var p := points[i]
		points[i] = Vector2(p.x * cos_a - p.y * sin_a, p.x * sin_a + p.y * cos_a) + center

	# Crisp white arrow fill (or crimson for Church Altar)
	draw_colored_polygon(points, _arrow_color)

	# Dark high-contrast outline
	var outline_points := points.duplicate()
	outline_points.push_back(points[0])
	draw_polyline(outline_points, Color(0.0, 0.0, 0.0, 0.78), 2.0, true)

	# Subtle owner-color pip near the base so players retain color info on the white arrow
	if _accent_color.a > 0.05:
		var pip_local := Vector2(0.0, arrow_size * 0.12)
		var pip_pos := Vector2(pip_local.x * cos_a - pip_local.y * sin_a, pip_local.x * sin_a + pip_local.y * cos_a) + center
		draw_circle(pip_pos, 3.4, Color(0.05, 0.05, 0.08, 0.85))
		draw_circle(pip_pos, 2.4, _accent_color)
