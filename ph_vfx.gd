extends HBEditorModule
class_name FieldSlidesModule

const ENTRY_TAG := "$PLAYFIELD"
const ROTATE_TAG := "$PF_ROTATE_SEL"
const USE_ABSOLUTE_CHAIN := true
const PF_SCALE_TAG := "$PF_SCALE_SEL"


const EPS := 0.0005

const DEFAULT_TARGETS := [
	"LAYER_Notes",
	"LAYER_Notes2",
	"LAYER_SlideChainPieces",
	"LAYER_SlideChainPieces2",
	"LAYER_Trails",
	"LAYER_HitParticles",
	"LAYER_StarParticles",
	"LAYER_AppearParticles"
]

const EASE_OPTIONS := [
	"linear",
	"quad_in",
	"quad_out",
	"quad_in_out",
	"cubic_in_out"
]

const FIELD_PIVOT_GL := Vector2(960.0, 540.0) # GameLayer-local pivot for scale/rotation

const MANAGER_NAME  := "PH_PlayfieldSlides_UNIFIED"
const WRAPPER_NAME  := "PH_PlayfieldWrapper_ALL"
const GAMELAYER_NAME := "GameLayer"

const LATENCY_BIAS_MS := 0.0
const SHINOBU_REL_PATH := "Node/ShinobuSoundPlayer"
const PREVIEW_ROTATES_ORIENTATION := true

const ICON_SIZE_PX := 64   # icon size in pixels (feel free to tweak)
const CARD_SIZE_PX := 112  # HBEditorButton "card" min size (square)


# ───────────────────────────────────────────────────────────────
# UI state + icons
# ───────────────────────────────────────────────────────────────

var ICON_SAVE_SLIDE   : Texture2D = null
var ICON_RESET_UI     : Texture2D = null
var ICON_SAVE_ROT     : Texture2D = null
var ICON_INJECT       : Texture2D = null
var ICON_UNINJECT     : Texture2D = null
var ICON_CALIBRATE    : Texture2D = null
var ICON_SAVE_SCALE   : Texture2D = null   # NEW
var ICON_CLEAR_FIELDS : Texture2D = null   # NEW (optional)

var in_start  : LineEdit
var in_end    : LineEdit
var in_sx     : LineEdit
var in_sy     : LineEdit
var in_ex     : LineEdit
var in_ey     : LineEdit
var ob_ease   : OptionButton

# Rotation inputs
var in_rot_start  : LineEdit
var in_rot_end    : LineEdit
var in_rot_a0     : LineEdit
var in_rot_a1     : LineEdit
var in_rot_pvx    : LineEdit
var in_rot_pvy    : LineEdit
var ob_rot_ease   : OptionButton

# Scale inputs (new)
var in_scale_start  : LineEdit
var in_scale_end    : LineEdit
var in_scale_s0     : LineEdit
var in_scale_s1     : LineEdit
var ob_scale_ease   : OptionButton



# ───────────────────────────────────────────────────────────────
# Lifecycle / UI
# ───────────────────────────────────────────────────────────────

func _ready() -> void:
	super._ready()
	_build_ui()


func _build_ui() -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.anchor_left = 0.0
	scroll.anchor_top = 0.0
	scroll.anchor_right = 1.0
	scroll.anchor_bottom = 1.0
	add_child(scroll)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	scroll.add_child(margin)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(root)

	# Make sure textures exist before we create the cards
	_ensure_icons_loaded()

	# ── SLIDE SEGMENTS ──────────────────────────────────────────
	root.add_child(_mk_section_label("Playfield Slides – $PLAYFIELD segments"))

	var desc := _mk_label("Saves slide segments (start/end, endpoints, ease). Blank Start X/Y chains from previous endpoint.")
	root.add_child(desc)

	var grid_t := GridContainer.new()
	grid_t.columns = 2
	root.add_child(grid_t)

	var cur_t: float = _current_playhead()

	grid_t.add_child(_mk_label("Start time (s, optional; blank = playhead):"))
	in_start = LineEdit.new()
	in_start.placeholder_text = "e.g. 12.000 (blank = playhead)"
	in_start.text = _fmt(cur_t)
	grid_t.add_child(in_start)

	grid_t.add_child(_mk_label("End time (s, required):"))
	in_end = LineEdit.new()
	in_end.placeholder_text = "e.g. 15.000"
	grid_t.add_child(in_end)

	grid_t.add_child(_mk_label("Start X (optional):"))
	in_sx = LineEdit.new()
	in_sx.placeholder_text = "(blank = chain from previous)"
	grid_t.add_child(in_sx)

	grid_t.add_child(_mk_label("Start Y (optional):"))
	in_sy = LineEdit.new()
	in_sy.placeholder_text = "(blank = chain from previous)"
	grid_t.add_child(in_sy)

	grid_t.add_child(_mk_label("End X (required):"))
	in_ex = LineEdit.new()
	in_ex.placeholder_text = "e.g. 40"
	grid_t.add_child(in_ex)

	grid_t.add_child(_mk_label("End Y (required, negative = UP):"))
	in_ey = LineEdit.new()
	in_ey.placeholder_text = "e.g. 18"
	grid_t.add_child(in_ey)

	grid_t.add_child(_mk_label("Ease:"))
	ob_ease = OptionButton.new()
	for i in range(EASE_OPTIONS.size()):
		ob_ease.add_item(EASE_OPTIONS[i], i)
	ob_ease.select(0) # linear
	grid_t.add_child(ob_ease)

	# --- Save / Reset buttons row (2 big cards) -----------------
	var row_btns := HBoxContainer.new()
	row_btns.alignment = BoxContainer.ALIGNMENT_CENTER
	row_btns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_btns.add_theme_constant_override("separation", 24)
	_configure_button_row(row_btns)
	root.add_child(row_btns)

	_add_big_icon_button(
		row_btns,
		"Calibrate",
		"Writes a 0→10 ms $PLAYFIELD segment at (0,0) so future slides can reliably return to the true origin.",
		"_on_calibrate_origin",
		ICON_CALIBRATE
	)

	_add_big_icon_button(
		row_btns,
		"Save Slide",
		"Saves/merges a $PLAYFIELD slide row in row-style JSON and refreshes the injector.",
		"_on_save_slide_segment",
		ICON_SAVE_SLIDE
	)

	_add_big_icon_button(
		row_btns,
		"Reset UI",
		"Reset Field slide inputs to defaults (playhead start, linear, blank coords/targets).",
		"_on_reset_ui",
		ICON_RESET_UI
	)

	# ── SCALE SEGMENTS ───────────────────────────────────────────
	root.add_child(_mk_section_label("Playfield Scale – $PF_SCALE_SEL segments"))

	var desc_scale := _mk_label("Saves scale segments (start/end time, start/end multipliers, ease, targets). Scaling is uniform and authored as a multiplier of the baseline field size.")
	root.add_child(desc_scale)

	var grid_s := GridContainer.new()
	grid_s.columns = 2
	root.add_child(grid_s)

	cur_t = _current_playhead()

	grid_s.add_child(_mk_label("Start time (s, optional; blank = playhead):"))
	in_scale_start = LineEdit.new()
	in_scale_start.placeholder_text = "e.g. 12.000 (blank = playhead)"
	in_scale_start.text = _fmt(cur_t)
	grid_s.add_child(in_scale_start)

	grid_s.add_child(_mk_label("End time (s, required):"))
	in_scale_end = LineEdit.new()
	in_scale_end.placeholder_text = "e.g. 15.000"
	grid_s.add_child(in_scale_end)

	grid_s.add_child(_mk_label("Start scale (multiplier, required):"))
	in_scale_s0 = LineEdit.new()
	in_scale_s0.placeholder_text = "e.g. 1.0"
	grid_s.add_child(in_scale_s0)

	grid_s.add_child(_mk_label("End scale (multiplier, required):"))
	in_scale_s1 = LineEdit.new()
	in_scale_s1.placeholder_text = "e.g. 1.10  (10% zoom in)"
	grid_s.add_child(in_scale_s1)

	grid_s.add_child(_mk_label("Ease:"))
	ob_scale_ease = OptionButton.new()
	for i in range(EASE_OPTIONS.size()):
		ob_scale_ease.add_item(EASE_OPTIONS[i], i)
	ob_scale_ease.select(0) # linear
	grid_s.add_child(ob_scale_ease)



	# Save Scale row – single centered card
	var row_scale := HBoxContainer.new()
	row_scale.alignment = BoxContainer.ALIGNMENT_CENTER
	row_scale.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_scale.add_theme_constant_override("separation", 24)
	_configure_button_row(row_scale)
	root.add_child(row_scale)

	_add_big_icon_button(
		row_scale,
		"Save Scale",
		"Saves/merges a $PF_SCALE_SEL scale row in row-style JSON and refreshes the manager.",
		"_on_save_scale_segment",
		ICON_SAVE_SCALE,
		160
	)


	# ── ROTATION SEGMENTS ───────────────────────────────────────
	root.add_child(_mk_section_label("Playfield Rotation – $PF_ROTATE_SEL segments"))

	var desc_rot := _mk_label("Saves rotation segments (start/end, angles, pivot, ease, targets). Pivot is authored in GameLayer-local space.")
	root.add_child(desc_rot)

	var grid_r := GridContainer.new()
	grid_r.columns = 2
	root.add_child(grid_r)

	cur_t = _current_playhead()

	grid_r.add_child(_mk_label("Start time (s, optional; blank = playhead):"))
	in_rot_start = LineEdit.new()
	in_rot_start.placeholder_text = "e.g. 12.000 (blank = playhead)"
	in_rot_start.text = _fmt(cur_t)
	grid_r.add_child(in_rot_start)

	grid_r.add_child(_mk_label("End time (s, required):"))
	in_rot_end = LineEdit.new()
	in_rot_end.placeholder_text = "e.g. 15.000"
	grid_r.add_child(in_rot_end)

	grid_r.add_child(_mk_label("Start angle ° (required):"))
	in_rot_a0 = LineEdit.new()
	in_rot_a0.placeholder_text = "e.g. 0"
	grid_r.add_child(in_rot_a0)

	grid_r.add_child(_mk_label("End angle ° (required):"))
	in_rot_a1 = LineEdit.new()
	in_rot_a1.placeholder_text = "e.g. 45"
	grid_r.add_child(in_rot_a1)

	grid_r.add_child(_mk_label("Pivot X (GameLayer-local, required):"))
	in_rot_pvx = LineEdit.new()
	in_rot_pvx.placeholder_text = "e.g. 960"
	grid_r.add_child(in_rot_pvx)

	grid_r.add_child(_mk_label("Pivot Y (GameLayer-local, required):"))
	in_rot_pvy = LineEdit.new()
	in_rot_pvy.placeholder_text = "e.g. 540"
	grid_r.add_child(in_rot_pvy)

	grid_r.add_child(_mk_label("Ease:"))
	ob_rot_ease = OptionButton.new()
	for i in range(EASE_OPTIONS.size()):
		ob_rot_ease.add_item(EASE_OPTIONS[i], i)
	ob_rot_ease.select(0)
	grid_r.add_child(ob_rot_ease)

	# Save Rotation row – single centered card
	var row_rot := HBoxContainer.new()
	row_rot.alignment = BoxContainer.ALIGNMENT_CENTER
	row_rot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_rot.add_theme_constant_override("separation", 24)
	_configure_button_row(row_rot)
	root.add_child(row_rot)

	_add_big_icon_button(
		row_rot,
		"Save Rotation",
		"Saves/merges a $PF_ROTATE_SEL rotation row in row-style JSON and refreshes the injector.",
		"_on_save_rotation_segment",
		ICON_SAVE_ROT,
		160   # <-- only Save Rotation gets a 160×160 card
	)


	# ── INJECT / UNINJECT / SNAP ────────────────────────────────
	root.add_child(_mk_section_label("Field Animations – inject / uninject"))

	var row_actions := HBoxContainer.new()
	row_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	row_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_actions.add_theme_constant_override("separation", 24)
	_configure_button_row(row_actions)
	root.add_child(row_actions)

	_add_big_icon_button(
		row_actions,
		"Inject",
		"Creates/updates PH_PlayfieldSlides_UNIFIED and arms preview+playtest slides.",
		"_on_inject_field_anims",
		ICON_INJECT
	)

	_add_big_icon_button(
		row_actions,
		"Uninject",
		"Restores preview positions from manager baselines, removes managers, and unwraps PH_PlayfieldWrapper_ALL.",
		"_on_uninject_field_anims",
		ICON_UNINJECT
	)

	_add_big_icon_button(
		row_actions,
		"Erase Field Animations",
		"Deletes all $PLAYFIELD / $PF_ROTATE_SEL / $PF_SCALE_SEL rows from the VFX JSON (note VFX rows are left untouched).",
		"_on_clear_field_anims",
		ICON_CLEAR_FIELDS  # or ICON_RESET_UI if you don't want a new icon
	)

	# Footer
	var foot := HBoxContainer.new()
	root.add_child(foot)
	foot.add_child(_mk_label("Slides use authored times (usually seconds); manager normalizes to ms if needed."))
	foot.add_child(_mk_spacer())


