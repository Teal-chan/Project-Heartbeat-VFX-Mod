# Media Player Menu - Main UI for the Extend media player feature
# Audio-only playlist player
extends HBMenu

# Preload our classes
const MediaItem = preload("res://menus/media_player/HBMediaItem.gd")
const MediaPlaylist = preload("res://menus/media_player/HBMediaPlaylist.gd")
const MediaPlayerController = preload("res://menus/media_player/HBMediaPlayerController.gd")
const VFXUtils = preload("user://editor_scripts/Modules/vfx_utils.gd")

signal song_changed(item)
signal pause_background_player
signal resume_background_player
signal play_song_in_background(song)
signal background_changed(texture, use_default)

# Node references
@onready var playlist_container: VBoxContainer = $MainContainer/PlaylistPanel/VBoxContainer/ScrollContainer/PlaylistContainer
@onready var playlist_name_label: Label = $MainContainer/PlaylistPanel/VBoxContainer/PlaylistHeader/PlaylistNameLabel
@onready var new_playlist_button: Button = $MainContainer/PlaylistPanel/VBoxContainer/PlaylistHeader/NewPlaylistButton
@onready var choose_playlist_button: Button = $MainContainer/PlaylistPanel/VBoxContainer/PlaylistHeader/ChoosePlaylistButton
@onready var new_playlist_dialog: ConfirmationDialog = $NewPlaylistDialog
@onready var new_playlist_line_edit: LineEdit = $NewPlaylistDialog/LineEdit
@onready var choose_playlist_dialog: ConfirmationDialog = $ChoosePlaylistDialog
@onready var choose_playlist_list: ItemList = $ChoosePlaylistDialog/ItemList
@onready var folder_choice_dialog: ConfirmationDialog = $FolderChoiceDialog
@onready var official_songs_button: Button = $FolderChoiceDialog/VBoxContainer/OfficialSongsButton
@onready var editor_folder_button: Button = $FolderChoiceDialog/VBoxContainer/EditorFolderButton
@onready var workshop_folder_button: Button = $FolderChoiceDialog/VBoxContainer/WorkshopFolderButton
@onready var official_songs_dialog: ConfirmationDialog = $OfficialSongsDialog
@onready var official_songs_list: ItemList = $OfficialSongsDialog/VBoxContainer/OfficialSongsList
@onready var select_all_button: Button = $OfficialSongsDialog/VBoxContainer/HBoxContainer/SelectAllButton
@onready var select_none_button: Button = $OfficialSongsDialog/VBoxContainer/HBoxContainer/SelectNoneButton
@onready var now_playing_label: Label = $MainContainer/PlayerPanel/VBoxContainer/NowPlayingLabel
@onready var artist_label: Label = $MainContainer/PlayerPanel/VBoxContainer/ArtistLabel
@onready var progress_bar: HSlider = $MainContainer/PlayerPanel/VBoxContainer/ProgressContainer/ProgressBar
@onready var time_current_label: Label = $MainContainer/PlayerPanel/VBoxContainer/ProgressContainer/TimeContainer/CurrentTimeLabel
@onready var time_total_label: Label = $MainContainer/PlayerPanel/VBoxContainer/ProgressContainer/TimeContainer/TotalTimeLabel
@onready var play_button: Button = $MainContainer/PlayerPanel/VBoxContainer/ControlsContainer/PlayButton
@onready var prev_button: Button = $MainContainer/PlayerPanel/VBoxContainer/ControlsContainer/PrevButton
@onready var next_button: Button = $MainContainer/PlayerPanel/VBoxContainer/ControlsContainer/NextButton
@onready var shuffle_button: Button = $MainContainer/PlayerPanel/VBoxContainer/ControlsContainer/ShuffleButton
@onready var repeat_button: Button = $MainContainer/PlayerPanel/VBoxContainer/ControlsContainer/RepeatButton
@onready var volume_slider: HSlider = $MainContainer/PlayerPanel/VBoxContainer/BottomControls/VolumeContainer/VolumeSlider
@onready var thumbnail_display: TextureRect = $MainContainer/PlayerPanel/VBoxContainer/ThumbnailDisplay
@onready var add_files_button: Button = $MainContainer/PlaylistPanel/VBoxContainer/AddFilesButton
@onready var play_in_game_button: Button = $MainContainer/PlayerPanel/VBoxContainer/BottomControls/PlayInGameButton

