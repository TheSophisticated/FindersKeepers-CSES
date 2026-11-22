extends Node
## Reproducible scene optimizer for Maps/GameMode.tscn -> binary Maps/GameMode.scn.
##
## Run via scene so all project autoloads (Settings, GameManager, NetworkManager, AudioManager)
## are loaded and all scripts/exported properties on GameMode.tscn pack cleanly:
##   Pass 1: godot --headless --path . res://tools/optimize_gamemode_runner.tscn -- --extract-only
##   Import: godot --headless --path . --import
##   Pass 2: godot --headless --path . res://tools/optimize_gamemode_runner.tscn

const SRC_SCENE := "res://Maps/GameMode.tscn"
const DST_SCENE := "res://Maps/GameMode.scn"
const TEX_DIR := "res://Maps/extracted_textures"

var _tex_hash_to_path: Dictionary = {} # hash_key -> res://Maps/extracted_textures/embedded_XX.png
var _tex_counter: int = 0
var _replaced_tex_count: int = 0
var _extract_only: bool = false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--extract-only":
			_extract_only = true

	var t0 := Time.get_ticks_msec()
	print("[OptimizeGameMode] Loading %s (extract_only=%s)..." % [SRC_SCENE, str(_extract_only)])
	var packed := load(SRC_SCENE) as PackedScene
	if packed == null:
		push_error("[OptimizeGameMode] Failed to load " + SRC_SCENE)
		get_tree().quit(1)
		return
	print("[OptimizeGameMode] Loaded source PackedScene in %d ms" % (Time.get_ticks_msec() - t0))

	var root := packed.instantiate()
	var nodes_before := _count_nodes(root)
	print("[OptimizeGameMode] Instantiated root '%s' (%d nodes)" % [root.name, nodes_before])

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEX_DIR))

	# Step 1: Extract or relink embedded ImageTexture sub-resources (~140 MB ASCII)
	_process_embedded_textures(root)
	print("[OptimizeGameMode] Unique embedded images=%d, texture slots relinked=%d" % [_tex_counter, _replaced_tex_count])

	if _extract_only:
		print("[OptimizeGameMode] Pass 1 (--extract-only) complete in %d ms." % (Time.get_ticks_msec() - t0))
		root.free()
		get_tree().quit(0)
		return

	# Step 2: Remove dead/hidden/redundant nodes
	_clean_dead_nodes(root)

	# Step 3: Merge thousands of individual foliage MeshInstance3Ds under skull_area
	_optimize_skull_area(root)

	# Step 4: Disable shadow casting on candle flame meshes
	_optimize_candle_shadows(root)

	var nodes_after := _count_nodes(root)
	print("[OptimizeGameMode] Node count: %d -> %d (removed %d nodes)" % [nodes_before, nodes_after, nodes_before - nodes_after])

	# Sanity-verify critical gameplay scripts & properties survived instantiation
	var tarot_spawner := root.get_node_or_null("TarotCardSpawner")
	var body_spawner := root.get_node_or_null("BodyPartSpawner")
	print("[OptimizeGameMode] Verify: root_script=%s | tarot_pts=%d | body_pts=%d" % [
		str(root.get_script()),
		tarot_spawner.get("spawn_points").size() if tarot_spawner and tarot_spawner.get("spawn_points") != null else -1,
		body_spawner.get("spawn_points").size() if body_spawner and body_spawner.get("spawn_points") != null else -1,
	])

	# Step 5: Pack & save binary GameMode.scn
	var out_packed := PackedScene.new()
	var pack_err := out_packed.pack(root)
	if pack_err != OK:
		push_error("[OptimizeGameMode] PackedScene.pack() failed with error %d" % pack_err)
		root.free()
		get_tree().quit(2)
		return

	var save_err := ResourceSaver.save(out_packed, DST_SCENE, ResourceSaver.FLAG_COMPRESS)
	if save_err != OK:
		push_error("[OptimizeGameMode] ResourceSaver.save() failed with error %d" % save_err)
		root.free()
		get_tree().quit(3)
		return

	print("[OptimizeGameMode] Saved binary scene to %s in %d ms total!" % [DST_SCENE, Time.get_ticks_msec() - t0])
	root.free()
	get_tree().quit(0)


