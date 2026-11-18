extends Control
## Heart-shaped transparent glass charm ("流麻") shown in the top-left HUD.
##
## The hero itself stays the white box-man. The charm is a glass heart: a
## neutral silver rim + highlights over a semi-transparent liquid. Taking a
## colour swirls that colour into the liquid and mixes it with what is already
## there. The pendant swings on a spring while walking, and silver glitter
## specks slosh around inside the heart mask.

const HEART_RADIUS := 26.0
const GLINT_COUNT := 18
const LIQUID_SHADER_PATH := "res://shaders/ui/charm_liquid.gdshader"
const INITIAL_LIQUID := Color(0.965, 0.955, 0.925, 1.0)

var _player: CharacterBody3D
var _pendant: Control
var _heart_liquid: TextureRect
var _heart_glass: TextureRect
var _liquid_material: ShaderMaterial
var _mask: Image
var _mask_texture: ImageTexture
var _glints: Array[Dictionary] = []
var _glint_texture: Texture2D
var _mix_tween: Tween

var _time: float = 0.0
var _active: bool = false
var _base_y: float = 12.0
var _last_velocity := Vector2.ZERO
var _slosh := Vector2.ZERO
var _slosh_strength: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(70.0, 82.0)
	_glint_texture = _make_sparkle_texture()
	_build()
	hide()

func set_player(node: CharacterBody3D) -> void:
	_player = node

func set_active(value: bool) -> void:
	_active = value
	visible = value
	if not value:
		_slosh = Vector2.ZERO
		_slosh_strength = 0.0
		# Keep the glass still; only the contents move.
		_pendant.rotation = 0.0
		_pendant.position = Vector2(3.0, _base_y)

func set_color_instant(color: Color) -> void:
	if _mix_tween != null and _mix_tween.is_valid():
		_mix_tween.kill()
	if _liquid_material == null:
		return
	_liquid_material.set_shader_parameter("base_color", color)
	_liquid_material.set_shader_parameter("incoming_color", color)
	_liquid_material.set_shader_parameter("mix_amount", 0.0)

func animate_color(color: Color) -> void:
	if _liquid_material == null:
		return
	if _mix_tween != null and _mix_tween.is_valid():
		_mix_tween.kill()
	# Keep the old liquid as the base and swirl the new mixed colour into it.
	_liquid_material.set_shader_parameter("incoming_color", color)
	_liquid_material.set_shader_parameter("mix_amount", 0.0)
	_mix_tween = create_tween()
	_mix_tween.tween_method(_set_mix_amount, 0.0, 1.0, 1.15)
	_mix_tween.tween_callback(func() -> void:
		_liquid_material.set_shader_parameter("base_color", color)
		_liquid_material.set_shader_parameter("incoming_color", color)
		_liquid_material.set_shader_parameter("mix_amount", 0.0)
	)
	pulse()

func _set_mix_amount(value: float) -> void:
	if _liquid_material != null:
		_liquid_material.set_shader_parameter("mix_amount", value)

func pulse() -> void:
	# Colour feedback is a slosh of the contents, never a moving container.
	_slosh += Vector2(randf_range(-0.55, 0.55), randf_range(-0.20, 0.20))
	_slosh_strength = maxf(_slosh_strength, 0.95)

func _process(delta: float) -> void:
	if not _active:
		return
	_time += delta
	if _liquid_material != null:
		_liquid_material.set_shader_parameter("liquid_time", _time)
	# The glass container itself never swings; the liquid and sand inside get
	# jostled by the hero's acceleration and walking speed.
	var velocity := Vector2.ZERO
	if _player != null:
		velocity = Vector2(_player.velocity.x, _player.velocity.z)
	var acceleration := (velocity - _last_velocity) / maxf(delta, 0.0001)
	_last_velocity = velocity

	var target_slosh := (acceleration.limit_length(22.0) / 22.0) * 0.9
	target_slosh += (velocity.limit_length(6.8) / 6.8) * 0.25
	_slosh = _slosh.lerp(target_slosh, 1.0 - exp(-7.0 * delta))
	var target_strength := clampf(velocity.length() / 4.5 + acceleration.length() * 0.06, 0.0, 1.0)
	_slosh_strength = lerpf(_slosh_strength, target_strength, 1.0 - exp(-6.0 * delta))

	if _liquid_material != null:
		_liquid_material.set_shader_parameter("slosh_dir", _slosh)
		_liquid_material.set_shader_parameter("slosh_strength", _slosh_strength)
		_liquid_material.set_shader_parameter("wave_time", _time)

	# Container stays put; no bob / no rotation.
	_pendant.rotation = 0.0
	_pendant.position = Vector2(3.0, _base_y)

	_update_glints(delta, acceleration, velocity)

