extends Node3D
## The carpenter's one-room-and-a-half home at the start of the opening. Built
## as its own scene so it can be iterated without touching the grass-slope world.
##
## Local layout: floor at y=0, door at -Z, workshop in the north half, living
## and sleeping area in the south half. The owner is out; the puppet wakes in
## the middle of his workshop/home.

const FONT_PATH := "res://assets/fonts/NotoSansSC-Subset.ttf"
const WIDTH := 18.0
const DEPTH := 24.0
const WALL_H := 3.45

var _root: Node3D

func _ready() -> void:
	_build()

func get_spawn_position() -> Vector3:
	return Vector3(0.0, 0.06, -2.5)

func get_floor_world_offset() -> float:
	return 0.0

func get_footprint_radius() -> float:
	return 14.5

func _build() -> void:
	_root = Node3D.new()
	_root.name = "CarpenterHouseInterior"
	add_child(_root)
	var north := -DEPTH * 0.5
	var south := DEPTH * 0.5
	var west := -WIDTH * 0.5
	var east := WIDTH * 0.5
	var beam := Color(0.27, 0.17, 0.10)
	var wall := Color(0.78, 0.67, 0.51)
	var wall_dark := Color(0.57, 0.43, 0.27)
	var floor_col := Color(0.43, 0.28, 0.17)
	var floor_alt := Color(0.47, 0.31, 0.19)
	var plaster := Color(0.84, 0.75, 0.59)

	# floor / foundation
	_add_box(Vector3(WIDTH + 0.8, 0.34, DEPTH + 0.8), Vector3(0.0, -0.17, 0.0), Color(0.31, 0.22, 0.14))
	for row in 12:
		for col in 6:
			var c := floor_col if (row + col) % 2 == 0 else floor_alt
			_add_box(Vector3(2.9, 0.035, 1.92), Vector3(-7.5 + float(col) * 3.0, 0.018, -11.0 + float(row) * 2.0), c)
	_add_static_box(Vector3(0.0, -0.18, 0.0), Vector3(WIDTH, 0.34, DEPTH))

	# outer walls, with a door gap in the north wall
	_add_box(Vector3(0.32, WALL_H, DEPTH), Vector3(west, WALL_H * 0.5, 0.0), wall_dark)
	_add_box(Vector3(0.32, WALL_H, DEPTH), Vector3(east, WALL_H * 0.5, 0.0), wall_dark)
	_add_box(Vector3(WIDTH, WALL_H, 0.32), Vector3(0.0, WALL_H * 0.5, south), wall_dark)
	for side in [-1.0, 1.0]:
		_add_box(Vector3(8.2, WALL_H, 0.32), Vector3(float(side) * 4.9, WALL_H * 0.5, north), wall_dark)
	_add_box(Vector3(2.8, 1.25, 0.32), Vector3(0.0, WALL_H - 0.625, north), wall_dark)
	# inner plaster panels and beams
	for side in [-1.0, 1.0]:
		_add_box(Vector3(0.06, 2.35, 20.8), Vector3(west + 0.18, 1.45, 0.0), plaster)
		_add_box(Vector3(0.06, 2.35, 20.8), Vector3(east - 0.18, 1.45, 0.0), plaster)
		_add_box(Vector3(7.6, 2.35, 0.06), Vector3(float(side) * 4.9, 1.45, north + 0.18), plaster)
	_add_box(Vector3(WIDTH - 0.5, 2.35, 0.06), Vector3(0.0, 1.45, south - 0.18), plaster)
	for x in [-8.0, -4.0, 0.0, 4.0, 8.0]:
		_add_box(Vector3(0.14, WALL_H, 0.18), Vector3(x, WALL_H * 0.5, south - 0.23), beam)
	for z in [-4.0, 2.0, 8.0]:
		_add_box(Vector3(0.14, WALL_H, 0.18), Vector3(west + 0.23, WALL_H * 0.5, z), beam)
		_add_box(Vector3(0.14, WALL_H, 0.18), Vector3(east - 0.23, WALL_H * 0.5, z), beam)
	# framed design sheet of the puppet the carpenter was making
	_add_box(Vector3(1.05, 1.45, 0.08), Vector3(3.15, 1.78, -11.79), wood_dark())
	var design := Sprite3D.new()
	design.texture = load("res://assets/generated/player_puppet_illustration.png")
	design.pixel_size = 0.0068
	design.position = Vector3(3.15, 1.78, -11.73)
	design.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	add_child(design)
	# north door frame
	for side in [-1.0, 1.0]:
		_add_box(Vector3(0.22, 2.25, 0.42), Vector3(float(side) * 1.48, 1.12, north), beam)
	_add_box(Vector3(3.2, 0.22, 0.42), Vector3(0.0, 2.23, north), beam)
	_add_box(Vector3(2.7, 0.12, 0.5), Vector3(0.0, 0.06, north + 0.15), wood_light())
	# wall collisions
	_add_static_box(Vector3(west, WALL_H * 0.5, 0.0), Vector3(0.34, WALL_H, DEPTH))
	_add_static_box(Vector3(east, WALL_H * 0.5, 0.0), Vector3(0.34, WALL_H, DEPTH))
	_add_static_box(Vector3(0.0, WALL_H * 0.5, south), Vector3(WIDTH, WALL_H, 0.34))
	for side in [-1.0, 1.0]:
		_add_static_box(Vector3(float(side) * 4.9, WALL_H * 0.5, north), Vector3(8.2, WALL_H, 0.34))
	# Open workshop/living transition: timber posts and a header beam instead of
	# a solid wall, so the whole carpenter's home stays readable from the bed.
	for side in [-1.0, 1.0]:
		_add_box(Vector3(0.22, 3.0, 0.36), Vector3(float(side) * 6.0, 1.50, -1.0), beam)
		_add_box(Vector3(0.14, 1.0, 0.30), Vector3(float(side) * 6.0, 0.50, -1.0), wood_light())
	_add_box(Vector3(WIDTH - 0.6, 0.18, 0.34), Vector3(0.0, 3.0, -1.0), beam)
	# short side buttresses at the room edges, leaving a wide central opening
	for side in [-1.0, 1.0]:
		_add_box(Vector3(1.4, 1.15, 0.26), Vector3(float(side) * 7.8, 0.58, -1.0), wall)
		_add_static_box(Vector3(float(side) * 7.8, 0.58, -1.0), Vector3(1.4, 1.15, 0.28))

	# ceiling and shallow pitched roof
	_add_box(Vector3(WIDTH, 0.16, DEPTH), Vector3(0.0, WALL_H, 0.0), Color(0.34, 0.23, 0.14))
	for x in [-7.0, -3.5, 0.0, 3.5, 7.0]:
		_add_box(Vector3(0.16, 0.18, DEPTH - 0.5), Vector3(x, WALL_H - 0.14, 0.0), beam)
	for side in [-1.0, 1.0]:
		var roof := _add_box(Vector3(WIDTH + 0.8, 0.16, DEPTH * 0.61), Vector3(0.0, WALL_H + 0.52, float(side) * DEPTH * 0.24), Color(0.37, 0.20, 0.14))
		roof.rotation.x = float(side) * 0.24
	# windows, two on each side
	for side in [-1.0, 1.0]:
		var wx := float(side) * (WIDTH * 0.5 - 0.18)
		for wz in [-7.0, 4.5]:
			_add_box(Vector3(0.08, 1.15, 1.65), Vector3(wx - float(side) * 0.06, 1.82, wz), Color(0.12, 0.15, 0.18))
			_add_box(Vector3(0.05, 0.94, 1.38), Vector3(wx - float(side) * 0.10, 1.82, wz), Color(0.65, 0.79, 0.86), Vector3.ZERO, true)
			_add_box(Vector3(0.04, 1.00, 0.07), Vector3(wx - float(side) * 0.11, 1.82, wz), beam)
			_add_box(Vector3(0.04, 0.07, 1.4), Vector3(wx - float(side) * 0.11, 1.82, wz), beam)
			# carved flower box under the window
			_add_box(Vector3(0.38, 0.20, 1.45), Vector3(wx - float(side) * 0.28, 1.12, wz), wood_light())
			for i in 4:
				_add_sphere(0.075, Vector3(wx - float(side) * 0.30, 1.26, wz - 0.52 + float(i) * 0.35), Color(0.72, 0.25, 0.30))

	# --- workshop: workbench and tool wall ---
	_add_furniture("tableCross", Vector3(-5.4, 0.02, -6.0), 0.24)
	# vice / carved block on the imported workbench
	_add_box(Vector3(0.38, 0.20, 0.30), Vector3(-4.2, 0.94, -6.0), wood_dark())
	_add_box(Vector3(0.15, 0.15, 0.20), Vector3(-4.2, 1.10, -6.0), Color(0.55, 0.55, 0.52))
	# tool board + tools
	_add_box(Vector3(4.2, 1.55, 0.08), Vector3(-5.4, 1.9, -10.85), Color(0.34, 0.23, 0.14))
	for i in 6:
		var tx := -7.1 + float(i) * 0.68
		_add_box(Vector3(0.08, 0.42, 0.06), Vector3(tx, 2.15, -10.78), Color(0.60, 0.62, 0.58))
		_add_box(Vector3(0.18, 0.12, 0.07), Vector3(tx, 1.96, -10.78), wood_dark())
	_add_box(Vector3(0.08, 0.55, 0.05), Vector3(3.6, 1.95, -2.0), Color(0.48, 0.48, 0.46))
	_add_box(Vector3(0.65, 0.08, 0.05), Vector3(3.6, 1.72, -2.0), Color(0.32, 0.25, 0.18))
	# lumber rack on the east wall
	for i in 4:
		_add_box(Vector3(1.0, 0.16, 4.0), Vector3(7.8, 0.35 + float(i) * 0.22, -6.0 - float(i) * 0.05), wall_dark)
		_add_box(Vector3(1.6, 0.08, 0.08), Vector3(7.3, 1.9, -6.0 - float(i) * 0.05), beam)
	# carving work sits on the imported workbench; no separate table in the door path
	# wood shavings on the floor
	var rng := RandomNumberGenerator.new()
	rng.seed = 8104
	for i in 42:
		var px := rng.randf_range(-7.0, 7.0)
		var pz := rng.randf_range(-10.0, -2.4)
		_add_box(Vector3(rng.randf_range(0.08, 0.28), 0.012, rng.randf_range(0.015, 0.06)),
			Vector3(px, 0.035, pz), Color(0.78, 0.65, 0.43), Vector3(0.0, rng.randf_range(0.0, TAU), 0.0))
	# lathe with a half-turned table leg
	_add_box(Vector3(2.1, 0.16, 0.8), Vector3(5.1, 0.72, -3.7), wood_dark())
	for lx in [4.2, 6.0]:
		_add_box(Vector3(0.12, 0.68, 0.12), Vector3(lx, 0.34, -3.7), beam)
	_add_box(Vector3(0.22, 0.55, 0.35), Vector3(4.35, 0.95, -3.7), wood_dark())
	_add_cylinder(0.20, 0.22, 0.16, Vector3(4.35, 1.30, -3.7), wood(), 10)
	_add_box(Vector3(1.0, 0.05, 0.06), Vector3(5.1, 0.85, -4.15), Color(0.55, 0.55, 0.52))
	_add_cylinder(0.055, 0.07, 0.55, Vector3(5.75, 0.99, -3.7), wood_light(), 8)
	_add_static_box(Vector3(5.1, 0.7, -3.7), Vector3(2.2, 1.4, 1.0))
	# imported bookcase along the east wall and travel boxes by the door
	_add_furniture("bookcaseOpen", Vector3(7.45, 0.02, -9.0), 0.30, -90.0)
	_add_furniture("cardboardBoxClosed", Vector3(5.25, 0.02, -10.7), 0.32)
	_add_furniture("cardboardBoxOpen", Vector3(6.05, 0.02, -10.0), 0.30, 20.0)
	# a low lumber pile
	for i in 4:
		_add_box(Vector3(2.2, 0.18, 0.28), Vector3(6.4, 0.10 + float(i) * 0.20, -1.0 + float(i % 2) * 0.35), wall_dark)
	# large bear carving on a plinth, visible from the bed
	_add_box(Vector3(0.8, 0.55, 0.8), Vector3(-5.4, 0.27, -2.0), wood_dark())
	_add_bear_carving(Vector3(-5.4, 0.55, -2.0), 1.2)
	# owner's boots by the door (coat rack is an imported model)
	_add_box(Vector3(0.52, 0.20, 0.44), Vector3(-1.9, 0.12, -10.2), Color(0.30, 0.21, 0.15))
	_add_box(Vector3(0.52, 0.20, 0.44), Vector3(-1.25, 0.12, -10.2), Color(0.30, 0.21, 0.15))
	# unfinished puppet + heart blanks on the imported workbench
	_add_box(Vector3(0.22, 0.30, 0.14), Vector3(-4.1, 0.99, -6.0), wood())
	_add_sphere(0.11, Vector3(-4.1, 1.23, -6.0), wood_light())
	_add_box(Vector3(0.06, 0.26, 0.07), Vector3(-4.36, 0.88, -6.0), wood_dark())
	_add_box(Vector3(0.06, 0.26, 0.07), Vector3(-3.84, 0.88, -6.0), wood_dark())
	_add_box(Vector3(0.10, 0.10, 0.03), Vector3(-4.1, 1.00, -5.92), Color(0.06, 0.04, 0.03))
	_add_owl_carving(Vector3(-2.9, 0.86, -6.15), 0.45)
	_add_heart(Vector3(-4.9, 0.86, -6.05), 0.09, wood_dark())
	for i in 3:
		_add_box(Vector3(0.035, 0.02, 0.24), Vector3(-5.5 + float(i) * 0.08, 0.84, -5.9), Color(0.66, 0.66, 0.62))

	# --- carvings around the workshop ---
	_add_bear_carving(Vector3(-7.4, 0.0, -3.0), 1.0)
	_add_owl_carving(Vector3(-6.9, 0.0, -8.6), 0.9)
	_add_fish_carving(Vector3(5.5, 0.0, -8.9), 0.9)
	_add_face_carving(Vector3(4.0, 0.0, -3.0), 1.0)
	_add_bird_carving(Vector3(-3.8, 0.0, -8.8), 0.8)
	for i in 4:
		_add_relief_panel(Vector3(-7.8, 1.1 + float(i) * 0.62, -4.0), i)
	# shelf of small carvings on the east wall
	_add_box(Vector3(0.6, 0.08, 4.0), Vector3(7.4, 1.55, -3.6), beam)
	_add_box(Vector3(0.6, 0.08, 4.0), Vector3(7.4, 2.10, -3.6), beam)
	for i in 5:
		_add_owl_carving(Vector3(7.4, 1.58, -5.2 + float(i) * 0.78), 0.55 + float(i % 2) * 0.12)

	# --- living room: imported Kenney furniture + custom carving details ---
	_add_furniture("bedDouble", Vector3(-6.0, 0.02, 6.0), 0.30)
	# pillow / folded blanket keep the bed in the carpenter's own palette
	_add_box(Vector3(1.25, 0.16, 0.45), Vector3(-6.0, 1.10, 4.55), Color(0.88, 0.83, 0.70))
	_add_box(Vector3(2.45, 0.055, 1.05), Vector3(-6.0, 1.08, 6.0), Color(0.47, 0.27, 0.25))
	_add_heart(Vector3(-6.0, 1.30, 3.28), 0.16, wood_dark())
	_add_furniture("tableCross", Vector3(2.0, 0.02, 5.7), 0.18)
	_add_furniture("chair", Vector3(2.0, 0.02, 4.45), 0.30, 180.0)
	_add_furniture("chair", Vector3(2.0, 0.02, 6.95), 0.30, 0.0)
	_add_furniture("bench", Vector3(-6.2, 0.02, 9.7), 0.30, 90.0)
	_add_furniture("bookcaseOpen", Vector3(7.35, 0.02, 9.0), 0.30, -90.0)
	# hearth on the east wall
	_add_box(Vector3(2.0, 1.75, 0.55), Vector3(6.8, 0.88, 6.0), Color(0.42, 0.40, 0.35))
	_add_box(Vector3(1.3, 0.85, 0.10), Vector3(6.8, 0.52, 5.68), Color(0.06, 0.055, 0.045))
	_add_box(Vector3(1.15, 0.36, 0.08), Vector3(6.8, 0.34, 5.60), Color(0.86, 0.36, 0.13), Vector3.ZERO, true)
	_add_box(Vector3(2.3, 0.14, 0.8), Vector3(6.8, 1.82, 6.0), wood_dark())
	_add_static_box(Vector3(6.8, 0.9, 6.0), Vector3(2.1, 1.8, 0.65))
	# shelf and crockery
	_add_box(Vector3(3.2, 0.09, 0.7), Vector3(4.0, 1.8, 9.8), beam)
	for i in 4:
		_add_cylinder(0.11, 0.13, 0.26, Vector3(3.0 + float(i) * 0.55, 1.98, 9.8), Color(0.64, 0.44, 0.28), 8)
	# rug
	_add_box(Vector3(5.4, 0.025, 3.8), Vector3(0.8, 0.03, 4.9), Color(0.43, 0.25, 0.22))
	_add_box(Vector3(4.5, 0.015, 3.0), Vector3(0.8, 0.045, 4.9), Color(0.62, 0.48, 0.30))
	# carved trunk
	_add_box(Vector3(1.8, 0.75, 1.1), Vector3(-1.8, 0.39, 9.6), wood_dark())
	_add_box(Vector3(1.7, 0.48, 0.04), Vector3(-1.8, 0.48, 9.05), wood_light())
	_add_box(Vector3(0.18, 0.18, 0.05), Vector3(-1.8, 0.62, 9.02), Color(0.72, 0.56, 0.30))

	# --- lights ---
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0.0, 3.0, 4.0)
	lamp.light_color = Color(1.0, 0.72, 0.42)
	lamp.light_energy = 1.9
	lamp.omni_range = 13.0
	lamp.shadow_enabled = true
	add_child(lamp)
	var work_lamp := OmniLight3D.new()
	work_lamp.position = Vector3(-4.5, 2.7, -6.0)
	work_lamp.light_color = Color(1.0, 0.72, 0.42)
	work_lamp.light_energy = 0.9
	work_lamp.omni_range = 6.0
	work_lamp.shadow_enabled = false
	add_child(work_lamp)
	var hearth_light := OmniLight3D.new()
	hearth_light.position = Vector3(6.3, 0.75, 5.9)
	hearth_light.light_color = Color(1.0, 0.42, 0.18)
	hearth_light.light_energy = 0.65
	hearth_light.omni_range = 3.2
	hearth_light.shadow_enabled = false
	add_child(hearth_light)
	# broad ceiling fills so the workshop joins are readable instead of black
	for entry in [[Vector3(0.0, 2.95, -5.0), 1.05, 10.5], [Vector3(0.0, 2.95, 7.5), 0.75, 10.0]]:
		var fill := OmniLight3D.new()
		fill.position = entry[0]
		fill.light_color = Color(1.0, 0.82, 0.60)
		fill.light_energy = float(entry[1])
		fill.omni_range = float(entry[2])
		fill.shadow_enabled = false
		add_child(fill)

