extends HBModifier
class_name PerfectRunModifier

const PerfectRunSettings := preload("res://rythm_game/modifiers/perfect_run/perfect_run_settings.gd")

var _game: HBRhythmGame = null
var _failed: bool = false
var _fine_count: int = 0

var _fine_window: PanelContainer = null
var _fine_label: Label = null

func _init() -> void:
	disables_video = false
	processing_notes = false
	modifier_settings = get_modifier_settings_class().new()

func _init_plugin() -> void:
	super._init_plugin()

func _pre_game(song: HBSong, game: HBRhythmGame) -> void:
	_game = game
	_failed = false
	_fine_count = 0
	
	if not _game.is_connected("note_judged", Callable(self, "_on_note_judged")):
		_game.connect("note_judged", Callable(self, "_on_note_judged"))
	
	if not _game.is_connected("restarting", Callable(self, "_on_restart")):
		_game.connect("restarting", Callable(self, "_on_restart"))
	
	var settings := modifier_settings as PerfectRunSettings
	if settings and settings.show_fine_counter:
		_create_fine_window()
		_update_fine_window()

func _post_game(song: HBSong, game: HBRhythmGame) -> void:
	if _game:
		if _game.is_connected("note_judged", Callable(self, "_on_note_judged")):
			_game.disconnect("note_judged", Callable(self, "_on_note_judged"))
		if _game.is_connected("restarting", Callable(self, "_on_restart")):
			_game.disconnect("restarting", Callable(self, "_on_restart"))
	_game = null
	_failed = false
	_fine_count = 0
	
	_destroy_fine_window()


func _on_restart() -> void:
	_failed = false
	_fine_count = 0
	_update_fine_window()


func _create_fine_window() -> void:
	_destroy_fine_window()
	
	if not _game or not _game.game_ui:
		return
	
	var panel := PanelContainer.new()
	panel.name = "PerfectRunFineCounter"
	
	# Anchor to top-left
	panel.anchor_left = 0.0
	panel.anchor_right = 0.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 0.0
	
	# Position under the song name bar, a bit to the right
	var left := 135.0
	var top := 100.0
	var width := 260.0
	var height := 48.0
	
	panel.offset_left = left
	panel.offset_top = top
	panel.offset_right = left + width
	panel.offset_bottom = top + height
	
	panel.custom_minimum_size = Vector2(width, height)
	
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(vbox)
	
	var title := Label.new()
	title.text = "Perfect Run"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(title)
	
	var label := Label.new()
	label.name = "FineLabel"
	label.text = "FINEs: 0"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(label)
	
	_game.game_ui.add_child(panel)
	
	_fine_window = panel
	_fine_label = label

func _destroy_fine_window() -> void:
	if _fine_window and is_instance_valid(_fine_window):
		_fine_window.queue_free()
	_fine_window = null
	_fine_label = null

func _update_fine_window() -> void:
	if not _fine_label:
		return
	
	var settings := modifier_settings as PerfectRunSettings
	var fine_limit_text := ""
	
	# Reset to default color
	_fine_label.modulate = Color.WHITE
	
	if settings and not settings.cool_only and settings.fine_limit > 0:
		fine_limit_text = " / %d" % settings.fine_limit
		
		var remaining := settings.fine_limit - _fine_count
		if remaining <= 20:
			if remaining <= 10:
				# Solid red when 10 or fewer remain
				_fine_label.modulate = Color.RED
			else:
				# Lerp from white (20 away) to yellow (11 away)
				var urgency := 1.0 - (remaining - 11) / 9.0
				_fine_label.modulate = Color.WHITE.lerp(Color.YELLOW, urgency)
	
	_fine_label.text = "FINEs: %d%s" % [_fine_count, fine_limit_text]

func _on_note_judged(judgement_info: Dictionary) -> void:
	if _failed or _game == null:
		return
	
	# Ignore editor / preview / non-normal modes
	if _game.editing or _game.previewing:
		return
	if _game.game_mode != HBRhythmGameBase.GAME_MODE.NORMAL:
		return
	
	var rating: int = int(judgement_info.get("judgement", HBJudge.JUDGE_RATINGS.COOL))
	var wrong: bool = bool(judgement_info.get("wrong", false))
	
	var settings := modifier_settings as PerfectRunSettings
	
	# Base threshold: FINE or better, unless COOL-only is set.
	var min_rating: int = HBJudge.JUDGE_RATINGS.FINE
	if settings and settings.cool_only:
		min_rating = HBJudge.JUDGE_RATINGS.COOL
	
	# Normal Perfect Run fail condition
	var is_bad := rating < min_rating or wrong
	if is_bad:
		_failed = true
		_game.emit_signal("game_over")
		return
	
	# Optional FINE tracking / limit (only in non-COOL-only mode)
	if settings and not settings.cool_only:
		if rating == HBJudge.JUDGE_RATINGS.FINE:
			_fine_count += 1
			_update_fine_window()
			
			if settings.fine_limit > 0 and _fine_count > settings.fine_limit:
				_failed = true
				_game.emit_signal("game_over")
				return
	else:
		# COOL-only mode: no FINEs allowed anyway; just keep label in sync.
		_update_fine_window()

static func get_modifier_name():
	return TranslationServer.tr("Perfect Run", &"Perfect Run modifier name")

func get_modifier_list_name():
	var settings := modifier_settings as PerfectRunSettings
	if settings:
		if settings.cool_only:
			return TranslationServer.tr("Perfect Run (COOL only)", &"Perfect Run modifier list name COOL only")
		if settings.fine_limit > 0:
			return TranslationServer.tr("Perfect Run (FINE limit)", &"Perfect Run modifier list name with FINE limit")
	return TranslationServer.tr("Perfect Run", &"Perfect Run modifier list name")

static func get_modifier_description():
	return TranslationServer.tr(
		"Fails the song on the first non-passing hit. Can upload scores to leaderboard.",
		&"Perfect Run modifier description"
	)

static func get_modifier_settings_class() -> Script:
	return PerfectRunSettings

static func get_option_settings() -> Dictionary:
	return {
		"cool_only": {
			"name": TranslationServer.tr("COOL-only mode", &"Perfect Run COOL only option name"),
			"description": TranslationServer.tr("If enabled, only COOL hits are allowed. FINE will also fail the run.", &"Perfect Run COOL only option description"),
			"default_value": false
		},
		"fine_limit": {
			"name": TranslationServer.tr("FINE limit", &"Perfect Run FINE limit option name"),
			"description": TranslationServer.tr("If greater than 0, the run fails once you exceed this number of FINE judgements. 0 disables the limit.", &"Perfect Run FINE limit option description"),
			"default_value": 0,
			"minimum": 0,
			"maximum": 999,
			"step": 1
		},
		"show_fine_counter": {
			"name": TranslationServer.tr("Show FINE counter", &"Perfect Run show FINE counter option name"),
			"description": TranslationServer.tr("Display a counter showing FINE judgements during gameplay.", &"Perfect Run show FINE counter option description"),
			"default_value": true
		}
	}
static func is_leaderboard_legal() -> bool:
	return true