# Playlist item scene
var PlaylistItemScene = preload("res://menus/media_player/HBMediaPlaylistItem.tscn")

# Core components
var controller
var playlist

# File dialog for importing media
var file_dialog: FileDialog

# UI state
var _seeking: bool = false
var _playlist_items: Array = []
var _launching_to_game: bool = false

# Button text
const TEXT_PLAY = "▶"
const TEXT_PAUSE = "⏸"
const TEXT_SHUFFLE_OFF = "🔀"
const TEXT_SHUFFLE_ON = "🔀✓"
const TEXT_REPEAT_OFF = "🔁"
const TEXT_REPEAT_ONE = "🔂"
const TEXT_REPEAT_ALL = "🔁✓"

# Icon textures (loaded at runtime)
var icon_shuffle: Texture2D
var icon_previous: Texture2D
var icon_play: Texture2D
var icon_pause: Texture2D
var icon_next: Texture2D
var icon_repeat_off: Texture2D
var icon_repeat_all: Texture2D
var icon_repeat_one: Texture2D


func _ready():
	super._ready()
	
	print("[MediaPlayerMenu] Initializing...")
	
	# Load custom SVG icons
	_load_custom_icons()
	
	# Initialize controller
	controller = MediaPlayerController.new()
	add_child(controller)
	
	# Connect controller signals
	controller.playback_started.connect(_on_playback_started)
	controller.playback_paused.connect(_on_playback_paused)
	controller.playback_resumed.connect(_on_playback_resumed)
	controller.playback_stopped.connect(_on_playback_stopped)
	controller.playback_finished.connect(_on_playback_finished)
	controller.position_changed.connect(_on_position_changed)
	controller.volume_changed.connect(_on_volume_changed)
	controller.media_load_failed.connect(_on_media_load_failed)
	
	print("[MediaPlayerMenu] Controller initialized")
	
	# Load last used playlist (or default)
	var last_playlist_name = _load_last_playlist_name()
	playlist = MediaPlaylist.load_playlist(last_playlist_name)
	if not playlist:
		print("[MediaPlayerMenu] ERROR: Failed to load playlist, falling back to default")
		playlist = MediaPlaylist.load_playlist(MediaPlaylist.DEFAULT_PLAYLIST_NAME)
	if not playlist:
		playlist = MediaPlaylist.new(MediaPlaylist.DEFAULT_PLAYLIST_NAME)
	
	print("[MediaPlayerMenu] Playlist loaded: ", playlist.name)
	
	# Connect UI signals
	_setup_ui_connections()
	
	print("[MediaPlayerMenu] UI connections set up")
	
	# Initialize UI state
	_update_ui_state()
	_rebuild_playlist_ui()
	
	print("[MediaPlayerMenu] UI initialized")
	
	# Set up file dialog
	_setup_file_dialog()
	
	print("[MediaPlayerMenu] Ready!")


func _setup_ui_connections():
	play_button.pressed.connect(_on_play_button_pressed)
	prev_button.pressed.connect(_on_prev_button_pressed)
	next_button.pressed.connect(_on_next_button_pressed)
	shuffle_button.pressed.connect(_on_shuffle_button_pressed)
	repeat_button.pressed.connect(_on_repeat_button_pressed)
	add_files_button.pressed.connect(_on_add_files_button_pressed)
	play_in_game_button.pressed.connect(_on_play_in_game_button_pressed)
	
	# Playlist control connections
	new_playlist_button.pressed.connect(_on_new_playlist_button_pressed)
	choose_playlist_button.pressed.connect(_on_choose_playlist_button_pressed)
	new_playlist_dialog.confirmed.connect(_on_new_playlist_confirmed)
	choose_playlist_dialog.confirmed.connect(_on_choose_playlist_confirmed)
	
	# Folder choice connections
	folder_choice_dialog.confirmed.connect(_on_folder_choice_browse)
	official_songs_button.pressed.connect(_on_official_songs_selected)
	editor_folder_button.pressed.connect(_on_editor_folder_selected)
	workshop_folder_button.pressed.connect(_on_workshop_folder_selected)
	
	# Official songs selection dialog connections
	official_songs_dialog.confirmed.connect(_on_official_songs_confirmed)
	select_all_button.pressed.connect(_on_select_all_official)
	select_none_button.pressed.connect(_on_select_none_official)
	
	volume_slider.value_changed.connect(_on_volume_slider_changed)
	
	# Progress bar - handle seeking
	progress_bar.drag_started.connect(func(): _seeking = true)
	progress_bar.drag_ended.connect(_on_progress_drag_ended)
	progress_bar.value_changed.connect(_on_progress_value_changed)


