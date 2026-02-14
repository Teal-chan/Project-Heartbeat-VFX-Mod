extends HBModifier
class_name GiantNotesModifier

const TARGET_NOTE_SIZE := 1.8

# Static var preserves the user's real note_size across the modifier lifecycle
static var _saved_note_size: float = -1.0

func _init() -> void:
	disables_video = false
	processing_notes = false

# Called by PreGameScreen when the modifier is added to the list
static func on_modifier_added() -> void:
	if _saved_note_size < 0.0:
		_saved_note_size = UserSettings.user_settings.note_size
	UserSettings.user_settings.note_size = TARGET_NOTE_SIZE

# Called by PreGameScreen when the modifier is removed from the list
static func on_modifier_removed() -> void:
	if _saved_note_size >= 0.0:
		UserSettings.user_settings.note_size = _saved_note_size
		_saved_note_size = -1.0

func _pre_game(song: HBSong, game: HBRhythmGame) -> void:
	UserSettings.user_settings.note_size = TARGET_NOTE_SIZE

	if not game.is_connected("restarting", Callable(self, "_on_restart")):
		game.connect("restarting", Callable(self, "_on_restart"))

func _post_game(song: HBSong, game: HBRhythmGame) -> void:
	if _saved_note_size >= 0.0:
		UserSettings.user_settings.note_size = _saved_note_size
		_saved_note_size = -1.0
	if game and game.is_connected("restarting", Callable(self, "_on_restart")):
		game.disconnect("restarting", Callable(self, "_on_restart"))

func _on_restart() -> void:
	UserSettings.user_settings.note_size = TARGET_NOTE_SIZE

static func get_modifier_name():
	return "Giant Notes"

func get_modifier_list_name():
	return "Giant Notes"

static func get_modifier_description():
	return "Sets the note size to 1.8 for a larger target."

static func get_modifier_settings_class() -> Script:
	return HBSerializable

static func get_option_settings() -> Dictionary:
	return {}

static func get_incompatible_modifiers() -> Array:
	return ["tiny_notes"]

static func is_leaderboard_legal() -> bool:
	return true
