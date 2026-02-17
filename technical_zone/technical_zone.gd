extends HBModifier
class_name TechnicalZoneModifier

const TechnicalZoneSettings := preload("res://rythm_game/modifiers/technical_zone/technical_zone_settings.gd")

const MIN_JUDGEMENT := 3 # FINE or better required (same as editor scripts)

var _game: HBRhythmGame = null

# All TZ zones parsed from the chart: Array of {start, end, penalty, failed, notes_hit, total_notes}
var _zones: Array = []

# Index of the currently active zone (-1 if none)
var _active_zone_idx: int = -1

# UI
var _counter_panel: PanelContainer = null
var _counter_label: Label = null

func _init() -> void:
	disables_video = false
	processing_notes = false
	modifier_settings = get_modifier_settings_class().new()

func _preprocess_timing_points(points: Array) -> Array:
	# Build zones here — this fires after _pre_game so _zones may be populated
	# after signals/UI are already set up, which is fine since _on_time_changed
	# won't activate any zone until _zones has entries
	_zones = _build_zones(points)
	return points

func _pre_game(song: HBSong, game: HBRhythmGame) -> void:
	_game = game
	_active_zone_idx = -1

	# Always connect signals and create UI — _zones may not be populated yet
	# since _preprocess_timing_points fires after _pre_game in the load order
	if not _game.is_connected("note_judged", Callable(self, "_on_note_judged")):
		_game.connect("note_judged", Callable(self, "_on_note_judged"))

	if not _game.is_connected("restarting", Callable(self, "_on_restart")):
		_game.connect("restarting", Callable(self, "_on_restart"))

	if not _game.is_connected("time_changed", Callable(self, "_on_time_changed")):
		_game.connect("time_changed", Callable(self, "_on_time_changed"))

	_create_counter_ui()
	_hide_counter()

func _post_game(song: HBSong, game: HBRhythmGame) -> void:
	if _game:
		if _game.is_connected("note_judged", Callable(self, "_on_note_judged")):
			_game.disconnect("note_judged", Callable(self, "_on_note_judged"))
		if _game.is_connected("restarting", Callable(self, "_on_restart")):
			_game.disconnect("restarting", Callable(self, "_on_restart"))
		if _game.is_connected("time_changed", Callable(self, "_on_time_changed")):
			_game.disconnect("time_changed", Callable(self, "_on_time_changed"))
	_game = null
	_zones.clear()
	_active_zone_idx = -1
	_destroy_counter_ui()

func _on_restart() -> void:
	_active_zone_idx = -1
	for zone in _zones:
		zone.failed = false
		zone.notes_hit = 0
	_hide_counter()

# ─────────────────────────────────────────────
# Zone building
# ─────────────────────────────────────────────

func _build_zones(points: Array) -> Array:
	var markers: Array = []
	for point in points:
		if not (point is HBTimingPoint):
			continue
		if point._class_name != "HBMetadata":
			continue
		var k: String = str(point.meta.get("key", ""))
		if k == "TZ start":
			markers.append({
				"key": "TZ start",
				"time": point.time,
				"penalty": clamp(float(point.meta.get("value", 0.0)), 0.0, 30.0)
			})
		elif k == "TZ end":
			markers.append({"key": "TZ end", "time": point.time})

	markers.sort_custom(func(a, b): return a.time < b.time)

	var zones: Array = []
	var pending = null
	for marker in markers:
		if marker.key == "TZ start":
			pending = marker
		elif marker.key == "TZ end" and pending != null:
			var total := _count_notes_in_zone(points, pending.time, marker.time)
			zones.append({
				"start": pending.time,
				"end": marker.time,
				"penalty": pending.penalty,
				"failed": false,
				"notes_hit": 0,
				"total_notes": total
			})
			pending = null

	return zones


func _count_notes_in_zone(points: Array, start_time: int, end_time: int) -> int:
	var note_times := {}
	var sustain_releases := 0
	for point in points:
		if not (point is HBBaseNote):
			continue
		
		# Skip slide chain pieces — they don't generate judgements
		# Check both via method and via note_type for safety
		if point is HBNoteData:
			if point.is_slide_hold_piece():
				continue
			# Also check note_type directly (6 or 7 are chain pieces)
			var nt = point.note_type
			if nt == 6 or nt == 7:
				continue
		
		var t: int = point.time
		if t < start_time or t > end_time:
			continue
		
		note_times[t] = true
		
		# Sustain releases are individual judgements
		if point is HBSustainNote and not (point is HBRushNote):
			var end_t: int = point.end_time
			if end_t >= start_time and end_t <= end_time:
				sustain_releases += 1
	
	return note_times.size() + sustain_releases

# ─────────────────────────────────────────────
# Time tracking — activate/deactivate zones
# ─────────────────────────────────────────────