func _add_furniture(model_name: String, pos: Vector3, model_scale: float, rot_y: float = 0.0) -> Node3D:
	var path := "res://assets/free/kenney_furniture/%s.obj" % model_name
	if not ResourceLoader.exists(path):
		return null
	var mesh := load(path) as Mesh
	if mesh == null:
		return null
	var node := MeshInstance3D.new()
	node.name = "Furniture_" + model_name
	node.mesh = mesh
	node.position = pos
	node.scale = Vector3.ONE * model_scale
	node.rotation.y = deg_to_rad(rot_y)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_root.add_child(node)
	var aabb := mesh.get_aabb()
	# Soft contact shadow makes the imported mesh read as grounded even when
	# the procedural room light is too dim to show a real shadow.
	var contact := StandardMaterial3D.new()
	contact.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	contact.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	contact.albedo_color = Color(0.03, 0.02, 0.015, 0.26)
	contact.cull_mode = BaseMaterial3D.CULL_DISABLED
	contact.disable_receive_shadows = true
	var shadow_mesh := CylinderMesh.new()
	var sh_width := aabb.size.x * model_scale
	var sh_depth := aabb.size.z * model_scale
	var sh_radius := maxf(sh_width, sh_depth) * 0.52
	shadow_mesh.top_radius = sh_radius
	shadow_mesh.bottom_radius = sh_radius
	shadow_mesh.height = 0.012
	shadow_mesh.radial_segments = 16
	var shadow := MeshInstance3D.new()
	shadow.mesh = shadow_mesh
	shadow.material_override = contact
	shadow.position = pos + Vector3((aabb.position.x + aabb.size.x * 0.5) * model_scale, 0.034, (aabb.position.z + aabb.size.z * 0.5) * model_scale)
	shadow.scale = Vector3(sh_width / (2.0 * sh_radius), 1.0, sh_depth / (2.0 * sh_radius))
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root.add_child(shadow)
	# Solid collision so the puppet cannot walk through the imported furniture.
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	body.rotation.y = deg_to_rad(rot_y)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = aabb.size * model_scale
	shape.shape = box
	shape.position = (aabb.position + aabb.size * 0.5) * model_scale
	body.add_child(shape)
	_root.add_child(body)
	return node

