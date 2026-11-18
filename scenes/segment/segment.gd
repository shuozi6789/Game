extends Node3D
## HD2D narrative segment builder.
##
## A segment is one small, self-contained slice of the 8-segment walk:
##   * a flat 120 x 120 m ground plane (pixel grass tile when the asset exists),
##     a StaticBody3D floor + 4 invisible perimeter walls,
##   * one winding dirt-path ribbon smoothed from `path_points`,
##   * a jittered field of shader-wind grass (one MultiMesh, no shadows),
##   * Kenney Nature Kit trees / rocks / bushes + pixel flower quads,
##   * sky, sun, fill light, fog, tonemap / glow / saturation / far DOF,
##   * an exit Area3D with a lit stone landmark that fires `exit_reached` once.
##
## NOTHING is built in _ready(). The game manager owns the order:
##     add_child(segment)
##     segment.setup(config)
##     player.global_position = segment.get_player_start()
##     ... spawn NPC at segment.get_npc_position() ...
##     await segment.exit_reached
## so setup() is the only entry point and it runs exactly once.
##
## config schema: scripts/game/segment_presets.gd (see also docs/SEGMENTS.md).
## Missing keys fall back to DEFAULT_CONFIG, which mirrors SEGMENTS[0].
##
## Design notes
##   * 1 world unit = 40 px, the ground is exactly at y = 0 and every prop sits
##     on it; the path is a visual-only ribbon 2 cm above the ground.
##   * Deterministic: the RNG is seeded from config["id"], so a segment always
##     looks the same. There is no per-frame script work at all; wind is in
##     res://shaders/world/grass.gdshader.
##   * The prop loading / per-surface tinting / metallic-fix logic is copied
##     from the verified scenes/world/world.gd — do not "simplify" it.
##
## Tuning: every constant in the block below is meant to be edited.

# =============================================================================
# CONFIG DEFAULTS (identical to SegmentPresets.SEGMENTS[0])
# =============================================================================

# Plain member (not a const Dictionary) so `duplicate()` can never hand back a
# read-only container: setup() merges the caller's config over this copy.
var DEFAULT_CONFIG := {
	"id": "s1_morning",
	"title": "一 · 晨光",
	"scenery_only": true,
	"npc_id": "",
	"area_size": 120.0,
	"sky_top": Color(0.30, 0.55, 0.86),
	"sky_horizon": Color(0.96, 0.86, 0.72),
	"sky_ground_bottom": Color(0.14, 0.18, 0.12),
	"sky_ground_horizon": Color(0.55, 0.62, 0.48),
	"sun_color": Color(1.0, 0.82, 0.62),
	"sun_energy": 1.25,
	"sun_rotation_deg": Vector3(-16.0, 72.0, 0.0),
	"ambient_color": Color(0.72, 0.82, 0.95),
	"ambient_energy": 0.42,
	"fill_energy": 0.10,
	"fog_color": Color(0.86, 0.86, 0.78),
	"fog_density": 0.0055,
	"fog_sun_scatter": 0.40,
	"tonemap_exposure": 0.95,
	"saturation": 1.12,
	"contrast": 1.05,
	"glow_intensity": 0.12,
	"glow_threshold": 1.3,
	"ground_tint": Color(0.80, 0.88, 0.76),
	"ground_uv_tiles": 9.0,
	"hill_height": 1.0,
	"pond_count": 1,
	"water_tint": Color(0.22, 0.40, 0.38, 0.82),
	"grass_grid": 0.45,
	"grass_width": 0.30,
	"grass_height": 0.42,
	"grass_base": Color(0.10, 0.22, 0.07),
	"grass_tip": Color(0.50, 0.74, 0.28),
	"grass_dry": Color(0.60, 0.55, 0.26),
	"grass_dry_mix": 0.08,
	"wind_strength": 0.06,
	"wind_speed": 1.4,
	"path_points": [Vector2(0, 40), Vector2(2, 24), Vector2(-3, 6), Vector2(1, -12), Vector2(0, -40)],
	"path_width": 2.4,
	"prop_tree_models": ["tree_default.glb", "tree_oak.glb", "tree_detailed.glb", "tree_fat.glb"],
	"prop_tree_count": 26,
	"prop_rock_count": 8,
	"prop_bush_count": 10,
	"prop_flower_count": 50,
	"prop_tint": Color(1.0, 1.06, 0.80),
	"tree_scale": 0.95,
	"player_start": Vector2(0, 40),
	"npc_position": Vector2(0, 0),
	"exit_position": Vector2(0, -40),
}

# =============================================================================
# OPTIONAL ART / MODELS
# =============================================================================

const GROUND_TEXTURE_PATH := "res://assets/generated/grass_ground.png"
const GROUND_SHADER_PATH := "res://shaders/segment/ground.gdshader"
const PATH_TEXTURE_PATH := "res://assets/generated/path_dirt.png"
const BLADE_TEXTURE_PATH := "res://assets/generated/grass_blade.png"
const TUFT_TEXTURE_PATH := "res://assets/generated/grass_tuft.png"
const FLOWER_WHITE_PATH := "res://assets/generated/flower_white.png"
const FLOWER_YELLOW_PATH := "res://assets/generated/flower_yellow.png"
const GRASS_SHADER_PATH := "res://shaders/world/grass.gdshader"

const KIT_DIR := "res://assets/free/kenney_nature_kit/models/"
const ROCK_MODELS := ["rock_smallA.glb", "rock_smallB.glb", "rock_smallC.glb", "rock_largeA.glb", "rock_largeB.glb"]
const BUSH_MODELS := ["plant_bush.glb", "plant_bushSmall.glb", "plant_bushDetailed.glb", "plant_bushLarge.glb", "plant_bushTriangle.glb"]

# Small dressing props (all already in the CC0 kit). Every group is optional:
# the count comes from the segment config ("detail_<group>_count").
const DETAIL_GROUPS := {
	"fern": {
		"models": ["plant_flatTall.glb", "plant_flatShort.glb", "plant_bushDetailed.glb",
			"plant_bushLargeTriangle.glb"],
		"spacing": 1.0, "corridor": 0.90, "mode": "height",
		"size_min": 0.45, "size_max": 1.05, "shadow": false,
	},
	"mushroom": {
		"models": ["mushroom_redGroup.glb", "mushroom_tanGroup.glb", "mushroom_red.glb",
			"mushroom_tan.glb", "mushroom_redTall.glb", "mushroom_tanTall.glb"],
		"spacing": 0.9, "corridor": 0.85, "mode": "height",
		"size_min": 0.22, "size_max": 0.55, "shadow": false,
	},
	"log": {
		"models": ["log.glb", "log_large.glb", "log_stack.glb", "log_stackLarge.glb"],
		"spacing": 2.4, "corridor": 0.85, "mode": "size",
		"size_min": 1.4, "size_max": 2.4, "shadow": true, "collide": true,
	},
	"flower3d": {
		"models": ["flower_purpleA.glb", "flower_redA.glb", "flower_yellowA.glb",
			"flower_purpleB.glb", "flower_redB.glb", "flower_yellowB.glb"],
		"spacing": 1.2, "corridor": 0.92, "mode": "height",
		"size_min": 0.30, "size_max": 0.75, "shadow": false,
	},
	"stone": {
		"models": ["rock_smallFlatA.glb", "rock_smallFlatB.glb", "rock_smallFlatC.glb"],
		"spacing": 1.6, "corridor": 0.95, "mode": "size",
		"size_min": 0.50, "size_max": 1.00, "shadow": false, "collide": true,
	},
	"fence": {
		"models": ["fence_simple.glb", "fence_planks.glb", "fence_simpleHigh.glb",
			"fence_planksDouble.glb"],
		"spacing": 3.2, "corridor": 0.88, "mode": "size",
		"size_min": 1.6, "size_max": 2.4, "shadow": true, "collide": true,
	},
}

# Ambient particles (pollen in daylight, fireflies at dusk/night).
const PARTICLE_TEXTURES := {
	"pollen": "res://assets/generated/particle_pollen.png",
	"fireflies": "res://assets/generated/particle_firefly.png",
	"dust": "res://assets/generated/particle_dust.png",
}

# =============================================================================
# TUNING CONSTANTS
# =============================================================================

# --- ground ---------------------------------------------------------------
const GROUND_UV_TILE_SIZE := 12.8 # texture metres per tile; used when the config has no ground_uv_tiles
const BACKDROP_FACTOR := 2.4 # visual-only skirt so the horizon does not end at the wall
const BACKDROP_DROP := 1.4
const WALL_THICKNESS := 2.0
const WALL_HEIGHT := 26.0
const WORLD_LAYER := 1
const PLAYER_LAYER := 2

# Rolling terrain: a deterministic height field over the whole segment.
const TERRAIN_RES := 257 # vertices per side (2^n + 1), ~0.4 m spacing on a 100 m map
const TERRAIN_FLATTEN_RADIUS := 5.0 # spawn / NPC / exit pads are levelled
const PAD_FLATTEN_CORE := 2.2
const PAD_FLATTEN_BLEND := 5.0
const NPC_FLATTEN_CORE := 4.4
const NPC_FLATTEN_BLEND := 7.5
const PATH_SMOOTH_CORE := 0.80
const PATH_SMOOTH_BLEND := 6.2
const WATER_SHADER_PATH := "res://shaders/segment/water.gdshader"
const POND_RIM_SCALE := 1.05
const POND_BLEND_SCALE := 0.62

# --- dirt path ------------------------------------------------------------
const PATH_STEP := 0.5 # Catmull-Rom sampling step (metres)

# --- grass field ----------------------------------------------------------
const MAX_BLADES := 700000
const GRASS_JITTER := 0.55 # fraction of grass_grid
const GRASS_WIDTH_SCALE_MIN := 0.45
const GRASS_WIDTH_SCALE_MAX := 1.05
const GRASS_HEIGHT_SCALE_MIN := 0.62
const GRASS_HEIGHT_SCALE_MAX := 1.35
const DENSITY_BASE := 0.78
const DENSITY_AMPLITUDE := 0.22
const DENSITY_FREQ_X := 0.13
const DENSITY_FREQ_Z := 0.11
const DENSITY_PHASE_X := 0.8
const DENSITY_PHASE_Z := -0.4
const CLEAR_PLAYER := 2.5
const CLEAR_NPC := 2.5
const PATH_CLEAR_MARGIN := 0.15
const WIND_DIRECTION := Vector2(0.86, 0.50)

# --- path proximity mask (fast reject for distance-to-path queries) -------
const MASK_CELL := 1.0
const PATH_MASK_RADIUS := 4.6 # coarse mask superset; exact distance is only run inside it

# --- prop scatter ---------------------------------------------------------
const SEED_BASE := 20261108
const PROP_EDGE_MARGIN := 2.0
const PATH_PROP_CLEAR := 1.0 # props keep path_width + this away from the path
const PROP_AVOID_PLAYER := 4.0
const PROP_AVOID_NPC := 3.0
const PROP_AVOID_EXIT := 3.5
const TREE_SPACING := 2.6
const ROCK_SPACING := 1.8
const BUSH_SPACING := 1.5
const TREE_HEIGHT_MIN := 2.8
const TREE_HEIGHT_MAX := 5.4
const TREE_CORRIDOR_RATIO := 0.85
const ROCK_CORRIDOR_RATIO := 0.55
const BUSH_CORRIDOR_RATIO := 0.80
const CORRIDOR_INNER := 4.0 # metres away from the path centre line
const CORRIDOR_OUTER := 18.0
const EDGE_INSET := 4.5 # first edge forest row sits this far inside the walls
const EDGE_ROWS := 3
const EDGE_ROW_STEP := 3.6
const EDGE_FRAME_SPACING := 2.8
const FLOWER_HEIGHT := 0.12
const FLOWER_SIZE := Vector2(0.17, 0.17)
const FLOWER_PATH_MIN := 0.35 # extra clearance beyond path_width * 0.5
const FLOWER_PATH_MAX := 6.0
const SPOT_NONE := Vector2(1.0e6, 1.0e6)

# --- lighting / atmosphere (ported from the verified world.gd) ------------
const SKY_CURVE := 0.14
const SKY_ENERGY := 1.10
const SKY_GROUND_CURVE := 0.06
const SKY_SUN_ANGLE_MAX := 24.0
const SKY_SUN_CURVE := 0.12
const SUN_SHADOW_DISTANCE := 80.0
const FILL_ROTATION_DEG := Vector3(-26.0, 148.0, 0.0)
const FILL_COLOR := Color(0.70, 0.80, 0.95, 1.0)
const FOG_AERIAL_PERSPECTIVE := 0.30
const DOF_FAR_DISTANCE := 24.0
const DOF_FAR_TRANSITION := 18.0
const DOF_AMOUNT := 0.08

# --- exit landmark --------------------------------------------------------
const EXIT_RADIUS := 2.5
const EXIT_RING_RADIUS := 2.0
const EXIT_RING_STONES := 8
const EXIT_GLOW_COLOR := Color(1.0, 0.86, 0.55, 1.0)
const EXIT_GLOW_ENERGY := 2.2
const STONE_COLOR := Color(0.54, 0.52, 0.47, 1.0)
const STONE_COLOR_COOL := Color(0.46, 0.47, 0.50, 1.0)

# =============================================================================
# PUBLIC API
# =============================================================================

## Emitted once, the first time a body in group "player" enters the exit area.
signal exit_reached

# =============================================================================
# STATE
# =============================================================================

var config: Dictionary = {}

var _built := false
var _rng := RandomNumberGenerator.new()

var _area_size := 120.0
var _half_size := 60.0
var _path_width := 2.4
var _prop_tint := Color(1.0, 1.06, 0.80, 1.0)

var _player_start := Vector3.ZERO
var _npc_position := Vector3.ZERO
var _exit_position := Vector3.ZERO
var _player_start_xz := Vector2.ZERO
var _npc_xz := Vector2.ZERO
var _exit_xz := Vector2.ZERO

var _path_samples := PackedVector2Array()
var _path_mask := PackedByteArray()
var _mask_dim := 0

var _ponds: Array[Dictionary] = []
var _creek_level: float = NAN
var _puzzle_enabled: bool = false
var _puzzle_center := Vector2.ZERO
var _puzzle_progress: int = 0
var _puzzle_solved: bool = false
var _puzzle_pillars: Array[Dictionary] = []
var _puzzle_tablet_pos := Vector3.ZERO
var _puzzle_light: OmniLight3D
var _puzzle_core: MeshInstance3D
var _puzzle_symbol_nodes: Array[Node3D] = []
var _puzzle_symbol_material: Material
var _puzzle_lit_material: Material
var _grass_shader_material: ShaderMaterial
var _grass_materials: Array[ShaderMaterial] = []
var _grass_player: Node3D
var _backdrop_y: float = -1.4
var _terrain_res := TERRAIN_RES
var _terrain_step := 1.0
var _terrain_origin := -60.0
var _terrain_heights := PackedFloat32Array()

var _occupied: Array[Vector2] = []
var _exit_used := false

# Counts for the build summary print.
var _tree_count := 0
var _rock_count := 0
var _bush_count := 0
var _flower_count := 0

# =============================================================================
# ENTRY POINT
# =============================================================================

## Builds the whole segment. Must be called once, after add_child().
func setup(cfg: Dictionary) -> void:
	if _built:
		push_warning("[segment] setup() called twice — ignoring the second call")
		return
	_built = true

	config = DEFAULT_CONFIG.duplicate(true)
	for key in cfg.keys():
		config[key] = cfg[key]

	# Same id -> same world. String.hash() is deterministic across runs.
	var segment_id := _s("id")
	_rng.seed = SEED_BASE if segment_id.is_empty() else int(segment_id.hash())

	_area_size = _f("area_size")
	_half_size = _area_size * 0.5
	_path_width = _f("path_width")
	_prop_tint = _c("prop_tint")

	_player_start = _to_world(_v2("player_start"))
	_npc_position = _to_world(_v2("npc_position"))
	_exit_position = _to_world(_v2("exit_position"))
	_player_start_xz = _v2("player_start")
	_npc_xz = _v2("npc_position")
	_exit_xz = _v2("exit_position")

	_path_samples = _sample_path(_points("path_points"))
	_build_path_near_mask()
	_init_creek_level()
	_plan_ponds()

	_build_environment()
	_build_terrain()
	_build_spawn_air_wall()

	var blades := _build_grass()
	_build_props()
	_build_particles()
	_build_exit()

	print("[segment] %s built — grass=%d trees=%d rocks=%d bushes=%d flowers=%d children=%d" % [
		_s("id"), blades, _tree_count, _rock_count, _bush_count, _flower_count, get_child_count()])

# --- public getters -------------------------------------------------------

## World position (y = terrain height) where the game manager places the player.
func get_player_start() -> Vector3:
	return Vector3(_player_start.x, _terrain_height_at(_player_start.x, _player_start.z), _player_start.z)

