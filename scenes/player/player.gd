extends CharacterBody3D
## HD2D wooden puppet hero (heart-shaped cavity in the chest).
## - walk sheet: 4 directions x 4 frames (rows down/left/right/up)
## - rest sheet: 8 frames (sit / breathe / lie down / lying / breathe / rise x2 / stand)
## The puppet carries an empty heart-shaped cavity; colours are still shown by
## the heart HUD and by the cavity story rather than by tinting the sprite.

signal stand_up_finished

@export_group("Movement")
@export var walk_speed: float = 4.2
@export var sprint_speed: float = 6.8
@export var acceleration: float = 24.0
@export var friction: float = 30.0
@export var jump_velocity: float = 7.2
@export var gravity: float = 24.0

@export_group("Presentation")
@export var sheet_path: String = "res://assets/generated/player_puppet_8dir.png"
@export var rest_sheet_path: String = "res://assets/generated/player_puppet_rest.png"
@export var shadow_path: String = "res://assets/generated/blob_shadow.png"
@export var anim_fps: float = 9.0
@export var pixel_size: float = 0.025
@export var frame_height_px: int = 48
@export var sheet_rows: int = 8
@export var sheet_cols: int = 4

# Row order of player_puppet_8dir.png:
# down, down-right, right, up-right, up, up-left, left, down-left.
const DIR_DOWN := 0
const DIR_DOWN_RIGHT := 1
const DIR_RIGHT := 2
const DIR_UP_RIGHT := 3
const DIR_UP := 4
const DIR_UP_LEFT := 5
const DIR_LEFT := 6
const DIR_DOWN_LEFT := 7

const REST_FRAMES := 8
const REST_SIT := 0
const REST_SIT_BREATHE := 1
const REST_LIE_DOWN := 2
const REST_LYING := 3
const REST_LYING_BREATHE := 4
const REST_RISE_1 := 5
const REST_RISE_2 := 6
const REST_STAND := 7

enum Pose { NORMAL, RESTING, STANDING_UP, SITTING_DOWN }

@onready var sprite: Sprite3D = $Sprite3D
@onready var shadow: MeshInstance3D = $Shadow

var pose: Pose = Pose.NORMAL
var _facing: int = DIR_DOWN
var _anim_time: float = 0.0
var _pose_time: float = 0.0
var _pose_frame_time: float = 0.0
var _normal_texture: Texture2D
var _rest_texture: Texture2D
var _shadow_material: StandardMaterial3D
var _shadow_ground_y: float = 0.0
var _first_person: bool = false
var _lying: bool = false
var _pose_steps: Array = []
var _pose_step_index := 0
var _pose_step_timer := 0.0
var _step_sfx_timer := 0.0
var _was_on_floor := true
var _dev_fly := false
var _dev_noclip := false
var _dev_speed_mult := 1.0
var _dev_infinite_jump := false
var _base_collision_mask := 1

func _ready() -> void:
	_setup_sprite()
	_setup_shadow()
	_shadow_ground_y = global_position.y
	# The hero stays white; the HUD heart charm carries the colours.

# =============================================================================
# MOVEMENT
# =============================================================================

