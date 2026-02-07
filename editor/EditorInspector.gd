extends Control

const INSPECTOR_TYPES = {
	"int": preload("res://tools/editor/inspector_types/int.tscn"),
	"Vector2": preload("res://tools/editor/inspector_types/Vector2.tscn"),
	"float": preload("res://tools/editor/inspector_types/float.tscn"),
	"Angle": preload("res://tools/editor/inspector_types/angle.tscn"),
	"bool": preload("res://tools/editor/inspector_types/bool.tscn"),
	"String": preload("res://tools/editor/inspector_types/String.tscn"),
	"Color": preload("res://tools/editor/inspector_types/Color.tscn"),
	"list": preload("res://tools/editor/inspector_types/list.tscn"),
	"time_signature": preload("res://tools/editor/inspector_types/time_signature.tscn"),
}

@onready var title_label = get_node("MarginContainer/ScrollContainer/VBoxContainer/TitleLabel")
@onready var property_container = get_node("MarginContainer/ScrollContainer/VBoxContainer/PropertyContainer")
@onready var copy_icon = get_node("MarginContainer/ScrollContainer/VBoxContainer/HBoxContainer/CopyIcon")
@onready var paste_icon = get_node("MarginContainer/ScrollContainer/VBoxContainer/HBoxContainer/PasteIcon")
@onready var description_label = get_node("MarginContainer/ScrollContainer/VBoxContainer/DescriptionLabel")

var inspecting_items: Array
var queued_items_to_inspect: Array
var inspector_update_queued := false
var inspecting_properties = {}
var labels = {}
var condition_properties = {}
var conditional_properties = {}

# Rush note info display
var rush_info_container: VBoxContainer = null
var rush_info_labels: Dictionary = {}

# Note info display (timeout, etc. - for all notes)
var note_info_container: VBoxContainer = null
var note_info_labels: Dictionary = {}

# Sustain note info display
var sustain_info_container: VBoxContainer = null
var sustain_info_labels: Dictionary = {}


signal properties_changed(property, values)
signal property_change_committed(property)
signal notes_pasted(notes)
signal reset_pos()

var copied_notes: Array

func get_inspector_type(type: String):
	return INSPECTOR_TYPES[type]

func _ready():
	copy_icon.connect("pressed", Callable(self, "_on_copy_pressed"))
	paste_icon.connect("pressed", Callable(self, "_on_paste_pressed"))
	copy_icon.disabled = true
	paste_icon.disabled = true

func get_common_inspecting_class_desc():
	if not inspecting_items:
		var item := EditorTimelineItem.new()
		var desc := item.get_ph_editor_description()
		item.queue_free()
		return desc
	var common_class = inspecting_items[0]._class_name
	
	var i = 1
	var inheritance_size = inspecting_items[0]._inheritance.size()
	for item in inspecting_items:
		var _data_class = item._class_name
		
		while (not common_class in item._inheritance) and _data_class != common_class:
			if inheritance_size - i < 0:
				break
			
			common_class = inspecting_items[0]._inheritance[inheritance_size - i]
			i += 1
	
	var instance = load("res://tools/editor/timeline_items/%s.gd" % common_class).new()
	var desc := instance.get_ph_editor_description() as String
	instance.queue_free()
	return desc

func get_common_data_class():
	if not inspecting_items:
		return HBTimingPoint.new()
	
	var common_data_class = inspecting_items[0].data._class_name
	
	var i = 1
	var inheritance_size = inspecting_items[0].data._inheritance.size()
	for item in inspecting_items:
		var _data_class = item.data._class_name
		
		while (not common_data_class in item.data._inheritance) and _data_class != common_data_class:
			common_data_class = inspecting_items[0].data._inheritance[inheritance_size - i]
			i += 1
	
	var path = "res://rythm_game/lyrics/%s.gd" if "Lyrics" in common_data_class else "res://scripts/timing_points/%s.gd"
	var instance = load(path % common_data_class).new()
	return instance

func get_property_range(property_name: String):
	if not inspecting_items:
		return []
	
	var _max = inspecting_items[0].data.get(property_name)
	var _min = inspecting_items[0].data.get(property_name)
	
	for item in inspecting_items:
		_max = max(_max, item.data.get(property_name))
		_min = min(_min, item.data.get(property_name))
	
	return [_min, _max]

func _on_copy_pressed():
	copied_notes.clear()
	for item in inspecting_items:
		copied_notes.append(item.data.clone())
	
	paste_icon.disabled = false

