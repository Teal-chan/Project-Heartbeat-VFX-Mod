# Core playback controller for the Media Player
# Audio-only playback via Shinobu
extends Node

const MediaItem = preload("res://menus/media_player/HBMediaItem.gd")

signal playback_started(item)
signal playback_paused
signal playback_resumed
signal playback_stopped
signal playback_finished  # Natural end of track
signal position_changed(position: float, duration: float)
signal volume_changed(volume: float)
signal media_loaded(item)
signal media_load_failed(item, error: String)

enum State {
	STOPPED,
	LOADING,
	PLAYING,
	PAUSED
}

var state: int = State.STOPPED
var current_item

# Audio playback via Shinobu
var _audio_player  # ShinobuSoundPlayer
var _shinobu_source  # ShinobuSoundSource
var _audio_stream: AudioStream

# Position tracking
var _last_reported_position: float = 0.0
const POSITION_UPDATE_INTERVAL = 0.05  # Update every 50ms


func _ready():
	set_process(false)


func _process(delta: float):
	if state == State.PLAYING and _audio_player:
		var current_pos = _audio_player.get_playback_position_msec() / 1000.0
		var duration = _audio_player.get_length_msec() / 1000.0
		
		# Check if audio finished
		if _audio_player.is_at_stream_end():
			_on_playback_finished()
			return
		
		# Only emit if position changed meaningfully
		if abs(current_pos - _last_reported_position) >= POSITION_UPDATE_INTERVAL:
			_last_reported_position = current_pos
			emit_signal("position_changed", current_pos, duration)
			
			# Update the item's last_position for resume support
			if current_item:
				current_item.last_position = current_pos


# Load and play a media item
func play(item) -> void:
	if not item or not item.is_valid():
		emit_signal("media_load_failed", item, "Invalid media item or file not found")
		return
	
	# Stop current playback first
	stop()
	
	current_item = item
	state = State.LOADING
	
	_load_audio(item)


# Internal: Load audio file
func _load_audio(item) -> void:
	var audio_path = item.audio_path
	var extension = audio_path.get_extension().to_lower()
	
	print("[MediaPlayer] Loading audio via Shinobu: ", audio_path)
	
	var sound_source = null
	var stream: AudioStream = null
	
	if extension == "ogg":
		# Load OGG - PHNative stores raw data in metadata
		stream = PHNative.load_ogg_from_file(audio_path)
		if stream and stream.has_meta("raw_file_data"):
			var raw_data = stream.get_meta("raw_file_data")
			sound_source = Shinobu.register_sound_from_memory("media_player_" + item.id, raw_data)
	elif extension == "wav":
		# For WAV, read raw file data directly
		var file = FileAccess.open(audio_path, FileAccess.READ)
		if file:
			var raw_data = file.get_buffer(file.get_length())
			file.close()
			sound_source = Shinobu.register_sound_from_memory("media_player_" + item.id, raw_data)
			stream = HBUtils.load_wav(audio_path)  # For duration info
	elif extension == "mp3":
		# For MP3, read raw file data
		var file = FileAccess.open(audio_path, FileAccess.READ)
		if file:
			var raw_data = file.get_buffer(file.get_length())
			file.close()
			sound_source = Shinobu.register_sound_from_memory("media_player_" + item.id, raw_data)
			# Also create stream for duration
			var mp3_stream = AudioStreamMP3.new()
			mp3_stream.data = raw_data
			stream = mp3_stream
	
	if not sound_source:
		print("[MediaPlayer] Failed to create Shinobu sound source")
		state = State.STOPPED
		emit_signal("media_load_failed", item, "Failed to load audio file: " + audio_path)
		return
	
	_setup_audio_playback(sound_source, item, stream)


# Internal: Set up audio playback using Shinobu
func _setup_audio_playback(sound_source, item, stream: AudioStream = null) -> void:
	_shinobu_source = sound_source
	_audio_stream = stream
	
	# Instantiate the sound player on the menu music group
	_audio_player = sound_source.instantiate(HBGame.menu_music_group)
	add_child(_audio_player)
	
	# Get duration
	if _audio_player.has_method("get_length_msec"):
		item.duration = _audio_player.get_length_msec() / 1000.0
	elif stream:
		item.duration = stream.get_length()
	
	print("[MediaPlayer] Audio duration: ", item.duration)
	
	# Seek to last position if resuming
	if item.last_position > 0 and item.last_position < item.duration - 1.0:
		_audio_player.seek(int(item.last_position * 1000))
	
	# Start audio playback
	_audio_player.schedule_start_time(Shinobu.get_dsp_time())
	_audio_player.start()
	
	print("[MediaPlayer] Playback started")
	
	state = State.PLAYING
	item.mark_played()
	set_process(true)
	
	emit_signal("media_loaded", item)
	emit_signal("playback_started", item)


# Pause playback
func pause() -> void:
	if state != State.PLAYING:
		return
	
	if _audio_player:
		_audio_player.stop()
	
	state = State.PAUSED
	set_process(false)
	emit_signal("playback_paused")


# Resume playback
func resume() -> void:
	if state != State.PAUSED:
		return
	
	if _audio_player:
		_audio_player.start()
	
	state = State.PLAYING
	set_process(true)
	emit_signal("playback_resumed")


# Toggle play/pause
func toggle_playback() -> void:
	match state:
		State.PLAYING:
			pause()
		State.PAUSED:
			resume()
		State.STOPPED:
			if current_item:
				play(current_item)


# Stop playback completely
func stop() -> void:
	set_process(false)
	
	if _audio_player:
		_audio_player.stop()
		_audio_player.queue_free()
		_audio_player = null
	
	_shinobu_source = null
	_audio_stream = null
	state = State.STOPPED
	_last_reported_position = 0.0
	emit_signal("playback_stopped")


# Seek to position (in seconds)
func seek(position: float) -> void:
	if state == State.STOPPED:
		return
	
	if _audio_player:
		_audio_player.seek(int(position * 1000))  # Shinobu uses milliseconds
	
	_last_reported_position = position
	if current_item:
		current_item.last_position = position


# Set volume (0.0 to 1.0)
func set_volume(volume: float) -> void:
	volume = clamp(volume, 0.0, 1.0)
	
	if current_item:
		current_item.volume = volume
	
	if _audio_player:
		_audio_player.volume = volume
	
	emit_signal("volume_changed", volume)


# Get current playback position in seconds
func get_position() -> float:
	if _audio_player:
		return _audio_player.get_playback_position_msec() / 1000.0
	return 0.0


# Get total duration in seconds
func get_duration() -> float:
	if _audio_player:
		return _audio_player.get_length_msec() / 1000.0
	if current_item:
		return current_item.duration
	return 0.0


# Check if currently playing
func is_playing() -> bool:
	return state == State.PLAYING


# Check if paused
func is_paused() -> bool:
	return state == State.PAUSED


# Internal: Called when playback finishes naturally
func _on_playback_finished() -> void:
	state = State.STOPPED
	set_process(false)
	
	if current_item:
		current_item.last_position = 0.0  # Reset for next play
	
	emit_signal("playback_finished")


func _exit_tree():
	stop()
