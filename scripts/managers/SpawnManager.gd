extends Node

enum spawnerType {
	TarotCardSpawner,
	BodyPartSpawner
}

@export var object_scene: PackedScene
@export var object_scenes: Array[PackedScene] = []
@export var spawn_points: Array[Marker3D]
@export var objects_to_spawn = 1
@export var object_spawner_type: spawnerType
@export var super_tarot_scene: PackedScene
@export var tarot_spawn_delay : float = 3.0

@export_group("Procedural Scatter (Tarot spawner only)")
## Scatter tarot cards automatically over the Terrain3D instead of relying only
## on hand-placed Marker3D spawn points.
@export var scatter_enabled: bool = true
## How many scattered cards to place (on top of any manual markers).
@export var scatter_count: int = 40
## Minimum distance (metres) between two cards. Relaxed automatically if the
## map is too small to fit scatter_count cards at this spacing.
@export var scatter_min_spacing: float = 15.0
## Ground below this world Y is ignored. The ocean plane sits at y = 5.
@export var scatter_min_height: float = 7.0
@export var scatter_max_height: float = 10000.0
## Steeper ground than this (degrees) is skipped so cards don't slide away.
@export var scatter_max_slope_deg: float = 30.0
## Skip spots overlapping trees, buildings, the altar, etc.
@export var scatter_avoid_obstacles: bool = true
@export var scatter_obstacle_radius: float = 1.0
## Optional XZ rectangle (world units) to restrict scattering. An empty Rect2
## means "the whole terrain".
@export var scatter_bounds: Rect2 = Rect2()
## 0 = different layout every match. Any other value = reproducible layout.
@export var scatter_seed: int = 0
## Also spawn cards at the manually placed Marker3D points.
@export var scatter_keep_manual_points: bool = true

var spawned_objects: Array[Node] = []
var _manual_points: Array[Marker3D] = []
var _scatter_markers: Array[Marker3D] = []
var _scene_bag: Array[PackedScene] = []
var _tarot_spawn_points: Dictionary = {}
var _spawn_generation: int = 0


func spawn_objects(peer_id: int = -1) -> void:
	clear_objects()

	if object_spawner_type == spawnerType.BodyPartSpawner:
		if spawn_points.is_empty():
			return
		var shuffled_points: Array[Marker3D] = spawn_points.duplicate()
		shuffled_points.shuffle()
		var n := 0
		for pid in GameManager.players.keys():
			for t in 4:
				_spawn_object(
					shuffled_points[n % shuffled_points.size()],
					pid,
					t
				)
				n += 1
		return

	if scatter_enabled:
		_spawn_scattered_tarots()
		return

	var available_scenes: Array[PackedScene] = object_scenes.duplicate()
	available_scenes.shuffle()

	for i in range(spawn_points.size()):
		var scene_to_spawn: PackedScene = object_scene

		if i < available_scenes.size():
			scene_to_spawn = available_scenes[i]

		_spawn_object(spawn_points[i], -1, -1, scene_to_spawn)


func spawn_super_tarot() -> void:
	if not multiplayer.is_server():
		return

	if super_tarot_scene == null:
		push_warning("SpawnManager: Super Tarot scene is not assigned")
		return

	if spawn_points.is_empty():
		push_warning("SpawnManager: No Tarot spawn points available")
		return

	var random_spawn_point: Marker3D = spawn_points.pick_random()

	_spawn_object(
		random_spawn_point,
		-1,
		-1,
		super_tarot_scene
	)
	print("Super Tarot Card was Spawned At: ", random_spawn_point)


# PROCEDURAL SCATTER

func regenerate_scatter() -> void:
	## Throw away the cached layout so the next spawn_objects() builds a new one.
	_clear_scatter_markers()


func _spawn_scattered_tarots() -> void:
	var generation := _spawn_generation
	# Let physics settle one frame so trees/buildings are queryable and the
	# cards freed by clear_objects() are really gone.
	await get_tree().physics_frame
	if generation != _spawn_generation or not is_inside_tree():
		return

	if _scatter_markers.is_empty():
		_generate_scatter_markers()

	var points: Array[Marker3D] = []
	if scatter_keep_manual_points:
		points.append_array(_manual_points)
	points.append_array(_scatter_markers)

	for point in points:
		_spawn_object(point, -1, -1, _next_scatter_scene())
	print("SpawnManager: spawned %d tarot cards (%d scattered)" % [points.size(), _scatter_markers.size()])


func _next_scatter_scene() -> PackedScene:
	# Shuffle-bag so every card type shows up evenly instead of pure randomness.
	if object_scenes.is_empty():
		return object_scene
	if _scene_bag.is_empty():
		_scene_bag.assign(object_scenes)
		_scene_bag.shuffle()
	return _scene_bag.pop_back()


func _clear_scatter_markers() -> void:
	for marker in _scatter_markers:
		spawn_points.erase(marker)
		if is_instance_valid(marker):
			marker.queue_free()
	_scatter_markers.clear()


