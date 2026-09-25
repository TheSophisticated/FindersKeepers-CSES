extends Node

enum spawnerType{
	TarotCardSpawner,
	BodyPartSpawner
}

@export var object_scene : PackedScene
@export var spawn_points : Array[Marker3D]
@export var objects_to_spawn = 1
@export var object_spawner_type : spawnerType


var spawned_objects : Array[Node] = []

func spawn_objects() -> void:
	if not multiplayer.is_server():
		return
	
	clear_objects()
	for i in range(len(spawn_points)):
		spawn_object(spawn_points[i])

func spawn_object(spawn_point : Marker3D) -> void:
	var object := object_scene.instantiate()
	add_child(object)
	object.global_position = spawn_point.global_position
	spawned_objects.append(object)
	

func clear_objects():
	for object in spawned_objects:
		if is_instance_valid(object):
			object.queue_free()
			
	spawned_objects.clear()

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if object_spawner_type == spawnerType.TarotCardSpawner:
		GameManager.tarot_card_spawner = self
	elif  object_spawner_type == spawnerType.BodyPartSpawner:
		GameManager.body_part_spawner = self


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
