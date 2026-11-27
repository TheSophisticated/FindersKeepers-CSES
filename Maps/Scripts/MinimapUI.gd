extends Control

## GTA V-style rotating bottom-left tactical minimap radar.
## Renders a pre-baked 512x512 top-down island radar texture with zero extra 3D cameras
## so game FPS stays unaffected. Press [M] to toggle expanded radar zoom.

const MAP_TEXTURE_PATH := "res://Maps/Textures/minimap_island.png"
const WORLD_MIN_X := -640.0
const WORLD_MAX_X := 640.0
const WORLD_MIN_Z := -640.0
const WORLD_MAX_Z := 640.0
const WORLD_SPAN := 1280.0

const NORMAL_SIZE := Vector2(220.0, 148.0)
const EXPANDED_SIZE := Vector2(316.0, 214.0)
const NORMAL_WORLD_RADIUS := 230.0
const EXPANDED_WORLD_RADIUS := 420.0
const UPDATE_INTERVAL := 0.033 # ~30 Hz redraw cadence for smooth radar with minimal overhead

var _map_texture: Texture2D = null
var _expanded: bool = false
var _update_accum: float = 0.0

var _player_world_xz: Vector2 = Vector2(-107.25, 25.07)
var _player_forward_xz: Vector2 = Vector2(0.0, -1.0)
var _altar_world_xz: Vector2 = Vector2(-107.25, 25.07)
var _altar_node: Node3D = null
var _local_player: Node = null
var _has_local_player: bool = false
var _other_players: Array[Dictionary] = []


func _ready() -> void:
	name = "MinimapUI"
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_load_map_texture()
	_apply_layout_size()


func _load_map_texture() -> void:
	if ResourceLoader.exists(MAP_TEXTURE_PATH):
		var loaded = load(MAP_TEXTURE_PATH)
		if loaded is Texture2D:
			_map_texture = loaded
			return
	var abs_path := ProjectSettings.globalize_path(MAP_TEXTURE_PATH)
	if FileAccess.file_exists(abs_path):
		var img := Image.load_from_file(abs_path)
		if img != null and not img.is_empty():
			_map_texture = ImageTexture.create_from_image(img)


func _apply_layout_size() -> void:
	var target_size := EXPANDED_SIZE if _expanded else NORMAL_SIZE
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = 20.0
	offset_bottom = -20.0
	offset_right = 20.0 + target_size.x
	offset_top = -20.0 - target_size.y
	queue_redraw()


func toggle_zoom() -> void:
	_expanded = not _expanded
	_apply_layout_size()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_M:
		var focus_owner := get_viewport().gui_get_focus_owner()
		if focus_owner is LineEdit or focus_owner is TextEdit:
			return
		toggle_zoom()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return
	_update_accum += delta
	if _update_accum < UPDATE_INTERVAL:
		return
	_update_accum = 0.0

	_refresh_local_player()
	_refresh_altar_position()
	_sample_radar_entities()
	queue_redraw()


func _refresh_local_player() -> void:
	if not is_instance_valid(_local_player):
		_local_player = null
		for p in get_tree().get_nodes_in_group("player"):
			if is_instance_valid(p) and p.is_multiplayer_authority():
				_local_player = p
				break

	if is_instance_valid(_local_player):
		_has_local_player = true
		var pos: Vector3 = (_local_player as Node3D).global_position
		_player_world_xz = Vector2(pos.x, pos.z)
		var cam: Node3D = _local_player.get("camera") as Node3D
		var basis: Basis = cam.global_transform.basis if is_instance_valid(cam) else (_local_player as Node3D).global_transform.basis
		var fwd := Vector2(-basis.z.x, -basis.z.z)
		if fwd.length_squared() > 0.0001:
			_player_forward_xz = fwd.normalized()
	else:
		_has_local_player = false


func _refresh_altar_position() -> void:
	if not is_instance_valid(_altar_node):
		var root := get_tree().root if get_tree() else null
		if root != null:
			_altar_node = root.find_child("SpellCenter", true, false) as Node3D
	if is_instance_valid(_altar_node):
		_altar_world_xz = Vector2(_altar_node.global_position.x, _altar_node.global_position.z)