func _update_glints(delta: float, acceleration: Vector2, velocity: Vector2) -> void:
	for entry in _glints:
		var node: TextureRect = entry["node"]
		var pos: Vector2 = entry["pos"]
		var vel: Vector2 = entry["vel"]
		var rel := pos - Vector2(32.0, 34.0)
		# Sand gets kicked opposite to the hero's acceleration, with a little
		# random jitter while walking so it keeps tumbling.
		vel -= (acceleration * 0.65).limit_length(180.0) * delta
		vel += _slosh * (55.0 * _slosh_strength) * delta
		vel += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * (18.0 * _slosh_strength) * delta
		vel += Vector2(-rel.y, rel.x) * 0.08 * delta * (0.6 + 0.4 * sin(_time * 1.7 + float(entry["phase"])))
		vel.y += 9.0 * delta
		vel *= exp(-1.8 * delta)
		pos += vel * delta
		var surface_y := _liquid_surface_y(pos.x) + 2.0
		if not _inside_heart(pos) or pos.y < surface_y:
			pos -= vel * delta
			vel = -vel * 0.35
			pos.y = maxf(pos.y, surface_y)
			pos = pos.lerp(Vector2(32.0, 36.0), 0.08)
		entry["pos"] = pos
		entry["vel"] = vel
		node.position = pos - node.size * 0.5
		node.modulate.a = clampf(0.55 + float(entry["alpha"]) + 0.25 * absf(sin(_time * 2.0 + float(entry["phase"]))), 0.0, 1.0)

func _liquid_surface_y(x: float) -> float:
	var nx := x / 64.0
	var slope := _slosh.x * 0.16 * _slosh_strength * (nx - 0.5)
	var ripple := sin(nx * 19.0 + _time * 5.0) * 0.030 * _slosh_strength
	return 64.0 * (0.30 + 0.020 * sin(nx * 13.0 + _time * 1.2) + 0.012 * sin(nx * 27.0 - _time * 0.9) + slope + ripple)

func _inside_heart(point: Vector2) -> bool:
	if _mask == null:
		return false
	var x := clampi(int(point.x), 0, _mask.get_width() - 1)
	var y := clampi(int(point.y), 0, _mask.get_height() - 1)
	return _mask.get_pixel(x, y).r > 0.5

# --- construction ---------------------------------------------------------

func _build() -> void:
	var chain := ColorRect.new()
	chain.position = Vector2(34.0, 0.0)
	chain.size = Vector2(1.0, 12.0)
	chain.color = Color(0.72, 0.74, 0.80, 0.95)
	chain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(chain)
	var ring := TextureRect.new()
	ring.texture = _make_ring_texture()
	ring.position = Vector2(28.0, 0.0)
	ring.size = Vector2(14.0, 10.0)
	ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ring.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ring)

	_pendant = Control.new()
	_pendant.position = Vector2(3.0, _base_y)
	_pendant.size = Vector2(64.0, 64.0)
	_pendant.pivot_offset = Vector2(32.0, 2.0)
	_pendant.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pendant)

	_mask_texture = _make_heart_mask_texture()

	# Liquid layer: the shader masks a heart and swirls the current mixture.
	_heart_liquid = TextureRect.new()
	_heart_liquid.position = Vector2.ZERO
	_heart_liquid.size = Vector2(64.0, 64.0)
	_heart_liquid.texture = _mask_texture
	_heart_liquid.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_heart_liquid.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_heart_liquid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := load(LIQUID_SHADER_PATH) as Shader
	_liquid_material = ShaderMaterial.new()
	_liquid_material.shader = shader
	_liquid_material.set_shader_parameter("mask_tex", _mask_texture)
	_liquid_material.set_shader_parameter("base_color", INITIAL_LIQUID)
	_liquid_material.set_shader_parameter("incoming_color", INITIAL_LIQUID)
	_liquid_material.set_shader_parameter("mix_amount", 0.0)
	_liquid_material.set_shader_parameter("liquid_alpha", 0.93)
	_liquid_material.set_shader_parameter("swirl_amount", 1.0)
	_heart_liquid.material = _liquid_material
	_pendant.add_child(_heart_liquid)

	# Silver glitter specks float between the liquid and the glass shell.
	for i in GLINT_COUNT:
		var glint := TextureRect.new()
		glint.texture = _glint_texture
		var size := 2.0 + float((i * 7) % 4)
		glint.size = Vector2(size, size)
		glint.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		glint.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		glint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pendant.add_child(glint)
		var pos := Vector2(randf_range(18.0, 46.0), randf_range(26.0, 48.0))
		while not _inside_heart(pos) or pos.y < _liquid_surface_y(pos.x) + 2.0:
			pos = Vector2(randf_range(18.0, 46.0), randf_range(26.0, 48.0))
		_glints.append({
			"node": glint,
			"pos": pos,
			"vel": Vector2(randf_range(-10.0, 10.0), randf_range(-6.0, 6.0)),
			"phase": randf() * TAU,
			"alpha": randf_range(0.0, 0.25),
		})

	# Transparent glass shell: neutral rim, inner reflection and specular streaks.
	_heart_glass = TextureRect.new()
	_heart_glass.position = Vector2.ZERO
	_heart_glass.size = Vector2(64.0, 64.0)
	_heart_glass.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_heart_glass.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_heart_glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_heart_glass.texture = _make_glass_texture()
	_pendant.add_child(_heart_glass)

