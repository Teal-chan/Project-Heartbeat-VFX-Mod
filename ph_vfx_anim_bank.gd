extends RefCounted

# Same tags as before
const SCALE_TAG  := "ScaleAbsAnim/v1"
const COLOR_TAG  := "ColorAnim/v1"
const ROTATE_TAG := "RotateAnim/v1"
const OFFSET_TAG := "PosOffsetAnim/v1"
const SPOT_TAG   := "SpotlightAnim/v1"
const GLOW_TAG   := "GlowAnim/v1"   # <── NEW

# Per-note buckets by TAG: key = "layer@note_type@anim_note_time"
var buckets_scale: Dictionary = {}
var times_scale: Dictionary = {}

var buckets_color: Dictionary = {}
var times_color: Dictionary = {}

var buckets_rot: Dictionary = {}
var times_rot: Dictionary = {}

var buckets_offset: Dictionary = {}
var times_offset: Dictionary = {}

var buckets_spot: Dictionary = {}
var times_spot: Dictionary = {}

# NEW: Glow buckets
var buckets_glow: Dictionary = {}
var times_glow: Dictionary = {}

# Merged event index (union of all row times across all tags)
var _events_times: PackedInt32Array = PackedInt32Array()
var _events_keys: Array = [] # Array[Array[String]]; keys that have a row at that time (any tag)

func clear() -> void:
	buckets_scale.clear();  times_scale.clear()
	buckets_color.clear();  times_color.clear()
	buckets_rot.clear();    times_rot.clear()
	buckets_offset.clear(); times_offset.clear()
	buckets_spot.clear();   times_spot.clear()
	buckets_glow.clear();   times_glow.clear()   # <── NEW

	_events_times = PackedInt32Array()
	_events_keys.clear()


func load_from_json(json_path: String) -> void:
	clear()
	if json_path.is_empty():
		return
	if not FileAccess.file_exists(json_path):
		return

	var f := FileAccess.open(json_path, FileAccess.READ)
	if f == null:
		return
	var parsed := JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_ARRAY:
		return

	# Bucket by tag → key → rows
	for v in (parsed as Array):
		if typeof(v) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = v
		var tag := String(e.get("anim", ""))
		if not (e.has("layer") and e.has("time") and e.has("note_type") and e.has("anim_note_time")):
			continue
		var layer := String(e["layer"])
		var nt := int(e["note_type"])
		var head_t := int(e["anim_note_time"])
		var key := "%s@%d@%d" % [layer, nt, head_t]

		match tag:
			SCALE_TAG:
				if not buckets_scale.has(key): buckets_scale[key] = []
				(buckets_scale[key] as Array).append(e)
			COLOR_TAG:
				if not buckets_color.has(key): buckets_color[key] = []
				(buckets_color[key] as Array).append(e)
			ROTATE_TAG:
				if not buckets_rot.has(key): buckets_rot[key] = []
				(buckets_rot[key] as Array).append(e)
			OFFSET_TAG:
				if not buckets_offset.has(key): buckets_offset[key] = []
				(buckets_offset[key] as Array).append(e)
			SPOT_TAG:
				if not buckets_spot.has(key): buckets_spot[key] = []
				(buckets_spot[key] as Array).append(e)
			GLOW_TAG:                                   # <── NEW
				if not buckets_glow.has(key): buckets_glow[key] = []
				(buckets_glow[key] as Array).append(e)
			_:
				pass

	# Sort & time indexes
	_func_sort_and_index(buckets_scale,  times_scale)
	_func_sort_and_index(buckets_color,  times_color)
	_func_sort_and_index(buckets_rot,    times_rot)
	_func_sort_and_index(buckets_offset, times_offset)
	_func_sort_and_index(buckets_spot,   times_spot)
	_func_sort_and_index(buckets_glow,   times_glow)   # <── NEW

	# Build merged event times (union of all times across all tags)
	var time_to_keys: Dictionary = {}
	_merge_times_into(time_to_keys, buckets_scale,  times_scale)
	_merge_times_into(time_to_keys, buckets_color,  times_color)
	_merge_times_into(time_to_keys, buckets_rot,    times_rot)
	_merge_times_into(time_to_keys, buckets_offset, times_offset)
	_merge_times_into(time_to_keys, buckets_spot,   times_spot)
	_merge_times_into(time_to_keys, buckets_glow,   times_glow)  # <── NEW

	var times: Array = time_to_keys.keys()
	times.sort()
	_events_times = PackedInt32Array(times)
	_events_keys.resize(_events_times.size())
	for i in _events_times.size():
		_events_keys[i] = time_to_keys[_events_times[i]]