func _add_bear_carving(pos: Vector3, scale_factor: float) -> void:
	var holder := Node3D.new()
	holder.position = pos
	holder.scale = Vector3.ONE * scale_factor
	_root.add_child(holder)
	_add_sphere_to(holder, 0.30, Vector3(0.0, 0.33, 0.0), wood())
	_add_sphere_to(holder, 0.20, Vector3(0.0, 0.67, 0.03), wood_light())
	for side in [-1.0, 1.0]:
		_add_sphere_to(holder, 0.075, Vector3(float(side) * 0.13, 0.83, 0.0), wood())
		_add_box_to(holder, Vector3(0.09, 0.24, 0.10), Vector3(float(side) * 0.15, 0.12, 0.0), wood_dark())
	_add_box_to(holder, Vector3(0.10, 0.06, 0.04), Vector3(0.0, 0.66, 0.22), wood_dark())

func _add_owl_carving(pos: Vector3, scale_factor: float) -> void:
	var holder := Node3D.new()
	holder.position = pos
	holder.scale = Vector3.ONE * scale_factor
	_root.add_child(holder)
	_add_sphere_to(holder, 0.20, Vector3(0.0, 0.20, 0.0), wood())
	_add_sphere_to(holder, 0.14, Vector3(0.0, 0.38, 0.02), wood_light())
	for side in [-1.0, 1.0]:
		_add_sphere_to(holder, 0.045, Vector3(float(side) * 0.07, 0.42, 0.16), Color(0.18, 0.12, 0.07))
		_add_box_to(holder, Vector3(0.08, 0.20, 0.08), Vector3(float(side) * 0.12, 0.26, 0.0), wood_dark())
	_add_box_to(holder, Vector3(0.09, 0.04, 0.06), Vector3(0.0, 0.34, 0.20), Color(0.80, 0.58, 0.24))

