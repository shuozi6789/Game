extends Node3D
## HD2D stylised grass field — everything is built procedurally in _ready().
##
## What this script creates:
##   * a 90 x 90 m ground plane (textured with the pixel-art grass tile when the
##     asset exists, otherwise a flat green) plus a StaticBody3D floor at y = -1,
##   * ~30k wind-blown grass blades in one MultiMesh (shader sway, no CPU cost),
##   * a worn spawn clearing with short tufts and a soft dirt tint,
##   * Kenney Nature Kit (CC0) GLB trees / rocks / bushes, scattered with a seeded
##     RNG, plus a dense 32-42 m tree ring to frame the horizon,
##   * pixel-art flower quads,
##   * warm sun + cool fill light, procedural sky, filmic tonemap, warm haze fog.
##
## Design notes
##   * 1 world unit = 40 screen px with the project's orthographic camera (size 9),
##     so the ground stays exactly at y = 0 and the hero spawns in a 7 m clearing.
##   * The camera is orthographic and pitched down, so it sees roughly a 16 x 15 m
##     slab of ground around the player. Props are dense inside that slab; the
##     32-42 m tree ring is horizon insurance for when the camera is zoomed out.
##   * No per-frame script work: wind lives in grass.gdshader, props are static
##     MultiMeshes. The whole world is a handful of draw calls.
##
## Tuning: see docs/WORLD.md; every number below is meant to be edited.

# =============================================================================
# TUNING CONSTANTS
# =============================================================================

# --- optional files from the asset pipeline ----------------------------------
const GROUND_TEXTURE_PATH := "res://assets/generated/grass_ground.png"
const BLADE_TEXTURE_PATH := "res://assets/generated/grass_blade.png"
const FLOWER_WHITE_PATH := "res://assets/generated/flower_white.png"
const FLOWER_YELLOW_PATH := "res://assets/generated/flower_yellow.png"
const GRASS_SHADER_PATH := "res://shaders/world/grass.gdshader"

# --- Kenney Nature Kit (CC0) low-poly props ----------------------------------
const KIT_DIR := "res://assets/free/kenney_nature_kit/models/"
const TREE_MODELS := [
	"tree_default.glb",
	"tree_oak.glb",
	"tree_detailed.glb",
	"tree_fat.glb",
	"tree_oak_fall.glb"
]
const ROCK_MODELS := ["rock_smallA.glb", "rock_smallC.glb", "rock_largeA.glb"]
const BUSH_MODELS := ["plant_bush.glb", "plant_bushSmall.glb"]
# Warm-green grade multiplied onto the imported palette (teal leaves -> greener,
# orange "fall" leaves -> warmer gold). Set to Color(1,1,1,1) to disable.
const PROP_TINT := Color(1.0, 1.06, 0.80, 1.0)

# --- ground ------------------------------------------------------------------
const GROUND_SIZE := 90.0
const GROUND_UV_TILES := 7.0
const GROUND_FALLBACK_COLOR := Color(0.30, 0.43, 0.21, 1.0)
const BACKDROP_SIZE := 260.0
const BACKDROP_DROP := 0.04

# --- spawn clearing ----------------------------------------------------------
const CLEARING_RADIUS := 3.5
const CLEARING_TINT_ENABLED := true
const CLEARING_TINT_RADIUS := 5.0
const CLEARING_TINT_ALPHA := 0.30
const CLEARING_TUFT_CLUMPS := 40
const CLEARING_TUFT_BLADES := 10
const CLEARING_TUFT_HEIGHT := 0.22

# --- grass field -------------------------------------------------------------
const GRASS_GRID := 0.40
const GRASS_EXTENT := 44.0
const BLADE_WIDTH := 0.30
const BLADE_HEIGHT := 0.46
const BLADE_HEIGHT_MIN := 0.62
const BLADE_HEIGHT_MAX := 1.35
const BLADE_WIDTH_MIN := 0.72
const BLADE_WIDTH_MAX := 1.28

# --- wind (keep in sync with the shader defaults) ---------------------------
const WIND_STRENGTH := 0.085
const WIND_SPEED := 1.70
const WIND_DIRECTION := Vector2(0.86, 0.50)

# --- trees / props -----------------------------------------------------------
const SEED := 20261108
const TREE_SCATTER_COUNT := 22
const TREE_SCATTER_MIN := 9.5
const TREE_SCATTER_MAX := 30.0
const TREE_RING_COUNT := 68
const TREE_RING_INNER := 32.0
const TREE_RING_OUTER := 42.0
const TREE_MIN_SPACING := 3.0
const ROCK_COUNT := 14
const BUSH_COUNT := 12
const FLOWER_COUNT := 55
const FLOWER_CLEARING_COUNT := 20
const PROP_MIN_SPACING := 1.4

