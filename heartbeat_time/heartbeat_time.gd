extends HBModifier
class_name HeartbeatTimeModifier

const HeartbeatTimeSettings := preload("res://rythm_game/modifiers/heartbeat_time/heartbeat_time_settings.gd")
const HeartbeatTimeBorderScene := preload("res://rythm_game/modifiers/heartbeat_time/HeartbeatTimeBorder.tscn")

const MIN_JUDGEMENT := 3 # FINE or better required (same as TZ and editor scripts)
const THRESHOLD := 0.75
const FAIL_PENALTY := 0.30      # 30% score deduction on fail (decimal ratio)
const FAIL_PENALTY_DISPLAY := 30.0   # display percentage shown to player

# Rainbow animation tuning
const RAINBOW_SPEED := 0.6      # cycles per second through the hue wheel
const RAINBOW_SATURATION := 0.85
const RAINBOW_VALUE := 1.0

var _game: HBRhythmGame = null

# All HBT zones parsed from the chart. Each zone is a Dict:
#   {start, qualifier_time, qualifier_notes_total,
#    total_regular, notes_hit, qualifier_notes_hit,
#    threshold_latched, resolved}
var _zones: Array = []

# Index of the currently active zone (-1 if none)
var _active_zone_idx: int = -1

# UI
var _counter_panel: PanelContainer = null
var _counter_title: Label = null
var _counter_label: Label = null
var _border_instance: Control = null

# Rainbow animation state
var _rainbow_phase: float = 0.0


func _init() -> void:
	disables_video = false
	processing_notes = false
	modifier_settings = get_modifier_settings_class().new()


func _preprocess_timing_points(points: Array) -> Array:
	# Build zones here — fires after _pre_game, so _zones may be populated
	# after signals/UI are already set up. _on_time_changed won't activate
	# any zone until _zones has entries, so this ordering is fine.
	_zones = _build_zones(points)
	return points


func _pre_game(song: HBSong, game: HBRhythmGame) -> void:
	_game = game
	_active_zone_idx = -1
	_rainbow_phase = 0.0
	_last_frame_usec = 0   # reset so first frame computes delta=0, not a giant value
	
	if not _game.is_connected("note_judged", Callable(self, "_on_note_judged")):
		_game.connect("note_judged", Callable(self, "_on_note_judged"))
	
	if not _game.is_connected("restarting", Callable(self, "_on_restart")):
		_game.connect("restarting", Callable(self, "_on_restart"))
	
	if not _game.is_connected("time_changed", Callable(self, "_on_time_changed")):
		_game.connect("time_changed", Callable(self, "_on_time_changed"))
	
	# Drive the rainbow animation off the scene tree's per-frame signal.
	# HBModifier isn't a Node, so we can't use _process directly — process_frame
	# is the equivalent for non-Node objects.
	var tree := _game.get_tree()
	if tree and not tree.is_connected("process_frame", Callable(self, "_on_process_frame")):
		tree.connect("process_frame", Callable(self, "_on_process_frame"))
	
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
		var tree := _game.get_tree()
		if tree and tree.is_connected("process_frame", Callable(self, "_on_process_frame")):
			tree.disconnect("process_frame", Callable(self, "_on_process_frame"))
	_game = null
	_zones.clear()
	_active_zone_idx = -1
	_destroy_counter_ui()


func _on_restart() -> void:
	_active_zone_idx = -1
	_rainbow_phase = 0.0
	for zone in _zones:
		zone.notes_hit = 0
		zone.qualifier_notes_hit = 0
		zone.threshold_latched = false
		zone.resolved = false
	_hide_counter()


# ─────────────────────────────────────────────
# Zone building
# ─────────────────────────────────────────────