func _add_fish_carving(pos: Vector3, scale_factor: float) -> void:
	var holder := Node3D.new()
	holder.position = pos
	holder.scale = Vector3.ONE * scale_factor
	_root.add_child(holder)
	_add_sphere_to(holder, 0.16, Vector3(0.0, 0.16, 0.0), wood())
	var tail := _add_box_to(holder, Vector3(0.18, 0.22, 0.04), Vector3(0.24, 0.16, 0.0), wood_dark())
	tail.rotation.z = -0.35
	_add_sphere_to(holder, 0.025, Vector3(-0.13, 0.20, 0.11), Color(0.12, 0.08, 0.05))
	_add_box_to(holder, Vector3(0.06, 0.025, 0.02), Vector3(-0.12, 0.12, 0.10), wood_dark())

func _add_bird_carving(pos: Vector3, scale_factor: float) -> void:
	var holder := Node3D.new()
	holder.position = pos
	holder.scale = Vector3.ONE * scale_factor
	_root.add_child(holder)
	_add_sphere_to(holder, 0.15, Vector3(0.0, 0.18, 0.0), wood())
	_add_sphere_to(holder, 0.09, Vector3(0.16, 0.28, 0.0), wood_light())
	for side in [-1.0, 1.0]:
		var wing := _add_box_to(holder, Vector3(0.28, 0.04, 0.16), Vector3(0.0, 0.14, float(side) * 0.10), wood_dark())
		wing.rotation.z = 0.15 * side
	_add_box_to(holder, Vector3(0.10, 0.025, 0.025), Vector3(0.26, 0.29, 0.0), Color(0.78, 0.56, 0.24))

