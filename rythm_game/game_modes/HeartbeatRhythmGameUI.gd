extends HBRhythmGameUIBase

class_name HBRhythmGameUI

@onready var rating_label: HBJudgementLabel = get_node("%JudgementLabel")
@onready var game_layer_node = get_node("%GameLayer")
@onready var slide_hold_score_text = get_node("AboveNotesUI/Control/SlideHoldScoreText")
@onready var intro_skip_ff_animation_player = get_node("UnderNotesUI/Control/Label/IntroSkipFastForwardAnimationPlayer")
@onready var lyrics_view = get_node("Lyrics/Control/LyricsView")
@onready var under_notes_node = get_node("UnderNotesUI")
@onready var aspect_ratio_container: AspectRatioContainer = get_node("AspectRatioContainer")

@onready var game_over_turn_off_node: Control = get_node("CanvasLayer2/GameOverTurnOff")
@onready var game_over_turn_off_top: Control = get_node("CanvasLayer2/GameOverTurnOff/GameOverTurnOffTop")
@onready var game_over_turn_off_bottom: Control = get_node("CanvasLayer2/GameOverTurnOff/GameOverTurnOffBottom")

@onready var game_over_message_node: Control = get_node("CanvasLayer2/GameOverMessage")
@onready var under_notes_user_ui_node = get_node("UnderNotesUI/Control/UserUI")
@onready var over_notes_user_ui_node = get_node("UserUI")

const SCORE_COUNTER_GROUP = "score_counter"
const CLEAR_BAR_GROUP = "clear_bar"
const LATENCY_DISPLAY_GROUP = "accuracy_display"
const DIFFICULTY_LABEL_GROUP = "song_difficulty"
const HOLD_INDICATOR_GROUP = "hold_indicator"
const SONG_PROGRESS_INDICATOR_GROUP = "song_progress"
const SONG_TITLE_GROUP = "song_title"
const MULTI_HINT_GROUP = "multi_hint"
const HEALTH_DISPLAY_GROUP = "health_display"

const SKIP_INTRO_INDICATOR_GROUP = "skip_intro_indicator"

var drawing_layer_nodes = {}

const LOG_NAME = "HeartbeatRhythmGameUI"

var start_time = 0.0
var end_time = 0.0

var game : set = set_game

#warning-ignore:unused_signal
signal tv_off_animation_finished
signal game_over_restart_requested
signal game_over_quit_requested

@onready var tv_animation_tween := Threen.new()
@onready var game_over_message_tween := Threen.new()

var skin_override: HBUISkin

# ─── Game Over Restart/Quit menu (runtime-created) ───
var _go_menu_container: Control = null
var _go_menu_visible := false
# Timer between "GAME OVER" text appearing and menu buttons sliding in
const GAME_OVER_MENU_DELAY := 0.8


func set_game(new_game):
	game = new_game
	slide_hold_score_text._game = game
	game.connect("time_changed", Callable(self, "_on_game_time_changed"))
	get_tree().call_group(LATENCY_DISPLAY_GROUP, "set_judge", game.judge)
func get_notes_node() -> Node2D:
	return get_drawing_layer_node(&"Notes")
	
func get_lyrics_view():
	return lyrics_view
	
func _on_game_time_changed(time: float):
	get_tree().set_group(SONG_PROGRESS_INDICATOR_GROUP, "value", time * 1000.0)
	lyrics_view._on_game_time_changed(int(time*1000.0))

func create_components():
	var skin := ResourcePackLoader.current_skin as HBUISkin
	if skin_override:
		if skin_override.has_screen("gameplay"):
			skin = skin_override
	if not skin.has_screen("gameplay"):
		skin = ResourcePackLoader.fallback_skin
	var cache := skin.resources.get_cache() as HBSkinResourcesCache
	var layered_components := skin.get_components("gameplay", cache)
	for node in layered_components.get("UnderNotes", []):
		under_notes_user_ui_node.add_child(node)
	for node in layered_components.get("OverNotes"):
		over_notes_user_ui_node.add_child(node)
	
