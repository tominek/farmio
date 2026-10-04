extends SceneTree
## Writes the UI theme built by UiStyle to assets/ui/theme.tres (the project's default theme, set in
## project.godot gui/theme/custom). Run after changing UiStyle:
##   Godot --headless --path . --script scripts/tools/make_theme.gd


func _init() -> void:
	var err := ResourceSaver.save(UiStyle.theme(), "res://assets/ui/theme.tres")
	print("theme saved: ", error_string(err))
	quit()
