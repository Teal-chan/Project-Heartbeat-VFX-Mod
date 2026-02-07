# Manages a playlist of media items with save/load functionality
extends RefCounted

const MediaItem = preload("res://menus/media_player/HBMediaItem.gd")

signal playlist_changed
signal item_added(item)
signal item_removed(item)

const PLAYLIST_SAVE_PATH = "user://media_playlists/"
const DEFAULT_PLAYLIST_NAME = "default"

var name: String = DEFAULT_PLAYLIST_NAME
var items: Array = []
var current_index: int = -1

enum ShuffleMode {
	OFF,
	ON
}

enum RepeatMode {
	OFF,
	ONE,
	ALL
}

var shuffle_mode: int = ShuffleMode.OFF
var repeat_mode: int = RepeatMode.OFF

# For shuffle - stores the randomized order
var _shuffle_order: Array = []
var _shuffle_index: int = 0


func _init(playlist_name: String = DEFAULT_PLAYLIST_NAME):
	name = playlist_name


# Add a media item to the playlist
func add_item(item) -> void:
	# Check for duplicates by ID
	for existing in items:
		if existing.id == item.id:
			return
	
	items.append(item)
	_rebuild_shuffle_order()
	emit_signal("item_added", item)
	emit_signal("playlist_changed")


# Add multiple items at once
func add_items(new_items: Array) -> void:
	for item in new_items:
		var is_duplicate = false
		for existing in items:
			if existing.id == item.id:
				is_duplicate = true
				break
		if not is_duplicate:
			items.append(item)
			emit_signal("item_added", item)
	
	_rebuild_shuffle_order()
	emit_signal("playlist_changed")


# Remove an item from the playlist
func remove_item(item) -> void:
	var idx = items.find(item)
	if idx != -1:
		items.remove_at(idx)
		
		# Adjust current_index if needed
		if current_index >= items.size():
			current_index = items.size() - 1
		elif idx < current_index:
			current_index -= 1
		
		_rebuild_shuffle_order()
		emit_signal("item_removed", item)
		emit_signal("playlist_changed")


# Remove item by index
func remove_at(index: int) -> void:
	if index >= 0 and index < items.size():
		var item = items[index]
		remove_item(item)


# Clear all items
func clear() -> void:
	items.clear()
	current_index = -1
	_shuffle_order.clear()
	_shuffle_index = 0
	emit_signal("playlist_changed")


# Move an item within the playlist
func move_item(from_index: int, to_index: int) -> void:
	if from_index < 0 or from_index >= items.size():
		return
	if to_index < 0 or to_index >= items.size():
		return
	if from_index == to_index:
		return
	
	var item = items[from_index]
	items.remove_at(from_index)
	items.insert(to_index, item)
	
	# Adjust current_index
	if current_index == from_index:
		current_index = to_index
	elif from_index < current_index and to_index >= current_index:
		current_index -= 1
	elif from_index > current_index and to_index <= current_index:
		current_index += 1
	
	emit_signal("playlist_changed")


# Get current item
func get_current():
	if current_index >= 0 and current_index < items.size():
		return items[current_index]
	return null


# Set current item by index
func set_current(index: int):
	if index >= 0 and index < items.size():
		current_index = index
		if shuffle_mode == ShuffleMode.ON:
			_shuffle_index = _shuffle_order.find(index)
		return items[current_index]
	return null


# Get next item based on shuffle/repeat settings
func get_next():
	if items.is_empty():
		return null
	
	if repeat_mode == RepeatMode.ONE:
		return get_current()
	
	var next_index: int
	
	if shuffle_mode == ShuffleMode.ON:
		_shuffle_index += 1
		if _shuffle_index >= _shuffle_order.size():
			if repeat_mode == RepeatMode.ALL:
				_rebuild_shuffle_order()
				_shuffle_index = 0
			else:
				return null
		next_index = _shuffle_order[_shuffle_index]
	else:
		next_index = current_index + 1
		if next_index >= items.size():
			if repeat_mode == RepeatMode.ALL:
				next_index = 0
			else:
				return null
	
	current_index = next_index
	return items[current_index]


# Get previous item
func get_previous():
	if items.is_empty():
		return null
	
	if repeat_mode == RepeatMode.ONE:
		return get_current()
	
	var prev_index: int
	
	if shuffle_mode == ShuffleMode.ON:
		_shuffle_index -= 1
		if _shuffle_index < 0:
			if repeat_mode == RepeatMode.ALL:
				_shuffle_index = _shuffle_order.size() - 1
			else:
				_shuffle_index = 0
				return null
		prev_index = _shuffle_order[_shuffle_index]
	else:
		prev_index = current_index - 1
		if prev_index < 0:
			if repeat_mode == RepeatMode.ALL:
				prev_index = items.size() - 1
			else:
				return null
	
	current_index = prev_index
	return items[current_index]