# --- lighting / atmosphere ---------------------------------------------------
const SUN_COLOR := Color(1.0, 0.89, 0.70, 1.0)
const SUN_ENERGY := 1.35
const SUN_ROTATION_DEG := Vector3(-40.0, -33.0, 0.0)
const SUN_SHADOW_DISTANCE := 80.0
const FILL_LIGHT_ENABLED := true
const AMBIENT_ENERGY := 0.30
const FOG_DENSITY := 0.004
const FOG_COLOR := Color(0.72, 0.78, 0.68, 1.0)
const SKY_TOP_COLOR := Color(0.18, 0.42, 0.74, 1.0)
const SKY_HORIZON_COLOR := Color(0.79, 0.87, 0.95, 1.0)
const SKY_GROUND_BOTTOM := Color(0.15, 0.20, 0.12, 1.0)
const SKY_GROUND_HORIZON := Color(0.62, 0.68, 0.55, 1.0)

# =============================================================================
# STATE
# =============================================================================

const SPOT_NONE := Vector2(1.0e6, 1.0e6)

var _rng := RandomNumberGenerator.new()
var _occupied: Array[Vector2] = []

# =============================================================================
# ENTRY POINT
# =============================================================================

func _ready() -> void:
	_rng.seed = SEED
	_build_environment()
	_build_ground()
	_build_clearing()
	var blade_count := _build_grass()
	var tree_count := _build_tree_field()
	_build_rocks()
	_build_bushes()
	_build_flowers()
	print("[world] ready — blades=%d trees=%d objects=%d" % [blade_count, tree_count, get_child_count()])

# =============================================================================
# SKY / LIGHTING / FOG
# =============================================================================

func _build_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = SKY_TOP_COLOR
	sky_material.sky_horizon_color = SKY_HORIZON_COLOR
	sky_material.sky_curve = 0.14
	sky_material.sky_energy_multiplier = 1.10
	sky_material.ground_bottom_color = SKY_GROUND_BOTTOM
	sky_material.ground_horizon_color = SKY_GROUND_HORIZON
	sky_material.ground_curve = 0.06
	sky_material.sun_angle_max = 24.0
	sky_material.sun_curve = 0.12

	var sky := Sky.new()
	sky.sky_material = sky_material

	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.72, 0.80, 0.66, 1.0)
	environment.ambient_light_energy = AMBIENT_ENERGY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 0.92
	environment.glow_enabled = true
	environment.glow_intensity = 0.10
	environment.glow_hdr_threshold = 1.4
	environment.fog_enabled = true
	environment.fog_light_color = FOG_COLOR
	environment.fog_density = FOG_DENSITY
	environment.fog_sun_scatter = 0.25
	environment.fog_aerial_perspective = 0.30
	environment.adjustment_enabled = true
	environment.adjustment_saturation = 1.18
	environment.adjustment_contrast = 1.08

	# HD2D signature: the 3D backdrop falls out of focus while the pixel hero
	# stays sharp. In Godot 4 depth of field lives on CameraAttributesPractical.
	var attributes := CameraAttributesPractical.new()
	attributes.dof_blur_far_enabled = true
	attributes.dof_blur_far_distance = 24.0
	attributes.dof_blur_far_transition = 18.0
	attributes.dof_blur_amount = 0.08

	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = environment
	world_environment.camera_attributes = attributes
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = SUN_ROTATION_DEG
	sun.light_color = SUN_COLOR
	sun.light_energy = SUN_ENERGY
	sun.shadow_enabled = true
	sun.directional_shadow_mode = 2 # DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = SUN_SHADOW_DISTANCE
	sun.shadow_blur = 1.0
	add_child(sun)

	if FILL_LIGHT_ENABLED:
		# Cool sky-bounce fill so shadow sides keep some colour, no shadows.
		var fill := DirectionalLight3D.new()
		fill.name = "FillLight"
		fill.rotation_degrees = Vector3(-26.0, 148.0, 0.0)
		fill.light_color = Color(0.70, 0.80, 0.95, 1.0)
		fill.light_energy = 0.10
		fill.shadow_enabled = false
		add_child(fill)

# =============================================================================
# GROUND
# =============================================================================

