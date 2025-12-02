#meta:name:Mirai Link (Timeout Parity + VFX Line)
#meta:description:Mirai-style link using GAME TIMEOUT + gap for icon travel, and writes a $MIRAI_LINK VFX row so the PH VFX modifier can draw a line between the notes.
#meta:usage:Select the ordered notes and press Run. First selected = start, last selected = end.
#meta:preview:true

extends ScriptRunnerScript

const NOTE_TYPE_NAMES := {
	0: "UP", 1: "LEFT", 2: "DOWN", 3: "RIGHT",
	4: "SLIDE_LEFT", 5: "SLIDE_RIGHT",
	6: "SLIDE_CHAIN_PIECE_LEFT", 7: "SLIDE_CHAIN_PIECE_RIGHT",
	8: "HEART"
}

# ─────────────────────────────────────────────
# Small math helpers
# ─────────────────────────────────────────────

func distance(x: Vector2, y: Vector2) -> float:
	return sqrt(pow(y.x - x.x, 2) + pow(y.y - x.y, 2))

func connection_vector(v1: Vector2, v2: Vector2) -> Vector2:
	return Vector2(v2.x - v1.x, v2.y - v1.y)

# ─────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────

func run_script() -> int:
	var selected_timing_points := get_selected_timing_points()
	var selected_point_count := selected_timing_points.size()

	if selected_point_count < 2:
		printerr("[MiraiLinkVFX] ❌ Need at least 2 notes selected.")
		return ERR_DOES_NOT_EXIST

	var first_tp = selected_timing_points[0]
	var last_tp	 = selected_timing_points[selected_point_count - 1]

	# Resolve data/type/time for the FIRST note (used for timeout parity)
	var first_core := _resolve_note_core(first_tp)
	var first_data = first_core[0]
	var first_type = first_core[1]
	var first_time_ms = first_core[2]

	var last_core := _resolve_note_core(last_tp)
	var last_time_ms = last_core[2]


	# Gap between first and last in ms
	var gap_ms: int = last_time_ms - first_time_ms
	if gap_ms < 0:
		gap_ms = 0

	# GAME TIMEOUT parity: how long before FIRST hit the icon normally travels
	var base_timeout_ms := _compute_timeout_ms(first_type, first_data, first_time_ms)

	# Total travel time = spawn lead + gap between notes
	var total_timeout_ms: int = base_timeout_ms + gap_ms
	if total_timeout_ms <= 0:
		# Fallbacks if timeout can't be determined
		total_timeout_ms = gap_ms
	if total_timeout_ms <= 0:
		total_timeout_ms = 2000	 # hard fallback, 2s

	print("[MiraiLinkVFX] base_timeout_ms=", base_timeout_ms,
		" gap_ms=", gap_ms, " total_timeout_ms=", total_timeout_ms)

	# ── Mirai behavior with timeout parity ──────────────────────────────

	# First note
	set_timing_point_property(first_tp, "distance", distance(last_tp.position, first_tp.position))
	set_timing_point_property(first_tp, "auto_time_out", false)
	set_timing_point_property(first_tp, "time_out", total_timeout_ms)
	set_timing_point_property(first_tp, "oscillation_amplitude", 0)
	set_timing_point_property(first_tp, "oscillation_frequency", -2)
	set_timing_point_property(
		first_tp,
		"entry_angle",
		Vector2.ZERO.angle_to_point(connection_vector(last_tp.position, first_tp.position)) / TAU * 360.0
	)

	# Middle notes: hide their icons, keep same timeout so their rings/logic are consistent
	for i in range(1, selected_point_count - 1):
		var mid = selected_timing_points[i]
		set_timing_point_property(mid, "distance", 9.0e18)
		set_timing_point_property(mid, "auto_time_out", false)
		set_timing_point_property(mid, "time_out", total_timeout_ms)
		set_timing_point_property(mid, "entry_angle", 270.0)

	# Last note
	set_timing_point_property(last_tp, "distance", distance(last_tp.position, first_tp.position))
	set_timing_point_property(last_tp, "auto_time_out", false)
	set_timing_point_property(last_tp, "time_out", total_timeout_ms)
	set_timing_point_property(last_tp, "oscillation_amplitude", 0)
	set_timing_point_property(last_tp, "oscillation_frequency", 2)
	set_timing_point_property(
		last_tp,
		"entry_angle",
		Vector2.ZERO.angle_to_point(connection_vector(last_tp.position, first_tp.position)) / TAU * 360.0
	)

	# ── NEW: write VFX link row for the MightyModifier ──────────────────
	_write_vfx_link_row(first_tp, last_tp)

	print("[MiraiLinkVFX] ✅ Linked ", selected_point_count,
		" notes (timeout parity) and wrote VFX link row.")
	return OK