func _ready():
	create_components()
	get_tree().set_group(SKIP_INTRO_INDICATOR_GROUP, "position:x", -100000)
	rating_label.hide()
	connect("resized", Callable(self, "_on_size_changed"))
	call_deferred("_on_size_changed")
	
	add_drawing_layer(&"Laser")
	add_drawing_layer(&"Trails")
	add_drawing_layer(&"StarParticles")
	add_drawing_layer(&"HitParticles")
	add_drawing_layer(&"AppearParticles")
	add_drawing_layer(&"SlideChainPieces")
	add_drawing_layer(&"SlideChainParticles")
	add_drawing_layer(&"Notes")
	add_drawing_layer(&"RushText")
	
	game_over_turn_off_node.hide()
	add_child(tv_animation_tween)
	
	tv_animation_tween.connect("tween_all_completed", Callable(self, "emit_signal").bind("tv_off_animation_finished"))
	tv_animation_tween.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(game_over_message_tween)
	game_over_message_tween.process_mode = Node.PROCESS_MODE_ALWAYS
	game_over_message_node.hide()

	get_tree().set_group(LATENCY_DISPLAY_GROUP, "visible", UserSettings.user_settings.show_latency)
	_on_hide_multi_hint()
func add_drawing_layer(layer_name: StringName):
	var layer_node = Node2D.new()
	layer_node.name = "LAYER_" + layer_name
	game_layer_node.add_child(layer_node)
	drawing_layer_nodes[layer_name] = layer_node
	
func get_drawing_layer_node(layer_name: StringName) -> Node2D:
	return drawing_layer_nodes[layer_name]
	
func _on_note_judged(judgement_info):
	get_tree().call_group(LATENCY_DISPLAY_GROUP, "_on_note_judged", judgement_info)
	
	if not is_ui_visible():
		return
	
	var rating_pos: Vector2 = game.remap_coords(judgement_info.avg_pos)
	rating_label.show_judgement(rating_pos, judgement_info.judgement, judgement_info.wrong, game.current_combo)
	if not game.previewing:
		rating_label.show()
	else:
		rating_label.hide()
func _on_size_changed():
	$UnderNotesUI/Control.set_deferred("size", size)
	$AboveNotesUI/Control.set_deferred("size", size)
	$Lyrics/Control.set_deferred("size", size)
		
func _on_reset():
	reset_score_counter()
	get_tree().set_group(CLEAR_BAR_GROUP, "value", 0.0)
	get_tree().set_group(CLEAR_BAR_GROUP, "potential_score", 0.0)
	get_tree().call_group(LATENCY_DISPLAY_GROUP, "reset")
	get_tree().call_group(HOLD_INDICATOR_GROUP, "disappear")
	
	rating_label.hide()
	
func reset_score_counter():
	get_tree().set_group(SCORE_COUNTER_GROUP, "score", 0.0)
	get_tree().call_group(SCORE_COUNTER_GROUP, "reset")
	
func _on_chart_set(chart: HBChart):
	get_tree().set_group(CLEAR_BAR_GROUP, "max_value", chart.get_max_score())
	_update_clear_bar_value()

func try_show_intro_skip(song: HBSong):
	_show_intro_skip(song)

func _show_intro_skip(song: HBSong):
	if song.allows_intro_skip and not game.disable_intro_skip:
		if game.earliest_note_time / 1000.0 > song.intro_skip_min_time and game._intro_skip_enabled:
			get_tree().call_group(SKIP_INTRO_INDICATOR_GROUP, "appear")
	
func _on_song_set(song: HBSong, difficulty: String, assets: SongAssetLoader.AssetLoadToken = null, modifiers = []):
	get_tree().set_group(SONG_PROGRESS_INDICATOR_GROUP, "min_value", song.start_time)
	get_tree().call_group(HOLD_INDICATOR_GROUP, "disappear")
		
	if song.end_time > 0:
		get_tree().set_group(SONG_PROGRESS_INDICATOR_GROUP, "max_value", song.end_time)
	else:
		get_tree().set_group(SONG_PROGRESS_INDICATOR_GROUP, "max_value", game.audio_playback.get_length_msec())

	get_tree().call_group(DIFFICULTY_LABEL_GROUP, "set_difficulty", difficulty)
	
	get_tree().call_group(SONG_TITLE_GROUP, "set_song", song, assets, game.current_variant)
		
	var modifiers_string = PackedStringArray()

	for modifier in modifiers:
		var modifier_instance = modifier
		modifier_instance._init_plugin()
		modifier_instance._pre_game(song, game)
		modifiers_string.append(modifier_instance.get_modifier_list_name())
	get_tree().call_group(DIFFICULTY_LABEL_GROUP, "set_modifiers_name_list", modifiers_string)
	get_tree().call_group(SKIP_INTRO_INDICATOR_GROUP, "hide")
	lyrics_view.set_phrases(song.lyrics)