# ───────────────────────────────────────────────────────────────
# Button entry points
# ───────────────────────────────────────────────────────────────

func _configure_button_row(row: HBoxContainer) -> void:
	if row == null:
		return
	# Tall enough for a 128×128 card + text
	row.custom_minimum_size = Vector2(0, 160)
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# caller decides separation; don’t override it here

func _on_save_scale_segment() -> void:
	if editor == null:
		_notify("❌ Editor not found.")
		return

	var cur_t := _current_playhead()
	var t0 := _parse_f(in_scale_start.text, cur_t)
	var t1 := _parse_f(in_scale_end.text, -1.0)
	if t1 < 0.0 or t1 <= t0:
		_notify("⚠️ End time must be > start time.")
		return

	if not _is_num(in_scale_s0.text) or not _is_num(in_scale_s1.text):
		_notify("⚠️ Start/End scale multipliers are required.")
		return

	var s0 := float(in_scale_s0.text.strip_edges())
	var s1 := float(in_scale_s1.text.strip_edges())

	# Always use the default field layers for scale
	var targets: Array = []
	for n in DEFAULT_TARGETS:
		targets.append(n)

	var ease_name: String = EASE_OPTIONS[ob_scale_ease.get_selected_id()]


	var row := {
		"layer": PF_SCALE_TAG,
		"pf_scale_start_time": t0,
		"pf_scale_end_time": t1,
		"pf_scale_start_mult": s0,
		"pf_scale_end_mult": s1,
		"pf_scale_ease": ease_name,
		"pf_scale_targets": targets,
	}

	var rows := _load_rows()
	_merge_scale_row_rowstyle(rows, row)
	_notify("🔍 Scale segment saved.")
	_refresh_slide_manager()


func _on_calibrate_origin() -> void:
	if editor == null:
		_notify("❌ Editor not found.")
		return

	# Load existing rows so we can merge/replace if a calibration row already exists
	var rows := _load_rows()

	# Use the default target set so the calibration applies to the normal field layers
	var calib_targets: Array = []
	for n in DEFAULT_TARGETS:
		calib_targets.append(n)

	# Author in seconds: 0.00 → 0.01 s.
	# PlayfieldSlidesManager will normalize to ms (0 → 10 ms) when it detects "seconds-style" data.
	var calib_row := {
		"layer": ENTRY_TAG,
		"pf_slide_start_time": 0.0,
		"pf_slide_end_time": 0.01,      # 10 ms after normalization
		"pf_slide_startpoint": [0.0, 0.0],
		"pf_slide_endpoint":   [0.0, 0.0],
		"pf_slide_ease": "linear",
		"pf_slide_targets": calib_targets
	}

	# Merge using the same logic as Save Slide (same time span + same targets → replace)
	_merge_row_rowstyle(rows, calib_row)

	# Make sure the manager sees the change immediately
	_refresh_slide_manager()

	_notify("📐 Field calibrated: wrote 0→10 ms (0,0) $PLAYFIELD segment.")


func _on_save_slide_segment() -> void:
	if editor == null:
		_notify("❌ Editor not found.")
		return

	var cur_t := _current_playhead()
	var t0 := _parse_f(in_start.text, cur_t)
	var t1 := _parse_f(in_end.text, -1.0)
	if t1 < 0.0 or t1 <= t0:
		_notify("⚠️ End time must be > start time.")
		return

	if not _is_num(in_ex.text) or not _is_num(in_ey.text):
		_notify("⚠️ End X/Y are required.")
		return

	# Always use the default field layers for slides
	var targets: Array = []
	for n in DEFAULT_TARGETS:
		targets.append(n)

	var end_x := float(in_ex.text.strip_edges())
	var end_y := float(in_ey.text.strip_edges())


	var use_explicit_start := _is_num(in_sx.text) and _is_num(in_sy.text)
	var start_pt := Vector2.ZERO
	if use_explicit_start:
		start_pt = Vector2(float(in_sx.text.strip_edges()), float(in_sy.text.strip_edges()))
	else:
		var rows := _load_rows()
		start_pt = _infer_last_position(rows, t0, targets)

	var ease_name: String = EASE_OPTIONS[ob_ease.get_selected_id()]

	var row := {
		"layer": ENTRY_TAG,
		"pf_slide_start_time": t0,
		"pf_slide_end_time": t1,
		"pf_slide_startpoint": [start_pt.x, start_pt.y],
		"pf_slide_endpoint": [end_x, end_y],
		"pf_slide_ease": ease_name,
		"pf_slide_targets": targets
	}

	var rows2 := _load_rows()
	_merge_row_rowstyle(rows2, row)
	_notify("🎬 Slide segment saved.")
	_refresh_slide_manager()

func _on_save_rotation_segment() -> void:
	if editor == null:
		_notify("❌ Editor not found.")
		return

	var cur_t := _current_playhead()
	var t0 := _parse_f(in_rot_start.text, cur_t)
	var t1 := _parse_f(in_rot_end.text, -1.0)
	if t1 < 0.0 or t1 <= t0:
		_notify("⚠️ End time must be > start time.")
		return

	if not _is_num(in_rot_a0.text) or not _is_num(in_rot_a1.text):
		_notify("⚠️ Start/End angle are required.")
		return

	if not _is_num(in_rot_pvx.text) or not _is_num(in_rot_pvy.text):
		_notify("⚠️ Pivot X/Y are required (GameLayer-local).")
		return

	var a0 := float(in_rot_a0.text.strip_edges())
	var a1 := float(in_rot_a1.text.strip_edges())
	var pvx := float(in_rot_pvx.text.strip_edges())
	var pvy := float(in_rot_pvy.text.strip_edges())

	# Always use the default field layers for rotations
	var targets: Array = []
	for n in DEFAULT_TARGETS:
		targets.append(n)

	var ease_name: String = EASE_OPTIONS[ob_rot_ease.get_selected_id()]


	var row := {
		"layer": ROTATE_TAG,
		"pf_rot_start_time": t0,
		"pf_rot_end_time": t1,
		"pf_rot_angle_start_deg": a0,
		"pf_rot_angle_end_deg": a1,
		"pf_rot_ease": ease_name,
		"pf_rot_targets": targets,
		"pf_rot_pivot_local": [pvx, pvy]
	}

	var rows := _load_rows()
	_merge_rot_row_rowstyle(rows, row)
	_notify("🎡 Rotation segment saved.")
	_refresh_slide_manager()

func _on_reset_ui() -> void:
	var cur_t := _current_playhead()
	if in_start:
		in_start.text = _fmt(cur_t)

	if in_end:
		in_end.text = ""
	if in_sx:
		in_sx.text = ""
	if in_sy:
		in_sy.text = ""
	if in_ex:
		in_ex.text = ""
	if in_ey:
		in_ey.text = ""


	if ob_ease:
		ob_ease.select(0)

	if in_rot_start:
		in_rot_start.text = _fmt(cur_t)
	if in_rot_end:
		in_rot_end.text = ""
	if in_rot_a0:
		in_rot_a0.text = ""
	if in_rot_a1:
		in_rot_a1.text = ""
	if in_rot_pvx:
		in_rot_pvx.text = ""
	if in_rot_pvy:
		in_rot_pvy.text = ""
	if ob_rot_ease:
		ob_rot_ease.select(0)

	# Scale (new)
	if in_scale_start:
		in_scale_start.text = _fmt(cur_t)
	if in_scale_end:
		in_scale_end.text = ""
	if in_scale_s0:
		in_scale_s0.text = ""
	if in_scale_s1:
		in_scale_s1.text = ""
	if ob_scale_ease:
		ob_scale_ease.select(0)

	_notify("↩️ Field slide UI reset to defaults.")

func _on_inject_field_anims() -> void:
	if editor == null:
		_notify("❌ Editor not found.")
		return

	var existing := editor.get_node_or_null(MANAGER_NAME)
	if existing != null and not (existing is PlayfieldSlidesManager):
		if existing.has_method("disarm"):
			existing.call("disarm")
		existing.queue_free()
		existing = null

	var mgr: PlayfieldSlidesManager = editor.get_node_or_null(MANAGER_NAME) as PlayfieldSlidesManager
	if mgr == null:
		mgr = PlayfieldSlidesManager.new()
		mgr.name = MANAGER_NAME
		editor.add_child(mgr)

	mgr.configure(editor, _resolve_vfx_path())
	mgr.arm()

	_notify("✅ Field animations injected (preview + playtest).")

func _on_uninject_field_anims() -> void:
	if editor == null:
		_notify("❌ Editor not found.")
		return

	var mgrs := _find_all_nodes_named(editor, MANAGER_NAME)
	var restored := 0
	for m in mgrs:
		restored += _restore_preview_from_manager(m)

	var removed_mgrs := _remove_nodes(mgrs)
	var unwrapped := _unwrap_all_wrappers_exact()

	var msg := "Restored:%d  Removed managers:%d  Unwrapped:%d" % [restored, removed_mgrs, unwrapped]
	_notify("🧹 Field animations uninject complete. " + msg)

func _on_clear_field_anims() -> void:
	if editor == null:
		_notify("❌ Editor not found.")
		return

	var path := _resolve_vfx_path()
	if path == "":
		_notify("⚠️ No VFX JSON path resolved.")
		return

	if not FileAccess.file_exists(path):
		_notify("ℹ️ No VFX JSON found to clear.")
		return

	var rows := _load_rows()
	if rows.is_empty():
		_notify("ℹ️ VFX JSON is empty; nothing to clear.")
		return

	var out: Array = []
	var removed := 0

	for e_v in rows:
		if typeof(e_v) != TYPE_DICTIONARY:
			out.append(e_v)
			continue

		var e: Dictionary = e_v
		var layer_name := String(e.get("layer", ""))

		# Only strip Field-related rows; do NOT touch note VFX, SPOT, MIRAI, etc.
		if layer_name == ENTRY_TAG or layer_name == ROTATE_TAG or layer_name == PF_SCALE_TAG:
			removed += 1
			continue

		out.append(e)

	if removed == 0:
		_notify("ℹ️ No $PLAYFIELD / $PF_ROTATE_SEL / $PF_SCALE_SEL rows found to clear.")
		return

	_write_rows(path, out)
	_refresh_slide_manager()

	_notify("🧹 Cleared %d Field animation rows (slides, rotations, scale). Note VFX rows left intact." % removed)


# ───────────────────────────────────────────────────────────────
# VFX JSON helpers
# ───────────────────────────────────────────────────────────────

func _resolve_vfx_path() -> String:
	if editor == null:
		return ""

	var inj := editor.get_node_or_null("PH_VFX_MegaInjector")
	if inj == null:
		inj = editor.find_child("PH_VFX_MegaInjector", true, false)

	if inj != null and inj.has_method("get"):
		var jp = inj.get("json_path")
		if typeof(jp) == TYPE_STRING and jp != "":
			return String(jp)

	if editor.current_song and editor.current_difficulty:
		var sid := str(editor.current_song.id)
		var diff := str(editor.current_difficulty).replace(" ", "_")
		return "user://editor_songs/%s/%s_vfx.json" % [sid, diff]

	return "user://note_vfx.json"

func _load_rows() -> Array:
	var path := _resolve_vfx_path()
	if not FileAccess.file_exists(path):
		return []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var parsed := JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if typeof(parsed) == TYPE_ARRAY else []

func _row_end_time(e: Dictionary) -> float:
	if e.has("pf_slide_end_time"):
		return _as_f(e["pf_slide_end_time"])
	if e.has("pf_rot_end_time"):
		return _as_f(e["pf_rot_end_time"])
	if e.has("pf_scale_end_time"):
		return _as_f(e["pf_scale_end_time"])
	return 0.0

