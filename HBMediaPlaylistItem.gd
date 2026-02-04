# Playlist item UI component for the Media Player
# Displays a single media item in the playlist with controls
extends HBoxContainer

const MediaItem = preload("res://menus/media_player/HBMediaItem.gd")

signal item_selected(index: int)
signal item_removed(index: int)

@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var artist_label: Label = $VBoxContainer/ArtistLabel
@onready var duration_label: Label = $DurationLabel
@onready var playing_indicator: TextureRect = $PlayingIndicator
@onready var remove_button: Button = $RemoveButton

var media_item
var item_index: int = -1
var _is_playing: bool = false


func _ready():
	# Connect signals
	gui_input.connect(_on_gui_input)
	remove_button.pressed.connect(_on_remove_pressed)
	
	# Set up focus
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP


func setup(item, index: int):
	media_item = item
	item_index = index
	
	title_label.text = item.get_display_title()
	artist_label.text = item.get_display_artist()
	
	# Format duration
	if item.duration > 0:
		var mins = int(item.duration) / 60
		var secs = int(item.duration) % 60
		duration_label.text = "%d:%02d" % [mins, secs]
	else:
		duration_label.text = "--:--"
	
	# Update playing state
	set_playing(false)


func set_playing(playing: bool):
	_is_playing = playing
	playing_indicator.visible = playing
	
	if playing:
		modulate = Color(1.2, 1.2, 1.2)  # Slight highlight
	else:
		modulate = Color.WHITE


func _on_gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if event.double_click:
				emit_signal("item_selected", item_index)
			else:
				grab_focus()
	elif event.is_action_pressed("gui_accept"):
		emit_signal("item_selected", item_index)


func _on_remove_pressed():
	emit_signal("item_removed", item_index)


func _get_drag_data(at_position: Vector2):
	# Support drag and drop reordering
	var preview = Label.new()
	preview.text = title_label.text
	set_drag_preview(preview)
	return {"type": "playlist_item", "index": item_index}


func _can_drop_data(at_position: Vector2, data) -> bool:
	return data is Dictionary and data.get("type") == "playlist_item"


func _drop_data(at_position: Vector2, data):
	var from_index = data.get("index", -1)
	if from_index != -1 and from_index != item_index:
		# Notify parent to reorder
		get_parent().get_parent().get_parent().get_parent().move_playlist_item(from_index, item_index)