func _add_face_carving(pos: Vector3, scale_factor: float) -> void:
	var holder := Node3D.new()
	holder.position = pos
	holder.scale = Vector3.ONE * scale_factor
	_root.add_child(holder)
	_add_box_to(holder, Vector3(0.38, 0.50, 0.12), Vector3(0.0, 0.28, 0.0), wood())
	_add_sphere_to(holder, 0.06, Vector3(-0.10, 0.33, 0.08), Color(0.08, 0.05, 0.03))
	_add_sphere_to(holder, 0.06, Vector3(0.10, 0.33, 0.08), Color(0.08, 0.05, 0.03))
	_add_box_to(holder, Vector3(0.14, 0.04, 0.05), Vector3(0.0, 0.20, 0.08), Color(0.08, 0.05, 0.03))
	_add_box_to(holder, Vector3(0.26, 0.04, 0.03), Vector3(0.0, 0.43, 0.08), wood_dark())

func _add_relief_panel(pos: Vector3, variant: int) -> void:
	_add_box(Vector3(0.32, 0.52, 0.06), pos, wood())
	for i in 3:
		var size := Vector3(0.18, 0.035, 0.04)
		var offset := Vector3(float(i - 1) * 0.09, 0.10 + float(i % 2) * 0.16, 0.05)
		_add_box(size, pos + offset, wood_dark())