func _func_sort_and_index(buckets: Dictionary, times_map: Dictionary) -> void:
	for k in buckets.keys():
		var arr: Array = buckets[k]
		arr.sort_custom(func(a, b):
			return int(a.get("time", 0)) < int(b.get("time", 0))
		)
		buckets[k] = arr
		var t := PackedInt32Array()
		t.resize(arr.size())
		for i in range(arr.size()):
			t[i] = int(arr[i].get("time", 0))
		times_map[k] = t


func _merge_times_into(acc: Dictionary, buckets: Dictionary, times_map: Dictionary) -> void:
	for k in buckets.keys():
		var ts: PackedInt32Array = times_map[k]
		for i in ts.size():
			var tval := ts[i]
			if not acc.has(tval):
				acc[tval] = []
			(acc[tval] as Array).append(k)


# ------ sampling helpers shared by tags ------

func _pair_around_time(times_idx: Dictionary, buckets: Dictionary, key: String, t_ms: int) -> Array:
	var arr: Array = buckets.get(key, [])
	if arr.is_empty():
		return [{}, {}]
	var times: PackedInt32Array = times_idx.get(key, PackedInt32Array())
	var lo := 0
	var hi := times.size() - 1
	var best := -1
	while lo <= hi:
		var mid := (lo + hi) / 2
		var tm := times[mid]
		if tm <= t_ms:
			best = mid
			lo = mid + 1
		else:
			hi = mid - 1
	var prev := {}
	var next := {}
	if best >= 0:
		prev = arr[best]
	if best + 1 < arr.size():
		next = arr[best + 1]
	return [prev, next]


func _segment_end_time_for_key_at_time(key: String, row_time: int) -> int:
	var nexts: Array[int] = []

	var idx := times_scale.get(key, null)
	if idx != null:
		var ts := idx as PackedInt32Array
		var i := ts.bsearch(row_time)
		if i < ts.size():
			var t := ts[i]
			if t != row_time or (i + 1) < ts.size():
				var j := i if ts[i] > row_time else (i + 1)
				if j < ts.size():
					nexts.append(ts[j])

	idx = times_color.get(key, null)
	if idx != null:
		var tc_arr := idx as PackedInt32Array
		var ic := tc_arr.bsearch(row_time)
		if ic < tc_arr.size():
			var tc := tc_arr[ic]
			if tc != row_time or (ic + 1) < tc_arr.size():
				var jc := ic if tc_arr[ic] > row_time else (ic + 1)
				if jc < tc_arr.size():
					nexts.append(tc_arr[jc])

	idx = times_rot.get(key, null)
	if idx != null:
		var tr_arr := idx as PackedInt32Array
		var ir := tr_arr.bsearch(row_time)
		if ir < tr_arr.size():
			var tr := tr_arr[ir]
			if tr != row_time or (ir + 1) < tr_arr.size():
				var jr := ir if tr_arr[ir] > row_time else (ir + 1)
				if jr < tr_arr.size():
					nexts.append(tr_arr[jr])

	idx = times_offset.get(key, null)
	if idx != null:
		var to_arr := idx as PackedInt32Array
		var io := to_arr.bsearch(row_time)
		if io < to_arr.size():
			var to := to_arr[io]
			if to != row_time or (io + 1) < to_arr.size():
				var jo := io if to_arr[io] > row_time else (io + 1)
				if jo < to_arr.size():
					nexts.append(to_arr[jo])

	idx = times_spot.get(key, null)
	if idx != null:
		var tsp_arr := idx as PackedInt32Array
		var isp := tsp_arr.bsearch(row_time)
		if isp < tsp_arr.size():
			var tsp := tsp_arr[isp]
			if tsp != row_time or (isp + 1) < tsp_arr.size():
				var jsp := isp if tsp_arr[isp] > row_time else (isp + 1)
				if jsp < tsp_arr.size():
					nexts.append(tsp_arr[jsp])

	# NEW: glow segments can also keep a key “live”
	idx = times_glow.get(key, null)
	if idx != null:
		var tg_arr := idx as PackedInt32Array
		var ig := tg_arr.bsearch(row_time)
		if ig < tg_arr.size():
			var tg := tg_arr[ig]
			if tg != row_time or (ig + 1) < tg_arr.size():
				var jg := ig if tg_arr[ig] > row_time else (ig + 1)
				if jg < tg_arr.size():
					nexts.append(tg_arr[jg])

	if nexts.is_empty():
		return row_time
	nexts.sort()
	return nexts[0]


