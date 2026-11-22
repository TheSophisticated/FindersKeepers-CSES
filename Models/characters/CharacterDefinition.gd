extends Resource
class_name CharacterDefinition

## Data for one playable character model. Uses lazy path loading so
## CharacterCatalog.tres does not eagerly pull all 8 FBX scenes at boot.
@export var character_id: StringName
@export var display_name: String
@export_file("*.fbx", "*.glb", "*.tscn", "*.scn") var model_scene_path: String = ""
@export var model_scene: PackedScene
@export var vertical_offset: float = -1.1
@export var model_scale: Vector3 = Vector3.ONE

var _cached_model_scene: PackedScene = null


func get_model_scene() -> PackedScene:
	if model_scene != null:
		return model_scene
	if _cached_model_scene == null and not model_scene_path.is_empty():
		_cached_model_scene = load(model_scene_path) as PackedScene
	return _cached_model_scene
