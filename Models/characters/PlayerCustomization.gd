class_name PlayerCustomization
extends RefCounted

## Static preset registry and cached material applier for player skin tone
## and hair customization. Targets only Mixamo skin (Body) and Hair meshes
## so clothing textures remain untouched with zero runtime allocation churn.

const TINT_SHADER_PATH := "res://Materials/character_tint.gdshader"

const SKIN_ORDER: Array[String] = [
	"default",
	"black",
	"caucasian",
	"indian",
	"chinese"
]

const SKIN_PRESETS: Dictionary = {
	"default": {
		"label": "Default",
		"color": Color(0.75, 0.65, 0.58),
		"strength": 0.0
	},
	"black": {
		"label": "Black",
		"color": Color(0.23, 0.14, 0.095),
		"strength": 0.94
	},
	"caucasian": {
		"label": "Caucasian",
		"color": Color(0.93, 0.77, 0.67),
		"strength": 0.90
	},
	"indian": {
		"label": "Indian",
		"color": Color(0.62, 0.41, 0.26),
		"strength": 0.92
	},
	"chinese": {
		"label": "Chinese",
		"color": Color(0.89, 0.76, 0.59),
		"strength": 0.90
	}
}

const HAIR_ORDER: Array[String] = [
	"default",
	"jet_black",
	"dark_brown",
	"blonde",
	"auburn",
	"silver",
	"crimson",
	"bald"
]

const HAIR_PRESETS: Dictionary = {
	"default": {
		"label": "Default",
		"color": Color(0.45, 0.38, 0.32),
		"strength": 0.0,
		"hide_hair": false
	},
	"jet_black": {
		"label": "Jet Black",
		"color": Color(0.07, 0.07, 0.09),
		"strength": 0.95,
		"hide_hair": false
	},
	"dark_brown": {
		"label": "Dark Brown",
		"color": Color(0.24, 0.14, 0.08),
		"strength": 0.92,
		"hide_hair": false
	},
	"blonde": {
		"label": "Blonde",
		"color": Color(0.86, 0.72, 0.36),
		"strength": 0.92,
		"hide_hair": false
	},
	"auburn": {
		"label": "Auburn",
		"color": Color(0.56, 0.19, 0.10),
		"strength": 0.92,
		"hide_hair": false
	},
	"silver": {
		"label": "Silver",
		"color": Color(0.82, 0.85, 0.90),
		"strength": 0.92,
		"hide_hair": false
	},
	"crimson": {
		"label": "Crimson",
		"color": Color(0.58, 0.07, 0.11),
		"strength": 0.92,
		"hide_hair": false
	},
	"bald": {
		"label": "Shaved",
		"color": Color(0.55, 0.52, 0.50),
		"strength": 0.0,
		"hide_hair": true
	}
}

static var _cached_shader: Shader = null
static var _material_cache: Dictionary = {}


static func sanitize_skin_id(skin_id: String) -> String:
	var key := skin_id.strip_edges().to_lower()
	return key if SKIN_PRESETS.has(key) else "default"


static func sanitize_hair_id(hair_id: String) -> String:
	var key := hair_id.strip_edges().to_lower()
	return key if HAIR_PRESETS.has(key) else "default"


static func get_skin_label(skin_id: String) -> String:
	var key := sanitize_skin_id(skin_id)
	return str(SKIN_PRESETS[key]["label"])


static func get_hair_label(hair_id: String) -> String:
	var key := sanitize_hair_id(hair_id)
	return str(HAIR_PRESETS[key]["label"])


static func get_skin_swatch(skin_id: String) -> Color:
	var key := sanitize_skin_id(skin_id)
	return SKIN_PRESETS[key]["color"] as Color


static func get_hair_swatch(hair_id: String) -> Color:
	var key := sanitize_hair_id(hair_id)
	return HAIR_PRESETS[key]["color"] as Color


static func apply_to_character(root: Node, skin_id: String, hair_id: String) -> void:
	if root == null or not is_instance_valid(root):
		return
	var s_id := sanitize_skin_id(skin_id)
	var h_id := sanitize_hair_id(hair_id)
	_apply_recursive(root, s_id, h_id, false)


static func apply_to_body_part(root: Node, part_type: int, skin_id: String, hair_id: String) -> void:
	if root == null or not is_instance_valid(root):
		return
	# Only Head (0) and Hands (1) expose skin/hair; Torso/Legs are clothed.
	if part_type != 0 and part_type != 1:
		return
	var s_id := sanitize_skin_id(skin_id)
	var h_id := sanitize_hair_id(hair_id)
	_apply_recursive(root, s_id, h_id, true)


