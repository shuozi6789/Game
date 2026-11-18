extends Node3D
## A standing NPC with a small personal vignette (rug, furniture, work props)
## and a signature 8-frame action loop.
##
## Sheet layouts (all 32x48 frames, rows = down/left/right/up):
##   64x192  = 2 cols (idle 0, breathe 1)            -- old fallback
##   160x192 = 5 cols (idle 0-1 + action 2-4)
##   320x192 = 10 cols (idle 0-1 + 8 action frames)  -- current art
## The NPC works while the hero is far away, stops and faces the hero when they
## come close (or while a dialogue is open), and resumes work afterwards.

const SHADOW_TEXTURE := "res://assets/generated/blob_shadow.png"
const KIT_DIR := "res://assets/free/kenney_nature_kit/models/"
const PIXEL_SIZE := 0.025
const FRAME_H := 48
const NEAR_RADIUS := 7.0
const HEAD_YAW_LIMIT := 1.02
const HEAD_PITCH_LIMIT := 0.28
const ACTION_FRAME_TIME := 0.34
const IDLE_COL := 0
const BREATHE_COL := 1
const ACTION_START_COL := 2

const WOOD := Color(0.52, 0.40, 0.26, 1.0)
const WOOD_DARK := Color(0.35, 0.27, 0.17, 1.0)
const STONE := Color(0.66, 0.64, 0.60, 1.0)
const STONE_DARK := Color(0.46, 0.45, 0.42, 1.0)
const CLOTH := Color(0.93, 0.89, 0.80, 1.0)
const CREAM := Color(0.94, 0.88, 0.72, 1.0)
const METAL := Color(0.44, 0.49, 0.55, 1.0)
const BRASS := Color(0.80, 0.64, 0.30, 1.0)
const GLASS := Color(0.78, 0.84, 0.90, 1.0)
const SOIL := Color(0.32, 0.24, 0.16, 1.0)

var npc_id: String = ""
var display_name: String = ""
var color: Color = Color.WHITE
var talked: bool = false

var _character: Node3D
var _head: Node3D
var _torso: Node3D
var _left_arm: Node3D
var _right_arm: Node3D
var _base_torso_y: float = 0.78
var _base_head_y: float = 1.24
var _head_yaw: float = 0.0
var _head_pitch: float = 0.0
var _shadow: MeshInstance3D
var _player: Node3D
var _sheet_path: String = ""
var _cols: int = 2
var _face_row: int = 0
var _anim_time: float = 0.0
var _pose: String = "idle"
var _pose_timer: float = 0.0
var _action_time: float = 0.0
var _idle_duration: float = 3.0
var _rng := RandomNumberGenerator.new()
var _lantern: OmniLight3D
var _lantern_glass: MeshInstance3D
var _vignette: Node3D
var _kite: Node3D
var _kite_base: Vector3
var _pinwheel: Node3D
var _imported_character: bool = false
var _imported_anim: AnimationPlayer
const BLOCKY_MODEL := {
	"red": "character-b",
	"yellow": "character-d",
	"green": "character-c",
	"blue": "character-j",
	"purple": "character-e",
	"orange": "character-p",
	"pink": "character-n",
	"teal": "character-f",
}
var _structure: Node3D
var _talk_lights: Array[OmniLight3D] = []
var _talk_stage: bool = false

func setup(id: String, data: Dictionary) -> void:
	npc_id = id
	display_name = str(data.get("name", ""))
	_sheet_path = str(data.get("sprite", ""))
	color = Narrative.color_of(id)
	_rng.seed = hash(id)
	_idle_duration = _rng.randf_range(2.0, 4.0)
	_build_character()
	_build_vignette()

func _ready() -> void:
	_build_visuals()
	_player = get_tree().get_first_node_in_group("player") as Node3D

# =============================================================================
# VISUALS
# =============================================================================

func _build_visuals() -> void:
	# Shadow + collision only; the body/head/face are built in _build_character()
	# once setup() knows which NPC this is.
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.0, 0.0, 0.0, 0.5)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	mat.render_priority = 1
	if ResourceLoader.exists(SHADOW_TEXTURE):
		mat.albedo_texture = load(SHADOW_TEXTURE)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.85, 0.85)
	quad.material = mat
	_shadow = MeshInstance3D.new()
	_shadow.mesh = quad
	_shadow.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_shadow.position.y = 0.010
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shadow)

	# Solid so the hero cannot walk through the person.
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.2
	shape.shape = capsule
	shape.position.y = 0.6
	body.add_child(shape)
	add_child(body)

# --- 3D low-poly character ------------------------------------------------