func _row_start_time(e: Dictionary) -> float:
	if e.has("pf_slide_start_time"):
		return _as_f(e["pf_slide_start_time"])
	if e.has("pf_rot_start_time"):
		return _as_f(e["pf_rot_start_time"])
	if e.has("pf_scale_start_time"):
		return _as_f(e["pf_scale_start_time"])
	return 0.0


func _write_rows(path: String, rows: Array) -> void:
	rows.sort_custom(func(a, b):
		var da: Dictionary = a
		var db: Dictionary = b
		var ea := _row_end_time(da)
		var eb := _row_end_time(db)
		if not _feq(ea, eb):
			return ea < eb
		return _row_start_time(da) < _row_start_time(db)
	)

	var lines := PackedStringArray()
	for e2 in rows:
		lines.append(JSON.stringify(e2))
	var content := "[\n  " + "\n,  ".join(lines) + "\n]\n"

	var f2 := FileAccess.open(path, FileAccess.WRITE)
	if f2:
		f2.store_string(content)
		f2.close()
		print("[FieldSlides] ✅ Merged write: %d rows → %s" % [rows.size(), path])
	else:
		printerr("[FieldSlides] ❌ Failed to write: ", path)

func _merge_row_rowstyle(existing: Array, new_row: Dictionary) -> void:
	var path := _resolve_vfx_path()
	var sig_new := _targets_signature(new_row.get("pf_slide_targets", []))
	var t0_new := _as_f(new_row.get("pf_slide_start_time", 0.0))
	var t1_new := _as_f(new_row.get("pf_slide_end_time", 0.0))

	var out: Array = []
	var replaced := false

	for e_v in existing:
		if typeof(e_v) != TYPE_DICTIONARY:
			out.append(e_v)
			continue

		var e: Dictionary = e_v
		var is_slide := String(e.get("layer", "")) == ENTRY_TAG

		if is_slide:
			var s0 := _as_f(e.get("pf_slide_start_time", -1.0))
			var s1 := _as_f(e.get("pf_slide_end_time", -1.0))
			var sig_old := _targets_signature(e.get("pf_slide_targets", []))

			if _feq(s0, t0_new) and _feq(s1, t1_new) and sig_old == sig_new and not replaced:
				out.append(new_row)
				replaced = true
				continue

		out.append(e)

	if not replaced:
		out.append(new_row)

	_write_rows(path, out)

func _merge_rot_row_rowstyle(existing: Array, new_row: Dictionary) -> void:
	var path := _resolve_vfx_path()
	var sig_new := _targets_signature(new_row.get("pf_rot_targets", []))
	var t0_new := _as_f(new_row.get("pf_rot_start_time", 0.0))
	var t1_new := _as_f(new_row.get("pf_rot_end_time", 0.0))

	var out: Array = []
	var replaced := false

	for e_v in existing:
		if typeof(e_v) != TYPE_DICTIONARY:
			out.append(e_v)
			continue

		var e: Dictionary = e_v
		var is_rot := String(e.get("layer", "")) == ROTATE_TAG

		if is_rot:
			var s0 := _as_f(e.get("pf_rot_start_time", -1.0))
			var s1 := _as_f(e.get("pf_rot_end_time", -1.0))
			var sig_old := _targets_signature(e.get("pf_rot_targets", []))

			if _feq(s0, t0_new) and _feq(s1, t1_new) and sig_old == sig_new and not replaced:
				out.append(new_row)
				replaced = true
				continue

		out.append(e)

	if not replaced:
		out.append(new_row)

	_write_rows(path, out)

func _merge_scale_row_rowstyle(existing: Array, new_row: Dictionary) -> void:
	var path := _resolve_vfx_path()
	var sig_new := _targets_signature(new_row.get("pf_scale_targets", []))
	var t0_new := _as_f(new_row.get("pf_scale_start_time", 0.0))
	var t1_new := _as_f(new_row.get("pf_scale_end_time", 0.0))

	var out: Array = []
	var replaced := false

	for e_v in existing:
		if typeof(e_v) != TYPE_DICTIONARY:
			out.append(e_v)
			continue

		var e: Dictionary = e_v
		var is_scale := String(e.get("layer", "")) == PF_SCALE_TAG

		if is_scale:
			var s0 := _as_f(e.get("pf_scale_start_time", -1.0))
			var s1 := _as_f(e.get("pf_scale_end_time", -1.0))
			var sig_old := _targets_signature(e.get("pf_scale_targets", []))

			if _feq(s0, t0_new) and _feq(s1, t1_new) and sig_old == sig_new and not replaced:
				out.append(new_row)
				replaced = true
				continue

		out.append(e)

	if not replaced:
		out.append(new_row)

	_write_rows(path, out)


func _infer_last_position(rows: Array, t0: float, targets: Array) -> Vector2:
	var sig := _targets_signature(targets)
	var best_end := -INF
	var best_pos := Vector2.ZERO

	for e_v in rows:
		if typeof(e_v) != TYPE_DICTIONARY:
			continue
		var e: Dictionary = e_v
		if String(e.get("layer", "")) != ENTRY_TAG:
			continue
		var sig_e := _targets_signature(e.get("pf_slide_targets", []))
		if sig_e != sig:
			continue

		var end_t := _as_f(e.get("pf_slide_end_time", -INF))
		if end_t <= t0 + EPS and end_t > best_end:
			best_end = end_t
			if e.has("pf_slide_endpoint") and typeof(e["pf_slide_endpoint"]) == TYPE_ARRAY:
				var a: Array = e["pf_slide_endpoint"]
				if a.size() >= 2:
					best_pos = Vector2(float(a[0]), float(a[1]))
			elif e.has("pf_slide_startpoint") and typeof(e["pf_slide_startpoint"]) == TYPE_ARRAY:
				var s: Array = e["pf_slide_startpoint"]
				if s.size() >= 2:
					best_pos = Vector2(float(s[0]), float(s[1]))
	return best_pos


# ───────────────────────────────────────────────────────────────
# Uninject / snap helpers
# ───────────────────────────────────────────────────────────────

func _restore_preview_from_manager(mgr: Node) -> int:
	if mgr == null:
		return 0

	# NEW: ask the manager to restore its own baselines first.
	# This covers:
	#  - Preview GameLayer pos/scale (via _baseline_pos_preview_gl / _baseline_scale_preview_gl)
	#  - Preview target nodes' pos/rot/scale
	if mgr.has_method("_restore_preview_to_baseline"):
		mgr.call("_restore_preview_to_baseline")

	# NEW: also reset playtest wrapper + GameLayer to their baselines
	# before we unwrap PH_PlayfieldWrapper_ALL.
	if mgr.has_method("_restore_playtest_wrapper_to_baseline"):
		mgr.call("_restore_playtest_wrapper_to_baseline")

	# Backwards-compatible per-node restore (older managers, or if helper
	# methods ever go missing). This also keeps your "restored" count.
	var baseline_pos_any   := _safe_get(mgr, "baseline_pos")
	var baseline_rot_any   := _safe_get(mgr, "baseline_rot")
	var baseline_scale_any := _safe_get(mgr, "baseline_scale")
	var targets_any        := _safe_get(mgr, "target_nodes")

	if typeof(targets_any) != TYPE_DICTIONARY:
		return 0

	var targets        : Dictionary = targets_any
	var baseline_pos   : Dictionary = (baseline_pos_any   if typeof(baseline_pos_any)   == TYPE_DICTIONARY else {})
	var baseline_rot   : Dictionary = (baseline_rot_any   if typeof(baseline_rot_any)   == TYPE_DICTIONARY else {})
	var baseline_scale : Dictionary = (baseline_scale_any if typeof(baseline_scale_any) == TYPE_DICTIONARY else {})

	var restored := 0

	for k in targets.keys():
		var key := String(k)
		var node_any = targets[key]
		if not (node_any is CanvasItem):
			continue

		var ci := node_any as CanvasItem

		# Position
		if baseline_pos.has(key) and typeof(baseline_pos[key]) == TYPE_VECTOR2:
			ci.position = baseline_pos[key]
			restored += 1

		# Rotation (for rotation preview)
		if baseline_rot.has(key):
			ci.rotation_degrees = float(baseline_rot[key])

		# Scale (for any per-layer scale the manager might drive)
		if baseline_scale.has(key) and typeof(baseline_scale[key]) == TYPE_VECTOR2:
			ci.scale = baseline_scale[key]

	return restored


func _remove_nodes(nodes: Array) -> int:
	var count := 0
	var seen := {}
	for n in nodes:
		if n == null:
			continue
		var id = n.get_instance_id()
		if seen.has(id):
			continue
		seen[id] = true

		if n.has_method("disarm"):
			n.call("disarm")

		for ch_v in n.get_children():
			var ch: Node = ch_v
			if ch is Timer:
				var tmr := ch as Timer
				if not tmr.is_stopped():
					tmr.stop()

		n.queue_free()
		count += 1
	return count

func _unwrap_all_wrappers_exact() -> int:
	if editor == null:
		return 0
	var wrappers := _find_all_nodes_named(editor, WRAPPER_NAME)

	var game_layers := _find_all_gamelayers(editor)
	for gl in game_layers:
		var par := gl.get_parent()
		if par is Node2D and String(par.name) == WRAPPER_NAME:
			wrappers.append(par)

	var unwrapped := 0
	var seen := {}
	for w in wrappers:
		if w == null:
			continue
		var id = w.get_instance_id()
		if seen.has(id):
			continue
		seen[id] = true
		unwrapped += _unwrap_one_wrapper(w as Node2D)
	return unwrapped

func _unwrap_one_wrapper(wrapper: Node2D) -> int:
	if wrapper == null or not is_instance_valid(wrapper):
		return 0

	var game_layers := _find_all_gamelayers(wrapper)
	var count := 0
	for gl in game_layers:
		var parent := wrapper.get_parent()
		if parent == null:
			continue
		var gp := gl.get_global_position()
		wrapper.remove_child(gl)
		parent.add_child(gl)
		parent.move_child(gl, wrapper.get_index())
		gl.set_global_position(gp)
		count += 1

	if wrapper.get_child_count() == 0:
		wrapper.queue_free()
	return count

# ───────────────────────────────────────────────────────────────
# Generic tree helpers
# ───────────────────────────────────────────────────────────────

func _find_all_nodes_named(root: Node, exact: String) -> Array:
	var out: Array = []
	if root == null:
		return out
	var stack: Array[Node] = [root]
	while stack.size() > 0:
		var n := stack.pop_back()
		if n == null:
			continue
		if String(n.name) == exact:
			out.append(n)
		for c_v in n.get_children():
			var c := c_v as Node
			if c != null:
				stack.append(c)
	return out

func _find_all_gamelayers(root: Node) -> Array[Node2D]:
	var out: Array[Node2D] = []
	if root == null:
		return out
	var stack: Array[Node] = [root]
	while stack.size() > 0:
		var n := stack.pop_back()
		if n == null:
			continue
		if String(n.name) == GAMELAYER_NAME and (n is Node2D):
			out.append(n as Node2D)
		for c_v in n.get_children():
			var c := c_v as Node
			if c != null:
				stack.append(c)
	return out


# ───────────────────────────────────────────────────────────────
# Small utils + UI helpers
# ───────────────────────────────────────────────────────────────

func _add_big_icon_button(
	parent: Container,
	label_text: String,
	tooltip: String,
	func_name: String,
	icon_tex: Texture2D,
	card_size: int = 128
) -> void:
	var cell := VBoxContainer.new()
	cell.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	cell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cell.add_theme_constant_override("separation", 0)
	parent.add_child(cell)

	# Square enforced by ratio container
	var ratio := HBoxRatioContainer.new()
	ratio.custom_minimum_size = Vector2(card_size, card_size)
	ratio.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ratio.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cell.add_child(ratio)

	var hb := _mk_hb_button(label_text, tooltip, func_name, card_size)
	hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	ratio.add_child(hb)

	var inner: Button = hb.get_button()
	if inner:
		inner.icon = icon_tex
		inner.expand_icon = true
		inner.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER



func _current_playhead() -> float:
	if editor == null:
		return 0.0
	var p = editor.get("playhead_position")
	if typeof(p) == TYPE_FLOAT or typeof(p) == TYPE_INT:
		return float(p)
	return 0.0

func _fmt(v: float) -> String:
	return "%0.3f" % v

func _is_num(s: String) -> bool:
	var t := s.strip_edges()
	return t.is_valid_float()

