extends Node
## PR screenshots: title, NPC prompt, dialogue line, weighted choices, result line,
## dye mid-animation and a dyed hero. Run:  Godot.exe --path <project> res://tools/shots_main.tscn

const SHOT_DIR := "F:/游戏制作/_tools/shots/"

var _main: Node

func _ready() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _wait(2.4)
	_shot("pr_title")
	await _tap(KEY_SPACE)
	await _wait(2.4)
	# Skip the morning monologue by jumping straight to the red courier segment.
	_main.call("_load_segment", 1)
	await _wait(2.2)
	_set_fade(0.0)
	var npc: Node3D = _main.get("_npc")
	var player: Node3D = _main.get("_player")
	player.global_position = npc.global_position + Vector3(0.0, 0.05, 2.0)
	await _wait(0.8)
	_shot("pr_npc_prompt")
	await _tap(KEY_E)
	await _wait(0.8)
	_shot("pr_dialogue_line")
	# Advance until the mid dialogue choice is on screen.
	var guard := 0
	while _mode() != 2 and guard < 30:
		await _tap(KEY_SPACE)
		await _wait(0.5)
		guard += 1
	_shot("pr_choice")
	# Pick the first option everywhere; the conversation now has three weighted
	# choices and ends with a silent judgement + one inner result line.
	await _tap(KEY_SPACE)
	await _wait(0.4)
	guard = 0
	while _mode() != 2 and guard < 40:
		await _tap(KEY_SPACE)
		await _wait(0.4)
		guard += 1
	if _mode() == 2:
		_shot("pr_choice2")
		await _tap(KEY_SPACE)
		await _wait(0.35)
	guard = 0
	while GameState.dialogue_active and str(_main.get("_current_npc_id")) != "" and guard < 160:
		await _tap(KEY_SPACE)
		await _wait(0.28)
		guard += 1
	await _wait(0.55)
	_shot("pr_dye_mid")
	guard = 0
	var got_result := false
	while GameState.dialogue_active and guard < 40:
		if not got_result:
			await _wait(0.9)
			_shot("pr_result")
			got_result = true
		await _tap(KEY_SPACE)
		await _wait(0.45)
		guard += 1
	await _wait(0.6)
	_shot("pr_dyed")
	print("[shots] done colors=", GameState.color_ids())
	get_tree().quit()

func _mode() -> int:
	return int((_main.get("_dialogue")).call("current_mode"))

func _set_fade(alpha: float) -> void:
	var fade: ColorRect = _main.get("_fade")
	if fade != null:
		fade.modulate.a = alpha

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func _tap(code: Key) -> void:
	_event(code, true)
	await get_tree().process_frame
	_event(code, false)
	await get_tree().process_frame

func _event(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.device = -1
	ev.pressed = pressed
	Input.parse_input_event(ev)

func _shot(name: String) -> void:
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(SHOT_DIR + name + ".png")
	print("[shots] ", name)
