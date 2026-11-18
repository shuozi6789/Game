extends Node3D
## Opening "vision": a playable, higher-resolution Ghibli-ish 3D prologue.
## The player runs down a grass slope toward a red-roofed village, a white
## windmill and a mountain in the clouds while the sky turns to sunset.
## Walking to the windmill and pressing E starts the 11-segment walk.

const FONT_PATH := "res://assets/fonts/NotoSansSC-Subset.ttf"
const KIT_DIR := "res://assets/free/kenney_nature_kit/models/"
const GRASS_SHADER := "res://shaders/world/grass.gdshader"
const BLADE_TEXTURE := "res://assets/generated/grass_blade.png"
const GROUND_TEXTURE := "res://assets/generated/grass_ground.png"
const WORLD_HALF := 84.0
const WORLD_RES := 141
const PLAYER_START := Vector3(0.0, 0.0, 58.0)
const VILLAGE_CENTER := Vector2(0.0, -22.0)
const WINDMILL_POS := Vector2(36.0, -28.0)
const MOUNTAIN_POS := Vector2(0.0, -150.0)

const SKY_PATH := "res://shaders/vision/sky.gdshader"
const HOUSE_SCENE_PATH := "res://scenes/vision/carpenter_house.tscn"

var _player: CharacterBody3D
var _camera: Camera3D
var _yaw: float = 0.0
var _pitch: float = -0.16
var _first_person: bool = false
var _mouse_captured: bool = true
var _character_mode: int = 0
var _blue_person: Node3D
var _white_person: Node3D
var _blue_rig: Dictionary = {}
var _white_rig: Dictionary = {}
var _anim_time: float = 0.0
var _walk_cycle: float = 0.0
var _cape_mesh: ArrayMesh
var _cape_vertices: PackedVector3Array
var _cape_indices: PackedInt32Array
var _cape_rows: int = 8
var _cape_cols: int = 6
var _windmill_sails: Node3D
var _sails_time: float = 0.0

var _sky_material: ShaderMaterial
var _sun: DirectionalLight3D
var _environment: Environment
var _time_of_day: float = 0.0
var _time_speed: float = 1.0
var _grass_materials: Array[ShaderMaterial] = []
var _grass_player_pos := Vector3.ZERO
var _grass_player_vel := Vector3.ZERO
var _house_footprints: Array[Vector3] = []
var _clouds: Array[Sprite3D] = []
var _ui_layer: CanvasLayer
var _fade: ColorRect
var _title: Label
var _hint: Label
var _phase_label: Label
var _saved_content_scale := Vector2i(640, 360)
var _time_started := false
var _journey_prompt: Label
var _journey_started: bool = false
var _pause_active: bool = false
var _pause_panel: Control
var _visual_yaw: float = PI
var _target_yaw: float = PI
var _house_floor_y: float = 0.0
var _intro_label: Label
var _intro_backdrop: ColorRect
var _start_house: Node3D
var _house_spawn := Vector3.ZERO

func _ready() -> void:
	_saved_content_scale = get_tree().root.content_scale_size
	get_tree().root.content_scale_size = Vector2i(1280, 720)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_build_environment()
	_build_terrain()
	_build_village()
	_build_windmill()
	_build_village_details()
	_build_start_house()
	_build_grass()
	_build_mountain_and_clouds()
	_build_trees()
	_build_player()
	_build_camera()
	_build_ui()
	_update_time_of_day(0.0)
	_fade_in()

func _exit_tree() -> void:
	if get_tree() != null and get_tree().root != null:
		get_tree().root.content_scale_size = _saved_content_scale
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _fade_in() -> void:
	_fade.color = Color(0.02, 0.03, 0.04, 1.0)
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 0.0, 2.2)
	await tween.finished
	_title.modulate.a = 1.0
	_time_started = true
	if _intro_label != null:
		var intro_tween := create_tween()
		intro_tween.tween_property(_intro_label, "modulate:a", 1.0, 0.8)
		intro_tween.parallel().tween_property(_intro_backdrop, "modulate:a", 1.0, 0.8)
		intro_tween.tween_interval(4.5)
		intro_tween.tween_property(_intro_label, "modulate:a", 0.0, 1.1)
		intro_tween.parallel().tween_property(_intro_backdrop, "modulate:a", 0.0, 1.1)

# =============================================================================
# SKY / ENVIRONMENT
# =============================================================================

func _build_environment() -> void:
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	_sky_material = ShaderMaterial.new()
	_sky_material.shader = load(SKY_PATH) as Shader
	sky.sky_material = _sky_material
	_environment.sky = sky
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_environment.ambient_light_energy = 0.72
	_environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	_environment.tonemap_exposure = 1.05
	_environment.glow_enabled = true
	_environment.glow_intensity = 0.65
	_environment.glow_strength = 1.0
	_environment.glow_bloom = 0.08
	_environment.glow_hdr_threshold = 1.05
	_environment.ssao_enabled = true
	_environment.ssao_radius = 2.4
	_environment.ssao_intensity = 1.3
	_environment.ssil_enabled = true
	_environment.fog_enabled = true
	_environment.fog_light_color = Color(0.76, 0.82, 0.88)
	_environment.fog_light_energy = 0.8
	_environment.fog_density = 0.0046
	_environment.fog_sky_affect = 0.35
	_environment.volumetric_fog_enabled = true
	_environment.volumetric_fog_density = 0.008
	_environment.volumetric_fog_gi_inject = 0.4
	var world_env := WorldEnvironment.new()
	world_env.name = "VisionEnvironment"
	world_env.environment = _environment
	add_child(world_env)

	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.light_energy = 1.55
	_sun.light_color = Color(1.0, 0.93, 0.76)
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 95.0
	_sun.shadow_bias = 0.04
	add_child(_sun)