func _build_zones(points: Array) -> Array:
	# Step 1: collect HBT start markers and qualifier-flagged notes (with their
	# chord-mate counts). Done in a single sorted pass.
	var hbt_starts: Array = []                # Array of int (times)
	var qualifier_times: Array = []           # Array of int (times that contain a qualifier-flagged note)
	var notes_at_time: Dictionary = {}        # time:int -> int (count of judgement-firing notes at that time)
	
	for point in points:
		if not (point is HBTimingPoint):
			continue
		
		# HBT start metadata markers
		if point._class_name == "HBMetadata":
			var k: String = str(point.meta.get("key", ""))
			if k == "HBT start":
				hbt_starts.append(int(point.time))
			continue
		
		# Notes — count and check for qualifier flag
		if point is HBBaseNote:
			# Skip slide chain pieces (they don't fire judgement)
			var skip := false
			if point is HBNoteData:
				if point.is_slide_hold_piece():
					skip = true
				else:
					var nt = point.note_type
					if nt == 6 or nt == 7:
						skip = true
			if skip:
				continue
			
			var t: int = int(point.time)
			notes_at_time[t] = int(notes_at_time.get(t, 0)) + 1
			
			var pmeta = point.meta
			if pmeta is Dictionary and bool(pmeta.get("qualifier", false)):
				if not (t in qualifier_times):
					qualifier_times.append(t)
			
			# Sustain releases also fire judgement at end_time — count them
			# in notes_at_time so a chord at qualifier_time that includes a
			# sustain end gets the right count.
			if point is HBSustainNote and not (point is HBRushNote):
				var end_t: int = int(point.end_time)
				notes_at_time[end_t] = int(notes_at_time.get(end_t, 0)) + 1
	
	hbt_starts.sort()
	qualifier_times.sort()
	
	# Step 2: pair each HBT start with the first qualifier_time at or after it,
	# bounded by the next HBT start (zones don't overlap).
	var zones: Array = []
	for i in hbt_starts.size():
		var s_time: int = hbt_starts[i]
		var next_start_time: int = 999999999
		if i + 1 < hbt_starts.size():
			next_start_time = hbt_starts[i + 1]
		
		var found_qt: int = -1
		for qt in qualifier_times:
			if qt >= s_time and qt < next_start_time:
				found_qt = qt
				break
		
		if found_qt == -1:
			# Forgotten Qualifier — skip the zone, log it, keep going.
			# The chart still plays, just without this HBT zone resolving.
			push_warning("[HeartbeatTime] HBT start at %d ms has no Qualifier-flagged note before next zone — skipping." % s_time)
			continue
		
		var q_count: int = int(notes_at_time.get(found_qt, 1))
		var total_regular: int = _count_regular_notes_in_zone(points, s_time, found_qt)
		
		zones.append({
			"start": s_time,
			"qualifier_time": found_qt,
			"qualifier_notes_total": q_count,
			"total_regular": total_regular,
			"notes_hit": 0,
			"qualifier_notes_hit": 0,
			"threshold_latched": false,
			"resolved": false,
		})
	
	return zones


func _count_regular_notes_in_zone(points: Array, start_time: int, qualifier_time: int) -> int:
	# Count judgements in [start_time, qualifier_time) — exclusive upper bound
	# so the qualifier chord is not part of the 75% threshold pool.
	var note_times := {}
	var sustain_releases := 0
	
	for point in points:
		if not (point is HBBaseNote):
			continue
		
		# Skip slide chain pieces
		if point is HBNoteData:
			if point.is_slide_hold_piece():
				continue
			var nt = point.note_type
			if nt == 6 or nt == 7:
				continue
		
		var t: int = int(point.time)
		if t < start_time or t >= qualifier_time:
			continue
		
		note_times[t] = true
		
		# Sustain release counts only if it lands before the qualifier
		if point is HBSustainNote and not (point is HBRushNote):
			var end_t: int = int(point.end_time)
			if end_t >= start_time and end_t < qualifier_time:
				sustain_releases += 1
	
	return note_times.size() + sustain_releases


# ─────────────────────────────────────────────
# Time tracking — activate zones
# ─────────────────────────────────────────────
# Note: unlike TZ, HBT does NOT deactivate on a fixed end time. The zone
# resolves when the qualifier-time chord is judged. _on_time_changed only
# handles activation here; resolution is _on_note_judged's job.

func _on_time_changed(time_sec: float) -> void:
	if _game == null or _game.editing or _game.previewing:
		return
	if _game.game_mode != HBRhythmGameBase.GAME_MODE.NORMAL:
		return
	
	var time_ms: int = int(time_sec * 1000.0)
	
	# Activate a zone if we're inside one and don't have one active
	if _active_zone_idx == -1:
		for i in _zones.size():
			var zone = _zones[i]
			if zone.resolved:
				continue
			if time_ms >= zone.start and time_ms <= zone.qualifier_time:
				_active_zone_idx = i
				_show_counter(zone)
				break


# ─────────────────────────────────────────────
# Note judging — the heart of HBT logic
# ─────────────────────────────────────────────

