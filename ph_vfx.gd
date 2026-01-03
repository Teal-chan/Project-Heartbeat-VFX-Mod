# I did this, with ChatGPT's help. - Teal

extends HBModifier

const LOG_NAME := "MightyModifier"

# Last chart context, set from PreGameScreen
static var s_last_song_id: String = ""
static var s_last_difficulty: String = ""

const NOTE_VFX_SHADER_PATH := "user://editor_scripts/Shaders/note_vfx.gdshader"
const FULLSCREEN_SPOT_SHADER_PATH := "user://editor_scripts/Shaders/spot_overlay.gdshader"
const PHVFXAnimBank = preload("user://editor_scripts/Utilities/ph_vfx_anim_bank.gd")

const VFX_META_ORIG_MAT := "_vfx_orig_material"
const VFX_META_SM       := "_vfx_sm"
const SLIDE_CHAIN_MAX_HEAD_DT_MS := 400  # how far (in ms) a chain piece can look for its head

const PF_ENTRY_TAG := "$PLAYFIELD"
const PF_ROTATE_TAG := "$PF_ROTATE_SEL"
const PF_USE_ABSOLUTE_CHAIN := true
const PF_SCALE_TAG := "$PF_SCALE_SEL" # NEW

const FIELD_PIVOT_GL := Vector2(960.0, 540.0) # GameLayer-local pivot for zoom/rot


var anim_bank := PHVFXAnimBank.new()
var _bank_loaded := false
var _note_shader: Shader = null

var _current_vfx_path: String = ""

var _song_ctx = null            # HBSong, resolved from statics
var _difficulty_ctx: String = ""
var _ctx_checked := false       # only read statics once

# Per-drawer caches
var _drawer_parts: Dictionary = {}   # Node -> parts dict
var _drawer_key: Dictionary = {}     # Node -> key string
var _key_remap: Dictionary = {}      # raw_key -> effective key


# Extra: slide chain drawers under GameLayer/LAYER_SlideChainPieces
var _slide_chain_drawers: Array[Node] = []
var _extra_cached: bool = false

# Playfield slide (field animation) state
var _pf_rows_loaded := false
var _pf_rows: Array = []                # [{t0, t1, endpoint: Vector2, ease: String}]
var _pf_chain: Array = []               # [{t0, t1, base: Vector2, end: Vector2, ease}]
var _pf_wrapper: Node2D = null          # runtime wrapper around GameLayer
var _pf_baseline_pos: Vector2 = Vector2.ZERO
var _pf_last_gl_scale: float = 1.0  # last applied GameLayer scale


# NEW: rotation rows for playfield
var _pf_rot_rows: Array = []            # raw rotation rows
var _pf_rot_chain: Array = []           # [{t0,t1,a0,a1,ease,pivot_parent}]
var _pf_game_layer: Node2D = null       # GameLayer reference for pivot conversion

var _pf_scale_rows: Array = []          # [{t0,t1,s0,s1,ease}]
var _pf_baseline_scale: float = 1.0     # wrapper baseline (slides only / legacy)
var _pf_baseline_gl_scale: float = 1.0  # NEW: GameLayer baseline scale for zoom

# Extra: trail drawers under GameLayer/LAYER_Trails
var _trail_drawers: Array[Node] = []

# Runtime time tracking so we can tick even when there are no drawers
var _rt_last_chart_ms: float = -1.0
var _rt_last_wall_ms: int = -1

# Spotlight overlay (full-screen)
var _spot_overlay = null            # ColorRect
var _spot_shader: Shader = null
# Drawers that should have a spotlight following them
var _spot_drawers: Array = []

# Per-frame sampling cache (key -> {S,C,R,O,G} at a given time)
var _frame_sample_time_ms: int = -1
var _frame_sample_cache: Dictionary = {}  # key -> { "S":..., "C":..., "R":..., "O":..., "G":... }

# Mirai link lines (runtime)
const MIRAI_LINE_NODE_NAME := "PH_MiraiLinkLines_RUNTIME"

# each entry:
# {
#   head_key: String,
#   tail_key: String,
#   head_time: int,
#   tail_time: int,
#   head_drawer: Node,
#   tail_drawer: Node,
#   line: Line2D
# }
var _mirai_links: Array = []
var _mirai_line_root: Node2D = null
var _mirai_rows_loaded := false
var _mirai_last_t_ms: int = 0   # last known song time in ms (for Mirai lifetime)

func _init() -> void:
	processing_notes = true


# ─────────────────────────────────────────────
# Metadata
# ─────────────────────────────────────────────

static func get_modifier_name() -> String:
	return "VFX (PH Shader Pack)"

func get_modifier_list_name() -> String:
	return get_modifier_name()

static func get_modifier_description() -> String:
	return "Applies shader-based visual effects to supported charts."


# Same path helper as editor MegaInjector
static func get_vfx_path_for_song(song, difficulty: String) -> String:
	if song == null:
		return ""
	var sid := String(song.id)
	var diff := difficulty.replace(" ", "_")
	return "user://editor_songs/%s/%s_vfx.json" % [sid, diff]

# ─────────────────────────────────────────────
# Static helpers for menus / tools
# ─────────────────────────────────────────────

static var _song_vfx_cache: Dictionary = {}


static func has_any_vfx_for_song(song: HBSong) -> bool:
	if song == null:
		return false

	var sid := String(song.id)
	if _song_vfx_cache.has(sid):
		return bool(_song_vfx_cache[sid])

	var has := false

	# Primary: look next to the song file, no matter where it lives.
	# This mirrors the logic we used in WorkshopUploadForm.
	var song_fs_path := ProjectSettings.globalize_path(song.path)
	var dir_path := song_fs_path

	# If song.path points to a file, fall back to its folder
	if not DirAccess.dir_exists_absolute(dir_path):
		dir_path = song_fs_path.get_base_dir()

	if DirAccess.dir_exists_absolute(dir_path):
		var d := DirAccess.open(dir_path)
		if d != null:
			d.list_dir_begin()
			while true:
				var fname := d.get_next()
				if fname == "":
					break
				if d.current_is_dir():
					continue

				var lower := fname.to_lower()
				if not lower.ends_with(".json"):
					continue

				# Be slightly flexible: *_vfx.json or any JSON with "vfx" in the name
				if lower.ends_with("_vfx.json") or lower.find("vfx") != -1:
					has = true
					break
			d.list_dir_end()

	_song_vfx_cache[sid] = has
	return has


static func clear_vfx_cache() -> void:
	_song_vfx_cache.clear()


# ─────────────────────────────────────────────
# Context from statics (PreGameScreen sets these)
# ─────────────────────────────────────────────

func _ensure_context_from_statics() -> void:
	if _ctx_checked:
		return
	_ctx_checked = true

	if _song_ctx != null and _difficulty_ctx != "":
		return

	if s_last_song_id == "" or s_last_difficulty == "":
		print("%s: no static context set (s_last_song_id/s_last_difficulty empty)" % LOG_NAME)
		return

	if SongLoader.songs.has(s_last_song_id):
		_song_ctx = SongLoader.songs[s_last_song_id]
		_difficulty_ctx = s_last_difficulty
		print("%s: context from statics → song_id=%s, difficulty=%s" % [
			LOG_NAME, s_last_song_id, s_last_difficulty
		])
	else:
		print("%s: static song id %s not found in SongLoader.songs" % [LOG_NAME, s_last_song_id])


func _detect_vfx_path() -> String:
	_ensure_context_from_statics()

	# If we have song + difficulty context, first try to find a VFX JSON
	# *next to the chart file/folder* (works for workshop AND editor songs).
	if _song_ctx != null and _difficulty_ctx != "":
		var song_res_path: String = _song_ctx.path
		if song_res_path != "":
			# Convert to OS path so we can poke around with DirAccess
			var song_fs_path := ProjectSettings.globalize_path(song_res_path)
			var dir_path := song_fs_path

			# If song.path is a file, use its parent directory instead.
			if not DirAccess.dir_exists_absolute(dir_path):
				dir_path = song_fs_path.get_base_dir()

			if DirAccess.dir_exists_absolute(dir_path):
				var dir := DirAccess.open(dir_path)
				if dir != null:
					var diff_tag := _difficulty_ctx.replace(" ", "_").to_lower()

					var preferred_os_path := ""   # "<difficulty>_vfx.json"
					var fallback_os_path := ""    # any "*_vfx.json"
					var loose_os_path := ""       # any JSON with "vfx" in the name

					dir.list_dir_begin()
					while true:
						var fn := dir.get_next()
						if fn == "":
							break
						if dir.current_is_dir():
							continue

						var lower := String(fn).to_lower()
						if not lower.ends_with(".json"):
							continue

						# Strong preference: "<difficulty>_vfx.json" (e.g. "hard_vfx.json")
						if lower == "%s_vfx.json" % diff_tag:
							preferred_os_path = dir_path.path_join(fn)
							break

						# Next: any "*_vfx.json" in this folder.
						if fallback_os_path == "" and lower.ends_with("_vfx.json"):
							fallback_os_path = dir_path.path_join(fn)
							continue

						# Final song-local fallback: any JSON with "vfx" in the name.
						if loose_os_path == "" and lower.find("vfx") != -1:
							loose_os_path = dir_path.path_join(fn)
					dir.list_dir_end()

					var os_path := preferred_os_path
					if os_path == "" and fallback_os_path != "":
						os_path = fallback_os_path
					if os_path == "" and loose_os_path != "":
						os_path = loose_os_path

					if os_path != "":
						# Convert back to a project path ("user://...") for FileAccess.
						var vfs_path := ProjectSettings.localize_path(os_path)
						print("%s: using song-local VFX JSON at %s" % [LOG_NAME, vfs_path])
						return vfs_path

		# Legacy editor path (user://editor_songs/<id>/<diff>_vfx.json)
		var candidate := get_vfx_path_for_song(_song_ctx, _difficulty_ctx)
		print("%s: candidate VFX path from song/diff: %s" % [LOG_NAME, candidate])
		if FileAccess.file_exists(candidate):
			print("%s: using chart-specific VFX JSON at %s" % [LOG_NAME, candidate])
			return candidate
		else:
			print("%s: chart-specific JSON missing at %s" % [LOG_NAME, candidate])

	# Global fallback: old single-slot JSON, if someone still uses it.
	var fallback_path := "user://note_vfx.json"
	if FileAccess.file_exists(fallback_path):
		print("%s: falling back to global VFX JSON at %s" % [LOG_NAME, fallback_path])
		return fallback_path

	print("%s: no VFX JSON found (local, chart-specific, or fallback)." % LOG_NAME)
	return ""