func _npc_mat(colour: Color, unshaded: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 1.0
	mat.metallic = 0.0
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat

func _body_box(parent: Node3D, size: Vector3, pos: Vector3, colour: Color,
		unshaded_or_rot = false, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var unshaded := false
	var rotation := rot
	if unshaded_or_rot is bool:
		unshaded = unshaded_or_rot
	elif unshaded_or_rot is Vector3:
		rotation = unshaded_or_rot
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _npc_mat(colour, unshaded)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	node.rotation = rotation
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(node)
	return node

func _body_cyl(parent: Node3D, top_r: float, bottom_r: float, height: float,
		pos: Vector3, colour: Color, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_r
	mesh.bottom_radius = bottom_r
	mesh.height = height
	mesh.radial_segments = 8
	mesh.material = _npc_mat(colour)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	node.rotation = rot
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(node)
	return node

func _body_sphere(parent: Node3D, radius: float, pos: Vector3, colour: Color,
		unshaded: bool = false) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	mesh.material = _npc_mat(colour, unshaded)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(node)
	return node

func _build_imported_character() -> bool:
	var model_name: String = BLOCKY_MODEL.get(npc_id, "")
	if model_name == "":
		return false
	var path := "res://assets/free/kenney_blocky_characters/models/%s.glb" % model_name
	if not ResourceLoader.exists(path):
		return false
	var packed := load(path) as PackedScene
	if packed == null:
		return false
	_character = packed.instantiate() as Node3D
	_character.name = "Character3D"
	# Kenney's blocky characters are authored in ~2.1 m units; scale to fit the
	# same 1.7 m silhouette as the vignette furniture.
	_character.scale = Vector3.ONE * 0.40
	_character.rotation.y = 0.0
	add_child(_character)
	_imported_character = true
	_imported_anim = _find_animation_player(_character)
	if _imported_anim != null:
		var clips := _imported_anim.get_animation_list()
		var idle := "idle" if "idle" in clips else ("static" if "static" in clips else (clips[0] if not clips.is_empty() else ""))
		if idle != "":
			_imported_anim.play(idle)
			_imported_anim.seek(randf_range(0.0, 1.2), true)
	return true

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null

func _build_character() -> void:
	if _character != null:
		_character.queue_free()
	if _build_imported_character():
		return
	var skin := Color(0.84, 0.70, 0.58, 1.0)
	var skin_shade := Color(0.70, 0.56, 0.45, 1.0)
	var hair := Color(0.20, 0.16, 0.13, 1.0)
	match npc_id:
		"red": hair = Color(0.20, 0.14, 0.10, 1.0)
		"yellow": hair = Color(0.16, 0.13, 0.10, 1.0)
		"green": hair = Color(0.24, 0.18, 0.12, 1.0)
		"blue": hair = Color(0.12, 0.11, 0.10, 1.0)
		"purple": hair = Color(0.28, 0.17, 0.14, 1.0)
		"orange": hair = Color(0.24, 0.15, 0.10, 1.0)
		"pink": hair = Color(0.34, 0.23, 0.18, 1.0)
		"teal": hair = Color(0.15, 0.13, 0.12, 1.0)
	var cloth := color.lightened(0.04)
	var cloth_dark := color.darkened(0.28)
	var trim := color.darkened(0.12).lerp(Color(0.90, 0.82, 0.66), 0.35)
	var boot := Color(0.24, 0.19, 0.15, 1.0)

	_character = Node3D.new()
	_character.name = "Character3D"
	_character.position.y = 0.0
	var build_scale := Vector3.ONE
	var head_scale := Vector3.ONE
	match npc_id:
		"red": build_scale = Vector3(1.05, 1.03, 1.02)
		"yellow": build_scale = Vector3(0.92, 0.94, 0.93); head_scale = Vector3(0.96, 1.00, 0.96)
		"green": build_scale = Vector3(1.08, 0.96, 1.08); head_scale = Vector3(1.05, 0.98, 1.04)
		"blue": build_scale = Vector3(0.95, 1.08, 0.95); head_scale = Vector3(0.94, 1.04, 0.95)
		"purple": build_scale = Vector3(0.95, 1.02, 0.95); head_scale = Vector3(0.98, 1.00, 0.98)
		"orange": build_scale = Vector3(1.10, 0.98, 1.08); head_scale = Vector3(1.05, 0.97, 1.04)
		"pink": build_scale = Vector3(0.90, 0.93, 0.91); head_scale = Vector3(0.97, 0.98, 0.97)
		"teal": build_scale = Vector3(0.94, 1.06, 0.94); head_scale = Vector3(0.95, 1.04, 0.95)
	_character.scale = build_scale
	add_child(_character)

	# legs + boots
	for side in [-1.0, 1.0]:
		_body_cyl(_character, 0.070, 0.080, 0.44, Vector3(side * 0.11, 0.24, 0.0), cloth_dark)
		_body_box(_character, Vector3(0.16, 0.09, 0.22),
			Vector3(side * 0.11, 0.05, 0.02), boot)

	# torso, belt
	_torso = Node3D.new()
	_torso.position = Vector3(0.0, _base_torso_y, 0.0)
	_character.add_child(_torso)
	_body_box(_torso, Vector3(0.36, 0.50, 0.24), Vector3.ZERO, cloth)
	_body_box(_torso, Vector3(0.38, 0.055, 0.25), Vector3(0.0, -0.24, 0.0), cloth_dark)
	# neck
	_body_cyl(_torso, 0.055, 0.065, 0.10, Vector3(0.0, 0.30, 0.0), skin_shade)

	# arms
	_left_arm = Node3D.new()
	_left_arm.position = Vector3(-0.23, 0.21, 0.0)
	_torso.add_child(_left_arm)
	_body_cyl(_left_arm, 0.052, 0.065, 0.42, Vector3(0.0, -0.21, 0.0), cloth)
	_body_sphere(_left_arm, 0.060, Vector3(0.0, -0.44, 0.0), skin)
	_right_arm = Node3D.new()
	_right_arm.position = Vector3(0.23, 0.21, 0.0)
	_torso.add_child(_right_arm)
	_body_cyl(_right_arm, 0.052, 0.065, 0.42, Vector3(0.0, -0.21, 0.0), cloth)
	_body_sphere(_right_arm, 0.060, Vector3(0.0, -0.44, 0.0), skin)

	# head (pivots for look-at)
	_head = Node3D.new()
	_head.position = Vector3(0.0, _base_head_y, 0.0)
	_head.scale = head_scale
	_character.add_child(_head)
	_body_sphere(_head, 0.175, Vector3.ZERO, skin)
	# ears
	for side in [-1.0, 1.0]:
		_body_sphere(_head, 0.040, Vector3(side * 0.165, 0.005, 0.0), skin_shade)

	# face detail (front is +Z because the NPC bodies face the path/camera)
	var face_z := 0.158
	var face_dark := Color(0.16, 0.12, 0.10, 1.0)
	var eye_white := Color(0.98, 0.96, 0.91, 1.0)
	var iris := color.darkened(0.15).lerp(Color(0.20, 0.15, 0.12), 0.35)
	for side in [-1.0, 1.0]:
		_body_box(_head, Vector3(0.070, 0.052, 0.012),
			Vector3(side * 0.072, 0.025, face_z), eye_white, true)
		_body_box(_head, Vector3(0.036, 0.040, 0.012),
			Vector3(side * 0.072, 0.022, face_z + 0.010), iris, true)
		_body_box(_head, Vector3(0.012, 0.015, 0.010),
			Vector3(side * 0.061, 0.035, face_z + 0.018), Color(1, 1, 1, 1), true)
		_body_box(_head, Vector3(0.072, 0.012, 0.010),
			Vector3(side * 0.072, 0.083, face_z + 0.008), hair, true,
			Vector3(0.0, 0.0, side * -0.10))
		_body_box(_head, Vector3(0.048, 0.018, 0.010),
			Vector3(side * 0.105, -0.060, face_z - 0.004),
			Color(0.88, 0.56, 0.48, 1.0), true)
	# nose, mouth, chin
	_body_box(_head, Vector3(0.028, 0.030, 0.022),
		Vector3(0.0, -0.010, face_z + 0.012), skin_shade, true)
	_body_box(_head, Vector3(0.072, 0.014, 0.010),
		Vector3(0.0, -0.092, face_z + 0.004), face_dark, true)
	_body_box(_head, Vector3(0.026, 0.012, 0.010),
		Vector3(-0.038, -0.108, face_z + 0.003), face_dark, true,
		Vector3(0.0, 0.0, 0.20))
	_body_box(_head, Vector3(0.026, 0.012, 0.010),
		Vector3(0.038, -0.108, face_z + 0.003), face_dark, true,
		Vector3(0.0, 0.0, -0.20))

	# hair cap + identity accessories
	_body_sphere(_head, 0.183, Vector3(0.0, 0.055, -0.015), hair)
	_body_box(_head, Vector3(0.30, 0.10, 0.26), Vector3(0.0, 0.145, -0.02), hair)
	match npc_id:
		"red":
			# Outgoing courier: red headband, rolled sleeves, leather satchel.
			_body_box(_head, Vector3(0.36, 0.060, 0.32), Vector3(0.0, 0.10, 0.0), color)
			_body_box(_head, Vector3(0.060, 0.19, 0.03), Vector3(0.17, 0.02, -0.15), color,
				Vector3(0.0, 0.0, 0.22))
			for sx in [-0.12, 0.0, 0.12]:
				_body_box(_head, Vector3(0.06, 0.10, 0.08), Vector3(sx, 0.16, -0.02), hair,
					Vector3(0.0, 0.0, sx * 0.4))
			_body_box(_torso, Vector3(0.04, 0.52, 0.02), Vector3(0.03, -0.01, 0.135), Color(0.34, 0.22, 0.14),
				Vector3(0.0, 0.0, -30.0))
			_body_box(_torso, Vector3(0.22, 0.20, 0.12), Vector3(0.24, -0.10, 0.06), Color(0.42, 0.27, 0.16))
			_body_box(_torso, Vector3(0.20, 0.05, 0.11), Vector3(0.24, 0.02, 0.06), Color(0.60, 0.44, 0.26))
			for arm in [_left_arm, _right_arm]:
				_body_box(arm, Vector3(0.09, 0.11, 0.09), Vector3(0.0, -0.34, 0.0), skin)
		"yellow":
			# Watchmaker: waistcoat, cravat, round glasses, watch chain.
			_body_box(_torso, Vector3(0.30, 0.36, 0.025), Vector3(0.0, -0.06, 0.135), Color(0.26, 0.23, 0.20))
			_body_box(_torso, Vector3(0.09, 0.30, 0.025), Vector3(-0.11, -0.02, 0.145), trim)
			_body_box(_torso, Vector3(0.09, 0.30, 0.025), Vector3(0.11, -0.02, 0.145), trim)
			_body_box(_torso, Vector3(0.22, 0.09, 0.24), Vector3(0.0, 0.27, 0.0), Color(0.84, 0.78, 0.66))
			_body_box(_torso, Vector3(0.10, 0.16, 0.02), Vector3(0.0, 0.20, 0.14), Color(0.72, 0.62, 0.48),
				Vector3(0.0, 0.0, 20.0))
			_body_glasses(_head, face_z, trim)
			for i in 4:
				_body_box(_torso, Vector3(0.025, 0.025, 0.012), Vector3(-0.08 + float(i) * 0.05, -0.20, 0.155),
					Color(0.90, 0.72, 0.28), true)
			_body_cyl(_torso, 0.035, 0.035, 0.018, Vector3(0.08, -0.25, 0.155), Color(0.90, 0.72, 0.28))
		"green":
			# Gardener: rounder build, straw hat, apron, flower badge, freckles.
			_body_sphere(_torso, 0.205, Vector3(0.0, -0.04, 0.015), cloth)
			_body_cyl(_head, 0.255, 0.255, 0.035, Vector3(0.0, 0.155, 0.0), Color(0.82, 0.71, 0.45))
			_body_cyl(_head, 0.145, 0.165, 0.15, Vector3(0.0, 0.235, 0.0), Color(0.82, 0.71, 0.45))
			_body_cyl(_head, 0.15, 0.16, 0.035, Vector3(0.0, 0.18, 0.0), Color(0.76, 0.42, 0.38))
			_body_box(_torso, Vector3(0.32, 0.35, 0.025), Vector3(0.0, -0.06, 0.135), Color(0.88, 0.86, 0.74))
			_body_box(_torso, Vector3(0.18, 0.12, 0.02), Vector3(0.0, -0.12, 0.150), Color(0.68, 0.64, 0.50))
			_body_box(_torso, Vector3(0.035, 0.30, 0.02), Vector3(-0.14, 0.14, 0.145), Color(0.70, 0.66, 0.50))
			_body_box(_torso, Vector3(0.035, 0.30, 0.02), Vector3(0.14, 0.14, 0.145), Color(0.70, 0.66, 0.50))
			_body_box(_head, Vector3(0.06, 0.025, 0.012), Vector3(0.13, 0.12, 0.16), Color(0.78, 0.42, 0.42))
			_body_box(_head, Vector3(0.035, 0.02, 0.012), Vector3(0.10, 0.15, 0.16), Color(0.96, 0.82, 0.38))
			for sx in [-0.11, 0.11]:
				_body_box(_head, Vector3(0.024, 0.015, 0.010), Vector3(sx, -0.045, 0.172), Color(0.62, 0.40, 0.30))
			for arm in [_left_arm, _right_arm]:
				_body_box(arm, Vector3(0.085, 0.10, 0.085), Vector3(0.0, -0.34, 0.0), Color(0.52, 0.46, 0.32))
		"blue":
			# Road keeper: tall frame, epaulettes, long coat, cap, scarf, bag.
			_body_box(_torso, Vector3(0.14, 0.06, 0.24), Vector3(-0.21, 0.25, 0.0), trim)
			_body_box(_torso, Vector3(0.14, 0.06, 0.24), Vector3(0.21, 0.25, 0.0), trim)
			_body_cyl(_head, 0.18, 0.19, 0.10, Vector3(0.0, 0.22, 0.0), color.darkened(0.42))
			_body_box(_head, Vector3(0.36, 0.025, 0.16), Vector3(0.0, 0.17, 0.15), color.darkened(0.42))
			_body_box(_torso, Vector3(0.34, 0.05, 0.03), Vector3(0.0, 0.26, 0.135), Color(0.80, 0.34, 0.28))
			_body_box(_torso, Vector3(0.08, 0.40, 0.025), Vector3(-0.10, -0.02, 0.14), cloth_dark)
			for side in [-1.0, 1.0]:
				_body_box(_torso, Vector3(0.13, 0.42, 0.025), Vector3(float(side) * 0.10, -0.04, 0.14), cloth)
			for side in [-1.0, 1.0]:
				_body_box(_torso, Vector3(0.16, 0.36, 0.025), Vector3(float(side) * 0.10, -0.30, -0.13),
					cloth_dark, Vector3(0.0, 0.0, float(side) * -7.0))
			_body_box(_torso, Vector3(0.22, 0.05, 0.13), Vector3(-0.22, -0.20, 0.04), Color(0.30, 0.20, 0.14))
		"purple":
			# Painter: long hair, wide-brim hat, paint-smudged smock, brush.
			_body_box(_head, Vector3(0.07, 0.34, 0.10), Vector3(-0.15, -0.05, -0.14), hair,
				Vector3(0.0, 0.0, 0.10))
			_body_box(_head, Vector3(0.07, 0.34, 0.10), Vector3(0.15, -0.05, -0.14), hair,
				Vector3(0.0, 0.0, -0.10))
			_body_cyl(_head, 0.28, 0.28, 0.035, Vector3(0.0, 0.155, 0.0), color.darkened(0.40))
			_body_cyl(_head, 0.14, 0.17, 0.11, Vector3(0.0, 0.23, 0.0), color.darkened(0.30))
			_body_cyl(_head, 0.155, 0.16, 0.025, Vector3(0.0, 0.19, 0.0), Color(0.84, 0.60, 0.50))
			_body_box(_torso, Vector3(0.34, 0.40, 0.025), Vector3(0.0, -0.04, 0.14), Color(0.94, 0.92, 0.84))
			for i in 5:
				_body_box(_torso, Vector3(0.05, 0.04, 0.012), Vector3(-0.12 + float(i) * 0.06, -0.16 + float(i % 2) * 0.07, 0.155),
					[Color(0.72, 0.32, 0.40), Color(0.36, 0.52, 0.72), Color(0.86, 0.62, 0.30), Color(0.44, 0.62, 0.44)][i % 4])
			_body_box(_torso, Vector3(0.24, 0.05, 0.03), Vector3(0.0, 0.26, 0.14), Color(0.74, 0.46, 0.56))
			_body_cyl(_head, 0.010, 0.014, 0.30, Vector3(0.17, 0.10, -0.04), WOOD_DARK,
				Vector3(0.0, 0.0, 32.0))
			_body_box(_head, Vector3(0.035, 0.08, 0.035), Vector3(0.21, 0.22, -0.06), Color(0.86, 0.68, 0.38),
				Vector3(0.0, 0.0, 32.0))
		"orange":
			# Carpenter: broad shoulders, work apron, tool belt, gloves, rolled sleeves.
			_body_box(_torso, Vector3(0.14, 0.09, 0.20), Vector3(-0.23, 0.21, 0.0), cloth)
			_body_box(_torso, Vector3(0.14, 0.09, 0.20), Vector3(0.23, 0.21, 0.0), cloth)
			_body_box(_head, Vector3(0.34, 0.06, 0.31), Vector3(0.0, 0.10, 0.0), color.darkened(0.10))
			_body_box(_head, Vector3(0.06, 0.14, 0.03), Vector3(0.15, 0.02, -0.15), color.darkened(0.10))
			_body_box(_torso, Vector3(0.30, 0.38, 0.025), Vector3(0.0, -0.04, 0.14), Color(0.54, 0.38, 0.24))
			_body_box(_torso, Vector3(0.30, 0.06, 0.05), Vector3(0.0, -0.24, 0.15), Color(0.28, 0.20, 0.13))
			for i in 3:
				_body_box(_torso, Vector3(0.06, 0.13, 0.04), Vector3(-0.16 + float(i) * 0.16, -0.24, 0.17),
					[Color(0.66, 0.50, 0.30), Color(0.46, 0.48, 0.50), Color(0.42, 0.28, 0.18)][i])
			_body_cyl(_torso, 0.035, 0.035, 0.16, Vector3(-0.13, -0.30, 0.17), Color(0.30, 0.30, 0.32))
			for arm in [_left_arm, _right_arm]:
				_body_box(arm, Vector3(0.09, 0.11, 0.09), Vector3(0.0, -0.34, 0.0), skin)
		"pink":
			# Free traveller: petite frame, ponytail, layered scarf, feather, coat.
			_body_sphere(_head, 0.17, Vector3(0.0, 0.10, -0.14), hair)
			_body_cyl(_head, 0.055, 0.035, 0.34, Vector3(0.0, -0.10, -0.18), hair,
				Vector3(0.28, 0.0, 0.0))
			_body_box(_torso, Vector3(0.36, 0.08, 0.26), Vector3(0.0, 0.27, 0.0), Color(0.96, 0.68, 0.75))
			_body_box(_torso, Vector3(0.34, 0.06, 0.27), Vector3(0.0, 0.21, 0.0), Color(0.82, 0.56, 0.62))
			_body_box(_torso, Vector3(0.38, 0.26, 0.025), Vector3(0.0, -0.10, 0.13), Color(0.84, 0.66, 0.56))
			_body_box(_torso, Vector3(0.06, 0.26, 0.10), Vector3(0.20, -0.16, 0.08), Color(0.88, 0.58, 0.48))
			_body_box(_head, Vector3(0.03, 0.24, 0.03), Vector3(0.17, 0.18, -0.05), Color(0.94, 0.82, 0.48),
				Vector3(0.0, 0.0, 38.0))
			_body_box(_head, Vector3(0.07, 0.20, 0.06), Vector3(0.16, 0.04, -0.10), hair,
				Vector3(0.0, 0.0, 20.0))
			_body_box(_head, Vector3(0.07, 0.20, 0.06), Vector3(-0.16, 0.04, -0.10), hair,
				Vector3(0.0, 0.0, -20.0))
			for arm in [_left_arm, _right_arm]:
				_body_box(arm, Vector3(0.06, 0.05, 0.06), Vector3(0.0, -0.41, 0.0), Color(0.94, 0.70, 0.52))
		"teal":
			# Record keeper: high collar, long robe, glasses, book satchel and bun.
			_body_glasses(_head, face_z, Color(0.55, 0.72, 0.72))
			_body_sphere(_head, 0.10, Vector3(0.0, 0.16, -0.13), hair)
			_body_box(_head, Vector3(0.06, 0.16, 0.03), Vector3(0.0, 0.02, 0.17), Color(0.86, 0.84, 0.72),
				Vector3(0.0, 0.0, 32.0))
			_body_box(_torso, Vector3(0.36, 0.05, 0.26), Vector3(0.0, 0.28, 0.0), color.darkened(0.36))
			for side in [-1.0, 1.0]:
				_body_box(_torso, Vector3(0.15, 0.52, 0.025), Vector3(float(side) * 0.095, -0.16, 0.14),
					color.darkened(0.24))
			_body_box(_torso, Vector3(0.22, 0.20, 0.12), Vector3(0.22, -0.10, 0.03), Color(0.30, 0.22, 0.15))
			_body_box(_torso, Vector3(0.18, 0.04, 0.10), Vector3(0.22, 0.02, 0.03), Color(0.64, 0.48, 0.28))

func _body_glasses(head: Node3D, face_z: float, colour: Color) -> void:
	for side in [-1.0, 1.0]:
		var torus := TorusMesh.new()
		torus.inner_radius = 0.035
		torus.outer_radius = 0.060
		torus.rings = 8
		torus.ring_segments = 8
		torus.material = _npc_mat(colour)
		var rim := MeshInstance3D.new()
		rim.mesh = torus
		rim.position = Vector3(side * 0.072, 0.025, face_z + 0.020)
		rim.rotation.x = PI * 0.5
		rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		head.add_child(rim)
	_body_box(head, Vector3(0.035, 0.012, 0.012), Vector3(0.0, 0.025, face_z + 0.020), colour, true)

func _apply_sheet() -> void:
	# Sprite sheets are no longer used for the NPC bodies; portraits are separate.
	pass

func _has_action() -> bool:
	return false

func _process(delta: float) -> void:
	if _character == null:
		return
	_anim_time += delta
	if talked and not _talk_stage:
		_talk_stage = true
		_apply_talked_stage()
	if _lantern != null:
		_lantern.light_energy = 1.05 + sin(_anim_time * 7.3) * 0.10
	if _kite != null:
		_kite.position = _kite_base + Vector3(
			sin(_anim_time * 0.7) * 0.16,
			sin(_anim_time * 0.95) * 0.12,
			cos(_anim_time * 0.55) * 0.10)
		_kite.rotation.z = sin(_anim_time * 1.1) * 0.22
		_kite.rotation.y = sin(_anim_time * 0.6) * 0.35
	if _pinwheel != null:
		_pinwheel.rotation.z += 2.6 * delta
	if _imported_character:
		return

	var near := _player != null and _player.global_position.distance_to(global_position) <= NEAR_RADIUS
	var look_at_player := near or GameState.dialogue_active

	# Body stays put; only the head turns, clamped so it never spins backwards.
	var target_yaw := 0.0
	var target_pitch := 0.0
	if look_at_player and _player != null:
		var local_player := to_local(_player.global_position + Vector3(0.0, 1.0, 0.0))
		var head_local_y := _base_head_y + _torso.position.y - _base_torso_y
		target_yaw = atan2(local_player.x, local_player.z)
		target_yaw = clampf(target_yaw, -HEAD_YAW_LIMIT, HEAD_YAW_LIMIT)
		target_pitch = -atan2(local_player.y - head_local_y,
			maxf(Vector2(local_player.x, local_player.z).length(), 0.001))
		target_pitch = clampf(target_pitch, -HEAD_PITCH_LIMIT, HEAD_PITCH_LIMIT)
	_head_yaw = lerp_angle(_head_yaw, target_yaw, 1.0 - exp(-7.0 * delta))
	_head_pitch = lerpf(_head_pitch, target_pitch, 1.0 - exp(-7.0 * delta))
	_head.rotation = Vector3(_head_pitch, _head_yaw, 0.0)

	# Work loop: arms move while the NPC is busy, and settle when the hero is near.
	if near or GameState.dialogue_active:
		_pose = "idle"
		_pose_timer = 0.0
	else:
		_pose_timer += delta
		if _pose == "idle" and _pose_timer >= _idle_duration:
			_pose = "action"
			_action_time = 0.0
			_pose_timer = 0.0
		elif _pose == "action":
			_action_time += delta
			if _action_time > 1.2:
				_pose = "idle"
				_pose_timer = 0.0
				_idle_duration = _rng.randf_range(2.4, 4.6)

	var breathe := sin(_anim_time * 2.0) * 0.008
	_torso.position.y = _base_torso_y + breathe
	_head.position.y = _base_head_y + breathe * 0.55
	var arm_target := 0.0
	var arm_wave := 0.0
	var torso_tilt := 0.0
	if _pose == "action":
		arm_target = -0.55
		arm_wave = sin(_action_time * 8.0) * 0.55
		torso_tilt = sin(_action_time * 2.0) * 0.025
	_left_arm.rotation.x = lerpf(_left_arm.rotation.x, arm_target - arm_wave, 1.0 - exp(-10.0 * delta))
	_right_arm.rotation.x = lerpf(_right_arm.rotation.x, arm_target + arm_wave, 1.0 - exp(-10.0 * delta))
	_torso.rotation.z = lerpf(_torso.rotation.z, torso_tilt, 1.0 - exp(-8.0 * delta))

# =============================================================================
# VIGNETTE (small personal scene around the NPC)
# =============================================================================

## Each NPC now has a small building/working set behind them, not just a rug.
## The structure is derived from the NPC's personality and their 2D illustration.
func _build_npc_building() -> void:
	_structure = Node3D.new()
	_structure.name = "NpcBuilding"
	_structure.position = Vector3(0.0, 0.0, -2.05)
	_vignette.add_child(_structure)
	_talk_lights.clear()
	match npc_id:
		"red":
			_building_shell(Color(0.52, 0.34, 0.21), Color(0.57, 0.20, 0.16))
			# post-office hatch and parcels
			_add_box(_structure, Vector3(1.6, 0.75, 0.08), Vector3(0.0, 1.42, 0.12), _mat(Color(0.31, 0.21, 0.14)))
			for i in 4:
				_add_box(_structure, Vector3(0.26, 0.08, 0.04), Vector3(-0.55 + float(i) * 0.37, 1.42, 0.17), _mat(Color(0.10, 0.08, 0.06)))
			_add_box(_structure, Vector3(1.2, 0.38, 0.08), Vector3(0.0, 1.95, 0.10), _mat(Color(0.74, 0.28, 0.20)))
			_add_box(_structure, Vector3(0.32, 0.22, 0.28), Vector3(-1.65, 0.14, 0.10), _mat(Color(0.43, 0.28, 0.17)))
			_add_box(_structure, Vector3(0.46, 0.30, 0.34), Vector3(1.55, 0.18, 0.15), _mat(Color(0.58, 0.40, 0.24)))
			_add_box(_structure, Vector3(0.23, 0.16, 0.05), Vector3(1.55, 0.24, 0.33), _mat(Color(0.78, 0.68, 0.46)))
			_add_structure_light(Vector3(0.0, 2.12, 0.20))
		"yellow":
			_building_shell(Color(0.84, 0.78, 0.62), Color(0.32, 0.23, 0.17))
			for x in [-2.25, -0.75, 0.75, 2.25]:
				_add_box(_structure, Vector3(0.10, 2.2, 0.08), Vector3(x, 1.1, 0.15), _mat(Color(0.30, 0.21, 0.14)))
			_add_box(_structure, Vector3(2.1, 0.08, 0.08), Vector3(0.0, 1.65, 0.16), _mat(Color(0.30, 0.21, 0.14)))
			_add_box(_structure, Vector3(2.0, 1.15, 0.07), Vector3(-0.55, 0.92, 0.13), _mat(Color(0.19, 0.20, 0.18)))
			_add_box(_structure, Vector3(1.9, 1.05, 0.04), Vector3(-0.55, 0.92, 0.18), _mat(Color(0.66, 0.80, 0.78)))
			_add_cylinder(_structure, 0.30, 0.30, 0.05, Vector3(1.35, 1.46, 0.20), _mat(Color(0.88, 0.77, 0.43)), Vector3(90.0, 0.0, 0.0))
			_add_cylinder(_structure, 0.23, 0.23, 0.06, Vector3(1.35, 1.46, 0.23), _mat(BRASS), Vector3(90.0, 0.0, 0.0))
			_add_box(_structure, Vector3(1.0, 0.30, 0.10), Vector3(1.35, 1.94, 0.14), _mat(Color(0.36, 0.27, 0.19)))
			_add_structure_light(Vector3(0.0, 2.10, 0.25))
		"green":
			_building_shell(Color(0.42, 0.56, 0.36), Color(0.28, 0.36, 0.22))
			# greenhouse glazing and a raised bed
			for x in [-1.75, -0.6, 0.6, 1.75]:
				_add_box(_structure, Vector3(0.055, 1.9, 0.055), Vector3(x, 1.0, 0.12), _mat(Color(0.54, 0.64, 0.46)))
			for y in [0.9, 1.65]:
				_add_box(_structure, Vector3(4.4, 0.045, 0.045), Vector3(0.0, y, 0.12), _mat(Color(0.54, 0.64, 0.46)))
			_add_box(_structure, Vector3(1.6, 0.32, 0.55), Vector3(-1.35, 0.18, 0.65), _mat(SOIL))
			for i in 5:
				_add_box(_structure, Vector3(0.10, 0.20, 0.10), Vector3(-1.95 + float(i) * 0.30, 0.38, 0.65), _mat([Color(0.78, 0.34, 0.34), Color(0.94, 0.78, 0.34), Color(0.88, 0.55, 0.70)][i % 3]))
			_add_box(_structure, Vector3(0.55, 0.45, 0.45), Vector3(1.55, 0.24, 0.45), _mat(Color(0.55, 0.38, 0.22)))
			_add_structure_light(Vector3(0.0, 2.1, 0.2))
		"blue":
			_building_shell(Color(0.35, 0.37, 0.38), Color(0.20, 0.25, 0.30))
			for i in 5:
				_add_box(_structure, Vector3(0.62, 1.8, 0.06), Vector3(-2.0 + float(i) * 1.0, 0.9, 0.15), _mat(Color(0.43, 0.45, 0.44)))
			_add_box(_structure, Vector3(1.10, 1.9, 0.16), Vector3(0.0, 0.95, 0.20), _mat(Color(0.10, 0.12, 0.14)))
			_add_box(_structure, Vector3(0.70, 0.20, 0.08), Vector3(0.0, 1.95, 0.28), _mat(Color(0.77, 0.58, 0.27)))
			_add_box(_structure, Vector3(0.22, 0.56, 0.22), Vector3(1.65, 2.02, 0.15), _mat(Color(0.22, 0.21, 0.19)))
			_add_box(_structure, Vector3(0.30, 0.18, 0.24), Vector3(1.65, 1.75, 0.15), _mat(Color(0.92, 0.76, 0.38), true, Color(1.0, 0.68, 0.32), 1.3))
			_add_structure_light(Vector3(0.0, 2.1, 0.35))
		"purple":
			_building_shell(Color(0.39, 0.30, 0.42), Color(0.28, 0.21, 0.34))
			# gallery wall with small canvases
			for i in 5:
				var cx := -1.7 + float(i) * 0.85
				_add_box(_structure, Vector3(0.55, 0.52, 0.04), Vector3(cx, 1.25 + float(i % 2) * 0.34, 0.15), _mat(Color(0.92, 0.88, 0.74)))
				_add_box(_structure, Vector3(0.40, 0.10, 0.02), Vector3(cx, 1.12 + float(i % 2) * 0.34, 0.18), _mat([Color(0.72, 0.32, 0.40), Color(0.36, 0.52, 0.72), Color(0.86, 0.62, 0.30), Color(0.44, 0.62, 0.44), Color(0.74, 0.46, 0.56)][i]))
			_add_box(_structure, Vector3(0.85, 0.65, 0.05), Vector3(1.55, 1.15, 0.15), _mat(Color(0.65, 0.50, 0.32)))
			_add_box(_structure, Vector3(0.10, 1.6, 0.10), Vector3(2.05, 0.8, 0.9), _mat(Color(0.32, 0.22, 0.15)))
			_add_structure_light(Vector3(0.0, 2.1, 0.25))
		"orange":
			_building_shell(Color(0.50, 0.35, 0.22), Color(0.30, 0.22, 0.16))
			# tool wall and lumber rack
			for i in 5:
				_add_box(_structure, Vector3(0.07, 0.32, 0.05), Vector3(-1.8 + float(i) * 0.30, 1.35, 0.16), _mat(Color(0.63, 0.64, 0.60)))
				_add_box(_structure, Vector3(0.12, 0.24, 0.06), Vector3(-1.8 + float(i) * 0.30, 1.10, 0.16), _mat(Color(0.35, 0.26, 0.18)))
			for i in 3:
				_add_box(_structure, Vector3(1.8, 0.22, 0.22), Vector3(1.1, 0.16 + float(i) * 0.25, 0.55), _mat(Color(0.68, 0.48, 0.28)))
			_add_box(_structure, Vector3(2.2, 0.08, 0.65), Vector3(-0.6, 0.78, 0.45), _mat(Color(0.52, 0.36, 0.22)))
			_add_structure_light(Vector3(0.0, 2.1, 0.25))
		"pink":
			# tent/canopy rather than a solid wall
			var canvas := _mat(Color(0.84, 0.67, 0.55))
			_add_box(_structure, Vector3(4.6, 0.12, 1.8), Vector3(0.0, 2.25, 0.55), canvas, Vector3(-18.0, 0.0, 0.0))
			for x in [-2.2, 2.2]:
				_add_box(_structure, Vector3(0.08, 2.25, 0.08), Vector3(x, 1.12, 1.3), _mat(WOOD_DARK))
				_add_box(_structure, Vector3(0.08, 2.25, 0.08), Vector3(x, 1.12, -0.1), _mat(WOOD_DARK))
			_add_box(_structure, Vector3(1.1, 0.65, 0.65), Vector3(-1.45, 0.32, 0.45), _mat(Color(0.70, 0.48, 0.28)))
			_add_box(_structure, Vector3(0.55, 0.25, 0.55), Vector3(1.1, 0.12, 0.35), _mat(Color(0.36, 0.28, 0.20)))
			_add_structure_light(Vector3(0.0, 2.0, 0.4))
		"teal":
			_building_shell(Color(0.31, 0.42, 0.40), Color(0.20, 0.28, 0.28))
			# archive shelves and books
			for row in 3:
				_add_box(_structure, Vector3(4.0, 0.06, 0.28), Vector3(0.0, 0.75 + float(row) * 0.52, 0.14), _mat(Color(0.38, 0.27, 0.17)))
				for i in 11:
					var col: Color = [Color(0.62, 0.26, 0.24), Color(0.28, 0.42, 0.56), Color(0.72, 0.60, 0.31), Color(0.36, 0.52, 0.43)][i % 4]
					_add_box(_structure, Vector3(0.15, 0.32, 0.16), Vector3(-1.75 + float(i) * 0.34, 0.95 + float(row) * 0.52, 0.18), _mat(col))
			_add_box(_structure, Vector3(1.4, 0.10, 0.60), Vector3(0.0, 0.62, 0.65), _mat(WOOD))
			_add_box(_structure, Vector3(0.60, 0.12, 0.40), Vector3(0.0, 0.72, 0.65), _mat(CREAM))
			_add_structure_light(Vector3(0.0, 2.1, 0.25))

func _building_shell(wall_colour: Color, roof_colour: Color) -> void:
	var wall := _mat(wall_colour)
	var roof := _mat(roof_colour)
	_add_box(_structure, Vector3(5.0, 2.25, 0.22), Vector3(0.0, 1.125, 0.0), wall)
	_add_box(_structure, Vector3(5.35, 0.16, 1.75), Vector3(0.0, 2.34, 0.42), roof,
		Vector3(-10.0, 0.0, 0.0))
	for side in [-1.0, 1.0]:
		_add_box(_structure, Vector3(0.14, 2.25, 0.14), Vector3(float(side) * 2.52, 1.12, 0.35), wall)
	# collision: back wall and side posts
	_add_building_collision(Vector3(0.0, 1.1, -2.05), Vector3(5.1, 2.3, 0.35))
	for side in [-1.0, 1.0]:
		_add_building_collision(Vector3(float(side) * 2.55, 1.1, -1.85), Vector3(0.25, 2.2, 0.5))

func _add_building_collision(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = pos
	body.add_child(shape)
	_vignette.add_child(body)

func _add_structure_light(pos: Vector3) -> void:
	var light := OmniLight3D.new()
	light.position = pos
	light.light_color = Color(1.0, 0.72, 0.40)
	light.omni_range = 4.0
	light.light_energy = 0.0
	light.shadow_enabled = false
	_structure.add_child(light)
	_talk_lights.append(light)

func _apply_talked_stage() -> void:
	# After the conversation the little shop wakes up: warm windows, lanterns and
	# a small banner. This is the dialogue-driven change to the scene.
	for light in _talk_lights:
		light.light_energy = 1.15
	var banner := _mat(color.darkened(0.18))
	_add_box(_structure, Vector3(0.55, 0.70, 0.05), Vector3(2.15, 1.55, 0.22), banner,
		Vector3(0.0, 0.0, 8.0))
	_add_box(_structure, Vector3(0.40, 0.12, 0.03), Vector3(2.15, 1.78, 0.25), _mat(Color(0.92, 0.84, 0.62)))

func _build_vignette() -> void:
	if _vignette != null:
		_vignette.queue_free()
	_vignette = Node3D.new()
	_vignette.name = "Vignette"
	# Lift the props 1.2 cm off the flattened ground: bottom faces are then never
	# coplanar with the terrain, which used to cause z-fighting/flicker.
	_vignette.position.y = 0.012
	add_child(_vignette)
	_build_npc_building()
	_add_rug(Vector2(3.2, 2.5))
	match npc_id:
		"red":
			_vignette_red()
		"yellow":
			_vignette_yellow()
		"green":
			_vignette_green()
		"blue":
			_vignette_blue()
		"purple":
			_vignette_purple()
		"orange":
			_vignette_orange()
		"teal":
			_vignette_teal()
		"pink":
			_vignette_pink()

# --- shared helpers -------------------------------------------------------

func _mat(color_value: Color, unshaded: bool = false, emission: Color = Color(0, 0, 0, 0), emission_energy: float = 2.2) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color_value
	material.roughness = 0.95
	material.metallic = 0.0
	if unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if emission.a > 0.0:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = emission_energy
	return material

func _add_mesh(parent: Node3D, mesh: Mesh, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, material: Material = null) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = pos
	instance.rotation_degrees = rot_deg
	if material != null:
		instance.material_override = material
	parent.add_child(instance)
	return instance

func _add_box(parent: Node3D, size: Vector3, pos: Vector3, material: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	return _add_mesh(parent, box, pos, rot_deg, material)

func _add_cylinder(parent: Node3D, top_radius: float, bottom_radius: float, height: float, pos: Vector3, material: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = top_radius
	cylinder.bottom_radius = bottom_radius
	cylinder.height = height
	cylinder.radial_segments = 10
	return _add_mesh(parent, cylinder, pos, rot_deg, material)

func _add_quad(parent: Node3D, size: Vector2, pos: Vector3, material: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = size
	return _add_mesh(parent, quad, pos, rot_deg, material)

## A flat work platform under the whole vignette. The surrounding terrain is
## sloped, so props would otherwise float or sink; the platform gives them one
## coherent surface, and its deep skirt hides the downhill gap.
func _add_rug(size: Vector2) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_texture = _make_rug_texture()
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.roughness = 1.0
	var plane := PlaneMesh.new()
	plane.size = size
	var rug := MeshInstance3D.new()
	rug.mesh = plane
	rug.material_override = material
	rug.position = Vector3(0.0, -0.002, -0.05)
	rug.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vignette.add_child(rug)

func _add_kit(file_name: String, pos: Vector3, target_size: float, rot_y: float = 0.0) -> Node3D:
	var path := KIT_DIR + file_name
	if not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var inst := packed.instantiate()
	var holder := Node3D.new()
	holder.name = "Kit_" + file_name.get_basename()
	holder.position = pos
	holder.rotation.y = rot_y
	var bounds := _scene_bounds(inst)
	if bounds.size.length() < 0.001:
		bounds = AABB(Vector3(-0.5, 0.0, -0.5), Vector3(1.0, 1.0, 1.0))
	var scale_factor := target_size / maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	holder.scale = Vector3.ONE * scale_factor
	holder.position.y += -bounds.position.y * scale_factor
	_vignette.add_child(holder)
	holder.add_child(inst)
	return holder

func _scene_bounds(root: Node) -> AABB:
	var result := _collect_bounds(root, Transform3D.IDENTITY)
	return result

func _collect_bounds(node: Node, xform: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	var local := xform
	if node is Node3D:
		local = xform * (node as Node3D).transform
	if node is MeshInstance3D:
		var instance := node as MeshInstance3D
		if instance.mesh != null:
			out = local * instance.mesh.get_aabb()
			first = false
	for child in node.get_children():
		var child_box := _collect_bounds(child, local)
		if child_box.size.length() < 0.0001 and child_box.position == Vector3.ZERO:
			continue
		if first:
			out = child_box
			first = false
		else:
			out = out.merge(child_box)
	return out

func _make_rug_texture() -> ImageTexture:
	var width := 64
	var height := 48
	var img := Image.create(width, height, false, Image.FORMAT_RGBA8)
	var base := Color(0.42, 0.31, 0.21, 1.0)
	for y in height:
		for x in width:
			var c := base
			if ((x / 4) + (y / 3)) % 2 == 0:
				c = base.lightened(0.05 * float((x * 7 + y * 3) % 3))
			if ((x / 8) + (y / 8)) % 3 == 0:
				c = c.darkened(0.04)
			if x < 3 or y < 3 or x >= width - 3 or y >= height - 3:
				c = Color(0.62, 0.50, 0.34, 1.0)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)

func _make_canvas_texture() -> ImageTexture:
	var width := 64
	var height := 48
	var img := Image.create(width, height, false, Image.FORMAT_RGBA8)
	for y in height:
		var t := float(y) / float(height)
		var sky := Color(0.98, 0.62, 0.38, 1.0).lerp(Color(0.42, 0.26, 0.52, 1.0), t)
		for x in width:
			var c := sky
			var dx := float(x) - 46.0
			var dy := float(y) - 30.0
			if dx * dx + dy * dy < 60.0:
				c = Color(1.0, 0.88, 0.58, 1.0)
			img.set_pixel(x, y, c)
	# a couple of hills and brush dots
	for x in width:
		var h := int(38.0 + sin(float(x) * 0.12) * 4.0)
		for y in range(h, height):
			img.set_pixel(x, y, Color(0.24, 0.28, 0.22, 1.0))
	for i in 24:
		var px := int(_rng.randf_range(2.0, 62.0))
		var py := int(_rng.randf_range(4.0, 30.0))
		img.set_pixel(px, py, Color(1.0, 0.78, 0.46, 1.0))
	return ImageTexture.create_from_image(img)

func _make_letter_texture() -> ImageTexture:
	var width := 16
	var height := 12
	var img := Image.create(width, height, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.95, 0.92, 0.84, 1.0))
	for x in width:
		img.set_pixel(x, 0, Color(0.78, 0.74, 0.64, 1.0))
		img.set_pixel(x, height - 1, Color(0.78, 0.74, 0.64, 1.0))
	for y in range(1, height - 1):
		img.set_pixel(0, y, Color(0.78, 0.74, 0.64, 1.0))
		img.set_pixel(width - 1, y, Color(0.78, 0.74, 0.64, 1.0))
	for x in range(2, width - 2):
		img.set_pixel(x, 2, Color(0.70, 0.66, 0.56, 1.0))
		img.set_pixel(x, 5, Color(0.70, 0.66, 0.56, 1.0))
		img.set_pixel(x, 8, Color(0.70, 0.66, 0.56, 1.0))
	return ImageTexture.create_from_image(img)

func _add_letter(pos: Vector3, rot_deg: Vector3) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_texture = _make_letter_texture()
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_add_quad(_vignette, Vector2(0.19, 0.14), pos, material, rot_deg)

# --- per-NPC vignettes ----------------------------------------------------

func _vignette_red() -> void:
	# Mail post + satchel + letters: the courier's roadside pick-up point.
	var pole := _add_cylinder(_vignette, 0.05, 0.06, 1.25, Vector3(-0.95, 0.62, -0.55), _mat(WOOD_DARK))
	pole.name = "MailPole"
	_add_box(_vignette, Vector3(0.34, 0.24, 0.20), Vector3(-0.95, 1.30, -0.55), _mat(Color(0.58, 0.34, 0.24)))
	_add_box(_vignette, Vector3(0.22, 0.03, 0.02), Vector3(-0.95, 1.33, -0.44), _mat(Color(0.16, 0.10, 0.08)))
	_add_box(_vignette, Vector3(0.30, 0.06, 0.22), Vector3(-0.95, 1.20, -0.55), _mat(WOOD_DARK))
	# satchel on the rug
	_add_box(_vignette, Vector3(0.34, 0.16, 0.16), Vector3(0.55, 0.10, -0.50), _mat(Color(0.46, 0.31, 0.20)))
	_add_box(_vignette, Vector3(0.36, 0.03, 0.05), Vector3(0.55, 0.19, -0.50), _mat(Color(0.30, 0.20, 0.13)))
	# scattered letters
	_add_letter(Vector3(0.32, 0.03, -0.05), Vector3(-90.0, 8.0, 0.0))
	_add_letter(Vector3(0.62, 0.03, 0.22), Vector3(-90.0, -14.0, 0.0))
	_add_letter(Vector3(0.05, 0.03, 0.35), Vector3(-90.0, 26.0, 0.0))
	# small red flag on the mail box and a crate of letters
	_add_box(_vignette, Vector3(0.02, 0.12, 0.12), Vector3(-0.77, 1.40, -0.42), _mat(Color(0.78, 0.26, 0.20)))
	_add_box(_vignette, Vector3(0.34, 0.24, 0.30), Vector3(0.95, 0.12, 0.42), _mat(WOOD_DARK))
	_add_letter(Vector3(0.95, 0.26, 0.42), Vector3(-90.0, 4.0, 0.0))
	# small stool and fence behind
	_add_cylinder(_vignette, 0.16, 0.17, 0.42, Vector3(-1.40, 0.21, 0.15), _mat(WOOD))
	_add_kit("fence_simple.glb", Vector3(-1.30, 0.0, -1.15), 1.5, 90.0)
	_add_kit("fence_simple.glb", Vector3(0.60, 0.0, -1.20), 1.5, 90.0)

func _vignette_yellow() -> void:
	# A portable watchmaker bench: table, tools, loupe, lamp, stool.
	_add_box(_vignette, Vector3(1.05, 0.07, 0.60), Vector3(-0.95, 0.74, -0.40), _mat(WOOD))
	for sx in [-1.48, -0.42]:
		for sz in [-0.66, -0.14]:
			_add_box(_vignette, Vector3(0.06, 0.70, 0.06), Vector3(sx, 0.35, sz), _mat(WOOD_DARK))
	# clock parts, gears and the loupe
	_add_cylinder(_vignette, 0.06, 0.06, 0.02, Vector3(-1.15, 0.79, -0.42), _mat(BRASS))
	_add_cylinder(_vignette, 0.04, 0.04, 0.02, Vector3(-0.98, 0.79, -0.32), _mat(METAL))
	_add_cylinder(_vignette, 0.03, 0.03, 0.02, Vector3(-0.88, 0.79, -0.46), _mat(BRASS))
	var torus := TorusMesh.new()
	torus.inner_radius = 0.05
	torus.outer_radius = 0.075
	torus.rings = 8
	torus.ring_segments = 8
	_add_mesh(_vignette, torus, Vector3(-1.30, 0.80, -0.20), Vector3(90.0, 0.0, 0.0), _mat(METAL))
	# little desk lamp
	_add_cylinder(_vignette, 0.02, 0.03, 0.30, Vector3(-0.62, 0.90, -0.62), _mat(METAL))
	_add_cylinder(_vignette, 0.02, 0.11, 0.10, Vector3(-0.62, 1.08, -0.62), _mat(BRASS, false, Color(1.0, 0.76, 0.40), 0.9))
	# books and a stool
	_add_box(_vignette, Vector3(0.20, 0.04, 0.26), Vector3(-0.30, 0.79, -0.52), _mat(Color(0.55, 0.42, 0.30)))
	_add_box(_vignette, Vector3(0.18, 0.03, 0.24), Vector3(-0.31, 0.83, -0.50), _mat(Color(0.72, 0.62, 0.42)))
	_add_cylinder(_vignette, 0.17, 0.18, 0.44, Vector3(-1.42, 0.22, 0.20), _mat(WOOD))
	_add_kit("fence_simple.glb", Vector3(-1.40, 0.0, -1.20), 1.6, 90.0)

func _add_pixel_flower(pos: Vector3, texture_path: String) -> void:
	if not ResourceLoader.exists(texture_path):
		return
	var texture := load(texture_path) as Texture2D
	if texture == null:
		return
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_add_quad(_vignette, Vector2(0.20, 0.20), pos, material)

func _vignette_green() -> void:
	# A little flower bed with a wooden border, pixel flowers, watering can and
	# a bench: the gardener's patch beside the path.
	_add_box(_vignette, Vector3(1.50, 0.05, 0.85), Vector3(1.00, 0.03, -0.45), _mat(SOIL))
	_add_box(_vignette, Vector3(1.62, 0.10, 0.07), Vector3(1.00, 0.08, -0.03), _mat(WOOD))
	_add_box(_vignette, Vector3(1.62, 0.10, 0.07), Vector3(1.00, 0.08, -0.88), _mat(WOOD))
	_add_box(_vignette, Vector3(0.07, 0.10, 0.90), Vector3(0.22, 0.08, -0.45), _mat(WOOD))
	_add_box(_vignette, Vector3(0.07, 0.10, 0.90), Vector3(1.78, 0.08, -0.45), _mat(WOOD))
	var flower_models := ["flower_redA.glb", "flower_yellowA.glb", "flower_purpleA.glb"]
	for i in 6:
		_add_kit(flower_models[i % flower_models.size()],
			Vector3(0.45 + float(i % 4) * 0.40, 0.05, -0.68 + float(i / 4) * 0.38), 0.24)
	var flower_textures := [
		"res://assets/generated/flower_white.png",
		"res://assets/generated/flower_yellow.png",
	]
	for i in 8:
		_add_pixel_flower(
			Vector3(0.35 + float(i % 4) * 0.38, 0.16, -0.72 + float(i / 4) * 0.34),
			flower_textures[i % 2])
	# watering can, clearly in front of the bed
	_add_cylinder(_vignette, 0.13, 0.15, 0.24, Vector3(-0.45, 0.13, 0.20), _mat(Color(0.50, 0.56, 0.44)))
	_add_cylinder(_vignette, 0.024, 0.045, 0.34, Vector3(-0.22, 0.24, 0.12), _mat(Color(0.44, 0.50, 0.39)), Vector3(0.0, 0.0, -35.0))
	_add_cylinder(_vignette, 0.05, 0.10, 0.10, Vector3(-0.45, 0.28, 0.20), _mat(Color(0.40, 0.46, 0.36)))
	# basket
	_add_cylinder(_vignette, 0.18, 0.15, 0.16, Vector3(-1.10, 0.09, -0.20), _mat(Color(0.70, 0.56, 0.34)))
	# bench with a backrest
	_add_box(_vignette, Vector3(0.95, 0.07, 0.36), Vector3(-0.85, 0.40, 0.62), _mat(WOOD))
	_add_box(_vignette, Vector3(0.95, 0.26, 0.06), Vector3(-0.85, 0.58, 0.80), _mat(WOOD), Vector3(-8.0, 0.0, 0.0))
	for sx in [-1.25, -0.45]:
		for sz in [0.48, 0.78]:
			_add_box(_vignette, Vector3(0.07, 0.38, 0.07), Vector3(sx, 0.19, sz), _mat(WOOD_DARK))

func _vignette_blue() -> void:
	# Lantern post (it really glows), a stone cairn and a barrier plank.
	_add_cylinder(_vignette, 0.05, 0.07, 1.78, Vector3(-0.95, 0.89, -0.55), _mat(WOOD_DARK))
	_add_box(_vignette, Vector3(0.26, 0.05, 0.05), Vector3(-0.95, 1.74, -0.46), _mat(WOOD_DARK))
	var glass := _mat(Color(0.64, 0.42, 0.16), true, Color(1.0, 0.60, 0.22), 1.15)
	_lantern_glass = _add_box(_vignette, Vector3(0.20, 0.26, 0.20), Vector3(-0.95, 1.55, -0.55), glass)
	_add_box(_vignette, Vector3(0.24, 0.05, 0.24), Vector3(-0.95, 1.70, -0.55), _mat(METAL))
	_add_box(_vignette, Vector3(0.24, 0.04, 0.24), Vector3(-0.95, 1.41, -0.55), _mat(METAL))
	_lantern = OmniLight3D.new()
	_lantern.name = "LanternLight"
	_lantern.position = Vector3(-0.95, 1.55, -0.55)
	_lantern.light_color = Color(1.0, 0.72, 0.36)
	_lantern.light_energy = 1.05
	_lantern.omni_range = 4.6
	_lantern.shadow_enabled = false
	_vignette.add_child(_lantern)
	# A small cairn of stones (kept in the game palette, not the kit colours).
	_add_box(_vignette, Vector3(0.46, 0.16, 0.40), Vector3(0.55, 0.08, -0.40), _mat(STONE), Vector3(0.0, 12.0, 0.0))
	_add_box(_vignette, Vector3(0.34, 0.16, 0.30), Vector3(0.60, 0.23, -0.36), _mat(STONE_DARK), Vector3(0.0, -18.0, 0.0))
	_add_box(_vignette, Vector3(0.22, 0.14, 0.20), Vector3(0.56, 0.37, -0.34), _mat(STONE), Vector3(0.0, 30.0, 0.0))
	# barrier and staff
	_add_kit("fence_planks.glb", Vector3(0.50, 0.0, -1.25), 1.9, 12.0)
	_add_cylinder(_vignette, 0.03, 0.035, 1.35, Vector3(-1.55, 0.62, -0.05), _mat(WOOD_DARK), Vector3(0.0, 0.0, 9.0))

func _vignette_purple() -> void:
	# Easel with a painted sky, paint pots, brush and a stool.
	var easel := Node3D.new()
	easel.name = "Easel"
	easel.position = Vector3(-1.05, 0.0, -0.60)
	_vignette.add_child(easel)
	# proper tripod: two front legs + one back leg + crossbar
	_add_box(easel, Vector3(0.05, 1.20, 0.05), Vector3(-0.30, 0.58, 0.05), _mat(WOOD_DARK), Vector3(0.0, 0.0, -9.0))
	_add_box(easel, Vector3(0.05, 1.20, 0.05), Vector3(0.30, 0.58, 0.05), _mat(WOOD_DARK), Vector3(0.0, 0.0, 9.0))
	_add_box(easel, Vector3(0.05, 1.22, 0.05), Vector3(0.0, 0.60, -0.30), _mat(WOOD_DARK), Vector3(16.0, 0.0, 0.0))
	_add_box(easel, Vector3(0.72, 0.06, 0.06), Vector3(0.0, 0.52, 0.02), _mat(WOOD))
	# canvas in a simple wooden frame
	_add_box(easel, Vector3(0.80, 0.62, 0.04), Vector3(0.0, 0.98, 0.07), _mat(WOOD))
	var canvas_material := StandardMaterial3D.new()
	canvas_material.albedo_texture = _make_canvas_texture()
	canvas_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	canvas_material.roughness = 0.95
	canvas_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	canvas_material.emission_enabled = true
	canvas_material.emission = Color(0.34, 0.26, 0.22)
	canvas_material.emission_energy_multiplier = 0.55
	_add_quad(easel, Vector2(0.70, 0.52), Vector3(0.0, 0.98, 0.10), canvas_material, Vector3(-3.0, 0.0, 0.0))
	# tray with paint pots and a brush
	_add_box(easel, Vector3(0.20, 0.05, 0.14), Vector3(0.30, 0.72, 0.10), _mat(WOOD))
	var pot_colors := [Color(0.80, 0.30, 0.26), Color(0.88, 0.72, 0.28), Color(0.38, 0.46, 0.72)]
	for i in 3:
		_add_cylinder(_vignette, 0.035, 0.04, 0.09, Vector3(-0.72 + 0.09 * float(i), 0.06, -0.34), _mat(Color(0.70, 0.62, 0.50)))
		_add_cylinder(_vignette, 0.028, 0.028, 0.02, Vector3(-0.72 + 0.09 * float(i), 0.11, -0.34), _mat(pot_colors[i]))
	_add_cylinder(_vignette, 0.012, 0.014, 0.34, Vector3(-0.48, 0.24, -0.58), _mat(WOOD_DARK), Vector3(0.0, 0.0, -18.0))
	# stool
	_add_cylinder(_vignette, 0.17, 0.18, 0.44, Vector3(-1.45, 0.22, 0.28), _mat(WOOD))

func _add_kite_string(from: Vector3, to: Vector3) -> void:
	var direction := to - from
	var length := direction.length()
	if length < 0.01:
		return
	var string_mesh := CylinderMesh.new()
	string_mesh.top_radius = 0.006
	string_mesh.bottom_radius = 0.006
	string_mesh.height = length
	string_mesh.radial_segments = 4
	var string := MeshInstance3D.new()
	string.mesh = string_mesh
	string.material_override = _mat(Color(0.86, 0.82, 0.72, 1.0))
	string.transform = Transform3D(Basis(Quaternion(Vector3.UP, direction.normalized())), (from + to) * 0.5)
	string.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vignette.add_child(string)

func _vignette_orange() -> void:
	# The carpenter's sawhorse, plank, toolbox and timber stack.
	for sx in [-0.52, 0.52]:
		_add_box(_vignette, Vector3(0.06, 0.78, 0.06), Vector3(sx - 0.14, 0.38, -0.55), _mat(WOOD_DARK), Vector3(0.0, 0.0, 13.0))
		_add_box(_vignette, Vector3(0.06, 0.78, 0.06), Vector3(sx + 0.14, 0.38, -0.55), _mat(WOOD_DARK), Vector3(0.0, 0.0, -13.0))
	_add_box(_vignette, Vector3(1.30, 0.10, 0.24), Vector3(0.0, 0.74, -0.55), _mat(WOOD))
	_add_box(_vignette, Vector3(1.10, 0.06, 0.34), Vector3(0.0, 0.82, -0.55), _mat(Color(0.74, 0.58, 0.38)))
	_add_box(_vignette, Vector3(0.42, 0.24, 0.26), Vector3(-1.18, 0.12, 0.28), _mat(WOOD_DARK))
	_add_box(_vignette, Vector3(0.34, 0.04, 0.22), Vector3(-1.18, 0.26, 0.28), _mat(WOOD))
	_add_cylinder(_vignette, 0.02, 0.02, 0.30, Vector3(-0.30, 0.90, -0.48), _mat(METAL), Vector3(0.0, 0.0, 62.0))
	_add_box(_vignette, Vector3(0.10, 0.06, 0.10), Vector3(-0.36, 0.96, -0.48), _mat(METAL))
	_add_kit("log_stack.glb", Vector3(1.12, 0.0, -0.95), 1.3, 24.0)
	_add_kit("log.glb", Vector3(0.95, 0.0, 0.55), 1.0, -30.0)
	_add_kit("fence_planks.glb", Vector3(-1.55, 0.0, -1.10), 1.6, 80.0)

func _vignette_teal() -> void:
	# The record-keeper's desk: ledger, ink, seal, sundial and the shadow line.
	_add_box(_vignette, Vector3(1.05, 0.07, 0.58), Vector3(-0.92, 0.74, -0.42), _mat(WOOD))
	for sx in [-1.42, -0.42]:
		for sz in [-0.66, -0.16]:
			_add_box(_vignette, Vector3(0.06, 0.70, 0.06), Vector3(sx, 0.35, sz), _mat(WOOD_DARK))
	# open ledger + loose sheets
	_add_box(_vignette, Vector3(0.52, 0.03, 0.36), Vector3(-0.95, 0.79, -0.40), _mat(CREAM))
	_add_box(_vignette, Vector3(0.24, 0.03, 0.34), Vector3(-0.62, 0.79, -0.36), _mat(Color(0.88, 0.86, 0.78)))
	_add_cylinder(_vignette, 0.05, 0.06, 0.10, Vector3(-1.32, 0.83, -0.30), _mat(Color(0.16, 0.16, 0.18)))
	_add_cylinder(_vignette, 0.012, 0.02, 0.34, Vector3(-1.30, 0.99, -0.30), _mat(CREAM), Vector3(0.0, 0.0, -28.0))
	_add_box(_vignette, Vector3(0.12, 0.12, 0.12), Vector3(-0.66, 0.83, -0.54), _mat(Color(0.62, 0.30, 0.26)))
	# sundial + measured shadow line
	_add_cylinder(_vignette, 0.30, 0.32, 0.05, Vector3(0.92, 0.03, 0.52), _mat(STONE))
	_add_box(_vignette, Vector3(0.04, 0.40, 0.04), Vector3(0.92, 0.24, 0.52), _mat(STONE_DARK), Vector3(0.0, 0.0, 18.0))
	_add_box(_vignette, Vector3(1.50, 0.012, 0.04), Vector3(0.20, 0.02, 0.52), _mat(Color(0.90, 0.86, 0.72)))
	# stool and book stack
	_add_cylinder(_vignette, 0.16, 0.17, 0.44, Vector3(-1.45, 0.22, 0.22), _mat(WOOD))
	_add_box(_vignette, Vector3(0.26, 0.05, 0.20), Vector3(-0.22, 0.80, -0.52), _mat(Color(0.50, 0.38, 0.28)))
	_add_box(_vignette, Vector3(0.24, 0.04, 0.19), Vector3(-0.22, 0.845, -0.52), _mat(Color(0.62, 0.50, 0.34)))

func _vignette_pink() -> void:
	# A traveller's picnic spot: basket, paper pinwheel, and a kite on a string.
	_add_kit("pot_large.glb", Vector3(-1.05, 0.0, 0.32), 0.45)
	_add_cylinder(_vignette, 0.16, 0.13, 0.16, Vector3(-1.05, 0.30, 0.32), _mat(Color(0.74, 0.58, 0.36)))
	# paper pinwheel on a stick
	_pinwheel = Node3D.new()
	_pinwheel.name = "Pinwheel"
	_pinwheel.position = Vector3(-1.50, 0.95, -0.15)
	_vignette.add_child(_pinwheel)
	_add_cylinder(_pinwheel, 0.012, 0.012, 1.05, Vector3(0.0, -0.52, 0.0), _mat(WOOD_DARK))
	for i in 4:
		var blade := QuadMesh.new()
		blade.size = Vector2(0.16, 0.16)
		var colors := [Color(0.92, 0.66, 0.72), Color(0.95, 0.90, 0.80), Color(0.86, 0.62, 0.66), Color(0.98, 0.86, 0.74)]
		var blade_quad := MeshInstance3D.new()
		blade_quad.mesh = blade
		blade_quad.material_override = _mat(colors[i], true)
		blade_quad.position = Vector3(0.0, 0.0, 0.0)
		blade_quad.rotation.z = float(i) * PI * 0.5
		_pinwheel.add_child(blade_quad)
	# kite in the air, slowly swaying, with the string held near the NPC
	_kite = Node3D.new()
	_kite.name = "Kite"
	_kite_base = Vector3(1.55, 2.60, -1.10)
	_kite.position = _kite_base
	_vignette.add_child(_kite)
	var kite_body := QuadMesh.new()
	kite_body.size = Vector2(0.52, 0.66)
	var kite_quad := MeshInstance3D.new()
	kite_quad.mesh = kite_body
	kite_quad.material_override = _mat(Color(0.92, 0.56, 0.66), true)
	kite_quad.rotation_degrees = Vector3(-12.0, 32.0, 0.0)
	kite_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_kite.add_child(kite_quad)
	var spar := BoxMesh.new()
	spar.size = Vector3(0.56, 0.02, 0.02)
	var spar_instance := MeshInstance3D.new()
	spar_instance.mesh = spar
	spar_instance.material_override = _mat(WOOD_DARK)
	spar_instance.rotation_degrees = Vector3(0.0, 32.0, 26.0)
	spar_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_kite.add_child(spar_instance)
	for i in 3:
		var tail := BoxMesh.new()
		tail.size = Vector3(0.08, 0.03, 0.03)
		var tail_piece := MeshInstance3D.new()
		tail_piece.mesh = tail
		tail_piece.material_override = _mat(Color(0.96, 0.86, 0.72), true)
		tail_piece.position = Vector3(0.10 * float(i), -0.38 - 0.06 * float(i), 0.0)
		tail_piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_kite.add_child(tail_piece)
	_add_kite_string(Vector3(0.30, 1.05, 0.30), _kite_base - Vector3(0.12, 0.32, 0.0))
	# folded blanket
	_add_box(_vignette, Vector3(0.90, 0.015, 0.62), Vector3(0.95, 0.016, 0.62), _mat(Color(0.86, 0.66, 0.70)))