func _build_ground() -> void:
	var ground_material := StandardMaterial3D.new()
	ground_material.roughness = 1.0
	ground_material.metallic = 0.0
	ground_material.uv1_scale = Vector3(GROUND_UV_TILES, GROUND_UV_TILES, 1.0)
	ground_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	var ground_texture := _load_texture(GROUND_TEXTURE_PATH)
	if ground_texture != null:
		ground_material.albedo_texture = ground_texture
		ground_material.albedo_color = Color(0.74, 0.84, 0.70, 1.0)
	else:
		ground_material.albedo_color = GROUND_FALLBACK_COLOR

	# Playable floor: exactly 90 x 90 m, top surface precisely at y = 0.
	var plane := PlaneMesh.new()
	plane.size = Vector2(GROUND_SIZE, GROUND_SIZE)
	plane.material = ground_material
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = plane
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)

	# Visual-only skirt a few cm below the playable floor: at +-45 m the camera
	# would otherwise see the edge of the world. No collision, no gameplay role.
	var skirt_material := ground_material.duplicate() as StandardMaterial3D
	if skirt_material != null:
		var uv_ratio := BACKDROP_SIZE / GROUND_SIZE
		skirt_material.uv1_scale = Vector3(GROUND_UV_TILES * uv_ratio, GROUND_UV_TILES * uv_ratio, 1.0)
	var skirt_plane := PlaneMesh.new()
	skirt_plane.size = Vector2(BACKDROP_SIZE, BACKDROP_SIZE)
	skirt_plane.material = skirt_material
	var skirt := MeshInstance3D.new()
	skirt.name = "GroundBackdrop"
	skirt.mesh = skirt_plane
	skirt.position = Vector3(0.0, -BACKDROP_DROP, 0.0)
	skirt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(skirt)

	# Invisible floor collider (player collision_layer = 2, mask = 1).
	var body := StaticBody3D.new()
	body.name = "GroundBody"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(GROUND_SIZE, 2.0, GROUND_SIZE)
	shape.shape = box
	shape.position = Vector3(0.0, -1.0, 0.0)
	body.add_child(shape)
	add_child(body)

# =============================================================================
# SPAWN CLEARING
# =============================================================================

func _build_clearing() -> void:
	if not CLEARING_TINT_ENABLED:
		return
	var tint_material := StandardMaterial3D.new()
	tint_material.albedo_color = Color(0.20, 0.17, 0.11, CLEARING_TINT_ALPHA)
	tint_material.albedo_texture = _make_radial_texture(64)
	tint_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tint_material.roughness = 1.0
	tint_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	tint_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	var quad := QuadMesh.new()
	quad.size = Vector2(CLEARING_TINT_RADIUS * 2.0, CLEARING_TINT_RADIUS * 2.0)
	quad.material = tint_material
	var tint := MeshInstance3D.new()
	tint.name = "ClearingTint"
	tint.mesh = quad
	tint.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	tint.position = Vector3(0.0, 0.012, 0.0)
	tint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(tint)

# =============================================================================
# GRASS
# =============================================================================

