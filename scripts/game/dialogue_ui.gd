extends Control
## Pixel-art dialogue box: speaker name, typewriter text, weighted mid choices,
## and the legacy final question mode (kept for compatibility; NPCs now judge
## silently from the weighted choices instead of asking 「我是这样的人」).

signal finished
signal final_choice(yes: bool)
## Emitted whenever a mid-conversation choice is picked.  The narrative uses
## these weights to decide (after the conversation) whether the hero takes
## the NPC's colour — there is no explicit 「are you this kind of person?」 ask.
signal choice_made(weight: int)

enum Mode { HIDDEN, ADVANCE, CHOICE, FINAL }

const FONT_PATH := "res://assets/fonts/NotoSansSC-Subset.ttf"
const PANEL_PATH := "res://assets/generated/ui_panel.png"
const CURSOR_PATH := "res://assets/generated/ui_choice_cursor.png"

const PANEL_RECT := Rect2(16.0, 190.0, 608.0, 162.0)
const TEXT_COLOR := Color(0.95, 0.91, 0.82, 1.0)
const NAME_COLOR := Color(1.00, 0.85, 0.55, 1.0)
const CHOICE_NORMAL := Color(0.82, 0.78, 0.68, 1.0)
const CHOICE_SELECTED := Color(1.00, 0.93, 0.62, 1.0)
const HINT_COLOR := Color(0.65, 0.62, 0.55, 1.0)
const TYPE_SPEED := 34.0

var _font: Font
var _panel: Control
var _name_label: Label
var _text_label: Label
var _choice_labels: Array[Label] = []
var _hint_label: Label
var _cursor_texture: Texture2D
var _portrait_border: ColorRect
var _portrait: TextureRect
var _charm_portrait: TextureRect
var _illustration: TextureRect

var _queue: Array = []
var _speaker := ""
var _mode: Mode = Mode.HIDDEN
var debug_events := 0
var _choices: Array = []
var _selected := 0
var _typing := false
var _chars_shown := 0.0
var _last_blip_char := 0
var _total_chars := 0
var _final_beat: Dictionary = {}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = _load_font()
	_cursor_texture = _load_texture(CURSOR_PATH)
	_build_ui()
	_build_illustration()
	visible = false

func is_open() -> bool:
	return _mode != Mode.HIDDEN

## 0 = hidden, 1 = advancing lines, 2 = mid choice, 3 = final yes/no question.
func current_mode() -> int:
	return int(_mode)

## Hard-close without emitting `finished` (used by the game on segment changes).
func force_close() -> void:
	_mode = Mode.HIDDEN
	visible = false
	_queue.clear()
	_choices = []
	_final_beat = {}
	_typing = false
	_hide_choices()
	_portrait_border.visible = false
	_portrait.visible = false
	_charm_portrait.visible = false
	if _illustration != null:
		_illustration.visible = false

# --- public API -----------------------------------------------------------

func start(beats: Array, speaker_name: String, portrait: Texture2D = null, portrait_tint: Color = Color.WHITE) -> void:
	AudioDirector.play_sfx("dialogue_open", -13.0)
	if _illustration != null:
		_illustration.visible = false
	_last_blip_char = 0
	_final_beat = {}
	_speaker = speaker_name
	_queue = beats.duplicate(true)
	_mode = Mode.ADVANCE
	visible = true
	_set_portrait(portrait, portrait_tint)
	_charm_portrait.visible = false
	_advance()

## Optional tinted overlay for the hero's small heart charm on the portrait.
func set_illustration(texture: Texture2D) -> void:
	if _illustration == null:
		return
	_illustration.texture = texture
	_illustration.visible = texture != null

func set_charm_overlay(texture: Texture2D, tint: Color) -> void:
	_charm_portrait.texture = texture
	_charm_portrait.modulate = tint
	_charm_portrait.visible = texture != null

func _build_illustration() -> void:
	_illustration = TextureRect.new()
	_illustration.position = Vector2(486.0, -2.0)
	_illustration.size = Vector2(128.0, 192.0)
	_illustration.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_illustration.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_illustration.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_illustration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_illustration.visible = false
	add_child(_illustration)

func _set_portrait(portrait: Texture2D, tint: Color) -> void:
	var has_portrait := portrait != null
	_portrait_border.visible = has_portrait
	_portrait.visible = has_portrait
	if has_portrait:
		_portrait.texture = portrait
		_portrait.modulate = tint