func _update_time_of_day(delta: float) -> void:
	if _time_started:
		_time_of_day = fmod(_time_of_day + delta * 0.018 * _time_speed, 1.0)
	var day := {
		"top": Color(0.14, 0.38, 0.70), "horizon": Color(0.44, 0.68, 0.84),
		"sun_col": Color(1.0, 0.93, 0.70), "cloud_dark": Color(0.52, 0.62, 0.70),
		"cloud_light": Color(1.0, 0.97, 0.84), "light": Color(1.0, 0.94, 0.78),
		"energy": 1.55, "fog": Color(0.60, 0.74, 0.84), "fog_density": 0.0035,
		"cover": 0.28, "sat": 1.08,
	}
	var gold := {
		"top": Color(0.22, 0.31, 0.50), "horizon": Color(0.98, 0.64, 0.32),
		"sun_col": Color(1.0, 0.72, 0.34), "cloud_dark": Color(0.66, 0.48, 0.50),
		"cloud_light": Color(1.0, 0.80, 0.48), "light": Color(1.0, 0.67, 0.38),
		"energy": 1.65, "fog": Color(0.85, 0.60, 0.46), "fog_density": 0.006,
		"cover": 0.38, "sat": 1.15,
	}
	var dusk := {
		"top": Color(0.15, 0.09, 0.30), "horizon": Color(0.84, 0.30, 0.48),
		"sun_col": Color(1.0, 0.40, 0.30), "cloud_dark": Color(0.30, 0.20, 0.42),
		"cloud_light": Color(0.92, 0.46, 0.62), "light": Color(0.95, 0.38, 0.32),
		"energy": 1.10, "fog": Color(0.46, 0.26, 0.38), "fog_density": 0.008,
		"cover": 0.50, "sat": 1.20,
	}
	var a: Dictionary
	var b: Dictionary
	var w: float
	if _time_of_day < 0.5:
		a = day
		b = gold
		w = smoothstep(0.0, 0.5, _time_of_day)
	else:
		a = gold
		b = dusk
		w = smoothstep(0.5, 1.0, _time_of_day)
	var top_color: Color = (a["top"] as Color).lerp(b["top"] as Color, w)
	var horizon_color: Color = (a["horizon"] as Color).lerp(b["horizon"] as Color, w)
	var sun_color: Color = (a["sun_col"] as Color).lerp(b["sun_col"] as Color, w)
	var cloud_dark: Color = (a["cloud_dark"] as Color).lerp(b["cloud_dark"] as Color, w)
	var cloud_light: Color = (a["cloud_light"] as Color).lerp(b["cloud_light"] as Color, w)
	var light_color: Color = (a["light"] as Color).lerp(b["light"] as Color, w)
	var fog_color: Color = (a["fog"] as Color).lerp(b["fog"] as Color, w)
	var energy := lerpf(float(a["energy"]), float(b["energy"]), w)
	var fog_density := lerpf(float(a["fog_density"]), float(b["fog_density"]), w)
	var cover := lerpf(float(a["cover"]), float(b["cover"]), w)
	var elevation := lerpf(0.86, 0.08, smoothstep(0.0, 1.0, _time_of_day))
	var azimuth := lerpf(-0.45, 0.55, smoothstep(0.0, 1.0, _time_of_day))
	var sun_dir := Vector3(cos(azimuth) * cos(elevation), sin(elevation), sin(azimuth) * cos(elevation)).normalized()
	_sky_material.set_shader_parameter("top_color", top_color)
	_sky_material.set_shader_parameter("horizon_color", horizon_color)
	_sky_material.set_shader_parameter("sun_color", sun_color)
	_sky_material.set_shader_parameter("cloud_dark", cloud_dark)
	_sky_material.set_shader_parameter("cloud_light", cloud_light)
	_sky_material.set_shader_parameter("sun_direction", sun_dir)
	_sky_material.set_shader_parameter("cloud_cover", cover)
	_sky_material.set_shader_parameter("cloud_scale", 2.7)
	_sun.global_transform = Transform3D(Basis.looking_at(-sun_dir, Vector3.UP), Vector3.ZERO)
	_sun.light_color = light_color
	_sun.light_energy = energy
	_environment.ambient_light_energy = lerpf(0.72, 0.52, _time_of_day)
	_environment.fog_light_color = fog_color
	_environment.fog_density = fog_density
	_environment.volumetric_fog_density = fog_density * 1.4
	_environment.adjustment_enabled = true
	_environment.adjustment_saturation = lerpf(1.06, 1.18, w)
	_environment.adjustment_contrast = lerpf(1.04, 1.10, w)
	for cloud in _clouds:
		if cloud != null:
			cloud.modulate = cloud.modulate.lerp(Color(1.0, 0.76, 0.62, 0.62), w * 0.35)
	if _phase_label != null:
		var phase_text := "晴 · 午后"
		if _time_of_day > 0.36:
			phase_text = "黄金时刻"
		if _time_of_day > 0.66:
			phase_text = "紫粉晚霞"
		_phase_label.text = phase_text

# =============================================================================
# TERRAIN
# =============================================================================

func _height(x: float, z: float) -> float:
	var h := 4.2
	h += 9.5 * smoothstep(-4.0, 68.0, z)
	h += 1.9 * sin(x * 0.060 + 1.4) * cos(z * 0.047 - 0.8)
	h += 0.75 * sin(x * 0.19 + 0.2) * sin(z * 0.16 + 2.1)
	h += 0.35 * sin(x * 0.44 - 1.1) * cos(z * 0.39 + 0.7)
	# A clear, smoothly descending sight corridor from the start meadow to the
	# village. Without this the small local knolls form a crest in front of the
	# camera and hide the whole valley.
	var corridor := 1.0 - smoothstep(12.0, 30.0, absf(x))
	if corridor > 0.001:
		var t := clampf((58.0 - z) / 80.0, 0.0, 1.0)
		var profile := lerpf(10.2, 4.0, smoothstep(0.0, 1.0, t))
		h = lerpf(h, profile, corridor * 0.88)
	# A soft, broad hill under the windmill.
	var wd := Vector2(x - WINDMILL_POS.x, z - WINDMILL_POS.y).length()
	h += 5.8 * exp(-wd * wd / 620.0)
	# Level the village terrace and the starting meadow.
	var village_d := Vector2(x - VILLAGE_CENTER.x, z - VILLAGE_CENTER.y).length()
	if village_d < 30.0:
		h = lerpf(4.0, h, smoothstep(10.0, 30.0, village_d))
	var start_d := Vector2(x - PLAYER_START.x, z - PLAYER_START.z).length()
	if start_d < 9.0:
		h = lerpf(10.2, h, smoothstep(3.0, 9.0, start_d))
	# The terrain dives away beyond the last meadow, hiding the map edge.
	if z < -54.0:
		h -= smoothstep(-54.0, -84.0, z) * 9.0
	return h

func _build_terrain() -> void:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var heights := PackedFloat32Array()
	heights.resize((WORLD_RES + 1) * (WORLD_RES + 1))
	var step := (WORLD_HALF * 2.0) / float(WORLD_RES)
	for z in WORLD_RES + 1:
		for x in WORLD_RES + 1:
			var wx := -WORLD_HALF + float(x) * step
			var wz := -WORLD_HALF + float(z) * step
			var h := _height(wx, wz)
			heights[z * (WORLD_RES + 1) + x] = h
			verts.append(Vector3(wx, h, wz))
			uvs.append(Vector2(wx / 9.0, wz / 9.0))
			var h_l := _height(wx - step, wz)
			var h_r := _height(wx + step, wz)
			var h_d := _height(wx, wz - step)
			var h_u := _height(wx, wz + step)
			normals.append(Vector3(h_l - h_r, 2.0 * step, h_d - h_u).normalized())
	for z in WORLD_RES:
		for x in WORLD_RES:
			var i := z * (WORLD_RES + 1) + x
			var a := i
			var b := i + 1
			var c := i + WORLD_RES + 1
			var d := c + 1
			indices.append_array([a, c, b, b, c, d])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.albedo_texture = load(GROUND_TEXTURE) as Texture2D
	material.albedo_color = Color(0.66, 0.78, 0.52)
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.uv1_scale = Vector3(1.0, 1.0, 1.0)
	mesh.surface_set_material(0, material)
	var terrain := MeshInstance3D.new()
	terrain.name = "ValleyTerrain"
	terrain.mesh = mesh
	terrain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(terrain)
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	var shape := CollisionShape3D.new()
	var faces := PackedVector3Array()
	for index in indices:
		faces.append(verts[index])
	var concave := ConcavePolygonShape3D.new()
	concave.set_faces(faces)
	concave.backface_collision = true
	shape.shape = concave
	body.add_child(shape)
	add_child(body)
	# A distant "sea" of fog-coloured ground beyond the playable meadow.
	var far := PlaneMesh.new()
	far.size = Vector2(500.0, 500.0)
	var far_mesh := MeshInstance3D.new()
	far_mesh.mesh = far
	far_mesh.position = Vector3(0.0, -7.0, -120.0)
	var far_mat := StandardMaterial3D.new()
	far_mat.albedo_color = Color(0.32, 0.40, 0.38)
	far_mat.roughness = 1.0
	far_mesh.material_override = far_mat
	far_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(far_mesh)
	_house_footprints.clear()

# =============================================================================
# GRASS
# =============================================================================

func _build_start_house() -> void:
	# The house is its own scene so the interior can be edited independently of
	# the grass-slope world.
	var packed := load(HOUSE_SCENE_PATH) as PackedScene
	if packed == null:
		_house_floor_y = _height(0.0, PLAYER_START.z) + 0.22
		_house_spawn = Vector3(PLAYER_START.x, _house_floor_y + 0.06, PLAYER_START.z)
		return
	_start_house = packed.instantiate() as Node3D
	var base_y := _height(0.0, PLAYER_START.z) + 0.22
	_start_house.position = Vector3(0.0, base_y, PLAYER_START.z)
	add_child(_start_house)
	_house_floor_y = base_y
	var local_spawn: Vector3 = _start_house.call("get_spawn_position")
	_house_spawn = _start_house.position + local_spawn
	_house_footprints.append(Vector3(0.0, float(_start_house.call("get_footprint_radius")), PLAYER_START.z))

