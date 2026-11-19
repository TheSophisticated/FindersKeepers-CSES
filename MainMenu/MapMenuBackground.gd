extends Control

@export_group("Time of Day")
@export_range(0.0, 23.9998, 0.001) var menu_time: float = 0.83


func _ready() -> void:
	var game_mode := NetworkManager.GAME_MODE_SCENE.instantiate()
	game_mode.name = "FullMapBackground"
	var sky := game_mode.get_node_or_null("SubViewportContainer/SubViewport/Sky3D")
	if sky:
		sky.current_time = menu_time
		var time_of_day := sky.get_node_or_null("TimeOfDay")
		if time_of_day:
			time_of_day.current_time = menu_time
	# Keep the full map and its camera, while stopping match setup and spawners.
	game_mode.set_script(null)
	_disable_gameplay_scripts(game_mode)
	var canvas_layer := game_mode.get_node_or_null("CanvasLayer")
	if canvas_layer:
		canvas_layer.hide()
	add_child(game_mode)
	var map_view := game_mode.get_node_or_null("SubViewportContainer")
	if map_view is Control:
		map_view.reparent(self)
		move_child(map_view, 0)


func _disable_gameplay_scripts(node: Node) -> void:
	var attached_script := node.get_script() as Script
	if attached_script and attached_script.resource_path in [
		"res://scripts/managers/SpawnManager.gd",
		"res://Maps/Scripts/PauseMenu.gd",
		"res://Maps/Scripts/TarotInventoryUI.gd",
		"res://Tarot/Scripts/TarotPickup.gd",
		"res://BodyParts/SpellCenter.gd",
	]:
		node.set_script(null)
	for child in node.get_children():
		_disable_gameplay_scripts(child)