func _advance() -> void:
	while not _queue.is_empty():
		var beat: Dictionary = _queue.pop_front()
		match str(beat.get("t", "line")):
			"line":
				AudioDirector.play_sfx("dialogue", -20.0)
				_last_blip_char = 0
				_show_line(str(beat.get("who", "npc")), str(beat.get("text", "")))
				return
			"choice":
				_show_choice(beat)
				return
			"final":
				_show_final(beat)
				return
	_close()

func _close() -> void:
	_mode = Mode.HIDDEN
	visible = false
	finished.emit()

# --- rendering ------------------------------------------------------------

func _build_ui() -> void:
	var panel_texture := _load_texture(PANEL_PATH)
	if panel_texture != null:
		var patch := NinePatchRect.new()
		patch.texture = panel_texture
		patch.patch_margin_left = 8
		patch.patch_margin_top = 8
		patch.patch_margin_right = 8
		patch.patch_margin_bottom = 8
		patch.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		patch.position = PANEL_RECT.position
		patch.size = PANEL_RECT.size
		patch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(patch)
		_panel = patch
	else:
		var border := ColorRect.new()
		border.color = Color(0.85, 0.80, 0.66, 1.0)
		border.position = PANEL_RECT.position - Vector2(2, 2)
		border.size = PANEL_RECT.size + Vector2(4, 4)
		border.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(border)
		_panel = border
		var fill := ColorRect.new()
		fill.color = Color(0.04, 0.05, 0.07, 0.94)
		fill.position = PANEL_RECT.position
		fill.size = PANEL_RECT.size
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(fill)

	_name_label = Label.new()
	_name_label.position = Vector2(70.0, 200.0)
	_name_label.size = Vector2(300.0, 18.0)
	_style_label(_name_label, 13, NAME_COLOR)
	add_child(_name_label)

	# Portrait bust, 32x32, framed with the same cream as the panel border.
	_portrait_border = ColorRect.new()
	_portrait_border.position = Vector2(24.0, 196.0)
	_portrait_border.size = Vector2(36.0, 36.0)
	_portrait_border.color = Color(0.85, 0.80, 0.66, 1.0)
	_portrait_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_border.visible = false
	add_child(_portrait_border)

	_portrait = TextureRect.new()
	_portrait.position = Vector2(26.0, 198.0)
	_portrait.size = Vector2(32.0, 32.0)
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_SCALE
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.visible = false
	add_child(_portrait)

	_charm_portrait = TextureRect.new()
	_charm_portrait.position = Vector2(26.0, 198.0)
	_charm_portrait.size = Vector2(32.0, 32.0)
	_charm_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_charm_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_charm_portrait.stretch_mode = TextureRect.STRETCH_SCALE
	_charm_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_charm_portrait.visible = false
	add_child(_charm_portrait)

	_text_label = Label.new()
	_text_label.position = Vector2(70.0, 220.0)
	_text_label.size = Vector2(538.0, 56.0)
	_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_text_label.add_theme_constant_override("line_spacing", 4)
	_style_label(_text_label, 13, TEXT_COLOR)
	add_child(_text_label)

	for i in 2:
		var option := Label.new()
		option.position = Vector2(78.0, 278.0 + 22.0 * float(i))
		option.size = Vector2(520.0, 20.0)
		_style_label(option, 13, CHOICE_NORMAL)
		option.visible = false
		add_child(option)
		_choice_labels.append(option)

	_hint_label = Label.new()
	_hint_label.position = Vector2(336.0, 328.0)
	_hint_label.size = Vector2(276.0, 18.0)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_style_label(_hint_label, 13, HINT_COLOR)
	add_child(_hint_label)

func _show_line(who: String, text: String) -> void:
	_mode = Mode.ADVANCE
	_hide_choices()
	if who == "me":
		_name_label.text = "我"
	elif who == "npc":
		_name_label.text = _speaker
	else:
		_name_label.text = ""
	_name_label.visible = _name_label.text != ""
	_text_label.text = text
	_text_label.visible_characters = 0
	_total_chars = text.length()
	_chars_shown = 0.0
	_typing = true
	_hint_label.text = "空格 继续"

func _show_choice(beat: Dictionary) -> void:
	_mode = Mode.CHOICE
	_choices = beat.get("options", [])
	_selected = 0
	_text_label.text = str(beat.get("prompt", ""))
	_text_label.visible_characters = -1
	_name_label.visible = false
	_typing = false
	_hint_label.text = "W / S 选择 · 空格 确认"
	for i in _choice_labels.size():
		var option: Label = _choice_labels[i]
		if i < _choices.size():
			option.visible = true
		else:
			option.visible = false
	_refresh_choices()

