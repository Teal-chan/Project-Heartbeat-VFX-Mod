extends Window

var current_song: HBSong
var current_resource_pack: HBResourcePack

@onready var compliance_checkbox: CheckBox = get_node("MarginContainer/VBoxContainer/CheckBox")
@onready var include_vfx_checkbox: CheckBox = get_node_or_null("MarginContainer/VBoxContainer/IncludeVFXCheckBox")
@onready var upload_button: Button = get_node("MarginContainer/VBoxContainer/UploadButton")
@onready var data_label = get_node("MarginContainer/VBoxContainer/DataLabel")
@onready var description_line_edit = get_node("MarginContainer/VBoxContainer/DescriptionLineEdit")
@onready var title_line_edit = get_node("MarginContainer/VBoxContainer/TitleLineEdit")
@onready var changelog_label = get_node("MarginContainer/VBoxContainer/Label4")
@onready var changelog_line_edit = get_node("MarginContainer/VBoxContainer/UpdateDescriptionLineEdit")

@onready var upload_dialog = get_node("UploadDialog")
@onready var post_upload_dialog = get_node("PostUploadDialog")
@onready var error_dialog = get_node("ErrorDialog")
@onready var workshop_file_not_found_dialog = get_node("%WorkshopFileNotFoundDialog")
@onready var upload_status_label = get_node("UploadDialog/Panel/MarginContainer/VBoxContainer/Label")
@onready var upload_progress_bar = get_node("UploadDialog/Panel/MarginContainer/VBoxContainer/ProgressBar")

const LOG_NAME = "WorkshopUploadForm"

var uploading_new = false
var uploading_ugc_item: HBSteamUGCItem = null
var item_update: HBSteamUGCEditor = null
# Records temporarily moved VFX files so we can restore them after upload
var _moved_vfx_files: Array = []


enum MODE {
	SONG,
	RESOURCE_PACK
}

@export var upload_form_mode: MODE = MODE.SONG

const UGC_STATUS_TEXTS = {
	0: "Invalid, BUG?",
	1: "Processing configuration data",
	2: "Reading and processing content files",
	3: "Uploading content to Steam",
	4: "Uploading preview image file",
	5: "Committing changes"
}

var ERR_MAP = {
	SteamworksConstants.RESULT_OK: "",
	SteamworksConstants.RESULT_FAIL: "Generic failure",
	SteamworksConstants.RESULT_INVALID_PARAM: "Invalid parameter",
	SteamworksConstants.RESULT_ACCESS_DENIED: "The user doesn't own a license for the provided app ID.",
	SteamworksConstants.RESULT_FILE_NOT_FOUND: "The provided content folder is not valid.",
	SteamworksConstants.RESULT_LIMIT_EXCEEDED: "The preview image is too large, it must be less than 1 Megabyte; or there is not enough space available on your Steam Cloud."
}

# Whether the user wants VFX JSONs included in the uploaded song contents
var include_vfx_file: bool = false

func _dbg(msg: String) -> void:
	# Mirror to stdout so you can see it in the Godot console
	print(msg)
	# Keep the existing game logging too
	Log.log(self, msg)


func _ready():
	if PlatformService.service_provider.implements_ugc:
		var ugc = PlatformService.service_provider.ugc_provider
		ugc.connect("item_created", Callable(self, "_on_item_created"))
		ugc.connect("item_update_result", Callable(self, "_on_item_updated"))
		ugc.connect("ugc_details_request_done", Callable(self, "_on_ugc_details_request_done"))

	# Compliance checkbox → enable/disable Upload button
	if compliance_checkbox:
		compliance_checkbox.toggled.connect(_on_compliance_checkbox_toggled)
		# Make sure initial state is respected
		_on_compliance_checkbox_toggled(compliance_checkbox.button_pressed)

	post_upload_dialog.connect("confirmed", Callable(self, "_on_post_upload_accepted"))
	upload_button.connect("pressed", Callable(self, "start_upload"))
	workshop_file_not_found_dialog.connect("confirmed", Callable(self, "_on_file_not_found_confirmed"))
	workshop_file_not_found_dialog.get_cancel_button().connect("pressed", Callable(self, "hide"))

	# Hook up the VFX checkbox (can be hidden for resource packs)
	if include_vfx_checkbox:
		include_vfx_checkbox.button_pressed = false
		include_vfx_checkbox.toggled.connect(_on_include_vfx_toggled)
		include_vfx_file = false