func _build_grass() -> int:
	var blade_mesh := QuadMesh.new()
	blade_mesh.size = Vector2(BLADE_WIDTH, BLADE_HEIGHT)

	var blade_material: Material
	var shader := _load_shader(GRASS_SHADER_PATH)
	if shader != null:
		var shader_material := ShaderMaterial.new()
		shader_material.shader = shader
		shader_material.set_shader_parameter("wind_strength", WIND_STRENGTH)
		shader_material.set_shader_parameter("wind_speed", WIND_SPEED)
		shader_material.set_shader_parameter("wind_direction", WIND_DIRECTION)
		shader_material.set_shader_parameter("blade_height", BLADE_HEIGHT)
		var blade_texture := _load_texture(BLADE_TEXTURE_PATH)
		if blade_texture != null:
			shader_material.set_shader_parameter("blade_tex", blade_texture)
		else:
			push_warning("[world] grass_blade.png missing — using untextured quads")
		blade_material = shader_material
	else:
		var flat := StandardMaterial3D.new()
		flat.albedo_color = Color(0.30, 0.52, 0.20, 1.0)
		flat.cull_mode = BaseMaterial3D.CULL_DISABLED
		flat.roughness = 1.0
		blade_material = flat
	blade_mesh.material = blade_material

	# --- dense field: jittered 0.5 m grid, clear of the spawn clearing -------
	var positions: Array[Vector3] = []
	var cells := int(round((GRASS_EXTENT * 2.0) / GRASS_GRID))
	var jitter := GRASS_GRID * 0.48
	var clearing_sq := CLEARING_RADIUS * CLEARING_RADIUS
	for gz in cells:
		for gx in cells:
			var px := (float(gx) + 0.5) * GRASS_GRID - GRASS_EXTENT + _rng.randf_range(-jitter, jitter)
			var pz := (float(gz) + 0.5) * GRASS_GRID - GRASS_EXTENT + _rng.randf_range(-jitter, jitter)
			if px * px + pz * pz < clearing_sq:
				continue
			# Large-scale density patches so the field is not a uniform carpet.
			var density := 0.72 + 0.28 * sin(px * 0.13 + 0.8) * sin(pz * 0.11 - 0.4)
			if _rng.randf() > density:
				continue
			positions.append(Vector3(px, 0.0, pz))

	# One 12-float transform per blade: basis columns (R_y * scale) then origin.
	# Blade quads are centred on their own origin, so origin.y = height / 2 puts
	# the base exactly on y = 0.
	var count := positions.size()
	var transforms := PackedFloat32Array()
	transforms.resize(count * 12)
	var customs := PackedColorArray()
	customs.resize(count)
	for i in count:
		var yaw := _rng.randf() * TAU
		var cos_yaw := cos(yaw)
		var sin_yaw := sin(yaw)
		var width_scale := _rng.randf_range(BLADE_WIDTH_MIN, BLADE_WIDTH_MAX)
		var height_scale := _rng.randf_range(BLADE_HEIGHT_MIN, BLADE_HEIGHT_MAX)
		var base := positions[i]
		var offset := i * 12
		transforms[offset + 0] = cos_yaw * width_scale
		transforms[offset + 1] = 0.0
		transforms[offset + 2] = -sin_yaw * width_scale
		transforms[offset + 3] = base.x
		transforms[offset + 4] = 0.0
		transforms[offset + 5] = height_scale
		transforms[offset + 6] = 0.0
		transforms[offset + 7] = BLADE_HEIGHT * height_scale * 0.5
		transforms[offset + 8] = sin_yaw * width_scale
		transforms[offset + 9] = 0.0
		transforms[offset + 10] = cos_yaw * width_scale
		transforms[offset + 11] = base.z
		customs[i] = Color(_rng.randf(), clampf(0.5 + 0.5 * sin(base.x * 0.19 + 1.3) * sin(base.z * 0.23 - 0.7), 0.0, 1.0), 0.0, 1.0)

	_add_grass_multimesh("Grass", blade_mesh, transforms, customs)

	# --- short tufts inside the clearing so it reads as trampled grass --------
	var tuft_transforms := Array()
	var tuft_customs := PackedColorArray()
	for clump in CLEARING_TUFT_CLUMPS:
		var clump_angle := _rng.randf() * TAU
		var clump_radius := sqrt(_rng.randf()) * (CLEARING_RADIUS - 0.9)
		var clump_x := cos(clump_angle) * clump_radius
		var clump_z := sin(clump_angle) * clump_radius
		for blade in CLEARING_TUFT_BLADES:
			var spread_angle := _rng.randf() * TAU
			var spread := _rng.randf_range(0.04, 0.45)
			var tuft_height := CLEARING_TUFT_HEIGHT * _rng.randf_range(0.55, 1.4)
			var tuft_scale_y := tuft_height / BLADE_HEIGHT
			_push_blade_xform(
				tuft_transforms,
				Vector2(clump_x + cos(spread_angle) * spread, clump_z + sin(spread_angle) * spread),
				_rng.randf() * TAU,
				_rng.randf_range(0.7, 1.05),
				tuft_scale_y,
				tuft_height * 0.5)
			tuft_customs.append(Color(_rng.randf(), 0.45, 0.0, 1.0))
	if not tuft_transforms.is_empty():
		_add_grass_multimesh("ClearingTufts", blade_mesh, PackedFloat32Array(tuft_transforms), tuft_customs)

	return count

func _floats_to_vec3_transforms(floats: PackedFloat32Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	var count := floats.size() / 12
	out.resize(count * 4)
	var o := 0
	for i in count:
		var f := i * 12
		out[o + 0] = Vector3(floats[f + 0], floats[f + 1], floats[f + 2])
		out[o + 1] = Vector3(floats[f + 4], floats[f + 5], floats[f + 6])
		out[o + 2] = Vector3(floats[f + 8], floats[f + 9], floats[f + 10])
		out[o + 3] = Vector3(floats[f + 3], floats[f + 7], floats[f + 11])
		o += 4
	return out

func _add_grass_multimesh(node_name: String, mesh: Mesh, transforms: PackedFloat32Array, customs: PackedColorArray) -> void:
	var count := int(transforms.size() / 12)
	if count <= 0:
		return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.use_custom_data = true
	multimesh.instance_count = count
	# Godot 4.7 stores MultiMesh transforms as a PackedVector3Array of
	# (basis.x, basis.y, basis.z, origin) per instance; our blade builder keeps a
	# flat 12-float buffer (x,y,z,ox per row), so repack it here.
	multimesh.transform_array = _floats_to_vec3_transforms(transforms)
	multimesh.custom_data_array = customs
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	# Blades do not cast shadows: 30k shadow casters would be wasted fill rate.
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)

# Appends one 12-float blade transform to a plain Array (later packed by caller).
func _push_blade_xform(out: Array, pos: Vector2, yaw: float, scale_x: float, scale_y: float, y_offset: float) -> void:
	var cos_yaw := cos(yaw)
	var sin_yaw := sin(yaw)
	out.append(cos_yaw * scale_x)
	out.append(0.0)
	out.append(-sin_yaw * scale_x)
	out.append(pos.x)
	out.append(0.0)
	out.append(scale_y)
	out.append(0.0)
	out.append(y_offset)
	out.append(sin_yaw * scale_x)
	out.append(0.0)
	out.append(cos_yaw * scale_x)
	out.append(pos.y)

