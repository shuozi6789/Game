extends Node
## End-to-end autotest driver (normal main loop, so autoloads work).
##
## Run:  Godot.exe --path <project> res://tools/autotest_main.tscn -- --pattern=10101
##       pattern: 8 chars, one per NPC in story order (red yellow green blue purple orange pink teal),
##                1 = answer 「我是这样的人」, 0 = answer 「我不是这样的人」.
##                Default "11111".
## It starts the run, teleports the hero to each NPC, answers the whole
## conversation, teleports to the exit, lets the fade happen, then verifies the
## ending key and prints a report.

const SHOT_DIR := "F:/游戏制作/_tools/shots/"
const NPC_ORDER := ["red", "yellow", "green", "blue", "purple", "orange", "pink", "teal"]

var _main: Node
var _pattern := "11111111"
var _failures: int = 0

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--pattern="):
			_pattern = arg.substr("--pattern=".length())
	while _pattern.length() < NPC_ORDER.size():
		_pattern += "1"
	print("[autotest] pattern=", _pattern)

	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	await _wait(0.9)
	_shot("auto_title")
	# This end-to-end test targets the 11 narrative segments, so it starts the
	# run directly instead of walking through the opening house prologue.
	_main.call("_start_run")
	await _wait(2.6)
	_shot("auto_start")

	var npc_index := 0
	var expected_ids: Array = []
	for i in SegmentPresets.count():
		await _wait(1.6)
		var segment_index: int = int(_main.get("_segment_index"))
		if segment_index != i:
			_log("WARN segment drift: loop=%d actual=%d" % [i, segment_index])
		var config: Dictionary = SegmentPresets.get_segment(i)
		var npc_id := str(config.get("npc_id", ""))
		if npc_id != "":
			var want_yes := _pattern.substr(npc_index, 1) == "1"
			npc_index += 1
			var npc: Node3D = _main.get("_npc")
			if npc == null:
				_log("FAIL no NPC in segment %d (%s)" % [i, npc_id])
				_failures += 1
			else:
				var player: Node3D = _main.get("_player")
				player.global_position = npc.global_position + Vector3(0.0, 0.05, 2.0)
				await _wait(0.5)
				_shot("npc_%d_%s" % [i, npc_id])
				await _tap(KEY_E)
				await _wait(0.4)
				if not GameState.dialogue_active:
					_log("FAIL dialogue did not open for %s" % npc_id)
					_failures += 1
				await _finish_dialogue(want_yes)
				if want_yes:
					expected_ids.append(npc_id)
				_shot("talked_%d_%s" % [i, npc_id])
				_log("segment %d %s yes=%s -> colors=%s" % [i, npc_id, str(want_yes), str(GameState.color_ids())])
		var exit_xz: Vector2 = config.get("exit_position", Vector2.ZERO)
		var player2: Node3D = _main.get("_player")
		player2.global_position = Vector3(exit_xz.x, 0.05, exit_xz.y)
		await _wait(0.5)
		await _wait(2.6)

	await _wait(1.5)
	_shot("auto_ending")
	var ending: Control = _main.get("_ending_screen")
	var ending_visible: bool = ending.visible
	var key: String = GameState.ending_key()
	var ids: Array = GameState.color_ids()
	var expected_key := _ending_key(expected_ids)
	_log("DONE ending_visible=%s key=%s expected_key=%s ids=%s mixed=%s met=%d failures=%d" % [
		str(ending_visible), key, expected_key, str(ids), str(GameState.mixed_color()),
		GameState.met.size(), _failures])
	if not ending_visible:
		_log("FAIL ending screen not visible")
		_failures += 1
	if key != expected_key:
		_log("FAIL ending key mismatch: %s vs %s" % [key, expected_key])
		_failures += 1
	await _wait(0.5)
	await _tap(KEY_SPACE)
	await _wait(1.0)
	_shot("auto_portrait")
	var portrait_layer: Control = _main.get("_portrait_layer")
	if portrait_layer == null or not portrait_layer.visible:
		_log("FAIL portrait page not visible")
		_failures += 1
	await _wait(0.4)
	get_tree().quit(0 if _failures == 0 else 1)

func _finish_dialogue(want_yes: bool) -> void:
	var guard := 0
	while GameState.dialogue_active and guard < 200:
		var mode: int = int((_main.get("_dialogue")).call("current_mode"))
		# mode 2 = a weighted mid-conversation choice.  The NPC conversations
		# now carry three of them and end with a silent judgement, so answering
		# "no" means taking the second option every time.
		if mode == 2 and not want_yes:
			await _tap(KEY_S)
		await _tap(KEY_SPACE)
		await _wait(0.30)
		guard += 1
	if guard >= 160:
		_log("FAIL dialogue never closed")
		_failures += 1

func _ending_key(ids: Array) -> String:
	if ids.is_empty():
		return "white"
	if ids.size() == 1:
		return "single_%s" % ids[0]
	if ids.size() == 2:
		var pair: Array = ids.duplicate()
		pair.sort_custom(func(a, b): return NPC_ORDER.find(a) < NPC_ORDER.find(b))
		return "pair_%s_%s" % [pair[0], pair[1]]
	return "multi_%d" % ids.size()

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
	var path := SHOT_DIR + name + ".png"
	image.save_png(path)

func _log(message: String) -> void:
	print("[autotest] ", message)