func _setup_file_dialog():
	file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	
	# Audio formats only
	file_dialog.filters = PackedStringArray([
		"*.ogg ; OGG Audio",
		"*.mp3 ; MP3 Audio",
		"*.wav ; WAV Audio"
	])
	
	file_dialog.files_selected.connect(_on_files_selected)
	add_child(file_dialog)


func _on_menu_enter(force_hard_transition=false, args = {}):
	super._on_menu_enter(force_hard_transition, args)

	# If launched from PreGameScreen with a song to play, reload the playlist and start playback
	if args.get("play_song", false):
		# Reload the playlist to pick up any newly added items and cursor position
		var last_playlist_name = _load_last_playlist_name()
		playlist = MediaPlaylist.load_playlist(last_playlist_name)
		if not playlist:
			playlist = MediaPlaylist.new(MediaPlaylist.DEFAULT_PLAYLIST_NAME)
		_rebuild_playlist_ui()

		var item = playlist.get_current()
		if item:
			controller.play(item)


func _on_menu_exit(force_hard_transition=false):
	super._on_menu_exit(force_hard_transition)
	
	# Save playlist state
	playlist.save()
	
	# Resume background music when leaving, unless we're launching to game or still playing
	if not _launching_to_game and not controller.is_playing():
		emit_signal("resume_background_player")
	
	_launching_to_game = false


func _load_custom_icons():
	"""Load SVG icons for media player controls"""
	var icon_dir = "res://graphics/icons/media_player/"
	
	icon_shuffle = VFXUtils.load_svg_icon(icon_dir + "shuffle.svg", 48)
	icon_previous = VFXUtils.load_svg_icon(icon_dir + "previous.svg", 48)
	icon_play = VFXUtils.load_svg_icon(icon_dir + "play.svg", 48)
	icon_pause = VFXUtils.load_svg_icon(icon_dir + "pause.svg", 48)
	icon_next = VFXUtils.load_svg_icon(icon_dir + "next.svg", 48)
	icon_repeat_off = VFXUtils.load_svg_icon(icon_dir + "repeat_off.svg", 48)
	icon_repeat_all = VFXUtils.load_svg_icon(icon_dir + "repeat_all.svg", 48)
	icon_repeat_one = VFXUtils.load_svg_icon(icon_dir + "repeat_one.svg", 48)
	
	# Apply icons to buttons
	if icon_shuffle:
		shuffle_button.icon = icon_shuffle
		shuffle_button.text = ""
	if icon_previous:
		prev_button.icon = icon_previous
		prev_button.text = ""
	if icon_play:
		play_button.icon = icon_play
		play_button.text = ""
	if icon_next:
		next_button.icon = icon_next
		next_button.text = ""
	if icon_repeat_off:
		repeat_button.icon = icon_repeat_off
		repeat_button.text = ""
	
	print("[MediaPlayerMenu] Custom icons loaded")


# UI Update Methods