# Toggle shuffle mode
func toggle_shuffle() -> int:
	if shuffle_mode == ShuffleMode.OFF:
		shuffle_mode = ShuffleMode.ON
		_rebuild_shuffle_order()
	else:
		shuffle_mode = ShuffleMode.OFF
	return shuffle_mode


# Cycle repeat mode
func cycle_repeat() -> int:
	match repeat_mode:
		RepeatMode.OFF:
			repeat_mode = RepeatMode.ALL
		RepeatMode.ALL:
			repeat_mode = RepeatMode.ONE
		RepeatMode.ONE:
			repeat_mode = RepeatMode.OFF
	return repeat_mode


# Rebuild shuffle order
func _rebuild_shuffle_order() -> void:
	_shuffle_order.clear()
	for i in range(items.size()):
		_shuffle_order.append(i)
	_shuffle_order.shuffle()
	
	# Make sure current song is at current position in shuffle
	if current_index >= 0 and current_index < items.size():
		var pos = _shuffle_order.find(current_index)
		if pos != -1 and pos != _shuffle_index:
			_shuffle_order.remove_at(pos)
			_shuffle_order.insert(_shuffle_index, current_index)


# Get total duration of playlist
func get_total_duration() -> float:
	var total: float = 0.0
	for item in items:
		total += item.duration
	return total


# Save playlist to disk
func save() -> int:
	DirAccess.make_dir_recursive_absolute(PLAYLIST_SAVE_PATH)
	
	var save_path = PLAYLIST_SAVE_PATH.path_join(name + ".json")
	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if not file:
		return FileAccess.get_open_error()
	
	var data = {
		"name": name,
		"shuffle_mode": shuffle_mode,
		"repeat_mode": repeat_mode,
		"current_index": current_index,
		"items": []
	}
	
	for item in items:
		data["items"].append(item.serialize())
	
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	
	return OK


# Load playlist from disk
static func load_playlist(playlist_name: String):
	var load_path = PLAYLIST_SAVE_PATH.path_join(playlist_name + ".json")
	
	var script = load("res://menus/media_player/HBMediaPlaylist.gd")
	
	if not FileAccess.file_exists(load_path):
		print("[MediaPlaylist] No saved playlist found, creating new")
		return script.new(playlist_name)
	
	var file = FileAccess.open(load_path, FileAccess.READ)
	if not file:
		print("[MediaPlaylist] Could not open playlist file")
		return script.new(playlist_name)
	
	var json = JSON.new()
	var error = json.parse(file.get_as_text())
	file.close()
	
	if error != OK:
		print("[MediaPlaylist] JSON parse error: ", json.get_error_message())
		return script.new(playlist_name)
	
	var data = json.data
	if not data is Dictionary:
		print("[MediaPlaylist] Invalid playlist data format")
		return script.new(playlist_name)
	
	var playlist = script.new(data.get("name", playlist_name))
	playlist.shuffle_mode = data.get("shuffle_mode", ShuffleMode.OFF)
	playlist.repeat_mode = data.get("repeat_mode", RepeatMode.OFF)
	playlist.current_index = data.get("current_index", -1)
	
	var item_script = load("res://menus/media_player/HBMediaItem.gd")
	for item_data in data.get("items", []):
		if not item_data is Dictionary:
			continue
		var item = item_script.new()
		# Manually load fields to avoid HBSerializable type lookup issues
		item.title = item_data.get("title", "")
		item.artist = item_data.get("artist", "")
		item.album = item_data.get("album", "")
		item.audio_path = item_data.get("audio_path", "")
		item.thumbnail_path = item_data.get("thumbnail_path", "")
		item.volume = item_data.get("volume", 1.0)
		item.has_audio_loudness = item_data.get("has_audio_loudness", false)
		item.audio_loudness = item_data.get("audio_loudness", 0.0)
		item.duration = item_data.get("duration", 0.0)
		item.last_position = item_data.get("last_position", 0.0)
		item.date_added = item_data.get("date_added", 0)
		item.play_count = item_data.get("play_count", 0)
		item.id = item_data.get("id", "")
		
		if item.is_valid():
			playlist.items.append(item)
	
	print("[MediaPlaylist] Loaded ", playlist.items.size(), " items")
	
	# Validate current_index
	if playlist.current_index >= playlist.items.size():
		playlist.current_index = playlist.items.size() - 1
	
	playlist._rebuild_shuffle_order()
	
	return playlist


# Get list of available playlists
static func get_available_playlists() -> Array:
	var playlists: Array = []
	
	if not DirAccess.dir_exists_absolute(PLAYLIST_SAVE_PATH):
		return playlists
	
	var dir = DirAccess.open(PLAYLIST_SAVE_PATH)
	if dir:
		dir.list_dir_begin()
		var filename = dir.get_next()
		while filename != "":
			if not dir.current_is_dir() and filename.ends_with(".json"):
				playlists.append(filename.get_basename())
			filename = dir.get_next()
		dir.list_dir_end()
	
	return playlists
