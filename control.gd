extends Control

@onready var timer_label: Label = $TimerLabel
@onready var start_btn: Button = $StartMatchBtn

func _ready():
	# Connect GameManager signals to UI
	GameManager.match_timer_updated.connect(_on_timer_updated)
	GameManager.game_over_announced.connect(_on_game_over)
	start_btn.pressed.connect(_on_start_pressed)

	# Simulate registering dummy players for testing
	GameManager.register_player(1, "Samyak")
	GameManager.register_player(2, "Ram")

func _on_start_pressed():
	GameManager.start_match()
	start_btn.disabled = true

func _on_timer_updated(time_left: float):
	timer_label.text = "Time Remaining: " + str(int(time_left)) + "s"

func _on_game_over(winner_id: int, winner_name: String):
	timer_label.text = "Game Over! Winner: " + winner_name