## World position (y = terrain height) for the segment NPC (config npc_position).
func get_npc_position() -> Vector3:
	return Vector3(_npc_position.x, _terrain_height_at(_npc_position.x, _npc_position.z), _npc_position.z)

# =============================================================================
# CONFIG ACCESSORS (typed, always fall back to DEFAULT_CONFIG)
# =============================================================================

func _f(key: String) -> float:
	var value = config.get(key)
	if value is float or value is int:
		return float(value)
	return float(DEFAULT_CONFIG.get(key, 0.0))

func _i(key: String) -> int:
	var value = config.get(key)
	if value is int or value is float:
		return int(value)
	return int(DEFAULT_CONFIG.get(key, 0))

func _s(key: String) -> String:
	var value = config.get(key)
	if value is String:
		var text: String = value
		return text
	var fallback: String = DEFAULT_CONFIG.get(key, "")
	return fallback

func _c(key: String) -> Color:
	var value = config.get(key)
	if value is Color:
		var color: Color = value
		return color
	var fallback: Color = DEFAULT_CONFIG.get(key, Color.WHITE)
	return fallback

func _v2(key: String) -> Vector2:
	var value = config.get(key)
	if value is Vector2:
		var point: Vector2 = value
		return point
	var fallback: Vector2 = DEFAULT_CONFIG.get(key, Vector2.ZERO)
	return fallback

func _v3(key: String) -> Vector3:
	var value = config.get(key)
	if value is Vector3:
		var point: Vector3 = value
		return point
	var fallback: Vector3 = DEFAULT_CONFIG.get(key, Vector3.ZERO)
	return fallback

func _names(key: String) -> PackedStringArray:
	var out := PackedStringArray()
	var value = config.get(key)
	if value is PackedStringArray:
		var packed: PackedStringArray = value
		return packed
	if value is Array:
		var list: Array = value
		for item in list:
			if item is String:
				var file_name: String = item
				out.append(file_name)
	return out

func _points(key: String) -> PackedVector2Array:
	var out := PackedVector2Array()
	var value = config.get(key)
	if value is PackedVector2Array:
		var packed: PackedVector2Array = value
		return packed
	if value is Array:
		var list: Array = value
		for item in list:
			if item is Vector2:
				var point: Vector2 = item
				out.append(point)
	return out

func _has_npc() -> bool:
	return not _s("npc_id").is_empty()

func _to_world(point: Vector2) -> Vector3:
	return Vector3(point.x, 0.0, point.y)

# =============================================================================
# SKY / LIGHTING / ATMOSPHERE
# =============================================================================

func _build_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = _c("sky_top")
	sky_material.sky_horizon_color = _c("sky_horizon")
	sky_material.sky_curve = SKY_CURVE
	sky_material.sky_energy_multiplier = SKY_ENERGY
	sky_material.ground_bottom_color = _c("sky_ground_bottom")
	sky_material.ground_horizon_color = _c("sky_ground_horizon")
	sky_material.ground_curve = SKY_GROUND_CURVE
	sky_material.sun_angle_max = SKY_SUN_ANGLE_MAX
	sky_material.sun_curve = SKY_SUN_CURVE

	var sky := Sky.new()
	sky.sky_material = sky_material

	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = _c("ambient_color")
	environment.ambient_light_energy = _f("ambient_energy")
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = _f("tonemap_exposure")
	environment.glow_enabled = true
	environment.glow_intensity = _f("glow_intensity")
	environment.glow_hdr_threshold = _f("glow_threshold")
	environment.fog_enabled = true
	environment.fog_light_color = _c("fog_color")
	environment.fog_density = _f("fog_density")
	environment.fog_sun_scatter = _f("fog_sun_scatter")
	environment.fog_aerial_perspective = FOG_AERIAL_PERSPECTIVE
	environment.adjustment_enabled = true
	environment.adjustment_saturation = _f("saturation")
	environment.adjustment_contrast = _f("contrast")

	# HD2D signature: the 3D backdrop falls out of focus while the pixel hero
	# stays sharp. In Godot 4 depth of field lives on CameraAttributesPractical.
	var attributes := CameraAttributesPractical.new()
	attributes.dof_blur_far_enabled = true
	attributes.dof_blur_far_distance = DOF_FAR_DISTANCE
	attributes.dof_blur_far_transition = DOF_FAR_TRANSITION
	attributes.dof_blur_amount = DOF_AMOUNT

	var world_environment := WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	world_environment.environment = environment
	world_environment.camera_attributes = attributes
	add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = _v3("sun_rotation_deg")
	sun.light_color = _c("sun_color")
	sun.light_energy = _f("sun_energy")
	sun.shadow_enabled = true
	sun.directional_shadow_mode = 2 # DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = SUN_SHADOW_DISTANCE
	sun.shadow_blur = 1.0
	add_child(sun)

	var fill_energy := _f("fill_energy")
	if fill_energy > 0.001:
		# Cool sky-bounce fill so shadow sides keep some colour, no shadows.
		var fill := DirectionalLight3D.new()
		fill.name = "FillLight"
		fill.rotation_degrees = FILL_ROTATION_DEG
		fill.light_color = FILL_COLOR
		fill.light_energy = fill_energy
		fill.shadow_enabled = false
		add_child(fill)

# =============================================================================
# GROUND
# =============================================================================

func _build_terrain() -> void:
	var uv_tiles := _area_size / GROUND_UV_TILE_SIZE
	var configured_tiles := _f("ground_uv_tiles")
	if configured_tiles > 0.0:
		uv_tiles = configured_tiles

	var ground_texture := _load_texture(GROUND_TEXTURE_PATH)
	var dirt_texture := _load_texture(PATH_TEXTURE_PATH)
	var ground_shader := _load_shader(GROUND_SHADER_PATH)
	var ground_material: Material = null
	if ground_shader != null and ground_texture != null:
		# The trail is baked into the terrain itself, so it can never occlude or
		# tint the hero's sprite (the old overlay ribbon did both at the feet).
		var shader_material := ShaderMaterial.new()
		shader_material.shader = ground_shader
		shader_material.set_shader_parameter("ground_tex", ground_texture)
		shader_material.set_shader_parameter("dirt_tex", dirt_texture if dirt_texture != null else ground_texture)
		shader_material.set_shader_parameter("path_mask", _build_path_mask_texture())
		shader_material.set_shader_parameter("ground_tint", _c("ground_tint"))
		shader_material.set_shader_parameter("dirt_tint", Color(0.90, 0.86, 0.78))
		shader_material.set_shader_parameter("uv_tiles", uv_tiles)
		ground_material = shader_material
	else:
		var fallback := StandardMaterial3D.new()
		fallback.roughness = 1.0
		fallback.metallic = 0.0
		fallback.cull_mode = BaseMaterial3D.CULL_DISABLED
		fallback.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		fallback.uv1_scale = Vector3(uv_tiles, uv_tiles, 1.0)
		fallback.albedo_color = _c("ground_tint")
		if ground_texture != null:
			fallback.albedo_texture = ground_texture
		else:
			push_warning("[segment] grass_ground.png missing - flat ground colour")
		ground_material = fallback

	# --- sample the height field -------------------------------------------
	_terrain_res = TERRAIN_RES
	_terrain_step = _area_size / float(_terrain_res - 1)
	_terrain_origin = -_half_size
	_terrain_heights.resize(0)
	_terrain_heights.resize(_terrain_res * _terrain_res)
	for iz in _terrain_res:
		var z := _terrain_origin + float(iz) * _terrain_step
		for ix in _terrain_res:
			var x := _terrain_origin + float(ix) * _terrain_step
			_terrain_heights[iz * _terrain_res + ix] = _terrain_height_at(x, z)

	# --- build the mesh ----------------------------------------------------
	var count := _terrain_res * _terrain_res
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	verts.resize(count)
	normals.resize(count)
	uvs.resize(count)
	var step := _terrain_step
	var row := _terrain_res
	for iz in _terrain_res:
		var z := _terrain_origin + float(iz) * step
		for ix in _terrain_res:
			var idx := iz * row + ix
			var x := _terrain_origin + float(ix) * step
			verts[idx] = Vector3(x, _terrain_heights[idx], z)
			uvs[idx] = Vector2((x + _half_size) / _area_size, (z + _half_size) / _area_size)
			var hl := _terrain_heights[iz * row + maxi(ix - 1, 0)]
			var hr := _terrain_heights[iz * row + mini(ix + 1, row - 1)]
			var hd := _terrain_heights[maxi(iz - 1, 0) * row + ix]
			var hu := _terrain_heights[mini(iz + 1, row - 1) * row + ix]
			normals[idx] = Vector3(hl - hr, 2.0 * step, hd - hu).normalized()

	var indices := PackedInt32Array()
	indices.resize((row - 1) * (row - 1) * 6)
	var cursor := 0
	for iz in row - 1:
		for ix in row - 1:
			var i00 := iz * row + ix
			var i10 := i00 + 1
			var i01 := i00 + row
			var i11 := i01 + 1
			indices[cursor] = i00
			indices[cursor + 1] = i11
			indices[cursor + 2] = i01
			cursor += 3
			indices[cursor] = i00
			indices[cursor + 1] = i10
			indices[cursor + 2] = i11
			cursor += 3

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, ground_material)

	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = mesh
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)

	# Visual-only skirt below the playable terrain (no collision). It must stay
	# below the *lowest* terrain point, otherwise it would cover low pads/paths
	# with a flat grass plane when the story elevation rises.
	var min_height := INF
	for h in _terrain_heights:
		min_height = minf(min_height, h)
	if min_height == INF:
		min_height = _macro_height(0.0, 0.0)
	_backdrop_y = min_height - 0.8
	var backdrop_size := _area_size * BACKDROP_FACTOR
	var ratio := backdrop_size / _area_size
	var backdrop_material := StandardMaterial3D.new()
	backdrop_material.roughness = 1.0
	backdrop_material.metallic = 0.0
	backdrop_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	backdrop_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	backdrop_material.albedo_color = _c("ground_tint")
	if ground_texture != null:
		backdrop_material.albedo_texture = ground_texture
	backdrop_material.uv1_scale = Vector3(uv_tiles * ratio, uv_tiles * ratio, 1.0)
	var backdrop_plane := PlaneMesh.new()
	backdrop_plane.size = Vector2(backdrop_size, backdrop_size)
	backdrop_plane.material = backdrop_material
	var backdrop := MeshInstance3D.new()
	backdrop.name = "GroundBackdrop"
	backdrop.mesh = backdrop_plane
	backdrop.position = Vector3(0.0, _backdrop_y, 0.0)
	backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(backdrop)
	_build_outer_terrain_ring()

	# Terrain collision: the same triangles the player sees.
	var ground_body := StaticBody3D.new()
	ground_body.name = "GroundBody"
	ground_body.collision_layer = WORLD_LAYER
	ground_body.collision_mask = 0
	var ground_shape := CollisionShape3D.new()
	var trimesh := mesh.create_trimesh_shape() as ConcavePolygonShape3D
	if trimesh != null:
		# Physics treats one side of a concave triangle as solid; make both sides
		# solid so the winding order can never drop the hero through the ground.
		trimesh.backface_collision = true
	ground_shape.shape = trimesh
	ground_body.add_child(ground_shape)
	add_child(ground_body)

	_build_water()
	_build_creek()
	_build_perimeter_walls()

## Rasterises the path polyline into a coverage mask over the whole segment.
## The ground shader blends grass/dirt through it, with a per-pixel dither that
## keeps the rim irregular without using transparency.
## A visual-only strip of ground outside each wall at the normal edge height.
## The outer curtain trees stand on this instead of hovering over the low
## backdrop; it also hides the seam between the map edge and the horizon plane.
func _build_outer_terrain_ring() -> void:
	var material := StandardMaterial3D.new()
	material.roughness = 1.0
	material.metallic = 0.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.albedo_color = _c("ground_tint")
	var texture := _load_texture(GROUND_TEXTURE_PATH)
	if texture != null:
		material.albedo_texture = texture
	material.uv1_scale = Vector3(9.0, 9.0, 1.0)
	var depth := 34.0
	var segments := 64
	for side in 4:
		var verts := PackedVector3Array()
		var normals := PackedVector3Array()
		var uvs := PackedVector2Array()
		var indices := PackedInt32Array()
		for i in segments + 1:
			var t := float(i) / float(segments)
			var along := lerpf(-(_half_size + depth), _half_size + depth, t)
			var edge_pos := Vector2.ZERO
			var outside_pos := Vector2.ZERO
			var edge_height := 0.0
			if side == 0 or side == 1:
				var z_edge := -_half_size if side == 0 else _half_size
				var z_out := -_half_size - depth if side == 0 else _half_size + depth
				var sample_x := clampf(along, -_half_size + 1.5, _half_size - 1.5)
				edge_height = _terrain_height_at(sample_x, z_edge)
				edge_pos = Vector2(along, z_edge)
				outside_pos = Vector2(along, z_out)
			else:
				var x_edge := -_half_size if side == 2 else _half_size
				var x_out := -_half_size - depth if side == 2 else _half_size + depth
				var sample_z := clampf(along, -_half_size + 1.5, _half_size - 1.5)
				edge_height = _terrain_height_at(x_edge, sample_z)
				edge_pos = Vector2(x_edge, along)
				outside_pos = Vector2(x_out, along)
			verts.append(Vector3(edge_pos.x, edge_height, edge_pos.y))
			verts.append(Vector3(outside_pos.x, edge_height, outside_pos.y))
			normals.append(Vector3.UP)
			normals.append(Vector3.UP)
			uvs.append(Vector2(t * 8.0, 0.0))
			uvs.append(Vector2(t * 8.0, depth / 12.8))
		for i in segments:
			var a := i * 2
			indices.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, material)
		var strip := MeshInstance3D.new()
		strip.name = "OuterRing_%d" % side
		strip.mesh = mesh
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(strip)

func _build_path_mask_texture() -> ImageTexture:
	var res := 512
	var img := Image.create(res, res, false, Image.FORMAT_L8)
	img.fill(Color(0, 0, 0, 1))
	if _path_samples.is_empty():
		return ImageTexture.create_from_image(img)
	var px_per_m := float(res) / _area_size
	var core_radius := 1.10
	var outer_radius := 1.86
	for i in _path_samples.size():
		var point := _path_samples[i]
		var wobble := 0.16 * sin(float(i) * 1.7) + 0.10 * sin(float(i) * 0.47)
		# Break the regular scalloped edge with low-frequency noise, so path
		# edges never repeat the same silhouette segment after segment.
		wobble += (_value_noise(point.x * 0.31 + 3.7, point.y * 0.27 - 1.9) - 0.5) * 0.46
		var core := core_radius + wobble
		var outer := outer_radius + wobble
		var x0 := maxi(0, int((point.x - outer + _half_size) * px_per_m))
		var x1 := mini(res - 1, int((point.x + outer + _half_size) * px_per_m))
		var y0 := maxi(0, int((point.y - outer + _half_size) * px_per_m))
		var y1 := mini(res - 1, int((point.y + outer + _half_size) * px_per_m))
		for py in range(y0, y1 + 1):
			var world_z := (float(py) + 0.5) / px_per_m - _half_size
			for px in range(x0, x1 + 1):
				var world_x := (float(px) + 0.5) / px_per_m - _half_size
				var distance := Vector2(world_x - point.x, world_z - point.y).length()
				if distance >= outer:
					continue
				var coverage := 1.0 - smoothstep(core, outer, distance)
				if coverage <= img.get_pixel(px, py).r:
					continue
				img.set_pixel(px, py, Color(coverage, coverage, coverage, 1.0))
	return ImageTexture.create_from_image(img)

## Invisible wall just south of the spawn pad: the path visually continues off
## screen, but the player cannot walk backwards out of the segment.
func _build_spawn_air_wall() -> void:
	var body := StaticBody3D.new()
	body.name = "SpawnAirWall"
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	body.position = Vector3(0.0, 13.0, _player_start_xz.y + 1.4)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(_area_size + 6.0, 26.0, 0.6)
	shape.shape = box
	body.add_child(shape)
	add_child(body)

## Invisible cylinder filling the pond volume: the hero can reach the bank but
## cannot walk into the water.
func _add_pond_wall(pond: Dictionary, pond_index: int) -> void:
	var center: Vector2 = pond["pos"]
	var radius: float = pond["radius"]
	var body := StaticBody3D.new()
	body.name = "PondAirWall_%d" % pond_index
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	var pond_base: float = float(pond["center_height"]) - 0.4
	body.position = Vector3(center.x, pond_base, center.y)
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius * 0.93
	cylinder.height = 4.5
	shape.shape = cylinder
	shape.position = Vector3(0.0, 2.25, 0.0)
	body.add_child(shape)
	add_child(body)

func _value_hash(ix: int, iz: int) -> float:
	var n := float(ix * 374761393 + iz * 668265263)
	return fposmod(sin(n * 0.000011) * 43758.5453, 1.0)

