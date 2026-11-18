class_name SaveSystem
## Persistent "where you stopped" state: JSON + one background screenshot.
##
## Writes into `user://save/` normally. In sandboxed/portable setups where the
## user data dir is not writable it falls back to `<project>/save/`, so the
## prototype keeps working when run from the project folder.

const VERSION := 1
const SAVE_JSON := "savegame.json"
const SAVE_PNG := "last_frame.png"
const SUBDIR := "save"

static var _resolved_dir := ""

static func save_dir() -> String:
	if _resolved_dir != "":
		return _resolved_dir
	var candidates := PackedStringArray()
	candidates.append(ProjectSettings.globalize_path("user://" + SUBDIR))
	candidates.append(ProjectSettings.globalize_path("res://" + SUBDIR))
	for candidate in candidates:
		if _is_writable(candidate):
			_resolved_dir = candidate
			# Keep Godot's importer out of the save folder (the fallback folder
			# lives inside the project, and screenshots must not be imported).
			var ignore := FileAccess.open(_resolved_dir.path_join(".gdignore"), FileAccess.WRITE)
			if ignore != null:
				ignore.store_string("")
				ignore.close()
			return _resolved_dir
	_resolved_dir = ""
	return ""

static func _is_writable(abs_dir: String) -> bool:
	if DirAccess.make_dir_recursive_absolute(abs_dir) != OK:
		return false
	var probe := abs_dir.path_join(".probe")
	var file := FileAccess.open(probe, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string("ok")
	file.close()
	DirAccess.remove_absolute(probe)
	return true

static func has_save() -> bool:
	var dir := save_dir()
	if dir == "":
		return false
	return FileAccess.file_exists(dir.path_join(SAVE_JSON)) \
		and FileAccess.file_exists(dir.path_join(SAVE_PNG))

static func write(payload: Dictionary, screenshot: Image) -> bool:
	var dir := save_dir()
	if dir == "":
		return false
	payload["version"] = VERSION
	payload["saved_at"] = int(Time.get_unix_time_from_system())
	var json := JSON.stringify(payload, "\t")
	var file := FileAccess.open(dir.path_join(SAVE_JSON), FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(json)
	file.close()
	if screenshot != null:
		screenshot.save_png(dir.path_join(SAVE_PNG))
	return true

static func read() -> Dictionary:
	var dir := save_dir()
	if dir == "":
		return {}
	var file := FileAccess.open(dir.path_join(SAVE_JSON), FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		var payload: Dictionary = parsed
		if int(payload.get("version", -1)) != VERSION:
			return {}
		return payload
	return {}

static func read_screenshot() -> Texture2D:
	var dir := save_dir()
	if dir == "":
		return null
	var path := dir.path_join(SAVE_PNG)
	if not FileAccess.file_exists(path):
		return null
	var image := Image.load_from_file(path)
	if image == null:
		return null
	return ImageTexture.create_from_image(image)

static func clear() -> void:
	var dir := save_dir()
	if dir == "":
		return
	DirAccess.remove_absolute(dir.path_join(SAVE_JSON))
	DirAccess.remove_absolute(dir.path_join(SAVE_PNG))
