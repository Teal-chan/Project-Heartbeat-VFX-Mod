extends EditorTimelineItem

class_name EditorTimelineItemMetadata

const HBMetadataClass = preload("res://scripts/timing_points/HBMetadata.gd")
const WIDTH = 5.0
const CLICK_WIDTH = 80.0  # Wider area for clicking

func _init():
	_class_name = "EditorTimelineItemMetadata"
	_inheritance = ["EditorTimelineItem"]

func _ready():
	super._ready()
	update_label()
	# Explicitly enable input handling
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process_input(true)

func _gui_input(event: InputEvent):
	super._gui_input(event)

func update_label():
	if has_node("Label") and data:
		if data is HBMetadataClass:
			var key = data.meta.get("key", "")
			$Label.text = key if key else "metadata"

func sync_value(property: String):
	if property == "meta":
		update_label()

func get_timeline_item_size():
	return Vector2(CLICK_WIDTH, size.y)

func get_editor_size():
	return Vector2(CLICK_WIDTH, size.y)

func get_duration():
	return 100

func get_click_rect():
	return get_global_rect()

func select():
	super.select()
	queue_redraw()  # Redraw to show yellow line

func deselect():
	super.deselect()
	queue_redraw()  # Redraw to show blue line

func _draw():
	# Draw the vertical line at x=0 (the actual time position)
	# Make it yellow when selected, blue when not
	var line_color = Color.YELLOW if _draw_selected_box else Color(0.7, 0.7, 1.0, 1.0)
	var height = size.y
	draw_line(Vector2(0, 0), Vector2(0, height), line_color, 3.0)  # Slightly thicker when drawing