func _value_noise(x: float, z: float) -> float:
	var ix := floori(x)
	var iz := floori(z)
	var fx := x - float(ix)
	var fz := z - float(iz)
	fx = fx * fx * (3.0 - 2.0 * fx)
	fz = fz * fz * (3.0 - 2.0 * fz)
	var a := _value_hash(ix, iz)
	var b := _value_hash(ix + 1, iz)
	var c := _value_hash(ix, iz + 1)
	var d := _value_hash(ix + 1, iz + 1)
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fz)

## Gentle, deterministic rolling hills (metres).
func _base_hill_height(x: float, z: float) -> float:
	var amplitude := _f("hill_height")
	var h := sin(x * 0.052 + 1.7) * cos(z * 0.047 - 0.9) * 1.00
	h += sin(x * 0.112 - 0.6) * sin(z * 0.097 + 2.3) * 0.50
	h += sin((x + z) * 0.021 + 0.4) * 0.70
	# Small, readable mounds (10-25 m wavelength) so the relief is visible
	# inside the 16 m camera view as well.
	h += sin(x * 0.26 + 0.9) * cos(z * 0.22 - 1.4) * 0.44
	h += sin(x * 0.41 - 0.3) * sin(z * 0.37 + 1.2) * 0.22
	# Closer, steeper knolls so relief reads inside the camera view.
	h += sin(x * 0.57 + 2.1) * cos(z * 0.49 - 1.6) * 0.55
	h += sin(x * 0.93 - 0.4) * sin(z * 0.81 + 2.2) * 0.30
	# Break the regular sine rhythm with two octaves of deterministic value
	# noise, so the same rolling slope does not repeat from segment to segment.
	h += (_value_noise(x * 0.031 + 17.3, z * 0.027 - 8.1) - 0.5) * 1.55
	h += (_value_noise(x * 0.083 - 4.7, z * 0.071 + 11.9) - 0.5) * 0.55
	# Raise the land away from the path: the walk sits in a shallow valley with
	# visible hillsides instead of a flat table.
	h += smoothstep(9.0, 30.0, absf(x)) * _f("terrain_side_lift")
	h += x * _f("terrain_cross_slope")
	return h * amplitude

## Story-level elevation: each segment climbs / descends along the walk, with
## an optional mid-route ridge (positive arc) or valley (negative arc).
func _macro_height(x: float, z: float) -> float:
	var start := _f("elevation_start")
	var finish := _f("elevation_end")
	var arc := _f("elevation_arc")
	var t := clampf((_half_size - z) / maxf(_area_size, 0.001), 0.0, 1.0)
	var ridge_height := _f("ridge_height")
	var ridge_pos := clampf(_f("ridge_pos"), 0.05, 0.95)
	var ridge_width := maxf(_f("ridge_width"), 0.03)
	var ridge := ridge_height * exp(-pow((t - ridge_pos) / ridge_width, 2.0))
	return lerpf(start, finish, t) + arc * sin(PI * t) + ridge

func _natural_height(x: float, z: float) -> float:
	return _base_hill_height(x, z) + _macro_height(x, z)

## Final terrain height: hills, story elevation, pond bowls, and levelled pads
## for the player start / NPC / exit so gameplay anchors are always flat.
func _terrain_height_at(x: float, z: float) -> float:
	var pos := Vector2(x, z)
	var h := _natural_height(x, z)
	for pond in _ponds:
		var center: Vector2 = pond["pos"]
		var radius: float = pond["radius"]
		var d := pos.distance_to(center)
		var rim := radius * POND_RIM_SCALE
		var blend_dist := radius * POND_BLEND_SCALE
		if d < rim + blend_dist:
			var w := clampf((rim + blend_dist - d) / blend_dist, 0.0, 1.0)
			w = smoothstep(0.0, 1.0, w)
			h = lerpf(h, float(pond["center_height"]), w)
			if d < rim:
				var t := d / rim
				h -= float(pond["depth"]) * (1.0 - t * t)
	# The path corridor is flattened toward the nearest path sample's natural
	# height: the trail reads as a gently graded walk instead of following every
	# small knoll.
	if _maybe_near_path(pos):
		var path_info := _nearest_path_info(pos)
		if float(path_info["distance"]) < PATH_SMOOTH_BLEND:
			var target_point: Vector2 = path_info["point"]
			var d := float(path_info["distance"])
			# The path is graded, but not ironed flat: the core/blend widths and
			# the strength drift along the path so the banks are irregular and
			# keep a little of the meadow's natural undulation.
			var bank_noise := sin(target_point.x * 0.61 + target_point.y * 0.43) * 0.5 \
				+ sin(target_point.x * 0.23 - target_point.y * 0.37 + 1.7) * 0.5
			var core := PATH_SMOOTH_CORE * (0.82 + 0.38 * (bank_noise * 0.5 + 0.5))
			var blend := PATH_SMOOTH_BLEND * (0.82 + 0.34 * (bank_noise * 0.5 + 0.5))
			var pw := 1.0
			if d > core:
				pw = 1.0 - smoothstep(core, blend, d)
			h = lerpf(h, _natural_height(target_point.x, target_point.y), pw * 0.80)

	var pads: Array[Dictionary] = [
		{"pos": _player_start_xz, "core": PAD_FLATTEN_CORE, "blend": PAD_FLATTEN_BLEND},
		{"pos": _exit_xz, "core": PAD_FLATTEN_CORE, "blend": PAD_FLATTEN_BLEND},
	]
	if _has_npc():
		pads.append({"pos": _npc_xz, "core": NPC_FLATTEN_CORE, "blend": NPC_FLATTEN_BLEND})
	for pad in pads:
		var pad_pos: Vector2 = pad["pos"]
		var d := pos.distance_to(pad_pos)
		var core: float = pad["core"]
		var blend: float = pad["blend"]
		if d < blend:
			var w := 1.0
			if d > core:
				w = 1.0 - smoothstep(core, blend, d)
			h = lerpf(h, _natural_height(pad_pos.x, pad_pos.y), w)
	if _creek_enabled():
		h = _creek_carve(pos, h)
	return h

## Picks a few pond spots beside the path, away from the player / NPC / exit.
func _plan_ponds() -> void:
	_ponds.clear()
	var pond_count := _i("pond_count")
	if pond_count <= 0 or _path_samples.size() < 8:
		return
	var attempts := 0
	while _ponds.size() < pond_count and attempts < 240:
		attempts += 1
		var index := _rng.randi_range(int(_path_samples.size() * 0.18), int(_path_samples.size() * 0.82))
		var anchor := _path_samples[index]
		var tangent := _path_samples[mini(index + 4, _path_samples.size() - 1)] - _path_samples[maxi(index - 4, 0)]
		if tangent.length_squared() < 1e-6:
			tangent = Vector2(0.0, -1.0)
		tangent = tangent.normalized()
		var side := Vector2(-tangent.y, tangent.x) * (1.0 if _rng.randf() < 0.5 else -1.0)
		var radius := _rng.randf_range(4.6, 6.4)
		var center := anchor + side * (radius + _rng.randf_range(2.5, 5.5))
		if absf(center.x) > _half_size - 9.0 or absf(center.y) > _half_size - 9.0:
			continue
		if _path_distance(center) < radius + 4.5:
			continue
		if center.distance_to(_player_start_xz) < radius + 6.0:
			continue
		if center.distance_to(_exit_xz) < radius + 6.0:
			continue
		if _has_npc() and center.distance_to(_npc_xz) < radius + 5.5:
			continue
		var overlaps := false
		for other in _ponds:
			if center.distance_to(other["pos"]) < radius + float(other["radius"]) + 7.0:
				overlaps = true
		if overlaps:
			continue
		var depth := _rng.randf_range(0.55, 0.8)
		_ponds.append({
			"pos": center,
			"radius": radius,
			"depth": depth,
			"center_height": _natural_height(center.x, center.y),
			"water_y": _natural_height(center.x, center.y) - 0.08,
		})

func _in_pond(pos: Vector2, margin: float = 0.0) -> bool:
	for pond in _ponds:
		if pos.distance_to(pond["pos"]) < float(pond["radius"]) * 1.02 + margin:
			return true
	return false

# --- creek (s4 "溪畔") -----------------------------------------------------

func _creek_cfg() -> Dictionary:
	var value = config.get("creek", {})
	return value if value is Dictionary else {}

func _creek_enabled() -> bool:
	return bool(_creek_cfg().get("enabled", false))

func _creek_center_z(x: float) -> float:
	var cfg := _creek_cfg()
	var curve := float(cfg.get("curve", 1.3))
	# Two harmonics make a readable S-bend instead of a shallow sine wave.
	return float(cfg.get("z", 27.0)) + sin(x * 0.060 + 0.55) * curve \
		+ sin(x * 0.135 - 0.9) * curve * 0.42

func _init_creek_level() -> void:
	if not _creek_enabled():
		return
	var half := _creek_half_width()
	# Anchor the horizontal water plane to the creek banks at the bridge on the
	# path. That keeps the bridge at a believable height while the S-bends in
	# the less visible parts are carved to the same water level.
	var level := INF
	if not _path_samples.is_empty():
		var target_z := float(_creek_cfg().get("z", 27.0))
		var best := INF
		var best_point := _path_samples[0]
		for i in _path_samples.size():
			var dist := absf(_path_samples[i].y - _creek_center_z(_path_samples[i].x))
			if dist < best:
				best = dist
				best_point = _path_samples[i]
		level = (
			_natural_height(best_point.x, best_point.y - 4.2)
			+ _natural_height(best_point.x, best_point.y + 4.2)) * 0.5
	if level == INF:
		level = _natural_height(0.0, float(_creek_cfg().get("z", 27.0)))
	_creek_level = level - 0.32

func _creek_water_y(_x: float) -> float:
	if is_nan(_creek_level):
		_init_creek_level()
	return _creek_level

func _creek_depth_at(x: float) -> float:
	var cfg := _creek_cfg()
	var base := float(cfg.get("depth", 0.62))
	return maxf(0.32, base + 0.18 * sin(x * 0.19 + 1.1) + 0.09 * sin(x * 0.47 - 0.6))

func _creek_half_width() -> float:
	return float(_creek_cfg().get("width", 3.6)) * 0.5

func _creek_water_half_width() -> float:
	return _creek_half_width() * 0.66

func _in_creek(pos: Vector2, margin: float = 0.0) -> bool:
	if not _creek_enabled():
		return false
	return absf(pos.y - _creek_center_z(pos.x)) < _creek_half_width() + margin

func _near_creek_cave(pos: Vector2) -> bool:
	if not _creek_enabled():
		return false
	if absf(pos.x) < _half_size - 13.0:
		return false
	return absf(pos.y - _creek_center_z(pos.x)) < 11.0

func _creek_carve(pos: Vector2, h: float) -> float:
	var cfg := _creek_cfg()
	var half := _creek_half_width()
	var water_half := _creek_water_half_width()
	var bank_width := 1.55
	var d := absf(pos.y - _creek_center_z(pos.x))
	if d >= water_half + bank_width:
		return h
	var water := _creek_water_y(pos.x)
	var bed := water - _creek_depth_at(pos.x)
	if d <= water_half:
		# Flat riverbed under the water surface.
		return bed
	# Bank rises from the waterline (exactly at water level) to the original
	# meadow height. The water mesh ends at this same waterline, so it can never
	# hover above the ground.
	var t := (d - water_half) / bank_width
	var bank_top := maxf(h, water + 0.35)
	return lerpf(water, bank_top, smoothstep(0.0, 1.0, t))

## Clear shallow creek. It crosses the path just in front of the spawn; a small
## timber bridge spans it on the path.
func _build_creek() -> void:
	if not _creek_enabled():
		return
	var cfg := _creek_cfg()
	var half := _creek_half_width()
	var water_mat := _creek_water_material()
	var bed_mat := StandardMaterial3D.new()
	bed_mat.albedo_texture = _load_texture("res://assets/generated/path_dirt.png")
	bed_mat.albedo_color = Color(0.72, 0.68, 0.56)
	bed_mat.roughness = 1.0
	bed_mat.uv1_scale = Vector3(2.0, 2.0, 1.0)
	var xs: Array[float] = []
	var x := -_half_size + 1.0
	while x <= _half_size - 1.0:
		xs.append(x)
		x += 0.55
	# riverbed
	var bed_verts := PackedVector3Array()
	var bed_uvs := PackedVector2Array()
	var bed_normals := PackedVector3Array()
	var bed_indices := PackedInt32Array()
	for i in xs.size():
		var wx := xs[i]
		var cz := _creek_center_z(wx)
		var wy := _creek_water_y(wx) - _creek_depth_at(wx) + 0.03
		bed_verts.append(Vector3(wx, wy, cz - _creek_water_half_width() * 0.96))
		bed_verts.append(Vector3(wx, wy, cz + _creek_water_half_width() * 0.96))
		bed_uvs.append(Vector2(0.0, float(i) * 0.6))
		bed_uvs.append(Vector2(1.0, float(i) * 0.6))
		bed_normals.append(Vector3.UP)
		bed_normals.append(Vector3.UP)
	for i in xs.size() - 1:
		var a := i * 2
		bed_indices.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])
	var bed_mesh := ArrayMesh.new()
	var bed_arrays := []
	bed_arrays.resize(Mesh.ARRAY_MAX)
	bed_arrays[Mesh.ARRAY_VERTEX] = bed_verts
	bed_arrays[Mesh.ARRAY_NORMAL] = bed_normals
	bed_arrays[Mesh.ARRAY_TEX_UV] = bed_uvs
	bed_arrays[Mesh.ARRAY_INDEX] = bed_indices
	bed_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, bed_arrays)
	var bed_instance := MeshInstance3D.new()
	bed_instance.name = "CreekBed"
	bed_instance.mesh = bed_mesh
	bed_instance.material_override = bed_mat
	bed_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bed_instance)
	# water ribbon, slightly wider than the carved channel so the edge is soft
	var water_verts := PackedVector3Array()
	var water_uvs := PackedVector2Array()
	var water_normals := PackedVector3Array()
	var water_indices := PackedInt32Array()
	for i in xs.size():
		var wx := xs[i]
		var cz := _creek_center_z(wx)
		var wy := _creek_water_y(wx)
		# Keep the water narrower than the carved channel: its edge then meets
		# the sloping bank instead of hovering above the riverbed.
		water_verts.append(Vector3(wx, wy, cz - _creek_water_half_width() * 0.98))
		water_verts.append(Vector3(wx, wy, cz + _creek_water_half_width() * 0.98))
		water_uvs.append(Vector2(0.0, float(i) * 0.8))
		water_uvs.append(Vector2(1.0, float(i) * 0.8))
		water_normals.append(Vector3.UP)
		water_normals.append(Vector3.UP)
	for i in xs.size() - 1:
		var a := i * 2
		water_indices.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])
	var water_mesh := ArrayMesh.new()
	var water_arrays := []
	water_arrays.resize(Mesh.ARRAY_MAX)
	water_arrays[Mesh.ARRAY_VERTEX] = water_verts
	water_arrays[Mesh.ARRAY_NORMAL] = water_normals
	water_arrays[Mesh.ARRAY_TEX_UV] = water_uvs
	water_arrays[Mesh.ARRAY_INDEX] = water_indices
	water_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, water_arrays)
	var water := MeshInstance3D.new()
	water.name = "CreekWater"
	water.mesh = water_mesh
	water.material_override = water_mat
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)
	# A narrow foam / wet-stone line at both water edges. It visually ties the
	# water surface to the bank instead of letting it read as a floating ribbon.
	for side in [-1.0, 1.0]:
		var foam_verts := PackedVector3Array()
		var foam_indices := PackedInt32Array()
		for i in xs.size():
			var wx := xs[i]
			var cz := _creek_center_z(wx)
			var wy := _creek_water_y(wx) + 0.012
			var edge_z: float = cz + float(side) * _creek_water_half_width() * 0.96
			foam_verts.append(Vector3(wx, wy, edge_z))
			foam_verts.append(Vector3(wx, wy - 0.035, edge_z + side * 0.16))
		for i in xs.size() - 1:
			var a := i * 2
			foam_indices.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])
		var foam_mesh := ArrayMesh.new()
		var foam_arrays := []
		foam_arrays.resize(Mesh.ARRAY_MAX)
		foam_arrays[Mesh.ARRAY_VERTEX] = foam_verts
		foam_arrays[Mesh.ARRAY_INDEX] = foam_indices
		foam_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, foam_arrays)
		var foam := MeshInstance3D.new()
		foam.mesh = foam_mesh
		var foam_material := StandardMaterial3D.new()
		foam_material.albedo_color = Color(0.82, 0.92, 0.88, 0.34)
		foam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		foam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		foam_material.cull_mode = BaseMaterial3D.CULL_DISABLED
		foam.material_override = foam_material
		foam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		foam.name = "CreekFoam"
		add_child(foam)
	# Pebbles and reeds along both banks.
	var rng := RandomNumberGenerator.new()
	rng.seed = 41027
	for i in 34:
		var wx := -_half_size + 4.0 + rng.randf() * (_area_size - 8.0)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var wz := _creek_center_z(wx) + side * (half + rng.randf_range(0.6, 1.7))
		var gy := _terrain_height_at(wx, wz)
		if rng.randf() < 0.55:
			var rock := CylinderMesh.new()
			rock.top_radius = rng.randf_range(0.10, 0.22)
			rock.bottom_radius = rock.top_radius * 1.2
			rock.height = rng.randf_range(0.12, 0.26)
			rock.radial_segments = 7
			_add_mesh_instance("CreekStone_%d" % i, rock,
				_flat_material(Color(0.46, 0.46, 0.40)),
				Vector3(wx, gy + rock.height * 0.35, wz), rng.randf() * TAU, false)
		else:
			var reed := CylinderMesh.new()
			reed.top_radius = 0.008
			reed.bottom_radius = 0.025
			reed.height = rng.randf_range(0.5, 1.0)
			reed.radial_segments = 5
			_add_mesh_instance("CreekReed_%d" % i, reed,
				_flat_material(Color(0.30, 0.44, 0.20)),
				Vector3(wx, gy + reed.height * 0.5, wz), 0.0, false)
	# Small riverbed pebbles: visible through the clear water, and intentionally
	# different from the random forest props that are excluded from the creek.
	for i in 26:
		var wx := -_half_size + 5.0 + rng.randf() * (_area_size - 10.0)
		var water_half := _creek_water_half_width()
		var wz := _creek_center_z(wx) + rng.randf_range(-water_half * 0.82, water_half * 0.82)
		var bed_y := _creek_water_y(wx) - _creek_depth_at(wx) + 0.02
		var pebble := CylinderMesh.new()
		pebble.top_radius = rng.randf_range(0.06, 0.15)
		pebble.bottom_radius = pebble.top_radius * 1.25
		pebble.height = rng.randf_range(0.035, 0.07)
		pebble.radial_segments = 7
		_add_mesh_instance("CreekPebble_%d" % i, pebble,
			_flat_material(Color(0.38, 0.36, 0.30).lerp(Color(0.58, 0.54, 0.42), rng.randf())),
			Vector3(wx, bed_y, wz), rng.randf() * TAU, false)
	if bool(cfg.get("bridge", true)):
		_build_creek_bridge()
	_build_creek_caves()
	_build_creek_puzzle()

