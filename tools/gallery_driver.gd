extends Node
## Screenshot gallery: loads each of the 8 segments directly and captures the
## spawn view, so all atmospheres can be reviewed in one pass.
## Run:  Godot.exe --path <project> res://tools/gallery_main.tscn

const SHOT_DIR := "F:/游戏制作/_tools/shots/"

func _ready() -> void:
	SaveSystem.clear()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	if bool(main.get("_resume_mode")):
		main.call("_start_fresh_from_resume")
	else:
		main.call("_start_run")
	await get_tree().create_timer(2.5).timeout
	for i in SegmentPresets.count():
		main.call("_load_segment", i)
		var fade: ColorRect = main.get("_fade")
		if fade != null:
			fade.modulate.a = 0.0
		await get_tree().create_timer(1.8).timeout
		var dialogue: Node = main.get("_dialogue")
		if dialogue != null and bool(dialogue.call("is_open")):
			dialogue.call("force_close")
		var ui: CanvasLayer = main.get("_ui")
		if ui != null:
			ui.visible = false
		await get_tree().create_timer(0.2).timeout
		var image: Image = get_viewport().get_texture().get_image()
		var path := SHOT_DIR + "gallery_%d.png" % i
		image.save_png(path)
		print("[gallery] ", path)
		var player: Node3D = main.get("_player")
		if player != null:
			var config: Dictionary = SegmentPresets.get_segment(i)
			var pos: Vector2 = config.get("player_start", Vector2.ZERO)
			player.global_position = Vector3(pos.x, 0.05, pos.y)
			await get_tree().create_timer(0.4).timeout
	get_tree().quit()