func _update_ui_state():
	# Update playlist name label
	playlist_name_label.text = "Playlist: " + playlist.name
	
	# Update play/pause button
	if controller.is_playing():
		if icon_pause:
			play_button.icon = icon_pause
		else:
			play_button.text = TEXT_PAUSE
	else:
		if icon_play:
			play_button.icon = icon_play
		else:
			play_button.text = TEXT_PLAY
	
	# Update shuffle button
	if playlist.shuffle_mode == MediaPlaylist.ShuffleMode.ON:
		shuffle_button.modulate = Color.WHITE
	else:
		shuffle_button.modulate = Color(1, 1, 1, 0.5)
	
	# Update repeat button - swap icons based on mode
	match playlist.repeat_mode:
		MediaPlaylist.RepeatMode.OFF:
			if icon_repeat_off:
				repeat_button.icon = icon_repeat_off
			else:
				repeat_button.text = TEXT_REPEAT_OFF
			repeat_button.modulate = Color(1, 1, 1, 0.5)
		MediaPlaylist.RepeatMode.ALL:
			if icon_repeat_all:
				repeat_button.icon = icon_repeat_all
			else:
				repeat_button.text = TEXT_REPEAT_ALL
			repeat_button.modulate = Color.WHITE
		MediaPlaylist.RepeatMode.ONE:
			if icon_repeat_one:
				repeat_button.icon = icon_repeat_one
			else:
				repeat_button.text = TEXT_REPEAT_ONE
			repeat_button.modulate = Color.WHITE
	
	# Update play in game button - only enable if we have a valid song
	var current_item = playlist.get_current()
	play_in_game_button.disabled = not _can_play_in_game(current_item)


func _can_play_in_game(item) -> bool:
	if not item:
		return false
	
	# Get the folder name from our audio path (e.g., "song_name" from ".../editor_songs/song_name/audio.ogg")
	var song_folder = item.audio_path.get_base_dir().get_file()
	
	for song_id in SongLoader.songs:
		var song = SongLoader.songs[song_id] as HBSong
		# Get the folder name from the song's path
		var song_path_folder = song.path.trim_suffix("/").get_file()
		if song_path_folder == song_folder:
			return song.charts.size() > 0
	
	return false


func _update_now_playing(item):
	if item:
		now_playing_label.text = item.get_display_title()
		artist_label.text = item.get_display_artist()
		
		# Update thumbnail
		if item.thumbnail_path and FileAccess.file_exists(item.thumbnail_path):
			var img = Image.load_from_file(item.thumbnail_path)
			if img:
				thumbnail_display.texture = ImageTexture.create_from_image(img)
		else:
			thumbnail_display.texture = preload("res://graphics/no_preview_texture.png")
	else:
		now_playing_label.text = "No Track Selected"
		artist_label.text = ""
		thumbnail_display.texture = preload("res://graphics/no_preview_texture.png")


func _rebuild_playlist_ui():
	# Clear existing items
	for item_node in _playlist_items:
		item_node.queue_free()
	_playlist_items.clear()
	
	# Add items from playlist
	for i in range(playlist.items.size()):
		var item = playlist.items[i]
		var item_node = PlaylistItemScene.instantiate()
		item_node.setup(item, i)
		item_node.item_selected.connect(_on_playlist_item_selected)
		item_node.item_removed.connect(_on_playlist_item_removed)
		playlist_container.add_child(item_node)
		_playlist_items.append(item_node)
	
	_highlight_current_item()


func _highlight_current_item():
	for i in range(_playlist_items.size()):
		var item_node = _playlist_items[i]
		item_node.set_playing(i == playlist.current_index and controller.is_playing())


func _format_time(seconds: float) -> String:
	var mins = int(seconds) / 60
	var secs = int(seconds) % 60
	return "%d:%02d" % [mins, secs]


# Controller Signal Handlers

func _on_playback_started(item):
	# Pause the game's background music when we start playing
	emit_signal("pause_background_player")
	
	# Update rich presence
	if HBGame.rich_presence:
		HBGame.rich_presence.notify_media_player(item.get_display_title(), item.get_display_artist())
	
	# Load background image from the matching HBSong
	var hb_song = _find_hb_song_for_item(item)
	if hb_song:
		var token := SongAssetLoader.request_asset_load(hb_song, [SongAssetLoader.ASSET_TYPES.BACKGROUND])
		token.assets_loaded.connect(_on_background_loaded)
	
	_update_now_playing(item)
	_update_ui_state()
	_highlight_current_item()
	emit_signal("song_changed", item)