func _creek_water_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	var shader := _load_shader("res://shaders/segment/creek.gdshader")
	if shader != null:
		material.shader = shader
		material.set_shader_parameter("shallow_color", Color(0.30, 0.64, 0.62, 0.55))
		material.set_shader_parameter("deep_color", Color(0.08, 0.28, 0.30, 0.84))
		return material
	var fallback := StandardMaterial3D.new()
	fallback.albedo_color = Color(0.20, 0.52, 0.50, 0.55)
	fallback.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fallback.roughness = 0.08
	fallback.metallic = 0.0
	material.shader = null
	return material

## The two ends of the creek disappear into a rocky cave mouth. The rock mass
## and its hidden collision wall replace the invisible map-edge wall visually.
func _build_creek_puzzle() -> void:
	_puzzle_enabled = false
	_puzzle_pillars.clear()
	_puzzle_symbol_nodes.clear()
	_puzzle_progress = 0
	_puzzle_solved = false
	if not _creek_enabled():
		return
	var candidates := [Vector2(10.0, 21.5), Vector2(-12.0, 19.0), Vector2(12.0, 18.0)]
	for candidate in candidates:
		if _in_creek(candidate, 2.2):
			continue
		if absf(candidate.x) > _half_size - 8.0 or absf(candidate.y) > _half_size - 8.0:
			continue
		_puzzle_center = candidate
		break
	if _puzzle_center == Vector2.ZERO:
		return
	_puzzle_enabled = true
	var stone := _flat_material(Color(0.40, 0.42, 0.39))
	var stone_dark := _flat_material(Color(0.25, 0.27, 0.26))
	var gold := _glow_material(Color(1.0, 0.76, 0.32), 1.8)
	var off := _glow_material(Color(0.46, 0.48, 0.42), 0.0)
	_puzzle_symbol_material = off
	_puzzle_lit_material = gold
	var cy := _terrain_height_at(_puzzle_center.x, _puzzle_center.y)
	var core_root := Node3D.new()
	core_root.position = Vector3(_puzzle_center.x, cy, _puzzle_center.y)
	add_child(core_root)
	_add_mesh_instance("PuzzleBrazier", _make_cylinder_mesh(0.46, 0.60, 0.48, 8), stone_dark,
		Vector3(0.0, 0.24, 0.0), 0.0, true, core_root)
	_add_mesh_instance("PuzzleCore", _make_cylinder_mesh(0.26, 0.32, 0.10, 10),
		gold, Vector3(0.0, 0.53, 0.0), 0.0, false, core_root)
	_puzzle_core = core_root.get_node("PuzzleCore") as MeshInstance3D
	_puzzle_light = OmniLight3D.new()
	_puzzle_light.position = Vector3(0.0, 0.85, 0.0)
	_puzzle_light.light_color = Color(1.0, 0.72, 0.34)
	_puzzle_light.omni_range = 5.0
	_puzzle_light.light_energy = 0.0
	_puzzle_light.shadow_enabled = false
	core_root.add_child(_puzzle_light)
	var symbol_order := ["mountain", "house", "sun"]
	var offsets := [Vector2(-2.35, 0.35), Vector2(2.35, 0.35), Vector2(0.0, -2.65)]
	for i in 3:
		var pos: Vector2 = _puzzle_center + offsets[i]
		var ground := _terrain_height_at(pos.x, pos.y)
		var root := Node3D.new()
		root.position = Vector3(pos.x, ground, pos.y)
		add_child(root)
		_add_mesh_instance("PuzzleBase_%d" % i, _make_cylinder_mesh(0.52, 0.66, 0.28, 8), stone,
			Vector3(0.0, 0.14, 0.0), 0.0, true, root)
		_add_mesh_instance("PuzzlePost_%d" % i, _make_box_mesh(Vector3(0.50, 1.10, 0.50)), stone_dark,
			Vector3(0.0, 0.83, 0.0), 0.0, true, root)
		var symbol := _make_puzzle_symbol(symbol_order[i], _puzzle_symbol_material)
		symbol.position = Vector3(0.0, 1.58, 0.0)
		root.add_child(symbol)
		_puzzle_symbol_nodes.append(symbol)
		_puzzle_pillars.append({"pos": pos, "symbol": symbol_order[i], "node": root})
		_add_cylinder_collision(pos, 0.34, 1.7, ground)
	var tablet_pos := _puzzle_center + Vector2(0.0, 3.0)
	var tablet_y := _terrain_height_at(tablet_pos.x, tablet_pos.y)
	var tablet := Node3D.new()
	tablet.position = Vector3(tablet_pos.x, tablet_y, tablet_pos.y)
	add_child(tablet)
	_add_mesh_instance("PuzzleTablet", _make_box_mesh(Vector3(1.35, 1.05, 0.22)), stone,
		Vector3(0.0, 0.54, 0.0), 0.0, true, tablet)
	_add_mesh_instance("PuzzleTabletFace", _make_box_mesh(Vector3(1.06, 0.78, 0.03)), stone_dark,
		Vector3(0.0, 0.57, 0.13), 0.0, false, tablet)
	for i in 3:
		_add_mesh_instance("PuzzleGlyph_%d" % i, _make_box_mesh(Vector3(0.16, 0.10, 0.02)),
			stone_dark, Vector3(-0.30 + float(i) * 0.30, 0.64 - float(i % 2) * 0.18, 0.16), 0.0, false, tablet)
	_add_box_collision(tablet_pos, Vector3(1.5, 1.2, 0.4), 0.0, tablet_y)
	_puzzle_tablet_pos = Vector3(tablet_pos.x, tablet_y, tablet_pos.y)
	if GameState.has_item("creek_chime"):
		_puzzle_solved = true
		_puzzle_light.light_energy = 1.2

func _make_cylinder_mesh(top: float, bottom: float, height: float, segments: int = 10) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = segments
	return mesh

func _make_box_mesh(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh

func _make_puzzle_symbol(kind: String, material: Material) -> Node3D:
	var holder := Node3D.new()
	match kind:
		"sun":
			var sun := MeshInstance3D.new()
			sun.mesh = _make_cylinder_mesh(0.22, 0.22, 0.05, 10)
			sun.rotation.z = PI * 0.5
			holder.add_child(sun)
			for i in 6:
				var ray := MeshInstance3D.new()
				ray.mesh = _make_box_mesh(Vector3(0.055, 0.055, 0.025))
				ray.position = Vector3(cos(TAU * float(i) / 6.0) * 0.31, sin(TAU * float(i) / 6.0) * 0.31, 0.0)
				holder.add_child(ray)
		"mountain":
			var peak := MeshInstance3D.new()
			peak.mesh = _make_cylinder_mesh(0.02, 0.30, 0.45, 5)
			peak.position = Vector3(0.0, 0.04, 0.0)
			holder.add_child(peak)
		_:
			var house := MeshInstance3D.new()
			house.mesh = _make_box_mesh(Vector3(0.34, 0.24, 0.28))
			house.position = Vector3(0.0, -0.02, 0.0)
			holder.add_child(house)
			var roof := MeshInstance3D.new()
			roof.mesh = _make_cylinder_mesh(0.02, 0.28, 0.20, 4)
			roof.position = Vector3(0.0, 0.18, 0.0)
			holder.add_child(roof)
	_set_symbol_material(holder, material)
	return holder

func _set_symbol_material(symbol: Node3D, material: Material) -> void:
	for child in symbol.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).material_override = material
			(child as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func get_puzzle_prompt(player_pos: Vector3) -> String:
	if not _puzzle_enabled:
		return ""
	if _puzzle_tablet_pos.distance_to(player_pos) < 2.15:
		return "E 阅读石碑"
	for pillar in _puzzle_pillars:
		var pos: Vector2 = pillar["pos"]
		var world := Vector3(pos.x, float(_terrain_height_at(pos.x, pos.y)), pos.y)
		if world.distance_to(player_pos) < 2.15:
			return "E 触碰石柱"
	return ""

func interact_puzzle(player_pos: Vector3) -> Dictionary:
	if not _puzzle_enabled:
		return {}
	if _puzzle_tablet_pos.distance_to(player_pos) < 2.15:
		return {"lines": [_puzzle_line("碑上刻着：先有晨光，再有山，最后才是家。")]}
	for i in _puzzle_pillars.size():
		var pillar: Dictionary = _puzzle_pillars[i]
		var pos: Vector2 = pillar["pos"]
		var world := Vector3(pos.x, float(_terrain_height_at(pos.x, pos.y)), pos.y)
		if world.distance_to(player_pos) >= 2.15:
			continue
		if _puzzle_solved:
			return {"lines": [_puzzle_line("石阵安静地亮着，风铃声很轻。")]}
		var symbol := str(pillar["symbol"])
		var expected := ["sun", "mountain", "house"]
		if symbol == expected[_puzzle_progress]:
			_set_symbol_material(_puzzle_symbol_nodes[i], _puzzle_lit_material)
			_puzzle_progress += 1
			if _puzzle_progress >= 3:
				_puzzle_solved = true
				_puzzle_light.light_energy = 2.2
				_puzzle_core.material_override = _glow_material(Color(1.0, 0.76, 0.32), 2.2)
				return {
					"lines": [
						_puzzle_line("三块石头依次亮起。"),
						_puzzle_line("石阵中央，一只旧风铃从石头缝里露出来。"),
					],
					"event": "solve",
					"give_item": true,
				}
			return {"event": "step", "lines": [_puzzle_line("石头亮起，风铃响了一声。")]}
		_puzzle_progress = 0
		for node in _puzzle_symbol_nodes:
			_set_symbol_material(node, _puzzle_symbol_material)
		return {"event": "wrong", "lines": [_puzzle_line("三块石头同时暗了下去，水面轻轻震了一下。")]}
	return {}

func _puzzle_line(text: String) -> Dictionary:
	return {"t": "line", "who": "me", "text": text}

func _build_creek_caves() -> void:
	if not _creek_enabled():
		return
	var level := _creek_water_y(0.0)
	var rock := _flat_material(Color(0.25, 0.28, 0.27))
	var rock_dark := _flat_material(Color(0.15, 0.18, 0.18))
	var moss := _flat_material(Color(0.22, 0.31, 0.17))
	var dark := _flat_material(Color(0.018, 0.022, 0.026))
	dark.cull_mode = BaseMaterial3D.CULL_DISABLED
	for side in [-1.0, 1.0]:
		var side_f := float(side)
		var x0: float = side_f * (_half_size - 5.0)
		var z0 := _creek_center_z(x0)
		var root := Node3D.new()
		root.name = "CreekCaveEast" if side_f > 0.0 else "CreekCaveWest"
		root.position = Vector3(x0, level, z0)
		add_child(root)
		# Open rock tunnel: its mouth is a circular dark hole facing the map.
		var tunnel := CylinderMesh.new()
		tunnel.top_radius = 2.8
		tunnel.bottom_radius = 2.8
		tunnel.height = 6.0
		tunnel.radial_segments = 14
		tunnel.cap_top = false
		tunnel.cap_bottom = false
		var tunnel_node := MeshInstance3D.new()
		tunnel_node.mesh = tunnel
		tunnel_node.material_override = dark
		tunnel_node.position = Vector3(side_f * 3.0, 2.25, 0.0)
		tunnel_node.rotation.z = PI * 0.5
		tunnel_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(tunnel_node)
		# dark back wall, well behind the mouth
		var back := CylinderMesh.new()
		back.top_radius = 2.78
		back.bottom_radius = 2.78
		back.height = 0.2
		back.radial_segments = 14
		var back_node := MeshInstance3D.new()
		back_node.mesh = back
		back_node.material_override = dark
		back_node.position = Vector3(side_f * 5.9, 2.25, 0.0)
		back_node.rotation.z = PI * 0.5
		root.add_child(back_node)
		var rng := RandomNumberGenerator.new()
		rng.seed = 31031 + int(side)
		# A dark disk at the mouth guarantees a readable cave opening above the
		# water even when the surrounding rock blobs overlap from an angle.
		var mouth := CylinderMesh.new()
		mouth.top_radius = 2.45
		mouth.bottom_radius = 2.45
		mouth.height = 0.12
		mouth.radial_segments = 18
		var mouth_node := MeshInstance3D.new()
		mouth_node.mesh = mouth
		mouth_node.material_override = dark
		mouth_node.position = Vector3(side_f * 0.12, 2.22, 0.0)
		mouth_node.rotation.z = PI * 0.5
		mouth_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mouth_node)
		# A semicircular rock arch around the mouth.
		for i in 11:
			var angle := lerpf(-0.10, PI + 0.10, float(i) / 10.0)
			var rock_mesh := SphereMesh.new()
			rock_mesh.radius = rng.randf_range(1.0, 1.9)
			rock_mesh.height = rock_mesh.radius * 1.5
			rock_mesh.radial_segments = 7
			rock_mesh.rings = 4
			var rock_node := MeshInstance3D.new()
			rock_node.mesh = rock_mesh
			rock_node.material_override = rock if i % 4 != 0 else moss
			rock_node.position = Vector3(
				side_f * rng.randf_range(-0.1, 0.5),
				2.25 + sin(angle) * 3.35,
				cos(angle) * 4.15)
			rock_node.scale = Vector3(1.0, rng.randf_range(0.8, 1.25), 1.0)
			root.add_child(rock_node)
		# Chunky side cliffs make the opening read as a mountain rather than a box.
		for i in 10:
			var zside := -1.0 if i % 2 == 0 else 1.0
			var r := rng.randf_range(1.5, 3.0)
			var sphere := SphereMesh.new()
			sphere.radius = r
			sphere.height = r * rng.randf_range(1.3, 1.8)
			sphere.radial_segments = 7
			sphere.rings = 4
			var cliff := MeshInstance3D.new()
			cliff.mesh = sphere
			cliff.material_override = rock if i % 4 != 0 else rock_dark
			cliff.position = Vector3(
				side_f * rng.randf_range(1.0, 5.5),
				rng.randf_range(1.0, 5.5),
				zside * rng.randf_range(4.8, 7.5))
			root.add_child(cliff)
		# A bigger mountain mass further out/up, overlapping the tunnel and cliffs.
		for i in 5:
			var peak := SphereMesh.new()
			peak.radius = rng.randf_range(2.5, 4.6)
			peak.height = peak.radius * rng.randf_range(1.1, 1.7)
			peak.radial_segments = 8
			peak.rings = 5
			var mass := MeshInstance3D.new()
			mass.mesh = peak
			mass.material_override = rock_dark if i == 0 else rock
			mass.position = Vector3(
				side_f * rng.randf_range(3.0, 7.0),
				rng.randf_range(4.0, 8.0),
				rng.randf_range(-4.5, 4.5))
			root.add_child(mass)
		# Hidden collision wall inside the cave mouth.
		var body := StaticBody3D.new()
		body.collision_layer = WORLD_LAYER
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.8, 8.0, 9.0)
		shape.shape = box
		shape.position = Vector3(side_f * 1.8, 3.0, 0.0)
		body.add_child(shape)
		root.add_child(body)