func _on_paste_pressed():
	emit_signal("notes_pasted", copied_notes)

func update_label():
	var item_description = get_common_inspecting_class_desc()
	description_label.text = ""
	if item_description != "":
		description_label.text += "%s" % [item_description]
		description_label.visible = true
	else:
		description_label.visible = false
	
	if inspecting_items.size() == 0:
		title_label.text = ""
	elif inspecting_items.size() == 1:
		var time = HBUtils.format_time(inspecting_items[0].data.time, HBUtils.TimeFormat.FORMAT_MINUTES | HBUtils.TimeFormat.FORMAT_SECONDS | HBUtils.TimeFormat.FORMAT_MILISECONDS)
		title_label.text = "Item at %s" % time
	else:
		var times = get_property_range("time")
		times[0] = HBUtils.format_time(times[0], HBUtils.TimeFormat.FORMAT_MINUTES | HBUtils.TimeFormat.FORMAT_SECONDS | HBUtils.TimeFormat.FORMAT_MILISECONDS)
		times[1] = HBUtils.format_time(times[1], HBUtils.TimeFormat.FORMAT_MINUTES | HBUtils.TimeFormat.FORMAT_SECONDS | HBUtils.TimeFormat.FORMAT_MILISECONDS)
		title_label.text = "Items from %s to %s" % times

func stop_inspecting():
	for item in inspecting_items:
		if item and is_instance_valid(item):
			item.disconnect("property_changed", Callable(self, "update_value"))
	inspecting_items = []
	
	for child in property_container.get_children():
		property_container.remove_child(child)
		child.queue_free()
	
	inspecting_properties.clear()
	labels.clear()
	condition_properties.clear()
	conditional_properties.clear()
	
	# Clear rush info
	rush_info_container = null
	rush_info_labels.clear()
	
	# Clear note info
	note_info_container = null
	note_info_labels.clear()
	
	# Clear sustain info
	sustain_info_container = null
	sustain_info_labels.clear()
	
	copy_icon.disabled = true
	paste_icon.disabled = true
	
	update_label()

func sync_visible_values_with_data():
	var inputs = []
	for item in inspecting_items:
		inputs.append(item.data.clone())
	
	for property_name in inspecting_properties:
		sync_value(property_name, inputs)
	
	# Also refresh info sections
	_refresh_note_info()
	_refresh_sustain_info()
	_refresh_rush_info()

# Syncs a single property
func sync_value(property_name: String, inputs: Array):
	inspecting_properties[property_name].sync_value(inputs)
	
	if property_name in condition_properties:
		pass
	
	update_label()

func inspect(items: Array):
	queued_items_to_inspect = items
	if not inspector_update_queued:
		inspector_update_queued = true
		_inspector_update_deferred.call_deferred()

func _inspector_update_deferred():
	inspect_internal(queued_items_to_inspect)
	inspector_update_queued = false

func inspect_internal(items: Array):
	if inspecting_items == items:
		return
	else:
		inspecting_items = items.duplicate()
	
	var common_data_class = get_common_data_class()
	
	if common_data_class is HBBaseNote:
		copy_icon.disabled = false
		paste_icon.disabled = false
	else:
		copy_icon.disabled = true
		paste_icon.disabled = true
	
	if not copied_notes:
		paste_icon.disabled = true
	
	inspecting_properties.clear()
	labels.clear()
	condition_properties.clear()
	conditional_properties.clear()
	
	update_label()
	
	for child in property_container.get_children():
		child.free()
	
	for item in inspecting_items:
		if not item.is_connected("property_changed", Callable(self, "update_value")):
			item.connect("property_changed", Callable(self, "update_value"))
	
	var properties = common_data_class.get_inspector_properties()
	for property_name in properties.keys():
		var property = properties[property_name]
		var inspector_editor = get_inspector_type(property.type).instantiate()
		inspector_editor.property_name = property_name
		
		var name = property_name.capitalize()
		if property.has("params"):
			inspector_editor.call_deferred("set_params", property.params)
			
			if property.params.has("name"):
				name = property.params.name
			
			if property.params.has("affects_properties"):
				condition_properties[property_name] = property.params.affects_properties
				for conditional_property in property.params.affects_properties:
					conditional_properties[conditional_property] = properties[conditional_property].params.condition
			
			if property.params.has("affected_by_properties"):
				for condition_property in property.params.affected_by_properties:
					if not condition_properties.has(condition_property):
						condition_properties[condition_property] = []
					
					condition_properties[condition_property].append(property_name)
				
				conditional_properties[property_name] = property.params.condition
		
		var label = Label.new()
		label.text = name
		property_container.add_child(label)
		labels[property_name] = label
		
		inspector_editor.connect("values_changed", Callable(self, "_on_property_value_changed_by_user").bind(property_name))
		inspector_editor.connect("value_change_committed", Callable(self, "_on_property_value_commited_by_user").bind(property_name))
		property_container.add_child(inspector_editor)
		inspecting_properties[property_name] = inspector_editor
		
		if property_name == "position":
			var reset_position_button = Button.new()
			reset_position_button.text = "Reset to default"
			reset_position_button.connect("pressed", Callable(self, "_on_reset_pos_pressed"))
			reset_position_button.size_flags_horizontal = reset_position_button.SIZE_EXPAND_FILL
			property_container.add_child(reset_position_button)
	
	# Add note info section (timeout) for all notes
	_update_note_info_section(common_data_class)
	
	# Add sustain note info section if applicable
	_update_sustain_info_section(common_data_class)
	
	# Add rush note info section if applicable
	_update_rush_info_section(common_data_class)
	
	check_conditional_properties()
	
	sync_visible_values_with_data()