# ─────────────────────────────────────────────
# Runtime: per-note hook (from LAYER_Notes)
# ─────────────────────────────────────────────

func _process_note(drawers: Array, time_sec: float, _note_speed: float) -> void:
	var t_ms: int = int(time_sec * 1000.0)
	_mirai_last_t_ms = t_ms  # cache current time for Mirai links
	_rt_last_chart_ms = float(t_ms)
	_rt_last_wall_ms = Time.get_ticks_msec()


	_ensure_bank_loaded()
	_ensure_note_shader()
	_ensure_playfield_rows_loaded()
	_ensure_mirai_rows_loaded()

	if anim_bank == null:
		return

	var first_drawer: Node = null
	if not drawers.is_empty():
		first_drawer = drawers[0] as Node

	_update_playfield_slides(t_ms, first_drawer)

	# Full-screen spotlight overlay (uses SPOT rows; must update even
	# on frames with no drawers so it can turn off at the right time).
	_update_spot_overlay(drawers, t_ms)

	# If there are no drawers this frame, we still want Mirai lines
	# to get a chance to despawn based on time / dead notes.
	if drawers.is_empty():
		_update_mirai_lines_runtime()
		return

	# Things that need a concrete drawer (GameLayer climb, spotlight, slide chains)
	if first_drawer != null:
		_ensure_extra_drawers_cached(first_drawer)
		_ensure_spot_overlay(first_drawer)
		_ensure_mirai_line_root(first_drawer)

	# Main note drawers (LAYER_Notes)
	for d in drawers:
		if d == null or not (d is Node):
			continue

		var nd = null
		if d.has_method("get"):
			nd = d.get("note_data")

		var adj_factor := _get_adj_factor(nd)

		var key: String = _get_effective_key_for_drawer(d)
		if key == "":
			continue

		# If this note has SPOT rows, remember its drawer so the overlay
		# can follow it even when it’s not in the current "drawers" batch.
		if anim_bank.buckets_spot.has(key) and not _spot_drawers.has(d):
			_spot_drawers.append(d)

		var parts: Dictionary = _drawer_parts.get(d, {})
		if parts.is_empty():
			parts = _parts_for_drawer(d)
			_init_part_state(parts)
			_drawer_parts[d] = parts

		var samples := _sample_all_for_key_cached(key, t_ms)
		if samples.is_empty():
			continue

		var S: Dictionary = samples["S"]
		var C: Dictionary = samples["C"]
		var R: Dictionary = samples["R"]
		var O: Dictionary = samples["O"]
		var G: Dictionary = samples["G"]


		_apply_drawer_field_transform(d, R, O, false)

		var O_rel := {
			"head":   O.head - O.target,
			"tail":   O.tail - O.target,
			"target": Vector2.ZERO,
			"hold":   O.hold - O.target,
			"bar1":   O.bar1 - O.target,
			"bar2":   O.bar2 - O.target,
		}

		_apply_parts_all(parts, S, C, R, O_rel, G, adj_factor)

	# Slide-chain pieces in LAYER_SlideChainPieces
	_update_slide_chain_drawers(t_ms)

	# Trails in LAYER_Trails
	_update_trail_drawers(t_ms)

	# Full-screen spotlight overlay (uses the same SPOT rows)
	_update_spot_overlay(drawers, t_ms)

	# Mirai link lines (runtime, JSON-driven)
	_update_mirai_link_drawer_refs(drawers)
	_update_mirai_lines_runtime()

func _process(delta: float) -> void:
	# If we’ve never seen chart time, nothing to do
	if _rt_last_chart_ms < 0.0 or _rt_last_wall_ms < 0:
		return
	if anim_bank == null:
		return
	if _spot_overlay == null or not _spot_overlay.is_inside_tree():
		return

	# Approximate current chart time from last known chart time + wall-clock delta
	var now_ms: int = Time.get_ticks_msec()
	var dt_ms: int = now_ms - _rt_last_wall_ms
	if dt_ms <= 0:
		return

	var chart_t_ms: int = int(_rt_last_chart_ms + dt_ms)

	# We don’t have any drawers on these frames, so pass an empty array.
	# _update_spot_overlay will sample SPOT rows at chart_t_ms and
	# turn itself off once there’s no active SPOT anymore.
	_update_spot_overlay([], chart_t_ms)

	# Optionally, keep playfield slides & Mirai lines moving too:
	_update_playfield_slides(chart_t_ms, null)
	_update_mirai_lines_runtime()


# ─────────────────────────────────────────────
# Bank + shader setup
# ─────────────────────────────────────────────

func _ensure_bank_loaded() -> void:
	if _bank_loaded:
		return
	_bank_loaded = true

	var path := _detect_vfx_path()
	_current_vfx_path = path

	if path == "":
		push_warning("%s: No VFX JSON found for current chart." % LOG_NAME)
		return

	if not FileAccess.file_exists(path):
		push_warning("%s: VFX JSON not found at %s" % [LOG_NAME, path])
		return

	anim_bank.clear()
	anim_bank.load_from_json(path)

	# Reset playfield slide data for this chart
	_pf_rows_loaded = false
	_pf_rows.clear()
	_pf_chain.clear()
	_pf_wrapper = null
	_pf_baseline_pos = Vector2.ZERO
	
	# NEW: reset playfield rotation for this chart
	_pf_rot_rows.clear()
	_pf_rot_chain.clear()
	_pf_game_layer = null

	# NEW: reset playfield scale for this chart
	_pf_scale_rows.clear()
	_pf_baseline_scale = 1.0
	_pf_baseline_gl_scale = 1.0
	_pf_last_gl_scale = 1.0


	# Mirai rows will be (re)loaded lazily
	_mirai_rows_loaded = false
	_mirai_links.clear()
	_mirai_line_root = null

	var debug_keys: Array = []
	for k in anim_bank.buckets_scale.keys():
		debug_keys.append(k)
		if debug_keys.size() >= 8:
			break


func _ensure_note_shader() -> void:
	if _note_shader != null:
		return

	var res := load(NOTE_VFX_SHADER_PATH)
	if res is Shader:
		_note_shader = res
	else:
		push_warning("%s: Failed to load note shader at %s" % [LOG_NAME, NOTE_VFX_SHADER_PATH])
		_note_shader = Shader.new()


func _get_shader() -> Shader:
	if _note_shader == null:
		_ensure_note_shader()
	return _note_shader


func _ensure_sm(ci: CanvasItem) -> ShaderMaterial:
	if ci == null:
		return null

	if not ci.has_meta(VFX_META_ORIG_MAT):
		ci.set_meta(VFX_META_ORIG_MAT, ci.material)

	var sm := ci.material as ShaderMaterial
	if sm == null or sm.shader == null:
		sm = ShaderMaterial.new()
		sm.shader = _get_shader()
		sm.resource_local_to_scene = true
		ci.use_parent_material = false
		ci.material = sm

	ci.set_meta(VFX_META_SM, sm)
	return sm


func _pivot_for(ci: CanvasItem) -> Vector2:
	if ci == null or not is_instance_valid(ci):
		return Vector2.ZERO

	# Cache pivot so we don't recompute every frame
	if ci.has_meta("_vfx_pivot"):
		var cached := ci.get_meta("_vfx_pivot")
		if cached is Vector2:
			return cached

	var pivot := Vector2.ZERO

	if ci is Sprite2D:
		var s := ci as Sprite2D
		if s.centered:
			pivot = Vector2.ZERO
		elif s.region_enabled:
			pivot = s.region_rect.size * 0.5 - s.offset
		else:
			var sz := Vector2.ZERO
			if s.texture != null:
				sz = s.texture.get_size()
			pivot = sz * 0.5 - s.offset
	elif ci is Control:
		pivot = (ci as Control).size * 0.5
	elif ci.has_method("get_item_rect"):
		var r: Rect2 = ci.call("get_item_rect")
		pivot = r.position + r.size * 0.5

	ci.set_meta("_vfx_pivot", pivot)
	return pivot



# Store scale/rotation/offset on the node; we commit all three at once via _commit_transform.
func _set_scale(ci: CanvasItem, s: float) -> void:
	if ci == null or not is_instance_valid(ci):
		return
	ci.set_meta("_vfx_scale", s)


func _set_rotation(ci: CanvasItem, deg: float) -> void:
	if ci == null or not is_instance_valid(ci):
		return
	ci.set_meta("_vfx_rot_deg", deg)


func _set_offset(ci: CanvasItem, ofs: Vector2) -> void:
	if ci == null or not is_instance_valid(ci):
		return
	ci.set_meta("_vfx_offset", ofs)


func _set_color(ci: CanvasItem, col: Color) -> void:
	var sm := _ensure_sm(ci)
	if sm == null:
		return
	sm.set_shader_parameter("override_color", col)
	ci.queue_redraw()


func _set_glow(ci: CanvasItem, g: float) -> void:
	if ci == null or not is_instance_valid(ci):
		return
	var sm := _ensure_sm(ci)
	if sm == null:
		return
	# Parity with MegaInjector: pass glow straight through
	sm.set_shader_parameter("u_glow", max(g, 0.0))
	ci.queue_redraw()

# Compute and apply packed transform for a CanvasItem:
#   x' = M * x + T, with pivot/scale/rotation/offset baked in.
func _commit_transform(ci: CanvasItem) -> void:
	if ci == null or not is_instance_valid(ci):
		return

	var sm := _ensure_sm(ci)
	if sm == null:
		return

	var scale: float = 1.0
	if ci.has_meta("_vfx_scale"):
		scale = float(ci.get_meta("_vfx_scale"))

	var rot_deg: float = 0.0
	if ci.has_meta("_vfx_rot_deg"):
		rot_deg = float(ci.get_meta("_vfx_rot_deg"))

	var ofs: Vector2 = Vector2.ZERO
	if ci.has_meta("_vfx_offset"):
		ofs = ci.get_meta("_vfx_offset")

	var pivot := _pivot_for(ci)

	var s := scale
	var rad := deg_to_rad(rot_deg)
	var c := cos(rad)
	var sn := sin(rad)

	# M = R * S, uniform scalar scale
	var a := c * s
	var b := -sn * s
	var c2 := sn * s
	var d := c * s

	# x' = R * S * (x - pivot) + pivot + ofs
	#    = M * x + (-M * pivot + pivot + ofs)
	var mp := Vector2(
		a * pivot.x + b * pivot.y,
		c2 * pivot.x + d * pivot.y
	)
	var T := pivot + ofs - mp

	sm.set_shader_parameter("u_trs0", Vector4(a, b, c2, d))
	sm.set_shader_parameter("u_trs1", T)
	ci.queue_redraw()