func _build_creek_bridge() -> void:
	if _path_samples.is_empty():
		return
	var z0 := float(_creek_cfg().get("z", 27.0))
	var index := 0
	var best := INF
	for i in _path_samples.size():
		var d := absf(_path_samples[i].y - z0)
		if d < best:
			best = d
			index = i
	var point := _path_samples[index]
	var prev := _path_samples[maxi(index - 2, 0)]
	var next := _path_samples[mini(index + 2, _path_samples.size() - 1)]
	var tangent := (next - prev)
	if tangent.length_squared() < 1e-6:
		tangent = Vector2(0.0, -1.0)
	tangent = tangent.normalized()
	var yaw := atan2(tangent.x, tangent.y)
	var end_y_a := _terrain_height_at(point.x, point.y - 4.4)
	var end_y_b := _terrain_height_at(point.x, point.y + 4.4)
	var bank_y := (end_y_a + end_y_b) * 0.5
	var water_at_bridge := _creek_water_y(point.x)
	var deck_y := maxf(bank_y + 0.08, water_at_bridge + 0.55)
	var bridge := Node3D.new()
	bridge.name = "CreekBridge"
	bridge.position = Vector3(point.x, deck_y, point.y)
	bridge.rotation.y = yaw
	add_child(bridge)

	var wood := _flat_material(Color(0.50, 0.34, 0.20))
	var wood_dark := _flat_material(Color(0.32, 0.21, 0.12))
	var wood_light := _flat_material(Color(0.64, 0.46, 0.28))
	var length := 7.2
	var width := 3.05
	var arch_height := 0.95
	var plank_count := 19
	var deck_half := length * 0.5

	# Curved planks. The planks are short boxes rotated along the arch tangent,
	# which gives a much more convincing arch than a flat deck.
	for i in plank_count:
		var t := float(i) / float(plank_count - 1)
		var local_z := lerpf(-deck_half, deck_half, t)
		var arch := _bridge_arch(local_z, length, arch_height)
		var slope := _bridge_slope(local_z, length, arch_height)
		var plank := BoxMesh.new()
		plank.size = Vector3(width + 0.14, 0.16, length / float(plank_count) + 0.05)
		var plank_node := MeshInstance3D.new()
		plank_node.mesh = plank
		plank_node.material_override = wood_light if i % 3 == 0 else wood
		plank_node.position = Vector3(0.0, arch, local_z)
		plank_node.rotation.x = atan(slope)
		plank_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		bridge.add_child(plank_node)

	# Two arched side beams under the planks.
	for side in [-1.0, 1.0]:
		var x: float = float(side) * (width * 0.5 - 0.12)
		for i in 13:
			var t0 := float(i) / 13.0
			var t1 := float(i + 1) / 13.0
			var z0b := lerpf(-deck_half, deck_half, t0)
			var z1b := lerpf(-deck_half, deck_half, t1)
			var a := Vector3(x, _bridge_arch(z0b, length, arch_height) - 0.18, z0b)
			var b := Vector3(x, _bridge_arch(z1b, length, arch_height) - 0.18, z1b)
			_add_bridge_beam(bridge, a, b, 0.18, wood_dark)
	# End sills (all wood, no stone abutments).
	for side in [-1.0, 1.0]:
		var sill := BoxMesh.new()
		sill.size = Vector3(width + 0.42, 0.24, 0.36)
		var sill_node := MeshInstance3D.new()
		sill_node.mesh = sill
		sill_node.material_override = wood_dark
		sill_node.position = Vector3(0.0, -0.06, side * (deck_half + 0.10))
		sill_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		bridge.add_child(sill_node)
		# short wooden approach planks at both ends
		for k in 2:
			var ramp := BoxMesh.new()
			ramp.size = Vector3(width - 0.2, 0.10, 0.62)
			var ramp_node := MeshInstance3D.new()
			ramp_node.mesh = ramp
			ramp_node.material_override = wood
			ramp_node.position = Vector3(0.0, -0.10 - float(k) * 0.03,
				side * (deck_half + 0.45 + float(k) * 0.55))
			ramp_node.rotation.x = side * 0.06
			ramp_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			bridge.add_child(ramp_node)
	# Railing posts and handrails follow the arch.
	for side in [-1.0, 1.0]:
		var x: float = float(side) * (width * 0.5 + 0.02)
		for i in 7:
			var t := float(i) / 6.0
			var z := lerpf(-deck_half + 0.25, deck_half - 0.25, t)
			var arch := _bridge_arch(z, length, arch_height)
			var post := BoxMesh.new()
			post.size = Vector3(0.13, 1.15, 0.13)
			var post_node := MeshInstance3D.new()
			post_node.mesh = post
			post_node.material_override = wood_dark
			post_node.position = Vector3(x, arch + 0.55, z)
			post_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			bridge.add_child(post_node)
			if i > 0:
				var t_prev := float(i - 1) / 6.0
				var z_prev := lerpf(-deck_half + 0.25, deck_half - 0.25, t_prev)
				var arch_prev := _bridge_arch(z_prev, length, arch_height)
				_add_bridge_beam(bridge,
					Vector3(x, arch_prev + 1.02, z_prev),
					Vector3(x, arch + 1.02, z),
					0.10, wood_light)
				_add_bridge_beam(bridge,
					Vector3(x, arch_prev + 0.48, z_prev),
					Vector3(x, arch + 0.48, z),
					0.07, wood_dark)
	# Wooden support posts / truss over the creek. No stone anywhere.
	var bottom_local := (_creek_water_y(point.x) - _creek_depth_at(point.x) - 0.15) - deck_y
	for i in 5:
		var t := float(i) / 4.0
		var z := lerpf(-deck_half * 0.72, deck_half * 0.72, t)
		var arch := _bridge_arch(z, length, arch_height)
		for side in [-1.0, 1.0]:
			var x: float = float(side) * 1.10
			var top := arch - 0.32
			var height := maxf(top - bottom_local, 0.2)
			var post := BoxMesh.new()
			post.size = Vector3(0.20, height, 0.20)
			var post_node := MeshInstance3D.new()
			post_node.mesh = post
			post_node.material_override = wood_dark
			post_node.position = Vector3(x, (top + bottom_local) * 0.5, z)
			post_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			bridge.add_child(post_node)
		# horizontal cross brace between the two legs
		_add_bridge_beam(bridge,
			Vector3(-1.10, bottom_local + 0.28, z),
			Vector3(1.10, bottom_local + 0.28, z),
			0.14, wood)
		if i > 0:
			# diagonal braces between consecutive frames
			var t_prev := float(i - 1) / 4.0
			var z_prev := lerpf(-deck_half * 0.72, deck_half * 0.72, t_prev)
			var arch_prev := _bridge_arch(z_prev, length, arch_height)
			_add_bridge_beam(bridge,
				Vector3(-1.10, arch_prev - 0.35, z_prev),
				Vector3(1.10, arch - 0.35, z), 0.09, wood)
			_add_bridge_beam(bridge,
				Vector3(1.10, arch_prev - 0.35, z_prev),
				Vector3(-1.10, arch - 0.35, z), 0.09, wood)
	# Arched walkable collision surface.
	var faces := PackedVector3Array()
	var collision_verts: Array[Vector3] = []
	for i in 17:
		var t := float(i) / 16.0
		var z := lerpf(-deck_half, deck_half, t)
		var arch := _bridge_arch(z, length, arch_height) + 0.08
		collision_verts.append(Vector3(-width * 0.5, arch, z))
		collision_verts.append(Vector3(width * 0.5, arch, z))
	for i in 16:
		var a := i * 2
		faces.append_array([
			collision_verts[a], collision_verts[a + 2], collision_verts[a + 1],
			collision_verts[a + 1], collision_verts[a + 2], collision_verts[a + 3],
		])
	var body := StaticBody3D.new()
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var concave := ConcavePolygonShape3D.new()
	concave.set_faces(faces)
	concave.backface_collision = true
	shape.shape = concave
	body.add_child(shape)
	bridge.add_child(body)

func _bridge_arch(local_z: float, length: float, height: float) -> float:
	var t := clampf((local_z + length * 0.5) / length, 0.0, 1.0)
	return height * (1.0 - pow(2.0 * t - 1.0, 2.0))

func _bridge_slope(local_z: float, length: float, height: float) -> float:
	var t := clampf((local_z + length * 0.5) / length, 0.0, 1.0)
	return -4.0 * height * (2.0 * t - 1.0) / length

func _add_bridge_beam(parent: Node3D, a: Vector3, b: Vector3, thickness: float, material: Material) -> void:
	var direction := b - a
	var length := direction.length()
	if length < 0.0001:
		return
	var beam := BoxMesh.new()
	beam.size = Vector3(thickness, thickness, length)
	var node := MeshInstance3D.new()
	node.mesh = beam
	node.material_override = material
	node.position = (a + b) * 0.5
	var dir_norm := direction.normalized()
	var basis := Basis.looking_at(-dir_norm, Vector3.UP)
	node.transform = Transform3D(basis, node.position)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(node)

## Water surface + rim decoration (stones, reeds, lily pads) for every pond.
func _build_water() -> void:
	for pond_index in _ponds.size():
		var pond: Dictionary = _ponds[pond_index]
		var center: Vector2 = pond["pos"]
		var radius: float = pond["radius"]
		var water_y: float = pond["water_y"]

		var material := ShaderMaterial.new()
		var shader := _load_shader(WATER_SHADER_PATH)
		if shader != null:
			material.shader = shader
			material.set_shader_parameter("tint", _c("water_tint"))
		else:
			var fallback := StandardMaterial3D.new()
			fallback.albedo_color = _c("water_tint")
			fallback.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			fallback.roughness = 0.1
			material = null

		var plane := PlaneMesh.new()
		plane.size = Vector2(radius * 2.1, radius * 2.1)
		var water := MeshInstance3D.new()
		water.name = "PondWater_%d" % pond_index
		water.mesh = plane
		if material != null:
			water.material_override = material
		else:
			water.material_override = _flat_material(_c("water_tint"))
		water.position = Vector3(center.x, water_y, center.y)
		water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(water)
		_add_pond_wall(pond, pond_index)
		_add_pond_decor(pond_index, pond)

func _add_pond_decor(pond_index: int, pond: Dictionary) -> void:
	var center: Vector2 = pond["pos"]
	var radius: float = pond["radius"]
	var water_y: float = pond["water_y"]

	var rock_names := ["rock_smallFlatA.glb", "rock_smallFlatB.glb", "rock_smallC.glb"]
	for i in 10:
		var model := _load_model(KIT_DIR + rock_names[i % rock_names.size()])
		if model.is_empty():
			continue
		var angle := TAU * float(i) / 10.0 + _rng.randf_range(-0.22, 0.22)
		var rim := radius * _rng.randf_range(1.04, 1.20)
		var spot := center + Vector2(cos(angle), sin(angle)) * rim
		var rock_height := _rng.randf_range(0.35, 0.7)
		_add_model_instances("PondRock_%d_%d" % [pond_index, i], model,
			[{"pos": spot, "height": rock_height}], true,
			_model_max_extent(model))
		_add_sphere_collision(spot, maxf(0.18, rock_height * 0.40),
			maxf(0.10, rock_height * 0.26), _terrain_height_at(spot.x, spot.y))

	var reed_models: Array[Dictionary] = []
	for file_name in ["plant_flatTall.glb", "plant_flatShort.glb"]:
		var model := _load_model(KIT_DIR + file_name)
		if not model.is_empty():
			reed_models.append(model)
	var reed_buckets: Array = []
	for i in reed_models.size():
		reed_buckets.append([])
	if not reed_models.is_empty():
		for i in 16:
			var angle := TAU * float(i) / 16.0 + _rng.randf_range(-0.2, 0.2)
			var rim := radius * _rng.randf_range(0.99, 1.26)
			var spot := center + Vector2(cos(angle), sin(angle)) * rim
			var bucket: Array = reed_buckets[i % reed_models.size()]
			bucket.append({"pos": spot, "height": _rng.randf_range(0.55, 1.1)})
		for i in reed_models.size():
			_add_model_instances("PondReed_%d_%d" % [pond_index, i], reed_models[i],
				reed_buckets[i], false, -1.0)

	var lily_material := _flat_material(Color(0.24, 0.42, 0.24, 1.0))
	var lily_flower := _load_texture(FLOWER_WHITE_PATH)
	for i in 4:
		var angle := _rng.randf() * TAU
		var r := radius * _rng.randf_range(0.15, 0.60)
		var spot := center + Vector2(cos(angle), sin(angle)) * r
		var disc := CylinderMesh.new()
		disc.top_radius = 0.27
		disc.bottom_radius = 0.27
		disc.height = 0.012
		disc.radial_segments = 10
		var pad := MeshInstance3D.new()
		pad.name = "LilyPad"
		pad.mesh = disc
		pad.material_override = lily_material
		pad.position = Vector3(spot.x, water_y + 0.008, spot.y)
		pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(pad)
		if i % 2 == 0 and lily_flower != null:
			var flower_quad := QuadMesh.new()
			flower_quad.size = Vector2(0.16, 0.16)
			flower_quad.material = _flower_material(lily_flower)
			var flower := MeshInstance3D.new()
			flower.mesh = flower_quad
			flower.position = Vector3(spot.x + 0.05, water_y + 0.10, spot.y - 0.03)
			flower.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(flower)

## Four invisible walls just outside the playable square, so the player cannot
## walk off the segment. They are 6 m tall: no jump clears them.
func _build_perimeter_walls() -> void:
	var half := _half_size
	var thickness := WALL_THICKNESS
	var long_side := _area_size + thickness * 2.0
	var specs := [
		[Vector3(0.0, WALL_HEIGHT * 0.5, -half - thickness * 0.5), Vector3(long_side, WALL_HEIGHT, thickness)],
		[Vector3(0.0, WALL_HEIGHT * 0.5, half + thickness * 0.5), Vector3(long_side, WALL_HEIGHT, thickness)],
		[Vector3(-half - thickness * 0.5, WALL_HEIGHT * 0.5, 0.0), Vector3(thickness, WALL_HEIGHT, long_side)],
		[Vector3(half + thickness * 0.5, WALL_HEIGHT * 0.5, 0.0), Vector3(thickness, WALL_HEIGHT, long_side)],
	]
	for spec in specs:
		var offset: Vector3 = spec[0]
		var size: Vector3 = spec[1]
		var body := StaticBody3D.new()
		body.name = "Wall"
		body.collision_layer = WORLD_LAYER
		body.collision_mask = 0
		body.position = offset
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)
		add_child(body)

# =============================================================================
# DIRT PATH (visual ribbon, no collision)
# =============================================================================

