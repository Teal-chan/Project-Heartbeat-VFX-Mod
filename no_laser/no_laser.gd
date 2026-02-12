extends HBModifier
class_name NoLaserModifier

var _game: HBRhythmGame = null

func _init() -> void:
	disables_video = false
	processing_notes = false

func _pre_game(song: HBSong, game: HBRhythmGame) -> void:
	_game = game
	_set_laser_visible(false)

	if not _game.is_connected("restarting", Callable(self, "_on_restart")):
		_game.connect("restarting", Callable(self, "_on_restart"))

func _post_game(song: HBSong, game: HBRhythmGame) -> void:
	_set_laser_visible(true)
	if _game and _game.is_connected("restarting", Callable(self, "_on_restart")):
		_game.disconnect("restarting", Callable(self, "_on_restart"))
	_game = null

func _on_restart() -> void:
	_set_laser_visible(false)

func _set_laser_visible(visible: bool) -> void:
	if _game == null or _game.game_ui == null:
		return
	var ui := _game.game_ui as HBRhythmGameUI
	if ui == null:
		return
	var laser_layer = ui.get_drawing_layer_node(&"Laser")
	if laser_layer != null:
		laser_layer.visible = visible

static func get_modifier_name():
	return "No Laser"

func get_modifier_list_name():
	return "No Laser"

static func get_modifier_description():
	return "Disables the laser effect during gameplay."

static func get_modifier_settings_class() -> Script:
	return HBSerializable

static func get_option_settings() -> Dictionary:
	return {}

static func is_leaderboard_legal() -> bool:
	return true