func _physics_process(delta: float) -> void:
	if GameState.control_locked or pose != Pose.NORMAL:
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= gravity * delta
		move_and_slide()
		if is_on_floor():
			_shadow_ground_y = global_position.y
		_animate(delta, false)
		# While resting, the first movement input gets the hero up.
		if pose == Pose.RESTING and _movement_pressed():
			begin_stand_up()
		return

	if _dev_fly or _dev_noclip:
		var fly_input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		var fly_camera := get_viewport().get_camera_3d()
		var fly_dir: Vector3
		if fly_camera != null:
			var fwd := -fly_camera.global_transform.basis.z
			fwd.y = 0.0
			fwd = fwd.normalized()
			var right := fly_camera.global_transform.basis.x
			right.y = 0.0
			right = right.normalized()
			fly_dir = right * fly_input.x + fwd * (-fly_input.y)
		else:
			fly_dir = Vector3(fly_input.x, 0.0, fly_input.y)
		if _dev_fly:
			if Input.is_action_pressed("jump"):
				fly_dir.y += 1.0
			if Input.is_action_pressed("sprint"):
				fly_dir.y -= 1.0
		var fly_speed := walk_speed * _dev_speed_mult
		velocity = fly_dir.normalized() * fly_speed if fly_dir.length_squared() > 0.001 else Vector3.ZERO
		move_and_slide()
		_update_facing(fly_dir)
		_animate(delta, fly_dir.length_squared() > 0.001)
		return

	if not is_on_floor():
		velocity.y -= gravity * delta

	# Camera-relative input: in the overview this matches the old fixed mapping,
	# and in first person W/S/A/D follow the mouse yaw.
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var camera := get_viewport().get_camera_3d()
	var dir: Vector3
	if camera != null:
		var forward := -camera.global_transform.basis.z
		forward.y = 0.0
		forward = forward.normalized()
		var right := camera.global_transform.basis.x
		right.y = 0.0
		right = right.normalized()
		dir = (right * input.x + forward * (-input.y)).normalized()
	else:
		dir = Vector3(input.x, 0.0, input.y)
	var speed := (sprint_speed if Input.is_action_pressed("sprint") else walk_speed) * _dev_speed_mult
	var target := dir * speed
	var rate := acceleration if dir.length_squared() > 0.0001 else friction
	velocity.x = move_toward(velocity.x, target.x, rate * delta)
	velocity.z = move_toward(velocity.z, target.z, rate * delta)

	if Input.is_action_just_pressed("jump") and (is_on_floor() or _dev_infinite_jump):
		velocity.y = jump_velocity
		AudioDirector.play_sfx("jump", -12.0)

	move_and_slide()
	if is_on_floor():
		_shadow_ground_y = global_position.y
	var grounded := is_on_floor()
	if grounded and not _was_on_floor:
		AudioDirector.play_sfx("land", -13.0)
	_was_on_floor = grounded
	var planar_speed := Vector2(velocity.x, velocity.z).length()
	if grounded and planar_speed > 0.35:
		_step_sfx_timer -= delta
		if _step_sfx_timer <= 0.0:
			_step_sfx_timer = 0.30 if planar_speed < sprint_speed * 0.7 else 0.21
			var step_id := "footstep_a" if randf() < 0.5 else "footstep_b"
			AudioDirector.play_sfx(step_id, -16.0, randf_range(0.88, 1.12))
	else:
		_step_sfx_timer = 0.0

	var moving := Vector2(velocity.x, velocity.z).length() > 0.25
	_update_facing(dir)
	_animate(delta, moving)

func set_dev_fly(enabled: bool) -> void:
	_dev_fly = enabled
	collision_mask = 0 if (_dev_fly or _dev_noclip) else _base_collision_mask
	if enabled:
		velocity.y = 0.0

func set_dev_noclip(enabled: bool) -> void:
	_dev_noclip = enabled
	collision_mask = 0 if (_dev_fly or _dev_noclip) else _base_collision_mask
	if enabled:
		velocity.y = 0.0

func set_dev_speed(multiplier: float) -> void:
	_dev_speed_mult = clampf(multiplier, 0.25, 8.0)

func set_dev_infinite_jump(enabled: bool) -> void:
	_dev_infinite_jump = enabled

func reset_dev_flags() -> void:
	_dev_fly = false
	_dev_noclip = false
	_dev_speed_mult = 1.0
	_dev_infinite_jump = false
	collision_mask = _base_collision_mask

func _movement_pressed() -> bool:
	return Input.is_action_pressed("move_left") or Input.is_action_pressed("move_right") \
		or Input.is_action_pressed("move_up") or Input.is_action_pressed("move_down") \
		or Input.is_action_pressed("jump")