## Samples the control polygon with a Catmull-Rom spline, ~PATH_STEP apart.
func _sample_path(points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	if points.size() < 2:
		return out
	var count := points.size()
	for i in range(count - 1):
		var p0 := points[maxi(i - 1, 0)]
		var p1 := points[i]
		var p2 := points[i + 1]
		var p3 := points[mini(i + 2, count - 1)]
		var span := p1.distance_to(p2)
		var steps := maxi(2, int(ceil(span / PATH_STEP)))
		if i == 0:
			out.append(p1)
		for s in range(1, steps + 1):
			out.append(_catmull_rom(p0, p1, p2, p3, float(s) / float(steps)))
	return _extend_path_ends(out)

## Extends the sampled path past its first/last control point until it reaches
## the segment edge, so the trail runs off-screen instead of being visibly cut
## at the spawn / exit pads. Extension points stay inside the playable margin.
func _extend_path_ends(samples: PackedVector2Array) -> PackedVector2Array:
	if samples.size() < 2:
		return samples
	var margin := _half_size - 1.5
	var start_tangent := (samples[1] - samples[0]).normalized()
	var end_tangent := (samples[samples.size() - 1] - samples[samples.size() - 2]).normalized()
	var before := PackedVector2Array()
	var offset := 0.0
	while offset < 20.0:
		offset += PATH_STEP
		var point := samples[0] - start_tangent * offset
		if absf(point.x) > margin or absf(point.y) > margin:
			break
		before.append(point)
	var out := PackedVector2Array()
	# Prepended points must run from far edge towards the original start.
	for i in range(before.size() - 1, -1, -1):
		out.append(before[i])
	out.append_array(samples)
	offset = 0.0
	while offset < 20.0:
		offset += PATH_STEP
		var point := samples[samples.size() - 1] + end_tangent * offset
		if absf(point.x) > margin or absf(point.y) > margin:
			break
		out.append(point)
	return out

func _catmull_rom(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	var a := p1 * 2.0
	var b := (p2 - p0) * t
	var c := (p0 * 2.0 - p1 * 5.0 + p2 * 4.0 - p3) * t2
	var d := (p1 * 3.0 - p0 - p2 * 3.0 + p3) * t3
	return (a + b + c + d) * 0.5

# --- path proximity queries ----------------------------------------------

## Coarse 1 m occupancy grid marking a superset of the cells near the path.
## Distance-to-path is only evaluated for cells inside it (fast reject).
func _build_path_near_mask() -> void:
	_mask_dim = int(ceil(_area_size / MASK_CELL)) + 2
	_path_mask = PackedByteArray()
	_path_mask.resize(_mask_dim * _mask_dim)
	if _path_samples.is_empty():
		return
	var reach := int(ceil(PATH_MASK_RADIUS / MASK_CELL))
	for sample in _path_samples:
		var cx := int(floor((sample.x + _half_size) / MASK_CELL))
		var cz := int(floor((sample.y + _half_size) / MASK_CELL))
		for dz in range(-reach, reach + 1):
			var iz := cz + dz
			if iz < 0 or iz >= _mask_dim:
				continue
			var row := iz * _mask_dim
			for dx in range(-reach, reach + 1):
				var ix := cx + dx
				if ix < 0 or ix >= _mask_dim:
					continue
				_path_mask[row + ix] = 1

func _maybe_near_path(pos: Vector2) -> bool:
	if _path_mask.is_empty():
		return true
	var ix := int(floor((pos.x + _half_size) / MASK_CELL))
	var iz := int(floor((pos.y + _half_size) / MASK_CELL))
	if ix < 0 or iz < 0 or ix >= _mask_dim or iz >= _mask_dim:
		return false
	return _path_mask[iz * _mask_dim + ix] != 0

## True when `pos` is at least `radius` metres away from the path polyline.
func _path_is_clear(pos: Vector2, radius: float) -> bool:
	if not _maybe_near_path(pos):
		return true
	return _path_distance(pos) >= radius

func _path_distance(pos: Vector2) -> float:
	var count := _path_samples.size()
	if count == 0:
		return INF
	if count == 1:
		return pos.distance_to(_path_samples[0])
	var best := INF
	var previous := _path_samples[0]
	for i in range(1, count):
		var current := _path_samples[i]
		# Cheap prune: no point on the segment can be closer than the gap in Z
		# between the query and the segment's Z span.
		var z_min := minf(previous.y, current.y)
		var z_max := maxf(previous.y, current.y)
		var z_gap := 0.0
		if pos.y < z_min:
			z_gap = z_min - pos.y
		elif pos.y > z_max:
			z_gap = pos.y - z_max
		if z_gap > best:
			previous = current
			continue
		var segment := _point_segment_distance(pos, previous, current)
		if segment < best:
			best = segment
		previous = current
	return best

func _point_segment_distance(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var length_sq := ab.length_squared()
	if length_sq < 1e-8:
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / length_sq, 0.0, 1.0)
	return point.distance_to(a + ab * t)

# =============================================================================
# GRASS
# =============================================================================

func _build_grass() -> int:
	var grid := maxf(_f("grass_grid"), 0.05)
	var cells := int(ceil(_area_size / grid))
	if cells * cells > MAX_BLADES:
		# Widen the grid instead of blowing the blade budget. The density mask
		# then removes ~28% of the cells, so the final count stays well below it.
		cells = int(floor(sqrt(float(MAX_BLADES))))
		grid = _area_size / float(cells)
		push_warning("[segment] grass_grid widened to %.3f to stay under %d blades" % [grid, MAX_BLADES])

	var blade_mesh := QuadMesh.new()
	blade_mesh.size = Vector2(_f("grass_width"), _f("grass_height"))
	blade_mesh.material = _grass_material()
	_grass_shader_material = blade_mesh.material as ShaderMaterial
	if _grass_shader_material != null:
		_grass_shader_material.set_shader_parameter("player_pos",
			Vector3(_player_start_xz.x, 0.0, _player_start_xz.y))
		_grass_materials.append(_grass_shader_material)

	var jitter := grid * GRASS_JITTER
	var path_clear := _path_width * 0.5 + PATH_CLEAR_MARGIN
	var player_sq := CLEAR_PLAYER * CLEAR_PLAYER
	var npc_sq := CLEAR_NPC * CLEAR_NPC
	var has_npc := _has_npc()
	var positions: Array[Vector3] = []
	var full := false

	for gz in cells:
		for gx in cells:
			var px := (float(gx) + 0.5) * grid - _half_size + _rng.randf_range(-jitter, jitter)
			var pz := (float(gz) + 0.5) * grid - _half_size + _rng.randf_range(-jitter, jitter)

			if positions.size() >= MAX_BLADES:
				full = true
				break

			# Jitter must never push a blade off the ground plane.
			if absf(px) >= _half_size or absf(pz) >= _half_size:
				continue

			# Spawn clearing for the player and (when present) the NPC.
			var dx := px - _player_start_xz.x
			var dz := pz - _player_start_xz.y
			if dx * dx + dz * dz < player_sq:
				continue
			if has_npc:
				dx = px - _npc_xz.x
				dz = pz - _npc_xz.y
				if dx * dx + dz * dz < npc_sq:
					continue

			if not _path_is_clear(Vector2(px, pz), path_clear):
				continue
			if _in_pond(Vector2(px, pz)):
				continue
			if _in_creek(Vector2(px, pz), 0.25):
				continue

			# Large-scale density patches so the field is not a uniform carpet.
			var density := DENSITY_BASE + DENSITY_AMPLITUDE * sin(px * DENSITY_FREQ_X + DENSITY_PHASE_X) * sin(pz * DENSITY_FREQ_Z + DENSITY_PHASE_Z)
			if _rng.randf() > density:
				continue

			positions.append(Vector3(px, _terrain_height_at(px, pz), pz))
		if full:
			break

	# One 12-float transform per blade: basis columns (R_y * scale) then origin.
	# Blade quads are centred on their origin, so origin.y = height / 2 puts the
	# base exactly on y = 0.
	var count := positions.size()
	var blade_height := _f("grass_height")
	var transforms := PackedFloat32Array()
	transforms.resize(count * 12)
	var customs := PackedColorArray()
	customs.resize(count)
	var cross_transforms := PackedFloat32Array()
	var cross_customs := PackedColorArray()
	for i in count:
		var yaw := _rng.randf() * TAU
		var cos_yaw := cos(yaw)
		var sin_yaw := sin(yaw)
		var width_scale := _rng.randf_range(GRASS_WIDTH_SCALE_MIN, GRASS_WIDTH_SCALE_MAX)
		var height_scale := _rng.randf_range(GRASS_HEIGHT_SCALE_MIN, GRASS_HEIGHT_SCALE_MAX)
		var base := positions[i]
		var offset := i * 12
		transforms[offset + 0] = cos_yaw * width_scale
		transforms[offset + 1] = 0.0
		transforms[offset + 2] = -sin_yaw * width_scale
		transforms[offset + 3] = base.x
		transforms[offset + 4] = 0.0
		transforms[offset + 5] = height_scale
		transforms[offset + 6] = 0.0
		transforms[offset + 7] = base.y + blade_height * height_scale * 0.5
		transforms[offset + 8] = sin_yaw * width_scale
		transforms[offset + 9] = 0.0
		transforms[offset + 10] = cos_yaw * width_scale
		transforms[offset + 11] = base.z
		customs[i] = Color(
			_rng.randf(),
			clampf(0.5 + 0.5 * sin(base.x * 0.19 + 1.3) * sin(base.z * 0.23 - 0.7), 0.0, 1.0),
			0.0,
			1.0)

		# Every blade gets a crossing companion quad, with a little random angle
		# so the field reads as woven grass instead of two clean layers.
		if true:
			var cross_yaw := yaw + PI * 0.5 + _rng.randf_range(-0.22, 0.22)
			var cross_cos := cos(cross_yaw)
			var cross_sin := sin(cross_yaw)
			var cross_width := width_scale * 0.72
			var cross_height := height_scale * 0.94
			var cross := PackedFloat32Array()
			cross.resize(12)
			cross[0] = cross_cos * cross_width
			cross[1] = 0.0
			cross[2] = -cross_sin * cross_width
			cross[3] = base.x
			cross[4] = 0.0
			cross[5] = cross_height
			cross[6] = 0.0
			cross[7] = base.y + blade_height * cross_height * 0.5
			cross[8] = cross_sin * cross_width
			cross[9] = 0.0
			cross[10] = cross_cos * cross_width
			cross[11] = base.z
			cross_transforms.append_array(cross)
			cross_customs.append(customs[i])

	_add_grass_multimesh("Grass", blade_mesh, transforms, customs)
	if cross_customs.size() > 0:
		_add_grass_multimesh("GrassCross", blade_mesh, cross_transforms, cross_customs)

	# A second, taller/wider tuft silhouette: breaks up the single-blade look and
	# adds a warmer colour variant to the field.
	var tuft_height := blade_height * 0.86
	var tuft_mesh := QuadMesh.new()
	tuft_mesh.size = Vector2(_f("grass_width") * 1.55, tuft_height)
	tuft_mesh.material = _grass_material(TUFT_TEXTURE_PATH, 1, tuft_height)
	var tuft_shader := tuft_mesh.material as ShaderMaterial
	if tuft_shader != null:
		tuft_shader.set_shader_parameter("player_pos",
			Vector3(_player_start_xz.x, 0.0, _player_start_xz.y))
		_grass_materials.append(tuft_shader)
	var tuft_transforms := PackedFloat32Array()
	var tuft_customs := PackedColorArray()
	for i in count:
		if i % 5 != 0:
			continue
		var yaw := _rng.randf() * TAU
		var cos_yaw := cos(yaw)
		var sin_yaw := sin(yaw)
		var width_scale := _rng.randf_range(0.90, 1.30)
		var height_scale := _rng.randf_range(0.70, 0.98)
		var base := positions[i] + Vector3(_rng.randf_range(-0.12, 0.12), 0.0,
			_rng.randf_range(-0.12, 0.12))
		var tuft := PackedFloat32Array()
		tuft.resize(12)
		tuft[0] = cos_yaw * width_scale
		tuft[1] = 0.0
		tuft[2] = -sin_yaw * width_scale
		tuft[3] = base.x
		tuft[4] = 0.0
		tuft[5] = height_scale
		tuft[6] = 0.0
		tuft[7] = base.y + tuft_height * height_scale * 0.5
		tuft[8] = sin_yaw * width_scale
		tuft[9] = 0.0
		tuft[10] = cos_yaw * width_scale
		tuft[11] = base.z
		tuft_transforms.append_array(tuft)
		tuft_customs.append(Color(
			_rng.randf(),
			clampf(0.5 + 0.5 * sin(base.x * 0.17 + 2.1) * sin(base.z * 0.21 - 1.7), 0.0, 1.0),
			0.0,
			1.0))
	if tuft_customs.size() > 0:
		_add_grass_multimesh("GrassTuft", tuft_mesh, tuft_transforms, tuft_customs)

	# Third, very thin and slightly taller layer: the soft "hair" that catches
	# the light between the broader blades and makes the field read as fur.
	var hair_height := blade_height * 1.20
	var hair_mesh := QuadMesh.new()
	hair_mesh.size = Vector2(_f("grass_width") * 0.30, hair_height)
	hair_mesh.material = _grass_material(BLADE_TEXTURE_PATH, 2, hair_height)
	var hair_shader := hair_mesh.material as ShaderMaterial
	if hair_shader != null:
		hair_shader.set_shader_parameter("player_pos",
			Vector3(_player_start_xz.x, 0.0, _player_start_xz.y))
		_grass_materials.append(hair_shader)
	var hair_transforms := PackedFloat32Array()
	var hair_customs := PackedColorArray()
	for i in count:
		if i % 3 != 0:
			continue
		var yaw := _rng.randf() * TAU
		var cos_yaw := cos(yaw)
		var sin_yaw := sin(yaw)
		var width_scale := _rng.randf_range(0.45, 0.95)
		var height_scale := _rng.randf_range(0.82, 1.18)
		var base := positions[i] + Vector3(_rng.randf_range(-0.18, 0.18), 0.0,
			_rng.randf_range(-0.18, 0.18))
		var hair := PackedFloat32Array()
		hair.resize(12)
		hair[0] = cos_yaw * width_scale
		hair[1] = 0.0
		hair[2] = -sin_yaw * width_scale
		hair[3] = base.x
		hair[4] = 0.0
		hair[5] = height_scale
		hair[6] = 0.0
		hair[7] = base.y + hair_height * height_scale * 0.5
		hair[8] = sin_yaw * width_scale
		hair[9] = 0.0
		hair[10] = cos_yaw * width_scale
		hair[11] = base.z
		hair_transforms.append_array(hair)
		hair_customs.append(Color(
			_rng.randf(),
			clampf(0.5 + 0.5 * sin(base.x * 0.29 + 0.4) * sin(base.z * 0.31 - 1.1), 0.0, 1.0),
			0.0,
			1.0))
	if hair_customs.size() > 0:
		_add_grass_multimesh("GrassHair", hair_mesh, hair_transforms, hair_customs)
	return count

func _grass_material(texture_path: String = BLADE_TEXTURE_PATH, variant: int = 0, mesh_height: float = -1.0) -> Material:
	var shader := _load_shader(GRASS_SHADER_PATH)
	var base_color := _c("grass_base")
	var tip_color := _c("grass_tip")
	var dry_mix := _f("grass_dry_mix")
	if variant == 1:
		# Warmer, slightly dry tuft colour.
		base_color = base_color.lerp(base_color * Color(1.14, 1.05, 0.76), 0.45)
		tip_color = tip_color.lerp(Color(0.68, 0.66, 0.32), 0.35)
		dry_mix = minf(1.0, dry_mix + 0.18)
	elif variant == 2:
		# Fine, soft "hair" blades: lighter tips and less dry contrast.
		base_color = base_color.lerp(Color(0.16, 0.30, 0.10), 0.45)
		tip_color = tip_color.lerp(Color(0.72, 0.88, 0.44), 0.55)
		dry_mix *= 0.45
	if shader == null:
		var fallback := StandardMaterial3D.new()
		fallback.albedo_color = base_color.lerp(tip_color, 0.5)
		fallback.cull_mode = BaseMaterial3D.CULL_DISABLED
		fallback.roughness = 1.0
		return fallback

	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("base_color", base_color)
	material.set_shader_parameter("tip_color", tip_color)
	material.set_shader_parameter("dry_color", _c("grass_dry"))
	material.set_shader_parameter("dry_mix", dry_mix)
	material.set_shader_parameter("blade_height", mesh_height if mesh_height > 0.0 else _f("grass_height"))
	material.set_shader_parameter("wind_strength", _f("wind_strength"))
	material.set_shader_parameter("wind_speed", _f("wind_speed"))
	material.set_shader_parameter("wind_direction", WIND_DIRECTION)
	var blade_texture := _load_texture(texture_path)
	if blade_texture != null:
		material.set_shader_parameter("blade_tex", blade_texture)
	return material

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
	multimesh.transform_array = _floats_to_vec3_transforms(transforms)
	multimesh.custom_data_array = customs
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	# Blades do not cast shadows: tens of thousands of shadow casters are wasted
	# fill rate at this camera distance.
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)

# =============================================================================
# PROPS (trees / rocks / bushes / flowers)
# =============================================================================

func _build_props() -> void:
	_tree_count = _build_tree_field()
	_rock_count = _build_rocks()
	_bush_count = _build_bushes()
	_flower_count = _build_flowers()
	_build_details()

## Feed the hero's world position / velocity to the grass shader so the field
## parts around the character's feet.
func _process(_delta: float) -> void:
	if _grass_shader_material == null:
		return
	if _grass_player == null or not is_instance_valid(_grass_player):
		_grass_player = get_tree().get_first_node_in_group("player") as Node3D
		if _grass_player == null:
			return
	var player_position := _grass_player.global_position
	var player_velocity := Vector3.ZERO
	if _grass_player is CharacterBody3D:
		player_velocity = (_grass_player as CharacterBody3D).velocity
	for material in _grass_materials:
		if material == null:
			continue
		material.set_shader_parameter("player_pos", player_position)
		material.set_shader_parameter("player_vel", player_velocity)

## Small dressing props scattered along the walk: ferns, mushroom groups, fallen
## logs, 3D flowers, flat stones and old fence pieces (per-segment counts).
## "height" groups are scaled by model height (upright plants); "size" groups are
## scaled by the model's longest axis (lying logs / flat stones / fence panels).
func _build_details() -> void:
	for group_name in DETAIL_GROUPS.keys():
		var group: Dictionary = DETAIL_GROUPS[group_name]
		var count := _i("detail_%s_count" % group_name)
		if count <= 0:
			continue
		var variants: Array[Dictionary] = []
		for file_name in group["models"]:
			var model := _load_model(KIT_DIR + str(file_name))
			if not model.is_empty():
				variants.append(model)
		if variants.is_empty():
			continue
		var entries: Array[Dictionary] = []
		var spacing := float(group["spacing"])
		var corridor := float(group["corridor"])
		var inner := float(group.get("inner", 1.6))
		var outer := float(group.get("outer", 10.0))
		for i in count:
			var spot := _find_prop_spot(spacing, corridor, inner, outer)
			if spot == SPOT_NONE:
				continue
			_occupied.append(spot)
			entries.append({
				"pos": spot,
				"height": _rng.randf_range(float(group["size_min"]), float(group["size_max"])),
				"yaw": _rng.randf() * TAU,
			})
		if entries.is_empty():
			continue
		var buckets: Array = []
		for i in variants.size():
			buckets.append([])
		for i in entries.size():
			buckets[i % variants.size()].append(entries[i])
		var use_size: bool = str(group.get("mode", "height")) == "size"
		var cast := bool(group["shadow"])
		var collide := bool(group.get("collide", false))
		for i in variants.size():
			if buckets[i].is_empty():
				continue
			var reference := _model_max_extent(variants[i]) if use_size else -1.0
			if collide:
				var bounds: AABB = variants[i]["aabb"]
				var scale_reference := reference if reference > 0.0 else maxf(bounds.size.y, 0.001)
				for entry in buckets[i]:
					var scale := float(entry["height"]) / scale_reference
					var dims := bounds.size * scale
					_add_box_collision(entry["pos"],
						Vector3(maxf(dims.x, 0.30), maxf(dims.y, 0.25), maxf(dims.z, 0.30)),
						float(entry["yaw"]), _terrain_height_at(entry["pos"].x, entry["pos"].y))
			_add_model_instances("Detail_%s_%d" % [group_name, i], variants[i], buckets[i], cast, reference)

## Ambient floating pollen / fireflies over the whole segment.
func _build_particles() -> void:
	var kind := _s("particles")
	if kind == "":
		return
	var texture_path: String = str(PARTICLE_TEXTURES.get(kind, PARTICLE_TEXTURES["pollen"]))
	var texture := _load_texture(texture_path)
	if texture == null:
		return
	var is_firefly := kind == "fireflies"
	var base_y := _macro_height(0.0, 0.0)
	var amount := maxi(8, _i("particle_amount"))

	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.07, 0.07) if is_firefly else Vector2(0.08, 0.08)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_texture = texture
	material.vertex_color_use_as_albedo = true
	material.disable_receive_shadows = true
	if is_firefly:
		material.emission_enabled = true
		material.emission = Color(1.0, 0.88, 0.40, 1.0)
		material.emission_energy_multiplier = 2.5
	mesh.material = material

	var particles := GPUParticles3D.new()
	particles.name = "AmbientParticles"
	particles.amount = amount
	particles.lifetime = 12.0
	particles.preprocess = 6.0
	particles.local_coords = false
	var macro_base := _macro_height(0.0, 0.0)
	particles.visibility_aabb = AABB(
		Vector3(-_half_size, macro_base - 4.0, -_half_size),
		Vector3(_area_size, 11.0, _area_size))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.direction = Vector3(0.3, 0.05, 0.15)
	process.spread = 180.0
	process.initial_velocity_min = 0.02
	process.initial_velocity_max = 0.10
	process.scale_min = 0.6
	process.scale_max = 1.25
	process.angle_min = 0.0
	process.angle_max = 360.0
	var box_x := minf(_half_size * 0.92, 22.0)
	var box_z := minf(_half_size * 0.95, 48.0)
	if is_firefly:
		particles.position = Vector3(0.0, base_y + 0.9, 0.0)
		process.emission_box_extents = Vector3(box_x, 0.9, box_z)
		process.initial_velocity_min = 0.05
		process.initial_velocity_max = 0.16
		process.gravity = Vector3(0.0, 0.0, 0.0)
		process.color = Color(0.85, 1.0, 0.55, 0.95)
	else:
		particles.position = Vector3(0.0, base_y + 1.4, 0.0)
		process.emission_box_extents = Vector3(box_x, 1.8, box_z)
		process.gravity = Vector3(0.0, -0.015, 0.0)
		process.color = Color(1.0, 0.96, 0.80, 0.90)
	particles.process_material = process
	particles.draw_pass_1 = mesh
	add_child(particles)

