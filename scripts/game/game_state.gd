extends Node
## Global state for one playthrough of the narrative walk.
##
## The game is a straight line of 8 segments. Five of them hold one NPC each;
## talking to an NPC ends with a binary choice 「我是这样的人」/「我不是这样的人」.
## Choosing "yes" mixes that NPC's colour into the hero (equal weight per NPC),
## choosing "no" leaves the hero unchanged. The ending is decided by the SET of
## colours the player accepted.

signal color_changed(mixed: Color)
signal segment_changed(index: int)
signal run_reset()
signal item_added(item_id: String)

const TOTAL_SEGMENTS := 11
const COLOR_ORDER := ["red", "yellow", "green", "blue", "purple", "orange", "teal", "pink"]

var segment_index: int = 0
## Entries: { "id": String, "color": Color } in the order they were accepted.
var chosen: Array[Dictionary] = []
## Entries: { "id": String, "name": String, "color": Color, "took": bool }.
var met: Array[Dictionary] = []
## Item ids granted by the NPCs, in the order they were received.
var items: Array[String] = []
## Blocks player movement while a dialogue is open.
var dialogue_active: bool = false
## Blocks player movement during dialogues AND segment transitions.
var control_locked: bool = false
## Set by the opening vision scene; main.tscn starts the walk immediately.
var begin_journey_on_main: bool = false

func reset() -> void:
	segment_index = 0
	chosen.clear()
	met.clear()
	items.clear()
	dialogue_active = false
	run_reset.emit()
	color_changed.emit(mixed_color())

func has_color(id: String) -> bool:
	for entry in chosen:
		if entry["id"] == id:
			return true
	return false

func took_any() -> bool:
	return not chosen.is_empty()

func record_met(id: String, display_name: String, color: Color, took: bool) -> void:
	met.append({"id": id, "name": display_name, "color": color, "took": took})

func has_item(item_id: String) -> bool:
	return item_id in items

func add_item(item_id: String) -> bool:
	if item_id == "" or has_item(item_id):
		return false
	items.append(item_id)
	item_added.emit(item_id)
	return true

func set_items(ids: Array) -> void:
	items.clear()
	for id in ids:
		var text := str(id)
		if text != "" and not has_item(text):
			items.append(text)

func item_ids() -> Array:
	return items.duplicate()

func dye(id: String, color: Color) -> void:
	if has_color(id):
		return
	chosen.append({"id": id, "color": color})
	color_changed.emit(mixed_color())

func color_ids() -> Array:
	var ids: Array = []
	for entry in chosen:
		ids.append(entry["id"])
	return ids

## Equal-weight perceptual mix (Oklab) so several colours blend into something
## readable instead of turning into grey mud. Pure white when nothing taken.
func mixed_color() -> Color:
	if chosen.is_empty():
		return Color(1.0, 1.0, 1.0, 1.0)
	var l := 0.0
	var a := 0.0
	var b := 0.0
	for entry in chosen:
		var lab := _rgb_to_oklab(entry["color"] as Color)
		l += lab.x
		a += lab.y
		b += lab.z
	var n := float(chosen.size())
	return _oklab_to_rgb(Vector3(l / n, a / n, b / n))

## "white" | "single_red" | "pair_red_blue" | "multi_3" .. "multi_5"
func ending_key() -> String:
	var ids := color_ids()
	if ids.is_empty():
		return "white"
	if ids.size() == 1:
		return "single_%s" % ids[0]
	if ids.size() == 2:
		var pair: Array = ids.duplicate()
		pair.sort_custom(func(x, y): return COLOR_ORDER.find(x) < COLOR_ORDER.find(y))
		return "pair_%s_%s" % [pair[0], pair[1]]
	return "multi_%d" % ids.size()

# --- Oklab (Björn Ottosson) ------------------------------------------------

func _srgb_to_linear(c: float) -> float:
	if c <= 0.04045:
		return c / 12.92
	return pow((c + 0.055) / 1.055, 2.4)

func _linear_to_srgb(c: float) -> float:
	if c <= 0.0031308:
		return c * 12.92
	return 1.055 * pow(c, 1.0 / 2.4) - 0.055

func _rgb_to_oklab(color: Color) -> Vector3:
	var r := _srgb_to_linear(color.r)
	var g := _srgb_to_linear(color.g)
	var b := _srgb_to_linear(color.b)
	var l := 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
	var m := 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
	var s := 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
	l = signf(l) * pow(absf(l), 1.0 / 3.0)
	m = signf(m) * pow(absf(m), 1.0 / 3.0)
	s = signf(s) * pow(absf(s), 1.0 / 3.0)
	return Vector3(
		0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
		1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
		0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
	)

func _oklab_to_rgb(lab: Vector3) -> Color:
	var l_ := lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z
	var m_ := lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z
	var s_ := lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z
	l_ = l_ * l_ * l_
	m_ = m_ * m_ * m_
	s_ = s_ * s_ * s_
	var r := 4.0767416621 * l_ - 3.3077115913 * m_ + 0.2309699292 * s_
	var g := -1.2684380046 * l_ + 2.6097574011 * m_ - 0.3413193965 * s_
	var b := -0.0041960863 * l_ - 0.7034186147 * m_ + 1.7076147010 * s_
	return Color(
		clampf(_linear_to_srgb(r), 0.0, 1.0),
		clampf(_linear_to_srgb(g), 0.0, 1.0),
		clampf(_linear_to_srgb(b), 0.0, 1.0),
		1.0
	)