func _on_compliance_checkbox_toggled(pressed: bool) -> void:
	upload_button.disabled = !pressed


func _on_include_vfx_toggled(pressed: bool) -> void:
	include_vfx_file = pressed
	var state_str := "ON" if pressed else "OFF"
	_dbg("[WorkshopUploadForm] Include VFX file: %s" % state_str)



func _on_file_not_found_confirmed():
	match upload_form_mode:
		MODE.SONG:
			current_song.ugc_id = 0
			current_song.ugc_service_name = ""
			set_song(current_song)
		MODE.RESOURCE_PACK:
			current_resource_pack.ugc_id = 0
			current_resource_pack.ugc_service_name = ""


func set_resource_pack(resource_pack: HBResourcePack):
	upload_form_mode = MODE.RESOURCE_PACK
	current_resource_pack = resource_pack

	var ugc = PlatformService.service_provider.ugc_provider
	changelog_line_edit.text = ""
	description_line_edit.text = ""

	# VFX is only meaningful for songs
	if include_vfx_checkbox:
		include_vfx_checkbox.visible = false

	if not FileAccess.file_exists(resource_pack.get_pack_icon_path()):
		error_dialog.dialog_text = "Your pack needs an icon to be uploaded to the workshop!"
		error_dialog.popup_centered()
		await error_dialog.visibility_changed
		hide()
		return

	if resource_pack.ugc_service_name == ugc.get_ugc_service_name():
		changelog_label.show()
		changelog_line_edit.show()
		Log.log(self, "Resource pack has been uploaded previously, requesting data.")
		_on_ugc_details_request_done(await _request_item_details(resource_pack.ugc_id))
	else:
		Log.log(self, "Resource pack hasn't been uploaded before to UGC.")
		changelog_label.hide()
		changelog_line_edit.hide()
		title_line_edit.text = resource_pack.pack_name
		data_label.text = "Updating new item: %s" % resource_pack.pack_name


func set_song(song: HBSong):
	upload_form_mode = MODE.SONG
	current_song = song
	var ugc = PlatformService.service_provider.ugc_provider
	changelog_line_edit.text = ""
	description_line_edit.text = ""

	if include_vfx_checkbox:
		include_vfx_checkbox.visible = true

	if song.ugc_service_name == ugc.get_ugc_service_name():
		changelog_label.show()
		changelog_line_edit.show()
		Log.log(self, "Song has been uploaded previously, requesting data.")
		_on_ugc_details_request_done(await _request_item_details(song.ugc_id))
	else:
		Log.log(self, "Song hasn't been uploaded before to UGC.")
		changelog_label.hide()
		changelog_line_edit.hide()
		title_line_edit.text = song.get_sanitized_field("title")
		data_label.text = "Updating new item: %s" % song.get_sanitized_field("title")


func do_metadata_size_check(dict: Dictionary) -> bool:
	if JSON.new().stringify(dict).to_utf8_buffer().size() > 5000:
		error_dialog.dialog_text = "There was an error uploading your item, %s" % ["Metadata encoding failed, maybe make the title or difficulty names smaller?"]
		error_dialog.popup_centered()
		return false
	return true


func start_upload():
	if PlatformService.service_provider.implements_ugc:
		var ugc = PlatformService.service_provider.ugc_provider
		if Steamworks.apps.get_app_owner() != Steamworks.user.get_local_user():
			error_dialog.dialog_text = """
			There was an error uploading your item:
			Content can't be uploaded to the Steam workshop from a family shared copy of the game, this is a limitation imposed by Steam.
			"""
			error_dialog.popup_centered()
			return
		var has_service_name = false
		match upload_form_mode:
			MODE.RESOURCE_PACK:
				if current_resource_pack.ugc_service_name == ugc.get_ugc_service_name():
					has_service_name = true
					uploading_new = false
					upload_resource_pack(current_resource_pack, current_resource_pack.ugc_id)
					return
			MODE.SONG:
				if not do_metadata_size_check(get_song_meta_dict()):
					return
				if current_song.ugc_service_name == ugc.get_ugc_service_name():
					has_service_name = true
					uploading_new = false
					upload_song(current_song, current_song.ugc_id)
					return
		if not has_service_name:
			uploading_new = true
			var item := HBSteamUGCEditor.new_community_file()
			item.submit()
			var create_result: Array = await item.file_submitted
			var result := create_result[0] as int
			var tos := create_result[1] as bool
			_on_item_created(result, item.file_id, tos)