# =============================================================================
# TREES
# =============================================================================

func _build_tree_field() -> int:
	# Spots are gathered first, then split over the available tree models so each
	# model becomes one (or two) MultiMesh draw calls.
	var spots: Array[Dictionary] = []

	# 1) Hand-placed framing trees just outside the clearing: they define the
	#    opening shot and throw long shadows across the spawn area.
	var frame_spots: Array[Vector2] = [
		Vector2(-7.9, 2.2),
		Vector2(7.7, 3.6),
		Vector2(-6.9, -1.6),
		Vector2(7.0, -1.2),
	]
	for spot in frame_spots:
		_occupied.append(spot)
		spots.append({"pos": spot, "height": _rng.randf_range(3.2, 4.2), "collide": true})

	# 2) Scattered trees, seeded RNG, clear of the clearing and of each other.
	for i in TREE_SCATTER_COUNT:
		var spot := _find_spot(TREE_SCATTER_MIN, TREE_SCATTER_MAX, TREE_MIN_SPACING)
		if spot == SPOT_NONE:
			continue
		_occupied.append(spot)
		spots.append({"pos": spot, "height": _rng.randf_range(2.8, 4.2), "collide": true})

	# 3) Dense ring at 32-42 m: frames / hides the horizon when zoomed out.
	var ring_step := TAU / float(TREE_RING_COUNT)
	for i in TREE_RING_COUNT:
		var angle := ring_step * float(i) + _rng.randf_range(-ring_step * 0.28, ring_step * 0.28)
		var radius := _rng.randf_range(TREE_RING_INNER, TREE_RING_OUTER)
		var spot := Vector2(cos(angle), sin(angle)) * radius
		_occupied.append(spot)
		spots.append({"pos": spot, "height": _rng.randf_range(4.5, 6.0), "collide": false})

	var variants: Array[Dictionary] = []
	for file_name in TREE_MODELS:
		var model := _load_model(KIT_DIR + file_name)
		if not model.is_empty():
			variants.append(model)
	if variants.is_empty():
		push_warning("[world] no Kenney tree models loaded — falling back to primitive trees")
		return _build_primitive_trees(spots)

	var buckets: Array = []
	for i in variants.size():
		buckets.append([])
	for i in spots.size():
		var bucket: Array = buckets[i % variants.size()]
		bucket.append(spots[i])
	for i in variants.size():
		_add_model_instances("Tree_%d" % i, variants[i], buckets[i], true, -1.0)

	for entry in spots:
		if entry["collide"]:
			var pos: Vector2 = entry["pos"]
			var height: float = entry["height"]
			_add_cylinder_collision(pos, maxf(0.20, height * 0.045), maxf(2.0, height * 0.55))
	return spots.size()

# Last-resort primitive trees (used only if the GLB kit is unavailable).
func _build_primitive_trees(spots: Array[Dictionary]) -> int:
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.09
	trunk_mesh.bottom_radius = 0.17
	trunk_mesh.height = 1.0
	trunk_mesh.radial_segments = 7
	trunk_mesh.material = _flat_material(Color(0.30, 0.22, 0.16, 1.0))

	var leaf_mesh := SphereMesh.new()
	leaf_mesh.radius = 1.0
	leaf_mesh.height = 2.0
	leaf_mesh.radial_segments = 8
	leaf_mesh.rings = 5
	leaf_mesh.material = _flat_material(Color(0.17, 0.36, 0.14, 1.0))

	var trunk_xforms: Array[Transform3D] = []
	var leaf_xforms: Array[Transform3D] = []
	for entry in spots:
		var pos: Vector2 = entry["pos"]
		var height: float = entry["height"]
		var trunk_height := height * 0.62
		var trunk_radius := maxf(0.75, height * 0.16)
		trunk_xforms.append(Transform3D(
			Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(trunk_radius, trunk_height, trunk_radius)),
			Vector3(pos.x, trunk_height * 0.5, pos.y)))
		var canopy_radius := height * 0.28
		for blob in 2:
			var blob_radius := canopy_radius * _rng.randf_range(0.85, 1.1)
			var offset := Vector2(_rng.randf_range(-0.3, 0.3), _rng.randf_range(-0.3, 0.3)) * canopy_radius
			leaf_xforms.append(Transform3D(
				Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(blob_radius, blob_radius * 0.8, blob_radius)),
				Vector3(pos.x + offset.x, trunk_height * (0.85 + 0.16 * float(blob)) + blob_radius * 0.45, pos.y + offset.y)))
	_add_transform_multimesh("TreeTrunks", trunk_mesh, trunk_xforms, true)
	_add_transform_multimesh("TreeCanopy", leaf_mesh, leaf_xforms, true)

	for entry in spots:
		if entry["collide"]:
			var pos: Vector2 = entry["pos"]
			var height: float = entry["height"]
			_add_cylinder_collision(pos, maxf(0.20, height * 0.045), maxf(2.0, height * 0.55))
	return spots.size()