func _on_intro_skipped(time):
	get_tree().call_group(SKIP_INTRO_INDICATOR_GROUP, "disappear")

	intro_skip_ff_animation_player.play("animate")

func hide_intro_skip():
	get_tree().call_group(SKIP_INTRO_INDICATOR_GROUP, "hide")

func _on_hold_released():
	# When you release a hold it disappears instantly
	_update_clear_bar_value()

func _on_hold_released_early():
	# When you release a hold it disappears instantly
	get_tree().call_group(HOLD_INDICATOR_GROUP, "disappear")
	_update_clear_bar_value()
func _on_max_hold():
	get_tree().call_group(HOLD_INDICATOR_GROUP, "show_max_combo", game.MAX_HOLD)

func _on_hold_score_changed(new_score: float):
	get_tree().set_group(HOLD_INDICATOR_GROUP, "current_score", new_score)
	_update_clear_bar_value()
	
func _on_show_slide_hold_score(point: Vector2, score: float, show_max: bool):
	slide_hold_score_text.show_at_point(point, score, show_max)
	
func _on_show_multi_hint(new_closest_multi_notes):
	get_tree().call_group(MULTI_HINT_GROUP, "show_notes", new_closest_multi_notes)
	
func _on_hide_multi_hint():
	get_tree().call_group(MULTI_HINT_GROUP, "hide")
	
func _on_end_intro_skip_period():
	get_tree().call_group(SKIP_INTRO_INDICATOR_GROUP, "disappear")


func _update_clear_bar_value():
	if disable_score_processing:
		return
	# HACK HACK HACHKs everyhwere
	var res = game.result.clone()
	var res_potential = game.get_potential_result().clone()
	
	if game.held_notes.size() > 0:
		res.hold_bonus += game.accumulated_hold_score + game.current_hold_score
		res.score += game.accumulated_hold_score + game.current_hold_score
		
		res_potential.hold_bonus += game.accumulated_hold_score + game.current_hold_score
		res_potential.score += game.accumulated_hold_score + game.current_hold_score
	
	get_tree().set_group(CLEAR_BAR_GROUP, "value", res.get_capped_score())
	get_tree().set_group(CLEAR_BAR_GROUP, "potential_score", res_potential.get_base_score())

func _on_score_added(score):
	if not disable_score_processing:
		get_tree().set_group(SCORE_COUNTER_GROUP, "score", game.result.score)
		_update_clear_bar_value()
	
func _on_hold_started(holds):
	get_tree().set_group(HOLD_INDICATOR_GROUP, "current_holds", holds)
	get_tree().call_group(HOLD_INDICATOR_GROUP, "appear")

func _input(event):
	if event.is_action_pressed("hide_ui") and event.is_command_or_control_pressed() and not event.shift_pressed and not game.editing:
		_on_toggle_ui()
		get_viewport().set_input_as_handled()

func _set_ui_visible(ui_visible):
	$UnderNotesUI/Control.visible = ui_visible
	$AboveNotesUI/Control.visible = ui_visible
	$UserUI.visible = ui_visible
func _on_toggle_ui():
	$UnderNotesUI/Control.visible = !$UnderNotesUI/Control.visible
	$AboveNotesUI/Control.visible = !$UnderNotesUI/Control.visible
	$UserUI.visible = !$UserUI.visible

func is_ui_visible():
	return $UserUI.visible

func play_game_over():
	game_over_message_node.show()
	# Re-randomize the game over quote (otherwise restarts show the same one)
	# The Label with reroll() may be nested several levels deep
	_reroll_game_over_message(game_over_message_node)
	HBGame.fire_and_forget_sound(HBGame.game_over_sfx, HBGame.sfx_group)
	game_over_message_node.pivot_offset = game_over_message_node.size * 0.5
	game_over_message_node.scale.x = 0.0
	game_over_message_tween.interpolate_property(game_over_message_node, "scale:x", 0.0, 1.0, 0.5, Threen.TRANS_BOUNCE, Threen.EASE_IN)
	game_over_message_tween.start()
	
	# Show restart/quit menu after the "GAME OVER" text finishes its bounce-in
	_show_game_over_menu_delayed()