func _add_chair(pos: Vector3, rot_y: float) -> void:
	var holder := Node3D.new()
	holder.position = pos
	holder.rotation.y = rot_y
	_root.add_child(holder)
	_add_box_to(holder, Vector3(0.62, 0.09, 0.55), Vector3(0.0, 0.50, 0.0), wood_light())
	for lx in [-0.24, 0.24]:
		_add_box_to(holder, Vector3(0.07, 0.48, 0.07), Vector3(lx, 0.25, -0.20), wood_dark())
		_add_box_to(holder, Vector3(0.07, 0.48, 0.07), Vector3(lx, 0.25, 0.20), wood_dark())
	_add_box_to(holder, Vector3(0.62, 0.55, 0.07), Vector3(0.0, 0.78, -0.26), wood())
	_add_heart_to(holder, Vector3(0.0, 0.82, -0.31), 0.08, wood_dark())

func _add_heart(pos: Vector3, size: float, colour: Color) -> void:
	var holder := Node3D.new()
	holder.position = pos
	_root.add_child(holder)
	_add_heart_to(holder, Vector3.ZERO, size, colour)

func _add_heart_to(parent: Node3D, pos: Vector3, size: float, colour: Color) -> void:
	_add_sphere_to(parent, size, pos + Vector3(-size * 0.55, size * 0.45, 0.0), colour)
	_add_sphere_to(parent, size, pos + Vector3(size * 0.55, size * 0.45, 0.0), colour)
	var point := _add_box_to(parent, Vector3(size * 1.55, size * 1.55, size * 0.8), pos + Vector3(0.0, -size * 0.1, 0.0), colour)
	point.rotation.z = PI * 0.25