# ─────────────────────────────────────────────
# Spotlight overlay helpers
# ─────────────────────────────────────────────

func _get_spot_shader() -> Shader:
	if _spot_shader != null:
		return _spot_shader

	var res := load(FULLSCREEN_SPOT_SHADER_PATH)
	if res is Shader:
		_spot_shader = res
	else:
		push_warning("%s: Failed to load fullscreen spotlight shader at %s" % [LOG_NAME, FULLSCREEN_SPOT_SHADER_PATH])
		_spot_shader = Shader.new()
	return _spot_shader


func _ensure_spot_overlay(any_drawer: Node) -> void:
	if any_drawer == null or not any_drawer.is_inside_tree():
		return

	# Already have a valid overlay?
	if _spot_overlay != null and _spot_overlay.is_inside_tree():
		return

	# Find GameLayer starting from this drawer
	var cur: Node = any_drawer
	var game_layer: Node = null
	while cur != null:
		if String(cur.name) == "GameLayer":
			game_layer = cur
			break
		cur = cur.get_parent()

	if game_layer == null:
		return

	# Find a Control ancestor to attach the overlay to.
	var attach_ctrl: Control = null
	cur = game_layer.get_parent()
	while cur != null:
		if cur is Control:
			attach_ctrl = cur as Control
			break
		cur = cur.get_parent()

	if attach_ctrl == null:
		return

	# Reuse existing overlay if present on that Control
	var existing: Node = attach_ctrl.get_node_or_null("PH_SpotOverlay")
	if existing != null and existing is ColorRect:
		_spot_overlay = existing
	else:
		# Create a new full-screen ColorRect overlay
		var cr: ColorRect = ColorRect.new()
		cr.name = "PH_SpotOverlay"
		cr.mouse_filter = Control.MOUSE_FILTER_IGNORE

		# Full-screen anchors
		cr.anchor_left   = 0.0
		cr.anchor_top    = 0.0
		cr.anchor_right  = 1.0
		cr.anchor_bottom = 1.0
		cr.offset_left   = 0.0
		cr.offset_top    = 0.0
		cr.offset_right  = 0.0
		cr.offset_bottom = 0.0

		var sm: ShaderMaterial = ShaderMaterial.new()
		sm.shader = _get_spot_shader()
		cr.material = sm

		attach_ctrl.add_child(cr)
		attach_ctrl.move_child(cr, attach_ctrl.get_child_count() - 1) # draw on top

		_spot_overlay = cr

	# ── NEW: ensure a runtime ticker Timer exists on the same Control ──
	var ticker = attach_ctrl.get_node_or_null("PH_VFX_RuntimeTicker")
	if ticker == null:
		ticker = Timer.new()
		ticker.name = "PH_VFX_RuntimeTicker"
		ticker.one_shot = false
		ticker.wait_time = 0.03  # ~33 FPS is enough for VFX
		attach_ctrl.add_child(ticker)
		ticker.timeout.connect(Callable(self, "_on_runtime_tick"))
		ticker.start()

func _on_runtime_tick() -> void:
	# If we never got a chart time, or overlay is gone, do nothing
	if _spot_overlay == null or not _spot_overlay.is_inside_tree():
		return
	if _rt_last_chart_ms < 0.0 or _rt_last_wall_ms < 0:
		return

	var wall_now: int = Time.get_ticks_msec()
	var dt_ms: int = wall_now - _rt_last_wall_ms
	if dt_ms < 0:
		dt_ms = 0

	var t_est: int = int(_rt_last_chart_ms + float(dt_ms))

	# We don't have any current drawers here, but _update_spot_overlay only
	# needs time to decide whether SPOT is active; it already handles an
	# empty drawer list.
	var empty_drawers: Array = []
	_update_spot_overlay(empty_drawers, t_est)
	_update_mirai_lines_runtime()

func _note_drawer_to_screen_uv(d: Node, prefer_head: bool = false) -> Vector2:
	if d == null or not d.is_inside_tree():
		return Vector2(0.5, 0.5)

	var ci: CanvasItem = null

	# prefer_head=false → aim at target first
	# prefer_head=true  → aim at Head/Note first
	if prefer_head:
		if d.has_node("Note"):
			ci = d.get_node("Note") as CanvasItem
		elif d.has_node("NoteTarget/Sprite2D"):
			ci = d.get_node("NoteTarget/Sprite2D") as CanvasItem
		elif d.has_node("NoteTarget"):
			ci = d.get_node("NoteTarget") as CanvasItem
	else:
		if d.has_node("NoteTarget/Sprite2D"):
			ci = d.get_node("NoteTarget/Sprite2D") as CanvasItem
		elif d.has_node("NoteTarget"):
			ci = d.get_node("NoteTarget") as CanvasItem
		elif d.has_node("Note"):
			ci = d.get_node("Note") as CanvasItem

	if ci == null and d is CanvasItem:
		ci = d as CanvasItem

	if ci == null:
		return Vector2(0.5, 0.5)

	var vp: Viewport = ci.get_viewport()
	if vp == null:
		return Vector2(0.5, 0.5)

	var rect: Rect2 = vp.get_visible_rect()
	if rect.size.x == 0.0 or rect.size.y == 0.0:
		return Vector2(0.5, 0.5)

	var canvas_pos: Vector2 = ci.get_global_transform_with_canvas().origin
	var canvas_xform: Transform2D = vp.get_canvas_transform()
	var screen_pos: Vector2 = canvas_xform * canvas_pos

	var uv_x: float = (screen_pos.x - rect.position.x) / rect.size.x
	var uv_y: float = (screen_pos.y - rect.position.y) / rect.size.y

	return Vector2(
		clampf(uv_x, 0.0, 1.0),
		clampf(uv_y, 0.0, 1.0)
	)


func _update_spotlight_for_drawer(d: Node, sm: ShaderMaterial) -> void:
	if d == null or sm == null:
		return

	# Spot 1 (main) → target / judgment ring
	var target_uv: Vector2 = _note_drawer_to_screen_uv(d, false)

	# Spot 2 (secondary) → icon / head sprite
	var icon_uv: Vector2 = _note_drawer_to_screen_uv(d, true)

	sm.set_shader_parameter("u_spot1_center", target_uv)

	sm.set_shader_parameter("u_spot2_enable", true)
	sm.set_shader_parameter("u_spot2_center", icon_uv)


func _update_spot_overlay(drawers: Array, t_ms: int) -> void:
	# No overlay or no bank → nothing to do
	if _spot_overlay == null or not _spot_overlay.is_inside_tree():
		return
	if anim_bank == null:
		return

	# If there are no SPOT rows at all, hard-disable the overlay
	if anim_bank.buckets_spot.is_empty():
		var sm0 := _spot_overlay.material as ShaderMaterial
		if sm0 != null:
			sm0.set_shader_parameter("u_tint", Color(0, 0, 0, 0.0))
			sm0.set_shader_parameter("u_spot2_enable", false)
		_spot_overlay.visible = false
		return

	var sm := _spot_overlay.material as ShaderMaterial
	if sm == null:
		return

	# Keep circles round in screen space
	var vp: Viewport = _spot_overlay.get_viewport()
	if vp != null:
		var rect: Rect2 = vp.get_visible_rect()
		if rect.size.y != 0.0:
			var ratio: float = rect.size.x / rect.size.y
			sm.set_shader_parameter("u_screen_ratio", Vector2(ratio, 1.0))

	# ----------------------------------------------------------------
	# 1) Choose the best active SPOT at this time (mirrors MegaInjector)
	# ----------------------------------------------------------------
	var best_key := ""
	var best_prio := -2147483648
	var best_start := -1
	var best_spot: Dictionary = {}
	var best_prev: Dictionary = {}
	var best_next: Dictionary = {}

	for key_v in anim_bank.buckets_spot.keys():
		var key := String(key_v)

		var times_for_key: PackedInt32Array = anim_bank.times_spot.get(key, PackedInt32Array())
		if times_for_key.is_empty():
			continue

		var first_t: int = times_for_key[0]
		var last_t: int = times_for_key[times_for_key.size() - 1]
		if t_ms < first_t or t_ms > last_t:
			continue

		var pair := anim_bank._pair_around_time(anim_bank.times_spot, anim_bank.buckets_spot, key, t_ms)
		var prev_r: Dictionary = pair[0]
		var next_r: Dictionary = pair[1]
		if prev_r.is_empty():
			continue

		var spot := anim_bank._sample_spot_for_key(key, t_ms)
		if not bool(spot.get("enable", false)):
			continue

		var prio0 := int(prev_r.get("spot_priority", prev_r.get("priority", 0)))
		var prio1 := prio0
		if not next_r.is_empty():
			prio1 = int(next_r.get("spot_priority", next_r.get("priority", prio0)))
		var prio := (prio0 if prio0 > prio1 else prio1)

		var start_time := int(prev_r.get("time", t_ms))

		if prio > best_prio or (prio == best_prio and start_time > best_start):
			best_prio = prio
			best_start = start_time
			best_key = key
			best_spot = spot
			best_prev = prev_r
			best_next = next_r

	# No active SPOT at this time → disable overlay immediately
	if best_key == "" or best_spot.is_empty() or not bool(best_spot.get("enable", false)):
		sm.set_shader_parameter("u_tint", Color(0, 0, 0, 0.0))
		sm.set_shader_parameter("u_spot2_enable", false)
		_spot_overlay.visible = false
		return


	# ----------------------------------------------------------------
	# 2) Find a drawer to anchor the spotlight to (target/head)
	# ----------------------------------------------------------------

	# First try any drawer from this frame
	var anchor: Node = null
	for d_v in drawers:
		var d: Node = d_v
		if d == null or not d.is_inside_tree():
			continue
		if _get_effective_key_for_drawer(d) == best_key:
			anchor = d
			break

	# Fallback: any cached spotlight drawer that still matches best_key
	if anchor == null and not _spot_drawers.is_empty():
		var alive: Array = []
		for d2 in _spot_drawers:
			if d2 != null and d2.is_inside_tree():
				alive.append(d2)
		_spot_drawers = alive

		for d2 in _spot_drawers:
			if _get_effective_key_for_drawer(d2) == best_key:
				anchor = d2
				break

	# Compute UVs – if we don't find a drawer, fall back to center screen
	var target_uv := Vector2(0.5, 0.5)
	var icon_uv := target_uv

	if anchor != null:
		target_uv = _note_drawer_to_screen_uv(anchor, false)
		icon_uv = _note_drawer_to_screen_uv(anchor, true)

	# ----------------------------------------------------------------
	# 3) Drive shader parameters from sampled SPOT row (parity with editor)
	# ----------------------------------------------------------------
	var base_radius: float = float(best_spot.get("radius", 0.12))
	var soft: float = float(best_spot.get("soft", 0.20))
	var dim: float = float(best_spot.get("dim", 0.15))

	var radius2: float = base_radius * 0.7
	var soft2: float = soft * 0.7

	var alpha: float = clamp(1.0 - dim, 0.0, 1.0)

	sm.set_shader_parameter("u_tint", Color(0.0, 0.0, 0.0, alpha))

	# Main spotlight: target / judgement ring
	sm.set_shader_parameter("u_spot1_center", target_uv)
	sm.set_shader_parameter("u_spot1_radius", base_radius)
	sm.set_shader_parameter("u_spot1_soft",   soft)

	# Secondary spotlight: icon / head
	sm.set_shader_parameter("u_spot2_enable", true)
	sm.set_shader_parameter("u_spot2_center", icon_uv)
	sm.set_shader_parameter("u_spot2_radius", radius2)
	sm.set_shader_parameter("u_spot2_soft",   soft2)
	_spot_overlay.visible = true




