class_name TarotPickup
extends Area3D

@export var card:TarotCard

signal collected(pickup : TarotPickup)

const CARD_SIZE := Vector2(0.62, 0.92)
const CARD_FACE_SHADER: Shader = preload("res://Tarot/Scripts/TarotCardFace.gdshader")
var _terrain: Terrain3D
var _frame_material: StandardMaterial3D = null
var _glow_phase: float = 0.0

func _ready() -> void:
	_glow_phase = randf() * TAU
	_build_card_visual()
	var physics_body := get_parent() as RigidBody3D
	if physics_body != null:
		# A slight wobble makes the thin card land naturally instead of
		# balancing on its edge when it spawns perfectly upright.
		physics_body.angular_velocity = Vector3(0.7, 0.4, 0.55)

func _physics_process(_delta: float) -> void:
	var physics_body := get_parent() as RigidBody3D
	if physics_body == null or physics_body.freeze:
		return

	if not is_instance_valid(_terrain):
		_terrain = get_tree().root.find_child("Terrain3D", true, false) as Terrain3D
	if _terrain == null or _terrain.data == null:
		return

	var ground_height: float = _terrain.data.get_height(physics_body.global_position)
	if is_nan(ground_height) or physics_body.global_position.y > ground_height + 0.06:
		return

	# Terrain3D's rendered height map can extend beyond its generated physics
	# colliders. Stop the card at the sampled surface so it cannot fall beneath
	# the playable map; leave the artwork face up and easy to spot.
	var landed_position := physics_body.global_position
	landed_position.y = ground_height + 0.045
	physics_body.global_position = landed_position
	physics_body.linear_velocity = Vector3.ZERO
	physics_body.angular_velocity = Vector3.ZERO
	physics_body.global_rotation = Vector3(-PI / 2.0, physics_body.global_rotation.y, 0.0)
	physics_body.freeze = true

func _build_card_visual() -> void:
	var old_visual := get_node_or_null("MeshInstance3D")
	if old_visual != null:
		old_visual.visible = false

	var frame := MeshInstance3D.new()
	frame.name = "CardFrame"
	var frame_mesh := BoxMesh.new()
	frame_mesh.size = Vector3(CARD_SIZE.x, CARD_SIZE.y, 0.035)
	frame.mesh = frame_mesh
	var frame_material := StandardMaterial3D.new()
	frame_material.albedo_color = Color("21151e")
	frame_material.metallic = 0.35
	frame_material.roughness = 0.42
	frame_material.emission_enabled = true
	frame_material.emission = Color("8c4fd9")
	frame_material.emission_energy_multiplier = 0.45
	_frame_material = frame_material
	frame.material_override = frame_material
	add_child(frame)

	var front := MeshInstance3D.new()
	front.name = "CardFront"
	var front_mesh := QuadMesh.new()
	front_mesh.size = CARD_SIZE - Vector2(0.045, 0.045)
	front.mesh = front_mesh
	front.position.z = 0.019
	front.material_override = _card_material(card.art if card != null else null, Color("392234"))
	add_child(front)

	var back := MeshInstance3D.new()
	back.name = "CardBack"
	var back_mesh := QuadMesh.new()
	back_mesh.size = front_mesh.size
	back.mesh = back_mesh
	back.position.z = -0.019
	back.rotation.y = PI
	back.material_override = _card_material(load("res://Models/dependencies/Tarot/back.png"), Color("392234"))
	add_child(back)

func _card_material(texture: Texture2D, fallback: Color) -> Material:
	if texture != null:
		var material := ShaderMaterial.new()
		material.shader = CARD_FACE_SHADER
		material.set_shader_parameter("card_texture", texture)
		return material

	var material := StandardMaterial3D.new()
	material.albedo_color = fallback
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material

@rpc("any_peer", "call_local", "reliable")
func collect(playerPath : NodePath)->bool:
	var player = get_node_or_null(playerPath)
	if card == null:
		push_warning("TarotPickup: No Tarot Card assigned")
		return false
	
	if player == null:
		push_warning("TarotPickup: received a null player")
		return false
	
	if not player.has_method("add_tarot_card"):
		push_warning("Player cannot receive Tarot cards.")
		return false
	
	var added: bool = player.add_tarot_card(card)
	if not added:
		return false
	collected.emit(self)
	var pickup_root: Node = self
	if get_parent() is RigidBody3D:
		pickup_root = get_parent()
	pickup_root.queue_free()
	return true

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if _frame_material != null:
		_glow_phase += delta * 2.2
		_frame_material.emission_energy_multiplier = 0.32 + 0.38 * (0.5 + 0.5 * sin(_glow_phase))