func _on_note_judged(judgement_info: Dictionary) -> void:
	if _game == null or _game.editing or _game.previewing:
		return
	if _game.game_mode != HBRhythmGameBase.GAME_MODE.NORMAL:
		return
	if _active_zone_idx == -1:
		return
	
	var zone = _zones[_active_zone_idx]
	if zone.resolved:
		return
	
	var target_time: int = judgement_info.get("target_time", -1)
	
	# Out of zone entirely
	if target_time < zone.start or target_time > zone.qualifier_time:
		return
	
	var judgement: int = judgement_info.get("judgement", -1)
	var wrong: bool = judgement_info.get("wrong", false)
	var clean_hit: bool = (judgement >= MIN_JUDGEMENT) and not wrong
	
	# QUALIFIER-TIME NOTE — resolution logic
	if target_time == zone.qualifier_time:
		if not clean_hit:
			# Any miss/wrong on the qualifier chord = immediate fail
			_resolve_fail(zone)
			return
		
		zone.qualifier_notes_hit += 1
		
		# Wait for the whole qualifier chord to land before evaluating
		if zone.qualifier_notes_hit >= zone.qualifier_notes_total:
			_evaluate_and_resolve(zone)
		return
	
	# REGULAR NOTE — accumulates toward the 75% threshold.
	# Misses do NOT fail the zone (per spec); they just don't count.
	if not clean_hit:
		return
	
	zone.notes_hit += 1
	_update_counter(zone)
	
	# Threshold latch — fires once when crossing 75%, persists through resolution
	if not zone.threshold_latched and zone.total_regular > 0:
		var pct = float(zone.notes_hit) / float(zone.total_regular)
		if pct >= THRESHOLD:
			zone.threshold_latched = true


func _evaluate_and_resolve(zone: Dictionary) -> void:
	var pct: float = 0.0
	if zone.total_regular > 0:
		pct = float(zone.notes_hit) / float(zone.total_regular)
	
	if pct >= THRESHOLD:
		_resolve_pass(zone, pct)
	else:
		_resolve_fail(zone)


func _resolve_pass(zone: Dictionary, final_pct: float) -> void:
	zone.resolved = true
	zone.threshold_latched = false   # stop rainbow animation; pass color takes over
	# Round to integer percent — matches the live counter display
	var pct_int: int = int(round(final_pct * 100.0))
	_show_result("%d%% Qualified!" % pct_int, Color(0.2, 1.0, 0.2, 1.0))
	_active_zone_idx = -1


func _resolve_fail(zone: Dictionary) -> void:
	zone.resolved = true
	zone.threshold_latched = false
	# Apply the 30% score penalty. The combined cap with TZ is enforced
	# inside add_percentage_penalty (or its accumulator) — we just contribute
	# our portion here.
	if _game and _game.result:
		_game.result.add_percentage_penalty(FAIL_PENALTY)
	_show_result("Disqualified!", Color(1.0, 0.2, 0.2, 1.0))
	_active_zone_idx = -1


# ─────────────────────────────────────────────
# Per-frame work — rainbow animation only
# ─────────────────────────────────────────────

var _last_frame_usec: int = 0

func _on_process_frame() -> void:
	# Compute delta ourselves — process_frame is a no-arg signal.
	var now_usec: int = Time.get_ticks_usec()
	var delta: float = 0.0
	if _last_frame_usec != 0:
		delta = float(now_usec - _last_frame_usec) / 1_000_000.0
	_last_frame_usec = now_usec
	
	# Rainbow animation runs whenever an active zone has the threshold latched.
	if _active_zone_idx == -1:
		return
	if _counter_label == null or not is_instance_valid(_counter_label):
		return
	
	var zone = _zones[_active_zone_idx]
	if not zone.threshold_latched:
		return
	
	_rainbow_phase = fposmod(_rainbow_phase + delta * RAINBOW_SPEED, 1.0)
	var rainbow_color = Color.from_hsv(_rainbow_phase, RAINBOW_SATURATION, RAINBOW_VALUE)
	_counter_label.modulate = rainbow_color


# ─────────────────────────────────────────────
# UI
# ─────────────────────────────────────────────