func _parse_f(s: String, def: float) -> float:
	var t := s.strip_edges()
	if t.is_empty():
		return def
	return float(t) if t.is_valid_float() else def

func _parse_targets(s: String) -> Array:
	var t := s.strip_edges()
	if t.is_empty():
		var a: Array = []
		for n in DEFAULT_TARGETS:
			a.append(n)
		return a
	var names := t.split(",", false)
	var out: Array = []
	for raw in names:
		var nm := String(raw).strip_edges()
		if not nm.is_empty():
			out.append(nm)
	return out

func _targets_signature(v) -> String:
	var arr: Array = []
	if typeof(v) == TYPE_ARRAY:
		for x in (v as Array):
			arr.append(String(x))
	else:
		for n in DEFAULT_TARGETS:
			arr.append(n)
	arr.sort()
	return "|".join(arr)

func _as_f(v) -> float:
	match typeof(v):
		TYPE_FLOAT:
			return float(v)
		TYPE_INT:
			return float(v)
		TYPE_STRING:
			var s := String(v)
			return float(s) if s.is_valid_float() else 0.0
		_:
			return 0.0

func _feq(a: float, b: float) -> bool:
	return abs(a - b) <= EPS

func _safe_get(obj: Object, prop: String) -> Variant:
	if obj == null:
		return null
	if obj.has_method("get_property_list"):
		for p in obj.get_property_list():
			if String(p.name) == prop:
				return obj.get(prop)
	if obj.has_method("has_meta") and obj.has_meta(prop):
		return obj.get_meta(prop)
	return null

func _notify(text: String) -> void:
	if editor and editor.message_shower:
		editor.message_shower._show_notification(text)
	else:
		print(text)

func _mk_section_label(t: String) -> Label:
	var L := Label.new()
	L.text = t
	L.add_theme_color_override("font_color", Color(0.85, 0.85, 1.0))
	L.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return L

func _mk_label(t: String) -> Label:
	var L := Label.new()
	L.text = t
	return L

func _mk_spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c

func _load_svg_icon(path: String, size: int = ICON_SIZE_PX) -> Texture2D:
	if not FileAccess.file_exists(path):
		print("[FieldSlidesModule] Custom SVG not found at:", path)
		return null

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		print("[FieldSlidesModule] Failed to open SVG:", path)
		return null

	var buffer := file.get_buffer(file.get_length())

	var img := Image.new()
	var err := img.load_svg_from_buffer(buffer)
	if err != OK:
		print("[FieldSlidesModule] Failed to load SVG from buffer:", path, " error:", err)
		return null

	img.resize(size, size, Image.INTERPOLATE_BILINEAR)
	var tex := ImageTexture.create_from_image(img)
	return tex


func _ensure_icons_loaded() -> void:
	if ICON_SAVE_SLIDE == null:
		ICON_SAVE_SLIDE = _load_svg_icon("user://editor_scripts/SVGs/field_save_slide.svg")
		if ICON_SAVE_SLIDE == null:
			ICON_SAVE_SLIDE = preload("res://graphics/icons/console-line.svg")

	if ICON_CALIBRATE == null:
		ICON_CALIBRATE = _load_svg_icon("user://editor_scripts/SVGs/calibrate.svg")
		if ICON_CALIBRATE == null:
			# Fallback: reuse Save Slide icon, or console icon if even that failed
			if ICON_SAVE_SLIDE != null:
				ICON_CALIBRATE = ICON_SAVE_SLIDE
			else:
				ICON_CALIBRATE = preload("res://graphics/icons/console-line.svg")

	if ICON_RESET_UI == null:
		ICON_RESET_UI = _load_svg_icon("user://editor_scripts/SVGs/field_reset.svg")
		if ICON_RESET_UI == null:
			ICON_RESET_UI = preload("res://graphics/icons/console-line.svg")

	if ICON_SAVE_ROT == null:
		ICON_SAVE_ROT = _load_svg_icon("user://editor_scripts/SVGs/field_save_rot.svg")
		if ICON_SAVE_ROT == null:
			ICON_SAVE_ROT = preload("res://graphics/icons/console-line.svg")

	if ICON_SAVE_SCALE == null:
		ICON_SAVE_SCALE = _load_svg_icon("user://editor_scripts/SVGs/field_save_scale.svg")
		if ICON_SAVE_SCALE == null:
			ICON_SAVE_SCALE = preload("res://graphics/icons/console-line.svg")

	if ICON_INJECT == null:
		ICON_INJECT = _load_svg_icon("user://editor_scripts/SVGs/field_inject.svg")
		if ICON_INJECT == null:
			ICON_INJECT = preload("res://graphics/icons/console-line.svg")

	if ICON_UNINJECT == null:
		ICON_UNINJECT = _load_svg_icon("user://editor_scripts/SVGs/field_uninject.svg")
		if ICON_UNINJECT == null:
			ICON_UNINJECT = preload("res://graphics/icons/console-line.svg")
	
	if ICON_CLEAR_FIELDS == null:
		ICON_CLEAR_FIELDS = _load_svg_icon("user://editor_scripts/SVGs/field_clear_anims.svg")
		if ICON_CLEAR_FIELDS == null:
			# Fallback: reuse Reset UI icon or console icon
			if ICON_RESET_UI != null:
				ICON_CLEAR_FIELDS = ICON_RESET_UI
			else:
				ICON_CLEAR_FIELDS = preload("res://graphics/icons/console-line.svg")



func _mk_hb_button(
	text: String,
	tooltip: String,
	func_name: String,
	card_size: int = 128
) -> HBEditorButton:
	var b := HBEditorButton.new()
	b.button_mode = "function"
	b.text = text
	b.tooltip = tooltip
	b.function_name = func_name
	b.params = []
	b.disable_when_playing = true
	b.disable_with_popup = true

	# Outer card – this is what HBox/Grid sees and sizes
	b.custom_minimum_size = Vector2(card_size, card_size)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	b.set_module(self)
	return b



func _refresh_slide_manager() -> void:
	if editor == null:
		return
	var mgr := editor.get_node_or_null(MANAGER_NAME)
	if mgr == null:
		return

	if mgr.has_method("reload_now"):
		mgr.call_deferred("reload_now")
		return

	if mgr.has_method("disarm"):
		mgr.call("disarm")
	if mgr.has_method("configure"):
		mgr.call("configure", editor, _resolve_vfx_path())
	if mgr.has_method("arm"):
		mgr.call_deferred("arm")


# ───────────────────────────────────────────────────────────────
# PlayfieldSlidesManager class (unchanged logic)
# ───────────────────────────────────────────────────────────────
# (…everything from PlayfieldSlidesManager down remains exactly as in your current file…)

