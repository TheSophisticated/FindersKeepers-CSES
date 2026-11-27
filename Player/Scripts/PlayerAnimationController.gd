# PlayerAnimationController.gd
# Dynamically loads character models and applies external animation FBX files.
# Supports avatar choosing by loading different character models.
# Handles bone name remapping from Mixamo animation rigs to the character skeleton.

extends Node

const PlayerCustomization = preload("res://Models/characters/PlayerCustomization.gd")

const ANIM_SCENES: Dictionary = {
	"run": "res://Animations/Running.fbx",
	"walk": "res://Animations/Walking.fbx",
	"walk_back": "res://Animations/Walking Backwards.fbx",
	"strafe_left": "res://Animations/Left Strafe Walking.fbx",
	"strafe_right": "res://Animations/Right Strafe Walking.fbx",
	"jump_in_place": "res://Animations/Jump.fbx",
	"jump_back": "res://Animations/Jump Backward.fbx",
	"injured_walk": "res://Animations/Injured Walk.fbx",
	"injured_walk_back": "res://Animations/Injured Walk Backwards.fbx",
	"crouch_walk": "res://Animations/Crouched Walking.fbx",
	"idle": "res://Animations/Idle.fbx",
}

const DEFAULT_LIBRARY_KEY = &""
const ANIM_BONE_PREFIX = "mixamorig2_"
const TARGET_BONE_PREFIX = "mixamorig_"

var animation_player: AnimationPlayer = null
var skeleton: Skeleton3D = null
var character_node: Node3D = null
var anim_library: AnimationLibrary = null
@export var character_catalog: CharacterCatalog
@export var default_character_id: StringName = &"player_1"
var current_character: CharacterDefinition
var player_node: Node3D
var skin_tone: String = "default"
var hair_style: String = "default"


func setup(player_node: Node3D) -> void:
	self.player_node = player_node
	var definition := character_catalog.get_character(default_character_id) if character_catalog != null else null
	if definition == null:
		push_error("Character definition '%s' is missing from the character catalog" % default_character_id)
		return
	current_character = definition
	if not load_character_model(player_node, definition):
		return
	_setup_animation_player()
	_load_all_animations()
	print("PlayerAnimationController: setup complete. Animations: ", anim_library.get_animation_list() if anim_library != null else "none")


func load_character_model(player_node: Node3D, definition: CharacterDefinition) -> bool:
	if character_node != null:
		character_node.queue_free()

	var packed_model := definition.get_model_scene() if definition != null else null
	if packed_model == null:
		push_error("Character definition does not have a model scene")
		return false

	character_node = packed_model.instantiate()
	character_node.name = "CharacterModel"
	character_node.position.y += definition.vertical_offset
	character_node.scale = definition.model_scale
	player_node.add_child(character_node)

	character_node.rotation = Vector3(0, PI, 0)
	PlayerCustomization.apply_to_character(character_node, skin_tone, hair_style)

	skeleton = _find_skeleton(character_node)
	if skeleton == null:
		push_error("No Skeleton3D found in character model '%s'" % definition.display_name)
		return false

	print("PlayerAnimationController: Loaded skeleton '%s' (%d bones)" % [skeleton.get_name(), skeleton.get_bone_count()])
	return true


## Switch to a catalog entry by definition or stable character ID.
func set_character_definition(definition: CharacterDefinition) -> bool:
	if definition == null:
		return false
	current_character = definition
	default_character_id = definition.character_id
	if player_node == null:
		return true
	if not load_character_model(player_node, definition):
		return false
	_setup_animation_player()
	_load_all_animations()
	play_state(&"idle")
	return true


func set_character_by_id(character_id: StringName) -> bool:
	if character_catalog == null:
		push_warning("Cannot select a character without a CharacterCatalog")
		return false
	var definition := character_catalog.get_character(character_id)
	if definition == null:
		push_warning("Character '%s' was not found in the catalog" % character_id)
		return false
	return set_character_definition(definition)

func set_customization(new_skin_tone: String, new_hair_style: String) -> void:
	skin_tone = PlayerCustomization.sanitize_skin_id(new_skin_tone)
	hair_style = PlayerCustomization.sanitize_hair_id(new_hair_style)
	if is_instance_valid(character_node):
		PlayerCustomization.apply_to_character(character_node, skin_tone, hair_style)