func _on_item_created(result, file_id, tos):
	var ugc = PlatformService.service_provider.ugc_provider
	if result == 1:
		match upload_form_mode:
			MODE.SONG:
				current_song.ugc_id = file_id
				current_song.ugc_service_name = ugc.get_ugc_service_name()
				current_song.save_song()
				upload_song(current_song, file_id)
			MODE.RESOURCE_PACK:
				current_resource_pack.ugc_id = file_id
				current_resource_pack.ugc_service_name = ugc.get_ugc_service_name()
				current_resource_pack.save_pack()
				upload_resource_pack(current_resource_pack, file_id)
	else:
		pass


func _request_item_details(item_id: int) -> HBSteamUGCItem:
	var query := HBSteamUGCQuery.create_query(SteamworksConstants.UGC_MATCHING_UGC_TYPE_ITEMS_READY_TO_USE) \
		.with_file_ids([item_id]) \
		.with_long_description(true)

	query.request_page(0)
	var result: HBSteamUGCQueryPageResult = await query.query_completed
	if result:
		if result.results.size() > 0:
			return result.results[0]
		else:
			return null
	return null


func _on_ugc_details_request_done(data: HBSteamUGCItem):
	if data:
		data_label.text = "Updating existing item: %s" % data.title
		title_line_edit.text = data.title
		description_line_edit.text = data.description
	else: # File not found, possibly because the user deleted it
		workshop_file_not_found_dialog.popup_centered()


func _process(delta):
	if item_update:
		var ugc = PlatformService.service_provider.ugc_provider
		var progress := item_update.get_update_progress()
		upload_status_label.text = UGC_STATUS_TEXTS[progress.update_status]
		if progress.bytes_total > 0:
			upload_progress_bar.value = progress.bytes_processed / float(progress.bytes_total)

	# EXTRA SAFETY: keep Upload button in sync with the compliance checkbox,
	# even if the signal connection somehow fails.
	if compliance_checkbox and upload_button:
		var allow := compliance_checkbox.button_pressed
		if upload_button.disabled == allow:
			upload_button.disabled = !allow


func get_song_meta_dict() -> Dictionary:
	var serialized = current_song.serialize()
	var out_dir = {}
	for field in ["title", "charts", "type", "romanized_title"]:
		if field in serialized:
			out_dir[field] = serialized[field]
	return out_dir


# --- VFX filesystem helpers ---------------------------------------------

# Returns the absolute directory on disk where the song's files live
func _get_song_dir_abs(song: HBSong) -> String:
	var song_fs_path := ProjectSettings.globalize_path(song.path)
	var dir_path := song_fs_path

	# If song.path happens to be a file, fall back to its folder
	if not DirAccess.dir_exists_absolute(dir_path):
		dir_path = song_fs_path.get_base_dir()

	return dir_path


# Scan for VFX JSONs in both the song directory and user://vfx_tmp/<song_id>
# Returns:
# {
#   "has_any": bool,
#   "files": Array[String],       # union of all filenames
#   "in_song_dir": Array[String], # filenames found in the song dir
#   "in_tmp_dir": Array[String],  # filenames found in the outer tmp dir
# }
func _log_vfx_files_for_song(song: HBSong) -> Dictionary:
	var song_dir_abs := _get_song_dir_abs(song)

	var tmp_root_abs := ProjectSettings.globalize_path("user://vfx_tmp")
	var tmp_song_abs := tmp_root_abs.path_join(str(song.id))

	var info := {
		"has_any": false,
		"files": [],
		"in_song_dir": [],
		"in_tmp_dir": [],
	}

	_dbg("[WorkshopUploadForm] ---- VFX scan for song ----")
	_dbg("[WorkshopUploadForm]   song.path: %s" % song.path)
	_dbg("[WorkshopUploadForm]   song_dir_abs: %s" % song_dir_abs)
	_dbg("[WorkshopUploadForm]   tmp_song_abs: %s" % tmp_song_abs)

	_scan_vfx_dir(song_dir_abs, info, "in_song_dir")
	_scan_vfx_dir(tmp_song_abs, info, "in_tmp_dir")

	# Build unique file list (union)
	var seen := {}
	for fn in info["in_song_dir"]:
		seen[fn] = true
	for fn in info["in_tmp_dir"]:
		seen[fn] = true

	info["files"] = seen.keys()
	info["has_any"] = info["in_song_dir"].size() > 0 or info["in_tmp_dir"].size() > 0

	if not info["has_any"]:
		_dbg("[WorkshopUploadForm]   No VFX JSONs found in song dir or temp dir.")
	else:
		_dbg("[WorkshopUploadForm]   in_song_dir: %s" % str(info["in_song_dir"]))
		_dbg("[WorkshopUploadForm]   in_tmp_dir: %s" % str(info["in_tmp_dir"]))

	_dbg("[WorkshopUploadForm] ---- end VFX scan ----")

	return info


