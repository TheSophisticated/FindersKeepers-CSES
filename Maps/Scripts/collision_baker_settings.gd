@tool
class_name CollisionBakerSettings
extends Resource

## ============================================================
## Tuning for CollisionBaker. Edit in the Inspector.
##
## EditorScenePostImport has no import-options hook, so this Resource is how
## the settings get a UI. Loaded from
## res://Maps/Scripts/collision_baker_settings.tres
## ============================================================


## ===== OUTPUT =====

## Master switch. Off imports the map with no collision at all.
@export var enabled: bool = true

## Layer for generated bodies. Layer 1 is this project's world/floor layer
## (see BodyParts/bodypart.gd, DEFAULT_COLLISION_LAYER).
@export_flags_3d_physics var collision_layer: int = 1

## Print the triangle summary to the Output panel after each import.
@export var verbose: bool = true


## ===== DECIMATION =====

## Upper bound on the grid cell used to snap collision vertices, in metres.
## The cell actually used is always clamped down by the mesh's own thickness,
## so this is a ceiling, not a fixed value.
##   0.10 faithful, heavy     0.25 good default
##   0.40 blocky, cheap       0.75 very cheap
@export_range(0.01, 2.0, 0.01, "or_greater") var decimate_cell: float = 0.25

## Floor for that adaptive cell, so zero-thickness planes cannot divide by zero.
@export_range(0.001, 0.5, 0.001, "or_greater") var min_cell: float = 0.02

## Meshes at or below this triangle count skip decimation entirely. They are
## already cheap, and decimating them only risks breaking them.
@export_range(0, 20000, 50) var pass_through_tris: int = 400

## If decimation would discard more than this fraction of a mesh's triangles,
## the original is kept. A lossy proxy is worse than a big one.
@export_range(0.0, 1.0, 0.05) var max_tri_loss: float = 0.5


## ===== FILTERING =====

## Meshes whose world AABB diagonal is under this (metres) get no collision at
## all. Most of a hotel kit is decor the player walks past; skipping it is the
## single biggest saving available.
@export_range(0.0, 10.0, 0.05, "or_greater") var min_extent: float = 0.5

## Case-insensitive substrings. A mesh whose name contains any of these is
## skipped. Watch this: the map has many "canvas" nodes.
@export var skip_name_patterns: PackedStringArray = PackedStringArray([
	"glass", "canvas", "nor_gl",
])


## ===== SHAPING =====

## Collision is merged into cubes of this size, keeping the physics broadphase
## small. Smaller values give more, tighter bodies.
@export_range(1.0, 64.0, 0.5, "or_greater") var chunk_size: float = 12.0

## Allow collision through from behind. This doubles the physics triangle count;
## only enable it if the geometry really is single-sided sheets.
@export var backface_collision: bool = false