func _lerp(a: float, b: float, t: float) -> float:
	return a + (b - a) * t


func _arr_to_color(a: Variant, fallback: Color) -> Color:
	if typeof(a) != TYPE_ARRAY:
		return fallback
	var aa := a as Array
	if aa.size() < 3:
		return fallback
	var r := float(aa[0])
	var g := float(aa[1])
	var b := float(aa[2])
	var al := float(aa[3]) if aa.size() >= 4 else 1.0
	return Color(r, g, b, al)


func _lerp_color(a: Color, b: Color, t: float) -> Color:
	return Color(
		a.r + (b.r - a.r) * t,
		a.g + (b.g - a.g) * t,
		a.b + (b.b - a.b) * t,
		a.a + (b.a - a.a) * t
	)


func _arr_to_vec2(v: Variant, fallback: Vector2) -> Vector2:
	if typeof(v) != TYPE_ARRAY:
		return fallback
	var a := v as Array
	if a.size() < 2:
		return fallback
	return Vector2(float(a[0]), float(a[1]))


func _shortest_arc_lerp(a0: float, a1: float, t: float) -> float:
	var delta := fposmod(a1 - a0 + 540.0, 360.0) - 180.0
	return fposmod(a0 + delta * t, 360.0)


func _ease_t(name: String, x: float) -> float:
	var tt := clampf(x, 0.0, 1.0)
	var nm := name.to_lower()

	if nm == "hold":
		return 0.0 if tt < 1.0 else 1.0
	if nm == "step":
		return 0.0 if tt <= 0.0 else 1.0

	match nm:
		"in_out_quad":
			if tt < 0.5: return 2.0 * tt * tt
			return 1.0 - pow(-2.0 * tt + 2.0, 2.0) / 2.0
		"in_out_cubic":
			if tt < 0.5: return 4.0 * tt * tt * tt
			return 1.0 - pow(-2.0 * tt + 2.0, 3.0) / 2.0
		"out_elastic":
			if tt == 0.0 or tt == 1.0: return tt
			var c := (2.0 * PI) / 3.0
			return pow(2.0, -10.0 * tt) * sin((tt * 10.0 - 0.75) * c) + 1.0
		_:
			return tt


# ------ per-tag sampling APIs used by the injector ------

func _sample_scales_for_key(key: String, t_ms: int) -> Dictionary:
	var out := {"head":1.0,"target":1.0,"bar1":1.0,"bar2":1.0,"tail":1.0,"hold":1.0}
	var bucket: Array = buckets_scale.get(key, [])
	if bucket.is_empty():
		return out

	var pair := _pair_around_time(times_scale, buckets_scale, key, t_ms)
	var prev_r: Dictionary = pair[0]
	var next_r: Dictionary = pair[1]

	if not prev_r.is_empty() and not next_r.is_empty():
		var t0 := float(prev_r.get("time", t_ms))
		var t1 := float(next_r.get("time", t_ms))
		var raw_t := 0.0
		if t1 > t0:
			raw_t = clamp((float(t_ms) - t0) / (t1 - t0), 0.0, 1.0)

		var ease_name := String(next_r.get("ease", prev_r.get("ease", "linear")))
		var tt := _ease_t(ease_name, raw_t)

		out.head   = _lerp(float(prev_r.get("scale_head",1.0)),   float(next_r.get("scale_head",1.0)), tt)
		out.target = _lerp(float(prev_r.get("scale_target",1.0)), float(next_r.get("scale_target",1.0)), tt)
		out.bar1   = _lerp(float(prev_r.get("scale_bar1",1.0)),   float(next_r.get("scale_bar1",1.0)), tt)

		var pb2 := float(prev_r.get("scale_bar2", float(prev_r.get("scale_bar1",1.0))))
		var nb2 := float(next_r.get("scale_bar2", float(next_r.get("scale_bar1",1.0))))
		out.bar2   = _lerp(pb2, nb2, tt)

		out.tail   = _lerp(float(prev_r.get("scale_tail",1.0)),   float(next_r.get("scale_tail",1.0)), tt)
		out.hold   = _lerp(float(prev_r.get("scale_hold",1.0)),   float(next_r.get("scale_hold",1.0)), tt)
	elif not prev_r.is_empty():
		out.head   = float(prev_r.get("scale_head",1.0))
		out.target = float(prev_r.get("scale_target",1.0))
		out.bar1   = float(prev_r.get("scale_bar1",1.0))
		out.bar2   = float(prev_r.get("scale_bar2", out.bar1))
		out.tail   = float(prev_r.get("scale_tail",1.0))
		out.hold   = float(prev_r.get("scale_hold",1.0))
	return out