func _scan_vfx_dir(dir_path: String, info: Dictionary, key: String) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		return

	var dir := DirAccess.open(dir_path)
	if dir == null:
		_dbg("[WorkshopUploadForm]   (failed to open dir: %s)" % dir_path)
		return

	dir.list_dir_begin()
	while true:
		var fn := dir.get_next()
		if fn == "":
			break
		if dir.current_is_dir():
			continue

		var lower := fn.to_lower()
		if not lower.ends_with(".json"):
			continue

		# Flexible: *_vfx.json or anything containing "vfx"
		if not (lower.ends_with("_vfx.json") or lower.find("vfx") != -1):
			continue

		info[key].append(fn)
	dir.list_dir_end()



# Move VFX JSONs out of the song content folder so Steam won't upload them.
# We send them to: user://vfx_tmp/<song_id>/<filename>.json
# Only moves files that are currently in the song dir.
func _temporarily_move_vfx_files(song: HBSong, vfx_info: Dictionary) -> void:
	_moved_vfx_files.clear()

	var files_in_song: Array = vfx_info.get("in_song_dir", [])
	if files_in_song.is_empty():
		return

	var song_dir_abs := _get_song_dir_abs(song)

	# Global temp root (outside the song content directory)
	var tmp_root_abs := ProjectSettings.globalize_path("user://vfx_tmp")
	DirAccess.make_dir_recursive_absolute(tmp_root_abs)

	# Per-song temp folder (to avoid collisions)
	var song_tmp_abs := tmp_root_abs.path_join(str(song.id))
	DirAccess.make_dir_recursive_absolute(song_tmp_abs)

	_dbg("[WorkshopUploadForm] Temporarily moving VFX files out of content dir:")
	_dbg("[WorkshopUploadForm]   song_dir_abs = %s" % song_dir_abs)
	_dbg("[WorkshopUploadForm]   song_tmp_abs = %s" % song_tmp_abs)

	for fn in files_in_song:
		var src := song_dir_abs.path_join(fn)
		var dst := song_tmp_abs.path_join(fn)

		if not FileAccess.file_exists(src):
			_dbg("[WorkshopUploadForm]   (skipping, not found) %s" % src)
			continue

		var err := DirAccess.rename_absolute(src, dst)
		if err != OK:
			printerr("[WorkshopUploadForm]   ERROR moving %s → %s (err=%d)" % [src, dst, err])
			continue

		_dbg("[WorkshopUploadForm]   moved %s → %s" % [src, dst])
		_moved_vfx_files.append({
			"src": src,
			"dst": dst,
		})