## Backward-compatible path setter for callers that still supply an FBX path.
func set_character_scene(scene_path: String) -> void:
	var packed_scene := load(scene_path) as PackedScene
	if packed_scene == null:
		push_error("Failed to load character scene: %s" % scene_path)
		return
	var definition := CharacterDefinition.new()
	definition.character_id = &"custom"
	definition.display_name = scene_path.get_file().get_basename()
	definition.model_scene = packed_scene
	if current_character != null:
		definition.vertical_offset = current_character.vertical_offset
		definition.model_scale = current_character.model_scale
	set_character_definition(definition)


func _setup_animation_player() -> void:
	# Create a new AnimationPlayer for clean setup
	if animation_player != null and is_instance_valid(animation_player):
		animation_player.queue_free()
	animation_player = AnimationPlayer.new()
	animation_player.name = "RuntimeAnimationPlayer"

	var parent = skeleton.get_parent()
	if parent != null:
		parent.add_child(animation_player)
	else:
		character_node.add_child(animation_player)

	# Set root_node to skeleton so bone tracks resolve
	# AnimationMixer paths are relative to the AnimationPlayer itself. It is
	# a sibling of the Skeleton3D, so this path must include the parent hop.
	var root_path = animation_player.get_path_to(skeleton)
	_set_root_node(root_path)

	# Ensure AnimationPlayer processes during physics frames
	if animation_player.has_method("set_playback_process_mode"):
		animation_player.call("set_playback_process_mode", 0)
	elif animation_player.has_method("set_process_callback"):
		animation_player.call("set_process_callback", 0)


static var _raw_anim_cache: Dictionary = {}
static var _remapped_lib_cache: Dictionary = {}
var _last_synced_anim: String = ""

func _get_library_cache_key() -> StringName:
	if current_character != null and current_character.character_id != &"" and current_character.character_id != &"custom":
		return current_character.character_id
	return &""

func _load_all_animations() -> void:
	var cache_key := _get_library_cache_key()
	if cache_key != &"" and _remapped_lib_cache.has(cache_key):
		anim_library = _remapped_lib_cache[cache_key]
		if animation_player != null:
			var cached_err := animation_player.add_animation_library(DEFAULT_LIBRARY_KEY, anim_library)
			if cached_err != OK:
				push_error("Failed to attach cached AnimationLibrary: %s" % cached_err)
		_last_synced_anim = ""
		return

	anim_library = AnimationLibrary.new()
	for anim_name in ANIM_SCENES:
		_load_animation(anim_name, ANIM_SCENES[anim_name])
	if cache_key != &"":
		_remapped_lib_cache[cache_key] = anim_library
	if animation_player != null:
		var lib_err := animation_player.add_animation_library(DEFAULT_LIBRARY_KEY, anim_library)
		if lib_err != OK:
			push_error("Failed to add AnimationLibrary: %s" % lib_err)
	_last_synced_anim = ""


func _load_animation(anim_name: String, scene_path: String) -> void:
	var source_anim: Animation = _raw_anim_cache.get(scene_path, null)
	if source_anim == null:
		var scene = load(scene_path)
		if scene == null:
			push_warning("Failed to load animation scene: %s" % scene_path)
			return

		var source_root = scene.instantiate()
		var source_player = _find_animation_player(source_root)
		if source_player == null:
			push_warning("No AnimationPlayer in: %s" % scene_path)
			source_root.queue_free()
			return

		var source_lib = source_player.get_animation_library(DEFAULT_LIBRARY_KEY)
		var anim_names = []

		# Try AnimationLibrary first
		if source_lib != null:
			anim_names = source_lib.get_animation_list()
			if anim_names.size() > 0:
				source_anim = source_lib.get_animation(anim_names[0])

		# Fallback: try AnimationPlayer's own methods
		if source_anim == null:
			anim_names = source_player.get_animation_list()
			if anim_names.size() > 0:
				source_anim = source_player.get_animation(anim_names[0])

		if source_anim == null or source_anim.get_track_count() == 0:
			push_warning("No valid animations found in: %s" % scene_path)
			source_root.queue_free()
			return

		source_anim = source_anim.duplicate(true) as Animation
		_raw_anim_cache[scene_path] = source_anim
		source_root.queue_free()

	var remapped_anim = _remap_animation(source_anim)
	# These movement clips need to repeat while their state remains active.
	# The FBX clips were exported without looping, so set looping on the copies
	# used by the controller. Jump clips remain one-shots.
	if anim_name in ["idle", "walk", "walk_back", "strafe_left", "strafe_right", "run", "crouch_walk", "injured_walk", "injured_walk_back"]:
		remapped_anim.loop_mode = Animation.LOOP_LINEAR
	var err = anim_library.add_animation(anim_name, remapped_anim)
	if err != OK:
		push_warning("Failed to add animation '%s': %s" % [anim_name, err])
	_last_synced_anim = ""