# ─────────────────────────────────────────────
# Mirai link runtime helpers (JSON-driven)
# ─────────────────────────────────────────────

func _ensure_mirai_rows_loaded() -> void:
	if _mirai_rows_loaded:
		return
	_mirai_rows_loaded = true
	_mirai_links.clear()
	_mirai_line_root = null

	if _current_vfx_path == "" or not FileAccess.file_exists(_current_vfx_path):
		return

	var f := FileAccess.open(_current_vfx_path, FileAccess.READ)
	if f == null:
		return
	var parsed := JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_ARRAY:
		return

	for e_v in (parsed as Array):
		if typeof(e_v) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = e_v
		if String(e.get("layer", "")) != "$MIRAI_LINK":
			continue

		var head_key := String(e.get("head_key", ""))
		var tail_key := String(e.get("tail_key", ""))
		if head_key == "" or tail_key == "":
			continue

		# We still read times, but we won't rely on them for lifetime.
		var head_time := int(e.get("head_time", 0))
		var tail_time := int(e.get("tail_time", 0))

		_mirai_links.append({
			"head_key": head_key,
			"tail_key": tail_key,
			"head_time": head_time,
			"tail_time": tail_time,
			"head_drawer": null,
			"tail_drawer": null,
			"head_note": null,
			"tail_note": null,
			"line": null,
		})



func _ensure_mirai_line_root(any_drawer: Node) -> void:
	if _mirai_line_root != null and _mirai_line_root.is_inside_tree():
		return
	if any_drawer == null or not any_drawer.is_inside_tree():
		return

	# Climb to GameLayer
	var cur: Node = any_drawer
	var game_layer: Node = null
	while cur != null:
		if String(cur.name) == "GameLayer":
			game_layer = cur
			break
		cur = cur.get_parent()

	if game_layer == null:
		return

	var parent: Node = game_layer
	var existing := parent.get_node_or_null(MIRAI_LINE_NODE_NAME)
	if existing is Node2D:
		_mirai_line_root = existing
		return

	var container := Node2D.new()
	container.name = MIRAI_LINE_NODE_NAME
	parent.add_child(container)

	# Try to position and z-order it just behind LAYER_Notes
	var notes_layer := parent.get_node_or_null("LAYER_Notes")

	if notes_layer != null:
		# Put container right before LAYER_Notes in the tree
		parent.move_child(container, notes_layer.get_index())

		# And make sure its z_index is just below LAYER_Notes so it draws behind
		if notes_layer is Node2D:
			var notes2d := notes_layer as Node2D
			container.z_as_relative = notes2d.z_as_relative
			container.z_index = notes2d.z_index - 1
	else:
		# Fallback: put it at the very front (we'll still control z_index if needed)
		parent.move_child(container, 0)

	_mirai_line_root = container




func _update_mirai_link_drawer_refs(drawers: Array) -> void:
	if _mirai_links.is_empty():
		return

	var any_drawer: Node = null
	if not drawers.is_empty():
		any_drawer = drawers[0] as Node

	if _mirai_line_root == null or not _mirai_line_root.is_inside_tree():
		_ensure_mirai_line_root(any_drawer)
	if _mirai_line_root == null or not _mirai_line_root.is_inside_tree():
		return

	for d_v in drawers:
		var d: Node = d_v
		if d == null or not d.is_inside_tree() or not d.has_method("get"):
			continue

		var nd = d.get("note_data")
		if nd == null:
			continue

		# Use raw key so Mirai links don't depend on VFX anim-bank rows
		var raw_key := _key_for_drawer(d)
		if raw_key == "":
			continue

		# Ensure parts cached for later head lookup
		if not _drawer_parts.has(d):
			var parts := _parts_for_drawer(d)
			_init_part_state(parts)
			_drawer_parts[d] = parts

		for i in range(_mirai_links.size()):
			var link: Dictionary = _mirai_links[i]

			# Bind head
			if link["head_drawer"] == null and link["head_key"] == raw_key:
				link["head_drawer"] = d
				link["head_note"] = nd

			# Bind tail
			if link["tail_drawer"] == null and link["tail_key"] == raw_key:
				link["tail_drawer"] = d
				link["tail_note"] = nd

			_mirai_links[i] = link


func _update_mirai_lines_runtime() -> void:
	if _mirai_links.is_empty():
		return
	if _mirai_line_root == null or not _mirai_line_root.is_inside_tree():
		return

	for i in range(_mirai_links.size()):
		var link: Dictionary = _mirai_links[i]
		var first_d: Node = link["head_drawer"]
		var last_d: Node = link["tail_drawer"]
		var head_note = link.get("head_note", null)
		var tail_note = link.get("tail_note", null)
		var line: Line2D = link["line"]

		var kill_link := false

		# 1) Validate head drawer + note identity
		if head_note != null:
			if first_d == null or not is_instance_valid(first_d) or not first_d.is_inside_tree():
				kill_link = true
			elif not first_d.has_method("get") or first_d.get("note_data") != head_note:
				# Drawer got reused for another note
				kill_link = true

		# 2) Validate tail drawer + note identity
		if not kill_link and tail_note != null:
			if last_d == null or not is_instance_valid(last_d) or not last_d.is_inside_tree():
				kill_link = true
			elif not last_d.has_method("get") or last_d.get("note_data") != tail_note:
				kill_link = true

		# 3) If invalid for any reason → nuke line and clear refs
		if kill_link:
			if line != null and is_instance_valid(line):
				line.queue_free()
			link["line"] = null
			link["head_drawer"] = null
			link["tail_drawer"] = null
			link["head_note"] = null
			link["tail_note"] = null
			_mirai_links[i] = link
			continue

		# Still waiting for both ends? Nothing to draw yet
		if first_d == null or last_d == null or head_note == null or tail_note == null:
			if line != null and is_instance_valid(line):
				line.visible = false
			_mirai_links[i] = link
			continue

		# 4) We have valid endpoints → ensure a Line2D exists
		if line == null or not is_instance_valid(line):
			line = Line2D.new()
			line.name = "PH_MiraiLinkLine"
			line.width = 6.0
			line.default_color = Color(1.0, 1.0, 1.0, 0.85)
			line.begin_cap_mode = Line2D.LINE_CAP_ROUND
			line.end_cap_mode = Line2D.LINE_CAP_ROUND
			line.antialiased = true
			_mirai_line_root.add_child(line)
			_mirai_line_root.move_child(line, 0)
			link["line"] = line

		# 5) Ensure part caches exist (for anchors)
		var parts1: Dictionary = _drawer_parts.get(first_d, {})
		if parts1.is_empty():
			parts1 = _parts_for_drawer(first_d)
			_init_part_state(parts1)
			_drawer_parts[first_d] = parts1

		var parts2: Dictionary = _drawer_parts.get(last_d, {})
		if parts2.is_empty():
			parts2 = _parts_for_drawer(last_d)
			_init_part_state(parts2)
			_drawer_parts[last_d] = parts2

		# Anchors: prefer target (judgement ring), fallback to head if missing
		var anchor1: CanvasItem = parts1.get("target", null)
		if anchor1 == null:
			anchor1 = parts1.get("head", null)

		var anchor2: CanvasItem = parts2.get("target", null)
		if anchor2 == null:
			anchor2 = parts2.get("head", null)

		if anchor1 == null or anchor2 == null:
			if line != null and is_instance_valid(line):
				line.visible = false
			_mirai_links[i] = link
			continue

		# 6) Position the line between the two anchors (targets)
		var pos1: Vector2 = anchor1.get_global_transform_with_canvas().origin
		var pos2: Vector2 = anchor2.get_global_transform_with_canvas().origin

		var inv_tf: Transform2D = line.get_global_transform_with_canvas().affine_inverse()
		var p1_local: Vector2 = inv_tf * pos1
		var p2_local: Vector2 = inv_tf * pos2

		line.points = PackedVector2Array([p1_local, p2_local])
		line.visible = true

		_mirai_links[i] = link




# ─────────────────────────────────────────────
# Drawer → key (matching MegaInjector)
# ─────────────────────────────────────────────

func _safe_get(obj: Object, prop: String, fallback: Variant = null) -> Variant:
	if obj == null:
		return fallback

	if obj.has_method("get_property_list"):
		for p in obj.get_property_list():
			if String(p.name) == prop:
				return obj.get(prop)

	if obj.has_method("has_meta") and obj.has_meta(prop):
		return obj.get_meta(prop)

	if obj.has_method("get"):
		var v = obj.get(prop)
		if v != null:
			return v

	return fallback


func _is_layer2_from_obj(obj: Object) -> bool:
	if obj == null:
		return false

	var lidx = _safe_get(obj, "layer_index", null)
	if lidx != null and int(lidx) == 1:
		return true

	var has_flag = _safe_get(obj, "second_layer", null)
	if has_flag != null and bool(has_flag):
		return true

	var layer_meta = _safe_get(obj, "layer", null)
	if layer_meta != null and String(layer_meta).ends_with("2"):
		return true

	return false


func _is_slide_chain_piece(d: Node) -> bool:
	if d == null or not d.has_method("get"):
		return false

	var nd = d.get("note_data")
	if nd == null:
		return false

	var obj := nd as Object
	if obj != null and obj.has_method("is_slide_hold_piece"):
		return obj.is_slide_hold_piece()

	return false