func _sample_colors_for_key(key: String, t_ms: int) -> Dictionary:
	var out := {
		"icon": Color(1,1,1,1),
		"target": Color(1,1,1,1),
		"bar1": Color(1,1,1,1),
		"bar2": Color(1,1,1,1),
		"head": Color(1,1,1,1),
		"tail": Color(1,1,1,1),
		"hold": Color(1,1,1,1)
	}
	var bucket: Array = buckets_color.get(key, [])
	if bucket.is_empty():
		return out

	var pair := _pair_around_time(times_color, buckets_color, key, t_ms)
	var prev_r: Dictionary = pair[0]
	var next_r: Dictionary = pair[1]

	if not prev_r.is_empty() and not next_r.is_empty():
		var t0 := float(prev_r.get("time", t_ms))
		var t1 := float(next_r.get("time", t_ms))
		var raw_t := 0.0
		if t1 > t0:
			raw_t = clamp((float(t_ms) - t0) / (t1 - t0), 0.0, 1.0)

		var ease_name := String(next_r.get("ease", prev_r.get("ease", "linear")))
		var tt := _ease_t(ease_name, raw_t)

		var p_icon := _arr_to_color(prev_r.get("color_icon", [1,1,1,1]), Color(1,1,1,1))
		var n_icon := _arr_to_color(next_r.get("color_icon", [1,1,1,1]), Color(1,1,1,1))
		var p_tgt  := _arr_to_color(prev_r.get("color_target", [1,1,1,1]), Color(1,1,1,1))
		var n_tgt  := _arr_to_color(next_r.get("color_target", [1,1,1,1]), Color(1,1,1,1))
		var p_b1   := _arr_to_color(prev_r.get("color_bar1", [1,1,1,1]), Color(1,1,1,1))
		var n_b1   := _arr_to_color(next_r.get("color_bar1", [1,1,1,1]), Color(1,1,1,1))
		var p_b2   := _arr_to_color(prev_r.get("color_bar2", prev_r.get("color_bar1", [1,1,1,1])), Color(1,1,1,1))
		var n_b2   := _arr_to_color(next_r.get("color_bar2", next_r.get("color_bar1", [1,1,1,1])), Color(1,1,1,1))
		var p_head := _arr_to_color(prev_r.get("color_icon_head", prev_r.get("color_icon", [1,1,1,1])), Color(1,1,1,1))
		var n_head := _arr_to_color(next_r.get("color_icon_head", next_r.get("color_icon", [1,1,1,1])), Color(1,1,1,1))
		var p_tail := _arr_to_color(prev_r.get("color_icon_tail", prev_r.get("color_icon", [1,1,1,1])), Color(1,1,1,1))
		var n_tail := _arr_to_color(next_r.get("color_icon_tail", next_r.get("color_icon", [1,1,1,1])), Color(1,1,1,1))
		var p_hold := _arr_to_color(prev_r.get("color_hold_text", [1,1,1,1]), Color(1,1,1,1))
		var n_hold := _arr_to_color(next_r.get("color_hold_text", [1,1,1,1]), Color(1,1,1,1))

		out.icon   = _lerp_color(p_icon, n_icon, tt)
		out.target = _lerp_color(p_tgt,  n_tgt,  tt)
		out.bar1   = _lerp_color(p_b1,   n_b1,   tt)
		out.bar2   = _lerp_color(p_b2,   n_b2,   tt)
		out.head   = _lerp_color(p_head, n_head, tt)
		out.tail   = _lerp_color(p_tail, n_tail, tt)
		out.hold   = _lerp_color(p_hold, n_hold, tt)
	elif not prev_r.is_empty():
		out.icon   = _arr_to_color(prev_r.get("color_icon", [1,1,1,1]), Color(1,1,1,1))
		out.target = _arr_to_color(prev_r.get("color_target", [1,1,1,1]), Color(1,1,1,1))
		out.bar1   = _arr_to_color(prev_r.get("color_bar1", [1,1,1,1]), Color(1,1,1,1))
		out.bar2   = _arr_to_color(prev_r.get("color_bar2", prev_r.get("color_bar1", [1,1,1,1])), Color(1,1,1,1))
		out.head   = _arr_to_color(prev_r.get("color_icon_head", prev_r.get("color_icon", [1,1,1,1])), Color(1,1,1,1))
		out.tail   = _arr_to_color(prev_r.get("color_icon_tail", prev_r.get("color_icon", [1,1,1,1])), Color(1,1,1,1))
		out.hold   = _arr_to_color(prev_r.get("color_hold_text", [1,1,1,1]), Color(1,1,1,1))
	return out