func _find_world_node() -> Node:
	if has_node("/root/GameMode/SubViewportContainer/SubViewport/WorldObjects"):
		return get_node("/root/GameMode/SubViewportContainer/SubViewport/WorldObjects")
	if get_tree() and get_tree().current_scene:
		var found := get_tree().current_scene.find_child("WorldObjects", true, false)
		if found != null:
			return found
	return get_parent()


func _generate_scatter_markers() -> void:
	var world_node := _find_world_node()
	var terrain := world_node.find_child("Terrain3D", true, false) as Terrain3D
	if terrain == null or terrain.data == null:
		push_warning("SpawnManager: scatter needs a Terrain3D named 'Terrain3D'; using manual points only")
		return

	var bounds := _scatter_area(terrain)
	if not bounds.has_area():
		push_warning("SpawnManager: terrain has no active regions; scatter skipped")
		return

	var rng := RandomNumberGenerator.new()
	if scatter_seed != 0:
		rng.seed = scatter_seed
	else:
		rng.randomize()

	var space: PhysicsDirectSpaceState3D = null
	if scatter_avoid_obstacles:
		var world3d := world_node.get_viewport().find_world_3d()
		if world3d != null:
			space = world3d.direct_space_state

	var accepted: Array[Vector3] = []
	var existing: Array[Vector3] = []
	for m in _manual_points:
		existing.append(m.global_position)

	var spacing := scatter_min_spacing
	var attempts_per_round := maxi(scatter_count, 1) * 80
	# Up to 4 rounds; each one halves the spacing if the previous couldn't fill
	# the quota (small islands, lots of water, etc.).
	for _pass in 4:
		var attempts := 0
		while accepted.size() < scatter_count and attempts < attempts_per_round:
			attempts += 1
			var x := rng.randf_range(bounds.position.x, bounds.end.x)
			var z := rng.randf_range(bounds.position.y, bounds.end.y)
			var h := _valid_ground_height(terrain, x, z)
			if is_nan(h):
				continue
			var candidate := Vector3(x, h, z)
			if not _far_enough(candidate, accepted, spacing) or not _far_enough(candidate, existing, spacing):
				continue
			if space != null and _blocked(space, candidate):
				continue
			accepted.append(candidate)
		if accepted.size() >= scatter_count:
			break
		spacing *= 0.5

	for i in accepted.size():
		var marker := Marker3D.new()
		marker.name = "ScatterSpawn%d" % (i + 1)
		add_child(marker)
		marker.global_position = accepted[i]
		_scatter_markers.append(marker)
		spawn_points.append(marker) # also lets spawn_super_tarot() use them

	if accepted.size() < scatter_count:
		push_warning("SpawnManager: only placed %d/%d scattered cards (area too small or too restrictive)" % [accepted.size(), scatter_count])


func _scatter_area(terrain: Terrain3D) -> Rect2:
	if scatter_bounds.has_area():
		return scatter_bounds

	var region_size: int = 256
	var spacing_v: float = 1.0
	var rs = terrain.get("region_size")
	if rs != null:
		region_size = int(rs)
	var vs = terrain.get("vertex_spacing")
	if vs != null:
		spacing_v = float(vs)
	var span := float(region_size) * spacing_v

	var data := terrain.data
	var locations: Array = []
	if data.has_method("get_region_locations"):
		locations = data.get_region_locations()
	elif data.has_method("get_regions_active"):
		for region in data.get_regions_active():
			locations.append(region.location)
	if locations.is_empty():
		return Rect2()

	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for loc in locations:
		lo.x = minf(lo.x, loc.x)
		lo.y = minf(lo.y, loc.y)
		hi.x = maxf(hi.x, loc.x + 1)
		hi.y = maxf(hi.y, loc.y + 1)
	var origin := Vector2(terrain.global_position.x, terrain.global_position.z)
	return Rect2(origin + lo * span, (hi - lo) * span)


## Returns terrain height at (x, z) if the spot is acceptable, otherwise NAN.
func _valid_ground_height(terrain: Terrain3D, x: float, z: float) -> float:
	var data := terrain.data
	var h: float = data.get_height(Vector3(x, 0.0, z))
	if is_nan(h) or h < scatter_min_height or h > scatter_max_height:
		return NAN

	# Slope from central differences; any NaN neighbour means we're at a region
	# edge or hole, which we don't want anyway.
	var d := 1.5
	var hx0: float = data.get_height(Vector3(x - d, 0.0, z))
	var hx1: float = data.get_height(Vector3(x + d, 0.0, z))
	var hz0: float = data.get_height(Vector3(x, 0.0, z - d))
	var hz1: float = data.get_height(Vector3(x, 0.0, z + d))
	if is_nan(hx0) or is_nan(hx1) or is_nan(hz0) or is_nan(hz1):
		return NAN
	var gx := (hx1 - hx0) / (2.0 * d)
	var gz := (hz1 - hz0) / (2.0 * d)
	if rad_to_deg(atan(sqrt(gx * gx + gz * gz))) > scatter_max_slope_deg:
		return NAN
	return h