# =============================================================================
# ROCKS / BUSHES / FLOWERS
# =============================================================================

func _build_rocks() -> void:
	var models: Array[Dictionary] = []
	for file_name in ROCK_MODELS:
		var model := _load_model(KIT_DIR + file_name)
		if not model.is_empty():
			models.append(model)
	if models.is_empty():
		return
	var buckets: Array = []
	for i in models.size():
		buckets.append([])
	for i in ROCK_COUNT:
		var spot := _find_spot(9.0, 34.0, 1.8)
		if spot == SPOT_NONE:
			continue
		_occupied.append(spot)
		var size := _rng.randf_range(0.45, 1.15)
		var bucket: Array = buckets[i % models.size()]
		bucket.append({"pos": spot, "height": size})
		if size > 0.65:
			_add_sphere_collision(spot, size * 0.42, size * 0.28)
	for i in models.size():
		_add_model_instances("Rock_%d" % i, models[i], buckets[i], true, _model_max_extent(models[i]))

func _build_bushes() -> void:
	var models: Array[Dictionary] = []
	for file_name in BUSH_MODELS:
		var model := _load_model(KIT_DIR + file_name)
		if not model.is_empty():
			models.append(model)
	if models.is_empty():
		return
	var buckets: Array = []
	for i in models.size():
		buckets.append([])
	for i in BUSH_COUNT:
		var spot := _find_spot(7.2, 26.0, PROP_MIN_SPACING)
		if spot == SPOT_NONE:
			continue
		_occupied.append(spot)
		var size := _rng.randf_range(0.55, 1.15)
		var bucket: Array = buckets[i % models.size()]
		bucket.append({"pos": spot, "height": size})
	for i in models.size():
		_add_model_instances("Bush_%d" % i, models[i], buckets[i], true, _model_max_extent(models[i]))

func _build_flowers() -> void:
	var white_texture := _load_texture(FLOWER_WHITE_PATH)
	var yellow_texture := _load_texture(FLOWER_YELLOW_PATH)
	if white_texture == null and yellow_texture == null:
		return
	var white_xforms: Array[Transform3D] = []
	var yellow_xforms: Array[Transform3D] = []
	var total := FLOWER_COUNT + FLOWER_CLEARING_COUNT
	for i in total:
		var angle := _rng.randf() * TAU
		var radius := 1.2 + sqrt(_rng.randf()) * 21.0
		var pos := Vector2(cos(angle), sin(angle)) * radius
		var xform := Transform3D(
			Basis(Vector3.UP, _rng.randf() * TAU),
			Vector3(pos.x, 0.12, pos.y))
		if i % 2 == 0:
			white_xforms.append(xform)
		else:
			yellow_xforms.append(xform)
	var size := Vector2(0.17, 0.17)
	if white_texture != null:
		var white_mesh := QuadMesh.new()
		white_mesh.size = size
		white_mesh.material = _flower_material(white_texture)
		_add_transform_multimesh("FlowersWhite", white_mesh, white_xforms, true)
	if yellow_texture != null:
		var yellow_mesh := QuadMesh.new()
		yellow_mesh.size = size
		yellow_mesh.material = _flower_material(yellow_texture)
		_add_transform_multimesh("FlowersYellow", yellow_mesh, yellow_xforms, true)

func _flower_material(texture: Texture2D) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material

# =============================================================================
# KENNEY GLB HELPERS
# =============================================================================

# Loads a GLB into { "parts": [{mesh, transform, material}], "aabb": AABB }.
# Returns an empty Dictionary when the model cannot be loaded.
func _load_model(path: String) -> Dictionary:
	if not ResourceLoader.exists(path):
		push_warning("[world] model missing: " + path)
		return {}
	var packed := load(path) as PackedScene
	if packed == null:
		push_warning("[world] not a PackedScene: " + path)
		return {}
	var root := packed.instantiate()
	if root == null:
		return {}
	var parts: Array = []
	_collect_mesh_parts(root, Transform3D.IDENTITY, parts)
	root.free()
	if parts.is_empty():
		push_warning("[world] no meshes in: " + path)
		return {}
	var bounds := AABB()
	var first := true
	for part in parts:
		var part_transform: Transform3D = part["transform"]
		var part_mesh: Mesh = part["mesh"]
		var part_bounds := _transform_aabb(part_transform, part_mesh.get_aabb())
		if first:
			bounds = part_bounds
			first = false
		else:
			bounds = _merge_aabb(bounds, part_bounds)
	return {"parts": parts, "aabb": bounds}

