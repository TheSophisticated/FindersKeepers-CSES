@tool
extends EditorScenePostImport

## ============================================================
## Bakes simplified static collision for imported map geometry.
##
## The source GLB ships no collision. A raw trimesh of every triangle is far
## too heavy to play against, so this decimates vertices onto a grid, drops
## small decor, and merges what remains into spatial chunks.
##
## Tuning lives in Maps/Scripts/collision_baker_settings.tres -- a
## CollisionBakerSettings resource, edited in the Inspector.
## ============================================================

const SETTINGS_PATH: String = "res://Maps/Scripts/collision_baker_settings.tres"


func _post_import(scene: Node) -> Object:
	var cfg := _load_settings()
	if not cfg.enabled:
		return scene

	var chunks: Dictionary = {}
	var meshes := 0
	var tris_in := 0
	var tris_out := 0

	for mi in _collect_meshes(scene):
		if mi.mesh == null or _is_skipped(mi.name, cfg.skip_name_patterns):
			continue

		var raw := _world_triangles(mi, scene)
		if raw.is_empty():
			continue

		var bounds := _bounds(raw)
		if bounds.size.length() < cfg.min_extent:
			continue

		tris_in += raw.size() / 3
		var tris := _decimate(raw, _cell_for(bounds, raw.size() / 3, cfg))
		# Too lossy to be a faithful stand-in -- keep the original rather than
		# leave a hole where a wall used to be.
		if float(tris.size()) < float(raw.size()) * (1.0 - cfg.max_tri_loss):
			tris = raw
		if tris.is_empty():
			continue

		meshes += 1
		tris_out += tris.size() / 3
		_merge_into(chunks, bounds, tris, cfg.chunk_size)

	for key: Vector3i in chunks:
		var tris: PackedVector3Array = chunks[key]
		_add_chunk_body(scene, key, tris, cfg)

	if cfg.verbose:
		print_rich("[CollisionBaker] %s: %d meshes, %d -> %d tris (%.1f%%), %d bodies" % [
			scene.name, meshes, tris_in, tris_out,
			100.0 * float(tris_out) / maxf(float(tris_in), 1.0), chunks.size()])
	return scene


## ===== SETTINGS =====

func _load_settings() -> CollisionBakerSettings:
	if ResourceLoader.exists(SETTINGS_PATH):
		var res: Resource = load(SETTINGS_PATH)
		if res is CollisionBakerSettings:
			return res as CollisionBakerSettings
		push_error("[CollisionBaker] %s is not a CollisionBakerSettings -- using defaults." % SETTINGS_PATH)
	else:
		push_warning("[CollisionBaker] %s not found -- using defaults. Create one: FileSystem dock, right-click Maps/Scripts, New > Resource > CollisionBakerSettings." % SETTINGS_PATH)
	return CollisionBakerSettings.new()


## ===== COLLECTION =====

## Depth-first collect of every MeshInstance3D under `scene`.
func _collect_meshes(scene: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var stack: Array[Node] = [scene]
	while not stack.is_empty():
		var node : Node = stack.pop_back()
		for child in node.get_children():
			if child is MeshInstance3D:
				out.append(child)
			stack.append(child)
	return out


func _is_skipped(node_name: String, patterns: PackedStringArray) -> bool:
	var lower := node_name.to_lower()
	for pattern in patterns:
		if lower.contains(pattern.to_lower()):
			return true
	return false


## ===== GEOMETRY =====

## Scene-relative transform. global_transform is unreliable during import
## because the scene is not in the tree yet.
func _relative_transform(node: Node3D, root: Node) -> Transform3D:
	var xf := node.transform
	var parent := node.get_parent()
	while parent != null and parent != root:
		xf = (parent as Node3D).transform * xf
		parent = parent.get_parent()
	return xf


## Mesh.get_faces() already returns flat triangle vertices in mesh-local space,
## which is the exact layout ConcavePolygonShape3D.set_faces() wants.
func _world_triangles(mi: MeshInstance3D, root: Node) -> PackedVector3Array:
	var xf := _relative_transform(mi, root)
	var src := mi.mesh.get_faces()
	var out := PackedVector3Array()
	out.resize(src.size())
	for i in src.size():
		out[i] = xf * src[i]
	return out


func _bounds(tris: PackedVector3Array) -> AABB:
	var out := AABB(tris[0], Vector3.ZERO)
	for i in range(1, tris.size()):
		out = out.expand(tris[i])
	return out


## Picks a grid cell for one mesh. Two rules keep surfaces intact:
##
##  - cheap meshes pass through untouched, so nothing is degraded for no gain;
##  - the cell never exceeds half the mesh's thinnest dimension. A slab
##    thinner than one cell would quantise its two faces onto the same grid
##    plane, every triangle would collapse, and the surface would be deleted.
func _cell_for(bounds: AABB, tri_count: int, cfg: CollisionBakerSettings) -> float:
	if tri_count <= cfg.pass_through_tris:
		return 0.0
	var thinnest := minf(bounds.size.x, minf(bounds.size.y, bounds.size.z))
	return clampf(thinnest * 0.5, cfg.min_cell, cfg.decimate_cell)


## Vertex-clustering decimation: snap every vertex onto a `cell`-sized grid,
## merge the ones landing together, then discard triangles that collapsed.
## It never invents geometry, only removes it -- what a collision proxy wants.
func _decimate(tris: PackedVector3Array, cell: float) -> PackedVector3Array:
	if cell <= 0.0:
		return tris

	var inv := 1.0 / cell
	var index_of: Dictionary = {}   # Vector3i cell -> index into `pos`
	var pos: Array[Vector3] = []
	var out := PackedVector3Array()

	for i in range(0, tris.size(), 3):
		var tri: Array[Vector3] = []
		for k in 3:
			var v: Vector3 = tris[i + k]
			var c := Vector3i(floor(v.x * inv), floor(v.y * inv), floor(v.z * inv))
			var idx: int = index_of[c] if index_of.has(c) else -1
			if idx < 0:
				idx = pos.size()
				index_of[c] = idx
				pos.append(v)
			tri.append(pos[idx])
		# Skip triangles that decayed into a point or an edge.
		if tri[0] == tri[1] or tri[1] == tri[2] or tri[0] == tri[2]:
			continue
		out.append(tri[0])
		out.append(tri[1])
		out.append(tri[2])
	return out


## ===== OUTPUT =====

## Buckets triangles into a coarse grid so each physics body covers one region.
func _merge_into(chunks: Dictionary, bounds: AABB, tris: PackedVector3Array, chunk_size: float) -> void:
	var c := bounds.get_center()
	var key := Vector3i(
		floor(c.x / chunk_size),
		floor(c.y / chunk_size),
		floor(c.z / chunk_size))
	var merged: PackedVector3Array = chunks[key] if chunks.has(key) else PackedVector3Array()
	merged.append_array(tris)
	chunks[key] = merged


## Vertices are already in scene space, so the body sits at the origin with an
## identity transform rather than being parented under a mesh.
func _add_chunk_body(root: Node, key: Vector3i, tris: PackedVector3Array, cfg: CollisionBakerSettings) -> void:
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(tris)
	shape.backface_collision = cfg.backface_collision

	var body := StaticBody3D.new()
	body.name = "Collision_%d_%d_%d" % [key.x, key.y, key.z]
	body.collision_layer = cfg.collision_layer
	body.collision_mask = 0  # static geometry is only collided against
	root.add_child(body)
	body.owner = root

	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	cs.owner = root