func _sample_offset_for_key(key: String, t_ms: int) -> Dictionary:
	var out := {
		"head":   Vector2.ZERO,
		"tail":   Vector2.ZERO,
		"target": Vector2.ZERO,
		"hold":   Vector2.ZERO,
		"bar1":   Vector2.ZERO,
		"bar2":   Vector2.ZERO,
	}

	var bucket: Array = buckets_offset.get(key, [])
	if bucket.is_empty():
		return out

	var pair := _pair_around_time(times_offset, buckets_offset, key, t_ms)
	var prev_r: Dictionary = pair[0]
	var next_r: Dictionary = pair[1]

	if not prev_r.is_empty() and not next_r.is_empty():
		var t0 := float(prev_r.get("time", t_ms))
		var t1 := float(next_r.get("time", t_ms))
		var raw_t := 0.0
		if t1 > t0:
			raw_t = clamp((float(t_ms) - t0) / (t1 - t0), 0.0, 1.0)

		var ease_name: String = String(next_r.get("ease", prev_r.get("ease", "linear")))
		var tt := _ease_t(ease_name, raw_t)

		var ph := _arr_to_vec2(prev_r.get("offset_head", [0, 0]), Vector2.ZERO)
		var nh := _arr_to_vec2(next_r.get("offset_head", [0, 0]), Vector2.ZERO)

		var pt := _arr_to_vec2(prev_r.get("offset_tail", prev_r.get("offset_head", [0, 0])), ph)
		var nt := _arr_to_vec2(next_r.get("offset_tail", next_r.get("offset_head", [0, 0])), nh)

		var ptg := _arr_to_vec2(prev_r.get("offset_target", [0, 0]), Vector2.ZERO)
		var ntg := _arr_to_vec2(next_r.get("offset_target", [0, 0]), Vector2.ZERO)

		var pho := _arr_to_vec2(prev_r.get("offset_hold", [0, 0]), Vector2.ZERO)
		var nho := _arr_to_vec2(next_r.get("offset_hold", [0, 0]), Vector2.ZERO)

		var pb1 := _arr_to_vec2(prev_r.get("offset_bar1", prev_r.get("offset_target", [0, 0])), ptg)
		var nb1 := _arr_to_vec2(next_r.get("offset_bar1", next_r.get("offset_target", [0, 0])), ntg)
		var pb2 := _arr_to_vec2(
			prev_r.get("offset_bar2", prev_r.get("offset_bar1", prev_r.get("offset_target", [0, 0]))),
			pb1
		)
		var nb2 := _arr_to_vec2(
			next_r.get("offset_bar2", next_r.get("offset_bar1", next_r.get("offset_target", [0, 0]))),
			nb1
		)

		out.head   = ph.lerp(nh, tt)
		out.tail   = pt.lerp(nt, tt)
		out.target = ptg.lerp(ntg, tt)
		out.hold   = pho.lerp(nho, tt)
		out.bar1   = pb1.lerp(nb1, tt)
		out.bar2   = pb2.lerp(nb2, tt)

	elif not prev_r.is_empty():
		out.head   = _arr_to_vec2(prev_r.get("offset_head", [0, 0]), Vector2.ZERO)
		out.tail   = _arr_to_vec2(prev_r.get("offset_tail", prev_r.get("offset_head", [0, 0])), out.head)
		out.target = _arr_to_vec2(prev_r.get("offset_target", [0, 0]), Vector2.ZERO)
		out.hold   = _arr_to_vec2(prev_r.get("offset_hold", [0, 0]), Vector2.ZERO)
		out.bar1   = _arr_to_vec2(prev_r.get("offset_bar1", prev_r.get("offset_target", [0, 0])), out.target)
		out.bar2   = _arr_to_vec2(
			prev_r.get("offset_bar2", prev_r.get("offset_bar1", prev_r.get("offset_target", [0, 0]))),
			out.bar1
		)

	return out