func wood() -> Color:
	return Color(0.56, 0.37, 0.21)

func wood_light() -> Color:
	return Color(0.70, 0.50, 0.30)

func wood_dark() -> Color:
	return Color(0.31, 0.20, 0.12)

func _mat(colour: Color, emissive: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.roughness = 0.92
	if emissive:
		material.emission_enabled = true
		material.emission = colour
		material.emission_energy_multiplier = 0.8
	return material

func _add_box(size: Vector3, pos: Vector3, colour: Color, rot: Vector3 = Vector3.ZERO, emissive: bool = false) -> MeshInstance3D:
	return _add_mesh(_root, size, pos, colour, rot, emissive)

func _add_box_to(parent: Node3D, size: Vector3, pos: Vector3, colour: Color, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	return _add_mesh(parent, size, pos, colour, rot, false)

func _add_mesh(parent: Node3D, size: Vector3, pos: Vector3, colour: Color, rot: Vector3, emissive: bool) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	node.rotation_degrees = rot
	node.material_override = _mat(colour, emissive)
	parent.add_child(node)
	return node

func _add_cylinder(top: float, bottom: float, height: float, pos: Vector3, colour: Color, segments: int = 10) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = segments
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	node.material_override = _mat(colour)
	_root.add_child(node)
	return node

func _add_sphere(radius: float, pos: Vector3, colour: Color) -> MeshInstance3D:
	return _add_sphere_to(_root, radius, pos, colour)

func _add_sphere_to(parent: Node3D, radius: float, pos: Vector3, colour: Color) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 10
	mesh.rings = 6
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	node.material_override = _mat(colour)
	parent.add_child(node)
	return node

func _add_static_box(pos: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = pos
	add_child(body)