func _on_property_value_changed_by_user(values, property_name):
	emit_signal("properties_changed", property_name, values)
	
	if property_name in condition_properties:
		check_conditional_properties()
	
	# Update rush info if relevant properties changed
	if property_name in ["time", "end_time", "auto_rush_hit_cap", "custom_rush_hit_cap"]:
		_refresh_rush_info()
	
	# Update sustain info if relevant properties changed
	if property_name in ["time", "end_time"]:
		_refresh_sustain_info()
	
	# Update note info if time changed (affects timeout calculation)
	if property_name == "time":
		_refresh_note_info()

func _on_property_value_commited_by_user(property_name):
	emit_signal("property_change_committed", property_name)

func _on_reset_pos_pressed():
	emit_signal("reset_pos")

func check_conditional_properties():
	var condition_differences := []
	var condition_equalities := []
	var property_values := []
	for property_name in condition_properties.keys():
		var first_value = inspecting_items[0].data.get(property_name)
		
		var found_diff := false
		for item in inspecting_items:
			if item.data.get(property_name) != first_value:
				condition_differences.append_array(condition_properties[property_name])
				found_diff = true
				break
		
		if not found_diff:
			condition_equalities.append(property_name)
			property_values.append(first_value)
	
	for property_name in conditional_properties.keys():
		var property = inspecting_properties[property_name]
		var label = labels[property_name]
		
		if property_name in condition_differences:
			property.visible = false
			label.visible = false
			continue
		
		var condition = conditional_properties[property_name]
		var expression := Expression.new()
		expression.parse(condition, condition_equalities)
		var result = expression.execute(property_values)
		
		property.visible = bool(result)
		label.visible = bool(result)


# ─────────────────────────────────────────────
# Note Info Display (Timeout - for all notes)
# ─────────────────────────────────────────────

func _update_note_info_section(common_data_class) -> void:
	# Clear existing note info
	if note_info_container != null:
		note_info_container.queue_free()
		note_info_container = null
	note_info_labels.clear()
	
	# Only show for notes (HBBaseNote and descendants)
	if not (common_data_class is HBBaseNote):
		return
	
	# Create container for note info
	note_info_container = VBoxContainer.new()
	note_info_container.name = "NoteInfoContainer"
	property_container.add_child(note_info_container)
	
	# Add separator
	var separator = HSeparator.new()
	note_info_container.add_child(separator)
	
	# Add header
	var header = Label.new()
	header.text = "Note Info (Calculated)"
	header.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	note_info_container.add_child(header)
	
	# Timeout label
	var timeout_label = Label.new()
	timeout_label.name = "TimeoutLabel"
	note_info_labels["timeout"] = timeout_label
	note_info_container.add_child(timeout_label)
	
	# Update values
	_refresh_note_info()


