extends HBModifier

const ArcadeDoublerSettings = preload("res://rythm_game/modifiers/arcade_doubler/arcade_doubler_settings.gd")

# ─────────────────────────────────────────────────────────────────────
# Arcade Doubler
#
# Lets an arcade controller play double notes (the "fat arrow" notes
# that require two distinct physical inputs to be pressed at once).
#
# Mechanism: when the player presses a directional button, we inject a
# phantom press of the same action with a different event_uid. The
# chart engine's double-note judgment looks for two press events on
# the same action from different sources within its timing window; the
# phantom satisfies the second-source requirement.
#
# Singles ignore the phantom (the second press just lands on empty
# air after the single has already been judged). Sustains and holds
# are not doubled — they only need one input to be held, and adding a
# phantom hold would create cleanup complexity for no benefit.
#
# This modifier disables leaderboard submission because it materially
# reduces input difficulty on arcade controllers.
# ─────────────────────────────────────────────────────────────────────

# Actions to double. Directional taps only — slides and heart_note are
# left alone, and sustain holds piggyback on the directional press but
# don't need the phantom release.
const DOUBLED_ACTIONS := ["note_up", "note_down", "note_left", "note_right"]

# Bit we OR into the event_uid of a phantom press so we can identify
# our own injections and avoid re-doubling them. Chosen high enough
# that it won't collide with real UIDs from get_event_uid (which
# combines device_idx and scancode/button into the low bits).
const SYNTHETIC_UID_FLAG := 1 << 30

var _input_manager: HBGameInputManager = null

func _init():
	modifier_settings = get_modifier_settings_class().new()

func _init_plugin():
	# Base init plugin must always be called after local init
	super._init_plugin()

func _pre_game(song: HBSong, game: HBRhythmGame):
	_input_manager = game.game_input_manager
	if _input_manager == null:
		push_warning("ArcadeDoubler: game.game_input_manager was null; modifier inactive")
		return
	_input_manager.input_out.connect(_on_input_out)

func _post_game(song: HBSong, game: HBRhythmGame):
	if _input_manager != null and _input_manager.input_out.is_connected(_on_input_out):
		_input_manager.input_out.disconnect(_on_input_out)
	_input_manager = null

func _on_input_out(event: InputEventHB) -> void:
	# Only press events; releases are stateless for double-note judgment.
	if not event.pressed:
		return
	# Only directional taps.
	if not event.action in DOUBLED_ACTIONS:
		return
	# Skip our own phantom presses to avoid an infinite loop.
	if event.event_uid & SYNTHETIC_UID_FLAG:
		return

	# Inject a phantom press of the same action. We give it a UID
	# distinct from the original so the chart engine treats it as a
	# second input source. Everything else (action, actions list,
	# timestamp, triggered_actions_count) we mirror from the real
	# event so the phantom looks like a sibling press, not a stranger.
	var synthetic_uid: int = event.event_uid | SYNTHETIC_UID_FLAG
	_input_manager.send_input(
		event.action,
		true,
		event.triggered_actions_count,
		synthetic_uid,
		event.actions,
		event.timestamp_usec
	)

# ─────────────────────────────────────────────────────────────────────
# Modifier metadata
# ─────────────────────────────────────────────────────────────────────

static func get_modifier_name():
	return "Arcade Doubler"

func get_modifier_list_name():
	return "Arcade Doubler"

static func get_modifier_description():
	return "Arcade controller: every directional press counts as a double press, so double notes (the 'fat arrow' notes from console charts) can be hit with a single input. Disables leaderboard submission."

static func get_modifier_settings_class() -> Script:
	return ArcadeDoublerSettings

static func is_leaderboard_legal() -> bool:
	return false
