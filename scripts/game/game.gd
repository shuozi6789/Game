extends Node3D
## Orchestrates the 8-segment narrative walk:
## builds each segment, places the hero and the NPC, runs dialogue, fades
## between segments, and shows the ending that matches the colours taken.

const PLAYER_SCENE_PATH := "res://scenes/player/player.tscn"
const NPC_SCENE_PATH := "res://scenes/npc/npc.tscn"
const CHARM_SCRIPT_PATH := "res://scripts/ui/charm_hud.gd"
const DIALOGUE_SCENE_PATH := "res://scenes/ui/dialogue_ui.tscn"
const SEGMENT_SCENE_PATH := "res://scenes/segment/segment.tscn"
const CAMERA_SCENE_PATH := "res://scenes/game/camera_rig.tscn"
const VIGNETTE_SHADER_PATH := "res://shaders/post_vignette.gdshader"
const FONT_PATH := "res://assets/fonts/NotoSansSC-Subset.ttf"
const SETTINGS_PATH := "user://settings.cfg"
const GROUND_TEXTURE := "res://assets/generated/grass_ground.png"
const PLAYER_SHEET_PATH := "res://assets/generated/player_whitebox.png"
const REST_SHEET_PATH := "res://assets/generated/player_rest.png"

const LOADING_MIN_SECONDS := 3.4

const INTERACT_RADIUS := 3.4
const TEXT_COLOR := Color(0.95, 0.91, 0.82, 1.0)
const DIM_COLOR := Color(0.70, 0.68, 0.62, 1.0)
const ACCENT_COLOR := Color(1.00, 0.86, 0.56, 1.0)

var _font: Font
var _segment_host: Node3D
var _player: CharacterBody3D
var _camera_rig: Node
var _camera: Camera3D
var _ui: CanvasLayer
var _dialogue: Control
var _charm_hud: Control
var _first_person: bool = false
var _prompt: Label
var _segment_title: Label
var _fade: ColorRect
var _title_screen: Control
var _ending_screen: Control
var _ending_title: Label
var _ending_body: Label
var _ending_chip: ColorRect
var _ending_meta: Label
var _ending_hint: Label
var _ending_page: int = 0
var _npc_score: int = 0
var _portrait_layer: Control
var _portrait_title: Label
var _portrait_subtitle: Label
var _portrait_axis_labels: Array[Label] = []
var _portrait_a_labels: Array[Label] = []
var _portrait_b_labels: Array[Label] = []
var _portrait_a_swatches: Array[ColorRect] = []
var _portrait_b_swatches: Array[ColorRect] = []
var _portrait_summary: Label
var _portrait_hint: Label

var _segment: Node3D
var _npc: Node3D
var _segment_index: int = 0
var _current_npc_id: String = ""
var _transitioning: bool = false
var _title_active: bool = true
var _title_time: float = 0.0
var _title_glows: Array[Dictionary] = []
var _title_mists: Array[Dictionary] = []
var _title_motes: Array[Dictionary] = []
var _title_hint_label: Label
var _title_menu: Control
var _title_menu_buttons: Array[Button] = []
var _title_menu_texts: Array[String] = []
var _title_menu_actions: Array[String] = []
var _title_menu_index: int = 0
var _settings_page: Control
var _settings_buttons: Array[Button] = []
var _settings_actions: Array[String] = []
var _settings_index: int = 0
var _settings_volume: float = 0.7
var _settings_fullscreen: bool = true
var _settings_return: String = "title"
var _menu_layer: CanvasLayer
var _loading_layer: CanvasLayer
var _loading_icon: Control
var _loading_hint: Label
var _pause_menu: Control
var _pause_buttons: Array[Button] = []
var _pause_texts: Array[String] = []
var _pause_actions: Array[String] = []
var _pause_index: int = 0
var _pause_active: bool = false
var _pause_prev_locked: bool = false
var _ending_active: bool = false
var _run_started: bool = false
# --- backpack ---------------------------------------------------------------
var _backpack_page: Control
var _backpack_buttons: Array[Button] = []
var _backpack_index: int = 0
var _backpack_active: bool = false
var _dev_panel: CanvasLayer
var _backpack_prev_locked: bool = false
var _backpack_preview_viewport: SubViewport
var _backpack_preview_root: Node3D
var _backpack_title: Label
var _backpack_desc: Label
var _item_toast: Label
var _item_toast_tween: Tween

# --- resume / loading / dye presentation ------------------------------------
var _autosave: Timer
var _flash: ColorRect
var _rest_hint: Label
var _resume_mode: bool = false
var _loading_active: bool = false
var _quitting: bool = false
var _save_data: Dictionary = {}
var _start_layer: CanvasLayer
var _start_overlay: Control
var _start_shot: TextureRect
var _start_sprite: Sprite2D
var _start_title: Label
var _start_prompt: Label
var _start_hint: Label
var _loading_label: Label
var _start_phase: String = "sit"
var _start_sprite_time: float = 0.0
var _start_has_rest: bool = false

func _ready() -> void:
	_font = _load_font()
	_load_settings()
	_build_world()
	_build_ui()
	if DEV_PANEL_ENABLED and OS.is_debug_build():
		var panel_script := load("res://scripts/dev/dev_panel.gd")
		if panel_script != null:
			_dev_panel = panel_script.new()
			add_child(_dev_panel)
			_dev_panel.call("setup", self)
	GameState.color_changed.connect(_on_color_changed)
	get_tree().set_auto_accept_quit(false)
	_autosave = Timer.new()
	_autosave.wait_time = 5.0
	_autosave.autostart = false
	_autosave.timeout.connect(_on_autosave_tick)
	add_child(_autosave)
	_show_title()
	if GameState.begin_journey_on_main:
		GameState.begin_journey_on_main = false
		_start_run()

# =============================================================================
# WORLD / CAMERA
# =============================================================================

func _build_world() -> void:
	_segment_host = Node3D.new()
	_segment_host.name = "SegmentHost"
	add_child(_segment_host)

	_player = load(PLAYER_SCENE_PATH).instantiate()
	_player.name = "Player"
	add_child(_player)
	_player.connect("stand_up_finished", Callable(self, "_on_player_stood_up"))

	_camera_rig = load(CAMERA_SCENE_PATH).instantiate()
	add_child(_camera_rig)
	_camera = _camera_rig.get_node("Camera3D") as Camera3D
	_camera_rig.call("set_target", _player)

	# Park the hero out of sight until the run starts.
	_player.global_position = Vector3(0.0, -20.0, 0.0)

# =============================================================================
# UI
# =============================================================================