func _collect_mesh_parts(node: Node, parent_transform: Transform3D, out: Array) -> void:
	var local_transform := parent_transform
	if node is Node3D:
		local_transform = parent_transform * (node as Node3D).transform
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null and mesh_instance.visible:
			out.append({
				"mesh": mesh_instance.mesh,
				"transform": local_transform,
				"material": mesh_instance.material_override,
			})
	for child in node.get_children():
		_collect_mesh_parts(child, local_transform, out)

# Creates one MultiMeshInstance3D per model part, instancing "entries"
# ({ "pos": Vector2, "height": float }) with a seeded yaw / scale jitter.
# reference_size <= 0 means "normalise by model height", otherwise the caller
# supplies the reference extent (used for rocks / bushes).
func _add_model_instances(node_name: String, model: Dictionary, entries: Array, cast_shadow: bool, reference_size: float) -> void:
	if entries.is_empty():
		return
	var parts: Array = model["parts"]
	var bounds: AABB = model["aabb"]
	var reference := reference_size
	if reference <= 0.0:
		reference = maxf(bounds.size.y, 0.001)
	for part_index in parts.size():
		var part: Dictionary = parts[part_index]
		var mesh: Mesh = part["mesh"]
		var relative: Transform3D = part["transform"]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		# Kenney meshes are multi-surface (trunk + foliage) and their glTF
		# materials are fully metallic; tint per surface on a duplicated mesh so
		# the shared MultiMesh material cannot flatten the two colours.
		multimesh.mesh = _mesh_with_tinted_surfaces(mesh)
		multimesh.instance_count = entries.size()
		for i in entries.size():
			var entry: Dictionary = entries[i]
			var pos: Vector2 = entry["pos"]
			var target_height: float = entry["height"]
			var uniform_scale := (target_height / reference) * _rng.randf_range(0.92, 1.10)
			var basis := Basis(Vector3.UP, _rng.randf() * TAU).scaled(
				Vector3(uniform_scale, uniform_scale, uniform_scale))
			# Drop the model so its lowest point sits exactly on y = 0.
			var origin := Vector3(pos.x, -bounds.position.y * uniform_scale, pos.y)
			multimesh.set_instance_transform(i, Transform3D(basis, origin) * relative)
		var instance := MultiMeshInstance3D.new()
		instance.name = node_name if parts.size() == 1 else "%s_%d" % [node_name, part_index]
		instance.multimesh = multimesh
		instance.material_override = _part_material(part, mesh)
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)

func _mesh_with_tinted_surfaces(mesh: Mesh) -> Mesh:
	var count := mesh.get_surface_count()
	if count == 0:
		return mesh
	var copy: Mesh = null
	for s in count:
		var surface_material := mesh.surface_get_material(s)
		if surface_material == null:
			continue
		if copy == null:
			copy = mesh.duplicate() as Mesh
		copy.surface_set_material(s, _tint_material(surface_material))
	return copy if copy != null else mesh

func _part_material(part: Dictionary, mesh: Mesh) -> Material:
	var direct := part.get("material") as Material
	if direct != null:
		return _tint_material(direct)
	var surface_count := mesh.get_surface_count()
	if surface_count <= 0:
		return null
	var first := mesh.surface_get_material(0)
	if first == null:
		return null
	for i in range(1, surface_count):
		if mesh.surface_get_material(i) != first:
			return null # multi-material mesh: leave its own surfaces alone
	return _tint_material(first)

func _tint_material(material: Material) -> Material:
	if material == null:
		return null
	if not (material is StandardMaterial3D):
		return material
	var base := material as StandardMaterial3D
	var copy := base.duplicate() as StandardMaterial3D
	if copy == null:
		return base
	# Kenney's stylised palette uses mint/teal foliage. Pull teal hues back to
	# grass green while leaving wood (orange/tan) and gold "fall" leaves alone.
	var col := base.albedo_color
	var hue := col.h
	var sat := col.s
	var val := col.v
	if hue > 0.36 and hue < 0.58 and sat > 0.15:
		hue = 0.27
		sat = minf(1.0, sat * 0.95)
		val *= 0.52
		col = Color.from_hsv(hue, sat, val, col.a)
	elif hue < 0.12 and val > 0.60:
		# Pale tan wood -> warm bark brown.
		val *= 0.72
		col = Color.from_hsv(hue, sat, val, col.a)
	copy.albedo_color = Color(
		col.r * PROP_TINT.r,
		col.g * PROP_TINT.g,
		col.b * PROP_TINT.b,
		col.a)
	# glTF's default metallicFactor is 1.0, so untextured Kenney materials import
	# as fully metallic and mirror the blue sky (the "cyan trees" bug). Stylised
	# matte props: no metal, full roughness.
	copy.metallic = 0.0
	copy.metallic_specular = 0.2
	copy.roughness = 1.0
	return copy