func is_resting() -> bool:
	return pose == Pose.RESTING or pose == Pose.STANDING_UP or pose == Pose.SITTING_DOWN

func is_standing() -> bool:
	return pose == Pose.NORMAL

func is_seated() -> bool:
	return pose == Pose.RESTING

# =============================================================================
# REST / POSE SHEET
# =============================================================================

## Put the hero on the ground (sitting by default, lying when `lying` = true).
func enter_resting(lying: bool = false) -> void:
	if _rest_texture == null:
		return
	pose = Pose.RESTING
	_lying = lying
	_pose_time = 0.0
	_use_rest_sheet()
	sprite.frame = REST_LYING if lying else REST_SIT

## Sit down animation (used right before saving the quit screenshot).
func sit_down_animation() -> void:
	if _rest_texture == null:
		return
	pose = Pose.SITTING_DOWN
	_pose_time = 0.0
	_use_rest_sheet()
	_pose_steps = [
		[REST_STAND, 0.18],
		[REST_RISE_2, 0.16],
		[REST_RISE_1, 0.16],
		[REST_SIT, 0.20],
	]
	_pose_step_index = 0
	_pose_step_timer = 0.0
	sprite.frame = _pose_steps[0][0]

func begin_stand_up() -> void:
	if _rest_texture == null:
		pose = Pose.NORMAL
		stand_up_finished.emit()
		return
	pose = Pose.STANDING_UP
	_pose_time = 0.0
	_use_rest_sheet()
	_pose_steps = [
		[REST_RISE_1, 0.22],
		[REST_RISE_2, 0.22],
		[REST_STAND, 0.20],
	]
	_pose_step_index = 0
	_pose_step_timer = 0.0
	sprite.frame = _pose_steps[0][0]

func finish_stand_up() -> void:
	pose = Pose.NORMAL
	_use_normal_sheet()
	_update_facing(Vector3(0.0, 0.0, 1.0))
	stand_up_finished.emit()

func _use_rest_sheet() -> void:
	sprite.texture = _rest_texture
	sprite.hframes = REST_FRAMES
	sprite.vframes = 1
	sprite.position.y = frame_height_px * pixel_size * 0.5
	sprite.frame = REST_SIT

func _use_normal_sheet() -> void:
	sprite.texture = _normal_texture
	sprite.hframes = sheet_cols
	sprite.vframes = sheet_rows
	sprite.position.y = frame_height_px * pixel_size * 0.5

func _process(delta: float) -> void:
	_update_shadow()
	match pose:
		Pose.SITTING_DOWN, Pose.STANDING_UP:
			_advance_pose_steps(delta)
		Pose.RESTING:
			_pose_time += delta
			if _lying:
				sprite.frame = REST_LYING_BREATHE if int(_pose_time * 0.9) % 2 == 0 else REST_LYING
			else:
				sprite.frame = REST_SIT_BREATHE if int(_pose_time * 0.9) % 2 == 0 else REST_SIT

func _advance_pose_steps(delta: float) -> void:
	if _pose_step_index >= _pose_steps.size():
		return
	_pose_step_timer += delta
	var step: Array = _pose_steps[_pose_step_index]
	sprite.frame = int(step[0])
	while _pose_step_timer >= float(step[1]):
		_pose_step_timer -= float(step[1])
		_pose_step_index += 1
		if _pose_step_index >= _pose_steps.size():
			_done_with_pose_steps()
			return
		step = _pose_steps[_pose_step_index]
		sprite.frame = int(step[0])

func _done_with_pose_steps() -> void:
	if pose == Pose.STANDING_UP:
		finish_stand_up()
	elif pose == Pose.SITTING_DOWN:
		pose = Pose.RESTING
		_lying = false
		sprite.frame = REST_SIT