func _build_ui() -> void:
	# --- vignette (below the interface) -------------------------------------
	var vignette_layer := CanvasLayer.new()
	vignette_layer.layer = 0
	add_child(vignette_layer)
	var vig_rect := ColorRect.new()
	vig_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vig_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vig_shader := load(VIGNETTE_SHADER_PATH) as Shader
	if vig_shader != null:
		var vig_mat := ShaderMaterial.new()
		vig_mat.shader = vig_shader
		vig_rect.material = vig_mat
	vignette_layer.add_child(vig_rect)

	# --- HUD / dialogue ------------------------------------------------------
	_ui = CanvasLayer.new()
	_ui.layer = 10
	add_child(_ui)

	_dialogue = load(DIALOGUE_SCENE_PATH).instantiate()
	_ui.add_child(_dialogue)

	# Top-left liquid-glitter heart: the hero's "self" lives in this charm now.
	var charm: Control = load(CHARM_SCRIPT_PATH).new()
	charm.position = Vector2(10.0, 6.0)
	charm.call("set_player", _player)
	_ui.add_child(charm)
	_charm_hud = charm
	_dialogue.connect("finished", Callable(self, "_on_dialogue_finished"))
	_dialogue.connect("final_choice", Callable(self, "_on_final_choice"))
	_dialogue.connect("choice_made", Callable(self, "_on_choice_made"))

	_prompt = _make_label(Vector2(230.0, 296.0), Vector2(180.0, 22.0), 12, TEXT_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	_prompt.text = "E 交谈"
	_prompt.add_theme_constant_override("outline_size", 4)
	_prompt.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	_prompt.visible = false
	_ui.add_child(_prompt)

	_segment_title = _make_label(Vector2(180.0, 22.0), Vector2(280.0, 26.0), 16, ACCENT_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	_segment_title.modulate.a = 0.0
	_ui.add_child(_segment_title)

	# --- fade -----------------------------------------------------------------
	_fade = ColorRect.new()
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.color = Color(0.0, 0.0, 0.0, 1.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.modulate.a = 0.0
	var fade_layer := CanvasLayer.new()
	fade_layer.layer = 20
	add_child(fade_layer)
	fade_layer.add_child(_fade)

	# Pause menu + shared settings page sit above both the game and title screens.
	_menu_layer = CanvasLayer.new()
	_menu_layer.layer = 40
	add_child(_menu_layer)

	# --- title / ending screens ----------------------------------------------
	var screen_layer := CanvasLayer.new()
	screen_layer.layer = 30
	add_child(screen_layer)

	_title_screen = Control.new()
	_title_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	screen_layer.add_child(_title_screen)
	var title_bg := ColorRect.new()
	title_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# A warm-white expanse instead of the old dark title card.
	title_bg.color = Color(0.895, 0.880, 0.845, 1.0)
	_title_screen.add_child(title_bg)

	var title_art := Control.new()
	title_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_screen.add_child(title_art)

	# Soft light pools (additive white on the warm-white page).
	var glow_specs := [
		{"size": 380, "pos": Vector2(-90.0, -110.0), "alpha": 0.72, "tint": Color(1.0, 1.0, 0.96)},
		{"size": 300, "pos": Vector2(400.0, -20.0), "alpha": 0.70, "tint": Color(1.0, 0.99, 0.92)},
		{"size": 240, "pos": Vector2(150.0, 150.0), "alpha": 0.55, "tint": Color(1.0, 1.0, 1.0)},
		{"size": 200, "pos": Vector2(290.0, -30.0), "alpha": 0.45, "tint": Color(1.0, 1.0, 0.97)},
		{"size": 130, "pos": Vector2(70.0, 250.0), "alpha": 0.22, "tint": Color(1.0, 0.99, 0.96)},
	]
	for spec in glow_specs:
		var glow := TextureRect.new()
		glow.texture = _make_glow_texture(int(spec["size"]))
		glow.position = spec["pos"]
		glow.size = Vector2(float(spec["size"]), float(spec["size"]))
		glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		glow.stretch_mode = TextureRect.STRETCH_SCALE
		glow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var glow_material := CanvasItemMaterial.new()
		glow_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		glow.material = glow_material
		var tint: Color = spec["tint"]
		glow.modulate = Color(tint.r, tint.g, tint.b, float(spec["alpha"]))
		title_art.add_child(glow)
		_title_glows.append({
			"node": glow,
			"base": spec["pos"],
			"alpha": float(spec["alpha"]),
			"phase": randf() * TAU,
			"drift": Vector2(randf_range(8.0, 18.0), randf_range(5.0, 12.0)),
		})

	# A broad, slightly angled shaft of light + its hot core: the "shining into
	# the camera" glare of the opening page.
	for beam_spec in [
		{"size": Vector2(1040.0, 230.0), "pos": Vector2(-190.0, -95.0), "alpha": 0.55, "angle": -17.0},
		{"size": Vector2(1040.0, 70.0), "pos": Vector2(-190.0, -28.0), "alpha": 0.85, "angle": -17.0},
		{"size": Vector2(1080.0, 26.0), "pos": Vector2(-200.0, -4.0), "alpha": 0.95, "angle": -17.0},
	]:
		var beam := TextureRect.new()
		beam.texture = _make_beam_texture()
		beam.position = beam_spec["pos"]
		beam.size = beam_spec["size"]
		beam.rotation_degrees = float(beam_spec["angle"])
		beam.pivot_offset = beam.size * 0.5
		beam.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		beam.stretch_mode = TextureRect.STRETCH_SCALE
		beam.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		beam.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var beam_material := CanvasItemMaterial.new()
		beam_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		beam.material = beam_material
		beam.modulate = Color(1.0, 0.99, 0.95, float(beam_spec["alpha"]))
		title_art.add_child(beam)
		_title_glows.append({
			"node": beam,
			"base": beam_spec["pos"],
			"alpha": float(beam_spec["alpha"]),
			"phase": randf() * TAU,
			"drift": Vector2(randf_range(2.0, 6.0), randf_range(1.0, 3.0)),
		})

	# A few tiny hot glints riding on the beam.
	var glint_texture := _make_glow_texture(26)
	for glint_spec in [
		{"size": 78.0, "pos": Vector2(512.0, 14.0), "alpha": 1.0},
		{"size": 48.0, "pos": Vector2(446.0, 68.0), "alpha": 0.95},
		{"size": 32.0, "pos": Vector2(578.0, 52.0), "alpha": 0.95},
	]:
		var glint := TextureRect.new()
		glint.texture = glint_texture
		glint.position = glint_spec["pos"]
		glint.size = Vector2(float(glint_spec["size"]), float(glint_spec["size"]))
		glint.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		glint.stretch_mode = TextureRect.STRETCH_SCALE
		glint.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		glint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var glint_material := CanvasItemMaterial.new()
		glint_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		glint.material = glint_material
		glint.modulate = Color(1.0, 1.0, 0.98, float(glint_spec["alpha"]))
		title_art.add_child(glint)
		_title_glows.append({
			"node": glint,
			"base": glint_spec["pos"],
			"alpha": float(glint_spec["alpha"]),
			"phase": randf() * TAU,
			"drift": Vector2(randf_range(1.0, 3.0), randf_range(1.0, 3.0)),
		})

	# Starburst lens flare: the harsh part of the "light shining into the lens".
	for flare_spec in [
		{"size": 430.0, "pos": Vector2(300.0, -125.0), "alpha": 1.0, "angle": 20.0},
		{"size": 180.0, "pos": Vector2(40.0, 300.0), "alpha": 0.25, "angle": -8.0},
	]:
		var flare := TextureRect.new()
		flare.texture = _make_flare_texture(256)
		flare.position = flare_spec["pos"]
		flare.size = Vector2(float(flare_spec["size"]), float(flare_spec["size"]))
		flare.rotation_degrees = float(flare_spec["angle"])
		flare.pivot_offset = flare.size * 0.5
		flare.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		flare.stretch_mode = TextureRect.STRETCH_SCALE
		flare.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		flare.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var flare_material := CanvasItemMaterial.new()
		flare_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		flare.material = flare_material
		flare.modulate = Color(1.0, 1.0, 0.99, float(flare_spec["alpha"]))
		title_art.add_child(flare)
		_title_glows.append({
			"node": flare,
			"base": flare_spec["pos"],
			"alpha": float(flare_spec["alpha"]),
			"phase": randf() * TAU,
			"drift": Vector2(randf_range(1.0, 4.0), randf_range(1.0, 4.0)),
		})

	# Anamorphic streak across the upper page: the harsh "sun in the lens" line.
	var streak := TextureRect.new()
	streak.texture = _make_beam_texture()
	streak.position = Vector2(30.0, 92.0)
	streak.size = Vector2(780.0, 24.0)
	streak.rotation_degrees = -3.5
	streak.pivot_offset = streak.size * 0.5
	streak.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	streak.stretch_mode = TextureRect.STRETCH_SCALE
	streak.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	streak.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var streak_material := CanvasItemMaterial.new()
	streak_material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	streak.material = streak_material
	streak.modulate = Color(1.0, 0.985, 0.93, 0.92)
	title_art.add_child(streak)
	_title_glows.append({
		"node": streak,
		"base": streak.position,
		"alpha": 0.92,
		"phase": randf() * TAU,
		"drift": Vector2(randf_range(1.0, 3.0), randf_range(0.5, 1.5)),
	})

	# A faint white veil pushes the whole page slightly overexposed.
	var veil := ColorRect.new()
	veil.position = Vector2.ZERO
	veil.size = Vector2(640.0, 360.0)
	veil.color = Color(1.0, 1.0, 1.0, 0.02)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_art.add_child(veil)

	# A couple of pale concentric rings for the "aperture" feel.
	var ring_specs := [
		{"size": 250, "pos": Vector2(40.0, 55.0), "alpha": 0.30},
		{"size": 160, "pos": Vector2(420.0, 180.0), "alpha": 0.34},
		{"size": 110, "pos": Vector2(250.0, 28.0), "alpha": 0.24},
	]
	for spec in ring_specs:
		var ring := TextureRect.new()
		ring.texture = _make_ring_texture(int(spec["size"]))
		ring.position = spec["pos"]
		ring.size = Vector2(float(spec["size"]), float(spec["size"]))
		ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ring.stretch_mode = TextureRect.STRETCH_SCALE
		ring.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ring.modulate = Color(0.78, 0.65, 0.44, float(spec["alpha"]))
		title_art.add_child(ring)
		_title_glows.append({
			"node": ring,
			"base": spec["pos"],
			"alpha": float(spec["alpha"]),
			"phase": randf() * TAU,
			"drift": Vector2(randf_range(4.0, 9.0), randf_range(3.0, 8.0)),
		})

	# Two very low-alpha mist sheets drifting over the page.
	for i in 2:
		var mist := TextureRect.new()
		mist.texture = _make_mist_texture()
		mist.position = Vector2(-60.0 + float(i) * 260.0, -40.0 + float(i) * 90.0)
		mist.size = Vector2(760.0, 440.0)
		mist.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mist.stretch_mode = TextureRect.STRETCH_SCALE
		mist.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		mist.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mist.modulate = Color(1.0, 0.99, 0.95, 0.16)
		title_art.add_child(mist)
		_title_mists.append({
			"node": mist,
			"base": mist.position,
			"phase": randf() * TAU,
			"drift": Vector2(randf_range(10.0, 20.0), randf_range(6.0, 14.0)),
		})

	# Tiny floating dust motes.
	var mote_texture := _make_glow_texture(14)
	for i in 18:
		var mote := TextureRect.new()
		mote.texture = mote_texture
		var mote_size := randf_range(7.0, 15.0)
		mote.position = Vector2(randf_range(20.0, 620.0), randf_range(10.0, 350.0))
		mote.size = Vector2(mote_size, mote_size)
		mote.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mote.stretch_mode = TextureRect.STRETCH_SCALE
		mote.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		mote.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mote.modulate = Color(1.0, 0.98, 0.92, randf_range(0.25, 0.55))
		title_art.add_child(mote)
		_title_motes.append({
			"node": mote,
			"speed": randf_range(4.0, 11.0),
			"phase": randf() * TAU,
			"drift": randf_range(3.0, 9.0),
		})

	var title_label := _make_label(Vector2(0.0, 128.0), Vector2(640.0, 40.0), 24, Color(0.26, 0.22, 0.18, 1.0), HORIZONTAL_ALIGNMENT_CENTER)
	title_label.text = "寻 找 自 己 的 路"
	_title_screen.add_child(title_label)
	var title_sub := _make_label(Vector2(0.0, 186.0), Vector2(640.0, 20.0), 12, Color(0.42, 0.37, 0.32, 1.0), HORIZONTAL_ALIGNMENT_CENTER)
	title_sub.text = "慢慢走。遇到人，就和他们说说话。"
	_title_screen.add_child(title_sub)
	_title_hint_label = _make_label(Vector2(0.0, 336.0), Vector2(640.0, 18.0), 10, Color(0.55, 0.34, 0.14, 1.0), HORIZONTAL_ALIGNMENT_CENTER)
	_title_hint_label.text = ""
	_title_screen.add_child(_title_hint_label)
	_build_title_menu()
	_build_settings_page()
	_build_pause_menu()
	_build_backpack_page()
	_build_loading_overlay()

	_ending_screen = Control.new()
	_ending_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ending_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ending_screen.visible = false
	screen_layer.add_child(_ending_screen)
	var end_bg := ColorRect.new()
	end_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	end_bg.color = Color(0.035, 0.040, 0.050, 1.0)
	_ending_screen.add_child(end_bg)
	_ending_title = _make_label(Vector2(0.0, 32.0), Vector2(640.0, 32.0), 20, ACCENT_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	_ending_screen.add_child(_ending_title)
	_ending_body = _make_label(Vector2(80.0, 92.0), Vector2(480.0, 150.0), 12, TEXT_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	_ending_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ending_body.add_theme_constant_override("line_spacing", 3)
	_ending_body.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_ending_screen.add_child(_ending_body)
	var chip_border := ColorRect.new()
	chip_border.position = Vector2(254.0, 246.0)
	chip_border.size = Vector2(132.0, 12.0)
	chip_border.color = Color(0.85, 0.80, 0.66, 1.0)
	_ending_screen.add_child(chip_border)
	_ending_chip = ColorRect.new()
	_ending_chip.position = Vector2(256.0, 248.0)
	_ending_chip.size = Vector2(128.0, 8.0)
	_ending_chip.color = Color.WHITE
	_ending_screen.add_child(_ending_chip)
	var chip_caption := _make_label(Vector2(0.0, 260.0), Vector2(640.0, 14.0), 10, DIM_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	chip_caption.text = "流麻里的颜色"
	_ending_screen.add_child(chip_caption)
	_ending_meta = _make_label(Vector2(70.0, 276.0), Vector2(500.0, 32.0), 9, DIM_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	_ending_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ending_meta.add_theme_constant_override("line_spacing", 2)
	_ending_screen.add_child(_ending_meta)
	_ending_hint = _make_label(Vector2(0.0, 326.0), Vector2(640.0, 18.0), 12, ACCENT_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	_ending_hint.text = "按 空格 查看性格画像"
	_ending_screen.add_child(_ending_hint)

	_portrait_layer = Control.new()
	_portrait_layer.name = "PortraitPage"
	_portrait_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_portrait_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_layer.visible = false
	_ending_screen.add_child(_portrait_layer)
	var portrait_bg := ColorRect.new()
	portrait_bg.position = Vector2.ZERO
	portrait_bg.size = Vector2(640.0, 360.0)
	portrait_bg.color = Color(0.04, 0.05, 0.06, 1.0)
	portrait_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_layer.add_child(portrait_bg)
	_portrait_title = _make_label(Vector2(0.0, 24.0), Vector2(640.0, 30.0), 18, ACCENT_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	_portrait_title.text = "你的性格画像"
	_portrait_layer.add_child(_portrait_title)
	_portrait_subtitle = _make_label(Vector2(0.0, 54.0), Vector2(640.0, 16.0), 10, DIM_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	_portrait_subtitle.text = "由你一路上取下的颜色拼成"
	_portrait_layer.add_child(_portrait_subtitle)
	for i in 4:
		var row_y := 88.0 + 42.0 * float(i)
		var axis_label := _make_label(Vector2(48.0, row_y), Vector2(70.0, 20.0), 12, DIM_COLOR, HORIZONTAL_ALIGNMENT_RIGHT)
		axis_label.text = ""
		_portrait_layer.add_child(axis_label)
		_portrait_axis_labels.append(axis_label)
		var a_swatch := ColorRect.new()
		a_swatch.position = Vector2(128.0, row_y + 5.0)
		a_swatch.size = Vector2(8.0, 8.0)
		a_swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_portrait_layer.add_child(a_swatch)
		_portrait_a_swatches.append(a_swatch)
		var a_label := _make_label(Vector2(144.0, row_y), Vector2(150.0, 20.0), 12, TEXT_COLOR, HORIZONTAL_ALIGNMENT_LEFT)
		_portrait_layer.add_child(a_label)
		_portrait_a_labels.append(a_label)
		var b_swatch := ColorRect.new()
		b_swatch.position = Vector2(330.0, row_y + 5.0)
		b_swatch.size = Vector2(8.0, 8.0)
		b_swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_portrait_layer.add_child(b_swatch)
		_portrait_b_swatches.append(b_swatch)
		var b_label := _make_label(Vector2(346.0, row_y), Vector2(170.0, 20.0), 12, TEXT_COLOR, HORIZONTAL_ALIGNMENT_LEFT)
		_portrait_layer.add_child(b_label)
		_portrait_b_labels.append(b_label)
	_portrait_summary = _make_label(Vector2(64.0, 262.0), Vector2(512.0, 46.0), 11, TEXT_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	_portrait_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_portrait_summary.add_theme_constant_override("line_spacing", 4)
	_portrait_layer.add_child(_portrait_summary)
	_portrait_hint = _make_label(Vector2(0.0, 318.0), Vector2(640.0, 18.0), 12, ACCENT_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	_portrait_hint.text = "按 空格 重新走一遍"
	_portrait_layer.add_child(_portrait_hint)

	# --- dye flash (over the 3D view, under the pop-up screens) --------------
	_flash = ColorRect.new()
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(1.0, 0.97, 0.88, 1.0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.modulate.a = 0.0
	var flash_layer := CanvasLayer.new()
	flash_layer.layer = 15
	add_child(flash_layer)
	flash_layer.add_child(_flash)

	# --- "stand up" hint after resuming --------------------------------------
	_rest_hint = _make_label(Vector2(160.0, 298.0), Vector2(320.0, 22.0), 12, TEXT_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	_rest_hint.text = "按 WASD 起身"
	_rest_hint.add_theme_constant_override("outline_size", 4)
	_rest_hint.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	_rest_hint.visible = false
	_ui.add_child(_rest_hint)

## Soft radial light pool (alpha falloff) used by the white title page.
func _make_glow_texture(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var centre := float(size) * 0.5
	for y in size:
		for x in size:
			var distance := Vector2(float(x) + 0.5 - centre, float(y) + 0.5 - centre).length() / centre
			var alpha := pow(clampf(1.0 - distance, 0.0, 1.0), 2.1)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(img)

## Starburst lens flare: hot core, thin rays and a soft ring.
func _make_flare_texture(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var centre := float(size) * 0.5
	for y in size:
		for x in size:
			var dx := float(x) + 0.5 - centre
			var dy := float(y) + 0.5 - centre
			var distance := Vector2(dx, dy).length() / centre
			var angle := atan2(dy, dx)
			var core := pow(clampf(1.0 - distance / 0.14, 0.0, 1.0), 2.0)
			var rays := 0.0
			for i in 6:
				var ray_angle := float(i) * PI / 3.0 + 0.35
				var alignment := absf(cos(angle - ray_angle))
				rays += pow(alignment, 26.0)
			rays *= pow(clampf(1.0 - distance, 0.0, 1.0), 1.4) * 0.55
			var ring := exp(-pow((distance - 0.36) / 0.05, 2.0)) * 0.25
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(core + rays + ring, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)

## Soft horizontal light shaft; drawn rotated with additive blending.
func _make_beam_texture() -> ImageTexture:
	var width := 256
	var height := 48
	var img := Image.create(width, height, false, Image.FORMAT_RGBA8)
	var centre := float(height) * 0.5
	for y in height:
		var band := pow(clampf(1.0 - absf(float(y) + 0.5 - centre) / centre, 0.0, 1.0), 2.0)
		for x in width:
			var ends := smoothstep(0.0, 0.08, float(x) / float(width)) * smoothstep(1.0, 0.92, float(x) / float(width))
			var alpha := band * ends
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(img)

## Pale concentric ring for the "light aperture" look.
func _make_ring_texture(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var centre := float(size) * 0.5
	for y in size:
		for x in size:
			var distance := Vector2(float(x) + 0.5 - centre, float(y) + 0.5 - centre).length() / centre
			var ring := exp(-pow((distance - 0.62) / 0.085, 2.0))
			var inner_glow := pow(clampf(1.0 - distance, 0.0, 1.0), 3.0) * 0.18
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(ring + inner_glow, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)

## Soft low-frequency mist sheet (stretched across the title page).
func _make_mist_texture() -> ImageTexture:
	var width := 160
	var height := 96
	var img := Image.create(width, height, false, Image.FORMAT_RGBA8)
	for y in height:
		for x in width:
			var fx := float(x)
			var fy := float(y)
			var n := 0.5 + 0.28 * sin(fx * 0.071 + fy * 0.043) * sin(fy * 0.083 - fx * 0.031)
			n += 0.12 * sin(fx * 0.19 + fy * 0.13)
			var alpha := clampf(0.03 + 0.06 * n, 0.0, 0.14)
			img.set_pixel(x, y, Color(1.0, 0.99, 0.95, alpha))
	return ImageTexture.create_from_image(img)

func _update_title_art(delta: float) -> void:
	_title_time += delta
	for entry in _title_glows:
		var node: TextureRect = entry["node"]
		var phase: float = entry["phase"]
		var drift: Vector2 = entry["drift"]
		node.position = (entry["base"] as Vector2) + Vector2(
			sin(_title_time * 0.18 + phase) * drift.x,
			cos(_title_time * 0.14 + phase * 1.7) * drift.y)
		node.modulate.a = float(entry["alpha"]) * (0.82 + 0.18 * sin(_title_time * 0.5 + phase))
	for entry in _title_mists:
		var node: TextureRect = entry["node"]
		var phase: float = entry["phase"]
		var drift: Vector2 = entry["drift"]
		node.position = (entry["base"] as Vector2) + Vector2(
			sin(_title_time * 0.06 + phase) * drift.x,
			cos(_title_time * 0.05 + phase * 1.3) * drift.y)
	for entry in _title_motes:
		var node: TextureRect = entry["node"]
		var phase: float = entry["phase"]
		node.position.y -= float(entry["speed"]) * delta
		node.position.x += sin(_title_time * 0.6 + phase) * float(entry["drift"]) * delta
		if node.position.y < -20.0:
			node.position.y = 376.0
			node.position.x = randf_range(10.0, 630.0)
		node.modulate.a = 0.30 + 0.30 * abs(sin(_title_time * 1.2 + phase))
	if _title_hint_label != null:
		_title_hint_label.modulate.a = 1.0

# =============================================================================
# TITLE MENU / SETTINGS
# =============================================================================

func _ui_hover_sound() -> void:
	AudioDirector.play_sfx("ui_move", -20.0)

func _ui_click_sound() -> void:
	AudioDirector.play_sfx("ui_click", -13.0)

func _style_pixel_button(button: Button, font_size: int, normal: Color, accent: Color) -> void:
	font_size = int(round(float(font_size) * 1.08))
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if _font != null:
		button.add_theme_font_override("font", _font)
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", normal)
	button.add_theme_color_override("font_hover_color", accent)
	button.add_theme_color_override("font_pressed_color", accent)
	button.add_theme_color_override("font_focus_color", accent)
	button.mouse_entered.connect(_ui_hover_sound)
	button.pressed.connect(_ui_click_sound)
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, empty)

func _build_title_menu() -> void:
	_title_menu = Control.new()
	_title_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title_menu.mouse_filter = Control.MOUSE_FILTER_PASS
	_title_screen.add_child(_title_menu)
	var specs := [
		{"text": "开始游戏", "action": "new"},
		{"text": "读取游戏", "action": "load"},
		{"text": "设置", "action": "settings"},
		{"text": "退出游戏", "action": "quit"},
	]
	for i in specs.size():
		var button := Button.new()
		button.position = Vector2(220.0, 222.0 + float(i) * 30.0)
		button.size = Vector2(200.0, 24.0)
		_style_pixel_button(button, 16, Color(0.30, 0.25, 0.20, 1.0), Color(0.58, 0.36, 0.12, 1.0))
		button.mouse_entered.connect(_on_title_menu_hover.bind(i))
		button.pressed.connect(_on_title_menu_pressed.bind(i))
		_title_menu.add_child(button)
		_title_menu_buttons.append(button)
		_title_menu_texts.append(str(specs[i]["text"]))
		_title_menu_actions.append(str(specs[i]["action"]))
	_refresh_title_menu()

func _refresh_title_menu() -> void:
	var can_load := SaveSystem.has_save()
	for i in _title_menu_buttons.size():
		var button := _title_menu_buttons[i]
		var selected := i == _title_menu_index
		button.text = ("> " if selected else "  ") + _title_menu_texts[i]
		var colour := Color(0.30, 0.25, 0.20, 1.0)
		if selected:
			colour = Color(0.58, 0.36, 0.12, 1.0)
		elif _title_menu_actions[i] == "load" and not can_load:
			colour = Color(0.60, 0.57, 0.52, 1.0)
		button.add_theme_color_override("font_color", colour)
		button.add_theme_color_override("font_hover_color", Color(0.58, 0.36, 0.12, 1.0))
		if is_instance_valid(button):
			button.modulate.a = 1.0

func _select_title_menu(index: int) -> void:
	var previous := _title_menu_index
	_title_menu_index = wrapi(index, 0, _title_menu_buttons.size())
	if previous != _title_menu_index:
		AudioDirector.play_sfx("ui_move", -20.0)
	if _title_hint_label != null:
		_title_hint_label.text = ""
	_refresh_title_menu()

func _on_title_menu_hover(index: int) -> void:
	_select_title_menu(index)

func _on_title_menu_pressed(index: int) -> void:
	_select_title_menu(index)
	_activate_title_menu()

func _activate_title_menu() -> void:
	match _title_menu_actions[_title_menu_index]:
		"new":
			_launch_opening()
		"load":
			_load_saved_game()
		"settings":
			_open_settings()
		"quit":
			_save_settings()
			get_tree().quit()

func _launch_opening() -> void:
	# Title / ending -> the opening house. The house exit and grass slope live
	# in the same high-resolution prologue scene; the windmill then starts the
	# 11-segment narrative.
	SaveSystem.clear()
	GameState.reset()
	GameState.control_locked = false
	_title_active = false
	_ending_active = false
	_ending_page = 0
	if _title_screen != null:
		_title_screen.visible = false
	if _ending_screen != null:
		_ending_screen.visible = false
	if _portrait_layer != null:
		_portrait_layer.visible = false
	_show_loading("正在回到木匠家…")
	AudioDirector.play_sfx("transition", -10.0, 0.92)
	await _wait(0.45)
	get_tree().change_scene_to_file("res://scenes/vision/vision.tscn")

func _load_saved_game() -> void:
	if not SaveSystem.has_save():
		if _title_hint_label != null:
			_title_hint_label.text = "没有可读取的存档"
		return
	_enter_resume_mode()
	if _resume_mode:
		_start_from_resume()

func _build_settings_page() -> void:
	_settings_page = Control.new()
	_settings_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_settings_page.mouse_filter = Control.MOUSE_FILTER_STOP
	_settings_page.visible = false
	_menu_layer.add_child(_settings_page)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.075, 0.070, 0.062, 1.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_settings_page.add_child(bg)

	var heading := _make_label(Vector2(0.0, 14.0), Vector2(640.0, 30.0), 20, ACCENT_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	heading.text = "设 置"
	_settings_page.add_child(heading)
	var key_heading := _make_label(Vector2(70.0, 40.0), Vector2(500.0, 18.0), 12, ACCENT_COLOR, HORIZONTAL_ALIGNMENT_LEFT)
	key_heading.text = "按 键"
	_settings_page.add_child(key_heading)
	var keys_left := _make_label(Vector2(70.0, 62.0), Vector2(260.0, 150.0), 10, TEXT_COLOR, HORIZONTAL_ALIGNMENT_LEFT)
	keys_left.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	keys_left.text = "移动　WASD / 方向键
跳跃　空格
奔跑　Shift
交谈 / 调查　E
背包　B / E"
	_settings_page.add_child(keys_left)
	var keys_right := _make_label(Vector2(340.0, 62.0), Vector2(280.0, 150.0), 10, TEXT_COLOR, HORIZONTAL_ALIGNMENT_LEFT)
	keys_right.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	keys_right.text = "第一人称　V（随时切换）
推进 / 确认　空格 / E / 回车
选择选项　W / S 或 ↑ / ↓
菜单　↑ / ↓ 选择，空格确认"
	_settings_page.add_child(keys_right)

	var specs := [
		{"action": "volume"},
		{"action": "back"},
	]
	for i in specs.size():
		var button := Button.new()
		button.position = Vector2(200.0, 196.0 + float(i) * 30.0)
		button.size = Vector2(240.0, 24.0)
		_style_pixel_button(button, 14, TEXT_COLOR, ACCENT_COLOR)
		button.mouse_entered.connect(_on_settings_hover.bind(i))
		button.pressed.connect(_on_settings_pressed.bind(i))
		_settings_page.add_child(button)
		_settings_buttons.append(button)
		_settings_actions.append(str(specs[i]["action"]))
	var hint := _make_label(Vector2(0.0, 330.0), Vector2(640.0, 16.0), 10, DIM_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	hint.text = "↑ / ↓ 选择 · 空格 / 回车 确认 · Esc 返回"
	_settings_page.add_child(hint)
	_refresh_settings()

func _refresh_settings() -> void:
	if _settings_buttons.is_empty():
		return
	for i in _settings_buttons.size():
		var selected := i == _settings_index
		var text := ""
		match _settings_actions[i]:
			"volume":
				text = "音量    %d%%" % int(round(_settings_volume * 100.0))
			"back":
				text = "返回主菜单"
		_settings_buttons[i].text = ("> " if selected else "  ") + text
		_settings_buttons[i].add_theme_color_override("font_color",
			ACCENT_COLOR if selected else TEXT_COLOR)

func _on_settings_hover(index: int) -> void:
	var previous := _settings_index
	_settings_index = clampi(index, 0, _settings_buttons.size() - 1)
	if previous != _settings_index:
		AudioDirector.play_sfx("ui_move", -20.0)
	_refresh_settings()

func _on_settings_pressed(index: int) -> void:
	_settings_index = clampi(index, 0, _settings_buttons.size() - 1)
	_refresh_settings()
	_activate_settings()

func _open_settings(return_to: String = "title") -> void:
	AudioDirector.play_sfx("ui_click", -13.0)
	_settings_return = return_to
	if return_to == "pause":
		_pause_menu.visible = false
	else:
		_title_menu.visible = false
	_settings_page.visible = true
	_settings_index = 0
	_refresh_settings()

func _close_settings() -> void:
	AudioDirector.play_sfx("ui_click", -14.0)
	_settings_page.visible = false
	if _settings_return == "pause":
		_pause_menu.visible = true
		_refresh_pause_menu()
	else:
		_title_menu.visible = true
		_select_title_menu(0)

func _activate_settings() -> void:
	match _settings_actions[_settings_index]:
		"volume":
			_settings_volume += 0.2
			if _settings_volume > 1.001:
				_settings_volume = 0.0
			_apply_settings()
			_save_settings()
			_refresh_settings()
		"back":
			_close_settings()


func _build_loading_overlay() -> void:
	_loading_layer = CanvasLayer.new()
	_loading_layer.name = "LoadingLayer"
	_loading_layer.layer = 70
	add_child(_loading_layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	_loading_layer.add_child(root)
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.035, 0.030, 0.026, 0.94)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	_loading_icon = (load("res://scripts/ui/loading_spinner.gd") as Script).new() as Control
	_loading_icon.position = Vector2(320.0 - 36.0, 148.0)
	_loading_icon.size = Vector2(72.0, 72.0)
	_loading_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_loading_icon)
	_loading_hint = _make_label(Vector2(0.0, 224.0), Vector2(640.0, 22.0), 12,
		Color(0.92, 0.86, 0.72, 1.0), HORIZONTAL_ALIGNMENT_CENTER)
	_loading_hint.text = "加载中…"
	root.add_child(_loading_hint)
	_loading_layer.visible = false

func _show_loading(text: String) -> void:
	if _loading_layer == null:
		return
	_loading_hint.text = text
	_loading_layer.visible = true
	_loading_icon.modulate.a = 1.0

func _hide_loading() -> void:
	if _loading_layer != null:
		_loading_layer.visible = false

func _build_pause_menu() -> void:
	_pause_menu = Control.new()
	_pause_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_menu.visible = false
	_menu_layer.add_child(_pause_menu)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.055, 0.050, 0.045, 0.86)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_menu.add_child(bg)
	var title := _make_label(Vector2(0.0, 76.0), Vector2(640.0, 34.0), 22, ACCENT_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	title.text = "游 戏 暂 停"
	_pause_menu.add_child(title)
	var specs := [
		{"text": "继续游戏", "action": "resume"},
		{"text": "设置", "action": "settings"},
		{"text": "返回主菜单", "action": "main_menu"},
		{"text": "退出游戏", "action": "quit"},
	]
	for i in specs.size():
		var button := Button.new()
		button.position = Vector2(200.0, 146.0 + float(i) * 34.0)
		button.size = Vector2(240.0, 26.0)
		_style_pixel_button(button, 15, Color(0.92, 0.88, 0.78, 1.0), ACCENT_COLOR)
		button.mouse_entered.connect(_on_pause_hover.bind(i))
		button.pressed.connect(_on_pause_pressed.bind(i))
		_pause_menu.add_child(button)
		_pause_buttons.append(button)
		_pause_texts.append(str(specs[i]["text"]))
		_pause_actions.append(str(specs[i]["action"]))
	var hint := _make_label(Vector2(0.0, 318.0), Vector2(640.0, 16.0), 10, DIM_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	hint.text = "↑ / ↓ 选择 · 空格 / 回车 确认 · Esc 继续游戏"
	_pause_menu.add_child(hint)
	_refresh_pause_menu()

func _refresh_pause_menu() -> void:
	for i in _pause_buttons.size():
		var selected := i == _pause_index
		_pause_buttons[i].text = ("> " if selected else "  ") + _pause_texts[i]
		_pause_buttons[i].add_theme_color_override("font_color",
			ACCENT_COLOR if selected else Color(0.92, 0.88, 0.78, 1.0))

func _on_pause_hover(index: int) -> void:
	var previous := _pause_index
	_pause_index = clampi(index, 0, _pause_buttons.size() - 1)
	if previous != _pause_index:
		AudioDirector.play_sfx("ui_move", -20.0)
	_refresh_pause_menu()

func _on_pause_pressed(index: int) -> void:
	_pause_index = clampi(index, 0, _pause_buttons.size() - 1)
	_refresh_pause_menu()
	_activate_pause()

func _activate_pause() -> void:
	match _pause_actions[_pause_index]:
		"resume":
			_close_pause()
		"settings":
			_open_settings("pause")
		"main_menu":
			_return_to_main_menu()
		"quit":
			_quit_from_pause()

func _can_pause() -> bool:
	return _run_started and not _title_active and not _ending_active \
		and not _loading_active and not _resume_mode and not _transitioning \
		and _segment != null

func _open_pause() -> void:
	if _pause_active:
		return
	# Keep the current first-person / third-person view: only V is allowed to
	# switch cameras. The mouse is only made visible for the menu.
	_pause_active = true
	AudioDirector.play_sfx("pause_open", -12.0)
	_pause_prev_locked = GameState.control_locked
	GameState.control_locked = true
	_autosave.stop()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_settings_page.visible = false
	_pause_menu.visible = true
	_pause_index = 0
	_refresh_pause_menu()

func _close_pause() -> void:
	if not _pause_active:
		return
	_pause_active = false
	_pause_menu.visible = false
	_settings_page.visible = false
	GameState.control_locked = _pause_prev_locked
	_autosave.start()
	AudioDirector.play_sfx("pause_close", -12.0)
	if _first_person:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _handle_pause_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
	if key == KEY_ESCAPE:
		_close_pause()
		get_viewport().set_input_as_handled()
	elif key == KEY_UP or key == KEY_W:
		_pause_index = wrapi(_pause_index - 1, 0, _pause_buttons.size())
		_refresh_pause_menu()
		get_viewport().set_input_as_handled()
	elif key == KEY_DOWN or key == KEY_S:
		_pause_index = wrapi(_pause_index + 1, 0, _pause_buttons.size())
		_refresh_pause_menu()
		get_viewport().set_input_as_handled()
	elif _is_confirm_event(event):
		_activate_pause()
		get_viewport().set_input_as_handled()

# =============================================================================
# BACKPACK
# =============================================================================

## Debug-only panel. Set to false (or delete scripts/dev/) for a release build.
const DEV_PANEL_ENABLED := true

const BACKPACK_ITEM_IDS := ["red", "yellow", "green", "blue", "purple", "orange", "pink", "teal", "creek_chime"]

func _build_backpack_page() -> void:
	_backpack_page = Control.new()
	_backpack_page.name = "BackpackPage"
	_backpack_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backpack_page.mouse_filter = Control.MOUSE_FILTER_STOP
	_backpack_page.visible = false
	_menu_layer.add_child(_backpack_page)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.045, 0.040, 0.034, 1.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backpack_page.add_child(bg)
	var title := _make_label(Vector2(0.0, 18.0), Vector2(640.0, 28.0), 20, ACCENT_COLOR,
		HORIZONTAL_ALIGNMENT_CENTER)
	title.text = "背 包"
	_backpack_page.add_child(title)
	var sub := _make_label(Vector2(0.0, 44.0), Vector2(640.0, 16.0), 9, DIM_COLOR,
		HORIZONTAL_ALIGNMENT_CENTER)
	sub.text = "八个路口，八件随身物，和一段溪畔记忆"
	_backpack_page.add_child(sub)

	# item slot buttons (2 columns x 4 rows)
	for i in BACKPACK_ITEM_IDS.size():
		var button := Button.new()
		button.position = Vector2(44.0 + float(i % 2) * 150.0, 74.0 + float(i / 2) * 40.0)
		button.size = Vector2(138.0, 30.0)
		_style_pixel_button(button, 11, Color(0.92, 0.88, 0.78, 1.0), ACCENT_COLOR)
		button.mouse_entered.connect(_on_backpack_hover.bind(i))
		button.pressed.connect(_on_backpack_pressed.bind(i))
		_backpack_page.add_child(button)
		_backpack_buttons.append(button)

	# dark frame behind the rotating 3D item preview
	var preview_border := ColorRect.new()
	preview_border.position = Vector2(354.0, 68.0)
	preview_border.size = Vector2(242.0, 184.0)
	preview_border.color = Color(0.10, 0.085, 0.070, 1.0)
	preview_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backpack_page.add_child(preview_border)
	var preview_bg := ColorRect.new()
	preview_bg.position = Vector2(357.0, 71.0)
	preview_bg.size = Vector2(236.0, 178.0)
	preview_bg.color = Color(0.055, 0.050, 0.044, 1.0)
	preview_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backpack_page.add_child(preview_bg)

	var container := SubViewportContainer.new()
	container.position = Vector2(357.0, 71.0)
	container.size = Vector2(236.0, 178.0)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backpack_page.add_child(container)

	_backpack_preview_viewport = SubViewport.new()
	_backpack_preview_viewport.size = Vector2i(236, 178)
	_backpack_preview_viewport.own_world_3d = true
	_backpack_preview_viewport.transparent_bg = false
	_backpack_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(_backpack_preview_viewport)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.055, 0.050, 0.044)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.92, 0.86, 0.74)
	env.ambient_light_energy = 0.9
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_backpack_preview_viewport.add_child(world_env)

	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 0.12, 0.92)
	cam.fov = 36.0
	_backpack_preview_viewport.add_child(cam)
	cam.look_at(Vector3(0.0, 0.0, 0.0))
	var key_light := OmniLight3D.new()
	key_light.position = Vector3(-0.8, 1.1, 1.2)
	key_light.light_energy = 1.2
	key_light.omni_range = 4.0
	_backpack_preview_viewport.add_child(key_light)
	var fill_light := OmniLight3D.new()
	fill_light.position = Vector3(0.9, 0.3, 0.7)
	fill_light.light_energy = 0.55
	fill_light.light_color = Color(0.78, 0.86, 1.0)
	fill_light.omni_range = 3.0
	_backpack_preview_viewport.add_child(fill_light)
	_backpack_preview_root = Node3D.new()
	_backpack_preview_viewport.add_child(_backpack_preview_root)

	_backpack_title = _make_label(Vector2(354.0, 258.0), Vector2(242.0, 22.0), 14,
		ACCENT_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	_backpack_page.add_child(_backpack_title)
	_backpack_desc = _make_label(Vector2(354.0, 280.0), Vector2(242.0, 38.0), 9,
		Color(0.76, 0.72, 0.64, 1.0), HORIZONTAL_ALIGNMENT_CENTER)
	_backpack_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_backpack_desc.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_backpack_page.add_child(_backpack_desc)

	var hint := _make_label(Vector2(0.0, 330.0), Vector2(640.0, 16.0), 9, DIM_COLOR,
		HORIZONTAL_ALIGNMENT_CENTER)
	hint.text = "B / E / Esc 关闭 · ↑↓←→ 选择 · 鼠标也可以点"
	_backpack_page.add_child(hint)

	_item_toast = _make_label(Vector2(110.0, 26.0), Vector2(420.0, 18.0), 11,
		Color(1.0, 0.92, 0.68, 1.0), HORIZONTAL_ALIGNMENT_CENTER)
	_item_toast.visible = false
	_item_toast.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.04, 1.0))
	_item_toast.add_theme_constant_override("outline_size", 3)
	_ui.add_child(_item_toast)

func _refresh_backpack() -> void:
	var selected_id: String = str(BACKPACK_ITEM_IDS[_backpack_index])
	for i in _backpack_buttons.size():
		var item_id: String = str(BACKPACK_ITEM_IDS[i])
		var owned := GameState.has_item(item_id)
		var selected := i == _backpack_index
		var data := Narrative.item(item_id)
		var text := "？？？"
		if owned:
			text = str(data.get("name", item_id))
		_backpack_buttons[i].text = ("> " if selected else "  ") + text
		var base_colour := Color(0.92, 0.88, 0.78, 1.0)
		if owned:
			base_colour = Narrative.color_of(item_id).lightened(0.35)
		_backpack_buttons[i].add_theme_color_override("font_color",
			ACCENT_COLOR if selected else (base_colour if owned else Color(0.42, 0.39, 0.34, 1.0)))
	var owned_selected := GameState.has_item(selected_id)
	var data_selected := Narrative.item(selected_id)
	if owned_selected:
		_backpack_title.text = str(data_selected.get("name", ""))
		_backpack_desc.text = str(data_selected.get("desc", ""))
	else:
		_backpack_title.text = "还没有得到"
		_backpack_desc.text = "和这位 NPC 好好聊完，他就会把随身物交给你。"
	_update_backpack_preview(selected_id if owned_selected else "")

func _update_backpack_preview(item_id: String) -> void:
	if _backpack_preview_root == null:
		return
	for child in _backpack_preview_root.get_children():
		child.queue_free()
	if item_id == "":
		return
	_backpack_preview_root.add_child(ItemModels.build(item_id))
	_backpack_preview_root.rotation.y = 0.0

func _on_backpack_hover(index: int) -> void:
	var previous := _backpack_index
	_backpack_index = clampi(index, 0, _backpack_buttons.size() - 1)
	if previous != _backpack_index:
		AudioDirector.play_sfx("ui_move", -20.0)
	_refresh_backpack()

func _on_backpack_pressed(index: int) -> void:
	_backpack_index = clampi(index, 0, _backpack_buttons.size() - 1)
	_refresh_backpack()

func _can_open_backpack() -> bool:
	return _run_started and not _title_active and not _ending_active \
		and not _loading_active and not _resume_mode and not _transitioning \
		and not _pause_active and _segment != null and not bool(_dialogue.call("is_open"))

func _open_backpack() -> void:
	if _backpack_active or not _can_open_backpack():
		return
	_backpack_active = true
	AudioDirector.play_sfx("backpack", -13.0)
	if _item_toast != null:
		_item_toast.visible = false
	_backpack_prev_locked = GameState.control_locked
	GameState.control_locked = true
	_autosave.stop()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	for i in BACKPACK_ITEM_IDS.size():
		if GameState.has_item(BACKPACK_ITEM_IDS[i]):
			_backpack_index = i
			break
	_backpack_page.visible = true
	_refresh_backpack()

func _close_backpack() -> void:
	if not _backpack_active:
		return
	_backpack_active = false
	AudioDirector.play_sfx("backpack", -15.0)
	_backpack_page.visible = false
	GameState.control_locked = _backpack_prev_locked
	_autosave.start()
	if _first_person:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _handle_backpack_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
	if key == KEY_ESCAPE or key == KEY_B or key == KEY_E:
		_close_backpack()
		get_viewport().set_input_as_handled()
	elif key == KEY_UP or key == KEY_W:
		_backpack_index = wrapi(_backpack_index - 2, 0, _backpack_buttons.size())
		_refresh_backpack()
		get_viewport().set_input_as_handled()
	elif key == KEY_DOWN or key == KEY_S:
		_backpack_index = wrapi(_backpack_index + 2, 0, _backpack_buttons.size())
		_refresh_backpack()
		get_viewport().set_input_as_handled()
	elif key == KEY_LEFT or key == KEY_A:
		_backpack_index = wrapi(_backpack_index - 1, 0, _backpack_buttons.size())
		_refresh_backpack()
		get_viewport().set_input_as_handled()
	elif key == KEY_RIGHT or key == KEY_D:
		_backpack_index = wrapi(_backpack_index + 1, 0, _backpack_buttons.size())
		_refresh_backpack()
		get_viewport().set_input_as_handled()

func _grant_npc_item(npc_id: String) -> void:
	if not GameState.add_item(npc_id):
		return
	var data := Narrative.item(npc_id)
	var item_name := str(data.get("name", npc_id))
	AudioDirector.play_sfx("pickup", -8.0, 1.04)
	if _item_toast == null:
		return
	_item_toast.text = "获得「%s」 · 按 B 打开背包" % item_name
	_item_toast.visible = true
	_item_toast.modulate.a = 0.0
	if _item_toast_tween != null:
		_item_toast_tween.kill()
	_item_toast_tween = create_tween()
	_item_toast_tween.tween_property(_item_toast, "modulate:a", 1.0, 0.25)
	_item_toast_tween.tween_interval(2.6)
	_item_toast_tween.tween_property(_item_toast, "modulate:a", 0.0, 0.6)

func _return_to_main_menu() -> void:
	_pause_active = false
	_pause_menu.visible = false
	_settings_page.visible = false
	if _run_started and not _ending_active:
		await _save_state(true)
	_autosave.stop()
	_free_segment()
	if _player != null:
		_player.global_position = Vector3(0.0, -20.0, 0.0)
	_run_started = false
	_segment_index = 0
	GameState.reset()
	if _charm_hud != null:
		_charm_hud.call("set_active", false)
	_show_title()

func _quit_from_pause() -> void:
	_pause_active = false
	_pause_menu.visible = false
	_settings_page.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_request_quit()

func _handle_title_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
	if key == KEY_ESCAPE:
		# Esc at the main menu never quits the game. Use the explicit
		# 「退出游戏」 entry when quitting is intended.
		get_viewport().set_input_as_handled()
	elif key == KEY_UP or key == KEY_W:
		_select_title_menu(_title_menu_index - 1)
		get_viewport().set_input_as_handled()
	elif key == KEY_DOWN or key == KEY_S:
		_select_title_menu(_title_menu_index + 1)
		get_viewport().set_input_as_handled()
	elif _is_confirm_event(event):
		_activate_title_menu()
		get_viewport().set_input_as_handled()

func _handle_settings_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
	if key == KEY_ESCAPE or key == KEY_BACKSPACE:
		_close_settings()
		get_viewport().set_input_as_handled()
	elif key == KEY_UP or key == KEY_W:
		_settings_index = wrapi(_settings_index - 1, 0, _settings_buttons.size())
		_refresh_settings()
		get_viewport().set_input_as_handled()
	elif key == KEY_DOWN or key == KEY_S:
		_settings_index = wrapi(_settings_index + 1, 0, _settings_buttons.size())
		_refresh_settings()
		get_viewport().set_input_as_handled()
	elif _is_confirm_event(event):
		_activate_settings()
		get_viewport().set_input_as_handled()

func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		_apply_settings()
		return
	_settings_volume = clampf(float(config.get_value("audio", "volume", 0.7)), 0.0, 1.0)
	_settings_fullscreen = bool(config.get_value("video", "fullscreen", true))
	# One-time migration: older configs defaulted to a windowed screen. The
	# game should now open fullscreen; after this migration the setting is
	# respected normally. v4 re-forces it once for existing installs that had
	# already saved "windowed".
	if not config.has_section_key("video", "fullscreen_default_v4"):
		_settings_fullscreen = true
		config.set_value("video", "fullscreen_default_v4", true)
		config.save(SETTINGS_PATH)
	_apply_settings()

func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "volume", _settings_volume)
	config.set_value("video", "fullscreen", _settings_fullscreen)
	config.set_value("video", "fullscreen_default_v4", true)
	config.save(SETTINGS_PATH)

func _apply_settings() -> void:
	var bus_index := AudioServer.get_bus_index("Master")
	if bus_index >= 0:
		AudioServer.set_bus_volume_db(bus_index,
			linear_to_db(maxf(_settings_volume, 0.001)))
	# Fullscreen is locked by project.godot (window/size/mode=3) at launch.
	# No runtime window-mode switching is allowed.

func _make_label(pos: Vector2, size: Vector2, font_size: int, color: Color, align: int) -> Label:
	font_size = maxi(11, int(round(float(font_size) * 1.10)))
	var label := Label.new()
	label.position = pos
	label.size = size
	label.set("horizontal_alignment", align)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _font != null:
		label.add_theme_font_override("font", _font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

# =============================================================================
# RUN FLOW
# =============================================================================

func _show_title() -> void:
	_hide_loading()
	if AudioDirector != null:
		AudioDirector.play_music("ambient")
	if _first_person:
		_set_first_person(false)
	_title_active = true
	_resume_mode = false
	_loading_active = false
	_run_started = false
	_title_screen.visible = true
	_ending_screen.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if _title_hint_label != null:
		_title_hint_label.text = ""
	if _settings_page != null:
		_settings_page.visible = false
	if _pause_menu != null:
		_pause_menu.visible = false
	_pause_active = false
	if _backpack_page != null:
		_backpack_page.visible = false
	_backpack_active = false
	if _item_toast != null:
		_item_toast.visible = false
	if _title_menu != null:
		_title_menu.visible = true
	_title_menu_index = 0
	_refresh_title_menu()
	if _charm_hud != null:
		_charm_hud.call("set_active", false)
	_fade.color = Color(0.0, 0.0, 0.0, 1.0)
	_fade.modulate.a = 0.0
	_title_time = 0.0
	_title_screen.modulate.a = 0.0
	var title_tween := create_tween()
	title_tween.tween_property(_title_screen, "modulate:a", 1.0, 1.1)
	if _start_overlay != null:
		_start_overlay.visible = false

func _start_run() -> void:
	_title_active = false
	_title_screen.visible = false
	if _pause_menu != null:
		_pause_menu.visible = false
	if _settings_page != null:
		_settings_page.visible = false
	_pause_active = false
	SaveSystem.clear()
	GameState.reset()
	GameState.control_locked = true
	_segment_index = 0
	_run_started = true
	_fade.color = Color(1.0, 0.99, 0.96, 1.0)
	_fade.modulate.a = 1.0
	_show_loading("正在进入…")
	AudioDirector.play_sfx("transition", -12.0, 1.1)
	await _wait(0.12)
	_load_segment(0)
	await _wait(0.22)
	_hide_loading()
	await _fade_in(0.9)
	_fade.color = Color(0.0, 0.0, 0.0, 1.0)
	if _charm_hud != null:
		_charm_hud.call("set_active", true)
		_charm_hud.call("set_color_instant", GameState.mixed_color())
	GameState.control_locked = false
	_autosave.start()

func _load_segment(index: int, spawn: Variant = null, start_resting: bool = false) -> void:
	_free_segment()
	_dialogue.call("force_close")
	_reset_dialogue_framing()
	GameState.dialogue_active = false
	_current_npc_id = ""
	var config: Dictionary = SegmentPresets.get_segment(index)
	var has_real: bool = ResourceLoader.exists(SEGMENT_SCENE_PATH)
	if has_real:
		_segment = load(SEGMENT_SCENE_PATH).instantiate()
	else:
		_segment = _build_fallback_segment()
	_segment_host.add_child(_segment)
	if has_real:
		_segment.call("setup", config)
	var spawn_pos: Vector3
	if spawn is Vector3:
		spawn_pos = spawn
	elif has_real:
		spawn_pos = _segment.call("get_player_start")
	else:
		spawn_pos = Vector3(0.0, 0.0, 22.0)
	_player.global_position = spawn_pos + Vector3(0.0, 0.05, 0.0)
	_player.velocity = Vector3.ZERO
	if has_real:
		_segment.connect("exit_reached", Callable(self, "_on_exit_reached"))
	_camera_rig.call("set_target", _player)
	_camera_rig.call("snap_to_target")
	_camera_rig.call("zoom_restore", 0.05)

	var npc_id := str(config.get("npc_id", ""))
	if npc_id != "":
		var npc_scene: Node3D = load(NPC_SCENE_PATH).instantiate()
		_segment_host.add_child(npc_scene)
		npc_scene.call("setup", npc_id, Narrative.npc(npc_id))
		if has_real:
			npc_scene.global_position = _segment.call("get_npc_position")
		else:
			npc_scene.global_position = Vector3(3.0, 0.0, 0.0)
		_npc = npc_scene
		if _npc_was_met(npc_id):
			npc_scene.set("talked", true)

	GameState.segment_index = index
	_segment_index = index
	_apply_scene_music()
	if start_resting:
		_player.enter_resting(false)
	else:
		_show_segment_title(str(config.get("title", "")))
		if bool(config.get("scenery_only", false)):
			var lines: Array = Narrative.MONOLOGUES.get(str(config.get("id", "")), [])
			if not lines.is_empty():
				_queue_monologue(lines)
	if _charm_hud != null:
		_charm_hud.call("set_active", true)
		_charm_hud.call("set_color_instant", GameState.mixed_color())
	if _run_started:
		_save_state(false)

## The watercolour filter is a style trial on the first segment only for now.
func _set_first_person(enabled: bool) -> void:
	if _first_person == enabled:
		return
	_first_person = enabled
	AudioDirector.play_sfx("camera", -15.0)
	if _camera_rig != null:
		_camera_rig.call("set_first_person", enabled)
	if _player != null:
		_player.call("set_first_person", enabled)

func _reset_dialogue_framing() -> void:
	if _camera_rig != null:
		_camera_rig.call("set_dialogue_framing", false)

func _free_segment() -> void:
	if _segment != null:
		_segment.queue_free()
		_segment = null
	if _npc != null:
		_npc.queue_free()
		_npc = null
	_current_npc_id = ""

func _queue_monologue(lines: Array) -> void:
	await get_tree().create_timer(1.4).timeout
	if _transitioning or _ending_active or not _run_started:
		return
	_open_dialogue(lines, "我", "")

func _on_exit_reached() -> void:
	if _transitioning or _ending_active:
		return
	_transitioning = true
	GameState.control_locked = true
	GameState.dialogue_active = false
	_current_npc_id = ""
	_dialogue.call("force_close")
	_prompt.visible = false
	AudioDirector.play_sfx("transition", -12.0)
	await _fade_out(0.6)
	_show_loading("正在前往下一段…")
	await _wait(0.12)
	_segment_index += 1
	if _segment_index >= SegmentPresets.count():
		_hide_loading()
		_show_ending()
	else:
		_load_segment(_segment_index)
		await _wait(0.22)
		_hide_loading()
		await _fade_in(0.8)
		GameState.control_locked = false
		_transitioning = false

func _show_ending() -> void:
	_hide_loading()
	AudioDirector.play_sfx("ending", -10.0, 0.95)
	# Do not change the camera on ending; only V may switch first/third person.
	_pause_active = false
	if _pause_menu != null:
		_pause_menu.visible = false
	if _settings_page != null:
		_settings_page.visible = false
	_ending_active = true
	if _charm_hud != null:
		_charm_hud.call("set_active", false)
	GameState.control_locked = true
	GameState.dialogue_active = false
	_prompt.visible = false
	_rest_hint.visible = false
	_autosave.stop()
	SaveSystem.clear()
	var data: Dictionary = Narrative.ending_for(GameState.color_ids())
	_ending_page = 0
	_portrait_layer.visible = false
	_ending_hint.text = "按 空格 查看性格画像"
	var ending_lines: Array = data.get("lines", [])
	_ending_body.add_theme_font_size_override("font_size", 12 if ending_lines.size() <= 4 else 10)
	_ending_title.text = "结 局 · " + str(data.get("title", ""))
	_ending_body.text = "\n".join(PackedStringArray(data.get("lines", [])))
	_ending_chip.color = GameState.mixed_color()
	var met_lines := PackedStringArray()
	for entry in GameState.met:
		var suffix := "（取色）" if bool(entry.get("took", false)) else "（未取）"
		met_lines.append(str(entry.get("name", "")) + suffix)
	if met_lines.is_empty():
		_ending_meta.text = "你没有遇见任何人。"
	else:
		_ending_meta.text = "遇见：" + " · ".join(met_lines)
	_ending_screen.visible = true
	_ending_screen.modulate.a = 0.0
	await _fade_in(0.7)
	var tween := create_tween()
	tween.tween_property(_ending_screen, "modulate:a", 1.0, 0.5)
	_transitioning = false

func _show_portrait_page() -> void:
	_ending_page = 1
	_populate_portrait()
	_portrait_layer.visible = true
	_ending_title.visible = false
	_ending_body.visible = false
	_ending_chip.visible = false
	_ending_meta.visible = false
	_ending_hint.visible = false
	_portrait_hint.text = "按 空格 重新走一遍"
	_portrait_title.text = "性格画像 · " + str(Narrative.portrait(GameState.color_ids()).get("title", "还在成形"))

func _populate_portrait() -> void:
	var data: Dictionary = Narrative.portrait(GameState.color_ids())
	var rows: Array = data.get("rows", [])
	for i in rows.size():
		if i >= _portrait_axis_labels.size():
			break
		var row: Dictionary = rows[i]
		var state := str(row.get("state", "none"))
		var a_color: Color = Narrative.color_of(str(Narrative.AXES[i]["a"]))
		var b_color: Color = Narrative.color_of(str(Narrative.AXES[i]["b"]))
		_portrait_axis_labels[i].text = str(row.get("label", ""))
		_portrait_a_labels[i].text = str(row.get("a_label", ""))
		_portrait_b_labels[i].text = str(row.get("b_label", ""))
		_portrait_a_swatches[i].color = Color(a_color.r, a_color.g, a_color.b, 1.0 if state in ["a", "both"] else 0.18)
		_portrait_b_swatches[i].color = Color(b_color.r, b_color.g, b_color.b, 1.0 if state in ["b", "both"] else 0.18)
		_portrait_a_labels[i].modulate = Color(1, 1, 1, 1.0 if state in ["a", "both"] else 0.35)
		_portrait_b_labels[i].modulate = Color(1, 1, 1, 1.0 if state in ["b", "both"] else 0.35)
	_portrait_summary.text = str(data.get("summary", ""))

func _enter_vision() -> void:
	# The post-ending "vision" is a separate high-resolution 3D scene. The main
	# run has already cleared its save and reached the ending, so changing the
	# scene is safe here.
	_show_loading("正在进入幻景…")
	AudioDirector.play_sfx("transition", -10.0, 0.9)
	await _wait(0.20)
	get_tree().change_scene_to_file("res://scenes/vision/vision.tscn")

func _restart() -> void:
	_launch_opening()

# =============================================================================
# DIALOGUE
# =============================================================================

func _process(delta: float) -> void:
	if _start_overlay != null and _start_overlay.visible:
		_update_start_sprite(delta)
		if _start_prompt.visible:
			_start_prompt.modulate.a = 0.55 + 0.45 * sin(Time.get_ticks_msec() * 0.004)
	if _title_active:
		_update_title_art(delta)
	if _backpack_active and _backpack_preview_root != null:
		_backpack_preview_root.rotation.y += delta * 0.85
	if _resume_mode or _loading_active:
		return
	if not _run_started or _ending_active or _transitioning:
		return
	# Robust exit trigger: the segment's Area3D normally fires first, but a
	# plain distance check keeps transitions working even if the area is missed
	# (e.g. after a teleport or a physics hiccup).
	var exit_config: Dictionary = SegmentPresets.get_segment(_segment_index)
	if not exit_config.is_empty():
		var exit_xz: Vector2 = exit_config.get("exit_position", Vector2.ZERO)
		var exit_world := Vector3(exit_xz.x, _player.global_position.y, exit_xz.y)
		if _player.global_position.distance_to(exit_world) < 3.0:
			_on_exit_reached()
			return
	var puzzle_prompt := ""
	if _segment != null and _segment.has_method("get_puzzle_prompt"):
		puzzle_prompt = str(_segment.call("get_puzzle_prompt", _player.global_position))
	if puzzle_prompt != "":
		_prompt.text = puzzle_prompt
		_prompt.visible = true
		if Input.is_action_just_pressed("interact"):
			var result: Variant = _segment.call("interact_puzzle", _player.global_position)
			_handle_puzzle_result(result)
		return
	if GameState.dialogue_active or _npc == null:
		_prompt.visible = false
		return
	if bool(_npc.get("talked")):
		_prompt.visible = false
		return
	var near := _player.global_position.distance_to(_npc.global_position) <= INTERACT_RADIUS
	_prompt.visible = near
	if near and Input.is_action_just_pressed("interact"):
		_start_npc_dialogue()

func _handle_puzzle_result(result: Variant) -> void:
	if not (result is Dictionary):
		return
	match str((result as Dictionary).get("event", "")):
		"solve":
			AudioDirector.play_sfx("puzzle_ok", -6.0)
		"wrong":
			AudioDirector.play_sfx("puzzle_wrong", -8.0)
		"step":
			AudioDirector.play_sfx("puzzle_step", -8.0)
	if bool((result as Dictionary).get("give_item", false)):
		_grant_npc_item("creek_chime")
	var lines: Array = (result as Dictionary).get("lines", [])
	if not lines.is_empty():
		_open_dialogue(lines, "我", "")

func _apply_scene_music() -> void:
	if AudioDirector == null:
		return
	# A dedicated, more melodic theme for the creek scene; the rest of the walk
	# keeps the quiet ambient bed.
	AudioDirector.play_music("creek" if _segment_index == 3 else "ambient")

func _start_npc_dialogue() -> void:
	if _npc == null:
		return
	var npc_id := str(_npc.get("npc_id"))
	var data: Dictionary = Narrative.npc(npc_id)
	if data.is_empty():
		return
	_npc_score = 0
	AudioDirector.play_sfx("talk", -9.0)
	_open_dialogue(data.get("beats", []), str(data.get("name", "")), npc_id)

func _on_choice_made(weight: int) -> void:
	_npc_score += weight

func _open_dialogue(beats: Array, speaker: String, npc_id: String) -> void:
	if bool(_dialogue.call("is_open")):
		return
	# Dialogue keeps the current first-person / overview framing.
	# Lift the hero out from behind the dialogue panel.
	_camera_rig.call("set_dialogue_framing", true)
	_current_npc_id = npc_id
	GameState.control_locked = true
	GameState.dialogue_active = true
	_prompt.visible = false
	var portrait: Texture2D = null
	var tint := Color.WHITE
	var charm_overlay: Texture2D = null
	if npc_id != "":
		portrait = _load_optional_texture("res://assets/generated/portrait_%s.png" % npc_id)
	else:
		portrait = _load_optional_texture("res://assets/generated/portrait_player.png")
		# The white bust stays white; only the little heart charm is tinted.
		charm_overlay = _load_optional_texture("res://assets/generated/portrait_player_charm.png")
	_dialogue.call("start", beats, speaker, portrait, tint)
	if charm_overlay != null:
		_dialogue.call("set_charm_overlay", charm_overlay, GameState.mixed_color())

func _on_final_choice(yes: bool) -> void:
	if _current_npc_id == "":
		return
	var data: Dictionary = Narrative.npc(_current_npc_id)
	var npc_color := Narrative.color_of(_current_npc_id)
	if yes:
		GameState.dye(_current_npc_id, npc_color)
		_grant_npc_item(_current_npc_id)
		_play_dye_feedback()
	GameState.record_met(_current_npc_id, str(data.get("name", "")), npc_color, yes)

func _on_dialogue_finished() -> void:
	GameState.control_locked = false
	GameState.dialogue_active = false
	if _npc != null and _current_npc_id != "":
		var npc_id := _current_npc_id
		var data: Dictionary = Narrative.npc(npc_id)
		var npc_color := Narrative.color_of(npc_id)
		# The judgement is silent: it comes from how the whole conversation
		# went, not from a final yes/no question.
		var took := _npc_score >= 1
		GameState.record_met(npc_id, str(data.get("name", "")), npc_color, took)
		if took:
			GameState.dye(npc_id, npc_color)
			_play_dye_feedback()
		# Every NPC gives one personal keepsake after the conversation, even
		# if the player did not take their colour.
		_grant_npc_item(npc_id)
		_npc.set("talked", true)
		_current_npc_id = ""
		_save_state(false)
		# One quiet inner line so the player can read what the conversation
		# decided without being asked to self-identify.
		GameState.control_locked = true
		GameState.dialogue_active = true
		await get_tree().create_timer(0.45).timeout
		GameState.dialogue_active = false
		_open_dialogue(Narrative.result_lines(npc_id, took), "我", "")
		return
	if _camera_rig != null:
		_camera_rig.call("set_dialogue_framing", false)
	_save_state(false)

func _on_color_changed(mixed: Color) -> void:
	# The white hero never tints; the liquid charm is what takes the colour.
	if _charm_hud != null:
		_charm_hud.call("animate_color", mixed)

# =============================================================================
# HELPERS
# =============================================================================

func _show_segment_title(title: String) -> void:
	if title == "":
		return
	_segment_title.text = title
	_segment_title.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(_segment_title, "modulate:a", 1.0, 0.6)
	tween.tween_interval(1.6)
	tween.tween_property(_segment_title, "modulate:a", 0.0, 0.9)

func _fade_out(duration: float) -> void:
	var tween := create_tween()
	tween.tween_property(_fade, "modulate:a", 1.0, duration)
	await tween.finished

func _fade_in(duration: float) -> void:
	var tween := create_tween()
	tween.tween_property(_fade, "modulate:a", 0.0, duration)
	await tween.finished

func _load_font() -> Font:
	if ResourceLoader.exists(FONT_PATH):
		var res := load(FONT_PATH)
		if res is Font:
			return res
	return ThemeDB.fallback_font

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and _dev_panel != null:
		var dev_key: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		if dev_key == KEY_F1 or dev_key == KEY_QUOTELEFT:
			if _dev_panel.visible:
				_dev_panel.call("close_panel")
			else:
				_dev_panel.call("open_panel")
			get_viewport().set_input_as_handled()
			return
	if _dev_panel != null and _dev_panel.visible:
		return
	if _backpack_active:
		_handle_backpack_input(event)
		return
	if _pause_active:
		if _settings_page != null and _settings_page.visible:
			_handle_settings_input(event)
		else:
			_handle_pause_input(event)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var pause_key: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		if pause_key == KEY_ESCAPE and _can_pause():
			_open_pause()
			get_viewport().set_input_as_handled()
			return
	if not (_resume_mode or _title_active or _ending_active) and _run_started \
			and not _loading_active and not bool(_dialogue.call("is_open")):
		if event is InputEventKey and event.pressed and not event.echo:
			var toggle_key: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
			if toggle_key == KEY_B or (toggle_key == KEY_E and _prompt != null and not _prompt.visible):
				_open_backpack()
				get_viewport().set_input_as_handled()
				return
			if toggle_key == KEY_V:
				_set_first_person(not _first_person)
				get_viewport().set_input_as_handled()
				return
	if _resume_mode:
		if _loading_active:
			return
		if event is InputEventKey and event.pressed and not event.echo:
			var resume_key: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
			if resume_key == KEY_R:
				_start_fresh_from_resume()
				get_viewport().set_input_as_handled()
				return
		if _is_confirm_event(event):
			_start_from_resume()
			get_viewport().set_input_as_handled()
		return
	if _title_active:
		if _settings_page != null and _settings_page.visible:
			_handle_settings_input(event)
		else:
			_handle_title_input(event)
		return
	elif _ending_active:
		if _is_confirm_event(event):
			if _ending_page == 0:
				_show_portrait_page()
			else:
				_restart()
			get_viewport().set_input_as_handled()

func _is_confirm_event(event: InputEvent) -> bool:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		if key == KEY_SPACE or key == KEY_ENTER or key == KEY_KP_ENTER or key == KEY_E:
			return true
	return event.is_action_pressed("ui_accept") or event.is_action_pressed("interact") or event.is_action_pressed("jump")

# --- fallback segment (used only until the real segment builder lands) ------

func _build_fallback_segment() -> Node3D:
	var root := Node3D.new()
	root.name = "FallbackSegment"
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(70.0, 70.0)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	if ResourceLoader.exists(GROUND_TEXTURE):
		mat.albedo_texture = load(GROUND_TEXTURE)
		mat.uv1_scale = Vector3(6.0, 6.0, 1.0)
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	else:
		mat.albedo_color = Color(0.30, 0.43, 0.21)
	mat.roughness = 1.0
	ground.material_override = mat
	root.add_child(ground)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(70.0, 2.0, 70.0)
	col.shape = box
	col.position.y = -1.0
	body.add_child(col)
	root.add_child(body)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40.0, -33.0, 0.0)
	sun.shadow_enabled = true
	root.add_child(sun)
	# exit marker at the far end
	var exit_area := Area3D.new()
	var exit_shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 2.5
	exit_shape.shape = sphere
	exit_area.add_child(exit_shape)
	exit_area.position = Vector3(0.0, 0.0, -25.0)
	root.add_child(exit_area)
	exit_area.body_entered.connect(func(b: Node3D) -> void:
		if b.is_in_group("player"):
			call_deferred("_on_exit_reached")
	)
	return root

# =============================================================================
# RESUME FROM LAST SESSION (start overlay + loading beat)
# =============================================================================

func _enter_resume_mode() -> void:
	_save_data = SaveSystem.read()
	if _save_data.is_empty():
		_show_title()
		return
	# The background shot is only trustworthy for the segment it was taken in.
	if int(_save_data.get("screen_segment", -1)) != int(_save_data.get("segment_index", 0)):
		_save_data.erase("screen")
	_resume_mode = true
	_title_active = false
	_run_started = false
	_title_screen.visible = false
	_ending_screen.visible = false
	if _pause_menu != null:
		_pause_menu.visible = false
	if _settings_page != null:
		_settings_page.visible = false
	_pause_active = false
	_fade.modulate.a = 0.0
	_apply_save_state()
	_build_start_overlay()
	_start_overlay.visible = true
	_start_overlay.modulate.a = 1.0
	_start_phase = "sit"
	_start_sprite_time = 0.0
	var seg_index := int(_save_data.get("segment_index", 0))
	var seg_title := str(SegmentPresets.get_segment(seg_index).get("title", ""))
	_start_title.text = "上次停在 · " + seg_title
	_start_title.visible = true
	_start_prompt.visible = true
	_start_hint.visible = true
	_loading_label.visible = false
	_update_start_sprite(0.0)

func _apply_save_state() -> void:
	GameState.reset()
	var colors = _save_data.get("colors", [])
	if colors is Array:
		for id in colors:
			GameState.dye(str(id), Narrative.color_of(str(id)))
	var saved_items = _save_data.get("items", [])
	if saved_items is Array:
		GameState.set_items(saved_items)
	var met = _save_data.get("met", [])
	if met is Array:
		for entry in met:
			if entry is Dictionary:
				var npc_id := str(entry.get("id", ""))
				GameState.record_met(npc_id, str(entry.get("name", "")), Narrative.color_of(npc_id), bool(entry.get("took", false)))

func _build_start_overlay() -> void:
	_start_layer = CanvasLayer.new()
	_start_layer.layer = 40
	add_child(_start_layer)
	_start_overlay = Control.new()
	_start_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_start_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_start_layer.add_child(_start_overlay)

	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.045, 0.05, 0.06, 1.0)
	_start_overlay.add_child(backdrop)

	var screen_pos := Vector2(320.0, 300.0)
	if _save_data.has("screen"):
		var saved = _save_data.get("screen")
		if saved is Array and (saved as Array).size() >= 2:
			screen_pos = Vector2(float(saved[0]), float(saved[1]))
		var shot := SaveSystem.read_screenshot()
		if shot != null:
			_start_shot = TextureRect.new()
			_start_shot.texture = shot
			_start_shot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			_start_shot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			_start_shot.stretch_mode = TextureRect.STRETCH_SCALE
			_start_shot.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			_start_overlay.add_child(_start_shot)

	var rest_tex := _load_optional_texture(REST_SHEET_PATH)
	_start_has_rest = rest_tex != null
	_start_sprite = Sprite2D.new()
	_start_sprite.centered = false
	_start_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if _start_has_rest:
		_start_sprite.texture = rest_tex
		_start_sprite.hframes = 8
		_start_sprite.frame = 0
	else:
		_start_sprite.texture = _load_optional_texture(PLAYER_SHEET_PATH)
		_start_sprite.hframes = 4
		_start_sprite.vframes = 4
		_start_sprite.frame = 0
	_start_sprite.position = screen_pos - Vector2(16.0, 48.0)
	_start_sprite.modulate = Color.WHITE
	_start_overlay.add_child(_start_sprite)

	# A faint veil so the labels read on top of the last frame.
	var veil := ColorRect.new()
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(0.0, 0.0, 0.0, 0.12)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_start_overlay.add_child(veil)

	_start_title = _make_label(Vector2(0.0, 34.0), Vector2(640.0, 20.0), 12, DIM_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	_start_title.text = ""
	_start_overlay.add_child(_start_title)

	_start_prompt = _make_label(Vector2(0.0, 278.0), Vector2(640.0, 24.0), 14, ACCENT_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	_start_prompt.text = "按 空格 / E 开始"
	_start_overlay.add_child(_start_prompt)

	_start_hint = _make_label(Vector2(0.0, 308.0), Vector2(640.0, 18.0), 10, DIM_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	_start_hint.text = "R · 从头开始"
	_start_overlay.add_child(_start_hint)

	_loading_label = _make_label(Vector2(0.0, 308.0), Vector2(640.0, 20.0), 12, TEXT_COLOR, HORIZONTAL_ALIGNMENT_CENTER)
	_loading_label.text = "加 载 中 ..."
	_loading_label.visible = false
	_start_overlay.add_child(_loading_label)

func _update_start_sprite(delta: float) -> void:
	if _start_sprite == null:
		return
	_start_sprite_time += delta
	if not _start_has_rest:
		_start_sprite.frame = 0
		return
	match _start_phase:
		"sit":
			_set_start_frame(1 if int(_start_sprite_time * 0.9) % 2 == 0 else 0)
		"attempt":
			var frames := [5, 6, 5, 0]
			var index := mini(int(_start_sprite_time / 0.35), frames.size() - 1)
			_set_start_frame(int(frames[index]))
			if _start_sprite_time >= 1.6:
				_set_start_phase("lie")
		"lie":
			# 先播一下"倒下去"的过渡帧，避免从坐着直接硬切到躺着。
			if _start_sprite_time < 0.3:
				_set_start_frame(2)
			else:
				_set_start_frame(4 if int(_start_sprite_time * 0.9) % 2 == 0 else 3)
		"rise":
			# Loading is done: sit up before the live scene hands over, so the
			# character never stays lying on the ground after the overlay.
			var rise_frames := [6, 5, 0]
			var rise_index := mini(int(_start_sprite_time / 0.22), rise_frames.size() - 1)
			_set_start_frame(int(rise_frames[rise_index]))
			if _start_sprite_time >= 0.66:
				_set_start_phase("sit")

func _set_start_frame(frame: int) -> void:
	if _start_sprite != null and _start_has_rest:
		_start_sprite.frame = frame

func _set_start_phase(phase: String) -> void:
	_start_phase = phase
	_start_sprite_time = 0.0

func _start_from_resume() -> void:
	if not _resume_mode or _loading_active:
		return
	_loading_active = true
	_start_prompt.visible = false
	_start_hint.visible = false
	_start_title.visible = false
	_loading_label.visible = true
	_set_start_phase("attempt")
	await _wait(1.6)
	_set_start_phase("lie")
	var spawn := Vector3(0.0, 0.0, 0.0)
	var saved_pos = _save_data.get("player_pos")
	if saved_pos is Array and (saved_pos as Array).size() >= 3:
		spawn = Vector3(float(saved_pos[0]), float(saved_pos[1]), float(saved_pos[2]))
	var started := Time.get_ticks_msec()
	_load_segment(int(_save_data.get("segment_index", 0)), spawn, true)
	var build_seconds := float(Time.get_ticks_msec() - started) / 1000.0
	var hold := maxf(0.5, LOADING_MIN_SECONDS - 1.6 - build_seconds)
	await _wait(hold)
	_set_start_phase("rise")
	await _wait(0.68)
	var tween := create_tween()
	tween.tween_property(_start_overlay, "modulate:a", 0.0, 0.6)
	await tween.finished
	_start_overlay.visible = false
	_loading_label.visible = false
	_resume_mode = false
	_loading_active = false
	_run_started = true
	if _charm_hud != null:
		_charm_hud.call("set_active", true)
		_charm_hud.call("set_color_instant", GameState.mixed_color())
	GameState.control_locked = false
	_autosave.start()
	if _player.is_resting():
		# The hero was seated under the overlay; get them up on their own so
		# loading never leaves them lying/sitting forever.
		await _wait(0.85)
		if _player.is_seated():
			_player.begin_stand_up()
	_save_state(false)

func _start_fresh_from_resume() -> void:
	if _loading_active:
		return
	SaveSystem.clear()
	_resume_mode = false
	_loading_active = false
	_start_overlay.visible = false
	_loading_label.visible = false
	_title_active = false
	_run_started = true
	GameState.reset()
	GameState.control_locked = true
	_segment_index = 0
	_fade.modulate.a = 1.0
	_load_segment(0)
	await _fade_in(0.9)
	GameState.control_locked = false
	_autosave.start()

func _show_rest_hint() -> void:
	_rest_hint.visible = true
	_rest_hint.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(3.0)
	tween.tween_property(_rest_hint, "modulate:a", 0.0, 0.8)

func _on_player_stood_up() -> void:
	_rest_hint.visible = false
	_save_state(false)

# =============================================================================
# SAVE / QUIT
# =============================================================================

func _save_state(capture_screenshot: bool) -> void:
	if not _run_started or _ending_active or _loading_active:
		return
	if _segment == null or _player == null:
		return
	var payload := {
		"segment_index": _segment_index,
		"player_pos": [_player.global_position.x, _player.global_position.y, _player.global_position.z],
		"colors": GameState.color_ids(),
		"items": GameState.item_ids(),
		"met": [],
	}
	var met_entries: Array = []
	for entry in GameState.met:
		met_entries.append({
			"id": str(entry.get("id", "")),
			"name": str(entry.get("name", "")),
			"took": bool(entry.get("took", false)),
		})
	payload["met"] = met_entries
	if capture_screenshot:
		var screen_pos := _camera.unproject_position(_player.global_position)
		payload["screen"] = [screen_pos.x, screen_pos.y]
		payload["screen_segment"] = _segment_index
		var image := await _capture_clean_frame()
		SaveSystem.write(payload, image)
	else:
		# Autosave keeps the last captured frame/anchor so a resume still has a
		# background even if the process is killed before the quit screenshot.
		var existing := SaveSystem.read()
		if existing.has("screen") and existing.has("screen_segment"):
			payload["screen"] = existing["screen"]
			payload["screen_segment"] = existing["screen_segment"]
		SaveSystem.write(payload, null)

func _capture_clean_frame() -> Image:
	_player.set_hidden_for_screenshot(true)
	_prompt.visible = false
	_segment_title.visible = false
	_rest_hint.visible = false
	if bool(_dialogue.call("is_open")):
		_dialogue.call("force_close")
	GameState.dialogue_active = false
	await get_tree().process_frame
	await get_tree().process_frame
	var image: Image = get_viewport().get_texture().get_image()
	_player.set_hidden_for_screenshot(false)
	return image

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_request_quit()

func _request_quit() -> void:
	if _quitting:
		return
	_quitting = true
	if _first_person:
		_set_first_person(false)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if _run_started and not _ending_active and not _loading_active and _segment != null and not _resume_mode:
		GameState.control_locked = true
		_player.sit_down_animation()
		await _wait(0.8)
		await _save_state(true)
	get_tree().quit()

func _on_autosave_tick() -> void:
	_save_state(false)

func _npc_was_met(npc_id: String) -> bool:
	for entry in GameState.met:
		if str(entry.get("id", "")) == npc_id:
			return true
	return false

func _play_dye_feedback() -> void:
	AudioDirector.play_sfx("color", -8.0, 1.03)
	# No body tint / camera lunge: the highlight is the charm taking the colour.
	if _charm_hud != null:
		_charm_hud.call("pulse")
	_flash.visible = true
	_flash.modulate.a = 0.0
	var flash_tween := create_tween()
	flash_tween.tween_property(_flash, "modulate:a", 0.18, 0.15)
	flash_tween.tween_property(_flash, "modulate:a", 0.0, 0.50)
	await _wait(0.55)

# =============================================================================
# DEV CHEATS (debug builds only)
# =============================================================================

func dev_get_speed() -> float:
	if _player == null:
		return 1.0
	return float(_player.get("_dev_speed_mult"))

func dev_set_speed(value: float) -> void:
	if _player != null:
		_player.call("set_dev_speed", value)

func dev_get_fly() -> bool:
	return _player != null and bool(_player.get("_dev_fly"))

func dev_set_fly(enabled: bool) -> void:
	if _player != null:
		_player.call("set_dev_fly", enabled)

func dev_get_noclip() -> bool:
	return _player != null and bool(_player.get("_dev_noclip"))

func dev_set_noclip(enabled: bool) -> void:
	if _player != null:
		_player.call("set_dev_noclip", enabled)

func dev_get_infinite_jump() -> bool:
	return _player != null and bool(_player.get("_dev_infinite_jump"))

func dev_set_infinite_jump(enabled: bool) -> void:
	if _player != null:
		_player.call("set_dev_infinite_jump", enabled)

func dev_skip_dialogue() -> void:
	if _dialogue != null and bool(_dialogue.call("is_open")):
		_dialogue.call("force_close")
	GameState.dialogue_active = false
	GameState.control_locked = false
	_reset_dialogue_framing()
	if _prompt != null:
		_prompt.visible = false

func dev_teleport_exit() -> void:
	var config: Dictionary = SegmentPresets.get_segment(_segment_index)
	if config.is_empty() or _player == null:
		return
	var exit_xz: Vector2 = config.get("exit_position", Vector2.ZERO)
	_player.global_position = Vector3(exit_xz.x, _player.global_position.y + 0.2, exit_xz.y)
	_on_exit_reached()

func dev_next_segment() -> void:
	if _segment_index + 1 < SegmentPresets.count():
		dev_jump_segment(_segment_index + 1)
	else:
		dev_trigger_ending()

func dev_jump_segment(index: int) -> void:
	if index < 0 or index >= SegmentPresets.count():
		return
	if _dev_panel != null:
		_dev_panel.call("close_panel")
	_dialogue.call("force_close")
	GameState.dialogue_active = false
	GameState.control_locked = false
	_transitioning = false
	_ending_active = false
	_ending_page = 0
	_run_started = true
	_title_active = false
	_pause_active = false
	_resume_mode = false
	_title_screen.visible = false
	_ending_screen.visible = false
	if _portrait_layer != null:
		_portrait_layer.visible = false
	if _pause_menu != null:
		_pause_menu.visible = false
	if _settings_page != null:
		_settings_page.visible = false
	if _backpack_page != null:
		_backpack_page.visible = false
	_backpack_active = false
	if _charm_hud != null:
		_charm_hud.call("set_active", true)
	_fade.modulate.a = 0.0
	_load_segment(index)
	_fade.modulate.a = 0.0
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if _first_person else Input.MOUSE_MODE_VISIBLE)

func dev_grant_all_colors() -> void:
	for id in GameState.COLOR_ORDER:
		if GameState.has_color(id):
			continue
		var colour: Color = Narrative.color_of(id)
		var npc_name := str(Narrative.npc(id).get("name", id))
		GameState.dye(id, colour)
		GameState.record_met(id, npc_name, colour, true)
	AudioDirector.play_sfx("color", -8.0)
	_on_color_changed(GameState.mixed_color())

func dev_grant_all_items() -> void:
	for item_id in BACKPACK_ITEM_IDS:
		GameState.add_item(item_id)
	AudioDirector.play_sfx("pickup", -8.0)

func dev_clear_colors() -> void:
	GameState.chosen.clear()
	GameState.met.clear()
	GameState.color_changed.emit(GameState.mixed_color())
	if _charm_hud != null:
		_charm_hud.call("set_color_instant", GameState.mixed_color())

func dev_trigger_ending() -> void:
	if _dev_panel != null:
		_dev_panel.call("close_panel")
	_dialogue.call("force_close")
	GameState.dialogue_active = false
	GameState.control_locked = false
	_transitioning = false
	_ending_active = false
	_show_ending()

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func _load_optional_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var res := load(path)
		if res is Texture2D:
			return res
	return null