func set_health(health_value: float, animated := false, old_health := -1):
	get_tree().call_group(HEALTH_DISPLAY_GROUP, "set_health", health_value, animated, old_health)

func play_tv_off_animation():
	game_over_turn_off_top.position.y = -game_over_turn_off_top.size.y / 2.0
	game_over_turn_off_bottom.position.y = game_over_turn_off_bottom.size.y / 2.0
	game_over_turn_off_node.show()
	tv_animation_tween.interpolate_property(game_over_turn_off_top, "position:y", game_over_turn_off_top.position.y, 0, 0.3, Threen.TRANS_LINEAR, Threen.EASE_IN)
	tv_animation_tween.interpolate_property(game_over_turn_off_bottom, "position:y", game_over_turn_off_bottom.position.y, 0, 0.3, Threen.TRANS_LINEAR, Threen.EASE_IN)
	tv_animation_tween.start()


# ─────────────────────────────────────────────────────────────
# Game Over menu: Restart / Quit
# ─────────────────────────────────────────────────────────────
#
# Built entirely at runtime so we don't touch the .tscn.
# Sits inside CanvasLayer2 alongside the existing GameOverMessage.
#
# IMPORTANT — input while paused:
# The tree is paused during game over.  Neither this node nor
# the controller receive _input / _unhandled_input while paused
# unless PROCESS_MODE_ALWAYS is set on the node AND its entire
# ancestor chain.  We solve this by adding a tiny input-handler
# Node directly to the scene root with PROCESS_MODE_ALWAYS.

var _go_restart_btn: Button = null
var _go_quit_btn: Button = null
var _go_selected_index: int = 0   # 0 = Restart, 1 = Quit
var _go_input_handler: Node = null


func _show_game_over_menu_delayed() -> void:
	var timer := get_tree().create_timer(GAME_OVER_MENU_DELAY)
	timer.timeout.connect(_build_and_show_game_over_menu)


func _build_and_show_game_over_menu() -> void:
	if not game_over_message_node.visible:
		return

	if _go_menu_container != null and is_instance_valid(_go_menu_container):
		_go_menu_container.show()
		_go_menu_visible = true
		return

	var canvas_layer: Node = game_over_message_node.get_parent()

	var container := VBoxContainer.new()
	container.name = "GameOverMenu"
	container.process_mode = Node.PROCESS_MODE_ALWAYS

	container.anchor_left   = 0.0
	container.anchor_top    = 0.0
	container.anchor_right  = 1.0
	container.anchor_bottom = 1.0
	container.offset_left   = 0.0
	container.offset_top    = 0.0
	container.offset_right  = 0.0
	container.offset_bottom = 0.0
	container.alignment = BoxContainer.ALIGNMENT_CENTER

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 160)
	container.add_child(spacer)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 40)
	container.add_child(hbox)

	var restart_btn := Button.new()
	restart_btn.text = "  Restart  "
	restart_btn.custom_minimum_size = Vector2(180, 50)
	restart_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	restart_btn.focus_mode = Control.FOCUS_ALL
	restart_btn.pressed.connect(_on_game_over_restart)
	hbox.add_child(restart_btn)

	var quit_btn := Button.new()
	quit_btn.text = "  Quit  "
	quit_btn.custom_minimum_size = Vector2(180, 50)
	quit_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	quit_btn.focus_mode = Control.FOCUS_ALL
	quit_btn.pressed.connect(_on_game_over_quit)
	hbox.add_child(quit_btn)

	canvas_layer.add_child(container)
	_go_menu_container = container
	_go_restart_btn = restart_btn
	_go_quit_btn = quit_btn
	_go_selected_index = 0
	_go_menu_visible = true

	_go_update_selection()

	# Fade in
	container.modulate.a = 0.0
	var tween := create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(container, "modulate:a", 1.0, 0.3)

	# Spawn the input handler on the scene tree root so it receives
	# _input even while the tree is paused.
	_go_spawn_input_handler()