func _build_grass() -> void:
	var shader := load(GRASS_SHADER) as Shader
	if shader == null:
		return
	var blade := QuadMesh.new()
	blade.size = Vector2(0.19, 0.52)
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("base_color", Color(0.08, 0.20, 0.05))
	material.set_shader_parameter("tip_color", Color(0.47, 0.72, 0.24))
	material.set_shader_parameter("dry_color", Color(0.58, 0.52, 0.25))
	material.set_shader_parameter("dry_mix", 0.10)
	material.set_shader_parameter("blade_height", 0.52)
	material.set_shader_parameter("wind_strength", 0.085)
	material.set_shader_parameter("wind_speed", 1.5)
	material.set_shader_parameter("blade_tex", load(BLADE_TEXTURE))
	material.set_shader_parameter("player_pos", _grass_player_pos)
	_grass_materials.append(material)
	blade.material = material
	var transforms: Array[Transform3D] = []
	var customs := PackedColorArray()
	var rng := RandomNumberGenerator.new()
	rng.seed = 94721
	var spacing := 0.34
	var half := 78.0
	var x := -half
	while x <= half:
		var z := -half
		while z <= half:
			var p := Vector2(x + rng.randf_range(-0.20, 0.20), z + rng.randf_range(-0.20, 0.20))
			if _grass_allowed(p):
				var density := 0.68 + 0.28 * sin(p.x * 0.15) * sin(p.y * 0.12)
				if rng.randf() <= density:
					var y := _height(p.x, p.y)
					var yaw := rng.randf() * TAU
					var scale_x := rng.randf_range(0.55, 1.15)
					var scale_y := rng.randf_range(0.65, 1.35)
					var basis := Basis(Vector3.UP, yaw).scaled(Vector3(scale_x, scale_y, scale_x))
					transforms.append(Transform3D(basis, Vector3(p.x, y + 0.26 * scale_y, p.y)))
					customs.append(Color(rng.randf(), rng.randf(), 0.0, 1.0))
					# Every blade gets a randomised crossing blade. It makes the
					# field read as woven grass rather than a row of vertical cards.
					var cross_yaw := yaw + PI * 0.5 + rng.randf_range(-0.24, 0.24)
					var cross_basis := Basis(Vector3.UP, cross_yaw).scaled(
						Vector3(scale_x * 0.72, scale_y * 0.92, scale_x * 0.72))
					transforms.append(Transform3D(cross_basis, Vector3(p.x, y + 0.24 * scale_y, p.y)))
					customs.append(Color(rng.randf(), rng.randf(), 0.0, 1.0))
					if transforms.size() >= 260000:
						break
			z += spacing
		if transforms.size() >= 240000:
			break
		x += spacing
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = blade
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		mm.set_instance_color(i, customs[i])
		mm.set_instance_custom_data(i, customs[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = "VisionGrass"
	instance.multimesh = mm
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)

func _grass_allowed(p: Vector2) -> bool:
	if absf(p.x) > 79.0 or absf(p.y) > 79.0:
		return false
	if p.y < -52.0:
		return false
	for footprint in _house_footprints:
		if p.distance_to(Vector2(footprint.x, footprint.z)) < footprint.y:
			return false
	if p.distance_to(WINDMILL_POS) < 5.5:
		return false
	return true

# =============================================================================
# VILLAGE
# =============================================================================

func _build_village() -> void:
	var specs := [
		{"pos": Vector2(-14.0, -15.0), "rot": -8.0, "w": 5.2, "d": 4.2, "h": 3.0, "roof": Color(0.62, 0.20, 0.15)},
		{"pos": Vector2(-6.0, -24.0), "rot": 4.0, "w": 4.2, "d": 3.6, "h": 2.6, "roof": Color(0.70, 0.24, 0.17)},
		{"pos": Vector2(6.5, -17.0), "rot": -3.0, "w": 5.0, "d": 4.0, "h": 2.8, "roof": Color(0.58, 0.18, 0.14)},
		{"pos": Vector2(14.0, -27.0), "rot": 12.0, "w": 4.6, "d": 3.8, "h": 2.9, "roof": Color(0.68, 0.22, 0.16)},
		{"pos": Vector2(-16.0, -30.0), "rot": 9.0, "w": 4.8, "d": 4.0, "h": 2.7, "roof": Color(0.64, 0.21, 0.15)},
		{"pos": Vector2(0.0, -33.0), "rot": 0.0, "w": 6.0, "d": 4.4, "h": 3.2, "roof": Color(0.56, 0.17, 0.13)},
		{"pos": Vector2(-8.0, -38.0), "rot": -6.0, "w": 4.0, "d": 3.4, "h": 2.5, "roof": Color(0.70, 0.25, 0.18)},
		{"pos": Vector2(20.0, -38.0), "rot": 15.0, "w": 4.6, "d": 3.6, "h": 2.8, "roof": Color(0.60, 0.19, 0.14)},
	]
	for spec in specs:
		_build_house(spec)
	# A little village green / well.
	var well_y := _height(0.0, -25.0)
	var well := Node3D.new()
	well.position = Vector3(0.0, well_y, -25.0)
	add_child(well)
	_add_cylinder(well, 0.85, 0.95, 0.55, Vector3(0.0, 0.28, 0.0), Color(0.48, 0.47, 0.42), 10)
	_add_cylinder(well, 0.64, 0.64, 0.05, Vector3(0.0, 0.56, 0.0), Color(0.10, 0.13, 0.13), 10)
	for i in 3:
		_add_box(well, Vector3(0.09, 1.5, 0.09), Vector3(-0.62 + float(i) * 0.62, 1.05, -0.16), Color(0.35, 0.25, 0.16))
	_add_box(well, Vector3(1.55, 0.09, 0.09), Vector3(0.0, 1.72, -0.16), Color(0.32, 0.23, 0.15))

func _build_house(spec: Dictionary) -> void:
	var pos: Vector2 = spec["pos"]
	var y := 0.0
	var w := float(spec["w"])
	var d := float(spec["d"])
	var h := float(spec["h"])
	var rot := deg_to_rad(float(spec["rot"]))
	var corners := [
		pos + Vector2(-w * 0.5, -d * 0.5), pos + Vector2(w * 0.5, -d * 0.5),
		pos + Vector2(-w * 0.5, d * 0.5), pos + Vector2(w * 0.5, d * 0.5),
	]
	y = 0.0
	for c in corners:
		y += _height(c.x, c.y)
	y /= 4.0
	var house := Node3D.new()
	house.position = Vector3(pos.x, y, pos.y)
	house.rotation.y = rot
	add_child(house)
	var wall_colour := Color(0.86, 0.78, 0.62)
	var timber := Color(0.28, 0.20, 0.14)
	var roof_colour: Color = spec["roof"]
	_add_box(house, Vector3(w, h, d), Vector3(0.0, h * 0.5, 0.0), wall_colour)
	# half-timber strips
	for i in 4:
		var sx := -w * 0.5 + 0.18 + float(i) * (w - 0.36) / 3.0
		_add_box(house, Vector3(0.10, h, 0.06), Vector3(sx, h * 0.5, d * 0.5 + 0.02), timber)
	_add_box(house, Vector3(w, 0.10, 0.06), Vector3(0.0, h * 0.72, d * 0.5 + 0.02), timber)
	# pitched roof (two sloped panels; no imported roofer needed)
	var roof_h := 1.5
	var roof_len := d + 0.7
	for side in [-1.0, 1.0]:
		var slope := 0.62
		var panel := BoxMesh.new()
		panel.size = Vector3(w * 0.62, 0.10, roof_len)
		var node := MeshInstance3D.new()
		node.mesh = panel
		node.material_override = _mat(roof_colour, 0.92)
		var angle := atan2(roof_h, w * 0.5)
		node.position = Vector3(side * w * 0.25, h + roof_h * 0.5, 0.0)
		node.rotation.z = -side * angle
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		house.add_child(node)
	# gable fill
	var gable := BoxMesh.new()
	gable.size = Vector3(w * 0.92, roof_h * 0.5, d * 0.02)
	_add_mesh(house, gable, Vector3(0.0, h + roof_h * 0.25, d * 0.5), roof_colour)
	# door
	_add_box(house, Vector3(0.72, 1.28, 0.08), Vector3(0.0, 0.64, d * 0.5 + 0.05), Color(0.30, 0.20, 0.13))
	# windows with warm light
	for sx in [-w * 0.30, w * 0.30]:
		_add_box(house, Vector3(0.58, 0.62, 0.06), Vector3(sx, h * 0.54, d * 0.5 + 0.045), Color(0.14, 0.17, 0.18))
		_add_box(house, Vector3(0.40, 0.44, 0.03), Vector3(sx, h * 0.54, d * 0.5 + 0.08), Color(0.98, 0.76, 0.38), true)
		_add_box(house, Vector3(0.03, 0.62, 0.04), Vector3(sx, h * 0.54, d * 0.5 + 0.09), Color(0.24, 0.18, 0.12))
	# chimney
	_add_box(house, Vector3(0.46, 1.1, 0.46), Vector3(w * 0.28, h + 1.2, -d * 0.18), Color(0.44, 0.34, 0.26))
	_add_box(house, Vector3(0.58, 0.09, 0.58), Vector3(w * 0.28, h + 1.76, -d * 0.18), Color(0.28, 0.22, 0.17))
	# flower boxes under the windows
	for sx in [-w * 0.30, w * 0.30]:
		_add_box(house, Vector3(0.62, 0.14, 0.20), Vector3(sx, h * 0.33, d * 0.5 + 0.13), Color(0.38, 0.23, 0.14))
		for i in 3:
			_add_box(house, Vector3(0.10, 0.12, 0.10), Vector3(sx - 0.20 + float(i) * 0.20, h * 0.33 + 0.12, d * 0.5 + 0.13), Color(0.86, 0.34, 0.40))
	# collision + grass-free footprint
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(w, h + 2.0, d)
	shape.shape = box
	shape.position.y = (h + 2.0) * 0.5
	body.add_child(shape)
	house.add_child(body)
	_house_footprints.append(Vector3(pos.x, maxf(w, d) * 0.72, pos.y))

func _build_village_details() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4407
	# stepping-stone path down the slope toward the village
	for i in 26:
		var z := 52.0 - float(i) * 2.15
		var x := sin(float(i) * 0.22) * 1.2
		var y := _height(x, z) + 0.055
		var stone := _add_cylinder(self, 0.42, 0.50, 0.12, Vector3(x, y, z), Color(0.61, 0.56, 0.46), 7)
		stone.scale = Vector3(rng.randf_range(0.8, 1.25), 1.0, rng.randf_range(0.7, 1.15))
	# low split-rail fences at the field edge
	for row in 2:
		var z := -6.0 - float(row) * 0.65
		for i in 13:
			var x := -18.0 + float(i) * 3.0
			var y := _height(x, z)
			_add_box(self, Vector3(0.12, 0.55, 0.12), Vector3(x, y + 0.27, z), Color(0.44, 0.30, 0.19))
			if i < 12:
				_add_box(self, Vector3(3.0, 0.07, 0.07), Vector3(x + 1.5, y + 0.38, z), Color(0.52, 0.36, 0.22))
				_add_box(self, Vector3(3.0, 0.06, 0.06), Vector3(x + 1.5, y + 0.18, z), Color(0.47, 0.32, 0.20))
	# flowers and small shrubs around the houses
	for i in 48:
		var angle := rng.randf() * TAU
		var radius := rng.randf_range(7.0, 22.0)
		var p := Vector3(cos(angle) * radius, 0.0, -16.0 + sin(angle) * radius * 0.65)
		var y := _height(p.x, p.z)
		if Vector2(p.x, p.z).distance_to(WINDMILL_POS) < 6.0:
			continue
		var colour: Color = [Color(0.92, 0.62, 0.70), Color(0.94, 0.82, 0.42), Color(0.78, 0.56, 0.82), Color(0.94, 0.94, 0.82)][i % 4]
		_add_cylinder(self, 0.012, 0.018, 0.22, Vector3(p.x, y + 0.11, p.z), Color(0.34, 0.44, 0.20), 5)
		_add_sphere(self, 0.075, Vector3(p.x, y + 0.25, p.z), colour)
	# well with a little roof
	var well_pos := Vector3(12.0, 0.0, -8.0)
	well_pos.y = _height(well_pos.x, well_pos.z)
	_add_cylinder(self, 0.85, 0.95, 0.70, well_pos + Vector3(0.0, 0.35, 0.0), Color(0.48, 0.44, 0.40), 12)
	_add_cylinder(self, 0.60, 0.60, 0.55, well_pos + Vector3(0.0, 0.72, 0.0), Color(0.10, 0.14, 0.15), 12)
	for side in [-1.0, 1.0]:
		_add_box(self, Vector3(0.12, 1.6, 0.12), well_pos + Vector3(float(side) * 0.8, 1.35, 0.0), Color(0.40, 0.28, 0.18))
	_add_box(self, Vector3(2.0, 0.10, 1.2), well_pos + Vector3(0.0, 2.18, 0.0), Color(0.56, 0.24, 0.18))
	# windmill signpost
	var sign_pos := Vector3(23.0, 0.0, -13.0)
	sign_pos.y = _height(sign_pos.x, sign_pos.z)
	_add_box(self, Vector3(0.12, 1.8, 0.12), sign_pos + Vector3(0.0, 0.9, 0.0), Color(0.37, 0.26, 0.16))
	_add_box(self, Vector3(1.3, 0.38, 0.08), sign_pos + Vector3(0.55, 1.55, 0.0), Color(0.67, 0.48, 0.28))
	_add_box(self, Vector3(0.85, 0.055, 0.03), sign_pos + Vector3(0.55, 1.60, 0.05), Color(0.88, 0.78, 0.56))
	# small cultivated field rows near the village
	for row in 4:
		var z2 := -37.0 - float(row) * 1.2
		for i in 9:
			var x2 := -14.0 + float(i) * 2.4
			var y2 := _height(x2, z2)
			_add_box(self, Vector3(1.7, 0.10, 0.30), Vector3(x2, y2 + 0.05, z2), Color(0.38, 0.28, 0.17))
			for k in 3:
				_add_cylinder(self, 0.018, 0.030, 0.30, Vector3(x2 - 0.55 + float(k) * 0.55, y2 + 0.22, z2), Color(0.34, 0.50, 0.22), 5)

func _build_windmill() -> void:
	var y := _height(WINDMILL_POS.x, WINDMILL_POS.y)
	var mill := Node3D.new()
	mill.name = "WhiteWindmill"
	mill.position = Vector3(WINDMILL_POS.x, y, WINDMILL_POS.y)
	add_child(mill)
	var white := Color(0.92, 0.89, 0.79)
	var trim := Color(0.35, 0.27, 0.20)
	var roof := Color(0.34, 0.28, 0.24)
	_add_cylinder(mill, 0.78, 1.35, 7.4, Vector3(0.0, 3.7, 0.0), white, 12)
	_add_cylinder(mill, 1.48, 1.48, 0.28, Vector3(0.0, 7.42, 0.0), trim, 12)
	_add_cylinder(mill, 0.10, 1.62, 1.55, Vector3(0.0, 8.30, 0.0), roof, 12)
	_add_cylinder(mill, 0.80, 0.80, 0.30, Vector3(0.0, 7.75, 0.0), trim, 12)
	# door and windows
	_add_box(mill, Vector3(1.0, 1.9, 0.12), Vector3(0.0, 0.95, 1.28), Color(0.27, 0.19, 0.13))
	for wy in [2.7, 4.9]:
		for side in [-1.0, 1.0]:
			_add_box(mill, Vector3(0.46, 0.62, 0.10), Vector3(side * 0.82, wy, 0.86), Color(0.14, 0.18, 0.20))
			_add_box(mill, Vector3(0.32, 0.46, 0.04), Vector3(side * 0.82, wy, 0.93), Color(0.98, 0.72, 0.33), true)
	# gallery
	_add_cylinder(mill, 2.0, 2.0, 0.14, Vector3(0.0, 2.65, 0.0), trim, 16)
	for i in 16:
		var a := TAU * float(i) / 16.0
		_add_box(mill, Vector3(0.06, 0.42, 0.06), Vector3(cos(a) * 1.88, 2.86, sin(a) * 1.88), trim)
	# sails
	_windmill_sails = Node3D.new()
	_windmill_sails.position = Vector3(0.0, 5.4, 1.55)
	mill.add_child(_windmill_sails)
	for arm in 4:
		var pivot := Node3D.new()
		pivot.rotation.z = float(arm) * PI * 0.5
		_windmill_sails.add_child(pivot)
		_add_box(pivot, Vector3(0.16, 5.4, 0.12), Vector3(0.0, 2.7, 0.0), trim)
		for k in 4:
			_add_box(pivot, Vector3(1.25, 0.05, 0.06), Vector3(0.62, 0.9 + float(k) * 1.25, 0.02), trim)
		for k in 4:
			_add_box(pivot, Vector3(0.04, 1.15, 0.06), Vector3(0.06 + float(k) * 0.31, 1.48 + float(k) * 1.25, 0.02), trim)
		for k in 4:
			_add_box(pivot, Vector3(1.10, 1.03, 0.035), Vector3(0.64, 1.47 + float(k) * 1.25, 0.01), Color(0.90, 0.85, 0.72))
		_add_box(pivot, Vector3(0.04, 5.1, 0.04), Vector3(0.0, 2.7, 0.06), white)
	# collision
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 1.4
	cyl.height = 8.0
	shape.shape = cyl
	shape.position.y = 4.0
	body.add_child(shape)
	mill.add_child(body)
	_house_footprints.append(Vector3(WINDMILL_POS.x, 3.2, WINDMILL_POS.y))

# =============================================================================
# MOUNTAIN / CLOUDS / TREES
# =============================================================================

func _build_mountain_and_clouds() -> void:
	var base_y := -9.0
	var rings := 8
	var segments := 18
	var verts := PackedVector3Array()
	var indices := PackedInt32Array()
	var colors := PackedColorArray()
	var normals := PackedVector3Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 913
	for ring in rings + 1:
		var t := float(ring) / float(rings)
		var radius := lerpf(42.0, 2.0, pow(t, 0.82))
		var y := base_y + pow(t, 1.25) * 64.0
		for s in segments:
			var a := TAU * float(s) / float(segments)
			var wobble := 1.0 + 0.16 * sin(a * 3.0 + float(ring) * 0.8)
			verts.append(Vector3(cos(a) * radius * wobble, y, sin(a) * radius * wobble))
			normals.append(Vector3(cos(a) * 0.62, 0.78, sin(a) * 0.62).normalized())
			if t > 0.76:
				colors.append(Color(0.82, 0.84, 0.86))
			else:
				colors.append(Color(0.28, 0.33, 0.36).lerp(Color(0.44, 0.48, 0.48), rng.randf()))
	for ring in rings:
		for s in segments:
			var a := ring * segments + s
			var b := ring * segments + (s + 1) % segments
			var c := a + segments
			var d := b + segments
			indices.append_array([a, b, c, b, d, c])
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mesh.surface_set_material(0, mat)
	var mountain := MeshInstance3D.new()
	mountain.name = "CloudPeak"
	mountain.mesh = mesh
	mountain.position = Vector3(MOUNTAIN_POS.x, 0.0, MOUNTAIN_POS.y)
	mountain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mountain)
	# Layered foothill ridges so the horizon reads as a mountain range rather
	# than one pale cone.
	var ridge_specs := [
		{"x": -58.0, "z": -112.0, "h": 26.0, "r": 26.0},
		{"x": -22.0, "z": -125.0, "h": 34.0, "r": 30.0},
		{"x": 24.0, "z": -118.0, "h": 29.0, "r": 26.0},
		{"x": 58.0, "z": -108.0, "h": 22.0, "r": 23.0},
	]
	for spec in ridge_specs:
		var ridge := _add_cylinder(self, 0.35, float(spec["r"]), float(spec["h"]), Vector3(float(spec["x"]), -8.0 + float(spec["h"]) * 0.5, float(spec["z"])), Color(0.30, 0.35, 0.36), 9)
		ridge.rotation.y = 0.35
		_add_cylinder(self, 0.25, 6.8, 5.0, Vector3(float(spec["x"]), -8.0 + float(spec["h"]) - 1.5, float(spec["z"])), Color(0.82, 0.84, 0.86), 9)
	# Cloud billboards around the peak.
	var cloud_texture := _make_cloud_texture()
	var cloud_specs := [
		Vector3(-55.0, 31.0, -125.0), Vector3(48.0, 40.0, -138.0),
		Vector3(-15.0, 48.0, -155.0), Vector3(75.0, 26.0, -120.0),
		Vector3(-90.0, 22.0, -115.0), Vector3(8.0, 18.0, -92.0),
	]
	for pos in cloud_specs:
		var sprite := Sprite3D.new()
		sprite.texture = cloud_texture
		sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sprite.pixel_size = 0.11
		sprite.position = pos
		sprite.modulate = Color(1.0, 0.95, 0.86, 0.60)
		sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
		sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(sprite)
		_clouds.append(sprite)