func _count_nodes(node: Node) -> int:
	var total := 1
	for c in node.get_children():
		total += _count_nodes(c)
	return total


func _is_local_node(node: Node, root: Node) -> bool:
	return node == root or (node.owner == root and node.scene_file_path.is_empty())


# ===== STEP 1: EXTRACT / RELINK EMBEDDED IMAGES =====

func _process_embedded_textures(root: Node) -> void:
	var visited_mats: Dictionary = {}
	_walk_for_materials(root, root, visited_mats)


func _walk_for_materials(node: Node, root: Node, visited_mats: Dictionary) -> void:
	if not _is_local_node(node, root):
		return

	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.material_override is BaseMaterial3D:
			_clean_material(mi.material_override, visited_mats)
		if mi.mesh != null:
			for s in range(mi.mesh.get_surface_count()):
				var sm := mi.get_surface_override_material(s)
				if sm is BaseMaterial3D:
					_clean_material(sm, visited_mats)
				var mm := mi.mesh.surface_get_material(s)
				if mm is BaseMaterial3D:
					_clean_material(mm, visited_mats)

	for child in node.get_children():
		_walk_for_materials(child, root, visited_mats)


func _clean_material(mat: BaseMaterial3D, visited_mats: Dictionary) -> void:
	var mid := mat.get_instance_id()
	if visited_mats.has(mid):
		return
	visited_mats[mid] = true

	var tex_slots: Array[BaseMaterial3D.TextureParam] = [
		BaseMaterial3D.TEXTURE_ALBEDO,
		BaseMaterial3D.TEXTURE_METALLIC,
		BaseMaterial3D.TEXTURE_ROUGHNESS,
		BaseMaterial3D.TEXTURE_EMISSION,
		BaseMaterial3D.TEXTURE_NORMAL,
		BaseMaterial3D.TEXTURE_AMBIENT_OCCLUSION,
	]
	for slot in tex_slots:
		var tex := mat.get_texture(slot)
		if tex is ImageTexture and (tex.resource_path.is_empty() or tex.resource_path.contains("::")):
			var img := (tex as ImageTexture).get_image()
			if img == null or img.is_empty():
				continue
			var ext_path := _get_or_save_extracted_texture(img)
			if not _extract_only and not ext_path.is_empty() and ResourceLoader.exists(ext_path):
				var loaded_tex := load(ext_path) as Texture2D
				if loaded_tex != null:
					mat.set_texture(slot, loaded_tex)
					_replaced_tex_count += 1


func _get_or_save_extracted_texture(img: Image) -> String:
	var raw_data := img.get_data()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(raw_data)
	var digest := ctx.finish().hex_encode().substr(0, 16)
	var key := "%dx%d_%d_%s" % [img.get_width(), img.get_height(), img.get_format(), digest]
	if _tex_hash_to_path.has(key):
		return _tex_hash_to_path[key]

	_tex_counter += 1
	var filename := "embedded_%s.png" % digest.substr(0, 12)
	var res_path := TEX_DIR + "/" + filename
	var abs_path := ProjectSettings.globalize_path(res_path)
	if not FileAccess.file_exists(abs_path):
		var save_img := img.duplicate() as Image
		if save_img.is_compressed():
			save_img.decompress()
		save_img.clear_mipmaps()
		var err := save_img.save_png(abs_path)
		if err != OK:
			push_warning("[OptimizeGameMode] Failed to save PNG %s (err=%d)" % [abs_path, err])
			return ""
	_tex_hash_to_path[key] = res_path
	return res_path


# ===== STEP 2: REMOVE DEAD / REDUNDANT NODES =====