# ─────────────────────────────────────────────
# VFX JSON: write $MIRAI_LINK row
# ─────────────────────────────────────────────

func _write_vfx_link_row(first_src: Object, last_src: Object) -> void:
	var path := _get_vfx_path()
	if path == "":
		printerr("[MiraiLinkVFX] ⚠️ No VFX path, skipping link row.")
		return

	var existing: Array = []
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f:
			var parsed := JSON.parse_string(f.get_as_text())
			if typeof(parsed) == TYPE_ARRAY:
				existing = parsed
			f.close()

	# ⬇️ NEW: keep everything we already have, including old $MIRAI_LINK rows
	var preserved: Array = existing.duplicate()

	var head_key := _make_note_key(first_src)
	var tail_key := _make_note_key(last_src)

	if head_key == "" or tail_key == "":
		printerr("[MiraiLinkVFX] ⚠️ Could not build head/tail keys; not writing link row.")
		return

	var head_time := _get_note_time(first_src)
	var tail_time := _get_note_time(last_src)

	var link_id := Time.get_unix_time_from_system()	 # simple id

	var row := {
		"layer": "$MIRAI_LINK",
		"time": head_time,
		"link_id": link_id,
		"head_key": head_key,
		"tail_key": tail_key,
		"head_time": head_time,
		"tail_time": tail_time
	}

	preserved.append(row)

	var lines := PackedStringArray()
	for e2 in preserved:
		lines.append(JSON.stringify(e2))
	var content := "[\n	 " + "\n,  ".join(lines) + "\n]\n"

	var fout := FileAccess.open(path, FileAccess.WRITE)
	if not fout:
		printerr("[MiraiLinkVFX] ❌ Failed to open VFX JSON for write: ", path)
		return
	fout.store_string(content)
	fout.close()
	print("[MiraiLinkVFX] 💾 Wrote Mirai link row → ", path)


# ─────────────────────────────────────────────
# Helpers: resolve note core info
# ─────────────────────────────────────────────

# Returns [data_obj, note_type, time_ms]
func _resolve_note_core(src: Object) -> Array:
	var data_obj := _safe_get(src, "data", null)
	if data_obj == null:
		data_obj = src

	var note_type := 0
	var note_time := 0

	if data_obj != null and (data_obj as Object).has_method("get"):
		var props := _get_property_names(data_obj)
		if "note_type" in props:
			note_type = int((data_obj as Object).get("note_type"))
		if "time" in props:
			note_time = int((data_obj as Object).get("time"))

	return [data_obj, note_type, note_time]

# ─────────────────────────────────────────────
# Timeout parity (same style as your VFX tools)
# ─────────────────────────────────────────────

func _get_rg() -> Object:
	if _editor == null:
		return null

	var rg = _editor.get("rhythm_game")
	if rg is Object:
		return rg

	var pv = _editor.get("rhythm_game_playtest_popup")
	if pv is Node:
		var r2 = (pv as Node).get("rhythm_game")
		if r2 is Object:
			return r2

	var gp = _editor.find_child("GamePreview", true, false)
	if gp != null and gp.has_method("get"):
		var r3 = gp.get("rhythm_game")
		if r3 is Object:
			return r3

	return null

const DEBUG_TIMEOUT := false  # flip to true if you want logs