# =============================================================================
# GENERIC MULTIMESH HELPERS
# =============================================================================

func _add_transform_multimesh(node_name: String, mesh: Mesh, xforms: Array, cast_shadow: bool) -> void:
	if xforms.is_empty():
		return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = xforms.size()
	for i in xforms.size():
		var xform: Transform3D = xforms[i]
		multimesh.set_instance_transform(i, xform)
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)

func _flat_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	material.metallic = 0.0
	return material

# =============================================================================
# COLLISION HELPERS (props are static, physics layer 1 = World)
# =============================================================================

func _add_cylinder_collision(pos: Vector2, radius: float, height: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = Vector3(pos.x, 0.0, pos.y)
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = maxf(radius, 0.15)
	cylinder.height = maxf(height, 1.0)
	shape.shape = cylinder
	shape.position = Vector3(0.0, cylinder.height * 0.5, 0.0)
	body.add_child(shape)
	add_child(body)

func _add_sphere_collision(pos: Vector2, radius: float, center_height: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = Vector3(pos.x, 0.0, pos.y)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = maxf(radius, 0.15)
	shape.shape = sphere
	shape.position = Vector3(0.0, maxf(center_height, sphere.radius * 0.5), 0.0)
	body.add_child(shape)
	add_child(body)

# =============================================================================
# MATH / TEXTURE / RESOURCE HELPERS
# =============================================================================

func _transform_aabb(xform: Transform3D, box: AABB) -> AABB:
	var min_point := Vector3(INF, INF, INF)
	var max_point := Vector3(-INF, -INF, -INF)
	for ix in 2:
		for iy in 2:
			for iz in 2:
				var corner := xform * Vector3(
					box.position.x + box.size.x * float(ix),
					box.position.y + box.size.y * float(iy),
					box.position.z + box.size.z * float(iz))
				min_point = Vector3(minf(min_point.x, corner.x), minf(min_point.y, corner.y), minf(min_point.z, corner.z))
				max_point = Vector3(maxf(max_point.x, corner.x), maxf(max_point.y, corner.y), maxf(max_point.z, corner.z))
	return AABB(min_point, max_point - min_point)

func _merge_aabb(a: AABB, b: AABB) -> AABB:
	var min_point := Vector3(
		minf(a.position.x, b.position.x),
		minf(a.position.y, b.position.y),
		minf(a.position.z, b.position.z))
	var max_point := Vector3(
		maxf(a.position.x + a.size.x, b.position.x + b.size.x),
		maxf(a.position.y + a.size.y, b.position.y + b.size.y),
		maxf(a.position.z + a.size.z, b.position.z + b.size.z))
	return AABB(min_point, max_point - min_point)

func _model_max_extent(model: Dictionary) -> float:
	var bounds: AABB = model["aabb"]
	return maxf(bounds.size.x, maxf(bounds.size.y, maxf(bounds.size.z, 0.001)))

func _make_radial_texture(size: int) -> ImageTexture:
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half := float(size) * 0.5
	for y in size:
		for x in size:
			var dx := (float(x) + 0.5 - half) / half
			var dy := (float(y) + 0.5 - half) / half
			var distance := clampf(1.0 - sqrt(dx * dx + dy * dy), 0.0, 1.0)
			var alpha := distance * distance
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(image)

func _load_texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	var resource: Resource = load(path)
	if resource is Texture2D:
		return resource as Texture2D
	return null

func _load_shader(path: String) -> Shader:
	if not ResourceLoader.exists(path):
		push_warning("[world] shader missing: " + path)
		return null
	var resource: Resource = load(path)
	if resource is Shader:
		return resource as Shader
	push_warning("[world] not a shader: " + path)
	return null

# =============================================================================
# SCATTER HELPERS (seeded, deterministic)
# =============================================================================

func _scatter_ring(min_radius: float, max_radius: float) -> Vector2:
	var angle := _rng.randf() * TAU
	var radius := sqrt(_rng.randf_range(min_radius * min_radius, max_radius * max_radius))
	return Vector2(cos(angle), sin(angle)) * radius

func _find_spot(min_radius: float, max_radius: float, clearance: float) -> Vector2:
	for attempt in 32:
		var pos := _scatter_ring(min_radius, max_radius)
		if _is_free(pos, clearance):
			return pos
	return SPOT_NONE

func _is_free(pos: Vector2, clearance: float) -> bool:
	var clearance_sq := clearance * clearance
	for other in _occupied:
		if pos.distance_squared_to(other) < clearance_sq:
			return false
	return true