func _deg_from_row(e: Dictionary, field: String, fallback: float) -> float:
	if e.has(field):
		return float(e[field])
	return fallback


func _sample_rot_for_key(key: String, t_ms: int) -> Dictionary:
	var out := {"head": 0.0, "tail": 0.0, "target": 0.0, "hold": 0.0}
	var bucket: Array = buckets_rot.get(key, [])
	if bucket.is_empty():
		return out

	var pair := _pair_around_time(times_rot, buckets_rot, key, t_ms)
	var prev_r: Dictionary = pair[0]
	var next_r: Dictionary = pair[1]

	if not prev_r.is_empty() and not next_r.is_empty():
		var t0 := float(prev_r.get("time", t_ms))
		var t1 := float(next_r.get("time", t_ms))
		var raw_t := 0.0
		if t1 > t0:
			raw_t = clamp((float(t_ms) - t0) / (t1 - t0), 0.0, 1.0)

		var ease_name := String(next_r.get("ease", prev_r.get("ease", "linear")))
		var tt := _ease_t(ease_name, raw_t)

		# IMPORTANT: treat degrees as literal, unbounded values.
		var hp := _deg_from_row(prev_r, "rotation_deg_head",    out.head)
		var hn := _deg_from_row(next_r, "rotation_deg_head",    hp)
		var tp := _deg_from_row(prev_r, "rotation_deg_tail",    out.tail)
		var tn := _deg_from_row(next_r, "rotation_deg_tail",    tp)
		var gp := _deg_from_row(prev_r, "rotation_deg_target",  out.target)
		var gn := _deg_from_row(next_r, "rotation_deg_target",  gp)
		var op := _deg_from_row(prev_r, "rotation_deg_holdtext", out.hold)
		var on := _deg_from_row(next_r, "rotation_deg_holdtext", op)

		out.head   = _lerp(hp, hn, tt)
		out.tail   = _lerp(tp, tn, tt)
		out.target = _lerp(gp, gn, tt)
		out.hold   = _lerp(op, on, tt)

	elif not prev_r.is_empty():
		out.head   = _deg_from_row(prev_r, "rotation_deg_head",    out.head)
		out.tail   = _deg_from_row(prev_r, "rotation_deg_tail",    out.tail)
		out.target = _deg_from_row(prev_r, "rotation_deg_target",  out.target)
		out.hold   = _deg_from_row(prev_r, "rotation_deg_holdtext", out.hold)

	return out