func _clean_dead_nodes(root: Node) -> void:
	# 1. Remove hidden OceanTerrain3D (replaced by BoujieOcean; saves 81 region .res + shader)
	var ocean_terrain := root.get_node_or_null("SubViewportContainer/SubViewport/WorldObjects/main_map/OceanTerrain3D")
	if ocean_terrain != null and not ocean_terrain.visible:
		ocean_terrain.get_parent().remove_child(ocean_terrain)
		ocean_terrain.free()
		print("[OptimizeGameMode] Removed hidden OceanTerrain3D")

	# 2. Detach redundant runtime trimesh script from grave/Object_5 (already has baked ConvexPolygonShape3D)
	var grave_obj5 := root.get_node_or_null("SubViewportContainer/SubViewport/WorldObjects/grave/Object_5")
	if grave_obj5 != null and grave_obj5.get_script() != null:
		grave_obj5.set_script(null)
		print("[OptimizeGameMode] Detached redundant object_collision.gd from grave/Object_5")

	# 3. Remove stray root-level Sketchfab_Scene sitting outside SubViewportContainer
	var stray_sketchfab := root.get_node_or_null("Sketchfab_Scene")
	if stray_sketchfab != null:
		stray_sketchfab.get_parent().remove_child(stray_sketchfab)
		stray_sketchfab.free()
		print("[OptimizeGameMode] Removed off-viewport root Sketchfab_Scene")

	# 4. Simplify decorative 50k-tri concave collider on ruins/angel_statue to fitted BoxShape3D
	var angel_statue := root.get_node_or_null("SubViewportContainer/SubViewport/WorldObjects/ruins/angel_statue")
	if angel_statue != null:
		var replaced_angel := 0
		for cs in angel_statue.find_children("*", "CollisionShape3D", true, false):
			var cshape := cs as CollisionShape3D
			if cshape.shape is ConcavePolygonShape3D:
				var faces: PackedVector3Array = (cshape.shape as ConcavePolygonShape3D).get_faces()
				if faces.size() > 3000:
					var aabb := AABB(faces[0], Vector3.ZERO)
					for v in faces:
						aabb = aabb.expand(v)
					var box := BoxShape3D.new()
					box.size = aabb.size
					cshape.shape = box
					cshape.position += aabb.get_center()
					replaced_angel += 1
		if replaced_angel > 0:
			print("[OptimizeGameMode] Simplified %d angel_statue high-poly concave collider(s) to BoxShape3D" % replaced_angel)


# ===== STEP 3: MERGE SKULL_AREA'S 6,471 LEAF/TWIG MESHES BY MATERIAL =====

func _optimize_skull_area(root: Node) -> void:
	for rel_path in [
		"SubViewportContainer/SubViewport/WorldObjects/skull_area/tree",
		"SubViewportContainer/SubViewport/WorldObjects/skull_area/japanese_tree",
	]:
		var container := root.get_node_or_null(rel_path) as Node3D
		if container != null:
			_merge_visual_meshes_under(container, root)


