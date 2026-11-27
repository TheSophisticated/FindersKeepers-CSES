extends SceneTree

## Reproducible headless baker for the GTA V-style top-down island radar map.
## Run with:
##   godot --headless --path . --script res://tools/bake_minimap.gd

const IMG_SIZE := 512
const WORLD_MIN_X := -640.0
const WORLD_MAX_X := 640.0
const WORLD_MIN_Z := -640.0
const WORLD_MAX_Z := 640.0
const OCEAN_Y := 5.0
const OUTPUT_PATH := "res://Maps/Textures/minimap_island.png"


func _world_to_pixel(wx: float, wz: float) -> Vector2i:
	var u := (wx - WORLD_MIN_X) / (WORLD_MAX_X - WORLD_MIN_X)
	var v := (wz - WORLD_MIN_Z) / (WORLD_MAX_Z - WORLD_MIN_Z)
	return Vector2i(
		clampi(int(round(u * float(IMG_SIZE - 1))), 0, IMG_SIZE - 1),
		clampi(int(round(v * float(IMG_SIZE - 1))), 0, IMG_SIZE - 1)
	)


func _stamp_disc(img: Image, cx: int, cy: int, radius: int, col: Color, alpha: float) -> void:
	var r2 := radius * radius
	for dy in range(-radius, radius + 1):
		var py := cy + dy
		if py < 0 or py >= IMG_SIZE:
			continue
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy > r2:
				continue
			var px := cx + dx
			if px < 0 or px >= IMG_SIZE:
				continue
			var dst := img.get_pixel(px, py)
			img.set_pixel(px, py, dst.lerp(col, alpha))


func _stamp_mesh_footprints(img: Image, root: Node, col: Color, alpha: float, max_half_extent: float = 40.0, min_radius: int = 1, use_discs: bool = false) -> int:
	if root == null:
		return 0
	var count := 0
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is MeshInstance3D:
			var mi := cur as MeshInstance3D
			if mi.visible and mi.mesh != null:
				var wb := mi.global_transform * mi.get_aabb()
				var sx := wb.size.x * 0.5
				var sz := wb.size.z * 0.5
				if sx <= max_half_extent and sz <= max_half_extent and wb.get_center().y >= OCEAN_Y - 2.0:
					var c := wb.get_center()
					var p0 := _world_to_pixel(c.x - sx, c.z - sz)
					var p1 := _world_to_pixel(c.x + sx, c.z + sz)
					var rx := maxi(min_radius, int(round((p1.x - p0.x) * 0.5)))
					var rz := maxi(min_radius, int(round((p1.y - p0.y) * 0.5)))
					var pc := _world_to_pixel(c.x, c.z)
					if use_discs or (rx <= 3 and rz <= 3):
						_stamp_disc(img, pc.x, pc.y, mini(8, maxi(rx, rz)), col, alpha)
					else:
						for py in range(maxi(0, pc.y - rz), mini(IMG_SIZE - 1, pc.y + rz) + 1):
							for px in range(maxi(0, pc.x - rx), mini(IMG_SIZE - 1, pc.x + rx) + 1):
								var dst := img.get_pixel(px, py)
								img.set_pixel(px, py, dst.lerp(col, alpha))
					count += 1
		for ch in cur.get_children():
			stack.append(ch)
	return count


