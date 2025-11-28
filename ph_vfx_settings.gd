extends HBSerializable

# NOTE: no `class_name` here – we keep this anonymous so the
# runtime doesn’t need to know any new global class type.

var enabled: bool = true
var vfx_json_override: String = ""

func _init() -> void:
	serializable_fields += ["enabled", "vfx_json_override"]

func get_serialized_type() -> String:
	return "PHVFXModifierSettings"