func _merge_visual_meshes_under(container: Node3D, root: Node) -> void:
	# Compute container's inverse global-like transform relative to root so we can merge without adding to tree
	var container_xform := _get_transform_relative_to(container, root)
	var container_inv := container_xform.affine_inverse()

	# Gather all pure visual MeshInstance3Ds and preserve any StaticBody3D / Light3D descendants
	var meshes_to_merge: Array[MeshInstance3D] = []
	var preserved_nodes: Array[Dictionary] = [] # {"node": Node3D, "rel_xform": Transform3D}

	_collect_merge_candidates(container, root, container_inv, meshes_to_merge, preserved_nodes)
	if meshes_to_merge.size() < 20:
		return

	# Group surfaces by material instance ID
	var mat_groups: Dictionary = {} # mat_key -> {"mat": Material, "st": SurfaceTool}
	var merged_surfaces := 0
	for mi in meshes_to_merge:
		if not mi.visible or mi.mesh == null:
			continue
		var mi_xform := container_inv * _get_transform_relative_to(mi, root)
		for surf_idx in range(mi.mesh.get_surface_count()):
			if mi.mesh.surface_get_primitive_type(surf_idx) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var mat := mi.material_override
			if mat == null:
				mat = mi.get_surface_override_material(surf_idx)
			if mat == null:
				mat = mi.mesh.surface_get_material(surf_idx)
			var mat_key := str(mat.get_instance_id()) if mat != null else "null"
			if not mat_groups.has(mat_key):
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				mat_groups[mat_key] = {"mat": mat, "st": st}
			var st: SurfaceTool = mat_groups[mat_key]["st"]
			st.append_from(mi.mesh, surf_idx, mi_xform)
			merged_surfaces += 1

	# Detach preserved physics/light nodes before clearing old hierarchy
	for entry in preserved_nodes:
		var pnode: Node3D = entry["node"]
		_clear_owner_recursive(pnode)
		if pnode.get_parent() != null:
			pnode.get_parent().remove_child(pnode)

	# Free old deep hierarchy under container
	for child in container.get_children():
		container.remove_child(child)
		child.free()

	# Re-attach preserved physics/light nodes directly under container with exact transforms
	var preserved_idx := 0
	for entry in preserved_nodes:
		var pnode: Node3D = entry["node"]
		preserved_idx += 1
		pnode.name = "%s_%d" % [pnode.name, preserved_idx]
		pnode.transform = entry["rel_xform"]
		container.add_child(pnode)
		_set_owner_recursive(pnode, root)

	# Commit each material bucket into a single indexed merged MeshInstance3D
	var bucket_idx := 0
	for mat_key in mat_groups:
		var group: Dictionary = mat_groups[mat_key]
		var st: SurfaceTool = group["st"]
		var mat: Material = group["mat"]
		st.index()
		var arr_mesh := st.commit()
		if arr_mesh == null or arr_mesh.get_surface_count() == 0:
			continue
		if mat != null:
			arr_mesh.surface_set_material(0, mat)
		bucket_idx += 1
		var merged_mi := MeshInstance3D.new()
		merged_mi.name = "MergedFoliage_%d" % bucket_idx
		merged_mi.mesh = arr_mesh
		merged_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		container.add_child(merged_mi)
		merged_mi.owner = root

	print("[OptimizeGameMode] Merged %s: %d MeshInstance3Ds (%d surfaces) -> %d merged meshes (preserved %d physics/light nodes)" % [
		container.name, meshes_to_merge.size(), merged_surfaces, bucket_idx, preserved_nodes.size()
	])


func _collect_merge_candidates(
	node: Node,
	root: Node,
	container_inv: Transform3D,
	out_meshes: Array[MeshInstance3D],
	out_preserved: Array[Dictionary]
) -> void:
	for child in node.get_children():
		if not _is_local_node(child, root):
			continue
		if child is StaticBody3D:
			# Skip empty StaticBody3Ds with zero CollisionShape3D children (e.g. 600+ empty foliage bodies)
			if not child.find_children("*", "CollisionShape3D", true, false).is_empty():
				var rel_xform := container_inv * _get_transform_relative_to(child as Node3D, root)
				out_preserved.append({"node": child as Node3D, "rel_xform": rel_xform})
			continue
		if child is Light3D or child is Area3D or child is AudioStreamPlayer3D:
			var rel_xform := container_inv * _get_transform_relative_to(child as Node3D, root)
			out_preserved.append({"node": child as Node3D, "rel_xform": rel_xform})
			continue
		if child is MeshInstance3D:
			out_meshes.append(child as MeshInstance3D)
		_collect_merge_candidates(child, root, container_inv, out_meshes, out_preserved)


func _get_transform_relative_to(node: Node3D, ancestor: Node) -> Transform3D:
	var xform := Transform3D.IDENTITY
	var cur: Node = node
	while cur != null and cur != ancestor:
		if cur is Node3D:
			xform = (cur as Node3D).transform * xform
		cur = cur.get_parent()
	return xform


func _clear_owner_recursive(node: Node) -> void:
	node.owner = null
	for child in node.get_children():
		if child.scene_file_path.is_empty():
			_clear_owner_recursive(child)


func _set_owner_recursive(node: Node, new_owner: Node) -> void:
	node.owner = new_owner
	for child in node.get_children():
		if child.scene_file_path.is_empty():
			_set_owner_recursive(child, new_owner)


# ===== STEP 4: DISABLE CANDLE SHADOW CASTING =====

func _optimize_candle_shadows(root: Node) -> void:
	var candle_root := root.get_node_or_null("SubViewportContainer/SubViewport/WorldObjects/candle")
	if candle_root == null:
		return
	var disabled := 0
	for mi in candle_root.find_children("*", "MeshInstance3D", true, false):
		if _is_local_node(mi, root):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			disabled += 1
	print("[OptimizeGameMode] Disabled shadow casting on %d local candle meshes" % disabled)