func _make_cloud_texture() -> ImageTexture:
	var size := Vector2i(192, 96)
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4031
	for y in size.y:
		for x in size.x:
			var nx := (float(x) / float(size.x) - 0.5) * 2.0
			var ny := (float(y) / float(size.y) - 0.5) * 2.0
			var d := Vector2(nx * 1.4, ny * 2.8).length()
			var n := 0.0
			var amp := 0.5
			var px := nx * 5.0
			var py := ny * 8.0
			for o in 4:
				n += absf(sin(px + py * 1.3 + float(o) * 4.2) * cos(py - px * 0.7 + float(o) * 2.1)) * amp
				amp *= 0.48
			var alpha := clampf(1.0 - d * 0.62 + n * 0.22, 0.0, 0.9)
			alpha *= clampf((0.5 - absf(ny - 0.10)) * 3.0, 0.0, 1.0)
			image.set_pixel(x, y, Color(1.0, 0.98, 0.94, alpha * 0.75))
	return ImageTexture.create_from_image(image)

func _build_trees() -> void:
	var tree_paths := ["tree_default.glb", "tree_oak.glb", "tree_detailed.glb", "tree_tall.glb", "tree_thin.glb", "tree_pineTallA.glb", "tree_plateau.glb"]
	var models: Array[PackedScene] = []
	for path in tree_paths:
		var packed := load(KIT_DIR + path) as PackedScene
		if packed != null:
			models.append(packed)
	var spots := [
		Vector2(-26.0, 22.0), Vector2(-34.0, -3.0), Vector2(26.0, 15.0), Vector2(38.0, 2.0),
		Vector2(-47.0, -34.0), Vector2(50.0, -38.0), Vector2(-30.0, -48.0), Vector2(12.0, -48.0),
		Vector2(58.0, 18.0), Vector2(-58.0, 34.0), Vector2(-20.0, 44.0), Vector2(22.0, 44.0),
		Vector2(-52.0, 8.0), Vector2(54.0, -12.0), Vector2(-42.0, -15.0), Vector2(44.0, -46.0),
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = 731
	for i in spots.size():
		var p: Vector2 = spots[i]
		var y := _height(p.x, p.y)
		var tree := (models[i % models.size()] if not models.is_empty() else null)
		if tree == null:
			continue
		var inst := tree.instantiate() as Node3D
		inst.position = Vector3(p.x, y, p.y)
		var s := rng.randf_range(0.8, 1.3)
		inst.scale = Vector3.ONE * s
		inst.rotation.y = rng.randf() * TAU
		add_child(inst)
		_fix_tree_materials(inst)
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.30 * s
		cyl.height = 2.0
		shape.shape = cyl
		shape.position.y = 1.0
		body.add_child(shape)
		inst.add_child(body)

func _fix_tree_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			for s in mesh_instance.mesh.get_surface_count():
				var mat := mesh_instance.mesh.surface_get_material(s)
				if mat is StandardMaterial3D:
					var copy := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
					copy.metallic = 0.0
					copy.roughness = 1.0
					mesh_instance.set_surface_override_material(s, copy)
	for child in node.get_children():
		_fix_tree_materials(child)

# =============================================================================
# CHARACTER
# =============================================================================

func _build_player() -> void:
	_player = CharacterBody3D.new()
	_player.name = "VisionPlayer"
	_player.collision_layer = 2
	_player.collision_mask = 1
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.30
	capsule.height = 1.65
	shape.shape = capsule
	shape.position.y = 0.83
	_player.add_child(shape)
	add_child(_player)
	var spawn := _house_spawn if _house_spawn != Vector3.ZERO else Vector3(PLAYER_START.x, _height(PLAYER_START.x, PLAYER_START.z) + 1.0, PLAYER_START.z)
	_player.position = spawn + Vector3(0.0, 0.04, 0.0)
	_blue_rig = _build_person(true)
	_blue_person = _blue_rig["root"] as Node3D
	_blue_person.rotation.y = PI
	_player.add_child(_blue_person)
	_white_rig = _build_person(false)
	_white_person = _white_rig["root"] as Node3D
	_white_person.rotation.y = PI
	_player.add_child(_white_person)
	_white_person.visible = false

func _build_person(blue: bool) -> Dictionary:
	# A wooden marionette with visible ball joints and an empty heart-shaped
	# cavity in the chest. The white-painted variant keeps the same body.
	var root := Node3D.new()
	var wood := Color(0.58, 0.39, 0.22) if blue else Color(0.82, 0.74, 0.60)
	var wood_light := Color(0.72, 0.53, 0.32) if blue else Color(0.91, 0.84, 0.72)
	var wood_dark := Color(0.31, 0.20, 0.12) if blue else Color(0.52, 0.43, 0.34)
	var paint := Color(0.16, 0.28, 0.52) if blue else Color(0.78, 0.22, 0.20)
	var skin := Color(0.72, 0.52, 0.32) if blue else Color(0.91, 0.84, 0.72)
	var brass := Color(0.78, 0.59, 0.24)
	var rig := {}
	# legs: hip pin, thigh, knee pin, shin, ankle, carved foot
	var legs := [Node3D.new(), Node3D.new()]
	for i in 2:
		var leg: Node3D = legs[i]
		leg.position = Vector3(-0.11 + float(i) * 0.22, 0.75, 0.0)
		root.add_child(leg)
		_add_sphere(leg, 0.075, Vector3(0.0, 0.0, 0.0), wood_dark)
		_add_cylinder(leg, 0.060, 0.070, 0.27, Vector3(0.0, -0.16, 0.0), wood_light, 8)
		_add_sphere(leg, 0.058, Vector3(0.0, -0.31, 0.0), brass)
		_add_cylinder(leg, 0.050, 0.060, 0.27, Vector3(0.0, -0.46, 0.0), wood, 8)
		_add_sphere(leg, 0.050, Vector3(0.0, -0.60, 0.0), wood_dark)
		_add_box(leg, Vector3(0.15, 0.10, 0.25), Vector3(0.0, -0.665, 0.035), wood_dark)
		_add_box(leg, Vector3(0.10, 0.035, 0.03), Vector3(0.0, -0.65, 0.16), wood_light)
	# hips / carved torso
	_add_box(root, Vector3(0.32, 0.14, 0.22), Vector3(0.0, 0.78, 0.0), wood_dark)
	_add_box(root, Vector3(0.34, 0.045, 0.24), Vector3(0.0, 0.87, 0.0), wood_light)
	var torso := _add_box(root, Vector3(0.36, 0.43, 0.24), Vector3(0.0, 1.10, 0.0), wood)
	# layered chest plates and carved seams
	_add_box(root, Vector3(0.30, 0.20, 0.025), Vector3(0.0, 1.15, 0.135), wood_light)
	_add_box(root, Vector3(0.28, 0.025, 0.02), Vector3(0.0, 1.24, 0.15), wood_dark)
	_add_box(root, Vector3(0.34, 0.035, 0.255), Vector3(0.0, 0.90, 0.0), wood_dark)
	# empty heart cavity (two dark lobes + a point, with a brass rim)
	for side in [-1.0, 1.0]:
		_add_sphere(root, 0.062, Vector3(float(side) * 0.052, 1.075, 0.140), Color(0.055, 0.040, 0.030))
	var heart_point := _add_box(root, Vector3(0.12, 0.12, 0.035), Vector3(0.0, 1.005, 0.140), Color(0.055, 0.040, 0.030))
	heart_point.rotation.z = PI * 0.25
	for side in [-1.0, 1.0]:
		_add_sphere(root, 0.020, Vector3(float(side) * 0.10, 1.12, 0.155), brass)
		_add_sphere(root, 0.020, Vector3(float(side) * 0.10, 1.00, 0.155), brass)
	_add_box(root, Vector3(0.022, 0.12, 0.025), Vector3(0.0, 0.96, 0.16), brass)
	# shoulders / arms: shoulder pin, upper arm, elbow pin, forearm, mitten
	var arms := [Node3D.new(), Node3D.new()]
	for i in 2:
		var arm: Node3D = arms[i]
		arm.position = Vector3(-0.24 + float(i) * 0.48, 1.27, 0.0)
		root.add_child(arm)
		_add_sphere(arm, 0.085, Vector3.ZERO, brass)
		_add_cylinder(arm, 0.045, 0.060, 0.25, Vector3(0.0, -0.155, 0.0), wood_light, 7)
		_add_sphere(arm, 0.055, Vector3(0.0, -0.30, 0.0), wood_dark)
		_add_cylinder(arm, 0.040, 0.050, 0.24, Vector3(0.0, -0.44, 0.0), wood, 7)
		_add_sphere(arm, 0.060, Vector3(0.0, -0.58, 0.0), skin)
		_add_box(arm, Vector3(0.075, 0.030, 0.075), Vector3(0.0, -0.62, 0.04), wood_dark)
	# neck and carved head
	_add_cylinder(root, 0.060, 0.070, 0.12, Vector3(0.0, 1.39, 0.0), wood_dark, 8)
	var head := Node3D.new()
	head.position = Vector3(0.0, 1.56, 0.0)
	root.add_child(head)
	_add_sphere(head, 0.175, Vector3.ZERO, skin)
	# painted hair cap and side locks
	_add_sphere(head, 0.183, Vector3(0.0, 0.065, -0.018), Color(0.24, 0.16, 0.10))
	for side in [-1.0, 1.0]:
		_add_box(head, Vector3(0.065, 0.17, 0.10), Vector3(float(side) * 0.15, 0.01, -0.035), Color(0.24, 0.16, 0.10))
		_add_sphere(head, 0.045, Vector3(float(side) * 0.175, -0.015, 0.0), skin)
		# eyes with tiny white catchlight
		_add_box(head, Vector3(0.050, 0.038, 0.014), Vector3(float(side) * 0.066, 0.020, 0.155), Color(0.10, 0.07, 0.05))
		_add_box(head, Vector3(0.018, 0.012, 0.008), Vector3(float(side) * 0.052, 0.026, 0.163), Color(0.96, 0.92, 0.80))
		_add_box(head, Vector3(0.052, 0.012, 0.010), Vector3(float(side) * 0.10, -0.058, 0.148), Color(0.68, 0.30, 0.24))
		# painted seam / eyebrow
		_add_box(head, Vector3(0.050, 0.010, 0.008), Vector3(float(side) * 0.064, 0.060, 0.155), Color(0.28, 0.18, 0.11))
	_add_box(head, Vector3(0.035, 0.025, 0.020), Vector3(0.0, -0.010, 0.170), skin)
	_add_box(head, Vector3(0.060, 0.012, 0.010), Vector3(0.0, -0.075, 0.160), Color(0.22, 0.12, 0.09))
	# scarf around the neck
	_add_box(root, Vector3(0.29, 0.070, 0.26), Vector3(0.0, 1.38, 0.0), paint)
	var scarf_tail := _add_box(root, Vector3(0.09, 0.22, 0.045), Vector3(0.10, 1.22, 0.125), paint)
	scarf_tail.rotation.z = -0.20
	if blue:
		# straw hat over the carved head
		_add_cylinder(head, 0.34, 0.35, 0.035, Vector3(0.0, 0.15, 0.0), Color(0.82, 0.68, 0.39), 14)
		_add_cylinder(head, 0.13, 0.19, 0.16, Vector3(0.0, 0.24, 0.0), Color(0.78, 0.62, 0.34), 12)
		_add_cylinder(head, 0.135, 0.14, 0.035, Vector3(0.0, 0.18, 0.0), Color(0.30, 0.22, 0.14), 12)
		var feather := _add_box(head, Vector3(0.035, 0.16, 0.025), Vector3(0.20, 0.31, -0.02), Color(0.88, 0.74, 0.42))
		feather.rotation.z = 0.49
	rig["root"] = root
	rig["legs"] = legs
	rig["arms"] = arms
	rig["head"] = head
	rig["torso"] = torso
	return rig

func _build_cape() -> void:
	var body := _blue_person
	var cape := MeshInstance3D.new()
	cape.name = "BlueCape"
	_cape_rows = 8
	_cape_cols = 6
	_cape_vertices = PackedVector3Array()
	_cape_indices = PackedInt32Array()
	for row in _cape_rows:
		for col in _cape_cols:
			var t := float(row) / float(_cape_rows - 1)
			var u := float(col) / float(_cape_cols - 1) - 0.5
			_cape_vertices.append(Vector3(u * 0.52, 1.34 - t * 0.95, -0.13 - t * 0.20))
	for row in _cape_rows - 1:
		for col in _cape_cols - 1:
			var a := row * _cape_cols + col
			_cape_indices.append_array([a, a + 1, a + _cape_cols, a + 1, a + _cape_cols + 1, a + _cape_cols])
	_cape_mesh = ArrayMesh.new()
	_update_cape_mesh(0.0, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.32, 0.68)
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	cape.material_override = mat
	cape.mesh = _cape_mesh
	cape.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	body.add_child(cape)
	_blue_rig["cape"] = cape
	var clasp := _add_sphere(_blue_person, 0.05, Vector3(0.0, 1.24, 0.13), Color(0.92, 0.74, 0.38))
	clasp.name = "CapeClasp"

func _update_cape_mesh(time: float, speed: float) -> void:
	if _cape_mesh == null:
		return
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	for row in _cape_rows:
		var t := float(row) / float(_cape_rows - 1)
		for col in _cape_cols:
			var u := float(col) / float(_cape_cols - 1) - 0.5
			var wave := sin(time * 3.2 + row * 0.85 + col * 0.35) * (0.025 + speed * 0.045) * t
			var vert := Vector3(
				u * (0.52 + t * 0.12),
				1.34 - t * 0.95,
				-0.13 - t * (0.20 + speed * 0.10) + wave)
			verts.append(vert)
			normals.append(Vector3(0.0, 0.2, -1.0).normalized())
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = _cape_indices
	_cape_mesh.clear_surfaces()
	_cape_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "VisionCamera"
	_camera.fov = 58.0
	_camera.near = 0.08
	_camera.far = 320.0
	_camera.current = true
	add_child(_camera)
	# mild cinematic depth of field
	_camera.attributes = CameraAttributesPractical.new()
	var attrs := _camera.attributes as CameraAttributesPractical
	attrs.dof_blur_far_enabled = true
	attrs.dof_blur_far_distance = 90.0
	attrs.dof_blur_far_transition = 45.0
	attrs.dof_blur_amount = 0.06

func _set_first_person(enabled: bool) -> void:
	_first_person = enabled
	if enabled:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if _blue_person != null:
		_blue_person.visible = not enabled and _character_mode == 0
	if _white_person != null:
		_white_person.visible = not enabled and _character_mode == 1

func _toggle_character() -> void:
	_character_mode = 1 - _character_mode
	_blue_person.visible = _character_mode == 0 and not _first_person
	_white_person.visible = _character_mode == 1 and not _first_person

# =============================================================================
# CAMERA / INPUT / ANIMATION
# =============================================================================

func _input(event: InputEvent) -> void:
	# Mouse look is captured here rather than in _unhandled_input so UI nodes
	# (prompt, pause panel) can never swallow first-person camera motion.
	if _pause_active or not _mouse_captured:
		return
	if event is InputEventMouseMotion:
		_yaw -= event.relative.x * 0.0025
		_pitch = clampf(_pitch - event.relative.y * 0.0022, -0.75, 0.35)
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var pause_key: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		if _pause_active:
			if pause_key == KEY_ESCAPE:
				_close_pause()
				get_viewport().set_input_as_handled()
			return
		if pause_key == KEY_ESCAPE:
			_open_pause()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed and not event.echo:
		var key: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		match key:
			KEY_ESCAPE:
				pass
			KEY_C:
				_toggle_character()
			KEY_V:
				_set_first_person(not _first_person)
			KEY_T:
				_time_speed = 1.0 if _time_speed > 4.0 else 5.0
			KEY_E:
				if _near_windmill():
					_begin_journey()
			KEY_SPACE:
				if _player != null and _player.is_on_floor():
					_player.velocity.y = 7.0

func _process(delta: float) -> void:
	_anim_time += delta
	if _first_person and not _pause_active and Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_update_time_of_day(delta)
	if _player != null:
		_grass_player_pos = _player.global_position
		_grass_player_vel = _player.velocity
		for material in _grass_materials:
			if material != null:
				material.set_shader_parameter("player_pos", _grass_player_pos)
				material.set_shader_parameter("player_vel", _grass_player_vel)
	if _windmill_sails != null:
		_windmill_sails.rotation.z += delta * 0.35
	for i in _clouds.size():
		var cloud := _clouds[i]
		if cloud != null:
			cloud.position.x += sin(_anim_time * 0.08 + float(i)) * delta * 0.20
	if _player != null:
		_update_player(delta)
		_update_camera(delta)
		if _journey_prompt != null and not _journey_started:
			_journey_prompt.visible = true
			var near_mill := _near_windmill()
			var inside_house := absf(_player.global_position.x) < 9.4 and _player.global_position.z > 46.0 and _player.global_position.z < 70.8
			_journey_prompt.text = "E · 开始旅程" if near_mill else ("推开木门，出去看看" if inside_house else "沿着草坡走到白风车下")
			_journey_prompt.modulate.a = 0.72 + 0.28 * sin(_anim_time * 2.4) if near_mill else 0.78

func _update_player(delta: float) -> void:
	if _pause_active:
		_player.velocity.x = 0.0
		_player.velocity.z = 0.0
		return
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input.length_squared() < 0.001:
		# physical fallback also keeps arrow keys working on unusual layouts
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			input.y -= 1.0
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			input.y += 1.0
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			input.x -= 1.0
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			input.x += 1.0
	input = input.normalized()
	var cam_basis := Basis(Vector3.UP, _yaw)
	var direction := cam_basis * Vector3(input.x, 0.0, input.y)
	if direction.length_squared() > 0.001:
		# Quantize to eight compass directions; the 3D puppet turns to face the
		# direction of travel instead of sliding in one fixed pose.
		var desired_yaw := atan2(direction.x, direction.z)
		_target_yaw = round(desired_yaw / (PI * 0.25)) * (PI * 0.25)
	var turn_weight := 1.0 - exp(-13.0 * delta)
	_visual_yaw = lerp_angle(_visual_yaw, _target_yaw, turn_weight)
	if _blue_person != null:
		_blue_person.rotation.y = _visual_yaw
	if _white_person != null:
		_white_person.rotation.y = _visual_yaw
	var running := Input.is_key_pressed(KEY_SHIFT)
	var speed := 6.5 if running else 3.4
	_player.velocity.x = move_toward(_player.velocity.x, direction.x * speed, delta * 24.0)
	_player.velocity.z = move_toward(_player.velocity.z, direction.z * speed, delta * 24.0)
	if not _player.is_on_floor():
		_player.velocity.y -= 20.0 * delta
	_player.move_and_slide()
	var planar_speed := Vector2(_player.velocity.x, _player.velocity.z).length()
	_walk_cycle += delta * (2.0 + planar_speed * 1.8)
	var run_factor := clampf(planar_speed / 6.0, 0.0, 1.0)
	var legs: Array = _blue_rig["legs"]
	var arms: Array = _blue_rig["arms"]
	for i in 2:
		var leg: Node3D = legs[i]
		var arm: Node3D = arms[i]
		var sign := 1.0 if i == 0 else -1.0
		leg.rotation.x = sin(_walk_cycle) * 0.55 * sign * (0.35 + run_factor)
		arm.rotation.x = -sin(_walk_cycle) * 0.45 * sign * (0.35 + run_factor)
	if _blue_rig.has("torso"):
		(_blue_rig["torso"] as Node3D).rotation.z = sin(_walk_cycle) * 0.025 * run_factor
	_update_cape_mesh(_anim_time, planar_speed)
	var white_legs: Array = _white_rig.get("legs", [])
	var white_arms: Array = _white_rig.get("arms", [])
	for i in 2:
		if i < white_legs.size():
			(white_legs[i] as Node3D).rotation.x = sin(_walk_cycle + PI) * 0.35 * run_factor
		if i < white_arms.size():
			(white_arms[i] as Node3D).rotation.x = -sin(_walk_cycle + PI) * 0.30 * run_factor

func _update_camera(delta: float) -> void:
	var target := _player.global_position + Vector3(0.0, 1.35, 0.0)
	var head := _player.global_position + Vector3(0.0, 1.65, 0.0)
	if _first_person:
		var forward := Basis.from_euler(Vector3(_pitch, _yaw, 0.0)) * Vector3(0.0, 0.0, -1.0)
		_camera.global_position = head + Vector3(0.0, -0.05, 0.0)
		_camera.look_at(head + forward, Vector3.UP)
		_camera.fov = 72.0
		return
	var basis := Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
	var offset := basis * Vector3(0.0, 0.2, 5.8)
	var desired := target + offset
	var from := target + Vector3(0.0, 0.4, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, desired, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		desired = (hit["position"] as Vector3) + (from - desired).normalized() * 0.35
	_camera.global_position = _camera.global_position.lerp(desired, 1.0 - exp(-10.0 * delta))
	_camera.look_at(target, Vector3.UP)
	_camera.fov = 58.0

# =============================================================================
# UI
# =============================================================================

func _build_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 80
	add_child(_ui_layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_layer.add_child(root)
	var font := load(FONT_PATH) as Font
	_fade = ColorRect.new()
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.color = Color(0.02, 0.03, 0.04, 1.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_fade)
	_title = _make_label(Vector2(0.0, 42.0), Vector2(1280.0, 44.0), 28, Color(1.0, 0.94, 0.78), font, HORIZONTAL_ALIGNMENT_CENTER)
	_title.text = "序 · 风 从 草 坡 来"
	_title.modulate.a = 0.0
	root.add_child(_title)
	_phase_label = _make_label(Vector2(0.0, 94.0), Vector2(1280.0, 24.0), 15, Color(1.0, 0.86, 0.62), font, HORIZONTAL_ALIGNMENT_CENTER)
	root.add_child(_phase_label)
	_hint = _make_label(Vector2(0.0, 650.0), Vector2(1280.0, 26.0), 15, Color(0.93, 0.89, 0.80), font, HORIZONTAL_ALIGNMENT_CENTER)
	_hint.text = "WASD 移动   Shift 奔跑   空格 跳   C 切换角色   V 视角   T 快进时间"
	root.add_child(_hint)
	_intro_backdrop = ColorRect.new()
	_intro_backdrop.position = Vector2(330.0, 480.0)
	_intro_backdrop.size = Vector2(620.0, 92.0)
	_intro_backdrop.color = Color(0.03, 0.04, 0.05, 0.58)
	_intro_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_intro_backdrop)
	_intro_label = _make_label(Vector2(0.0, 488.0), Vector2(1280.0, 76.0), 19, Color(0.97, 0.91, 0.80), font, HORIZONTAL_ALIGNMENT_CENTER)
	_intro_label.text = "我在一间木匠的屋子里醒来。\n屋里没有人，刨花还带着新木头的味道。"
	_intro_label.modulate.a = 0.0
	_intro_backdrop.modulate.a = 0.0
	root.add_child(_intro_label)
	_journey_prompt = _make_label(Vector2(0.0, 606.0), Vector2(1280.0, 32.0), 18, Color(1.0, 0.88, 0.58), font, HORIZONTAL_ALIGNMENT_CENTER)
	_journey_prompt.text = "沿着草坡走到白风车下，按 E 开始旅程"
	_journey_prompt.modulate.a = 0.82
	root.add_child(_journey_prompt)
	_build_pause_ui(root, font)

func _build_pause_ui(root: Control, font: Font) -> void:
	_pause_panel = Control.new()
	_pause_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_panel.visible = false
	_pause_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_pause_panel)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.04, 0.68)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pause_panel.add_child(dim)
	var panel := ColorRect.new()
	panel.position = Vector2(400.0, 240.0)
	panel.size = Vector2(480.0, 220.0)
	panel.color = Color(0.04, 0.055, 0.06, 0.96)
	_pause_panel.add_child(panel)
	var title := _make_label(Vector2(400.0, 252.0), Vector2(480.0, 40.0), 24, Color(1.0, 0.86, 0.56), font, HORIZONTAL_ALIGNMENT_CENTER)
	title.text = "暂 停"
	_pause_panel.add_child(title)
	var resume := Button.new()
	resume.text = "继续"
	resume.position = Vector2(520.0, 310.0)
	resume.size = Vector2(240.0, 34.0)
	resume.add_theme_font_override("font", font)
	resume.add_theme_font_size_override("font_size", 18)
	resume.pressed.connect(_close_pause)
	_pause_panel.add_child(resume)
	var back := Button.new()
	back.text = "返回标题"
	back.position = Vector2(520.0, 360.0)
	back.size = Vector2(240.0, 34.0)
	back.add_theme_font_override("font", font)
	back.add_theme_font_size_override("font_size", 18)
	back.pressed.connect(_return_to_title)
	_pause_panel.add_child(back)
	var hint := _make_label(Vector2(400.0, 416.0), Vector2(480.0, 24.0), 14, Color(0.72, 0.72, 0.66), font, HORIZONTAL_ALIGNMENT_CENTER)
	hint.text = "Esc 继续游戏"
	_pause_panel.add_child(hint)