class PlayfieldSlidesManager:
	extends Node

	class SlideRow:
		var start_time: float = 0.0
		var end_time: float = 0.0
		var endpoint: Vector2 = Vector2.ZERO
		var ease: String = "linear"
		var targets: Array = []

	class RotateRow:
		var start_time: float = 0.0
		var end_time: float = 0.0
		var a0_deg: float = 0.0
		var a1_deg: float = 0.0
		var ease: String = "linear"
		var targets: Array = []
		var pivot_gl_local: Vector2 = Vector2.ZERO
	
	class ScaleRow:
		var start_time: float = 0.0
		var end_time: float = 0.0
		var s0: float = 1.0
		var s1: float = 1.0
		var ease: String = "linear"
		var targets: Array = []

	const JUDGEMENT_WRAPPER_NAME := "PH_JudgementWrapper"

	var editor: Node = null
	var json_path: String = ""
	var rows: Array = []
	var rot_rows: Array = []
	var scale_rows: Array = []

	var pt_target_nodes: Dictionary = {}
	var pt_baseline_pos: Dictionary = {}
	var pt_baseline_rot: Dictionary = {}
	var pt_baseline_scale: Dictionary = {}

	var _gl_preview: Node = null
	var target_nodes: Dictionary = {}
	var baseline_pos: Dictionary = {}
	var baseline_scale: Dictionary = {}
	var baseline_rot: Dictionary = {}
	var chains_preview: Dictionary = {}
	var rot_chains: Dictionary = {}
	var _rot_chain_global: Array = []

	var popup: Node = null
	var rg_logic: Node = null
	var game_layer: Node2D = null
	var wrapper: Node2D = null
	var _baseline_px: Vector2 = Vector2.ZERO
	var chain_pt: Array = []
	var rot_chain_pt: Array = []
	var _baseline_scale_wrapper: float = 1.0
	var _baseline_scale_game_layer: float = 1.0

	var _scale_pivot_gl: Vector2 = Vector2.ZERO
	var _baseline_scale_preview_gl: float = 1.0
	var _baseline_pos_preview_gl: Vector2 = Vector2.ZERO
	var _baseline_game_layer_pos: Vector2 = Vector2.ZERO

	# ─── JudgementLabel support (playtest) ───
	var judgement_label: Control = null
	var judgement_wrapper: Node2D = null
	var _baseline_judgement_wrapper_pos: Vector2 = Vector2.ZERO
	var _baseline_judgement_label_pos: Vector2 = Vector2.ZERO
	var _baseline_judgement_label_size: Vector2 = Vector2.ZERO
	var _judgement_label_original_parent: Node = null
	var _judgement_label_original_index: int = -1

	# ─── JudgementLabel support (preview) ───
	var _preview_judgement_label: Control = null
	var _preview_judgement_wrapper: Node2D = null
	var _preview_baseline_judgement_wrapper_pos: Vector2 = Vector2.ZERO
	var _preview_baseline_judgement_label_pos: Vector2 = Vector2.ZERO
	var _preview_judgement_label_original_parent: Node = null
	var _preview_judgement_label_original_index: int = -1

	var _poll_timer: Timer = null
	var _bound: bool = false
	var _audio_ready: bool = false
	var _seed_editor_ms: float = -1.0
	var _wall_bind_ms: float = -1.0
	var _last_clock_ms: float = -1.0
	var _last_editor_ms: float = -1.0

	func _gl_node2d() -> Node2D:
		if _gl_preview is Node2D:
			return _gl_preview as Node2D
		if _gl_preview is Node:
			var gl := (_gl_preview as Node).find_child("GameLayer", true, false)
			return gl as Node2D
		return null

	func _as_f(v: Variant) -> float:
		if typeof(v) == TYPE_FLOAT:
			return float(v)
		elif typeof(v) == TYPE_INT:
			return float(v)
		elif typeof(v) == TYPE_STRING:
			var s := String(v)
			return float(s) if s.is_valid_float() else 0.0
		return 0.0

	func _progress(tnow: float, t0: float, t1: float) -> float:
		if t1 <= t0:
			return 1.0
		return clamp((tnow - t0) / (t1 - t0), 0.0, 1.0)

	func _ease_eval(name: String, x: float) -> float:
		var n := name.strip_edges().to_lower()
		if n == "quad_in_out":
			if x < 0.5:
				return 2.0 * x * x
			var u := 1.0 - x
			return 1.0 - 2.0 * u * u
		elif n == "quad_in":
			return x * x
		elif n == "quad_out":
			return 1.0 - (1.0 - x) * (1.0 - x)
		elif n == "cubic_in_out":
			if x < 0.5:
				return 4.0 * x * x * x
			var k := 2.0 * x - 2.0
			return 0.5 * k * k * k + 1.0
		return x

	func _current_playhead() -> float:
		if editor == null:
			return 0.0
		var p := editor.get("playhead_position")
		if typeof(p) == TYPE_FLOAT or typeof(p) == TYPE_INT:
			return float(p)
		return 0.0

	func configure(p_editor: Node, p_json_path: String) -> void:
		editor = p_editor
		json_path = p_json_path

	func arm() -> void:
		_load_rows()
		_normalize_rows_times_ms()

		_snapshot_targets_and_baselines()
		_wrap_preview_judgement_label()
		_build_preview_chains()
		_build_preview_rot_chains()

		_connect_editor_signals()
		_last_editor_ms = -1.0

		_start_poll()
		set_process(true)
		process_priority = 1024

		_tick_preview()

	func disarm() -> void:
		_disconnect_editor_signals()
		_stop_poll()
		_unwrap_preview_judgement_label()
		_unwrap_playtest_judgement_label()
		_unwrap_if_any()
		set_process(false)

		rows.clear()
		rot_rows.clear()
		scale_rows.clear()
		target_nodes.clear()
		baseline_pos.clear()
		baseline_scale.clear()
		baseline_rot.clear()
		chains_preview.clear()
		rot_chains.clear()
		popup = null
		rg_logic = null
		game_layer = null
		wrapper = null
		_baseline_px = Vector2.ZERO
		chain_pt.clear()
		rot_chain_pt.clear()
		_baseline_scale_wrapper = 1.0
		_bound = false
		_audio_ready = false
		_seed_editor_ms = -1.0
		_last_editor_ms = -1.0
		_wall_bind_ms = -1.0
		_last_clock_ms = -1.0

		pt_target_nodes.clear()
		pt_baseline_pos.clear()
		pt_baseline_rot.clear()
		pt_baseline_scale.clear()

		# Clear judgement label references
		judgement_label = null
		judgement_wrapper = null
		_preview_judgement_label = null
		_preview_judgement_wrapper = null

	# ─────────────────────────────────────────────────────────────
	# Preview JudgementLabel wrapping
	# ─────────────────────────────────────────────────────────────

	func _wrap_preview_judgement_label() -> void:
		if editor == null:
			return

		# Find preview's RhythmGame
		var gp := editor.get("game_preview")
		if gp == null:
			return

		var rhythm_game := (gp as Node).find_child("RhythmGame", true, false)
		if rhythm_game == null:
			# Try finding it as direct child
			rhythm_game = gp as Node

		var jl := rhythm_game.find_child("JudgementLabel", true, false) if rhythm_game else null
		if not (jl is Control):
			return

		_preview_judgement_label = jl as Control
		var jl_parent := _preview_judgement_label.get_parent()
		if jl_parent == null:
			return

		# Check if already wrapped
		var existing_wrapper := jl_parent.get_node_or_null(JUDGEMENT_WRAPPER_NAME)
		if existing_wrapper is Node2D and existing_wrapper.is_ancestor_of(_preview_judgement_label):
			_preview_judgement_wrapper = existing_wrapper as Node2D
			_preview_baseline_judgement_wrapper_pos = _preview_judgement_wrapper.position
			_preview_baseline_judgement_label_pos = _preview_judgement_label.position
			return

		# Store original parent info for unwrapping
		_preview_judgement_label_original_parent = jl_parent
		_preview_judgement_label_original_index = _preview_judgement_label.get_index()
		_preview_baseline_judgement_label_pos = _preview_judgement_label.position

		# Create wrapper
		_preview_judgement_wrapper = Node2D.new()
		_preview_judgement_wrapper.name = JUDGEMENT_WRAPPER_NAME

		# Insert wrapper at JudgementLabel's position in tree
		jl_parent.add_child(_preview_judgement_wrapper)
		jl_parent.move_child(_preview_judgement_wrapper, _preview_judgement_label_original_index)

		# Reparent JudgementLabel under wrapper
		jl_parent.remove_child(_preview_judgement_label)
		_preview_judgement_wrapper.add_child(_preview_judgement_label)

		# Restore label's position (now relative to wrapper which is at origin)
		_preview_judgement_label.position = _preview_baseline_judgement_label_pos
		_preview_baseline_judgement_wrapper_pos = Vector2.ZERO

	func _unwrap_preview_judgement_label() -> void:
		if _preview_judgement_label == null or _preview_judgement_wrapper == null:
			return
		if not is_instance_valid(_preview_judgement_label) or not is_instance_valid(_preview_judgement_wrapper):
			_preview_judgement_label = null
			_preview_judgement_wrapper = null
			return

		var wrapper_parent := _preview_judgement_wrapper.get_parent()
		if wrapper_parent == null:
			return

		# Restore JudgementLabel to original parent
		_preview_judgement_wrapper.remove_child(_preview_judgement_label)

		if _preview_judgement_label_original_parent != null and is_instance_valid(_preview_judgement_label_original_parent):
			_preview_judgement_label_original_parent.add_child(_preview_judgement_label)
			if _preview_judgement_label_original_index >= 0:
				var max_idx := _preview_judgement_label_original_parent.get_child_count() - 1
				var target_idx := min(_preview_judgement_label_original_index, max_idx)
				_preview_judgement_label_original_parent.move_child(_preview_judgement_label, target_idx)
		else:
			wrapper_parent.add_child(_preview_judgement_label)
			wrapper_parent.move_child(_preview_judgement_label, _preview_judgement_wrapper.get_index())

		# Restore baseline position
		_preview_judgement_label.position = _preview_baseline_judgement_label_pos

		# Remove wrapper
		_preview_judgement_wrapper.queue_free()
		_preview_judgement_wrapper = null
		_preview_judgement_label = null
		_preview_judgement_label_original_parent = null
		_preview_judgement_label_original_index = -1

	# ─────────────────────────────────────────────────────────────
	# Playtest JudgementLabel wrapping
	# ─────────────────────────────────────────────────────────────

	func _wrap_playtest_judgement_label(search_root: Node) -> void:
		if search_root == null:
			return

		var jl := search_root.find_child("JudgementLabel", true, false)
		if not (jl is Control):
			return

		judgement_label = jl as Control
		var jl_parent := judgement_label.get_parent()
		if jl_parent == null:
			return

		# Check if already wrapped
		var existing_wrapper := jl_parent.get_node_or_null(JUDGEMENT_WRAPPER_NAME)
		if existing_wrapper is Node2D and existing_wrapper.is_ancestor_of(judgement_label):
			judgement_wrapper = existing_wrapper as Node2D
			_baseline_judgement_wrapper_pos = judgement_wrapper.position
			_baseline_judgement_label_pos = judgement_label.position
			_baseline_judgement_label_size = judgement_label.size
			return

		# Store original parent info for unwrapping
		_judgement_label_original_parent = jl_parent
		_judgement_label_original_index = judgement_label.get_index()
		_baseline_judgement_label_pos = judgement_label.position
		_baseline_judgement_label_size = judgement_label.size

		# Create wrapper
		judgement_wrapper = Node2D.new()
		judgement_wrapper.name = JUDGEMENT_WRAPPER_NAME

		# Insert wrapper at JudgementLabel's position in tree
		jl_parent.add_child(judgement_wrapper)
		jl_parent.move_child(judgement_wrapper, _judgement_label_original_index)

		# Reparent JudgementLabel under wrapper
		jl_parent.remove_child(judgement_label)
		judgement_wrapper.add_child(judgement_label)

		# Restore label's position (now relative to wrapper which is at origin)
		judgement_label.position = _baseline_judgement_label_pos
		_baseline_judgement_wrapper_pos = Vector2.ZERO

	func _unwrap_playtest_judgement_label() -> void:
		if judgement_label == null or judgement_wrapper == null:
			return
		if not is_instance_valid(judgement_label) or not is_instance_valid(judgement_wrapper):
			judgement_label = null
			judgement_wrapper = null
			return

		var wrapper_parent := judgement_wrapper.get_parent()
		if wrapper_parent == null:
			return

		# Restore JudgementLabel to original parent
		judgement_wrapper.remove_child(judgement_label)

		if _judgement_label_original_parent != null and is_instance_valid(_judgement_label_original_parent):
			_judgement_label_original_parent.add_child(judgement_label)
			if _judgement_label_original_index >= 0:
				var max_idx := _judgement_label_original_parent.get_child_count() - 1
				var target_idx := min(_judgement_label_original_index, max_idx)
				_judgement_label_original_parent.move_child(judgement_label, target_idx)
		else:
			wrapper_parent.add_child(judgement_label)
			wrapper_parent.move_child(judgement_label, judgement_wrapper.get_index())

		# Restore baseline position
		judgement_label.position = _baseline_judgement_label_pos

		# Remove wrapper
		judgement_wrapper.queue_free()
		judgement_wrapper = null
		judgement_label = null
		_judgement_label_original_parent = null
		_judgement_label_original_index = -1

	# ─────────────────────────────────────────────────────────────
	# Restore helpers
	# ─────────────────────────────────────────────────────────────

	func _restore_preview_to_baseline() -> void:
		if target_nodes.is_empty():
			return

		# Restore preview GameLayer transform
		var gl2d := _gl_node2d()
		if gl2d != null and is_instance_valid(gl2d):
			gl2d.position = _baseline_pos_preview_gl
			gl2d.scale = Vector2(_baseline_scale_preview_gl, _baseline_scale_preview_gl)

		for name in target_nodes.keys():
			var node := target_nodes[name] as Node2D
			if node == null or not is_instance_valid(node):
				continue

			if baseline_pos.has(name):
				node.position = baseline_pos[name]
			if baseline_rot.has(name):
				node.rotation_degrees = float(baseline_rot[name])
			if baseline_scale.has(name):
				node.scale = baseline_scale[name]

		# Restore preview JudgementLabel wrapper
		if _preview_judgement_wrapper != null and is_instance_valid(_preview_judgement_wrapper):
			_preview_judgement_wrapper.position = _preview_baseline_judgement_wrapper_pos
			_preview_judgement_wrapper.rotation_degrees = 0.0
			_preview_judgement_wrapper.scale = Vector2.ONE
			
	func _restore_playtest_wrapper_to_baseline() -> void:
		if wrapper != null and is_instance_valid(wrapper):
			wrapper.position = _baseline_px
			wrapper.rotation_degrees = 0.0
			wrapper.scale = Vector2(_baseline_scale_wrapper, _baseline_scale_wrapper)

		if game_layer != null and is_instance_valid(game_layer):
			game_layer.position = _baseline_game_layer_pos
			game_layer.rotation_degrees = 0.0
			game_layer.scale = Vector2(_baseline_scale_game_layer, _baseline_scale_game_layer)

		# Restore playtest target nodes (rotation is applied per-node)
		for name in pt_target_nodes.keys():
			var node := pt_target_nodes[name] as Node2D
			if node == null or not is_instance_valid(node):
				continue
			
			if pt_baseline_pos.has(name):
				node.position = pt_baseline_pos[name]
			if pt_baseline_rot.has(name):
				node.rotation_degrees = float(pt_baseline_rot[name])
			if pt_baseline_scale.has(name):
				node.scale = pt_baseline_scale[name]

		# Restore playtest JudgementLabel wrapper
		if judgement_wrapper != null and is_instance_valid(judgement_wrapper):
			judgement_wrapper.position = _baseline_judgement_wrapper_pos
			judgement_wrapper.rotation_degrees = 0.0
			judgement_wrapper.scale = Vector2.ONE
			
	func _tick_preview_scale_gl(playhead: float, sfac: float) -> void:
		if scale_rows.is_empty():
			return

		var gl2d := _gl_node2d()
		if gl2d == null or not is_instance_valid(gl2d):
			return

		var target_scale := _baseline_scale_preview_gl * sfac

		if abs(gl2d.scale.x - target_scale) < 0.0001 and abs(gl2d.scale.y - target_scale) < 0.0001:
			return

		var pivot_local := FIELD_PIVOT_GL
		var baseline_pos := _baseline_pos_preview_gl

		gl2d.position = baseline_pos
		gl2d.scale = Vector2(_baseline_scale_preview_gl, _baseline_scale_preview_gl)
		var pivot_world_ref := gl2d.to_global(pivot_local)

		gl2d.scale = Vector2(target_scale, target_scale)
		var pivot_world_scaled := gl2d.to_global(pivot_local)

		var delta := pivot_world_scaled - pivot_world_ref
		gl2d.position = baseline_pos - delta

	func reload_now() -> void:
		_restore_preview_to_baseline()

		_load_rows()
		_normalize_rows_times_ms()

		_build_preview_chains()
		_build_preview_rot_chains()

		_build_chain_pt()
		_build_chain_rot_pt()

		_tick_preview()

		if _bound and wrapper != null and is_instance_valid(wrapper):
			var t := _seeded_time_ms()
			if t >= 0.0:
				var pos := _eval_pos_pt(t)
				if wrapper.position != pos:
					wrapper.position = pos

				_tick_playtest_scale(t)
				_tick_playtest_rotation(t)
				_tick_playtest_judgement_label(t)

				_last_clock_ms = t

	func _load_rows() -> void:
		rows.clear()
		rot_rows.clear()
		scale_rows.clear()
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

		for e_v in (parsed as Array):
			if typeof(e_v) != TYPE_DICTIONARY:
				continue
			var e: Dictionary = e_v
			var layer_name := String(e.get("layer", ""))
			if layer_name == ENTRY_TAG:
				var r := SlideRow.new()
				r.start_time = _as_f(e.get("pf_slide_start_time", 0.0))
				r.end_time   = _as_f(e.get("pf_slide_end_time", 0.0))
				var ep := e.get("pf_slide_endpoint", null)
				if typeof(ep) == TYPE_ARRAY:
					var a: Array = ep
					if a.size() >= 2:
						r.endpoint = Vector2(float(a[0]), float(a[1]))
				r.ease = String(e.get("pf_slide_ease", "linear"))
				r.targets = []
				var tlist := e.get("pf_slide_targets", null)
				if typeof(tlist) == TYPE_ARRAY:
					for t in (tlist as Array):
						r.targets.append(String(t))
				if r.targets.is_empty():
					for d in DEFAULT_TARGETS:
						r.targets.append(d)
				if r.end_time > r.start_time:
					rows.append(r)
			elif layer_name == ROTATE_TAG:
				var rr := RotateRow.new()
				rr.start_time = _as_f(e.get("pf_rot_start_time", 0.0))
				rr.end_time   = _as_f(e.get("pf_rot_end_time", 0.0))
				rr.a0_deg     = _as_f(e.get("pf_rot_angle_start_deg", 0.0))
				rr.a1_deg     = _as_f(e.get("pf_rot_angle_end_deg", 0.0))
				rr.ease       = String(e.get("pf_rot_ease", "linear"))
				rr.targets = []
				var tlist2 := e.get("pf_rot_targets", null)
				if typeof(tlist2) == TYPE_ARRAY:
					for t2 in (tlist2 as Array):
						rr.targets.append(String(t2))
				if rr.targets.is_empty():
					for d2 in DEFAULT_TARGETS:
						rr.targets.append(d2)
				var pv := e.get("pf_rot_pivot_local", null)
				if typeof(pv) == TYPE_ARRAY and (pv as Array).size() >= 2:
					rr.pivot_gl_local = Vector2(float(pv[0]), float(pv[1]))
				if rr.end_time > rr.start_time:
					rot_rows.append(rr)
			elif layer_name == PF_SCALE_TAG:
				var sr := ScaleRow.new()
				sr.start_time = _as_f(e.get("pf_scale_start_time", 0.0))
				sr.end_time   = _as_f(e.get("pf_scale_end_time",   0.0))
				sr.s0         = _as_f(e.get("pf_scale_start_mult", 1.0))
				sr.s1         = _as_f(e.get("pf_scale_end_mult",   1.0))
				sr.ease       = String(e.get("pf_scale_ease", "linear"))
				sr.targets = []
				var tlist3 := e.get("pf_scale_targets", null)
				if typeof(tlist3) == TYPE_ARRAY:
					for t3 in (tlist3 as Array):
						sr.targets.append(String(t3))
				if sr.targets.is_empty():
					for d3 in DEFAULT_TARGETS:
						sr.targets.append(d3)
				if sr.end_time > sr.start_time:
					scale_rows.append(sr)

		rows.sort_custom(func(a: SlideRow, b: SlideRow) -> bool:
			return a.start_time < b.start_time
		)
		rot_rows.sort_custom(func(a: RotateRow, b: RotateRow) -> bool:
			return a.start_time < b.start_time
		)
		scale_rows.sort_custom(func(a: ScaleRow, b: ScaleRow) -> bool:
			return a.start_time < b.start_time
		)

	func _normalize_rows_times_ms() -> void:
		var max_end_slide: float = 0.0
		for r in rows:
			if r.end_time > max_end_slide:
				max_end_slide = r.end_time
		var max_end_rot: float = 0.0
		for rr in rot_rows:
			if rr.end_time > max_end_rot:
				max_end_rot = rr.end_time
		var max_end_scale: float = 0.0
		for sr in scale_rows:
			if sr.end_time > max_end_scale:
				max_end_scale = sr.end_time

		var need_ms := false
		if (max_end_slide > 0.0 and max_end_slide <= 600.0) \
		or (max_end_rot > 0.0 and max_end_rot <= 600.0) \
		or (max_end_scale > 0.0 and max_end_scale <= 600.0):
			need_ms = true

		if need_ms:
			for r2 in rows:
				r2.start_time *= 1000.0
				r2.end_time   *= 1000.0
			for rr2 in rot_rows:
				rr2.start_time *= 1000.0
				rr2.end_time   *= 1000.0
			for sr2 in scale_rows:
				sr2.start_time *= 1000.0
				sr2.end_time   *= 1000.0

	func _preview_root() -> Node2D:
		if editor == null:
			return null
		var gp := editor.get("game_preview")
		if gp is Node:
			var gl := (gp as Node).find_child("GameLayer", true, false)
			return gl as Node2D
		var gl2 := editor.find_child("GameLayer", true, false)
		return gl2 as Node2D

	func _endpoint_to_parent_space(node: Node2D, endpoint_gl_local: Vector2) -> Vector2:
		var gl2d := _gl_node2d()
		var parent2d := node.get_parent() as Node2D
		if gl2d == null or parent2d == null:
			return endpoint_gl_local
		return parent2d.to_local(gl2d.to_global(endpoint_gl_local))

	func _pivot_gl_from_seg(rs: Dictionary) -> Vector2:
		if rs.has("pivot_gl_local") and rs["pivot_gl_local"] is Vector2:
			return rs["pivot_gl_local"]
		if rs.has("pivot") and rs["pivot"] is Vector2:
			return rs["pivot"]
		return Vector2.ZERO

	func _snapshot_playtest_targets() -> void:
		pt_target_nodes.clear()
		pt_baseline_pos.clear()
		pt_baseline_rot.clear()
		pt_baseline_scale.clear()

		if game_layer == null or not is_instance_valid(game_layer):
			return

		var names: Dictionary = {}
		if rows.is_empty() and rot_rows.is_empty():
			for d in DEFAULT_TARGETS:
				names[d] = true
		else:
			for r in rows:
				for n in r.targets:
					names[String(n)] = true
			for rr in rot_rows:
				for n2 in rr.targets:
					names[String(n2)] = true

		for name_k in names.keys():
			var nm := String(name_k)
			var n := game_layer.find_child(nm, true, false)
			if n is Node2D:
				var nd := n as Node2D
				pt_target_nodes[nm] = nd
				pt_baseline_pos[nm] = nd.position
				pt_baseline_rot[nm] = nd.rotation_degrees
				pt_baseline_scale[nm] = nd.scale

	func _snapshot_targets_and_baselines() -> void:
		target_nodes.clear()
		baseline_pos.clear()
		baseline_rot.clear()

		_gl_preview = _preview_root()
		if _gl_preview == null:
			return

		var gl2d := _gl_node2d()
		if gl2d != null and is_instance_valid(gl2d):
			_baseline_pos_preview_gl = gl2d.position
			_baseline_scale_preview_gl = (gl2d.scale.x if gl2d.scale.x != 0.0 else 1.0)

		var names: Dictionary = {}
		if rows.is_empty() and rot_rows.is_empty():
			for d in DEFAULT_TARGETS:
				names[d] = true
		else:
			for r in rows:
				for n in r.targets:
					names[String(n)] = true
			for rr in rot_rows:
				for n2 in rr.targets:
					names[String(n2)] = true

		for name_k in names.keys():
			var nm := String(name_k)
			var n := (_gl_preview as Node).find_child(nm, true, false)
			if n is Node2D:
				var nd := n as Node2D
				target_nodes[nm] = nd
				baseline_pos[nm] = nd.position

				if not baseline_scale.has(nm):
					baseline_scale[nm] = nd.scale

				baseline_rot[nm] = nd.rotation_degrees

		_recompute_scale_pivot_from_preview()

	func _recompute_scale_pivot_from_preview() -> void:
		_scale_pivot_gl = FIELD_PIVOT_GL

	func _build_preview_chains() -> void:
		chains_preview.clear()
		if _gl_preview == null:
			return

		var known: Dictionary = {}
		for nm in target_nodes.keys():
			known[nm] = true
		for r in rows:
			for nm in r.targets:
				known[String(nm)] = true

		for nm_k in known.keys():
			var nm := String(nm_k)
			var node := target_nodes.get(nm, null) as Node2D
			if node == null:
				chains_preview[nm] = []
				continue

			var base_parent_pos: Vector2 = baseline_pos.get(nm, Vector2.ZERO)
			var segs: Array = []
			var prev_end_parent := base_parent_pos

			for r in rows:
				var applies := false
				for tname in r.targets:
					if String(tname) == nm:
						applies = true
						break
				if not applies:
					continue

				var end_parent := _endpoint_to_parent_space(node, r.endpoint)

				segs.append({
					"t0": r.start_time,
					"t1": r.end_time,
					"base": prev_end_parent,
					"end": end_parent,
					"ease": r.ease
				})
				prev_end_parent = end_parent

			chains_preview[nm] = segs

	func _build_preview_rot_chains() -> void:
		rot_chains.clear()
		_rot_chain_global.clear()
		if _gl_preview == null:
			return

		var known: Dictionary = {}
		for nm in target_nodes.keys():
			known[nm] = true
		for rr in rot_rows:
			for nm in rr.targets:
				known[String(nm)] = true
		for nm_k in known.keys():
			rot_chains[String(nm_k)] = []

		for rr in rot_rows:
			for nm in rr.targets:
				var key := String(nm)
				var arr: Array = rot_chains.get(key, [])
				arr.append({
					"t0": rr.start_time,
					"t1": rr.end_time,
					"a0": rr.a0_deg,
					"a1": rr.a1_deg,
					"ease": rr.ease,
					"pivot_gl_local": rr.pivot_gl_local
				})
				rot_chains[key] = arr

			_rot_chain_global.append({
				"t0": rr.start_time,
				"t1": rr.end_time,
				"a0": rr.a0_deg,
				"a1": rr.a1_deg,
				"ease": rr.ease,
				"pivot_gl_local": rr.pivot_gl_local
			})

		for nm2 in rot_chains.keys():
			var arr2: Array = rot_chains[nm2]
			arr2.sort_custom(func(a, b):
				return float(a["t0"]) < float(b["t0"])
			)
			rot_chains[nm2] = arr2

		_rot_chain_global.sort_custom(func(a, b):
			return float(a["t0"]) < float(b["t0"])
		)

	func _eval_global_rot_at(playhead: float) -> Dictionary:
		if _rot_chain_global.is_empty():
			return {"ok": false}
		if playhead < float(_rot_chain_global[0]["t0"]):
			return {"ok": false}
		var ang := 0.0
		var seg: Dictionary = {}
		for i in range(_rot_chain_global.size()):
			var s = _rot_chain_global[i]
			var t0 := float(s["t0"])
			var t1 := float(s["t1"])
			if playhead < t0:
				break
			if playhead <= t1:
				var pr := _progress(playhead, t0, t1)
				var ez := _ease_eval(String(s["ease"]), pr)
				ang = lerp(float(s["a0"]), float(s["a1"]), ez)
				seg = s
				return {"ok": true, "angle": ang, "seg": seg}
			else:
				ang = float(s["a1"])
				seg = s
		return {"ok": true, "angle": ang, "seg": seg}

	func _eval_scale_factor_at(playhead: float) -> float:
		if scale_rows.is_empty():
			return 1.0

		if playhead <= scale_rows[0].start_time:
			return 1.0

		var last_s: float = 1.0

		for sr in scale_rows:
			var t0 = sr.start_time
			var t1 = sr.end_time
			if playhead < t0:
				return last_s
			elif playhead <= t1:
				var pr := _progress(playhead, t0, t1)
				var ez := _ease_eval(sr.ease, pr)
				return lerp(sr.s0, sr.s1, ez)
			else:
				last_s = sr.s1

		return last_s

	# ─────────────────────────────────────────────────────────────
	# Compute slide offset for JudgementLabel
	# ─────────────────────────────────────────────────────────────

	func _eval_slide_offset_at(playhead: float) -> Vector2:
		# Returns the offset from baseline that the wrapper should have
		# This is used for JudgementLabel which needs the same offset as the main field
		if chain_pt.is_empty():
			# For preview, compute from the first target's chain
			if chains_preview.is_empty():
				return Vector2.ZERO
			
			# Get offset from any target chain (they all move together for field slides)
			for nm in chains_preview.keys():
				var segs: Array = chains_preview[nm]
				if segs.is_empty():
					continue
				
				var base_pos: Vector2 = baseline_pos.get(nm, Vector2.ZERO)
				
				if playhead <= float(segs[0]["t0"]):
					return Vector2.ZERO
				
				var pos_now := base_pos
				for i in range(segs.size()):
					var s = segs[i]
					var t0 := float(s["t0"])
					var t1 := float(s["t1"])
					var b: Vector2 = s["base"]
					var e: Vector2 = s["end"]
					
					if playhead < t0:
						pos_now = (segs[i - 1]["end"] if i > 0 else base_pos)
						break
					elif playhead <= t1:
						var t := _progress(playhead, t0, t1)
						var eased := _ease_eval(String(s["ease"]), t)
						pos_now = b.lerp(e, eased)
						break
					else:
						pos_now = e
				
				return pos_now - base_pos
			
			return Vector2.ZERO
		
		# For playtest, compute from chain_pt
		var pos := _eval_pos_pt(playhead)
		return pos - _baseline_px

	func _connect_editor_signals() -> void:
		if editor == null:
			return
		if not editor.is_connected("playhead_position_changed", Callable(self, "_on_editor_playhead")):
			editor.playhead_position_changed.connect(Callable(self, "_on_editor_playhead"))
		if not editor.is_connected("paused", Callable(self, "_on_editor_playhead")):
			editor.paused.connect(Callable(self, "_on_editor_playhead"))

		var gp := editor.get("game_preview")
		if gp is Object and (gp as Object).has_signal("preview_size_changed"):
			if not (gp as Object).is_connected("preview_size_changed", Callable(self, "_on_preview_resized")):
				(gp as Object).connect("preview_size_changed", Callable(self, "_on_preview_resized"))

	func _disconnect_editor_signals() -> void:
		if editor == null:
			return
		if editor.is_connected("playhead_position_changed", Callable(self, "_on_editor_playhead")):
			editor.playhead_position_changed.disconnect(Callable(self, "_on_editor_playhead"))
		if editor.is_connected("paused", Callable(self, "_on_editor_playhead")):
			editor.paused.disconnect(Callable(self, "_on_editor_playhead"))

		var gp := editor.get("game_preview")
		if gp is Object and (gp as Object).has_signal("preview_size_changed"):
			if (gp as Object).is_connected("preview_size_changed", Callable(self, "_on_preview_resized")):
				(gp as Object).disconnect("preview_size_changed", Callable(self, "_on_preview_resized"))

	func _on_preview_resized() -> void:
		_snapshot_targets_and_baselines()
		_build_preview_chains()
		_build_preview_rot_chains()
		_tick_preview()

	func _on_editor_playhead() -> void:
		_tick_preview()

	func _tick_playtest_scale(t_ms: float) -> void:
		if scale_rows.is_empty():
			return
		if pt_target_nodes.is_empty():
			return

		var sfac := _eval_scale_factor_at(t_ms)

		for name in pt_target_nodes.keys():
			var node := pt_target_nodes[name] as Node2D
			if node == null or not is_instance_valid(node):
				continue

	func _tick_playtest_scale_gl(t_ms: float) -> void:
		if scale_rows.is_empty():
			return
		if game_layer == null or not is_instance_valid(game_layer):
			return

		var sfac := _eval_scale_factor_at(t_ms)
		var target_scale := _baseline_scale_game_layer * sfac

		if abs(game_layer.scale.x - target_scale) < 0.0001 and abs(game_layer.scale.y - target_scale) < 0.0001:
			return

		var pivot_gl_local := _scale_pivot_gl
		var baseline_pos := _baseline_game_layer_pos

		game_layer.position = baseline_pos
		game_layer.scale = Vector2(_baseline_scale_game_layer, _baseline_scale_game_layer)
		var pivot_world_ref := game_layer.to_global(pivot_gl_local)

		game_layer.scale = Vector2(target_scale, target_scale)
		var pivot_world_scaled := game_layer.to_global(pivot_gl_local)

		var delta := pivot_world_scaled - pivot_world_ref
		game_layer.position = baseline_pos - delta

	func _tick_playtest_rotation(t_ms: float) -> void:
		if rot_rows.is_empty():
			return
		if game_layer == null or pt_target_nodes.is_empty():
			return

		var g := _eval_global_rot_at(t_ms)
		if not g.get("ok", false):
			for name in pt_target_nodes.keys():
				var node := pt_target_nodes[name] as Node2D
				if node == null or not is_instance_valid(node):
					continue
				node.position = pt_baseline_pos.get(name, node.position)
				node.rotation_degrees = pt_baseline_rot.get(name, node.rotation_degrees)
			return

		var angle_now_deg := float(g["angle"])
		var seg: Dictionary = g["seg"]
		var pv_gl_local := seg.get("pivot_gl_local", Vector2.ZERO)
		if not (pv_gl_local is Vector2):
			pv_gl_local = Vector2.ZERO

		var gl2d := game_layer
		var parent2d := gl2d.get_parent() as Node2D
		if parent2d == null:
			return

		for name in pt_target_nodes.keys():
			var node := pt_target_nodes[name] as Node2D
			if node == null or not is_instance_valid(node):
				continue

			var base_pos: Vector2 = pt_baseline_pos.get(name, node.position)
			var base_rot: float = pt_baseline_rot.get(name, node.rotation_degrees)

			var node_parent := node.get_parent() as Node2D
			if node_parent == null:
				continue

			var pv_parent := node_parent.to_local(gl2d.to_global(pv_gl_local))

			var rel := base_pos - pv_parent
			var pos_now := pv_parent + rel.rotated(deg_to_rad(angle_now_deg))

			node.position = pos_now
			node.rotation_degrees = base_rot + angle_now_deg

	# ─────────────────────────────────────────────────────────────
	# JudgementLabel tick (playtest)
	# ─────────────────────────────────────────────────────────────

	func _tick_preview_judgement_label(playhead: float, sfac: float) -> void:
		if _preview_judgement_wrapper == null or not is_instance_valid(_preview_judgement_wrapper):
			return

		# The scale pivot is the field center (960, 540)
		var scale_pivot := FIELD_PIVOT_GL
		
		# 1) Slides - compute offset from field movement
		var jl_slide_offset := _eval_slide_offset_at(playhead)
		
		# The JudgementLabel's screen position at baseline (wrapper at origin, label at its original pos)
		# Since wrapper starts at (0,0), the label's screen pos is just its local position
		var label_screen_pos := _preview_baseline_judgement_label_pos
		
		# For scale: we want to scale around FIELD_PIVOT_GL, not around the wrapper origin
		# The label's position relative to the scale pivot
		var label_to_pivot := label_screen_pos - scale_pivot
		
		# When we scale the wrapper, content scales around wrapper origin (0,0)
		# But we want it to scale around scale_pivot
		# So we need to move the wrapper to compensate
		
		# At scale sfac, the label would move to: label_screen_pos * sfac (if wrapper stays at origin)
		# But we want it at: scale_pivot + label_to_pivot * sfac
		# The difference is our scale compensation for the wrapper position
		
		var desired_label_pos := scale_pivot + label_to_pivot * sfac
		var uncompensated_label_pos := label_screen_pos * sfac  # where it would be with wrapper at origin
		var scale_compensation := desired_label_pos - uncompensated_label_pos
		
		# Apply scale to wrapper
		_preview_judgement_wrapper.scale = Vector2(sfac, sfac)
		
		# Wrapper position = slide offset + scale compensation
		var final_pos := jl_slide_offset + scale_compensation

		# 3) Rotation around FIELD_PIVOT_GL
		var g := _eval_global_rot_at(playhead)
		if g.get("ok", false):
			var angle_deg := float(g["angle"])
			_preview_judgement_wrapper.rotation_degrees = angle_deg
			
			# The wrapper's position also needs to rotate around the pivot
			# final_pos is currently the wrapper position before rotation
			# We need to rotate this position around scale_pivot
			var rel := final_pos - scale_pivot
			var rotated_pos := scale_pivot + rel.rotated(deg_to_rad(angle_deg))
			_preview_judgement_wrapper.position = rotated_pos
		else:
			_preview_judgement_wrapper.rotation_degrees = 0.0
			_preview_judgement_wrapper.position = final_pos


	func _tick_playtest_judgement_label(t_ms: float) -> void:
		if judgement_wrapper == null or not is_instance_valid(judgement_wrapper):
			return

		# The scale pivot is the field center (960, 540)
		var scale_pivot := FIELD_PIVOT_GL
		var sfac := _eval_scale_factor_at(t_ms)
		
		# 1) Slides - compute offset from field movement
		var jl_slide_offset := _eval_slide_offset_at(t_ms)
		
		# The JudgementLabel's screen position at baseline (wrapper at origin, label at its original pos)
		var label_screen_pos := _baseline_judgement_label_pos
		
		# The label's position relative to the scale pivot
		var label_to_pivot := label_screen_pos - scale_pivot
		
		# At scale sfac, where we want the label vs where it would be
		var desired_label_pos := scale_pivot + label_to_pivot * sfac
		var uncompensated_label_pos := label_screen_pos * sfac
		var scale_compensation := desired_label_pos - uncompensated_label_pos
		
		# Apply scale to wrapper
		judgement_wrapper.scale = Vector2(sfac, sfac)
		
		# Wrapper position = slide offset + scale compensation
		var final_pos := jl_slide_offset + scale_compensation

		# 3) Rotation around FIELD_PIVOT_GL
		var g := _eval_global_rot_at(t_ms)
		if g.get("ok", false):
			var angle_deg := float(g["angle"])
			judgement_wrapper.rotation_degrees = angle_deg
			
			# Rotate wrapper position around the pivot
			var rel := final_pos - scale_pivot
			var rotated_pos := scale_pivot + rel.rotated(deg_to_rad(angle_deg))
			judgement_wrapper.position = rotated_pos
		else:
			judgement_wrapper.rotation_degrees = 0.0
			judgement_wrapper.position = final_pos

	# ─────────────────────────────────────────────────────────────
	# Preview tick (includes JudgementLabel)
	# ─────────────────────────────────────────────────────────────

	func _tick_preview() -> void:
		if _gl_preview == null or not is_instance_valid(_gl_preview):
			_snapshot_targets_and_baselines()
			_wrap_preview_judgement_label()
			_build_preview_chains()
			_build_preview_rot_chains()
			if _gl_preview == null:
				return
		if target_nodes.is_empty():
			return

		var playhead: float = _current_playhead()
		var sfac: float = _eval_scale_factor_at(playhead)

		_tick_preview_scale_gl(playhead, sfac)

		for name in target_nodes.keys():
			var node := target_nodes[name] as Node2D
			if node == null or not is_instance_valid(node):
				continue

			var base_pos: Vector2 = baseline_pos.get(name, Vector2.ZERO)
			var base_rot: float = baseline_rot.get(name, 0.0)

			var segs: Array = chains_preview.get(name, [])
			var pos_now: Vector2 = base_pos
			if not segs.is_empty():
				if playhead <= float(segs[0]["t0"]):
					pos_now = base_pos
				else:
					var placed := false
					for i in range(segs.size()):
						var s = segs[i]
						var t0 := float(s["t0"])
						var t1 := float(s["t1"])
						var b: Vector2 = s["base"]
						var e: Vector2 = s["end"]

						if playhead < t0:
							pos_now = (segs[i - 1]["end"] if i > 0 else base_pos)
							placed = true
							break
						elif playhead <= t1:
							var t := _progress(playhead, t0, t1)
							var eased := _ease_eval(String(s["ease"]), t)
							pos_now = b.lerp(e, eased)
							placed = true
							break
						else:
							pos_now = e
					if not placed:
						pos_now = segs[segs.size() - 1]["end"]

			var rsegs: Array = rot_chains.get(name, [])
			var angle_now_deg: float = 0.0
			var have_rot := false
			var pivot_gl_from: Dictionary = {}

			if not rsegs.is_empty() and playhead >= float(rsegs[0]["t0"]):
				var last_seg: Dictionary = {}
				for rs in rsegs:
					var rt0 := float(rs["t0"])
					var rt1 := float(rs["t1"])

					if playhead < rt0:
						break

					if playhead <= rt1:
						var pr := _progress(playhead, rt0, rt1)
						var re := _ease_eval(String(rs["ease"]), pr)
						angle_now_deg = lerp(float(rs["a0"]), float(rs["a1"]), re)
						have_rot = true
						pivot_gl_from = rs
						break
					else:
						angle_now_deg = float(rs["a1"])
						last_seg = rs

				if not have_rot and not last_seg.is_empty():
					have_rot = true
					pivot_gl_from = last_seg
			else:
				var g := _eval_global_rot_at(playhead)
				if g.get("ok", false):
					have_rot = true
					angle_now_deg = float(g["angle"])
					pivot_gl_from = g["seg"]

			if have_rot:
				var gl2d := _gl_node2d()
				var parent2d := node.get_parent() as Node2D
				if gl2d != null and parent2d != null:
					var pv_gl := _pivot_gl_from_seg(pivot_gl_from)
					var pv_parent := parent2d.to_local(gl2d.to_global(pv_gl))
					var rel := pos_now - pv_parent
					pos_now = pv_parent + rel.rotated(deg_to_rad(angle_now_deg))

			if node.position != pos_now:
				node.position = pos_now
			var rot_target := base_rot
			if PREVIEW_ROTATES_ORIENTATION and have_rot:
				rot_target += angle_now_deg
			if abs(node.rotation_degrees - rot_target) > 0.001:
				node.rotation_degrees = rot_target

		# Tick preview JudgementLabel
		_tick_preview_judgement_label(playhead, sfac)

	func _start_poll() -> void:
		if _poll_timer != null:
			return
		_poll_timer = Timer.new()
		_poll_timer.wait_time = 0.25
		_poll_timer.one_shot = false
		add_child(_poll_timer)
		_poll_timer.timeout.connect(Callable(self, "_poll_bind"))
		_poll_timer.start()

	func _stop_poll() -> void:
		if _poll_timer == null:
			return
		_poll_timer.stop()
		_poll_timer.queue_free()
		_poll_timer = null

	func _poll_bind() -> void:
		if _bound:
			if popup == null or not popup.is_inside_tree():
				# Restore transforms to baseline BEFORE unwrapping
				_restore_playtest_wrapper_to_baseline()
				_unwrap_playtest_judgement_label()
				_unwrap_if_any()
				_bound = false
			return
		_bind_once()

	func _bind_once() -> void:
		popup = null
		rg_logic = null
		game_layer = null
		wrapper = null
		judgement_label = null
		judgement_wrapper = null

		if editor == null:
			return

		var pv := editor.get("rhythm_game_playtest_popup")
		if pv == null:
			return
		var p := pv as Node
		if p == null or not p.is_inside_tree():
			return
		popup = p

		var rg_prop := p.get("rhythm_game")
		if rg_prop is Node:
			rg_logic = rg_prop as Node

		var rg_ui := popup.find_child("RhythmGame", true, false)
		var search_root: Node = rg_ui if rg_ui != null else popup

		var gl_node := search_root.find_child("GameLayer", true, false)
		game_layer = gl_node as Node2D
		if game_layer == null:
			return

		var parent: Node = game_layer.get_parent()
		if parent == null:
			return

		var existing: Node = parent.get_node_or_null(WRAPPER_NAME)
		if existing is Node2D and (existing as Node2D).is_ancestor_of(game_layer):
			wrapper = existing as Node2D
		else:
			if not (existing is Node2D):
				wrapper = Node2D.new()
				wrapper.name = WRAPPER_NAME
				parent.add_child(wrapper)
				parent.move_child(wrapper, game_layer.get_index())
			else:
				wrapper = existing as Node2D
				parent.move_child(wrapper, game_layer.get_index())

			var gp: Vector2 = game_layer.get_global_position()
			parent.remove_child(game_layer)
			wrapper.add_child(game_layer)
			game_layer.set_global_position(gp)

		_baseline_px = wrapper.position
		_baseline_scale_wrapper = (wrapper.scale.x if wrapper.scale.x != 0.0 else 1.0)
		_baseline_game_layer_pos = game_layer.position
		_baseline_scale_game_layer = (game_layer.scale.x if game_layer.scale.x != 0.0 else 1.0)

		_build_chain_pt()
		_build_chain_rot_pt()
		_snapshot_playtest_targets()

		# Wrap JudgementLabel for playtest
		_wrap_playtest_judgement_label(search_root)

		_seed_editor_ms = _read_editor_ms()
		_last_editor_ms = _seed_editor_ms
		_wall_bind_ms = Time.get_ticks_msec()
		_audio_ready = false
		_last_clock_ms = -1.0
		_bound = true

		if _seed_editor_ms >= 0.0:
			wrapper.position = _eval_pos_pt(_seed_editor_ms)
			_tick_playtest_judgement_label(_seed_editor_ms)

	func _unwrap_if_any() -> void:
		if wrapper != null and is_instance_valid(wrapper) and game_layer != null and is_instance_valid(game_layer):
			if game_layer.get_parent() == wrapper:
				var parent: Node = wrapper.get_parent()
				if parent != null:
					var gp: Vector2 = game_layer.get_global_position()
					wrapper.remove_child(game_layer)
					parent.add_child(game_layer)
					parent.move_child(game_layer, wrapper.get_index())
					game_layer.set_global_position(gp)

	func _build_chain_pt() -> void:
		chain_pt.clear()
		if game_layer == null or wrapper == null:
			return

		var parent_node: Node = wrapper.get_parent()
		var parent2d: Node2D = parent_node as Node2D
		if parent2d == null:
			parent2d = wrapper

		var prev_end: Vector2 = _baseline_px

		for r in rows:
			var base_pos: Vector2 = prev_end
			var endpoint_parent: Vector2

			if parent2d == wrapper:
				var endpoint_global := game_layer.to_global(r.endpoint)
				var endpoint_wrapper_local := wrapper.to_local(endpoint_global)
				endpoint_parent = _baseline_px + endpoint_wrapper_local
			else:
				endpoint_parent = parent2d.to_local(game_layer.to_global(r.endpoint))

			var end_pos: Vector2 = endpoint_parent if USE_ABSOLUTE_CHAIN else base_pos + endpoint_parent

			var seg := {
				"t0": r.start_time,
				"t1": r.end_time,
				"base": base_pos,
				"end": end_pos,
				"ease": r.ease,
			}
			chain_pt.append(seg)
			prev_end = end_pos

	func _build_chain_rot_pt() -> void:
		rot_chain_pt.clear()
		if game_layer == null or wrapper == null:
			return

		var parent2d := wrapper.get_parent() as Node2D
		if parent2d == null:
			return

		for rr in rot_rows:
			var pivot_parent := parent2d.to_local(game_layer.to_global(rr.pivot_gl_local))

			var seg := {
				"t0": rr.start_time,
				"t1": rr.end_time,
				"a0": rr.a0_deg,
				"a1": rr.a1_deg,
				"ease": rr.ease,
				"pivot_parent": pivot_parent,
			}
			rot_chain_pt.append(seg)

		rot_chain_pt.sort_custom(func(a, b):
			return float(a["t0"]) < float(b["t0"])
		)

	func _process(_dt: float) -> void:
		_tick_preview()

		if not _bound or wrapper == null or not is_instance_valid(wrapper):
			return

		var t: float = _seeded_time_ms()
		if t < 0.0:
			return

		var pos := _eval_pos_pt(t)
		if wrapper.position != pos:
			wrapper.position = pos

		_tick_playtest_scale_gl(t)
		_tick_playtest_rotation(t)
		_tick_playtest_judgement_label(t)

		_last_clock_ms = t

	func _eval_pos_pt(t: float) -> Vector2:
		if chain_pt.is_empty():
			return _baseline_px
		if t <= float(chain_pt[0]["t0"]):
			return _baseline_px
		var last_end: Vector2 = _baseline_px
		for i in range(chain_pt.size()):
			var s = chain_pt[i]
			var t0 := float(s["t0"])
			var t1 := float(s["t1"])
			var b: Vector2 = s["base"]
			var e: Vector2 = s["end"]
			if t < t0:
				return last_end
			elif t <= t1:
				var pr := _progress(t, t0, t1)
				var eased := _ease_eval(String(s["ease"]), pr)
				return b.lerp(e, eased)
			else:
				last_end = e
		return chain_pt[chain_pt.size() - 1]["end"]

	func _seeded_time_ms() -> float:
		var a: float = _audio_time_ms()
		if a > 0.0:
			_audio_ready = true
			_last_editor_ms = -1.0
			return a

		var ed: float = _read_editor_ms()
		if ed >= 0.0:
			if _last_editor_ms < 0.0 or abs(ed - _last_editor_ms) > 0.001:
				_last_editor_ms = ed
				_wall_bind_ms = Time.get_ticks_msec()
				return ed
			if _wall_bind_ms >= 0.0:
				var elapsed := float(Time.get_ticks_msec() - _wall_bind_ms)
				return _last_editor_ms + elapsed
			return ed

		if _wall_bind_ms >= 0.0:
			return float(Time.get_ticks_msec() - _wall_bind_ms)

		return _last_clock_ms

	func _audio_time_ms() -> float:
		if rg_logic != null:
			var shin := _get_shinobu()
			if shin != null:
				var sec := _shinobu_seconds(shin)
				if sec > 0.0:
					var hi: float = sec \
						+ AudioServer.get_time_since_last_mix() \
						- AudioServer.get_time_to_next_mix() \
						- AudioServer.get_output_latency() \
						+ (LATENCY_BIAS_MS / 1000.0)
					var ms: float = hi * 1000.0
					if ms > 0.0:
						return ms

			var ap := rg_logic.get("audio_playback")
			if ap != null and (ap as Object).has_method("get_playback_position"):
				var base_s := float((ap as Object).call("get_playback_position"))
				if base_s > 0.0:
					var hi2: float = base_s \
						+ AudioServer.get_time_since_last_mix() \
						- AudioServer.get_time_to_next_mix() \
						- AudioServer.get_output_latency() \
						+ (LATENCY_BIAS_MS / 1000.0)
					var ms2: float = hi2 * 1000.0
					if ms2 > 0.0:
						return ms2

			var game_v := rg_logic.get("game")
			if game_v != null:
				var g := game_v as Object
				if g.has_method("get_time_msec"):
					var tg := float(g.call("get_time_msec"))
					if tg > 0.0:
						return tg
				if g.has_method("get_time_ms"):
					var tg2 := float(g.call("get_time_ms"))
					if tg2 > 0.0:
						return tg2

		if popup != null:
			var asp := _find_first_audio_player(popup)
			if asp != null and asp.playing:
				var base_s2 := asp.get_playback_position()
				if base_s2 > 0.0:
					var hi_s2: float = base_s2 \
						+ AudioServer.get_time_since_last_mix() \
						- AudioServer.get_time_to_next_mix() \
						- AudioServer.get_output_latency() \
						+ (LATENCY_BIAS_MS / 1000.0)
					var ms3: float = hi_s2 * 1000.0
					if ms3 > 0.0:
						return ms3

		return 0.0

	func _read_editor_ms() -> float:
		if editor == null:
			return -1.0
		var p := editor.get("playhead_position")
		if typeof(p) == TYPE_INT or typeof(p) == TYPE_FLOAT:
			return float(p)
		return -1.0

	func _get_shinobu() -> Object:
		if rg_logic == null:
			return null
		if SHINOBU_REL_PATH != "":
			var n := rg_logic.get_node_or_null(SHINOBU_REL_PATH)
			if n != null:
				return n
		var stack: Array[Node] = [rg_logic]
		var visited := 0
		while stack.size() > 0 and visited < 5000:
			var node := stack.pop_back()
			visited += 1
			if node != null:
				var cname := str(node.get_class())
				if cname.findn("ShinobuSoundPlayer") != -1:
					return node
				for c_v in node.get_children():
					var c := c_v as Node
					if c != null:
						stack.append(c)
		return null

	func _shinobu_seconds(shin: Object) -> float:
		var methods: Array[String] = ["get_playback_position", "get_play_time", "get_song_time", "get_position", "get_time_seconds", "get_time"]
		for m in methods:
			if shin.has_method(m):
				var v := shin.call(m)
				if typeof(v) == TYPE_FLOAT:
					return float(v)
				elif typeof(v) == TYPE_INT:
					return float(v)
		var props: Array[String] = ["playback_position", "play_time", "song_time", "position", "time_seconds", "time"]
		for n in props:
			if shin.has_method("get"):
				var v2 := shin.get(n)
				if typeof(v2) == TYPE_FLOAT:
					return float(v2)
				elif typeof(v2) == TYPE_INT:
					return float(v2)
		return 0.0

	func _find_first_audio_player(root: Node) -> AudioStreamPlayer:
		var stack: Array[Node] = [root]
		var visited := 0
		while stack.size() > 0 and visited < 10000:
			var n := stack.pop_back()
			visited += 1
			if n is AudioStreamPlayer:
				return n as AudioStreamPlayer
			for c_v in n.get_children():
				var c := c_v as Node
				if c != null:
					stack.append(c)
		return null
