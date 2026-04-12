extends Control

const MAP_SIZES := {
	"Small (256x256)": 256,
	"Medium (512x512)": 512,
	"Large (1024x1024)": 1024,
	"Huge (2048x2048)": 2048,
}

@onready var map_size_button: OptionButton = $VBox/MapSize
@onready var new_game_button: Button = $VBox/NewGame
@onready var quit_button: Button = $VBox/Quit


func _ready() -> void:
	map_size_button.clear()
	for label in MAP_SIZES.keys():
		map_size_button.add_item(label)
	map_size_button.selected = 1  # Medium default
	map_size_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS

	new_game_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	quit_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS

	new_game_button.pressed.connect(_on_new_game)
	quit_button.pressed.connect(_on_quit)


func _on_new_game() -> void:
	var selected_label := map_size_button.get_item_text(map_size_button.selected)
	var map_size: int = MAP_SIZES[selected_label]

	# Store settings for the game scene to pick up
	GameSettings.map_size = map_size
	GameSettings.seed_value = randi()

	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_quit() -> void:
	get_tree().quit()
