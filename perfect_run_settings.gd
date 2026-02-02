extends HBSerializable
class_name PerfectRunSettings

var cool_only: bool = false
var fine_limit: int = 0
var show_fine_counter: bool = true  # NEW

func _init() -> void:
    serializable_fields += ["cool_only", "fine_limit", "show_fine_counter"]

func get_serialized_type():
    return "PerfectRunSettings"