func _build_tree_field() -> int:
	var variants: Array[Dictionary] = []
	for file_name in _names("prop_tree_models"):
		var model := _load_model(KIT_DIR + file_name)
		if not model.is_empty():
			variants.append(model)
	if variants.is_empty():
		push_warning("[segment] no Kenney tree models loaded — no trees in this segment")
		return 0

	var tree_scale := _f("tree_scale")
	var scattered: Array[Dictionary] = []
	for i in _i("prop_tree_count"):
		# Trees keep ~6 m of open view corridor beside the path: they frame the
		# shot instead of covering the hero.
		var spot := _find_prop_spot(TREE_SPACING, TREE_CORRIDOR_RATIO, 4.5, CORRIDOR_OUTER, 1.4, true)
		if spot == SPOT_NONE:
			continue
		_occupied.append(spot)
		scattered.append({
			"pos": spot,
			"height": _rng.randf_range(TREE_HEIGHT_MIN, TREE_HEIGHT_MAX) * tree_scale,
		})

	var avenue := _avenue_tree_spots(tree_scale)
	var saplings := _foreground_sapling_spots(tree_scale)
	var framing := _edge_frame_spots(tree_scale)
	var curtain := _outer_curtain_spots(tree_scale)
	var boundary := _outer_boundary_forest_spots(tree_scale)
	var total := _instance_model_spread("Tree_%d", variants, scattered, true, -1.0)
	total += _instance_model_spread("AvenueTree_%d", variants, avenue, true, -1.0)
	total += _instance_model_spread("ForeTree_%d", variants, saplings, true, -1.0)
	total += _instance_model_spread("EdgeTree_%d", variants, framing, true, -1.0)
	total += _instance_model_spread("CurtainTree_%d", variants, curtain, true, -1.0)
	total += _instance_model_spread("BoundaryTree_%d", variants, boundary, true, -1.0)

	# Only the playable-area trees collide; the perimeter framing trees are set
	# dressing and are left intangible (same choice as the verified world.gd ring).
	for entry in scattered + avenue + saplings + framing:
		var pos: Vector2 = entry["pos"]
		var height: float = entry["height"]
		# Invisible trunk wall: wide enough that the hero cannot walk through the
		# trunk from any direction, tall enough that jumping cannot clear it.
		_add_cylinder_collision(pos, clampf(height * 0.10, 0.30, 0.62), 3.2,
			_terrain_height_at(pos.x, pos.y))
	return total