func _find_hb_song_for_item(item) -> HBSong:
	if not item:
		return null
	var song_folder = item.audio_path.get_base_dir().get_file()
	for song_id in SongLoader.songs:
		var song = SongLoader.songs[song_id] as HBSong
		var song_path_folder = song.path.trim_suffix("/").get_file()
		if song_path_folder == song_folder:
			return song
	return null


func _on_background_loaded(token: SongAssetLoader.AssetLoadToken):
	var background = token.get_asset(SongAssetLoader.ASSET_TYPES.BACKGROUND)
	if background:
		emit_signal("background_changed", background, false)
	else:
		# No background - signal to use default
		emit_signal("background_changed", null, true)


func _on_playback_paused():
	_update_ui_state()
	_highlight_current_item()


func _on_playback_resumed():
	_update_ui_state()
	_highlight_current_item()


func _on_playback_stopped():
	_update_ui_state()
	_highlight_current_item()
	progress_bar.value = 0
	time_current_label.text = "0:00"
	
	# Reset rich presence to main menu
	if HBGame.rich_presence:
		HBGame.rich_presence.notify_at_main_menu()
	
	# Resume background music when we stop
	emit_signal("resume_background_player")


func _on_playback_finished():
	# Auto-advance to next track
	var next_item = playlist.get_next()
	if next_item:
		controller.play(next_item)
	else:
		_update_ui_state()
		_highlight_current_item()


func _on_position_changed(position: float, duration: float):
	if not _seeking:
		progress_bar.max_value = duration
		progress_bar.value = position
		time_current_label.text = _format_time(position)
		time_total_label.text = _format_time(duration)


func _on_volume_changed(volume: float):
	volume_slider.value = volume


func _on_media_load_failed(item, error: String):
	push_warning("Media Player: Failed to load '%s': %s" % [item.get_display_title(), error])


# UI Event Handlers

func _on_play_button_pressed():
	if controller.is_playing():
		controller.pause()
	elif controller.is_paused():
		controller.resume()
	else:
		# Start from current selection or first item
		var item = playlist.get_current()
		if not item and playlist.items.size() > 0:
			item = playlist.set_current(0)
		if item:
			controller.play(item)


func _on_prev_button_pressed():
	# If more than 3 seconds into track, restart; otherwise previous
	if controller.get_position() > 3.0:
		controller.seek(0)
	else:
		var item = playlist.get_previous()
		if item:
			controller.play(item)


func _on_next_button_pressed():
	var item = playlist.get_next()
	if item:
		controller.play(item)


func _on_shuffle_button_pressed():
	playlist.toggle_shuffle()
	_update_ui_state()


func _on_repeat_button_pressed():
	playlist.cycle_repeat()
	_update_ui_state()


func _on_volume_slider_changed(value: float):
	controller.set_volume(value)


func _on_progress_drag_ended(value_changed: bool):
	_seeking = false
	if value_changed:
		controller.seek(progress_bar.value)


func _on_progress_value_changed(value: float):
	if _seeking:
		time_current_label.text = _format_time(value)


func _on_add_files_button_pressed():
	folder_choice_dialog.popup_centered()


# Store official songs data for selection dialog
var _official_songs_data: Array = []

func _on_official_songs_selected():
	folder_choice_dialog.hide()
	
	# Build list of official songs
	_official_songs_data.clear()
	official_songs_list.clear()
	
	for song_id in SongLoader.songs:
		var song = SongLoader.songs[song_id] as HBSong
		# Official songs have paths starting with res://songs
		if song.path.begins_with("res://songs"):
			var audio_path = song.get_song_audio_res_path()
			if not audio_path.is_empty() and FileAccess.file_exists(audio_path):
				# Check if already in playlist
				var already_exists = false
				for item in playlist.items:
					if item.audio_path.get_base_dir().get_file() == song.path.get_file():
						already_exists = true
						break
				
				if not already_exists:
					_official_songs_data.append(song)
					var display_text = "%s - %s" % [song.artist, song.title]
					official_songs_list.add_item(display_text)
	
	if _official_songs_data.is_empty():
		print("[MediaPlayer] No official songs available to add")
		return
	
	# Sort alphabetically by display name
	official_songs_dialog.popup_centered()


