@tool
extends EditorScenePostImport

## ============================================================
## Bakes simplified static collision for imported map geometry.
##
## The source GLB ships no collision. A raw trimesh of every triangle is far
## too heavy to be playable, so this decimates vertices onto a grid, drops
## small props entirely, and merges what remains into spatial chunks to keep
## the physics broadphase small.
## ============================================================

## Layer 1 is this project's "world / floor" layer (see bodypart.gd).
const COLLISION_LAYER: int = 1

## Meshes whose name contains any of these get no collision.
const SKIP_PATTERNS: PackedStringArray = [
	"glass", "canvas", "nor_gl",
]

## Collision vertex snap resolution, in metres. This is the main quality knob:
## bigger cells = far fewer triangles = smoother physics.
##   0.10 = faithful, heavy     0.25 = good default
##   0.40 = cheap              0.75 = blocky, very cheap
const DECIMATE_CELL: float = 0.25

## Meshes whose world AABB is smaller than this on any axis get no collision.
## Most of a hotel kit is decor the player walks past; skipping it is the
## single biggest win available.
const MIN_EXTENT: float = 0.5

## Collision is merged into cubes of this size, so the broadphase gets a
## manageable number of bodies instead of one per mesh.
const CHUNK: float = 12.0


func _post_import(scene: Node) -> Object:
	var chunks: Dictionary = {}
	var meshes := 0
	var tris_in := 0
	var tris_out := 0

	for mi in _collect_meshes(scene):
		if mi.mesh == null or _is_skipped(mi.name):
			continue

		var tris := _world_triangles(mi, scene)
		if tris.is_empty():
			continue

		tris_in += tris.size() / 3
		var bounds := _bounds(tris)
		if bounds.size.length() < MIN_EXTENT:
			continue

		tris = _decimate(tris, DECIMATE_CELL)
		if tris.is_empty():
			continue

		meshes += 1
		tris_out += tris.size() / 3
		_merge_into(chunks, bounds, tris)

	for key: Vector3i in chunks:
		_add_chunk_body(scene, key, chunks[key])

	print_rich("[CollisionBaker] %s: %d meshes, %d -> %d tris (%.0f%%), %d bodies" % [
		scene.name, meshes, tris_in, tris_out,
		100.0 * float(tris_out) / maxf(float(tris_in), 1.0), chunks.size()])
	return scene


## ===== INTERNAL =====

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


func _is_skipped(node_name: String) -> bool:
	var lower := node_name.to_lower()
	for pattern in SKIP_PATTERNS:
		if lower.contains(pattern):
			return true
	return false


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
## which is the same layout ConcavePolygonShape3D.set_faces() wants.
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


## Vertex-clustering decimation: snap every vertex onto a `cell`-sized grid,
## merge the ones that land together, and discard triangles that collapse.
## It never invents geometry, only removes it -- exactly what a collision
## proxy wants.
func _decimate(tris: PackedVector3Array, cell: float) -> PackedVector3Array:
	if cell <= 0.0:
		return tris

	var inv := 1.0 / cell
	var index_of: Dictionary = {}   # Vector3i cell -> index into `pos`
	var keys: Array[Vector3] = []
	var pos: Array[Vector3] = []
	var out := PackedVector3Array()

	for i in range(0, tris.size(), 3):
		var tri: Array[Vector3] = []
		for k in 3:
			var v: Vector3 = tris[i + k]
			var c := Vector3i(floor(v.x * inv), floor(v.y * inv), floor(v.z * inv))
			if not index_of.has(c):
				index_of[c] = pos.size()
				keys.append(c)
				pos.append(v)
			tri.append(pos[index_of[c]])
		# Skip triangles that decayed into a point or an edge.
		if tri[0] == tri[1] or tri[1] == tri[2] or tri[0] == tri[2]:
			continue
		out.append(tri[0])
		out.append(tri[1])
		out.append(tri[2])
	return out


## Buckets triangles into a coarse grid so each physics body covers one region.
func _merge_into(chunks: Dictionary, bounds: AABB, tris: PackedVector3Array) -> void:
	var c := bounds.get_center()
	var key := Vector3i(floor(c.x / CHUNK), floor(c.y / CHUNK), floor(c.z / CHUNK))
	var merged: PackedVector3Array = chunks[key] if chunks.has(key) else PackedVector3Array()
	merged.append_array(tris)
	chunks[key] = merged


## Vertices are already in scene space, so the body sits at the origin with
## an identity transform rather than being parented under a mesh.
func _add_chunk_body(root: Node, key: Vector3i, tris: PackedVector3Array) -> void:
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(tris)
	# Left off deliberately: enabling it duplicates every triangle. Turn it on
	# only if you fall through single-sided geometry.
	shape.backface_collision = false

	var body := StaticBody3D.new()
	body.name = "Collision_%d_%d_%d" % [key.x, key.y, key.z]
	body.collision_layer = COLLISION_LAYER
	body.collision_mask = 0  # static geometry is only collided against
	root.add_child(body)
	body.owner = root

	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	cs.owner = root