# When including VFX again, ensure any files in user://vfx_tmp/<song_id>
# are moved back into the song directory BEFORE we upload.
func _ensure_vfx_files_in_song_dir(song: HBSong, vfx_info: Dictionary) -> void:
	var files_in_tmp: Array = vfx_info.get("in_tmp_dir", [])
	if files_in_tmp.is_empty():
		return

	var song_dir_abs := _get_song_dir_abs(song)
	var tmp_root_abs := ProjectSettings.globalize_path("user://vfx_tmp")
	var song_tmp_abs := tmp_root_abs.path_join(str(song.id))

	_dbg("[WorkshopUploadForm] Ensuring VFX files are in song dir for upload:")
	_dbg("[WorkshopUploadForm]   song_dir_abs = %s" % song_dir_abs)
	_dbg("[WorkshopUploadForm]   song_tmp_abs = %s" % song_tmp_abs)

	for fn in files_in_tmp:
		var src := song_tmp_abs.path_join(fn)
		var dst := song_dir_abs.path_join(fn)

		if not FileAccess.file_exists(src):
			_dbg("[WorkshopUploadForm]   (temp file missing) %s" % src)
			continue

		if FileAccess.file_exists(dst):
			_dbg("[WorkshopUploadForm]   (already exists in song dir) %s" % dst)
			continue

		var err := DirAccess.rename_absolute(src, dst)
		if err != OK:
			printerr("[WorkshopUploadForm]   ERROR moving back %s → %s (err=%d)" % [src, dst, err])
		else:
			_dbg("[WorkshopUploadForm]   moved back %s → %s" % [src, dst])



func upload_song(song: HBSong, ugc_id: int):
	# Step 1: scan VFX in both song dir and user://vfx_tmp/<song_id>
	var vfx_info := {
		"has_any": false,
		"files": [],
		"in_song_dir": [],
		"in_tmp_dir": [],
	}

	if upload_form_mode == MODE.SONG:
		vfx_info = _log_vfx_files_for_song(song)

		if include_vfx_file:
			# Bring any previously hidden VFX JSONs back into the song folder
			_ensure_vfx_files_in_song_dir(song, vfx_info)
		else:
			# Move VFX JSONs out of the song folder so this upload has no VFX files
			_temporarily_move_vfx_files(song, vfx_info)

	# Step 2: normal Project Heartbeat UGC setup
	var query := HBSteamUGCQuery.create_query(SteamworksConstants.UGC_MATCHING_UGC_TYPE_ITEMS_READY_TO_USE)
	query.allow_cached_response(0).with_children(true).with_file_ids([ugc_id]).request_page(ugc_id)
	var query_result: HBSteamUGCQueryPageResult = await query.query_completed

	if query_result.results.size() > 0:
		var item := query_result.results[0]
		for child_id in item.children:
			item.remove_dependency(child_id)
		if song.skin_ugc_id != 0:
			item.add_dependency(song.skin_ugc_id)

	var ugc = PlatformService.service_provider.ugc_provider
	song.save_chart_info()

	var out_dir = get_song_meta_dict()

	# Debug: what did we find?
	var has_any_vfx := bool(vfx_info.get("has_any", false))
	_dbg("[WorkshopUploadForm] include_vfx_file=%s, has_any_vfx=%s"
		% [str(include_vfx_file), str(has_any_vfx)])

	# If the user ticked "Include VFX file" *and* we actually found VFX JSONs,
	# declare a tiny metadata block so WorkshopBrowser / mods can see it.
	if include_vfx_file and has_any_vfx:
		var files_arr: Array = vfx_info.get("files", [])
		out_dir["ph_vfx"] = {
			"enabled": true,
			"files": files_arr,
			"ver": 1
		}
		_dbg("[WorkshopUploadForm] Adding ph_vfx metadata: %s"
			% JSON.stringify(out_dir["ph_vfx"]))

	var meta_str := JSON.stringify(out_dir)
	_dbg("[WorkshopUploadForm] Final metadata JSON length: %d bytes"
		% meta_str.to_utf8_buffer().size())

	var update := HBSteamUGCItem.from_id(ugc_id).edit() \
		.with_title(title_line_edit.text) \
		.with_description(description_line_edit.text) \
		.with_metadata(meta_str) \
		.with_content(ProjectSettings.globalize_path(current_song.path)) \
		.with_preview_file(ProjectSettings.globalize_path(current_song.get_song_preview_res_path()))

	# ...rest of upload_song stays the same (tags, changelog, submit, etc.)

	if uploading_new:
		var video_id = YoutubeDL.get_video_id(song.youtube_url)
		if video_id:
			update.with_preview_video_id(video_id)

	var tags := ["Charts"]
	for chart in song.charts:
		if song.charts[chart].has("stars"):
			var stars: float = song.charts[chart].stars
			for diff_string in HBGame.CHART_DIFFICULTY_TAGS:
				var min_stars: float = HBGame.CHART_DIFFICULTY_TAGS[diff_string][0]
				var max_stars: float = HBGame.CHART_DIFFICULTY_TAGS[diff_string][1]
				if stars >= min_stars and stars <= max_stars:
					if not diff_string in tags:
						tags.push_back(diff_string)
	update.with_tags(tags)

	if uploading_new:
		update.with_changelog("Initial upload")
	else:
		update.with_changelog(changelog_line_edit.text)

	upload_dialog.popup_centered()

	update.submit()
	item_update = update
	var update_result := await update.file_submitted as Array
	_on_item_updated(update_result[0], update_result[1], HBSteamUGCItem.from_id(ugc_id))