# =============================================================================
# VISUALS
# =============================================================================

func _setup_sprite() -> void:
	_normal_texture = _load_texture(sheet_path, _make_placeholder_sheet())
	_rest_texture = _load_texture(rest_sheet_path, null)
	sprite.texture = _normal_texture
	sprite.hframes = sheet_cols
	sprite.vframes = sheet_rows
	sprite.frame = 0
	sprite.texture_filter = 0
	sprite.alpha_cut = 1
	sprite.billboard = 2
	sprite.pixel_size = pixel_size
	sprite.position.y = frame_height_px * pixel_size * 0.5

## The blob shadow stays on the last grounded point instead of following the
## feet upwards during a jump; it shrinks and fades with height.
func _update_shadow() -> void:
	if shadow == null:
		return
	var height := maxf(0.0, global_position.y - _shadow_ground_y)
	shadow.global_position = Vector3(global_position.x, _shadow_ground_y + 0.03, global_position.z)
	var shrink := clampf(1.0 - height * 0.12, 0.38, 1.0)
	shadow.scale = Vector3(shrink, shrink, 1.0)
	if _shadow_material != null:
		_shadow_material.albedo_color.a = 0.55 * clampf(1.0 - height * 0.22, 0.10, 1.0)

func _setup_shadow() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.0, 0.0, 0.0, 0.55)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	mat.render_priority = 1
	var tex := _load_texture(shadow_path, _make_placeholder_shadow())
	if tex != null:
		mat.albedo_texture = tex
	shadow.material_override = mat
	_shadow_material = mat
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _update_facing(dir: Vector3) -> void:
	if dir.length_squared() < 0.0001:
		return
	# 8-way facing: 0 = down, 1 = down-right, 2 = right, ... 7 = down-left.
	var angle := atan2(dir.x, dir.z)
	_facing = wrapi(int(round(angle / (PI * 0.25))), 0, 8)

func _animate(delta: float, moving: bool) -> void:
	var col := 0
	if moving:
		_anim_time += delta * anim_fps
		col = int(_anim_time) % sheet_cols
	else:
		_anim_time = 0.0
	sprite.frame = _facing * sheet_cols + col

## Hide/show for the quit screenshot (the UI draws the resting hero instead).
## First person hides the white-box body and its blob shadow.
func set_first_person(enabled: bool) -> void:
	_first_person = enabled
	if sprite != null:
		sprite.visible = not enabled
	if shadow != null:
		shadow.visible = not enabled

func set_hidden_for_screenshot(hidden: bool) -> void:
	if sprite != null:
		sprite.visible = not hidden
	if shadow != null:
		shadow.visible = not hidden

# =============================================================================
# TEXTURE HELPERS
# =============================================================================

func _load_texture(path: String, fallback: Texture2D) -> Texture2D:
	if ResourceLoader.exists(path):
		var res := load(path)
		if res is Texture2D:
			return res
	return fallback

func _make_placeholder_sheet() -> Texture2D:
	var img := Image.create(sheet_cols * 32, sheet_rows * frame_height_px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var white := Color(1, 1, 1, 1)
	for row in sheet_rows:
		for col in sheet_cols:
			var ox := col * 32
			var oy := row * frame_height_px
			img.fill_rect(Rect2i(ox + 9, oy + 12, 14, 14), white)
			img.fill_rect(Rect2i(ox + 7, oy + 28, 18, 14), white)
			img.fill_rect(Rect2i(ox + 8, oy + 42, 6, 6), white)
			img.fill_rect(Rect2i(ox + 18, oy + 42, 6, 6), white)
	return ImageTexture.create_from_image(img)

func _make_placeholder_shadow() -> Texture2D:
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var d := Vector2(x - size * 0.5 + 0.5, y - size * 0.5 + 0.5).length() / (size * 0.5)
			var a := clampf(1.0 - d, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a))
	return ImageTexture.create_from_image(img)