func _on_official_songs_confirmed():
	var selected_indices = official_songs_list.get_selected_items()
	if selected_indices.is_empty():
		return
	
	var added_count = 0
	for idx in selected_indices:
		var song = _official_songs_data[idx] as HBSong
		var audio_path = song.get_song_audio_res_path()
		
		var item = MediaItem.from_file(audio_path)
		item.title = song.title
		item.artist = song.artist
		playlist.add_item(item)
		added_count += 1
	
	if added_count > 0:
		_rebuild_playlist_ui()
		playlist.save()
		print("[MediaPlayer] Added %d official songs" % added_count)


func _on_select_all_official():
	for i in range(official_songs_list.item_count):
		official_songs_list.select(i, false)


func _on_select_none_official():
	official_songs_list.deselect_all()


func _on_editor_folder_selected():
	folder_choice_dialog.hide()
	var editor_path = ProjectSettings.globalize_path("user://editor_songs")
	file_dialog.current_dir = editor_path
	file_dialog.popup_centered_ratio(0.7)


func _on_workshop_folder_selected():
	folder_choice_dialog.hide()
	var workshop_path = _get_workshop_path()
	if not workshop_path.is_empty():
		file_dialog.current_dir = workshop_path
	file_dialog.popup_centered_ratio(0.7)


func _on_folder_choice_browse():
	# "Browse..." button - just open file dialog at current/default location
	file_dialog.popup_centered_ratio(0.7)


func _get_workshop_path() -> String:
	# Try to find Steam workshop content folder for Project Heartbeat
	# App ID is 1216230
	var possible_paths = []
	
	if OS.get_name() == "Windows":
		# Common Steam install locations on Windows
		possible_paths = [
			"C:/Program Files (x86)/Steam/steamapps/workshop/content/1216230",
			"C:/Program Files/Steam/steamapps/workshop/content/1216230",
			"D:/Steam/steamapps/workshop/content/1216230",
			"D:/SteamLibrary/steamapps/workshop/content/1216230",
			"E:/Steam/steamapps/workshop/content/1216230",
			"E:/SteamLibrary/steamapps/workshop/content/1216230",
		]
	elif OS.get_name() == "Linux":
		var home = OS.get_environment("HOME")
		possible_paths = [
			home + "/.steam/steam/steamapps/workshop/content/1216230",
			home + "/.local/share/Steam/steamapps/workshop/content/1216230",
		]
	elif OS.get_name() == "macOS":
		var home = OS.get_environment("HOME")
		possible_paths = [
			home + "/Library/Application Support/Steam/steamapps/workshop/content/1216230",
		]
	
	for path in possible_paths:
		if DirAccess.dir_exists_absolute(path):
			return path
	
	# Fallback - return empty and let user navigate
	return ""


func _on_new_playlist_button_pressed():
	new_playlist_line_edit.text = ""
	new_playlist_dialog.popup_centered()
	new_playlist_line_edit.grab_focus()


func _on_new_playlist_confirmed():
	var new_name = new_playlist_line_edit.text.strip_edges()
	if new_name.is_empty():
		return
	
	# Sanitize name for filesystem
	new_name = new_name.replace("/", "_").replace("\\", "_").replace(":", "_")
	
	# Save current playlist first
	playlist.save()
	
	# Stop playback when switching playlists
	controller.stop()
	
	# Create new playlist
	playlist = MediaPlaylist.new(new_name)
	playlist.save()
	
	# Remember this playlist for next time
	_save_last_playlist_name(new_name)
	
	_rebuild_playlist_ui()
	_update_ui_state()
	_update_now_playing(null)