func _on_time_changed(time_sec: float) -> void:
	if _game == null or _game.editing or _game.previewing:
		return
	if _game.game_mode != HBRhythmGameBase.GAME_MODE.NORMAL:
		return

	var time_ms: int = int(time_sec * 1000.0)

	# Check if we need to activate a new zone
	if _active_zone_idx == -1:
		for i in _zones.size():
			var zone = _zones[i]
			if zone.failed:
				continue
			if time_ms >= zone.start and time_ms < zone.end:
				_active_zone_idx = i
				_show_counter(zone)
				break

	# Check if the active zone has ended
	if _active_zone_idx != -1:
		var zone = _zones[_active_zone_idx]
		if time_ms >= zone.end:
			if not zone.failed:
				# Zone completed without failure
				if zone.notes_hit >= zone.total_notes:
					_show_result("Complete!", Color(0.2, 1.0, 0.2, 1.0))
				else:
					_show_result("%d / %d" % [zone.notes_hit, zone.total_notes], Color(1.0, 0.85, 0.3, 1.0))
			_active_zone_idx = -1

# ─────────────────────────────────────────────
# Note judging
# ─────────────────────────────────────────────

func _on_note_judged(judgement_info: Dictionary) -> void:
	if _game == null or _game.editing or _game.previewing:
		return
	if _game.game_mode != HBRhythmGameBase.GAME_MODE.NORMAL:
		return
	if _active_zone_idx == -1:
		return

	var zone = _zones[_active_zone_idx]
	if zone.failed:
		return

	var target_time: int = judgement_info.get("target_time", -1)
	if target_time < zone.start or target_time > zone.end:
		return

	var judgement: int = judgement_info.get("judgement", -1)
	var wrong: bool = judgement_info.get("wrong", false)

	if judgement < MIN_JUDGEMENT or wrong:
		zone.failed = true
		# Convert penalty from percentage (10.0) to decimal ratio (0.10)
		_game.result.add_percentage_penalty(zone.penalty / 100.0)
		var fail_text := "Fail!"
		if zone.penalty > 0.0:
			fail_text = "Fail! -%.0f%%" % zone.penalty
		_show_result(fail_text, Color(1.0, 0.2, 0.2, 1.0))
		_active_zone_idx = -1
		return

	zone.notes_hit += 1
	_update_counter(zone)

	if zone.notes_hit >= zone.total_notes:
		_show_result("Complete!", Color(0.2, 1.0, 0.2, 1.0))
		_active_zone_idx = -1

# ─────────────────────────────────────────────
# UI
# ─────────────────────────────────────────────

func _create_counter_ui() -> void:
	_destroy_counter_ui()

	if not _game or not _game.game_ui:
		return

	var panel := PanelContainer.new()
	panel.name = "TZCounterPanel"
	
	# Anchor to top-right instead of top-left
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 0.0

	var width := 260.0
	var height := 48.0
	var right_margin := 135.0
	var top := 100.0
	
	# Position from the right edge
	panel.offset_left = -width - right_margin
	panel.offset_top = top
	panel.offset_right = -right_margin
	panel.offset_bottom = top + height
	panel.custom_minimum_size = Vector2(width, height)
	
	# Add visual styling - dark background with blue border
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.9)
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.border_color = Color(0.3, 0.7, 1.0, 1.0)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Technical Zone"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(title)

	var label := Label.new()
	label.name = "CounterLabel"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(label)

	_game.game_ui.add_child(panel)
	_counter_panel = panel
	_counter_label = label


func _destroy_counter_ui() -> void:
	if _counter_panel and is_instance_valid(_counter_panel):
		_counter_panel.queue_free()
	_counter_panel = null
	_counter_label = null


func _hide_counter() -> void:
	if _counter_panel:
		_counter_panel.visible = false


func _show_counter(zone: Dictionary) -> void:
	if not _counter_panel:
		return
	_counter_panel.visible = true
	_update_counter(zone)


func _update_counter(zone: Dictionary) -> void:
	if not _counter_label:
		return
	_counter_label.modulate = Color.WHITE
	_counter_label.text = "%d / %d" % [zone.notes_hit, zone.total_notes]


func _show_result(result_text: String, color: Color) -> void:
	if not _counter_label:
		return
	_counter_label.modulate = color
	_counter_label.text = result_text

	# Fade out after 1 second
	var panel := _counter_panel
	var tree := _game.get_tree() if _game else null
	if tree == null:
		_hide_counter()
		return
	tree.create_timer(1.0).timeout.connect(func():
		if panel and is_instance_valid(panel):
			var tween := panel.create_tween()
			tween.tween_property(panel, "modulate:a", 0.0, 0.3)
			tween.finished.connect(func():
				if panel and is_instance_valid(panel):
					panel.modulate.a = 1.0
					panel.visible = false
			)
	)

# ─────────────────────────────────────────────
# Modifier metadata
# ─────────────────────────────────────────────

static func get_modifier_name():
	return TranslationServer.tr("Technical Zone", &"Technical Zone modifier name")

func get_modifier_list_name():
	return get_modifier_name()

static func get_modifier_description():
	return TranslationServer.tr(
		"Tracks Technical Zones defined by the charter. Missing a note in a zone applies a percentage penalty.",
		&"Technical Zone modifier description"
	)

static func get_modifier_settings_class() -> Script:
	return TechnicalZoneSettings

static func get_option_settings() -> Dictionary:
	return {}

static func is_leaderboard_legal() -> bool:
	return true