func _sample_radar_entities() -> void:
	_other_players.clear()
	var local_peer_id := multiplayer.get_unique_id() if multiplayer != null and multiplayer.has_multiplayer_peer() else -1
	for p in get_tree().get_nodes_in_group("player"):
		if not is_instance_valid(p) or not (p is Node3D):
			continue
		if p == _local_player or p.is_multiplayer_authority():
			continue
		if not (p as Node3D).visible:
			continue
		var pid: int = int(p.get("player_id")) if p.get("player_id") != null else -1
		if pid == local_peer_id and local_peer_id != -1:
			continue
		var dot_color := Color(0.95, 0.35, 0.35, 1.0)
		if GameManager != null and GameManager.players.has(pid):
			var pdata: Dictionary = GameManager.players[pid]
			if not bool(pdata.get("is_alive", true)):
				continue
			var c_idx := clampi(int(pdata.get("color", 0)), 0, GameManager.PLAYER_COLOR_VALUES.size() - 1)
			dot_color = GameManager.PLAYER_COLOR_VALUES[c_idx].lightened(0.18)
		var pos: Vector3 = (p as Node3D).global_position
		_other_players.append({
			"xz": Vector2(pos.x, pos.z),
			"color": dot_color
		})


func _world_delta_to_radar(world_xz: Vector2, center: Vector2, px_per_meter: float) -> Vector2:
	var d := world_xz - _player_world_xz
	var fx := _player_forward_xz.x
	var fz := _player_forward_xz.y
	# Right = (-fz, fx), Up(Ahead) = (fx, fz) mapped to negative screen Y
	var rx := d.x * (-fz) + d.y * fx
	var ry := -(d.x * fx + d.y * fz)
	return center + Vector2(rx * px_per_meter, ry * px_per_meter)


func _clamp_to_radar_rect(pt: Vector2, margin: float) -> Dictionary:
	var min_x := margin
	var max_x := size.x - margin
	var min_y := margin
	var max_y := size.y - margin
	if pt.x >= min_x and pt.x <= max_x and pt.y >= min_y and pt.y <= max_y:
		return {"pos": pt, "clamped": false}
	var center := size * 0.5
	var dir := pt - center
	var half_w := maxf(1.0, (max_x - min_x) * 0.5)
	var half_h := maxf(1.0, (max_y - min_y) * 0.5)
	var tx := half_w / maxf(absf(dir.x), 0.0001)
	var ty := half_h / maxf(absf(dir.y), 0.0001)
	var t := minf(tx, ty)
	return {"pos": center + dir * t, "clamped": true}


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var center := size * 0.5
	var world_radius := EXPANDED_WORLD_RADIUS if _expanded else NORMAL_WORLD_RADIUS
	var px_per_meter := (minf(size.x, size.y) * 0.5) / world_radius

	# 1. Deep ocean background fill
	draw_rect(rect, Color(0.055, 0.095, 0.145, 0.94), true)

	# 2. Rotating pre-baked island radar texture aligned to player camera yaw
	if _map_texture != null:
		var map_draw_span := WORLD_SPAN * px_per_meter
		var player_u := (_player_world_xz.x - WORLD_MIN_X) / WORLD_SPAN
		var player_v := (_player_world_xz.y - WORLD_MIN_Z) / WORLD_SPAN
		var map_rot := atan2(-_player_forward_xz.x, -_player_forward_xz.y)

		draw_set_transform(center, map_rot, Vector2.ONE)
		var map_top_left := Vector2(-player_u * map_draw_span, -player_v * map_draw_span)
		draw_texture_rect(_map_texture, Rect2(map_top_left, Vector2(map_draw_span, map_draw_span)), false, Color(1.0, 1.0, 1.0, 0.94))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 3. Subtle GTA V radar vignette & grid rings
	draw_arc(center, minf(size.x, size.y) * 0.36, 0.0, TAU, 36, Color(1.0, 1.0, 1.0, 0.07), 1.0, true)

	# 4. Player FOV vision cone (pointing upward from center)
	var cone_len := minf(size.x, size.y) * 0.34
	var cone_half_w := cone_len * 0.58
	var cone_pts := PackedVector2Array([
		center,
		center + Vector2(-cone_half_w, -cone_len),
		center + Vector2(cone_half_w, -cone_len)
	])
	var cone_cols := PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.16),
		Color(1.0, 1.0, 1.0, 0.0),
		Color(1.0, 1.0, 1.0, 0.0)
	])
	draw_polygon(cone_pts, cone_cols)

	# 5. Church Altar landmark icon (cross)
	_draw_church_landmark(center, px_per_meter)

	# 6. Multiplayer other-player circular dots (hook)
	_draw_other_players(center, px_per_meter)

	# 7. Centered white GTA V player chevron
	if _has_local_player:
		var chevron := PackedVector2Array([
			center + Vector2(0.0, -7.5),
			center + Vector2(5.2, 5.2),
			center + Vector2(0.0, 2.2),
			center + Vector2(-5.2, 5.2)
		])
		draw_colored_polygon(chevron, Color(1.0, 1.0, 1.0, 0.98))
		var outline := chevron.duplicate()
		outline.append(chevron[0])
		draw_polyline(outline, Color(0.04, 0.04, 0.06, 0.95), 1.4, true)

	# 8. Rotating North indicator badge on the perimeter
	_draw_north_badge(center)

	# 9. GTA V-style dark outer bezel frame + subtle inner hairline
	draw_rect(rect, Color(0.04, 0.045, 0.06, 0.96), false, 4.0)
	draw_rect(Rect2(Vector2(2.5, 2.5), size - Vector2(5.0, 5.0)), Color(0.72, 0.76, 0.82, 0.38), false, 1.0)

	# 10. Subtle [M] zoom hint tag
	var font := ThemeDB.fallback_font
	if font != null:
		var tag := "[M] WIDE" if _expanded else "[M]"
		draw_string(font, Vector2(size.x - (56.0 if _expanded else 26.0), size.y - 7.0), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.86, 0.88, 0.92, 0.65))