func _remap_animation(source_anim: Animation) -> Animation:
	# Keep imported interpolation, update modes, transitions, and other track
	# metadata intact; only the target paths need to change for this skeleton.
	var new_anim := source_anim.duplicate(true) as Animation
	for track_idx in new_anim.get_track_count():
		new_anim.track_set_path(track_idx, NodePath(_remap_track_path(String(new_anim.track_get_path(track_idx)))))
	return new_anim


func _remap_track_path(original_path: String) -> String:
	# FBX tracks point through the source rig (for example
	# Skeleton3D:mixamorig2_Hips). The destination AnimationPlayer
	# roots at the target Skeleton3D. Character FBXs use several different
	# Mixamo prefixes, so resolve the bone by its suffix in this skeleton.
	var colon_index := original_path.find(":")
	if colon_index < 0:
		return original_path
	var bone_name := original_path.substr(colon_index + 1)
	var separator_index := bone_name.find("_")
	if bone_name.begins_with("mixamorig") and separator_index >= 0:
		var bone_suffix := bone_name.substr(separator_index + 1)
		if skeleton != null:
			var standard_name := TARGET_BONE_PREFIX + bone_suffix
			if skeleton.find_bone(standard_name) >= 0:
				return ":" + standard_name
			for bone_index in skeleton.get_bone_count():
				var target_bone := String(skeleton.get_bone_name(bone_index))
				if target_bone.ends_with("_" + bone_suffix):
					return ":" + target_bone
		bone_name = TARGET_BONE_PREFIX + bone_suffix
	return ":" + bone_name


func _set_root_node(path: NodePath) -> void:
	if animation_player == null:
		return
	print("PlayerAnimationController: Setting root to path=", path)
	# Godot 4.7 exposes this as AnimationMixer.root_node. The old set_root()
	# method still exists for compatibility, but root is not a property.
	animation_player.root_node = path
	print("PlayerAnimationController: root_node verify = ", animation_player.root_node)


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var result = _find_animation_player(child)
		if result != null:
			return result
	return null


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var result = _find_skeleton(child)
		if result != null:
			return result
	return null

@rpc("any_peer", "call_local", "reliable")
func _play_animation(name: String) -> void:
	if animation_player == null:
		return
	if anim_library == null or not anim_library.has_animation(name):
		return
	if animation_player.current_animation != name or not animation_player.is_playing():
		animation_player.play(name)


## Public playback API for local or remote state drivers. This controller does
## not read input or network state; callers select a clip by its key in ANIM_SCENES.
func play_state(animation_state: StringName) -> void:
	var target := String(animation_state)
	if target.is_empty():
		return
	# Deduplicate: avoid flooding the network with reliable RPCs every physics frame
	# when the player is already playing the requested animation.
	if target == _last_synced_anim and animation_player != null and animation_player.current_animation == target and animation_player.is_playing():
		return
	_last_synced_anim = target
	if multiplayer != null and multiplayer.has_multiplayer_peer():
		_play_animation.rpc(target)
	else:
		_play_animation(target)


func play_locomotion(animation_name: StringName) -> void:
	play_state(animation_name)


func play_walk() -> void:
	play_state(&"walk")

func play_walk_back() -> void:
	play_state(&"walk_back")

func play_crouch_walk() -> void:
	play_state(&"crouch_walk")

func play_sprint() -> void:
	play_state(&"run")

func play_idle() -> void:
	play_state(&"idle")

func play_jump(jump_animation: StringName = &"jump_in_place") -> void:
	play_state(jump_animation)

func play_fall() -> void:
	# No fall clip is present yet; keep a valid looping pose while airborne.
	play_idle()

func is_jump_animation_playing() -> bool:
	return animation_player != null and animation_player.is_playing() and String(animation_player.current_animation).begins_with("jump_")

func stop_animations() -> void:
	if animation_player != null:
		animation_player.stop()