# --- generated art --------------------------------------------------------

func _heart_inside(x: int, y: int) -> bool:
	var nx := (float(x) + 0.5 - 32.0) / HEART_RADIUS
	var ny := (32.0 - (float(y) + 0.5)) / HEART_RADIUS
	return pow(nx * nx + ny * ny - 1.0, 3.0) - nx * nx * ny * ny * ny <= 0.0

func _make_heart_mask_texture() -> ImageTexture:
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_L8)
	_mask = Image.create(size, size, false, Image.FORMAT_L8)
	var inside := PackedByteArray()
	inside.resize(size * size)
	for y in size:
		for x in size:
			if _heart_inside(x, y):
				inside[y * size + x] = 1
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, 1.0))
				_mask.set_pixel(x, y, Color(1.0, 1.0, 1.0, 1.0))
	return ImageTexture.create_from_image(img)

func _make_glass_texture() -> ImageTexture:
	var size := 64
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var inside := PackedByteArray()
	inside.resize(size * size)
	for y in size:
		for x in size:
			if _heart_inside(x, y):
				inside[y * size + x] = 1
	for y in size:
		for x in size:
			if inside[y * size + x] == 0:
				img.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))
				continue
			# Glass body is almost clear: only a faint milkiness so the liquid
			# inside still reads as being behind glass.
			var colour := Color(0.93, 0.97, 1.0, 0.055)
			var rim := false
			var inner_rim := false
			for oy in [-1, 0, 1]:
				for ox in [-1, 0, 1]:
					var nx2: int = int(x) + int(ox)
					var ny2: int = int(y) + int(oy)
					if nx2 < 0 or ny2 < 0 or nx2 >= size or ny2 >= size or inside[ny2 * size + nx2] == 0:
						rim = true
			for oy in [-2, 0, 2]:
				for ox in [-2, 0, 2]:
					var nx3: int = int(x) + int(ox)
					var ny3: int = int(y) + int(oy)
					if nx3 < 0 or ny3 < 0 or nx3 >= size or ny3 >= size or inside[ny3 * size + nx3] == 0:
						inner_rim = true
			if rim:
				img.set_pixel(x, y, Color(0.86, 0.90, 0.98, 0.96))
				continue
			if inner_rim:
				colour = Color(1.0, 1.0, 1.0, 0.30)
			# Glass reflections.
			var sx := (float(x) - 22.0) / 9.0
			var sy := (float(y) - 20.0) / 7.0
			if sx * sx + sy * sy < 1.0:
				colour = Color(1.0, 1.0, 1.0, 0.22)
			var streak := absf((float(x) - 18.0) - (34.0 - float(y)) * 0.75)
			if streak < 1.6 and float(y) < 38.0:
				colour = Color(1.0, 1.0, 1.0, 0.20)
			if float(y) > 52.0:
				colour = Color(0.82, 0.88, 0.98, 0.14)
			# A few fixed silver star sparkles read as liquid glitter at 1x.
			for spark in [Vector2i(23, 33), Vector2i(39, 27), Vector2i(30, 45), Vector2i(45, 40), Vector2i(35, 52)]:
				if absi(x - spark.x) <= 1 and y == spark.y:
					colour = Color(1.0, 1.0, 1.0, 0.88)
				elif x == spark.x and absi(y - spark.y) <= 1:
					colour = Color(0.88, 0.92, 1.0, 0.62)
			img.set_pixel(x, y, colour)
	return ImageTexture.create_from_image(img)

func _make_ring_texture() -> ImageTexture:
	var size := Vector2i(14, 10)
	var img := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	for y in size.y:
		for x in size.x:
			var nx := (float(x) + 0.5 - 7.0) / 7.0
			var ny := (float(y) + 0.5 - 5.0) / 5.0
			var d := nx * nx + ny * ny
			var ring := absf(d - 1.0) < 0.28
			img.set_pixel(x, y, Color(0.84, 0.86, 0.92, 1.0 if ring else 0.0))
	return ImageTexture.create_from_image(img)

func _make_sparkle_texture() -> ImageTexture:
	var img := Image.create(5, 5, false, Image.FORMAT_RGBA8)
	for y in 5:
		for x in 5:
			var dx := absf(float(x) - 2.0)
			var dy := absf(float(y) - 2.0)
			var alpha := 0.0
			var colour := Color(0.66, 0.72, 0.90, 1.0)
			if dx == 0.0 and dy == 0.0:
				alpha = 1.0
				colour = Color(1.0, 1.0, 1.0, 1.0)
			elif (dx == 0.0 and dy <= 2.0) or (dy == 0.0 and dx <= 2.0):
				alpha = 1.0
			elif dx + dy <= 2.0:
				alpha = 0.72
			img.set_pixel(x, y, Color(colour.r, colour.g, colour.b, alpha))
	return ImageTexture.create_from_image(img)
