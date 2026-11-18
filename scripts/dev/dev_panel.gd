extends CanvasLayer
## Developer cheat panel. Only created when OS.is_debug_build() is true and the
## DEV_PANEL_ENABLED flag in game.gd is on. Delete this script / turn the flag
## off for a release build.
##
## Toggle with F1 or `.

const FONT_PATH := "res://assets/fonts/NotoSansSC-Subset.ttf"

var game: Node
var _root: Control
var _panel: Panel
var _status: Label
var _speed_label: Label
var _speed_slider: HSlider
var _fly_check: CheckBox
var _noclip_check: CheckBox
var _jump_check: CheckBox
var _map_buttons: Array[Button] = []
var _prev_locked := false
var _prev_mouse := Input.MOUSE_MODE_VISIBLE

func setup(owner_game: Node) -> void:
	game = owner_game
	layer = 120
	_build()
	visible = false

func _build() -> void:
	var font := load(FONT_PATH) as Font
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.015, 0.02, 0.03, 0.68)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	_panel = Panel.new()
	_panel.position = Vector2(52.0, 16.0)
	_panel.size = Vector2(536.0, 328.0)
	_panel.add_theme_stylebox_override("panel", _panel_style())
	_root.add_child(_panel)
	var margin := MarginContainer.new()
	margin.position = Vector2(10.0, 8.0)
	margin.size = Vector2(516.0, 312.0)
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_top", 2)
	margin.add_theme_constant_override("margin_bottom", 2)
	_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	margin.add_child(box)
	var title := _label("开发者控制面板 · DEBUG ONLY", 15, Color(1.0, 0.84, 0.52), font)
	box.add_child(title)
	_status = _label("", 10, Color(0.76, 0.80, 0.78), font)
	box.add_child(_status)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 12)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(columns)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(240.0, 0.0)
	left.add_theme_constant_override("separation", 2)
	columns.add_child(left)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(250.0, 0.0)
	right.add_theme_constant_override("separation", 2)
	columns.add_child(right)

	left.add_child(_label("玩家 / 移动", 12, Color(0.94, 0.88, 0.68), font))
	_fly_check = _check("飞行（无重力，空格上升 / Shift 下降）", font)
	_fly_check.toggled.connect(_on_fly)
	left.add_child(_fly_check)
	_noclip_check = _check("穿墙（关闭碰撞）", font)
	_noclip_check.toggled.connect(_on_noclip)
	left.add_child(_noclip_check)
	_jump_check = _check("无限跳跃", font)
	_jump_check.toggled.connect(_on_infinite_jump)
	left.add_child(_jump_check)
	var speed_row := HBoxContainer.new()
	speed_row.add_theme_constant_override("separation", 6)
	left.add_child(speed_row)
	speed_row.add_child(_label("速度 ×", 11, Color(0.86, 0.83, 0.72), font))
	_speed_slider = HSlider.new()
	_speed_slider.min_value = 0.5
	_speed_slider.max_value = 5.0
	_speed_slider.step = 0.5
	_speed_slider.value = 1.0
	_speed_slider.custom_minimum_size = Vector2(130.0, 18.0)
	_speed_slider.value_changed.connect(_on_speed)
	speed_row.add_child(_speed_slider)
	_speed_label = _label("1.0×", 11, Color(0.92, 0.82, 0.58), font)
	speed_row.add_child(_speed_label)
	left.add_child(_button("跳过当前对话", font, _on_skip_dialogue))
	left.add_child(_button("传送到本段出口", font, _on_teleport_exit))
	left.add_child(_button("直接进入下一段", font, _on_next_segment))

	right.add_child(_label("进度 / 地图", 12, Color(0.94, 0.88, 0.68), font))
	var progress_row := HBoxContainer.new()
	progress_row.add_theme_constant_override("separation", 3)
	right.add_child(progress_row)
	progress_row.add_child(_button("全颜色", font, _on_grant_colors, 68.0))
	progress_row.add_child(_button("全道具", font, _on_grant_items, 68.0))
	progress_row.add_child(_button("清空取色", font, _on_clear_colors, 78.0))
	right.add_child(_button("直接进入结局", font, _on_ending))
	right.add_child(_label("跳转到地图（当前高亮）", 11, Color(0.86, 0.83, 0.72), font))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(245.0, 104.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 2)
	scroll.add_child(grid)
	for i in SegmentPresets.count():
		var title_text := str(SegmentPresets.get_segment(i).get("title", "地图 %d" % (i + 1)))
		var button := _button(title_text, font, Callable(self, "_on_jump").bind(i), 0.0, 9)
		button.custom_minimum_size = Vector2(76.0, 20.0)
		grid.add_child(button)
		_map_buttons.append(button)
	var hint := _label("F1 / ~ 关闭    ·    地图按钮会立即载入对应场景", 10, Color(0.66, 0.70, 0.68), font)
	box.add_child(hint)

