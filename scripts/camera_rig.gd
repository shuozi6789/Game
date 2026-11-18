extends Node3D
## Smoothly follows the player with a fixed HD2D camera framing.
## Also owns the "zoom in while dyeing" move.

@export var target_path: NodePath
@export var follow_lerp: float = 9.0
@export var height_offset: float = 0.6
@export var base_size: float = 9.0
## While a dialogue panel is open the camera drops by this many metres, which
## lifts the hero's sprite ~20 px so the panel never covers the legs.
@export var dialogue_drop: float = 0.70
## Optional first-person view (toggled with V by the game).
@export var eye_height: float = 1.55
@export var first_person_fov: float = 72.0
@export var mouse_sensitivity: float = 0.0022

@onready var camera: Camera3D = $Camera3D

var _target: Node3D
var _zoom_tween: Tween
var _base_camera_y: float = 7.0
var _dialogue_framing: float = 0.0
var _dialogue_framing_target: float = 0.0
var _first_person: bool = false
var _yaw: float = 0.0
var _pitch: float = 0.0
var _third_camera_position := Vector3(0.0, 7.0, 9.5)
var _third_camera_rotation := Vector3(-0.635, 0.0, 0.0)

func _ready() -> void:
	if camera != null:
		_base_camera_y = camera.position.y
		_third_camera_position = camera.position
		_third_camera_rotation = camera.rotation
	if not target_path.is_empty():
		_target = get_node_or_null(target_path) as Node3D
	if _target != null:
		snap_to_target()

func set_target(node: Node3D) -> void:
	_target = node
	snap_to_target()

func snap_to_target() -> void:
	if _target != null:
		if _first_person:
			global_position = _target.global_position
		else:
			global_position = _target.global_position + Vector3(0.0, height_offset, 0.0)

## Switch between the HD2D overview and a mouse-look first-person camera.
func set_first_person(enabled: bool) -> void:
	if camera == null or _first_person == enabled:
		return
	_first_person = enabled
	if _zoom_tween != null and _zoom_tween.is_valid():
		_zoom_tween.kill()
	_dialogue_framing = 0.0
	_dialogue_framing_target = 0.0
	if enabled:
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.fov = first_person_fov
		camera.position = Vector3(0.0, eye_height, 0.0)
		camera.rotation = Vector3(_pitch, _yaw, 0.0)
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = base_size
		camera.position = _third_camera_position
		camera.rotation = _third_camera_rotation
		if _target != null:
			global_position = _target.global_position + Vector3(0.0, height_offset, 0.0)

func _unhandled_input(event: InputEvent) -> void:
	if not _first_person:
		return
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch = clampf(_pitch - event.relative.y * mouse_sensitivity, -1.35, 1.35)
		if camera != null:
			camera.rotation = Vector3(_pitch, _yaw, 0.0)
		get_viewport().set_input_as_handled()

## Called by the game when a dialogue panel opens/closes.
func set_dialogue_framing(active: bool) -> void:
	if _first_person:
		_dialogue_framing_target = 0.0
		return
	_dialogue_framing_target = dialogue_drop if active else 0.0

func _process(delta: float) -> void:
	if _first_person:
		if _target != null:
			global_position = _target.global_position
		if camera != null:
			camera.position = Vector3(0.0, eye_height, 0.0)
			camera.rotation = Vector3(_pitch, _yaw, 0.0)
		return
	_dialogue_framing = lerpf(_dialogue_framing, _dialogue_framing_target, 1.0 - exp(-9.0 * delta))
	if camera != null:
		camera.position.y = _base_camera_y - _dialogue_framing
	if _target == null:
		return
	var desired := _target.global_position + Vector3(0.0, height_offset, 0.0)
	var weight := 1.0 - exp(-follow_lerp * delta)
	global_position = global_position.lerp(desired, weight)

## Dye close-up: zoom in over `duration` seconds.
func zoom_in(size: float, duration: float) -> void:
	_zoom_to(size, duration)

func zoom_restore(duration: float) -> void:
	_zoom_to(base_size, duration)

func _zoom_to(size: float, duration: float) -> void:
	if camera == null or _first_person:
		return
	if _zoom_tween != null and _zoom_tween.is_valid():
		_zoom_tween.kill()
	_zoom_tween = create_tween()
	_zoom_tween.tween_property(camera, "size", size, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