# Put any temporarily moved VFX files back where they came from
func _restore_moved_vfx_files() -> void:
	if _moved_vfx_files.is_empty():
		return

	_dbg("[WorkshopUploadForm] Restoring temporarily moved VFX files...")

	for m in _moved_vfx_files:
		var src: String = m["dst"]
		var dst: String = m["src"]

		if not FileAccess.file_exists(src):
			_dbg("[WorkshopUploadForm]   (missing temp file) %s" % src)
			continue

		var err := DirAccess.rename_absolute(src, dst)
		if err != OK:
			printerr("[WorkshopUploadForm]   ERROR restoring %s → %s (err=%d)" % [src, dst, err])
		else:
			_dbg("[WorkshopUploadForm]   restored %s → %s" % [src, dst])

	_moved_vfx_files.clear()


func upload_resource_pack(resource_pack: HBResourcePack, ugc_id):
	item_update = null
	var item := HBSteamUGCItem.from_id(ugc_id)
	item_update = item.edit() \
		.with_title(title_line_edit.text) \
		.with_description(description_line_edit.text) \
		.with_metadata(JSON.stringify(resource_pack.serialize())) \
		.with_preview_file(ProjectSettings.globalize_path(resource_pack.get_pack_icon_path())) \
		.with_content(ProjectSettings.globalize_path(resource_pack._path))

	var tags := []

	if resource_pack.is_skin():
		item_update.with_tags(["Skins"])
	else:
		item_update.with_tags(["Note Packs"])
	if uploading_new:
		item_update.with_changelog("Initial upload")
	else:
		item_update.with_changelog(changelog_line_edit.text)
	item_update.submit()
	upload_dialog.popup_centered()
	var update_result := await item_update.file_submitted as Array
	_on_item_updated(update_result[0], update_result[1], HBSteamUGCItem.from_id(ugc_id))


func _on_item_updated(result: int, tos: bool, item: HBSteamUGCItem):
	_restore_moved_vfx_files()
	upload_dialog.hide()
	item_update = null
	if result == SteamworksConstants.RESULT_OK:
		var text = """Item uploaded succesfully, you wil now be redirected to your item's workshop page,
		if this is the first time you upload this item you will need to set your song's visibility and if you've never uploaded
		a workshop item before you will need to accept the workshop's terms of service."""
		post_upload_dialog.dialog_text = text
		post_upload_dialog.popup_centered()
		match upload_form_mode:
			MODE.SONG:
				current_song.save_song()
			MODE.RESOURCE_PACK:
				current_resource_pack.save_pack()
	else:
		var ugc = PlatformService.service_provider.ugc_provider
		error_dialog.dialog_text = "There was an error uploading your item, %s" % [ERR_MAP.get(result, "Unknown Error")]
		if uploading_new:
			match upload_form_mode:
				MODE.SONG:
					current_song.ugc_id = 0
					current_song.ugc_service_name = ""
					current_song.save_song()
					item.delete_item()
				MODE.RESOURCE_PACK:
					current_resource_pack.ugc_id = 0
					current_resource_pack.ugc_service_name = ""
					current_resource_pack.save_pack()
					item.delete_item()
		error_dialog.popup_centered()


func _on_post_upload_accepted():
	match upload_form_mode:
		MODE.SONG:
			Steamworks.friends.activate_game_overlay_to_web_page("steam://url/CommunityFilePage/%d" % [current_song.ugc_id], true)
		MODE.RESOURCE_PACK:
			Steamworks.friends.activate_game_overlay_to_web_page("steam://url/CommunityFilePage/%d" % [current_resource_pack.ugc_id], true)

	hide()
