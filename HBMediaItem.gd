# Lightweight data class for imported media files in the Media Player
# Audio-only playback for imported songs
extends HBSerializable

# Core metadata
var title: String = ""
var artist: String = ""
var album: String = ""

# File path
var audio_path: String = ""
var thumbnail_path: String = ""  # Optional - preview image

# Playback settings
var volume: float = 1.0
var has_audio_loudness: bool = false
var audio_loudness: float = 0.0

# Timestamps (in seconds)
var duration: float = 0.0
var last_position: float = 0.0  # Resume support

# Metadata
var date_added: int = 0  # Unix timestamp
var play_count: int = 0

# Unique identifier (generated from path hash)
var id: String = ""


func _init():
	serializable_fields += [
		"title", "artist", "album",
		"audio_path", "thumbnail_path",
		"volume", "has_audio_loudness", "audio_loudness",
		"duration", "last_position",
		"date_added", "play_count", "id"
	]


func get_serialized_type():
	return "MediaItem"


# Factory method to create from a file path
static func from_file(path: String):
	var script = load("res://menus/media_player/HBMediaItem.gd")
	var item = script.new()
	item.id = path.sha256_text().substr(0, 16)
	item.date_added = int(Time.get_unix_time_from_system())
	
	# Parse filename for basic metadata
	var filename = path.get_file().get_basename()
	
	# Try to parse "Artist - Title" format
	if " - " in filename:
		var parts = filename.split(" - ", true, 1)
		item.artist = parts[0].strip_edges()
		item.title = parts[1].strip_edges() if parts.size() > 1 else filename
	else:
		item.title = filename
	
	item.audio_path = path
	return item


# Get display title (falls back to filename if no title set)
func get_display_title() -> String:
	if title != "":
		return title
	return audio_path.get_file().get_basename()


# Get display artist (falls back to "Unknown Artist")
func get_display_artist() -> String:
	if artist != "":
		return artist
	return "Unknown Artist"


# Get volume in dB
func get_volume_db() -> float:
	return linear_to_db(volume)


# Increment play count
func mark_played():
	play_count += 1


# Check if the media file still exists
func is_valid() -> bool:
	return audio_path != "" and FileAccess.file_exists(audio_path)