func _is_slide_note(d: Node) -> bool:
	if d == null or not d.has_method("get"):
		return false

	var nd = d.get("note_data")
	if nd == null:
		return false

	var obj := nd as Object
	if obj == null or not obj.has_method("get"):
		return false

	var nt_v = obj.get("note_type")
	if nt_v == null:
		return false

	var nti := int(nt_v)
	# 4,5 = slide heads; 6,7 = slide chain/tail pieces
	return nti == 4 or nti == 5 or nti == 6 or nti == 7


func _key_for_drawer(d: Node) -> String:
	if d == null or not d.has_method("get"):
		return ""

	var nd = d.get("note_data")
	if nd == null:
		return ""
	if not (nd as Object).has_method("get"):
		return ""

	var nt_v = (nd as Object).get("note_type")
	var time_v = (nd as Object).get("time")
	if nt_v == null or time_v == null:
		return ""

	var nti := int(nt_v)
	var head_t := int(time_v)

	var lname := "UNKNOWN"
	match nti:
		0: lname = "UP"
		1: lname = "LEFT"
		2: lname = "DOWN"
		3: lname = "RIGHT"
		4, 6: lname = "SLIDE_LEFT"
		5, 7: lname = "SLIDE_RIGHT"
		8: lname = "HEART"

	var is_l2 := _is_layer2_from_obj(nd) or _is_layer2_from_obj(d)
	var layer_tag := "layer_%s%s" % [lname, ("2" if is_l2 else "")]

	return "%s@%d@%d" % [layer_tag, nti, head_t]


func _anim_bank_has_any_rows_for_key(key: String) -> bool:
	if anim_bank == null:
		return false
	if anim_bank.buckets_scale.has(key):
		return true
	if anim_bank.buckets_color.has(key):
		return true
	if anim_bank.buckets_rot.has(key):
		return true
	if anim_bank.buckets_offset.has(key):
		return true
	if anim_bank.buckets_spot.has(key):
		return true
	if anim_bank.buckets_glow.has(key):   # NEW
		return true
	return false

func _sample_all_for_key_cached(key: String, t_ms: int) -> Dictionary:
	if anim_bank == null or key == "":
		return {}

	# If time changed, start a new per-frame cache
	if _frame_sample_time_ms != t_ms:
		_frame_sample_time_ms = t_ms
		_frame_sample_cache.clear()

	if _frame_sample_cache.has(key):
		return _frame_sample_cache[key]

	var res := {
		"S": anim_bank._sample_scales_for_key(key, t_ms),
		"C": anim_bank._sample_colors_for_key(key, t_ms),
		"R": anim_bank._sample_rot_for_key(key, t_ms),
		"O": anim_bank._sample_offset_for_key(key, t_ms),
		"G": anim_bank._sample_glow_for_key(key, t_ms),
	}

	_frame_sample_cache[key] = res
	return res


func _get_effective_key_for_drawer(d: Node) -> String:
	if d == null or not d.has_method("get") or anim_bank == null:
		return ""

	var raw_key: String
	if _drawer_key.has(d):
		raw_key = String(_drawer_key[d])
	else:
		raw_key = _key_for_drawer(d)
		if raw_key == "":
			return ""
		_drawer_key[d] = raw_key

	# Exact match in any bucket → use as-is.
	if _anim_bank_has_any_rows_for_key(raw_key):
		return raw_key

	# Cached remap?
	if _key_remap.has(raw_key):
		return String(_key_remap[raw_key])

	var effective_key := ""

	# Only *chain pieces* borrow from a slide head.
	if _is_slide_chain_piece(d):
		effective_key = _find_nearest_slide_head_key(raw_key)
	else:
		effective_key = ""  # taps, hearts, and slide heads don't borrow

	_key_remap[raw_key] = effective_key
	return effective_key


func _find_nearest_slide_head_key(chain_raw_key: String) -> String:
	if anim_bank == null:
		return ""

	var parts := chain_raw_key.split("@")
	if parts.size() != 3:
		return ""

	var layer_tag := String(parts[0])
	var chain_time := int(parts[2])

	var candidate_dict: Dictionary = {}

	for k in anim_bank.buckets_scale.keys():
		candidate_dict[k] = true
	for k in anim_bank.buckets_color.keys():
		candidate_dict[k] = true
	for k in anim_bank.buckets_rot.keys():
		candidate_dict[k] = true
	for k in anim_bank.buckets_offset.keys():
		candidate_dict[k] = true
	for k in anim_bank.buckets_spot.keys():
		candidate_dict[k] = true
	for k in anim_bank.buckets_glow.keys():   # NEW
		candidate_dict[k] = true

	if candidate_dict.is_empty():
		return ""

	var best_key: String = ""
	var best_dt: int = 2147483647

	for key_v in candidate_dict.keys():
		var ks := String(key_v)
		var kp := ks.split("@")
		if kp.size() != 3:
			continue

		# Same lane (layer_UP, layer_SLIDE_RIGHT2, etc.)
		if String(kp[0]) != layer_tag:
			continue

		var ntk := int(kp[1])
		# Only slide *heads* (4,5) are valid donors
		if ntk != 4 and ntk != 5:
			continue

		var head_time := int(kp[2])
		var dt := abs(head_time - chain_time)

		# Don't borrow from heads that are too far away in time
		if dt > SLIDE_CHAIN_MAX_HEAD_DT_MS:
			continue

		if dt < best_dt:
			best_dt = dt
			best_key = ks

	return best_key



# ─────────────────────────────────────────────
# Playfield slides: load + eval
# ─────────────────────────────────────────────

func _ensure_playfield_rows_loaded() -> void:
	if _pf_rows_loaded:
		return
	_pf_rows_loaded = true

	_pf_rows.clear()
	_pf_chain.clear()
	_pf_rot_rows.clear()
	_pf_rot_chain.clear()
	_pf_scale_rows.clear()

	if _current_vfx_path == "" or not FileAccess.file_exists(_current_vfx_path):
		return

	var f := FileAccess.open(_current_vfx_path, FileAccess.READ)
	if f == null:
		return
	var parsed := JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_ARRAY:
		return

	for e_v in (parsed as Array):
		if typeof(e_v) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = e_v
		var layer_name := String(e.get("layer", ""))

		# ---- Slides ----
		if layer_name == PF_ENTRY_TAG:
			var t0 := float(e.get("pf_slide_start_time", 0.0))
			var t1 := float(e.get("pf_slide_end_time", 0.0))
			if t1 <= t0:
				continue

			var ep_val = e.get("pf_slide_endpoint", null)
			var endpoint := Vector2.ZERO
			if typeof(ep_val) == TYPE_ARRAY:
				var arr: Array = ep_val
				if arr.size() >= 2:
					endpoint = Vector2(float(arr[0]), float(arr[1]))

			var ease := String(e.get("pf_slide_ease", "linear"))

			_pf_rows.append({
				"t0": t0,
				"t1": t1,
				"endpoint": endpoint,
				"ease": ease,
			})

		elif layer_name == PF_ROTATE_TAG:
			var rt0 := float(e.get("pf_rot_start_time", 0.0))
			var rt1 := float(e.get("pf_rot_end_time", 0.0))
			if rt1 <= rt0:
				continue

			var a0 := float(e.get("pf_rot_angle_start_deg", 0.0))
			var a1 := float(e.get("pf_rot_angle_end_deg", 0.0))
			var rease := String(e.get("pf_rot_ease", "linear"))

			# This is stored as GameLayer-local (same as the editor tool)
			var pv_val = e.get("pf_rot_pivot_local", null)
			var pivot_gl := Vector2.ZERO
			if typeof(pv_val) == TYPE_ARRAY:
				var parr: Array = pv_val
				if parr.size() >= 2:
					pivot_gl = Vector2(float(parr[0]), float(parr[1]))

			_pf_rot_rows.append({
				"t0": rt0,
				"t1": rt1,
				"a0": a0,
				"a1": a1,
				"ease": rease,
				"pivot_gl": pivot_gl,
			})

		# ---- Scale (uniform wrapper scale multiplier) ----
		elif layer_name == PF_SCALE_TAG:
			var st0 := float(e.get("pf_scale_start_time", 0.0))
			var st1 := float(e.get("pf_scale_end_time", 0.0))
			if st1 <= st0:
				continue

			var s0 := float(e.get("pf_scale_start_mult", 1.0))
			var s1 := float(e.get("pf_scale_end_mult",   1.0))
			var sease := String(e.get("pf_scale_ease", "linear"))

			_pf_scale_rows.append({
				"t0": st0,
				"t1": st1,
				"s0": s0,
				"s1": s1,
				"ease": sease,
			})

	# ---- seconds vs ms heuristic (slides + rotations + scale) ----
	var max_end := 0.0
	for r in _pf_rows:
		var e_t := float(r["t1"])
		if e_t > max_end:
			max_end = e_t
	for rr in _pf_rot_rows:
		var e_rt := float(rr["t1"])
		if e_rt > max_end:
			max_end = e_rt
	for sr in _pf_scale_rows:  # NEW
		var e_st := float(sr["t1"])
		if e_st > max_end:
			max_end = e_st

	if max_end > 0.0 and max_end <= 600.0:
		for r2 in _pf_rows:
			r2["t0"] = float(r2["t0"]) * 1000.0
			r2["t1"] = float(r2["t1"]) * 1000.0
		for rr2 in _pf_rot_rows:
			rr2["t0"] = float(rr2["t0"]) * 1000.0
			rr2["t1"] = float(rr2["t1"]) * 1000.0
		for sr2 in _pf_scale_rows:     # NEW
			sr2["t0"] = float(sr2["t0"]) * 1000.0
			sr2["t1"] = float(sr2["t1"]) * 1000.0

	print("%s: PF rows loaded → slides:%d  rotates:%d  scales:%d  from:%s"
		% [LOG_NAME, _pf_rows.size(), _pf_rot_rows.size(), _pf_scale_rows.size(), _current_vfx_path])



func _build_pf_chain() -> void:
	_pf_chain.clear()
	if _pf_rows.is_empty():
		return

	var prev_end: Vector2 = _pf_baseline_pos

	for r in _pf_rows:
		var t0 := float(r["t0"])
		var t1 := float(r["t1"])
		var base_pos := prev_end
		var end_pos := Vector2.ZERO
		var endpoint: Vector2 = r["endpoint"]

		if PF_USE_ABSOLUTE_CHAIN:
			end_pos = endpoint
		else:
			end_pos = base_pos + endpoint

		_pf_chain.append({
			"t0": t0,
			"t1": t1,
			"base": base_pos,
			"end": end_pos,
			"ease": String(r["ease"]),
		})

		prev_end = end_pos

