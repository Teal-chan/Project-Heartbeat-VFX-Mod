# Metadata timing point class
# Used for storing metadata entries that can be read by scripts/systems
extends HBTimingPoint
class_name HBMetadata

signal changed

var key: String = "metadata": set = set_key

func set_key(value: String):
	key = value
	emit_signal("changed")

func _init():
	super._init()
	serializable_fields += ["key"]
	_class_name = "HBMetadata"
	key = "metadata"  # Set default value

func get_serialized_type():
	return "Metadata"

func get_timeline_item():
	return preload("res://tools/editor/timeline_items/EditorTimelineItemMetadata.tscn").instantiate()

func get_inspector_properties():
	var props = super.get_inspector_properties()
	props["key"] = {
		"type": "String",
		"params": {
			"placeholder": "Enter key (e.g., hello, drop, outro)"
		}
	}
	return props
