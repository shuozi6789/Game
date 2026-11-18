extends Node
func _ready() -> void:
	var house: Node3D = load("res://scenes/vision/carpenter_house.tscn").instantiate()
	add_child(house)
	await get_tree().create_timer(0.2).timeout
	_dump(house)
	get_tree().quit()
func _dump(n: Node) -> void:
	if n is MeshInstance3D and str(n.name).begins_with("Furniture_"):
		var mi := n as MeshInstance3D
		var xf := mi.global_transform
		var aabb := xf * mi.mesh.get_aabb()
		print("[furn] ", n.name, " min_y=", aabb.position.y, " top=", aabb.position.y + aabb.size.y)
	for c in n.get_children(): _dump(c)