func _show_final(beat: Dictionary) -> void:
	_final_beat = beat
	_choices = [
		{"text": "我是这样的人", "yes": true},
		{"text": "我不是这样的人", "yes": false},
	]
	_mode = Mode.FINAL
	_selected = 0
	_text_label.text = str(beat.get("prompt", ""))
	_text_label.visible_characters = -1
	_name_label.visible = false
	_typing = false
	_hint_label.text = "W / S 选择 · 空格 确认"
	for i in _choice_labels.size():
		_choice_labels[i].visible = i < 2
	_refresh_choices()

func _hide_choices() -> void:
	for option in _choice_labels:
		option.visible = false
	_hint_label.text = ""

func _refresh_choices() -> void:
	for i in _choice_labels.size():
		if i >= _choices.size():
			continue
		var option: Label = _choice_labels[i]
		var entry: Dictionary = _choices[i]
		option.text = ("▶ " if i == _selected else "     ") + str(entry.get("text", ""))
		option.add_theme_color_override("font_color", CHOICE_SELECTED if i == _selected else CHOICE_NORMAL)

# --- input / update -------------------------------------------------------

func _process(delta: float) -> void:
	if _mode != Mode.ADVANCE or not _typing:
		return
	_chars_shown += delta * TYPE_SPEED
	var count := int(_chars_shown)
	if count >= _total_chars:
		_text_label.visible_characters = -1
		_typing = false
	else:
		_text_label.visible_characters = count
		if count / 3 > _last_blip_char:
			_last_blip_char = count / 3
			AudioDirector.play_sfx("type", -30.0, randf_range(0.94, 1.08))

func _unhandled_input(event: InputEvent) -> void:
	if _mode == Mode.HIDDEN:
		return
	debug_events += 1
	if _is_confirm(event):
		if _typing:
			AudioDirector.play_sfx("ui_click", -16.0)
			_text_label.visible_characters = -1
			_typing = false
		elif _mode == Mode.ADVANCE:
			AudioDirector.play_sfx("ui_click", -18.0)
			_advance()
		elif _mode == Mode.CHOICE:
			AudioDirector.play_sfx("choice", -12.0)
			_pick(_selected)
		elif _mode == Mode.FINAL:
			AudioDirector.play_sfx("choice", -12.0)
			_pick_final(_selected == 0)
		accept_event()
		return
	if _mode == Mode.CHOICE or _mode == Mode.FINAL:
		var step := _nav_step(event)
		if step != 0:
			AudioDirector.play_sfx("ui_move", -20.0)
			_selected = (_selected + step + _choices.size()) % _choices.size()
			_refresh_choices()
			accept_event()

func _is_confirm(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		if key == KEY_SPACE or key == KEY_ENTER or key == KEY_KP_ENTER or key == KEY_E:
			return true
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		return true
	return event.is_action_pressed("ui_accept") or event.is_action_pressed("interact")

func _nav_step(event: InputEvent) -> int:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		if key == KEY_W or key == KEY_UP:
			return -1
		if key == KEY_S or key == KEY_DOWN:
			return 1
	if event.is_action_pressed("ui_up") or event.is_action_pressed("move_up"):
		return -1
	if event.is_action_pressed("ui_down") or event.is_action_pressed("move_down"):
		return 1
	return 0

func _pick(index: int) -> void:
	if index < 0 or index >= _choices.size():
		return
	var option: Dictionary = _choices[index]
	var weight := int(option.get("weight", 0))
	if weight != 0:
		choice_made.emit(weight)
	var reply: Array = option.get("reply", [])
	_hide_choices()
	_choices = []
	_queue = reply + _queue
	_advance()

func _pick_final(yes: bool) -> void:
	var reply: Array = _final_beat.get("yes" if yes else "no", [])
	_hide_choices()
	_choices = []
	final_choice.emit(yes)
	_queue = reply + _queue
	_advance()

# --- helpers --------------------------------------------------------------

func _style_label(label: Label, size: int, color: Color) -> void:
	if _font != null:
		label.add_theme_font_override("font", _font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _load_font() -> Font:
	if ResourceLoader.exists(FONT_PATH):
		var res := load(FONT_PATH)
		if res is Font:
			return res
	return ThemeDB.fallback_font

func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var res := load(path)
		if res is Texture2D:
			return res
	return null