func _build_pf_rot_chain() -> void:
	_pf_rot_chain.clear()
	if _pf_rot_rows.is_empty():
		return
	if _pf_wrapper == null or not _pf_wrapper.is_inside_tree():
		return
	if _pf_game_layer == null or not _pf_game_layer.is_inside_tree():
		return

	var parent := _pf_wrapper.get_parent()
	var parent_ci := parent as CanvasItem
	var parent_xf: Transform2D = Transform2D.IDENTITY
	if parent_ci != null:
		parent_xf = parent_ci.get_global_transform_with_canvas()

	for r in _pf_rot_rows:
		var t0 := float(r["t0"])
		var t1 := float(r["t1"])
		var a0 := float(r["a0"])
		var a1 := float(r["a1"])
		var ease := String(r["ease"])
		var pivot_gl: Vector2 = r.get("pivot_gl", Vector2.ZERO)

		# GameLayer-local → world → wrapper-parent space
		var pivot_world: Vector2 = _pf_game_layer.get_global_transform_with_canvas() * pivot_gl
		var pivot_parent: Vector2 = parent_xf.affine_inverse() * pivot_world

		_pf_rot_chain.append({
			"t0": t0,
			"t1": t1,
			"a0": a0,
			"a1": a1,
			"ease": ease,
			"pivot_parent": pivot_parent,
		})

	_pf_rot_chain.sort_custom(func(a, b):
		return float(a["t0"]) < float(b["t0"])
	)



func _ensure_playfield_wrapper_from_drawer(any_drawer: Node) -> void:
	# No rows => no wrapper
	if _pf_rows.is_empty() and _pf_rot_rows.is_empty() and _pf_scale_rows.is_empty():
		return
	# Already have a wrapper?
	if _pf_wrapper != null and _pf_wrapper.is_inside_tree():
		return
	# Need a live drawer to climb up to GameLayer
	if any_drawer == null or not any_drawer.is_inside_tree():
		return

	# Walk upwards to find GameLayer
	var cur: Node = any_drawer
	var game_layer: Node2D = null
	while cur != null:
		if String(cur.name) == "GameLayer":
			game_layer = cur as Node2D
			break
		cur = cur.get_parent()

	if game_layer == null:
		return

	var parent: Node = game_layer.get_parent()
	if parent == null:
		return

	var existing: Node = parent.get_node_or_null("PH_PlayfieldWrapper_RUNTIME")
	if existing is Node2D and (existing as Node2D).is_ancestor_of(game_layer):
		_pf_wrapper = existing as Node2D
		_pf_game_layer = game_layer
		_pf_baseline_pos = _pf_wrapper.position
	else:
		# Create wrapper and reparent GameLayer into it
		var wrapper := Node2D.new()
		wrapper.name = "PH_PlayfieldWrapper_Runtime"
		parent.add_child(wrapper)
		parent.move_child(wrapper, game_layer.get_index())

		var gp: Vector2 = game_layer.get_global_position()
		parent.remove_child(game_layer)
		wrapper.add_child(game_layer)
		game_layer.set_global_position(gp)

		_pf_wrapper = wrapper
		_pf_game_layer = game_layer
		_pf_baseline_pos = _pf_wrapper.position

	# Wrapper baseline scale (kept for slides, but we won't zoom via wrapper anymore)
	if _pf_wrapper != null:
		var sc: Vector2 = _pf_wrapper.scale
		_pf_baseline_scale = (sc.x if sc.x != 0.0 else 1.0)

	# GameLayer baseline scale (this is what we actually zoom)
	if _pf_game_layer != null:
		var gl_sc: Vector2 = _pf_game_layer.scale
		_pf_baseline_gl_scale = (gl_sc.x if gl_sc.x != 0.0 else 1.0)
		_pf_last_gl_scale = _pf_baseline_gl_scale


	_build_pf_chain()
	_build_pf_rot_chain()




func _update_playfield_slides(t_ms: int, any_drawer: Node) -> void:
	# Nothing to do if there are no slide, rotation, *and* scale rows
	if _pf_rows.is_empty() and _pf_rot_rows.is_empty() and _pf_scale_rows.is_empty():
		return

	# Make sure we have a wrapper. If we already made one, we don't need a drawer.
	if _pf_wrapper == null or not _pf_wrapper.is_inside_tree():
		_ensure_playfield_wrapper_from_drawer(any_drawer)
	if _pf_wrapper == null or not _pf_wrapper.is_inside_tree():
		return

	# Ensure chains built
	if _pf_chain.is_empty() and not _pf_rows.is_empty():
		_build_pf_chain()
	if _pf_rot_chain.is_empty() and not _pf_rot_rows.is_empty():
		_build_pf_rot_chain()

		# Slides: evaluate wrapper base position (no rotation yet)
	var t := float(t_ms)

	# Slides: wrapper base position (no rot yet)
	var pos := _eval_pf_pos(t)

	# Rotation: wrapper rotation around its pivot (same semantics as before)
	var angle_now_deg := 0.0
	if not _pf_rot_chain.is_empty():
		var rot_res := _eval_pf_rot_at(t)
		if rot_res.get("ok", false):
			angle_now_deg = float(rot_res["angle"])
			var seg: Dictionary = rot_res["seg"]
			var pv: Vector2 = seg.get("pivot_parent", Vector2.ZERO)
			pos = pv + (pos - pv).rotated(deg_to_rad(angle_now_deg))

	# Commit slides + rotation to the wrapper
	if _pf_wrapper.position != pos:
		_pf_wrapper.position = pos
	if abs(_pf_wrapper.rotation_degrees - angle_now_deg) > 0.001:
		_pf_wrapper.rotation_degrees = angle_now_deg

	# --- Zoom the GameLayer around a fixed GameLayer-local pivot (960,540) ---
	if _pf_game_layer != null and _pf_game_layer.is_inside_tree():
		var sfac := _eval_pf_scale_at(t)
		var target_scale := _pf_baseline_gl_scale * sfac

		# Only do work if scale actually changed since last frame
		if abs(target_scale - _pf_last_gl_scale) > 0.0001:
			var pivot_local := FIELD_PIVOT_GL

			# 1) World position of pivot at current scale/position
			var pivot_world_before: Vector2 = _pf_game_layer.to_global(pivot_local)

			# 2) Apply new scale
			_pf_game_layer.scale = Vector2(target_scale, target_scale)

			# 3) World position of pivot after scaling
			var pivot_world_after: Vector2 = _pf_game_layer.to_global(pivot_local)

			# 4) Convert the world-space delta into the parent's local space,
			#    so rotation on the wrapper doesn't break the adjustment.
			var parent2d := _pf_game_layer.get_parent() as Node2D
			if parent2d != null and parent2d.is_inside_tree():
				var before_local: Vector2 = parent2d.to_local(pivot_world_before)
				var after_local: Vector2  = parent2d.to_local(pivot_world_after)
				var delta_local: Vector2  = before_local - after_local
				_pf_game_layer.position += delta_local
			else:
				# Fallback if, for some reason, there is no Node2D parent
				_pf_game_layer.position += (pivot_world_before - pivot_world_after)

			_pf_last_gl_scale = target_scale



func _progress(tnow: float, t0: float, t1: float) -> float:
	if t1 <= t0:
		return 1.0
	return clamp((tnow - t0) / (t1 - t0), 0.0, 1.0)


func _ease_eval(name: String, x: float) -> float:
	var n := name.strip_edges().to_lower()
	match n:
		"quad_in_out":
			if x < 0.5:
				return 2.0 * x * x
			var u := 1.0 - x
			return 1.0 - 2.0 * u * u
		"quad_in":
			return x * x
		"quad_out":
			var u2 := 1.0 - x
			return 1.0 - u2 * u2
		"cubic_in_out":
			if x < 0.5:
				return 4.0 * x * x * x
			var k := 2.0 * x - 2.0
			return 0.5 * k * k * k + 1.0
		_:
			return x


func _eval_pf_pos(t_ms: float) -> Vector2:
	if _pf_chain.is_empty():
		return _pf_baseline_pos
	if t_ms <= float(_pf_chain[0]["t0"]):
		return _pf_baseline_pos

	var last_end: Vector2 = _pf_baseline_pos
	for seg in _pf_chain:
		var t0 := float(seg["t0"])
		var t1 := float(seg["t1"])
		var b: Vector2 = seg["base"]
		var e: Vector2 = seg["end"]

		if t_ms < t0:
			return last_end
		elif t_ms <= t1:
			var pr := _progress(t_ms, t0, t1)
			var eased := _ease_eval(String(seg["ease"]), pr)
			return b.lerp(e, eased)
		else:
			last_end = e

	return _pf_chain[_pf_chain.size() - 1]["end"]

func _eval_pf_rot_at(t_ms: float) -> Dictionary:
	if _pf_rot_chain.is_empty():
		return {"ok": false}

	if t_ms < float(_pf_rot_chain[0]["t0"]):
		return {"ok": false}

	var angle := 0.0
	var seg: Dictionary = {}

	for s in _pf_rot_chain:
		var t0 := float(s["t0"])
		var t1 := float(s["t1"])

		if t_ms < t0:
			# We haven't reached this segment yet; stop here.
			break

		if t_ms <= t1:
			# Inside this segment → interpolate
			var pr := _progress(t_ms, t0, t1)
			var eased := _ease_eval(String(s["ease"]), pr)
			angle = lerp(float(s["a0"]), float(s["a1"]), eased)
			seg = s
			return {"ok": true, "angle": angle, "seg": seg}
		else:
			# Past this segment → remember its final angle
			angle = float(s["a1"])
			seg = s

	# If we got here, we're past the last segment; stick to its final angle
	return {"ok": true, "angle": angle, "seg": seg}

func _eval_pf_scale_at(t_ms: float) -> float:
	# No scale rows → neutral multiplier
	if _pf_scale_rows.is_empty():
		return 1.0

	# Before first segment → neutral
	if t_ms <= float(_pf_scale_rows[0]["t0"]):
		return 1.0

	var last_s: float = 1.0

	for sr in _pf_scale_rows:
		var t0 := float(sr["t0"])
		var t1 := float(sr["t1"])
		if t_ms < t0:
			return last_s
		elif t_ms <= t1:
			var pr := _progress(t_ms, t0, t1)
			var ez := _ease_eval(String(sr["ease"]), pr)
			var s0 := float(sr["s0"])
			var s1 := float(sr["s1"])
			return lerp(s0, s1, ez)
		else:
			# Remember most recent end multiplier
			last_s = float(sr["s1"])

	return last_s