func _on_choose_playlist_button_pressed():
	# Populate the playlist list
	choose_playlist_list.clear()
	
	var playlists = _get_available_playlists()
	for pl_name in playlists:
		choose_playlist_list.add_item(pl_name)
	
	# Select current playlist
	var current_idx = playlists.find(playlist.name)
	if current_idx >= 0:
		choose_playlist_list.select(current_idx)
	
	choose_playlist_dialog.popup_centered()
	choose_playlist_list.grab_focus()


func _on_choose_playlist_confirmed():
	var selected_items = choose_playlist_list.get_selected_items()
	if selected_items.is_empty():
		return
	
	var selected_name = choose_playlist_list.get_item_text(selected_items[0])
	if selected_name == playlist.name:
		return  # Same playlist, no change needed
	
	# Save current playlist first
	playlist.save()
	
	# Stop playback when switching playlists
	controller.stop()
	
	# Load selected playlist
	playlist = MediaPlaylist.load_playlist(selected_name)
	
	# Remember this playlist for next time
	_save_last_playlist_name(selected_name)
	
	_rebuild_playlist_ui()
	_update_ui_state()
	_update_now_playing(null)


func _get_available_playlists() -> Array:
	var playlists = []
	var dir = DirAccess.open("user://media_playlists")
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".json"):
				playlists.append(file_name.get_basename())
			file_name = dir.get_next()
		dir.list_dir_end()
	
	# Ensure default is always available
	if not "default" in playlists:
		playlists.insert(0, "default")
	
	playlists.sort()
	return playlists


const SETTINGS_PATH = "user://media_playlists/settings.cfg"

func _save_last_playlist_name(playlist_name: String):
	var config = ConfigFile.new()
	config.set_value("media_player", "last_playlist", playlist_name)
	config.save(SETTINGS_PATH)


func _load_last_playlist_name() -> String:
	var config = ConfigFile.new()
	var err = config.load(SETTINGS_PATH)
	if err == OK:
		return config.get_value("media_player", "last_playlist", MediaPlaylist.DEFAULT_PLAYLIST_NAME)
	return MediaPlaylist.DEFAULT_PLAYLIST_NAME


func _on_play_in_game_button_pressed():
	var current_item = playlist.get_current()
	if not current_item:
		return
	
	# Get the folder name from our audio path
	var song_folder = current_item.audio_path.get_base_dir().get_file()
	var hb_song: HBSong = null
	
	for song_id in SongLoader.songs:
		var song = SongLoader.songs[song_id] as HBSong
		var song_path_folder = song.path.trim_suffix("/").get_file()
		if song_path_folder == song_folder:
			hb_song = song
			break
	
	if not hb_song:
		push_warning("Media Player: Could not find matching game song for: " + current_item.audio_path)
		return
	
	# Get the first available difficulty
	var difficulty = ""
	if hb_song.charts.size() > 0:
		difficulty = hb_song.charts.keys()[0]
	
	if difficulty.is_empty():
		push_warning("Media Player: Song has no charts: " + hb_song.title)
		return
	
	# Stop media player audio - let the background player take over with this song
	controller.stop()
	
	# Emit signal to tell background player to play this song
	# This will also trigger the background image to update
	emit_signal("play_song_in_background", hb_song)
	
	# Mark that we're launching to game
	_launching_to_game = true
	
	# Launch the game
	change_to_menu("pre_game", false, {"song": hb_song, "difficulty": difficulty})


func _on_files_selected(paths: PackedStringArray):
	for path in paths:
		var item = MediaItem.from_file(path)
		playlist.add_item(item)
	
	_rebuild_playlist_ui()
	playlist.save()


func _on_playlist_item_selected(index: int):
	var item = playlist.set_current(index)
	if item:
		controller.play(item)


func _on_playlist_item_removed(index: int):
	playlist.remove_at(index)
	_rebuild_playlist_ui()
	playlist.save()


# Allow drag and drop reordering from playlist items
func move_playlist_item(from_index: int, to_index: int):
	playlist.move_item(from_index, to_index)
	_rebuild_playlist_ui()
	playlist.save()


# Input handling
func _unhandled_input(event: InputEvent):
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		change_to_menu("main_menu")
	elif event.is_action_pressed("gui_accept"):
		get_viewport().set_input_as_handled()
		_on_play_button_pressed()