func _compute_timeout_ms(note_type: int, note_obj: Object, t_ms: int) -> int:
	var rg := _get_rg()
	if rg != null:
		# 1) Best: type+time-specific
		if (rg as Object).has_method("get_time_out_for"):
			var ms := int(round(float((rg as Object).call("get_time_out_for", note_type, t_ms))))
			if DEBUG_TIMEOUT:
				print("[MiraiLinkVFX][timeout] rg.get_time_out_for t=", t_ms, " => ", ms, "ms")
			if ms > 0:
				return ms

		# 2) Note instance + speed
		var speed := 1.0
		if (rg as Object).has_method("get_note_speed_at_time"):
			speed = float((rg as Object).call("get_note_speed_at_time", t_ms))

		if note_obj != null and (note_obj as Object).has_method("get_time_out"):
			var ms2 := int(round(float((note_obj as Object).call("get_time_out", speed))))
			if DEBUG_TIMEOUT:
				print("[MiraiLinkVFX][timeout] note.get_time_out(speed) t=", t_ms, " speed=", speed, " => ", ms2, "ms")
			if ms2 > 0:
				return ms2

		# 3) Fallbacks: rg.get_time_out(...)
		if (rg as Object).has_method("get_time_out"):
			var try_ms := float((rg as Object).call("get_time_out", speed, t_ms))
			if try_ms <= 0.0:
				try_ms = float((rg as Object).call("get_time_out", speed))
			var ms3 := int(round(try_ms))
			if DEBUG_TIMEOUT:
				print("[MiraiLinkVFX][timeout] rg.get_time_out(...) => ", ms3, "ms")
			if ms3 > 0:
				return ms3

	# 4) Tempo-aware fallback (~8 beats)
	var map = _editor.get_timing_map() if _editor != null else []
	if map and map.size() >= 2:
		var idx := HBUtils.bsearch_upper(map, t_ms)
		var i0 := clamp(idx - 1, 0, map.size() - 1)
		var i1 := clamp(idx, 0, map.size() - 1)
		var beat_ms := max(1, int(map[i1] - map[i0]))
		if DEBUG_TIMEOUT:
			print("[MiraiLinkVFX][timeout] 8*beat_fallback beat_ms=", beat_ms, " => ", 8 * beat_ms, "ms")
		return 8 * beat_ms

	if DEBUG_TIMEOUT:
		print("[MiraiLinkVFX][timeout] hard_fallback 2000ms")
	return 2000

# ─────────────────────────────────────────────
# Helpers for note keys / path
# ─────────────────────────────────────────────

func _make_note_key(src: Object) -> String:
	if src == null:
		return ""

	var data_obj := _safe_get(src, "data", null)
	if data_obj == null:
		data_obj = src
	if data_obj == null or not data_obj is Object or not (data_obj as Object).has_method("get"):
		return ""

	var props := _get_property_names(data_obj)
	if not ("note_type" in props and "time" in props):
		printerr("[MiraiLinkVFX] ⚠️ Object has no note_type/time: ", data_obj)
		return ""

	var sel_type: int = int((data_obj as Object).get("note_type"))
	var time_val: int = int((data_obj as Object).get("time"))

	var layer2: bool = _is_layer2_from_obj(data_obj) or _is_layer2_from_obj(src)

	var lname: String = NOTE_TYPE_NAMES.get(sel_type, "UNKNOWN")
	if lname == "SLIDE_CHAIN_PIECE_LEFT":
		lname = "SLIDE_LEFT"
	if lname == "SLIDE_CHAIN_PIECE_RIGHT":
		lname = "SLIDE_RIGHT"

	var layer_tag: String = "layer_" + lname + ( "2" if layer2 else "" )
	return "%s@%d@%d" % [layer_tag, sel_type, time_val]

func _get_note_time(src: Object) -> int:
	if src == null:
		return 0
	var data_obj := _safe_get(src, "data", null)
	if data_obj == null:
		data_obj = src
	if data_obj != null and (data_obj as Object).has_method("get"):
		var props := _get_property_names(data_obj)
		if "time" in props:
			return int((data_obj as Object).get("time"))
	return 0

func _get_vfx_path() -> String:
	if _editor and _editor.current_song and _editor.current_difficulty:
		var sid := str(_editor.current_song.id)
		var diff := str(_editor.current_difficulty).replace(" ", "_")
		var dir_rel := "editor_songs/" + sid
		var d := DirAccess.open("user://")
		if d:
			d.make_dir_recursive(dir_rel)
		return "user://%s/%s_vfx.json" % [dir_rel, diff]
	return "user://note_vfx.json"

func _is_layer2_from_obj(obj: Object) -> bool:
	if obj == null:
		return false
	var lidx := _safe_get(obj, "layer_index", null)
	if lidx != null and int(lidx) == 1:
		return true
	var has_flag := _safe_get(obj, "second_layer", null)
	if has_flag != null and bool(has_flag):
		return true
	var layer_meta := _safe_get(obj, "layer", null)
	if layer_meta != null and String(layer_meta).ends_with("2"):
		return true
	return false

func _get_property_names(obj: Object) -> Array[String]:
	var out: Array[String] = []
	if obj:
		for p in obj.get_property_list():
			out.append(str(p.name))
	return out

func _safe_get(obj: Object, prop: String, fallback: Variant = null) -> Variant:
	if obj == null:
		return fallback

	if obj.has_method("get_property_list"):
		for p in obj.get_property_list():
			if str(p.name) == prop:
				return obj.get(prop)

	if obj.has_method("has_meta") and obj.has_meta(prop):
		return obj.get_meta(prop)

	if obj.has_method("get"):
		var v = obj.get(prop)
		if v != null:
			return v

	return fallback
