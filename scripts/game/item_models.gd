class_name ItemModels
extends RefCounted
## Small low-poly meshes for the eight keepsakes. They are used by the
## backpack's 3D preview, so each item has an actual model rather than just an
## icon.

static func build(id: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Item_" + id
	match id:
		"red":
			_build_letter(root)
		"yellow":
			_build_watch(root)
		"green":
			_build_seed_packet(root)
		"blue":
			_build_lantern(root)
		"purple":
			_build_painting(root)
		"orange":
			_build_wooden_horse(root)
		"pink":
			_build_kite_spool(root)
		"teal":
			_build_bookmark(root)
		"creek_chime":
			_build_creek_chime(root)
		_:
			_build_letter(root)
	return root

static func _material(colour: Color, emissive: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 0.85
	mat.metallic = 0.0
	if emissive > 0.0:
		mat.emission_enabled = true
		mat.emission = colour
		mat.emission_energy_multiplier = emissive
	return mat

static func _add_box(parent: Node3D, size: Vector3, pos: Vector3, colour: Color,
		rot: Vector3 = Vector3.ZERO, emissive: float = 0.0) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _material(colour, emissive)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	node.rotation = rot
	parent.add_child(node)
	return node

static func _add_cyl(parent: Node3D, top: float, bottom: float, height: float,
		pos: Vector3, colour: Color, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 12
	mesh.material = _material(colour)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	node.rotation = rot
	parent.add_child(node)
	return node

static func _add_sphere(parent: Node3D, radius: float, pos: Vector3, colour: Color) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	mesh.material = _material(colour)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	parent.add_child(node)
	return node

static func _add_ring(parent: Node3D, inner: float, outer: float, pos: Vector3,
		colour: Color, rot: Vector3 = Vector3(90.0, 0.0, 0.0)) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 16
	mesh.ring_segments = 8
	mesh.material = _material(colour)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = pos
	node.rotation_degrees = rot
	parent.add_child(node)
	return node

static func _build_letter(root: Node3D) -> void:
	var paper := Color(0.92, 0.84, 0.68)
	var ink := Color(0.35, 0.24, 0.18)
	_add_box(root, Vector3(0.36, 0.025, 0.24), Vector3.ZERO, paper)
	_add_box(root, Vector3(0.34, 0.020, 0.10), Vector3(0.0, 0.016, 0.065), Color(0.97, 0.91, 0.77),
		Vector3(-16.0, 0.0, 0.0))
	_add_box(root, Vector3(0.035, 0.050, 0.035), Vector3(0.0, 0.005, -0.02),
		Color(0.72, 0.18, 0.16))
	_add_box(root, Vector3(0.13, 0.012, 0.16), Vector3(0.0, 0.022, 0.04), ink)
	_add_box(root, Vector3(0.22, 0.012, 0.012), Vector3(-0.03, 0.024, -0.02), ink,
		Vector3(0.0, 14.0, 0.0))
	_add_box(root, Vector3(0.18, 0.012, 0.012), Vector3(0.04, 0.024, 0.035), ink,
		Vector3(0.0, -8.0, 0.0))

static func _build_watch(root: Node3D) -> void:
	var brass := Color(0.80, 0.63, 0.28)
	var face := Color(0.95, 0.91, 0.80)
	_add_cyl(root, 0.135, 0.145, 0.045, Vector3.ZERO, brass, Vector3(90.0, 0.0, 0.0))
	_add_cyl(root, 0.112, 0.112, 0.050, Vector3(0.0, 0.0, 0.002), face, Vector3(90.0, 0.0, 0.0))
	_add_ring(root, 0.125, 0.145, Vector3(0.0, 0.0, 0.024), brass, Vector3.ZERO)
	_add_box(root, Vector3(0.018, 0.10, 0.012), Vector3(0.0, 0.035, 0.028), Color(0.20, 0.17, 0.14),
		Vector3(0.0, 0.0, 18.0))
	_add_box(root, Vector3(0.018, 0.075, 0.012), Vector3(0.035, -0.025, 0.028), Color(0.20, 0.17, 0.14),
		Vector3(0.0, 0.0, -65.0))
	_add_box(root, Vector3(0.055, 0.075, 0.035), Vector3(0.0, 0.17, 0.0), brass)
	_add_cyl(root, 0.012, 0.012, 0.07, Vector3(0.0, 0.245, 0.0), brass)
	_add_ring(root, 0.030, 0.052, Vector3(0.0, 0.29, 0.0), brass, Vector3.ZERO)

static func _build_seed_packet(root: Node3D) -> void:
	var paper := Color(0.88, 0.80, 0.63)
	var green := Color(0.35, 0.58, 0.28)
	_add_box(root, Vector3(0.26, 0.34, 0.035), Vector3.ZERO, paper,
		Vector3(0.0, 0.0, -4.0))
	_add_box(root, Vector3(0.22, 0.15, 0.040), Vector3(0.0, 0.04, 0.003), green,
		Vector3(0.0, 0.0, -4.0))
	_add_box(root, Vector3(0.13, 0.012, 0.045), Vector3(-0.01, 0.095, 0.004), Color(0.93, 0.89, 0.70),
		Vector3(0.0, 0.0, -4.0))
	for i in 5:
		_add_sphere(root, 0.020, Vector3(-0.06 + 0.035 * float(i), -0.10 + 0.025 * float(i % 3), 0.035),
			Color(0.58, 0.42, 0.24))
	_add_box(root, Vector3(0.24, 0.025, 0.045), Vector3(0.0, 0.16, 0.0),
		Color(0.70, 0.62, 0.46), Vector3(0.0, 0.0, -4.0))

static func _build_lantern(root: Node3D) -> void:
	var metal := Color(0.30, 0.32, 0.34)
	var glass := Color(0.98, 0.78, 0.38)
	_add_box(root, Vector3(0.20, 0.035, 0.20), Vector3(0.0, -0.16, 0.0), metal)
	_add_box(root, Vector3(0.20, 0.035, 0.20), Vector3(0.0, 0.16, 0.0), metal)
	for sx in [-0.09, 0.09]:
		for sz in [-0.09, 0.09]:
			_add_box(root, Vector3(0.025, 0.31, 0.025), Vector3(sx, 0.0, sz), metal)
	_add_box(root, Vector3(0.15, 0.25, 0.15), Vector3.ZERO, glass, Vector3.ZERO, 1.4)
	_add_cyl(root, 0.10, 0.13, 0.06, Vector3(0.0, 0.20, 0.0), metal)
	_add_ring(root, 0.045, 0.065, Vector3(0.0, 0.30, 0.0), metal, Vector3.ZERO)
	_add_sphere(root, 0.045, Vector3(0.0, -0.02, 0.0), Color(1.0, 0.72, 0.28))

static func _build_painting(root: Node3D) -> void:
	var wood := Color(0.45, 0.31, 0.20)
	var canvas := Color(0.95, 0.88, 0.72)
	_add_box(root, Vector3(0.40, 0.30, 0.025), Vector3.ZERO, wood)
	_add_box(root, Vector3(0.35, 0.25, 0.018), Vector3(0.0, 0.0, 0.016), canvas)
	_add_box(root, Vector3(0.30, 0.05, 0.010), Vector3(0.0, -0.065, 0.028), Color(0.88, 0.44, 0.34))
	_add_box(root, Vector3(0.26, 0.04, 0.010), Vector3(-0.01, 0.015, 0.028), Color(0.72, 0.48, 0.56))
	_add_box(root, Vector3(0.18, 0.035, 0.010), Vector3(-0.04, 0.075, 0.028), Color(0.95, 0.70, 0.46))
	_add_cyl(root, 0.012, 0.014, 0.30, Vector3(0.22, -0.02, 0.0), wood, Vector3(0.0, 0.0, 18.0))
	_add_box(root, Vector3(0.18, 0.018, 0.08), Vector3(0.15, -0.20, 0.0), wood,
		Vector3(0.0, 0.0, 18.0))

static func _build_wooden_horse(root: Node3D) -> void:
	var wood := Color(0.65, 0.44, 0.24)
	var dark := Color(0.40, 0.27, 0.15)
	_add_box(root, Vector3(0.28, 0.16, 0.13), Vector3(0.0, 0.0, 0.0), wood)
	_add_box(root, Vector3(0.13, 0.16, 0.13), Vector3(0.15, 0.09, 0.0), wood,
		Vector3(0.0, 0.0, -18.0))
	_add_box(root, Vector3(0.11, 0.08, 0.10), Vector3(0.24, 0.16, 0.0), dark,
		Vector3(0.0, 0.0, -18.0))
	for sx in [-0.10, 0.10]:
		for sz in [-0.035, 0.035]:
			_add_box(root, Vector3(0.042, 0.20, 0.042), Vector3(sx, -0.16, sz), dark)
	_add_box(root, Vector3(0.03, 0.16, 0.04), Vector3(-0.17, 0.02, 0.0), wood,
		Vector3(0.0, 0.0, 24.0))
	_add_box(root, Vector3(0.05, 0.08, 0.05), Vector3(0.20, 0.19, 0.0), wood)

static func _build_kite_spool(root: Node3D) -> void:
	var wood := Color(0.55, 0.38, 0.22)
	var pink := Color(0.92, 0.52, 0.60)
	_add_cyl(root, 0.13, 0.13, 0.20, Vector3.ZERO, wood, Vector3(90.0, 0.0, 0.0))
	_add_cyl(root, 0.16, 0.16, 0.035, Vector3(0.0, 0.0, 0.11), wood, Vector3(90.0, 0.0, 0.0))
	_add_cyl(root, 0.16, 0.16, 0.035, Vector3(0.0, 0.0, -0.11), wood, Vector3(90.0, 0.0, 0.0))
	for i in 5:
		_add_ring(root, 0.135, 0.155, Vector3(0.0, 0.0, -0.09 + 0.045 * float(i)),
			Color(0.86, 0.75, 0.54), Vector3.ZERO)
	_add_cyl(root, 0.018, 0.018, 0.42, Vector3(0.19, 0.06, 0.0), wood, Vector3(0.0, 0.0, 0.0))
	var kite := Node3D.new()
	kite.position = Vector3(0.30, 0.26, 0.0)
	kite.rotation_degrees = Vector3(0.0, 0.0, 45.0)
	root.add_child(kite)
	_add_box(kite, Vector3(0.18, 0.18, 0.012), Vector3.ZERO, pink, Vector3.ZERO, 0.15)
	_add_box(root, Vector3(0.30, 0.012, 0.012), Vector3(0.16, 0.05, 0.0),
		Color(0.55, 0.42, 0.26), Vector3(0.0, 0.0, 30.0))

static func _build_creek_chime(root: Node3D) -> void:
	var wood := Color(0.45, 0.32, 0.20)
	var stone := Color(0.48, 0.55, 0.50)
	var string_col := Color(0.84, 0.78, 0.62)
	_add_cyl(root, 0.025, 0.025, 0.30, Vector3(0.0, 0.16, 0.0), wood)
	_add_sphere(root, 0.055, Vector3(0.0, 0.32, 0.0), stone)
	for i in 3:
		var x := -0.16 + float(i) * 0.16
		_add_box(root, Vector3(0.015, 0.15, 0.015), Vector3(x, 0.02, 0.0), string_col)
		_add_cyl(root, 0.045, 0.030, 0.16, Vector3(x, -0.09, 0.0), stone if i % 2 == 0 else Color(0.55, 0.44, 0.30))
		_add_box(root, Vector3(0.10, 0.012, 0.10), Vector3(x, 0.09, 0.0), wood)
	_add_box(root, Vector3(0.48, 0.025, 0.08), Vector3(0.0, -0.23, 0.0), wood)

static func _build_bookmark(root: Node3D) -> void:
	var paper := Color(0.90, 0.84, 0.66)
	var teal := Color(0.32, 0.58, 0.55)
	_add_box(root, Vector3(0.10, 0.40, 0.018), Vector3.ZERO, paper)
	_add_box(root, Vector3(0.10, 0.08, 0.020), Vector3(0.0, 0.16, 0.001), teal)
	for i in 4:
		_add_box(root, Vector3(0.06, 0.012, 0.021), Vector3(0.0, 0.06 - 0.045 * float(i), 0.002),
			Color(0.38, 0.30, 0.22))
	_add_box(root, Vector3(0.07, 0.012, 0.024), Vector3(0.0, -0.14, 0.002), teal,
		Vector3(0.0, 0.0, 18.0))
	_add_box(root, Vector3(0.12, 0.012, 0.012), Vector3(0.0, -0.21, 0.0), Color(0.72, 0.24, 0.22),
		Vector3(0.0, 0.0, 8.0))
