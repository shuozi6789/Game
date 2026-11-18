extends Control
## Small hand-drawn pixel loading charm: a pulsing heart with orbiting dust.

var _time := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(72.0, 72.0)
	set_process(true)

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _draw() -> void:
	var c := size * 0.5
	var pulse := 1.0 + 0.06 * sin(_time * 3.4)
	var ink := Color(0.98, 0.92, 0.78, 1.0)
	var glow := Color(1.0, 0.82, 0.48, 0.45)
	# orbiting crumbs
	for i in 8:
		var a := _time * 1.9 + TAU * float(i) / 8.0
		var r := 26.0 + sin(_time * 2.0 + float(i)) * 2.0
		var alpha := 0.18 + 0.55 * maxf(0.0, sin(a - _time * 0.4))
		draw_circle(c + Vector2(cos(a) * r, sin(a) * r), 1.7, Color(1.0, 0.88, 0.62, alpha))
	# heart body (two lobes + triangle)
	var heart_c := c + Vector2(0.0, -2.0)
	draw_circle(heart_c + Vector2(-5.2, -3.2), 6.2 * pulse, ink)
	draw_circle(heart_c + Vector2(5.2, -3.2), 6.2 * pulse, ink)
	var tri := PackedVector2Array([
		heart_c + Vector2(-10.8, 0.0),
		heart_c + Vector2(10.8, 0.0),
		heart_c + Vector2(0.0, 12.2 * pulse),
	])
	draw_colored_polygon(tri, ink)
	draw_circle(heart_c + Vector2(-3.5, -3.5), 1.8, Color(1.0, 0.96, 0.84, 0.8))
	# soft halo
	draw_circle(heart_c, 22.0, Color(glow.r, glow.g, glow.b, 0.06))