func _go_spawn_input_handler() -> void:
	if _go_input_handler != null and is_instance_valid(_go_input_handler):
		return

	var handler := Node.new()
	handler.name = "PH_GameOverInputHandler"
	handler.process_mode = Node.PROCESS_MODE_ALWAYS

	# Attach a script inline via set_script
	var script := GDScript.new()
	script.source_code = """extends Node

var menu_owner: Control = null

func _input(event: InputEvent) -> void:
	if menu_owner == null or not menu_owner._go_menu_visible:
		return

	var go_left := false
	var go_right := false
	var go_accept := false

	# Check standard ui_* actions
	go_left = event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up")
	go_right = event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down")
	go_accept = event.is_action_pressed("ui_accept")

	# Raw joypad fallback (covers remapped controllers)
	if event is InputEventJoypadButton and event.pressed:
		var btn: int = (event as InputEventJoypadButton).button_index
		if btn == JOY_BUTTON_DPAD_LEFT or btn == JOY_BUTTON_DPAD_UP:
			go_left = true
		elif btn == JOY_BUTTON_DPAD_RIGHT or btn == JOY_BUTTON_DPAD_DOWN:
			go_right = true
		elif btn == JOY_BUTTON_A:
			go_accept = true

	# Keyboard fallback
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_LEFT, KEY_UP:
				go_left = true
			KEY_RIGHT, KEY_DOWN:
				go_right = true
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
				go_accept = true

	if go_left:
		menu_owner._go_selected_index = 0
		menu_owner._go_update_selection()
		get_viewport().set_input_as_handled()
		return

	if go_right:
		menu_owner._go_selected_index = 1
		menu_owner._go_update_selection()
		get_viewport().set_input_as_handled()
		return

	if go_accept:
		if menu_owner._go_selected_index == 0:
			menu_owner._on_game_over_restart()
		else:
			menu_owner._on_game_over_quit()
		get_viewport().set_input_as_handled()
		return
"""
	script.reload()
	handler.set_script(script)
	handler.menu_owner = self

	get_tree().root.add_child(handler)
	_go_input_handler = handler


const GO_COLOR_SELECTED := Color(1.0, 1.0, 1.0, 1.0)
const GO_COLOR_DESELECTED := Color(0.6, 0.6, 0.6, 0.4)

func _go_update_selection() -> void:
	if _go_restart_btn != null:
		if _go_selected_index == 0:
			_go_restart_btn.modulate = GO_COLOR_SELECTED
			_go_restart_btn.text = "> Restart <"
		else:
			_go_restart_btn.modulate = GO_COLOR_DESELECTED
			_go_restart_btn.text = "  Restart  "

	if _go_quit_btn != null:
		if _go_selected_index == 1:
			_go_quit_btn.modulate = GO_COLOR_SELECTED
			_go_quit_btn.text = "> Quit <"
		else:
			_go_quit_btn.modulate = GO_COLOR_DESELECTED
			_go_quit_btn.text = "  Quit  "


func _reroll_game_over_message(node: Node) -> bool:
	if node.has_method("reroll"):
		node.reroll()
		return true
	for child in node.get_children():
		if _reroll_game_over_message(child):
			return true
	return false


func _dismiss_game_over_menu() -> void:
	if _go_menu_container != null and is_instance_valid(_go_menu_container):
		_go_menu_container.queue_free()
		_go_menu_container = null
	if _go_input_handler != null and is_instance_valid(_go_input_handler):
		_go_input_handler.queue_free()
		_go_input_handler = null
	_go_restart_btn = null
	_go_quit_btn = null
	_go_menu_visible = false


func _on_game_over_restart() -> void:
	_dismiss_game_over_menu()

	# Hide the "GAME OVER" text
	game_over_message_node.hide()
	game_over_message_node.scale.x = 1.0
	game_over_turn_off_node.hide()

	# Let the controller handle the actual restart (video, audio, fade, etc.)
	emit_signal("game_over_restart_requested")


func _on_game_over_quit() -> void:
	_dismiss_game_over_menu()

	# Let the controller handle the quit flow (TV-off → results)
	emit_signal("game_over_quit_requested")