func _open_pause() -> void:
	if _pause_panel == null or _pause_active:
		return
	_pause_active = true
	_pause_panel.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _close_pause() -> void:
	if not _pause_active:
		return
	_pause_active = false
	_pause_panel.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _make_label(pos: Vector2, size: Vector2, font_size: int, colour: Color, font: Font, align: int) -> Label:
	var label := Label.new()
	label.position = pos
	label.size = size
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if font != null:
		label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", Color(0.12, 0.09, 0.06, 0.85))
	label.add_theme_constant_override("outline_size", 4)
	return label

func _near_windmill() -> bool:
	if _player == null:
		return false
	var mill_pos := Vector3(WINDMILL_POS.x, _height(WINDMILL_POS.x, WINDMILL_POS.y), WINDMILL_POS.y)
	return _player.global_position.distance_to(mill_pos) < 8.0

func _begin_journey() -> void:
	if _journey_started:
		return
	_journey_started = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	AudioDirector.play_sfx("transition", -7.0, 0.92)
	if _journey_prompt != null:
		_journey_prompt.visible = false
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, 0.8)
	await tween.finished
	GameState.begin_journey_on_main = true
	get_tree().root.content_scale_size = _saved_content_scale
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _return_to_title() -> void:
	get_tree().root.content_scale_size = _saved_content_scale
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file("res://scenes/main.tscn")

# =============================================================================
# SMALL MESH HELPERS
# =============================================================================

func _mat(colour: Color, roughness: float = 1.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = roughness
	mat.metallic = 0.0
	return mat

func _add_box(parent: Node3D, size: Vector3, pos: Vector3, colour: Color,
		emissive: bool = false) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	var mat := _mat(colour)
	if emissive:
		mat.emission_enabled = true
		mat.emission = colour
		mat.emission_energy_multiplier = 0.55
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(node)
	return node

func _add_cylinder(parent: Node3D, top: float, bottom: float, height: float,
		pos: Vector3, colour: Color, segments: int = 10, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = segments
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	node.rotation = rot
	node.material_override = _mat(colour)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(node)
	return node

func _add_sphere(parent: Node3D, radius: float, pos: Vector3, colour: Color) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	node.material_override = _mat(colour)
	parent.add_child(node)
	return node

func _add_mesh(parent: Node3D, mesh: Mesh, pos: Vector3, colour: Color) -> void:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	node.material_override = _mat(colour)
	parent.add_child(node)
