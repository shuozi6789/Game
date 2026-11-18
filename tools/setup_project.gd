extends SceneTree
## One-shot project bootstrap: registers the input map and a few engine settings,
## then rewrites project.godot.
## Run: Godot --headless --path <project> --script res://tools/setup_project.gd

func _init() -> void:
	_add_action(&"move_up", [KEY_W, KEY_UP])
	_add_action(&"move_down", [KEY_S, KEY_DOWN])
	_add_action(&"move_left", [KEY_A, KEY_LEFT])
	_add_action(&"move_right", [KEY_D, KEY_RIGHT])
	_add_action(&"jump", [KEY_SPACE])
	_add_action(&"sprint", [KEY_SHIFT])
	_add_action(&"interact", [KEY_E])
	_add_action(&"debug_toggle", [KEY_F1])

	# Global run state singleton.
	ProjectSettings.set_setting("autoload/GameState", "*res://scripts/game/game_state.gd")

	# Crisp pixel-art defaults.
	ProjectSettings.set_setting("rendering/textures/canvas_textures/default_texture_filter", 0)
	ProjectSettings.set_setting("rendering/renderer/rendering_method", "forward_plus")
	ProjectSettings.set_setting("rendering/anti_aliasing/quality/msaa_3d", 0)
	ProjectSettings.set_setting("rendering/lights_and_shadows/directional_shadow/size", 4096)
	ProjectSettings.set_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality", 3)
	# Keep the 3D scene rendering at the low base resolution for the pixel look.
	ProjectSettings.set_setting("display/window/stretch/mode", "viewport")
	ProjectSettings.set_setting("display/window/stretch/scale_mode", "integer")
	ProjectSettings.set_setting("display/window/size/viewport_width", 640)
	ProjectSettings.set_setting("display/window/size/viewport_height", 360)

	# Enabled editor plugins (installed by plugin-scout). GUT is dev-only and
	# Dialogic is an alpha that adds autoloads, so both stay disabled by default.
	ProjectSettings.set_setting("editor_plugins/enabled", PackedStringArray([
		"res://addons/phantom_camera/plugin.cfg",
		"res://addons/AsepriteWizard/plugin.cfg",
	]))

	var err := ProjectSettings.save()
	if err == OK:
		print("[setup_project] project.godot saved OK")
	else:
		printerr("[setup_project] ProjectSettings.save() failed: ", err)
	quit()

func _add_action(action: StringName, keys: Array) -> void:
	var events: Array = []
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		ev.device = -1 # match events from any device
		events.append(ev)
	ProjectSettings.set_setting("input/" + String(action), {"deadzone": 0.2, "events": events})