# ─────────────────────────────────────────────
# Extra: discover slide-chain drawers under GameLayer
# ─────────────────────────────────────────────

func _ensure_extra_drawers_cached(any_drawer: Node) -> void:
	if any_drawer == null or not any_drawer.is_inside_tree():
		return

	# Walk upwards to find GameLayer
	var cur: Node = any_drawer
	var game_layer: Node = null
	while cur != null:
		if String(cur.name) == "GameLayer":
			game_layer = cur
			break
		cur = cur.get_parent()

	if game_layer == null:
		return

	# --- Slide chain pieces ---
	var slide_layer: Node = game_layer.get_node_or_null("LAYER_SlideChainPieces")
	_slide_chain_drawers.clear()
	if slide_layer != null:
		_collect_drawers_with_note_data(slide_layer, _slide_chain_drawers)

	# --- Trails ---
	var trail_layer: Node = game_layer.get_node_or_null("LAYER_Trails")
	_trail_drawers.clear()
	if trail_layer != null:
		_collect_drawers_with_note_data(trail_layer, _trail_drawers)


func _collect_drawers_with_note_data(root: Node, out: Array) -> void:
	if root == null:
		return
	if root.has_method("get"):
		var nd = root.get("note_data")
		if nd != null:
			out.append(root)
	for c in root.get_children():
		if c is Node:
			_collect_drawers_with_note_data(c, out)


func _update_slide_chain_drawers(t_ms: int) -> void:
	if anim_bank == null:
		return
	if _slide_chain_drawers.is_empty():
		return

	for d in _slide_chain_drawers:
		if d == null or not d.is_inside_tree():
			continue

		var nd = null
		if d.has_method("get"):
			nd = d.get("note_data")

		var adj_factor := _get_adj_factor(nd)
		var key: String = _get_effective_key_for_drawer(d)
		if key == "":
			continue

		var parts: Dictionary = _drawer_parts.get(d, {})
		if parts.is_empty():
			parts = _parts_for_drawer(d)
			_init_part_state(parts)
			_drawer_parts[d] = parts

		var samples := _sample_all_for_key_cached(key, t_ms)
		if samples.is_empty():
			continue

		var S: Dictionary = samples["S"]
		var C: Dictionary = samples["C"]
		var R: Dictionary = samples["R"]
		var O: Dictionary = samples["O"]
		var G: Dictionary = samples["G"]


		_apply_drawer_field_transform(d, R, O, false)

		var O_rel := {
			"head":   O.head - O.target,
			"tail":   O.tail - O.target,
			"target": Vector2.ZERO,
			"hold":   O.hold - O.target,
			"bar1":   O.bar1 - O.target,
			"bar2":   O.bar2 - O.target,
		}

		_apply_parts_all(parts, S, C, R, O_rel, G, adj_factor)

func _apply_trail_width(tr: Node, S: Dictionary) -> void:
	if tr == null or not tr.is_inside_tree():
		return
	if not tr.has_method("get"):
		return

	# Trails usually expose their Line2D via a "line" property.
	var line_obj = tr.get("line")
	if line_obj == null or not (line_obj is Line2D):
		return

	var line := line_obj as Line2D

	# Cache the base width once so we always scale from original.
	if not tr.has_meta("_vfx_trail_base_width"):
		tr.set_meta("_vfx_trail_base_width", line.width)

	var base_width: float = float(tr.get_meta("_vfx_trail_base_width"))
	if base_width <= 0.0:
		return

	# Scale comes from the TARGET scale channel.
	var target_scale: float = 1.0
	if S.has("target"):
		target_scale = float(S["target"])

	var clamped_scale: float = clamp(target_scale, 0.6, 1.6)
	var new_width: float = base_width * clamped_scale

	if abs(line.width - new_width) > 0.01:
		line.width = new_width



func _update_trail_drawers(t_ms: int) -> void:
	if anim_bank == null:
		return
	if _trail_drawers.is_empty():
		return

	for d in _trail_drawers:
		if d == null or not d.is_inside_tree():
			continue

		var nd = null
		if d.has_method("get"):
			nd = d.get("note_data")

		# Same adjacency logic as other parts
		var adj_factor := _get_adj_factor(nd)

		var key: String = _get_effective_key_for_drawer(d)
		if key == "":
			continue

		var parts: Dictionary = _drawer_parts.get(d, {})
		if parts.is_empty():
			parts = _parts_for_drawer(d)
			_init_part_state(parts)
			_drawer_parts[d] = parts

		var samples := _sample_all_for_key_cached(key, t_ms)
		if samples.is_empty():
			continue

		var S: Dictionary = samples["S"]
		var C: Dictionary = samples["C"]
		var R: Dictionary = samples["R"]
		var O: Dictionary = samples["O"]
		var G: Dictionary = samples["G"]


		# Move whole drawer (trail) with the target offset / rotation
		_apply_drawer_field_transform(d, R, O, false)

		var O_rel := {
			"head":   O.head - O.target,
			"tail":   O.tail - O.target,
			"target": Vector2.ZERO,
			"hold":   O.hold - O.target,
			"bar1":   O.bar1 - O.target,
			"bar2":   O.bar2 - O.target,
		}

		_apply_parts_all(parts, S, C, R, O_rel, G, adj_factor)
		_apply_trail_width(d, S)




# ─────────────────────────────────────────────
# Drawer parts (head / tail / target / hold)
# ─────────────────────────────────────────────

func _parts_for_drawer(d: Node) -> Dictionary:
	var out: Dictionary = {}

	out["head"] = d.get_node_or_null("Note") as CanvasItem
	out["tail"] = d.get_node_or_null("Note2") as CanvasItem

	var target_ci: CanvasItem = null
	var nt_root := d.get_node_or_null("NoteTarget")
	if nt_root != null:
		var sp := nt_root.get_node_or_null("Sprite2D") as CanvasItem
		if sp != null:
			target_ci = sp
		else:
			for c in nt_root.get_children():
				if c is CanvasItem:
					target_ci = c
					break

	out["target"] = target_ci if target_ci != null else (nt_root as CanvasItem)
	out["target_root"] = nt_root

	var hold_nodes: Array = []
	_collect_named(d, "HoldTextSprite", hold_nodes)
	out["hold_nodes"] = hold_nodes

	return out


func _collect_named(root: Node, exact: String, out: Array) -> void:
	if root == null:
		return
	if String(root.name) == exact:
		out.append(root)
	for c in root.get_children():
		if c is Node:
			_collect_named(c, exact, out)


func _init_part_state(p: Dictionary) -> void:
	if p.has("_lastS"):
		return
	p["_lastS"] = {
		"h": -1.0, "t": -1.0, "tg": -1.0,
		"b1": -1.0, "b2": -1.0, "ho": -1.0,
	}
	p["_lastC"] = {
		"h": Color(9,9,9,0), "t": Color(9,9,9,0), "tg": Color(9,9,9,0),
		"b1": Color(9,9,9,0), "b2": Color(9,9,9,0),
		"ho": Color(9,9,9,0),
	}
	p["_lastR"] = {
		"h": -9999.0, "t": -9999.0,
		"tg": -9999.0, "ho": -9999.0,
	}
	p["_lastO"] = {
		"h":  Vector2(999999, 999999),
		"t":  Vector2(999999, 999999),
		"tg": Vector2(999999, 999999),
		"ho": Vector2(999999, 999999),
		"b1": Vector2(999999, 999999),
		"b2": Vector2(999999, 999999),
	}
	p["_lastG"] = {
		"h": -9999.0, "t": -9999.0, "tg": -9999.0,
		"b1": -9999.0, "b2": -9999.0, "ho": -9999.0,
	}



# ─────────────────────────────────────────────
# Drawer root transform (offset/rot)
# ─────────────────────────────────────────────

func _apply_drawer_field_transform(root: Node, R: Dictionary, O: Dictionary, use_rotation: bool = true) -> void:
	if root == null or not (root is Node2D):
		return
	var n2d := root as Node2D

	if not n2d.has_meta("_vfx_base_pos"):
		n2d.set_meta("_vfx_base_pos", n2d.position)
	if not n2d.has_meta("_vfx_base_rot"):
		n2d.set_meta("_vfx_base_rot", n2d.rotation_degrees)
	if not n2d.has_meta("_vfx_last_ofs"):
		n2d.set_meta("_vfx_last_ofs", Vector2.ZERO)
	if not n2d.has_meta("_vfx_last_rot"):
		n2d.set_meta("_vfx_last_rot", 0.0)

	var base_pos: Vector2 = n2d.get_meta("_vfx_base_pos")
	var base_rot: float = n2d.get_meta("_vfx_base_rot")

	var target_ofs: Vector2 = O.get("target", Vector2.ZERO)
	var target_rot: float = 0.0
	if use_rotation:
		target_rot = float(R.get("target", 0.0))

	var new_pos := base_pos + target_ofs
	var new_rot := base_rot + target_rot

	if n2d.position != new_pos:
		n2d.position = new_pos
	if abs(n2d.rotation_degrees - new_rot) > 0.001:
		n2d.rotation_degrees = new_rot

	n2d.set_meta("_vfx_last_ofs", target_ofs)
	n2d.set_meta("_vfx_last_rot", target_rot)



# ─────────────────────────────────────────────
# Parts application (scale × adj, color, rot, offset)
# ─────────────────────────────────────────────