func _draw_church_landmark(center: Vector2, px_per_meter: float) -> void:
	var raw_pt := _world_delta_to_radar(_altar_world_xz, center, px_per_meter)
	var clamped_info := _clamp_to_radar_rect(raw_pt, 10.0)
	var p: Vector2 = clamped_info["pos"]
	var is_clamped: bool = bool(clamped_info["clamped"])
	var alpha := 0.72 if is_clamped else 0.95
	# Dark backing circle + golden-crimson altar cross
	draw_circle(p, 5.8 if not is_clamped else 4.8, Color(0.08, 0.05, 0.06, 0.85 * alpha))
	var cross_col := Color(0.98, 0.82, 0.38, alpha)
	var arm := 3.6 if not is_clamped else 2.8
	draw_line(p + Vector2(0.0, -arm), p + Vector2(0.0, arm), cross_col, 1.8, true)
	draw_line(p + Vector2(-arm * 0.8, -arm * 0.25), p + Vector2(arm * 0.8, -arm * 0.25), cross_col, 1.8, true)


func _draw_north_badge(center: Vector2) -> void:
	var north_world := _player_world_xz + Vector2(0.0, -500.0)
	var raw_n := _world_delta_to_radar(north_world, center, 1.0)
	var clamped := _clamp_to_radar_rect(raw_n, 9.0)
	var np: Vector2 = clamped["pos"]
	draw_circle(np, 6.8, Color(0.07, 0.08, 0.10, 0.92))
	draw_arc(np, 6.8, 0.0, TAU, 18, Color(0.85, 0.88, 0.92, 0.55), 1.0, true)
	var font := ThemeDB.fallback_font
	if font != null:
		draw_string(font, np + Vector2(-3.5, 3.6), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1.0, 1.0, 1.0, 0.95))


func _draw_other_players(center: Vector2, px_per_meter: float) -> void:
	for entry in _other_players:
		var world_xz: Vector2 = entry["xz"]
		var base_col: Color = entry["color"]
		var raw_pt := _world_delta_to_radar(world_xz, center, px_per_meter)
		var clamped_info := _clamp_to_radar_rect(raw_pt, 8.5)
		var pt: Vector2 = clamped_info["pos"]
		var is_clamped: bool = bool(clamped_info["clamped"])

		var dot_r := 3.1 if is_clamped else 4.0
		var ring_r := dot_r + 1.4
		var alpha := 0.78 if is_clamped else 0.98
		var col := Color(base_col.r, base_col.g, base_col.b, alpha)

		# GTA V-style small circular dot with dark contrast outline
		draw_circle(pt, ring_r, Color(0.03, 0.03, 0.05, 0.92 * alpha))
		draw_circle(pt, dot_r, col)
		if not is_clamped:
			draw_circle(pt + Vector2(-0.9, -0.9), 1.0, Color(1.0, 1.0, 1.0, 0.45))