func _refresh_note_info() -> void:
	if note_info_container == null or inspecting_items.is_empty():
		return
	
	# Check if we're inspecting notes
	var first_note = inspecting_items[0].data
	if not (first_note is HBBaseNote):
		return
	
	# For multiple selection, show range
	if inspecting_items.size() == 1:
		var t_ms: int = first_note.time
		var ntype: int = first_note.note_type if "note_type" in first_note else -1
		var timeout_ms := _compute_timeout_ms(ntype, first_note, t_ms)
		
		note_info_labels["timeout"].text = "Timeout: %d ms" % timeout_ms
	else:
		# Multiple selection - show ranges
		var min_timeout: int = 999999999
		var max_timeout: int = 0
		
		for item in inspecting_items:
			var note = item.data
			if note is HBBaseNote:
				var t_ms: int = note.time
				var ntype: int = note.note_type if "note_type" in note else -1
				var timeout_ms := _compute_timeout_ms(ntype, note, t_ms)
				min_timeout = mini(min_timeout, timeout_ms)
				max_timeout = maxi(max_timeout, timeout_ms)
		
		if min_timeout == max_timeout:
			note_info_labels["timeout"].text = "Timeout: %d ms" % min_timeout
		else:
			note_info_labels["timeout"].text = "Timeout: %d - %d ms" % [min_timeout, max_timeout]


func _compute_timeout_ms(note_type: int, note_obj: Object, t_ms: int) -> int:
	# Try to get timeout from the editor's rhythm_game
	var rg := _get_rg()
	if rg != null:
		# Method 1: get_time_out_for(note_type, time)
		if (rg as Object).has_method("get_time_out_for"):
			var ms := int(round(float((rg as Object).call("get_time_out_for", note_type, t_ms))))
			if ms > 0:
				return ms

		# Get note speed for other methods
		var speed := 1.0
		if (rg as Object).has_method("get_note_speed_at_time"):
			speed = float((rg as Object).call("get_note_speed_at_time", t_ms))

		# Method 2: note.get_time_out(speed)
		if note_obj != null and (note_obj as Object).has_method("get_time_out"):
			var ms2 := int(round(float((note_obj as Object).call("get_time_out", speed))))
			if ms2 > 0:
				return ms2

		# Method 3: rg.get_time_out(speed, time) or rg.get_time_out(speed)
		if (rg as Object).has_method("get_time_out"):
			var try_ms := float((rg as Object).call("get_time_out", speed, t_ms))
			if try_ms <= 0.0:
				try_ms = float((rg as Object).call("get_time_out", speed))
			var ms3 := int(round(try_ms))
			if ms3 > 0:
				return ms3

	# Hard fallback
	return 2000


func _get_rg() -> Object:
	# Try to find the editor through our parent hierarchy
	var editor = _find_editor()
	if editor == null:
		return null
	
	var rg = editor.get("rhythm_game")
	if rg is Object:
		return rg
	
	var pv = editor.get("rhythm_game_playtest_popup")
	if pv is Node:
		var r2 = (pv as Node).get("rhythm_game")
		if r2 is Object:
			return r2
	
	var gp = editor.find_child("GamePreview", true, false)
	if gp != null and gp.has_method("get"):
		var r3 = gp.get("rhythm_game")
		if r3 is Object:
			return r3
	
	return null


func _find_editor() -> Node:
	# Walk up the tree to find the editor
	var node: Node = self
	while node != null:
		if node.has_method("get_timing_map"):
			return node
		# Check for common editor class names
		var node_class := node.get_class()
		if "Editor" in String(node.name) or "Editor" in node_class:
			return node
		node = node.get_parent()
	return null


# ─────────────────────────────────────────────
# Sustain Note Info Display
# ─────────────────────────────────────────────

func _update_sustain_info_section(common_data_class) -> void:
	# Clear existing sustain info
	if sustain_info_container != null:
		sustain_info_container.queue_free()
		sustain_info_container = null
	sustain_info_labels.clear()
	
	# Only show for sustain notes (but NOT rush notes, which have their own section)
	if not (common_data_class is HBSustainNote):
		return
	if common_data_class is HBRushNote:
		return
	
	# Create container for sustain info
	sustain_info_container = VBoxContainer.new()
	sustain_info_container.name = "SustainInfoContainer"
	property_container.add_child(sustain_info_container)
	
	# Add separator
	var separator = HSeparator.new()
	sustain_info_container.add_child(separator)
	
	# Add header
	var header = Label.new()
	header.text = "Sustain Info (Calculated)"
	header.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	sustain_info_container.add_child(header)
	
	# Duration label
	var duration_label = Label.new()
	duration_label.name = "DurationLabel"
	sustain_info_labels["duration"] = duration_label
	sustain_info_container.add_child(duration_label)
	
	# Update values
	_refresh_sustain_info()