func _label(text: String, size_px: int, colour: Color, font: Font) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", colour)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _check(text: String, font: Font) -> CheckBox:
	var check := CheckBox.new()
	check.text = text
	check.add_theme_font_override("font", font)
	check.add_theme_font_size_override("font_size", 10)
	check.add_theme_color_override("font_color", Color(0.83, 0.84, 0.80))
	check.add_theme_color_override("font_pressed_color", Color(1.0, 0.82, 0.48))
	return check

func _button(text: String, font: Font, callback: Callable, width: float = 0.0, size_px: int = 10) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_override("font", font)
	button.add_theme_font_size_override("font_size", size_px)
	button.add_theme_color_override("font_color", Color(0.90, 0.84, 0.70))
	button.add_theme_color_override("font_hover_color", Color(1.0, 0.90, 0.52))
	if width > 0.0:
		button.custom_minimum_size = Vector2(width, 20.0)
	else:
		button.custom_minimum_size = Vector2(0.0, 20.0)
	button.pressed.connect(callback)
	return button

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.06, 0.07, 0.97)
	style.border_color = Color(0.72, 0.58, 0.32, 1.0)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style

func open_panel() -> void:
	_prev_locked = GameState.control_locked
	_prev_mouse = Input.mouse_mode
	GameState.control_locked = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	visible = true
	_refresh()

func close_panel() -> void:
	visible = false
	GameState.control_locked = _prev_locked
	Input.set_mouse_mode(_prev_mouse)

func _refresh() -> void:
	var index := int(game.get("_segment_index"))
	var title := str(SegmentPresets.get_segment(index).get("title", ""))
	var player: Node3D = game.get("_player")
	var pos := Vector3.ZERO
	if player != null:
		pos = player.global_position
	_status.text = "当前：%s（%d/%d）  坐标 %.1f, %.1f, %.1f" % [title, index + 1, SegmentPresets.count(), pos.x, pos.y, pos.z]
	_speed_slider.set_value_no_signal(clampf(float(game.call("dev_get_speed")), 0.5, 5.0))
	_speed_label.text = "%.1f×" % float(game.call("dev_get_speed"))
	_fly_check.set_pressed_no_signal(bool(game.call("dev_get_fly")))
	_noclip_check.set_pressed_no_signal(bool(game.call("dev_get_noclip")))
	_jump_check.set_pressed_no_signal(bool(game.call("dev_get_infinite_jump")))
	for i in _map_buttons.size():
		var button := _map_buttons[i]
		button.text = ("▶ " + str(SegmentPresets.get_segment(i).get("title", ""))) if i == index else str(SegmentPresets.get_segment(i).get("title", ""))

func _process(_delta: float) -> void:
	if visible:
		_refresh()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		if key == KEY_ESCAPE or key == KEY_F1 or key == KEY_QUOTELEFT:
			close_panel()
			get_viewport().set_input_as_handled()

# --- actions --------------------------------------------------------------

func _on_fly(enabled: bool) -> void:
	game.call("dev_set_fly", enabled)

func _on_noclip(enabled: bool) -> void:
	game.call("dev_set_noclip", enabled)

func _on_infinite_jump(enabled: bool) -> void:
	game.call("dev_set_infinite_jump", enabled)

func _on_speed(value: float) -> void:
	game.call("dev_set_speed", value)
	_speed_label.text = "%.1f×" % value

func _on_skip_dialogue() -> void:
	game.call("dev_skip_dialogue")

func _on_teleport_exit() -> void:
	game.call("dev_teleport_exit")
	close_panel()

func _on_next_segment() -> void:
	game.call("dev_next_segment")
	close_panel()

func _on_grant_colors() -> void:
	game.call("dev_grant_all_colors")

func _on_grant_items() -> void:
	game.call("dev_grant_all_items")

func _on_clear_colors() -> void:
	game.call("dev_clear_colors")

func _on_ending() -> void:
	close_panel()
	game.call("dev_trigger_ending")

func _on_jump(index: int) -> void:
	close_panel()
	game.call("dev_jump_segment", index)