func _sample_spot_for_key(key: String, t_ms: int) -> Dictionary:
	var out := {
		"enable": false,
		"center": Vector2(0.5, 0.5),
		"radius": 0.30,
		"soft":   0.20,
		"dim":    0.15
	}

	var bucket: Array = buckets_spot.get(key, [])
	if bucket.is_empty():
		return out

	var pair := _pair_around_time(times_spot, buckets_spot, key, t_ms)
	var prev_r: Dictionary = pair[0]
	var next_r: Dictionary = pair[1]

	if not prev_r.is_empty() and not next_r.is_empty():
		var t0 := float(prev_r.get("time", t_ms))
		var t1 := float(next_r.get("time", t_ms))
		var raw_t := 0.0
		if t1 > t0:
			raw_t = clamp((float(t_ms) - t0) / (t1 - t0), 0.0, 1.0)

		var ease_name := String(next_r.get("ease", prev_r.get("ease", "linear")))
		var tt := _ease_t(ease_name, raw_t)

		var r0 := float(prev_r.get("spot_radius", out["radius"]))
		var r1 := float(next_r.get("spot_radius", r0))
		var s0 := float(prev_r.get("spot_soft", out["soft"]))
		var s1 := float(next_r.get("spot_soft", s0))
		var d0 := float(prev_r.get("spot_dim", out["dim"]))
		var d1 := float(next_r.get("spot_dim", d0))

		out["radius"] = _lerp(r0, r1, tt)
		out["soft"]   = _lerp(s0, s1, tt)
		out["dim"]    = _lerp(d0, d1, tt)

		var c0 := _arr_to_vec2(prev_r.get("spot_center", [0.5, 0.5]), out["center"])
		var c1 := _arr_to_vec2(next_r.get("spot_center", [0.5, 0.5]), c0)
		out["center"] = c0.lerp(c1, tt)

		var e0 := bool(prev_r.get("spot_enable", false))
		var e1 := bool(next_r.get("spot_enable", e0))
		out["enable"] = e0 or e1
	elif not prev_r.is_empty():
		out["radius"] = float(prev_r.get("spot_radius", out["radius"]))
		out["soft"]   = float(prev_r.get("spot_soft", out["soft"]))
		out["dim"]    = float(prev_r.get("spot_dim", out["dim"]))
		out["center"] = _arr_to_vec2(prev_r.get("spot_center", [0.5, 0.5]), out["center"])
		out["enable"] = bool(prev_r.get("spot_enable", out["enable"]))

	return out


# NEW: Glow sampling – mirrors _sample_scales_for_key
func _sample_glow_for_key(key: String, t_ms: int) -> Dictionary:
	var out := {"head":0.0,"target":0.0,"bar1":0.0,"bar2":0.0,"tail":0.0,"hold":0.0}
	var bucket: Array = buckets_glow.get(key, [])
	if bucket.is_empty():
		return out

	var pair := _pair_around_time(times_glow, buckets_glow, key, t_ms)
	var prev_r: Dictionary = pair[0]
	var next_r: Dictionary = pair[1]

	if not prev_r.is_empty() and not next_r.is_empty():
		var t0 := float(prev_r.get("time", t_ms))
		var t1 := float(next_r.get("time", t_ms))
		var raw_t := 0.0
		if t1 > t0:
			raw_t = clamp((float(t_ms) - t0) / (t1 - t0), 0.0, 1.0)

		var ease_name := String(next_r.get("ease", prev_r.get("ease", "linear")))
		var tt := _ease_t(ease_name, raw_t)

		out.head   = _lerp(float(prev_r.get("glow_head",0.0)),   float(next_r.get("glow_head",0.0)), tt)
		out.target = _lerp(float(prev_r.get("glow_target",0.0)), float(next_r.get("glow_target",0.0)), tt)
		out.bar1   = _lerp(float(prev_r.get("glow_bar1",0.0)),   float(next_r.get("glow_bar1",0.0)), tt)

		var pb2 := float(prev_r.get("glow_bar2", float(prev_r.get("glow_bar1",0.0))))
		var nb2 := float(next_r.get("glow_bar2", float(next_r.get("glow_bar1",0.0))))
		out.bar2   = _lerp(pb2, nb2, tt)

		out.tail   = _lerp(float(prev_r.get("glow_tail",0.0)),   float(next_r.get("glow_tail",0.0)), tt)
		out.hold   = _lerp(float(prev_r.get("glow_hold",0.0)),   float(next_r.get("glow_hold",0.0)), tt)
	elif not prev_r.is_empty():
		out.head   = float(prev_r.get("glow_head",0.0))
		out.target = float(prev_r.get("glow_target",0.0))
		out.bar1   = float(prev_r.get("glow_bar1",0.0))
		out.bar2   = float(prev_r.get("glow_bar2", out.bar1))
		out.tail   = float(prev_r.get("glow_tail",0.0))
		out.hold   = float(prev_r.get("glow_hold",0.0))
	return out