func _refresh_sustain_info() -> void:
	if sustain_info_container == null or inspecting_items.is_empty():
		return
	
	# Check if we're inspecting sustain notes
	var sustain_note = inspecting_items[0].data
	if not (sustain_note is HBSustainNote):
		return
	if sustain_note is HBRushNote:
		return
	
	# For multiple selection, show range or indicate mixed values
	if inspecting_items.size() == 1:
		var duration_ms: int = sustain_note.end_time - sustain_note.time
		
		sustain_info_labels["duration"].text = "Duration: %d ms" % duration_ms
	else:
		# Multiple selection - show ranges
		var min_duration: int = 999999999
		var max_duration: int = 0
		
		for item in inspecting_items:
			var note = item.data
			if note is HBSustainNote and not (note is HBRushNote):
				var dur: int = note.end_time - note.time
				min_duration = mini(min_duration, dur)
				max_duration = maxi(max_duration, dur)
		
		if min_duration == max_duration:
			sustain_info_labels["duration"].text = "Duration: %d ms" % min_duration
		else:
			sustain_info_labels["duration"].text = "Duration: %d - %d ms" % [min_duration, max_duration]


# ─────────────────────────────────────────────
# Rush Note Info Display
# ─────────────────────────────────────────────

func _update_rush_info_section(common_data_class) -> void:
	# Clear existing rush info
	if rush_info_container != null:
		rush_info_container.queue_free()
		rush_info_container = null
	rush_info_labels.clear()
	
	# Only show for rush notes
	if not (common_data_class is HBRushNote):
		return
	
	# Create container for rush info
	rush_info_container = VBoxContainer.new()
	rush_info_container.name = "RushInfoContainer"
	property_container.add_child(rush_info_container)
	
	# Add separator
	var separator = HSeparator.new()
	rush_info_container.add_child(separator)
	
	# Add header
	var header = Label.new()
	header.text = "Rush Info (Calculated)"
	header.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	rush_info_container.add_child(header)
	
	# Duration label
	var duration_label = Label.new()
	duration_label.name = "DurationLabel"
	rush_info_labels["duration"] = duration_label
	rush_info_container.add_child(duration_label)
	
	# Hit count label
	var hit_count_label = Label.new()
	hit_count_label.name = "HitCountLabel"
	rush_info_labels["hit_count"] = hit_count_label
	rush_info_container.add_child(hit_count_label)
	
	# Score label
	var score_label = Label.new()
	score_label.name = "ScoreLabel"
	rush_info_labels["score"] = score_label
	rush_info_container.add_child(score_label)
	
	# Update values
	_refresh_rush_info()


func _refresh_rush_info() -> void:
	if rush_info_container == null or inspecting_items.is_empty():
		return
	
	# Check if we're inspecting rush notes
	var rush_note = inspecting_items[0].data
	if not (rush_note is HBRushNote):
		return
	
	# For multiple selection, show range or indicate mixed values
	if inspecting_items.size() == 1:
		var duration_ms: int = rush_note.end_time - rush_note.time
		var hit_count: int = rush_note.calculate_capped_hit_count()
		var score: int = hit_count * 30
		
		rush_info_labels["duration"].text = "Duration: %d ms" % duration_ms
		rush_info_labels["hit_count"].text = "Hit Count: %d hits" % hit_count
		rush_info_labels["score"].text = "Score: %d" % score
	else:
		# Multiple selection - show ranges
		var min_duration: int = 999999999
		var max_duration: int = 0
		var min_hits: int = 999999999
		var max_hits: int = 0
		
		for item in inspecting_items:
			var note = item.data
			if note is HBRushNote:
				var dur: int = note.end_time - note.time
				var hits: int = note.calculate_capped_hit_count()
				min_duration = mini(min_duration, dur)
				max_duration = maxi(max_duration, dur)
				min_hits = mini(min_hits, hits)
				max_hits = maxi(max_hits, hits)
		
		if min_duration == max_duration:
			rush_info_labels["duration"].text = "Duration: %d ms" % min_duration
		else:
			rush_info_labels["duration"].text = "Duration: %d - %d ms" % [min_duration, max_duration]
		
		if min_hits == max_hits:
			rush_info_labels["hit_count"].text = "Hit Count: %d hits" % min_hits
			rush_info_labels["score"].text = "Score: %d" % (min_hits * 30)
		else:
			rush_info_labels["hit_count"].text = "Hit Count: %d - %d hits" % [min_hits, max_hits]
			rush_info_labels["score"].text = "Score: %d - %d" % [min_hits * 30, max_hits * 30]