func _init() -> void:
	print("Baking GTA V-style island minimap...")
	var gm_path := "res://Maps/GameMode.scn"
	if not ResourceLoader.exists(gm_path):
		gm_path = "res://Maps/GameMode.tscn"
	var packed := load(gm_path) as PackedScene
	if packed == null:
		push_error("Failed to load GameMode scene")
		quit(1)
		return

	var gm := packed.instantiate()
	get_root().add_child(gm)
	await process_frame
	await process_frame

	var world := gm.find_child("WorldObjects", true, false)
	var terrain := world.find_child("Terrain3D", true, false) if world != null else null
	if terrain == null or terrain.get("data") == null:
		push_error("Could not find Terrain3D data")
		gm.queue_free()
		quit(1)
		return

	var data = terrain.data
	var heights := PackedFloat32Array()
	heights.resize(IMG_SIZE * IMG_SIZE)

	var span_x := WORLD_MAX_X - WORLD_MIN_X
	var span_z := WORLD_MAX_Z - WORLD_MIN_Z
	var max_land_h := 55.0

	for py in range(IMG_SIZE):
		var wz := WORLD_MIN_Z + (float(py) / float(IMG_SIZE - 1)) * span_z
		for px in range(IMG_SIZE):
			var wx := WORLD_MIN_X + (float(px) / float(IMG_SIZE - 1)) * span_x
			var h: float = data.get_height(Vector3(wx, 0.0, wz))
			if is_nan(h):
				h = 0.0
			heights[py * IMG_SIZE + px] = h

	# GTA V tactical dark radar palette
	var col_deep_ocean := Color(0.068, 0.112, 0.165, 1.0)
	var col_mid_ocean := Color(0.095, 0.162, 0.235, 1.0)
	var col_shallow := Color(0.145, 0.245, 0.340, 1.0)
	var col_shore_rim := Color(0.32, 0.44, 0.52, 1.0)
	var col_land_low := Color(0.215, 0.242, 0.248, 1.0)
	var col_land_mid := Color(0.285, 0.312, 0.310, 1.0)
	var col_land_high := Color(0.385, 0.405, 0.395, 1.0)

	var img := Image.create(IMG_SIZE, IMG_SIZE, false, Image.FORMAT_RGBA8)
	var step_world := span_x / float(IMG_SIZE)

	for py in range(IMG_SIZE):
		for px in range(IMG_SIZE):
			var h := heights[py * IMG_SIZE + px]
			var color: Color
			if h < OCEAN_Y:
				var t_depth := clampf(h / OCEAN_Y, 0.0, 1.0)
				if t_depth < 0.55:
					color = col_deep_ocean.lerp(col_mid_ocean, t_depth / 0.55)
				else:
					color = col_mid_ocean.lerp(col_shallow, (t_depth - 0.55) / 0.45)
				# Subtle ocean depth rings
				if h > 1.2 and fmod(h, 1.8) < 0.14:
					color = color.lightened(0.08)
			else:
				var norm_h := clampf((h - OCEAN_Y) / maxf(1.0, max_land_h - OCEAN_Y), 0.0, 1.0)
				if norm_h < 0.5:
					color = col_land_low.lerp(col_land_mid, norm_h * 2.0)
				else:
					color = col_land_mid.lerp(col_land_high, (norm_h - 0.5) * 2.0)

				# Directional NW hillshade
				var hx0 := heights[py * IMG_SIZE + maxi(0, px - 1)]
				var hx1 := heights[py * IMG_SIZE + mini(IMG_SIZE - 1, px + 1)]
				var hz0 := heights[maxi(0, py - 1) * IMG_SIZE + px]
				var hz1 := heights[mini(IMG_SIZE - 1, py + 1) * IMG_SIZE + px]
				var gx := (hx1 - hx0) / (2.0 * step_world)
				var gz := (hz1 - hz0) / (2.0 * step_world)
				var nrm := Vector3(-gx, 1.0, -gz).normalized()
				var light_dir := Vector3(-0.55, 0.70, -0.45).normalized()
				var shade := clampf(nrm.dot(light_dir), 0.0, 1.0)
				color = color * lerpf(0.76, 1.24, shade)

				# Subtle topographic contour lines every 8m
				var rel_h := h - OCEAN_Y
				if rel_h > 2.0 and fmod(rel_h, 8.0) < 0.45:
					color = color.darkened(0.16)

				# Crisp shoreline highlight where land touches ocean
				var near_water := (hx0 < OCEAN_Y or hx1 < OCEAN_Y or hz0 < OCEAN_Y or hz1 < OCEAN_Y)
				if near_water:
					color = color.lerp(col_shore_rim, 0.72)

			color.a = 1.0
			img.set_pixel(px, py, color)

	# Stamp zone footprints from real scene geometry
	var main_map := world.get_node_or_null("main_map")
	var forest_node := main_map.get_node_or_null("Node3D") if main_map != null else null
	var church_node := main_map.get_node_or_null("church") if main_map != null else null
	var grave_node := world.get_node_or_null("grave")
	var ruins_node := world.get_node_or_null("ruins")
	var skull_node := world.get_node_or_null("skull_area")

	var n_forest := _stamp_mesh_footprints(img, forest_node, Color(0.15, 0.28, 0.19), 0.42, 16.0, 2, true)
	var n_skull := _stamp_mesh_footprints(img, skull_node, Color(0.32, 0.18, 0.22), 0.46, 22.0, 2, true)
	var n_grave := _stamp_mesh_footprints(img, grave_node, Color(0.46, 0.49, 0.54), 0.44, 16.0, 1, true)
	var n_ruins := _stamp_mesh_footprints(img, ruins_node, Color(0.58, 0.57, 0.52), 0.60, 24.0, 2, false)
	var n_church := _stamp_mesh_footprints(img, church_node, Color(0.76, 0.72, 0.64), 0.85, 16.0, 2, false)

	# Crisp architectural church footprint centered at SpellCenter (-107.25, 25.07)
	var sc_node := world.get_node_or_null("SpellCenter") as Node3D
	var ch_pos := sc_node.global_position if sc_node != null else Vector3(-107.25, 42.0, 25.07)
	var cp := _world_to_pixel(ch_pos.x, ch_pos.z)
	for py in range(cp.y - 6, cp.y + 7):
		for px in range(cp.x - 9, cp.x + 10):
			if px >= 0 and px < IMG_SIZE and py >= 0 and py < IMG_SIZE:
				var is_border := (px == cp.x - 9 or px == cp.x + 9 or py == cp.y - 6 or py == cp.y + 6)
				img.set_pixel(px, py, Color(0.92, 0.88, 0.78) if is_border else Color(0.68, 0.64, 0.58))

	print("Stamped footprints -> forest:%d skull:%d grave:%d ruins:%d church:%d" % [n_forest, n_skull, n_grave, n_ruins, n_church])

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Maps/Textures"))
	var abs_out := ProjectSettings.globalize_path(OUTPUT_PATH)
	var err := img.save_png(abs_out)
	if err != OK:
		push_error("Failed to save minimap PNG: %d" % err)
		gm.queue_free()
		quit(1)
		return

	print("Saved baked minimap to: ", abs_out)
	gm.queue_free()
	quit(0)