## Short trees on the camera side of the path. They sit low in the frame (below
## the hero's feet), so they add foreground depth without covering the hero.
func _foreground_sapling_spots(tree_scale: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _path_samples.size() < 4:
		return out
	var target := maxi(6, int(_i("prop_tree_count") * 0.18))
	var attempts := 0
	while out.size() < target and attempts < target * 12:
		attempts += 1
		var sample := _path_samples[_rng.randi_range(0, _path_samples.size() - 1)]
		var spot := sample + Vector2(_rng.randf_range(-2.0, 2.0), _rng.randf_range(4.8, 9.0))
		if absf(spot.x) > _half_size - 3.0 or absf(spot.y) > _half_size - 3.0:
			continue
		if _path_distance(spot) < 4.4:
			continue
		if _nearest_path_point(spot).y > spot.y - 2.0:
			continue
		if _in_pond(spot):
			continue
		if _in_creek(spot, 1.0) or _near_creek_cave(spot):
			continue
		if _puzzle_enabled and spot.distance_to(_puzzle_center) < 5.2:
			continue
		if spot.distance_squared_to(_player_start_xz) < 16.0:
			continue
		if _has_npc() and spot.distance_squared_to(_npc_xz) < 64.0:
			continue
		if not _is_free(spot, 2.2):
			continue
		_occupied.append(spot)
		out.append({
			"pos": spot,
			"height": _rng.randf_range(1.5, 2.4) * tree_scale,
		})
	return out

## Avenue trees: every ~6 m along the path, alternate sides, 5.6-9 m out. They
## line the walk and fill the frame without standing between camera and hero.
func _avenue_tree_spots(tree_scale: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _path_samples.size() < 4:
		return out
	var step_along := 3.6
	var traveled := 0.0
	var side := 1.0
	for i in range(1, _path_samples.size()):
		var previous := _path_samples[i - 1]
		var current := _path_samples[i]
		traveled += previous.distance_to(current)
		if traveled < step_along:
			continue
		traveled = 0.0
		side = -side
		var tangent := current - _path_samples[maxi(i - 3, 0)]
		if tangent.length_squared() < 1e-6:
			continue
		tangent = tangent.normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		for attempt in 8:
			var distance := _rng.randf_range(4.8, 7.2)
			var spot := current + normal * side * distance + tangent * _rng.randf_range(-2.0, 2.0)
			if absf(spot.x) > _half_size - 3.0 or absf(spot.y) > _half_size - 3.0:
				continue
			if not _tree_view_clear(spot):
				continue
			if _path_distance(spot) < 4.8:
				continue
			if _in_pond(spot):
				continue
			if _in_creek(spot, 1.0) or _near_creek_cave(spot):
				continue
			if _puzzle_enabled and spot.distance_to(_puzzle_center) < 5.2:
				continue
			if spot.distance_squared_to(_player_start_xz) < 25.0:
				continue
			if spot.distance_squared_to(_exit_xz) < 25.0:
				continue
			if _has_npc() and spot.distance_squared_to(_npc_xz) < 16.0:
				continue
			if not _is_free(spot, TREE_SPACING):
				continue
			_occupied.append(spot)
			out.append({
				"pos": spot,
				"height": _rng.randf_range(TREE_HEIGHT_MIN, TREE_HEIGHT_MAX) * tree_scale,
			})
			break
	return out

## Distributes `entries` over the loaded model variants, one MultiMesh bucket
## per model, so every variant is one draw call per mesh part.
func _instance_model_spread(name_pattern: String, variants: Array[Dictionary], entries: Array, cast_shadow: bool, reference_size: float) -> int:
	if entries.is_empty():
		return 0
	var buckets: Array = []
	for i in variants.size():
		buckets.append([])
	for i in entries.size():
		var bucket: Array = buckets[i % variants.size()]
		bucket.append(entries[i])
	for i in variants.size():
		_add_model_instances(name_pattern % i, variants[i], buckets[i], cast_shadow, reference_size)
	return entries.size()

## Trees along the inside of the invisible walls: they hide the world edge and
## frame the horizon in every direction without costing a gameplay collider.
func _edge_frame_spots(tree_scale: float) -> Array[Dictionary]:
	# Three dense rows inside the boundary wall: the outermost ring is the
	# "you cannot see the void" curtain; inner rows add forest depth.
	var out: Array[Dictionary] = []
	for row in EDGE_ROWS:
		var inset := EDGE_INSET + float(row) * EDGE_ROW_STEP
		var edge := _half_size - inset
		var height_min := 4.6 + float(row) * 1.2
		var height_max := 6.4 + float(row) * 1.6
		var spacing := EDGE_FRAME_SPACING + float(row) * 0.5
		for side_index in 4:
			var along := -edge
			while along <= edge:
				var spot := Vector2.ZERO
				var inward := Vector2.ZERO
				match side_index:
					0:
						spot = Vector2(along, -edge)
						inward = Vector2(0.0, 1.0)
					1:
						spot = Vector2(along, edge)
						inward = Vector2(0.0, -1.0)
					2:
						spot = Vector2(-edge, along)
						inward = Vector2(1.0, 0.0)
					_:
						spot = Vector2(edge, along)
						inward = Vector2(-1.0, 0.0)
				spot += inward * _rng.randf_range(0.0, 2.0)
				var step := spacing * _rng.randf_range(0.85, 1.20)
				if _in_pond(spot, 1.2) or _in_creek(spot, 1.0) or _near_creek_cave(spot):
					along += step
					continue
				# Keep the spawn / exit pads and the NPC clear so the forest never
				# blocks the hero or the interactive props.
				if spot.distance_to(_player_start_xz) < 12.0:
					along += step
					continue
				if spot.distance_to(_exit_xz) < 10.0:
					along += step
					continue
				if _has_npc() and spot.distance_to(_npc_xz) < 9.0:
					along += step
					continue
				# The hero starts against the south edge; the camera looks from +Z,
				# so south-edge trees in that window would sit right in front of
				# the lens.
				if side_index == 1 and absf(spot.x) < 12.0:
					along += step
					continue
				out.append({
					"pos": spot,
					"height": _rng.randf_range(height_min, height_max) * tree_scale,
				})
				along += step
	return out

## Tall visual-only forest beyond the boundary wall. It hides the horizon / the
## outside of the map; no collision because the player can never reach it.
func _outer_curtain_spots(tree_scale: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var rings := [
		{"radius": _half_size + 3.0, "step": 4.0, "h_min": 7.0, "h_max": 10.0},
		{"radius": _half_size + 10.5, "step": 4.6, "h_min": 9.0, "h_max": 13.0},
		{"radius": _half_size + 19.0, "step": 5.4, "h_min": 11.0, "h_max": 15.0},
	]
	for ring in rings:
		var radius: float = ring["radius"]
		var count := int(ceil(TAU * radius / float(ring["step"])))
		for i in count:
			var angle := TAU * float(i) / float(count) + _rng.randf_range(-0.06, 0.06)
			var jitter := _rng.randf_range(-1.6, 1.6)
			var pos := Vector2(cos(angle), sin(angle)) * (radius + jitter)
			# The circular ring cuts through the square corners; skip the parts
			# that fall inside the playable map (those are already edge forest).
			if absf(pos.x) < _half_size - 0.5 and absf(pos.y) < _half_size - 0.5:
				continue
			if _near_creek_cave(pos):
				continue
			out.append({
				"pos": pos,
				"height": _rng.randf_range(float(ring["h_min"]), float(ring["h_max"])) * tree_scale,
				"ground_y": _curtain_ground_height(pos),
			})
	return out

## Curtain trees are visual-only and sit outside the walls. Ground them at the
## height of the nearest playable edge so the forest stays at the normal ridge
## height instead of dropping to the low backdrop plane.
func _curtain_ground_height(pos: Vector2) -> float:
	var edge := maxf(_half_size - 1.5, 0.0)
	var clamped := Vector2(clampf(pos.x, -edge, edge), clampf(pos.y, -edge, edge))
	return _terrain_height_at(clamped.x, clamped.y)

## Dense tree rows just outside the invisible wall. Together with the outer
## hedge they replace the empty air wall visually: from either camera the
## horizon is a wall of interlocking trunks and canopies.
func _outer_boundary_forest_spots(tree_scale: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in 3:
		var offset := 2.0 + float(row) * 3.4
		var edge := _half_size + offset
		var spacing := 1.35 + float(row) * 0.18
		var height_min := 5.4 + float(row) * 1.1
		var height_max := 7.2 + float(row) * 1.5
		for side in 4:
			var along := -edge
			while along <= edge:
				var pos := Vector2.ZERO
				match side:
					0:
						pos = Vector2(along, -edge)
					1:
						pos = Vector2(along, edge)
					2:
						pos = Vector2(-edge, along)
					_:
						pos = Vector2(edge, along)
				if _near_creek_cave(pos):
					along += spacing
					continue
				out.append({
					"pos": pos,
					"height": _rng.randf_range(height_min, height_max) * tree_scale,
					"ground_y": _curtain_ground_height(pos),
				})
				along += spacing * _rng.randf_range(0.9, 1.25)
	return out

func _build_outer_boundary_hedge(models: Array[Dictionary]) -> int:
	if models.is_empty():
		return 0
	var buckets: Array = []
	for i in models.size():
		buckets.append([])
	var total := 0
	for row in 2:
		var offset := 0.7 + float(row) * 1.45
		var edge := _half_size + offset
		var spacing := 0.82 + float(row) * 0.12
		for side in 4:
			var along := -edge
			while along <= edge:
				var pos := Vector2.ZERO
				match side:
					0:
						pos = Vector2(along, -edge)
					1:
						pos = Vector2(along, edge)
					2:
						pos = Vector2(-edge, along)
					_:
						pos = Vector2(edge, along)
				var bucket: Array = buckets[total % models.size()]
				bucket.append({
					"pos": pos,
					"height": _rng.randf_range(1.55, 2.8),
					"ground_y": _curtain_ground_height(pos),
				})
				total += 1
				along += spacing * _rng.randf_range(0.85, 1.20)
	for i in models.size():
		_add_model_instances("BoundaryHedge_%d" % i, models[i], buckets[i], false, -1.0)
	return total

func _build_rocks() -> int:
	var models: Array[Dictionary] = []
	for file_name in ROCK_MODELS:
		var model := _load_model(KIT_DIR + file_name)
		if not model.is_empty():
			models.append(model)
	if models.is_empty():
		return 0

	var buckets: Array = []
	for i in models.size():
		buckets.append([])
	var total := 0
	for i in _i("prop_rock_count"):
		var spot := _find_prop_spot(ROCK_SPACING, ROCK_CORRIDOR_RATIO)
		if spot == SPOT_NONE:
			continue
		_occupied.append(spot)
		var size := _rng.randf_range(0.45, 1.15)
		var bucket: Array = buckets[i % models.size()]
		bucket.append({"pos": spot, "height": size})
		total += 1
		_add_sphere_collision(spot, maxf(0.22, size * 0.40), maxf(0.12, size * 0.26),
			_terrain_height_at(spot.x, spot.y))
	for i in models.size():
		_add_model_instances("Rock_%d" % i, models[i], buckets[i], true, _model_max_extent(models[i]))
	return total

func _build_bushes() -> int:
	var models: Array[Dictionary] = []
	for file_name in BUSH_MODELS:
		var model := _load_model(KIT_DIR + file_name)
		if not model.is_empty():
			models.append(model)
	if models.is_empty():
		return 0

	var buckets: Array = []
	for i in models.size():
		buckets.append([])
	var total := 0
	for i in _i("prop_bush_count"):
		var spot := _find_prop_spot(BUSH_SPACING, BUSH_CORRIDOR_RATIO)
		if spot == SPOT_NONE:
			continue
		_occupied.append(spot)
		var size := _rng.randf_range(0.55, 1.15)
		var bucket: Array = buckets[i % models.size()]
		bucket.append({"pos": spot, "height": size})
		total += 1
		if size >= 0.45:
			_add_cylinder_collision(spot, clampf(size * 0.42, 0.25, 0.58),
				maxf(0.7, size * 0.95), _terrain_height_at(spot.x, spot.y))
	for i in models.size():
		_add_model_instances("Bush_%d" % i, models[i], buckets[i], true, _model_max_extent(models[i]))
	total += _build_outer_boundary_hedge(models)
	return total

func _build_flowers() -> int:
	var white_texture := _load_texture(FLOWER_WHITE_PATH)
	var yellow_texture := _load_texture(FLOWER_YELLOW_PATH)
	if white_texture == null and yellow_texture == null:
		return 0

	var white_xforms: Array[Transform3D] = []
	var yellow_xforms: Array[Transform3D] = []
	var total := 0
	var path_half := _path_width * 0.5
	var samples := _path_samples
	if samples.is_empty():
		return 0

	for i in _i("prop_flower_count"):
		var anchor := samples[_rng.randi_range(0, samples.size() - 1)]
		var angle := _rng.randf() * TAU
		var radius := path_half + _rng.randf_range(FLOWER_PATH_MIN, FLOWER_PATH_MAX)
		var pos := anchor + Vector2(cos(angle), sin(angle)) * radius
		var flower_scale := _rng.randf_range(0.75, 1.55)
		var xform := Transform3D(
			Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(flower_scale, flower_scale, flower_scale)),
			Vector3(pos.x, _terrain_height_at(pos.x, pos.y) + FLOWER_HEIGHT, pos.y))
		if i % 2 == 0:
			white_xforms.append(xform)
		else:
			yellow_xforms.append(xform)
		total += 1

	if white_texture != null:
		var white_mesh := QuadMesh.new()
		white_mesh.size = FLOWER_SIZE
		white_mesh.material = _flower_material(white_texture)
		_add_transform_multimesh("FlowersWhite", white_mesh, white_xforms, false)
	if yellow_texture != null:
		var yellow_mesh := QuadMesh.new()
		yellow_mesh.size = FLOWER_SIZE
		yellow_mesh.material = _flower_material(yellow_texture)
		_add_transform_multimesh("FlowersYellow", yellow_mesh, yellow_xforms, false)
	return total

func _flower_material(texture: Texture2D) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material

## Seeded scatter: `corridor_ratio` of the attempts land in a band beside the
## path, the rest anywhere in the area. Every attempt respects the path,
## player-start, NPC and exit keep-out radii plus the existing prop spacing.
## `inner`/`outer` override the corridor band (details hug the path more closely).
func _find_prop_spot(spacing: float, corridor_ratio: float, inner: float = CORRIDOR_INNER, outer: float = CORRIDOR_OUTER, path_extra: float = 0.0, view_clear: bool = false) -> Vector2:
	var margin := _half_size - PROP_EDGE_MARGIN
	var path_clear := _path_width + PATH_PROP_CLEAR + path_extra
	var player_sq := PROP_AVOID_PLAYER * PROP_AVOID_PLAYER
	var npc_sq := PROP_AVOID_NPC * PROP_AVOID_NPC
	var exit_sq := PROP_AVOID_EXIT * PROP_AVOID_EXIT
	var has_npc := _has_npc()
	var use_corridor := not _path_samples.is_empty()

	for attempt in 96:
		var spot := Vector2.ZERO
		if use_corridor and _rng.randf() < corridor_ratio:
			var anchor := _path_samples[_rng.randi_range(0, _path_samples.size() - 1)]
			var angle := _rng.randf() * TAU
			var radius := sqrt(_rng.randf_range(inner * inner, outer * outer))
			spot = anchor + Vector2(cos(angle), sin(angle)) * radius
		else:
			spot = Vector2(_rng.randf_range(-margin, margin), _rng.randf_range(-margin, margin))

		if absf(spot.x) > margin or absf(spot.y) > margin:
			continue
		if not _path_is_clear(spot, path_clear):
			continue
		if spot.distance_squared_to(_player_start_xz) < player_sq:
			continue
		if has_npc and spot.distance_squared_to(_npc_xz) < npc_sq:
			continue
		if spot.distance_squared_to(_exit_xz) < exit_sq:
			continue
		if view_clear and not _tree_view_clear(spot):
			continue
		if _in_pond(spot, 0.6):
			continue
		if _in_creek(spot, 1.35):
			continue
		if _puzzle_enabled and spot.distance_to(_puzzle_center) < 5.2:
			continue
		if not _is_free(spot, spacing):
			continue
		return spot
	return SPOT_NONE

## The camera looks down the -Z axis, so a tall tree on the +Z side of the path
## stands between the camera and the hero. Keep that band clear of trees.
func _tree_view_clear(spot: Vector2) -> bool:
	if _path_samples.is_empty():
		return true
	if _has_npc() and spot.distance_squared_to(_npc_xz) < 64.0:
		return false
	var nearest := _nearest_path_point(spot)
	var delta := spot - nearest
	if delta.length() < 5.0:
		return false
	# Trees strictly on the camera side of the path (+Z) within 12 m would sit
	# between the camera and the hero. Side trees (delta.y ~ 0) are safe: they
	# frame the shot at the left/right edge instead of covering the hero.
	if delta.y > 2.0 and delta.length() < 12.0:
		return false
	return true

func _nearest_path_point(pos: Vector2) -> Vector2:
	var best := pos
	var best_distance := INF
	for i in range(1, _path_samples.size()):
		var a := _path_samples[i - 1]
		var b := _path_samples[i]
		var ab := b - a
		var length_sq := ab.length_squared()
		var t := 0.0 if length_sq < 1e-8 else clampf((pos - a).dot(ab) / length_sq, 0.0, 1.0)
		var point := a + ab * t
		var distance := pos.distance_squared_to(point)
		if distance < best_distance:
			best_distance = distance
			best = point
	return best

## Nearest path point + distance, used to grade the walkable trail.
func _nearest_path_info(pos: Vector2) -> Dictionary:
	var count := _path_samples.size()
	if count == 0:
		return {"distance": INF, "point": pos}
	if count == 1:
		return {"distance": pos.distance_to(_path_samples[0]), "point": _path_samples[0]}
	var best_distance := INF
	var best_point := _path_samples[0]
	var previous := _path_samples[0]
	for i in range(1, count):
		var current := _path_samples[i]
		var ab := current - previous
		var length_sq := ab.length_squared()
		var t := 0.0 if length_sq < 1e-8 else clampf((pos - previous).dot(ab) / length_sq, 0.0, 1.0)
		var point := previous + ab * t
		var distance := pos.distance_squared_to(point)
		if distance < best_distance:
			best_distance = distance
			best_point = point
		previous = current
	return {"distance": sqrt(best_distance), "point": best_point}

func _is_free(pos: Vector2, clearance: float) -> bool:
	var clearance_sq := clearance * clearance
	for other in _occupied:
		if pos.distance_squared_to(other) < clearance_sq:
			return false
	return true

# =============================================================================
# EXIT AREA + LANDMARK
# =============================================================================

func _build_exit() -> void:
	var area := Area3D.new()
	area.name = "ExitArea"
	var exit_ground := _terrain_height_at(_exit_position.x, _exit_position.z)
	area.position = Vector3(_exit_position.x, exit_ground, _exit_position.z)
	area.monitoring = true
	area.monitorable = false
	area.collision_layer = 0
	area.collision_mask = PLAYER_LAYER
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = EXIT_RADIUS
	shape.shape = sphere
	shape.position = Vector3(0.0, 1.0, 0.0)
	area.add_child(shape)
	area.body_entered.connect(_on_exit_body_entered)
	add_child(area)

	_build_exit_landmark()

## Two stone pillars flanking the path plus a ring of glowing stones, so the
## exit is readable from the spawn point even in the night segment.
func _build_exit_landmark() -> void:
	var tangent := Vector2(0.0, -1.0)
	var samples := _path_samples
	if samples.size() >= 2:
		var last := samples[samples.size() - 1]
		var previous := samples[samples.size() - 2]
		if last.distance_squared_to(previous) > 1e-8:
			tangent = (last - previous).normalized()
	var side := Vector2(-tangent.y, tangent.x)
	var centre := _exit_xz
	var ground_y := _terrain_height_at(centre.x, centre.y)

	var stone := _flat_material(STONE_COLOR)
	var cool_stone := _flat_material(STONE_COLOR_COOL)
	var glow := _glow_material(EXIT_GLOW_COLOR, EXIT_GLOW_ENERGY)
	var pillar_offset := _path_width * 0.5 + 1.4

	for side_index in 2:
		var factor := 1.0 if side_index == 0 else -1.0
		var base := centre + side * pillar_offset * factor
		var pillar := CylinderMesh.new()
		pillar.top_radius = 0.34
		pillar.bottom_radius = 0.46
		pillar.height = 3.0
		pillar.radial_segments = 8
		_add_mesh_instance("ExitPillar_%d" % side_index, pillar, stone, Vector3(base.x, ground_y + 1.5, base.y), 0.0, true)

		var cap := BoxMesh.new()
		cap.size = Vector3(1.05, 0.26, 1.05)
		_add_mesh_instance("ExitCap_%d" % side_index, cap, cool_stone, Vector3(base.x, ground_y + 3.12, base.y), _rng.randf() * TAU, true)

		var lantern := SphereMesh.new()
		lantern.radius = 0.19
		lantern.height = 0.38
		lantern.radial_segments = 8
		lantern.rings = 4
		_add_mesh_instance("ExitLantern_%d" % side_index, lantern, glow, Vector3(base.x, ground_y + 3.42, base.y), 0.0, false)

		_add_cylinder_collision(base, 0.46, 3.0, ground_y)

	for i in EXIT_RING_STONES:
		var angle := TAU * float(i) / float(EXIT_RING_STONES) + 0.2
		var spot := centre + Vector2(cos(angle), sin(angle)) * EXIT_RING_RADIUS
		var stone_mesh := BoxMesh.new()
		stone_mesh.size = Vector3(
			_rng.randf_range(0.26, 0.40),
			_rng.randf_range(0.24, 0.42),
			_rng.randf_range(0.26, 0.40))
		_add_mesh_instance("ExitStone_%d" % i, stone_mesh, glow,
			Vector3(spot.x, ground_y + _rng.randf_range(0.12, 0.20), spot.y),
			_rng.randf() * TAU, false)

	var light := OmniLight3D.new()
	light.name = "ExitLight"
	light.position = Vector3(centre.x, ground_y + 1.6, centre.y)
	light.light_color = EXIT_GLOW_COLOR
	light.light_energy = 1.2
	light.omni_range = 8.0
	light.shadow_enabled = false
	add_child(light)

func _on_exit_body_entered(body: Node3D) -> void:
	if _exit_used:
		return
	if body == null:
		return
	if not body.is_in_group("player"):
		return
	_exit_used = true
	exit_reached.emit()

# =============================================================================
# KENNEY GLB HELPERS (verbatim behaviour from the verified world.gd)
# =============================================================================

# Loads a GLB into { "parts": [{mesh, transform, material}], "aabb": AABB }.
# Returns an empty Dictionary when the model cannot be loaded.
func _load_model(path: String) -> Dictionary:
	if not ResourceLoader.exists(path):
		push_warning("[segment] model missing: " + path)
		return {}
	var packed := load(path) as PackedScene
	if packed == null:
		push_warning("[segment] not a PackedScene: " + path)
		return {}
	var root := packed.instantiate()
	if root == null:
		return {}
	var parts: Array = []
	_collect_mesh_parts(root, Transform3D.IDENTITY, parts)
	root.free()
	if parts.is_empty():
		push_warning("[segment] no meshes in: " + path)
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
		multimesh.use_colors = true
		multimesh.instance_count = entries.size()
		for i in entries.size():
			var entry: Dictionary = entries[i]
			var pos: Vector2 = entry["pos"]
			var target_height: float = entry["height"]
			var ground_y: float = entry.get("ground_y", _terrain_height_at(pos.x, pos.y))
			var uniform_scale := (target_height / reference) * _rng.randf_range(0.92, 1.10)
			var yaw_value = entry.get("yaw")
			var yaw: float = float(yaw_value) if yaw_value != null else _rng.randf() * TAU
			var basis := Basis(Vector3.UP, yaw).scaled(
				Vector3(uniform_scale, uniform_scale, uniform_scale))
			# Drop the model so its lowest point sits exactly on the terrain.
			var origin := Vector3(pos.x, ground_y - bounds.position.y * uniform_scale, pos.y)
			multimesh.set_instance_transform(i, Transform3D(basis, origin) * relative)
			# Subtle per-instance hue/brightness drift so even the same GLB reads
			# as a different tree, the way a real forest varies.
			multimesh.set_instance_color(i, Color(
				_rng.randf_range(0.88, 1.05),
				_rng.randf_range(0.90, 1.07),
				_rng.randf_range(0.82, 1.02),
				1.0))
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
		col.r * _prop_tint.r,
		col.g * _prop_tint.g,
		col.b * _prop_tint.b,
		col.a)
	# glTF's default metallicFactor is 1.0, so untextured Kenney materials import
	# as fully metallic and mirror the sky (the "cyan trees" bug). Stylised matte
	# props: no metal, full roughness.
	copy.vertex_color_use_as_albedo = true
	copy.metallic = 0.0
	copy.metallic_specular = 0.2
	copy.roughness = 1.0
	return copy

# =============================================================================
# GENERIC HELPERS
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

func _add_mesh_instance(node_name: String, mesh: Mesh, surface_material: Material, world_position: Vector3, yaw: float, cast_shadow: bool, parent: Node3D = null) -> void:
	mesh.material = surface_material
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = world_position
	instance.rotation.y = yaw
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if parent != null:
		parent.add_child(instance)
	else:
		add_child(instance)

func _flat_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	material.metallic = 0.0
	return material

func _glow_material(color: Color, energy: float) -> StandardMaterial3D:
	var material := _flat_material(color)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material

func _load_texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	var resource: Resource = load(path)
	if resource is Texture2D:
		return resource as Texture2D
	return null

func _load_shader(path: String) -> Shader:
	if not ResourceLoader.exists(path):
		push_warning("[segment] shader missing: " + path)
		return null
	var resource: Resource = load(path)
	if resource is Shader:
		return resource as Shader
	push_warning("[segment] not a shader: " + path)
	return null

# =============================================================================
# COLLISION HELPERS (props are static, physics layer 1 = World)
# =============================================================================

func _add_cylinder_collision(pos: Vector2, radius: float, height: float, base_y: float = 0.0) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	body.position = Vector3(pos.x, base_y, pos.y)
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = maxf(radius, 0.15)
	cylinder.height = maxf(height, 1.0)
	shape.shape = cylinder
	shape.position = Vector3(0.0, cylinder.height * 0.5, 0.0)
	body.add_child(shape)
	add_child(body)

func _add_box_collision(pos: Vector2, size: Vector3, yaw: float, base_y: float = 0.0) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	body.position = Vector3(pos.x, base_y, pos.y)
	body.rotation.y = yaw
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(maxf(size.x, 0.2), maxf(size.y, 0.2), maxf(size.z, 0.2))
	shape.shape = box
	shape.position = Vector3(0.0, box.size.y * 0.5, 0.0)
	body.add_child(shape)
	add_child(body)

func _add_sphere_collision(pos: Vector2, radius: float, center_height: float, base_y: float = 0.0) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = WORLD_LAYER
	body.collision_mask = 0
	body.position = Vector3(pos.x, base_y, pos.y)
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = maxf(radius, 0.15)
	shape.shape = sphere
	shape.position = Vector3(0.0, maxf(center_height, sphere.radius * 0.5), 0.0)
	body.add_child(shape)
	add_child(body)

# =============================================================================
# MATH HELPERS
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