func _apply_parts_all(
	p: Dictionary,
	S: Dictionary,
	C: Dictionary,
	R: Dictionary,
	O: Dictionary,
	G: Dictionary,
	adj_factor: float
) -> void:
	if p.is_empty():
		return

	var LS: Dictionary = p["_lastS"]
	var LC: Dictionary = p["_lastC"]
	var LR: Dictionary = p["_lastR"]
	var LO: Dictionary = p["_lastO"]
	var LG: Dictionary = p["_lastG"]

	var head: CanvasItem = p.get("head", null)
	var tail: CanvasItem = p.get("tail", null)
	var target_root: Node = p.get("target_root", null)
	var target_ci: CanvasItem = p.get("target", null)
	var hold_nodes: Array = p.get("hold_nodes", [])

	# -------- SCALE (with adjacency) --------
	var head_scale: float = float(S.head) * adj_factor
	var tail_scale: float = float(S.tail) * adj_factor
	var target_scale: float = float(S.target) * adj_factor
	var bar1_scale: float = float(S.bar1) * adj_factor
	var bar2_scale: float = float(S.bar2) * adj_factor
	var hold_scale: float = float(S.hold) * adj_factor

	if head != null and LS["h"] != head_scale:
		_set_scale(head, head_scale)
		LS["h"] = head_scale

	if tail != null and LS["t"] != tail_scale:
		_set_scale(tail, tail_scale)
		LS["t"] = tail_scale

	if target_root != null:
		for child in (target_root as Node).get_children():
			if not (child is CanvasItem):
				continue
			var ci_child := child as CanvasItem
			var cname := String(ci_child.name).to_lower()
			if cname.findn("sprite") != -1 or cname.findn("target") != -1:
				if LS["tg"] != target_scale:
					_set_scale(ci_child, target_scale)
					LS["tg"] = target_scale
			elif cname.findn("timingarm2") != -1:
				if LS["b2"] != bar2_scale:
					_set_scale(ci_child, bar2_scale)
					LS["b2"] = bar2_scale
			elif cname.findn("timingarm") != -1 or cname.findn("bar") != -1:
				if LS["b1"] != bar1_scale:
					_set_scale(ci_child, bar1_scale)
					LS["b1"] = bar1_scale

	for h in hold_nodes:
		if h is CanvasItem and LS["ho"] != hold_scale:
			_set_scale(h, hold_scale)
			LS["ho"] = hold_scale

	# -------- COLOR --------
	if head != null and LC["h"] != C.head:
		_set_color(head, C.head)
		LC["h"] = C.head

	if tail != null and LC["t"] != C.tail:
		_set_color(tail, C.tail)
		LC["t"] = C.tail

	if target_root != null:
		for child2 in (target_root as Node).get_children():
			if not (child2 is CanvasItem):
				continue
			var ci_child2 := child2 as CanvasItem
			var cname2 := String(ci_child2.name).to_lower()
			if cname2.findn("timingarm2") != -1:
				if LC["b2"] != C.bar2:
					_set_color(ci_child2, C.bar2)
					LC["b2"] = C.bar2
			elif cname2.findn("timingarm") != -1 or cname2.findn("bar") != -1:
				if LC["b1"] != C.bar1:
					_set_color(ci_child2, C.bar1)
					LC["b1"] = C.bar1
			elif cname2.findn("sprite") != -1 or cname2.findn("target") != -1:
				if LC["tg"] != C.target:
					_set_color(ci_child2, C.target)
					LC["tg"] = C.target
			else:
				if target_root is CanvasItem:
					var prev_root_col: Color = LC.get("tg_root", Color(9, 9, 9, 0))
					if prev_root_col != C.target:
						_set_color(target_root as CanvasItem, C.target)
						LC["tg_root"] = C.target

	for h2 in hold_nodes:
		if h2 is CanvasItem and LC["ho"] != C.hold:
			_set_color(h2, C.hold)
			LC["ho"] = C.hold

	# -------- ROTATION --------
	if head != null and LR["h"] != R.head:
		_set_rotation(head, R.head)
		LR["h"] = R.head

	if tail != null and LR["t"] != R.tail:
		_set_rotation(tail, R.tail)
		LR["t"] = R.tail

	if target_ci != null and LR["tg"] != R.target:
		_set_rotation(target_ci, R.target)
		LR["tg"] = R.target

	for h3 in hold_nodes:
		if h3 is CanvasItem and LR["ho"] != R.hold:
			_set_rotation(h3, R.hold)
			LR["ho"] = R.hold

	# -------- OFFSET --------
	if head != null and LO["h"] != O.head:
		_set_offset(head, O.head)
		LO["h"] = O.head

	if tail != null and LO["t"] != O.tail:
		_set_offset(tail, O.tail)
		LO["t"] = O.tail

	if target_ci != null and LO["tg"] != O.target:
		_set_offset(target_ci, O.target)
		LO["tg"] = O.target

	for h4 in hold_nodes:
		if h4 is CanvasItem and LO["ho"] != O.hold:
			_set_offset(h4, O.hold)
			LO["ho"] = O.hold

	if target_root != null:
		for child3 in (target_root as Node).get_children():
			if not (child3 is CanvasItem):
				continue
			var ci_child3 := child3 as CanvasItem
			var cname3 := String(ci_child3.name).to_lower()
			if cname3.findn("timingarm2") != -1:
				if LO["b2"] != O.bar2:
					_set_offset(ci_child3, O.bar2)
					LO["b2"] = O.bar2
			elif cname3.findn("timingarm") != -1 or cname3.findn("bar") != -1:
				if LO["b1"] != O.bar1:
					_set_offset(ci_child3, O.bar1)
					LO["b1"] = O.bar1

	# -------- GLOW (no adjacency scaling – match MegaInjector) --------
	var head_glow   : float = float(G.get("head",   0.0))
	var tail_glow   : float = float(G.get("tail",   0.0))
	var target_glow : float = float(G.get("target", 0.0))
	var bar1_glow   : float = float(G.get("bar1",   0.0))
	var bar2_glow   : float = float(G.get("bar2",   0.0))
	var hold_glow   : float = float(G.get("hold",   0.0))

	if head != null and LG["h"] != head_glow:
		_set_glow(head, head_glow)
		LG["h"] = head_glow

	if tail != null and LG["t"] != tail_glow:
		_set_glow(tail, tail_glow)
		LG["t"] = tail_glow

	if target_root != null:
		for child_g in (target_root as Node).get_children():
			if not (child_g is CanvasItem):
				continue
			var ci_child_g := child_g as CanvasItem
			var cname_g := String(ci_child_g.name).to_lower()
			if cname_g.findn("timingarm2") != -1:
				if LG["b2"] != bar2_glow:
					_set_glow(ci_child_g, bar2_glow)
					LG["b2"] = bar2_glow
			elif cname_g.findn("timingarm") != -1 or cname_g.findn("bar") != -1:
				if LG["b1"] != bar1_glow:
					_set_glow(ci_child_g, bar1_glow)
					LG["b1"] = bar1_glow
			elif cname_g.findn("sprite") != -1 or cname_g.findn("target") != -1:
				if LG["tg"] != target_glow:
					_set_glow(ci_child_g, target_glow)
					LG["tg"] = target_glow

	for h_g in hold_nodes:
		if h_g is CanvasItem and LG["ho"] != hold_glow:
			_set_glow(h_g, hold_glow)
			LG["ho"] = hold_glow

	# -------- COMMIT PACKED TRANSFORMS --------
	if head != null:
		_commit_transform(head)
	if tail != null:
		_commit_transform(tail)
	if target_ci != null:
		_commit_transform(target_ci)

	for h6 in hold_nodes:
		if h6 is CanvasItem:
			_commit_transform(h6 as CanvasItem)

	if target_root != null:
		for ch in (target_root as Node).get_children():
			if ch is CanvasItem:
				_commit_transform(ch as CanvasItem)




# ─────────────────────────────────────────────
# Adjacency: shrink tight note clusters
# ─────────────────────────────────────────────

func _mark_adjacent_notes(points: Array) -> void:
	# Map time -> Array[HBNoteData]
	var time_to_notes := {}

	for p in points:
		if p is HBNoteData:
			var nd := p as HBNoteData
			var t := nd.time

			if not time_to_notes.has(t):
				time_to_notes[t] = []

			time_to_notes[t].append(nd)

			# Clear any previous adjacency factor just in case
			if (nd as Object).has_method("has_meta") and nd.has_meta("phvfx_adj_factor"):
				nd.set_meta("phvfx_adj_factor", 1.0)

	# Build a "heads" list, but ONLY for times that are true singles (no chords)
	var heads: Array = []

	for t in time_to_notes.keys():
		var arr: Array = time_to_notes[t]
		if arr.size() == 1:
			heads.append({
				"note": arr[0],
				"time": t
			})

	# If we have fewer than 2 single notes, nothing to do
	if heads.size() < 2:
		return

	# Sort by time (ascending)
	heads.sort_custom(func(a, b):
		return int(a["time"]) < int(b["time"])
	)

	var threshold := 90  # ms
	var current_group: Array = []
	var last_time = null

	for i in range(heads.size()):
		var h = heads[i]
		var t := int(h["time"])

		if last_time == null:
			current_group.clear()
			current_group.append(h)
		else:
			if abs(t - last_time) <= threshold:
				current_group.append(h)
			else:
				_apply_adjacent_group(current_group)
				current_group.clear()
				current_group.append(h)

		last_time = t

	# Flush final group
	_apply_adjacent_group(current_group)



func _apply_adjacent_group(group: Array) -> void:
	if group.size() <= 1:
		return

	var factor := 0.9
	if group.size() >= 3:
		factor = 0.85

	for h in group:
		var nd = h["note"]
		if nd != null and (nd as Object).has_method("set_meta"):
			(nd as Object).set_meta("phvfx_adj_factor", factor)


func _get_adj_factor(nd) -> float:
	if nd == null:
		return 1.0
	var obj := nd as Object
	if obj.has_method("has_meta") and obj.has_meta("phvfx_adj_factor"):
		var v = obj.get_meta("phvfx_adj_factor")
		if v != null:
			return float(v)
	return 1.0



# ─────────────────────────────────────────────
# Chart hook
# ─────────────────────────────────────────────

func _preprocess_timing_points(points: Array) -> Array:
	# New chart incoming – reset runtime caches
	_bank_loaded = false
	anim_bank.clear()
	_current_vfx_path = ""
	_key_remap.clear()
	_drawer_parts.clear()
	_drawer_key.clear()
	_slide_chain_drawers.clear()
	_extra_cached = false
	_spot_drawers.clear()

	# Playfield slides
	_pf_rows_loaded = false
	_pf_rows.clear()
	_pf_chain.clear()
	_pf_wrapper = null
	_pf_baseline_pos = Vector2.ZERO
	
	# NEW: playfield rotation
	_pf_rot_rows.clear()
	_pf_rot_chain.clear()
	_pf_game_layer = null

	# NEW: playfield scale
	_pf_scale_rows.clear()
	_pf_baseline_scale = 1.0
	_pf_baseline_gl_scale = 1.0
	_pf_last_gl_scale = 1.0




	# Mirai lines (runtime)
	if _mirai_line_root != null and is_instance_valid(_mirai_line_root):
		_mirai_line_root.queue_free()
	_mirai_rows_loaded = false
	_mirai_links.clear()
	_mirai_line_root = null

	# <<< NEW: reset runtime time tracking >>>
	_rt_last_chart_ms = -1.0
	_rt_last_wall_ms = -1

	_mark_adjacent_notes(points)
	return points