static func _apply_recursive(node: Node, skin_id: String, hair_id: String, is_split_part: bool) -> void:
	if node is MeshInstance3D:
		_apply_to_mesh_instance(node as MeshInstance3D, skin_id, hair_id, is_split_part)
	for child in node.get_children():
		_apply_recursive(child, skin_id, hair_id, is_split_part)


static func _apply_to_mesh_instance(mi: MeshInstance3D, skin_id: String, hair_id: String, is_split_part: bool) -> void:
	var mesh := mi.mesh
	if mesh == null:
		return
	var lname := String(mi.name).to_lower()
	var surface_count := mesh.get_surface_count()

	if not is_split_part:
		var is_skin_mesh := (lname == "body" or lname.ends_with("_body"))
		var is_hair_mesh := (lname == "hair" or lname.ends_with("_hair"))
		if is_hair_mesh:
			var hide_hair := bool(HAIR_PRESETS[hair_id]["hide_hair"])
			mi.visible = not hide_hair
			if hide_hair:
				return
			for s in range(surface_count):
				_set_surface_tint(mi, mesh, s, hair_id, true)
		elif is_skin_mesh:
			for s in range(surface_count):
				_set_surface_tint(mi, mesh, s, skin_id, false)
	else:
		# SplitParts meshes share generic names ("head", "head_001", "hands"), so inspect surface materials
		var all_hair_surfaces := true
		for s in range(surface_count):
			var base_mat := mesh.surface_get_material(s)
			var mname := base_mat.resource_name.to_lower() if base_mat != null else ""
			if "cutcover" in mname:
				all_hair_surfaces = false
				continue
			if "hair" in mname:
				var hide_hair := bool(HAIR_PRESETS[hair_id]["hide_hair"])
				if not hide_hair:
					_set_surface_tint(mi, mesh, s, hair_id, true)
			elif "body" in mname:
				all_hair_surfaces = false
				_set_surface_tint(mi, mesh, s, skin_id, false)
			else:
				all_hair_surfaces = false
		if all_hair_surfaces and surface_count > 0:
			mi.visible = not bool(HAIR_PRESETS[hair_id]["hide_hair"])


static func _set_surface_tint(mi: MeshInstance3D, mesh: Mesh, surface_idx: int, preset_id: String, is_hair: bool) -> void:
	if preset_id == "default":
		mi.set_surface_override_material(surface_idx, null)
		return
	var base_mat := mesh.surface_get_material(surface_idx)
	var override_mat := _get_or_build_tint_material(base_mat, preset_id, is_hair)
	mi.set_surface_override_material(surface_idx, override_mat)


static func _get_or_build_tint_material(base_mat: Material, preset_id: String, is_hair: bool) -> ShaderMaterial:
	var mat_key := "%d|%s|%s" % [
		base_mat.get_instance_id() if base_mat != null else 0,
		"hair" if is_hair else "skin",
		preset_id
	]
	if _material_cache.has(mat_key):
		var existing = _material_cache[mat_key]
		if existing != null and is_instance_valid(existing):
			return existing as ShaderMaterial

	if _cached_shader == null:
		_cached_shader = load(TINT_SHADER_PATH) as Shader

	var sm := ShaderMaterial.new()
	sm.shader = _cached_shader

	var preset: Dictionary = HAIR_PRESETS[preset_id] if is_hair else SKIN_PRESETS[preset_id]
	var target_col: Color = preset["color"]
	var strength: float = float(preset["strength"])
	sm.set_shader_parameter("target_tint", target_col)
	sm.set_shader_parameter("tint_strength", strength)
	sm.set_shader_parameter("is_hair", is_hair)

	if base_mat is StandardMaterial3D:
		var std := base_mat as StandardMaterial3D
		if std.albedo_texture != null:
			sm.set_shader_parameter("albedo_tex", std.albedo_texture)
			sm.set_shader_parameter("has_albedo_tex", true)
		else:
			sm.set_shader_parameter("has_albedo_tex", false)
		sm.set_shader_parameter("base_albedo_color", std.albedo_color)
		sm.set_shader_parameter("roughness_val", std.roughness)
	else:
		sm.set_shader_parameter("has_albedo_tex", false)
		sm.set_shader_parameter("base_albedo_color", Color.WHITE)
		sm.set_shader_parameter("roughness_val", 0.65)

	_material_cache[mat_key] = sm
	return sm