func _create_counter_ui() -> void:
	_destroy_counter_ui()
	
	if not _game or not _game.game_ui:
		return
	
	var panel := PanelContainer.new()
	panel.name = "HBTCounterPanel"
	
	# Top-center anchoring — distinct from TZ (top-right) and Perfect Run.
	# anchor_left = anchor_right = 0.5 puts the anchor at horizontal center;
	# offsets pull half the width to either side so the panel is centered.
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.0
	panel.anchor_bottom = 0.0
	
	var width := 260.0
	var height := 48.0
	var top := 100.0
	
	panel.offset_left = -width / 2.0
	panel.offset_top = top
	panel.offset_right = width / 2.0
	panel.offset_bottom = top + height
	panel.custom_minimum_size = Vector2(width, height)
	
	# Match TZ's visual style — dark bg, blue border — for family resemblance
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
	title.text = "Heartbeat Time"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(title)
	
	var label := Label.new()
	label.name = "CounterLabel"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(label)
	
	_game.game_ui.add_child(panel)
	_counter_panel = panel
	_counter_title = title
	_counter_label = label


func _destroy_counter_ui() -> void:
	if _counter_panel and is_instance_valid(_counter_panel):
		_counter_panel.queue_free()
	_counter_panel = null
	_counter_title = null
	_counter_label = null
	_destroy_border_ui()


func _hide_counter() -> void:
	if _counter_panel:
		_counter_panel.visible = false
	_hide_border()


func _show_border() -> void:
	if not _game or not _game.game_ui:
		return
	if _border_instance and is_instance_valid(_border_instance):
		_border_instance.modulate.a = 1.0
		_border_instance.visible = true
		return
	var border = HeartbeatTimeBorderScene.instantiate()
	_game.game_ui.add_child(border)
	_border_instance = border


func _hide_border() -> void:
	if _border_instance and is_instance_valid(_border_instance):
		_border_instance.visible = false


func _destroy_border_ui() -> void:
	if _border_instance and is_instance_valid(_border_instance):
		_border_instance.queue_free()
	_border_instance = null


func _show_counter(zone: Dictionary) -> void:
	if not _counter_panel:
		return
	_counter_panel.visible = true
	_counter_panel.modulate.a = 1.0
	_show_border()
	if _game and _game.game_ui:
		var gui = _game.game_ui
		gui.get_node("UnderNotesUI/Control").visible = false
		gui.get_node("AboveNotesUI/Control").visible = false
	_update_counter(zone)


func _update_counter(zone: Dictionary) -> void:
	if not _counter_label:
		return
	# Don't override modulate during rainbow — _process is driving it
	if not zone.threshold_latched:
		_counter_label.modulate = Color.WHITE
	
	var pct: int = 0
	if zone.total_regular > 0:
		pct = int(round(float(zone.notes_hit) / float(zone.total_regular) * 100.0))
	_counter_label.text = "%d%%" % pct


func _show_result(result_text: String, color: Color) -> void:
	if not _counter_label:
		return
	_counter_label.modulate = color
	_counter_label.text = result_text
	
	# Fade out after 1 second — same pattern as TZ
	var panel := _counter_panel
	var border := _border_instance
	var game_ui = _game.game_ui if _game else null
	var tree := _game.get_tree() if _game else null
	if tree == null:
		_hide_counter()
		return
	tree.create_timer(1.0).timeout.connect(func():
		if game_ui and is_instance_valid(game_ui):
			game_ui.get_node("UnderNotesUI/Control").visible = true
			game_ui.get_node("AboveNotesUI/Control").visible = true
		if panel and is_instance_valid(panel):
			var tween := panel.create_tween()
			tween.tween_property(panel, "modulate:a", 0.0, 0.3)
			tween.finished.connect(func():
				if panel and is_instance_valid(panel):
					panel.modulate.a = 1.0
					panel.visible = false
			)
		if border and is_instance_valid(border):
			var tween_b := border.create_tween()
			tween_b.tween_property(border, "modulate:a", 0.0, 0.3)
			tween_b.finished.connect(func():
				if border and is_instance_valid(border):
					border.modulate.a = 1.0
					border.visible = false
			)
	)


# ─────────────────────────────────────────────
# Modifier metadata
# ─────────────────────────────────────────────

static func get_modifier_name():
	return TranslationServer.tr("Heartbeat Time", &"Heartbeat Time modifier name")


func get_modifier_list_name():
	return get_modifier_name()


static func get_modifier_description():
	return TranslationServer.tr(
		"Tracks Heartbeat Time zones defined by the charter. Hit at least 75% of notes in the zone and land the Qualifier note to pass; falling short or missing the Qualifier applies a percentage penalty.",
		&"Heartbeat Time modifier description"
	)


static func get_modifier_settings_class() -> Script:
	return HeartbeatTimeSettings


static func get_option_settings() -> Dictionary:
	return {}


static func is_leaderboard_legal() -> bool:
	return true