func _far_enough(p: Vector3, others: Array[Vector3], min_dist: float) -> bool:
	var min_sq := min_dist * min_dist
	for o in others:
		var dx := p.x - o.x
		var dz := p.z - o.z
		if dx * dx + dz * dz < min_sq:
			return false
	return true


func _blocked(space: PhysicsDirectSpaceState3D, ground: Vector3) -> bool:
	var shape := SphereShape3D.new()
	shape.radius = scatter_obstacle_radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	# Float the sphere clear of the terrain collider so only real obstacles hit.
	query.transform = Transform3D(Basis(), ground + Vector3(0.0, scatter_obstacle_radius + 0.35, 0.0))
	query.collision_mask = 0xFFFFFFFF
	query.collide_with_areas = false
	return not space.intersect_shape(query, 1).is_empty()


func _prepare_replication_limits() -> void:
	# MultiplayerSpawner.spawn_limit (12 in the stock scene) would silently stop
	# extra cards from replicating to clients.
	var needed := scatter_count + _manual_points.size() + 8
	for child in get_children():
		if child is MultiplayerSpawner and child.spawn_limit != 0 and child.spawn_limit < needed:
			child.spawn_limit = needed


func _spawn_object(
	spawn_point: Marker3D,
	owner_id: int = -1,
	part_type: int = -1,
	scene_to_spawn: PackedScene = null
) -> void:
	if spawn_point == null:
		return

	if scene_to_spawn == null:
		scene_to_spawn = object_scene

	if scene_to_spawn == null:
		return

	print("Spawn_Point: ", spawn_point.global_position)

	var object := scene_to_spawn.instantiate()
	object.name = "Object_" + str(spawned_objects.size())

	if owner_id >= 0:
		object.owner_id = owner_id
		object.part_type = part_type

		var c: int = GameManager.players[owner_id]["color"]
		object.part_color = GameManager.PLAYER_COLOR_VALUES[c]

	var world_node: Node = _find_world_node()

	world_node.add_child(object, true)
	var spawn_position := spawn_point.global_position
	if object_spawner_type == spawnerType.TarotCardSpawner:
		var terrain := world_node.find_child("Terrain3D", true, false) as Terrain3D
		if terrain != null and terrain.data != null:
			var ground_height: float = terrain.data.get_height(spawn_position)
			if not is_nan(ground_height):
				# Some tarot markers are embedded below the generated terrain.
				# Start above the actual surface so gravity can settle the card
				# onto the map instead of leaving it underground.
				spawn_position.y = max(spawn_position.y, ground_height + 1.75)
	object.global_position = spawn_position
	spawned_objects.append(object)
	_track_tarot_pickup(object, spawn_point)

func _track_tarot_pickup(spawned_root: Node, spawn_point: Marker3D) -> void:
	if object_spawner_type != spawnerType.TarotCardSpawner:
		return
	
	var pickup := _find_tarot_pickup(spawned_root)
	if pickup == null:
		return
	
	_tarot_spawn_points[pickup] = spawn_point
	pickup.collected.connect(_on_tarot_collected)

func _find_tarot_pickup(spawned_root: Node) -> TarotPickup:
	if spawned_root is TarotPickup:
		return spawned_root
	
	for child in spawned_root.get_children():
		if child is TarotPickup:
			return child
	
	return null

func _on_tarot_collected(pickup: TarotPickup) -> void:
	if not multiplayer.is_server():
		return

	if not _tarot_spawn_points.has(pickup):
		return

	var spawn_point: Marker3D = _tarot_spawn_points[pickup]
	_tarot_spawn_points.erase(pickup)

	get_tree().create_timer(tarot_spawn_delay).timeout.connect(
		_respawn_tarot.bind(spawn_point, pickup.get_parent(), _spawn_generation)
	)

func _respawn_tarot(spawn_point: Marker3D, old_root: Node, generation: int):
	if generation != _spawn_generation:
		return

	if GameManager.current_state == GameManager.MatchState.GAME_OVER:
		return

	if is_instance_valid(old_root):
		old_root.queue_free()

	if not is_instance_valid(spawn_point):
		return

	_spawn_object(spawn_point, -1, -1, _pick_respawn_scene())

func _pick_respawn_scene() -> PackedScene:
	if object_scenes.is_empty():
		return object_scene
	
	return object_scenes.pick_random()

func clear_objects() -> void:
	for object in spawned_objects:
		if is_instance_valid(object):
			object.queue_free()

	spawned_objects.clear()
	_tarot_spawn_points.clear()
	_spawn_generation += 1


func _ready() -> void:
	if object_spawner_type == spawnerType.TarotCardSpawner:
		GameManager.tarot_card_spawner = self
		_manual_points = spawn_points.duplicate()
		if scatter_enabled:
			_prepare_replication_limits()

	if object_spawner_type == spawnerType.BodyPartSpawner:
		GameManager.body_part_spawner = self

	if multiplayer.is_server():
		# Whenever a client connects, call spawn_objects.
		multiplayer.peer_connected.connect(spawn_objects)



func _process(delta: float) -> void:
	pass
