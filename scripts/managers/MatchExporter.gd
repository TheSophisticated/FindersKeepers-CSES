extends RefCounted

## Simple plain-text (.txt) match exporter for Silence of the Limbs.
## Writes a clean human-readable match summary and event timeline to user://exports/.

const PlayerCustomization = preload("res://Models/characters/PlayerCustomization.gd")
const EXPORT_DIR := "user://exports"


static func _format_mmss(total_sec: float) -> String:
	var s := maxi(0, int(round(total_sec)))
	return "%02d:%02d" % [s / 60, s % 60]


static func build_match_report(game_manager: Node, network_manager: Node = null) -> String:
	var lines: PackedStringArray = []
	var now_str := Time.get_datetime_string_from_system(false, true)
	lines.append("============================================================")
	lines.append("SILENCE OF THE LIMBS — MATCH EXPORT (.TXT)")
	lines.append("============================================================")
	lines.append("Exported At:    %s" % now_str)

	if game_manager == null:
		lines.append("Status:         No active GameManager state available.")
		return "\n".join(lines) + "\n"

	var start_dt: String = str(game_manager.get("match_start_datetime"))
	if not start_dt.is_empty():
		lines.append("Match Started:  %s" % start_dt)

	var state_idx := int(game_manager.get("current_state"))
	var state_names := ["WAITING_FOR_PLAYERS", "IN_PROGRESS", "BLOOD_SHRINE_ACTIVE", "GAME_OVER"]
	var state_label: String = state_names[state_idx] if state_idx >= 0 and state_idx < state_names.size() else str(state_idx)
	var time_rem := float(game_manager.get("time_remaining"))
	var duration := 300.0
	var elapsed := clampf(duration - time_rem, 0.0, duration)

	lines.append("Match State:    %s" % state_label)
	lines.append("Time Elapsed:   %s" % _format_mmss(elapsed))
	lines.append("Time Remaining: %s" % _format_mmss(time_rem))

	if state_idx == 3:
		var winner_id := int(game_manager.get("last_winner_id"))
		var winner_str := "Draw (No winner)"
		if winner_id != -1:
			winner_str = game_manager.get_player_display_name(winner_id)
		lines.append("Result:         %s" % winner_str)

	lines.append("")
	lines.append("------------------------------------------------------------")
	lines.append("PLAYERS")
	lines.append("------------------------------------------------------------")

	var players_dict: Dictionary = game_manager.get("players")
	if players_dict.is_empty():
		lines.append("  (No players registered)")
	else:
		var pids: Array = players_dict.keys()
		pids.sort()
		var part_codes := ["H", "A", "T", "L"]
		for pid in pids:
			var pdata: Dictionary = players_dict[pid]
			var pname: String = game_manager.get_player_display_name(pid)
			var pcolor: String = game_manager.get_player_color(pid)
			var dep_cnt := int(pdata.get("parts_deposited", 0))
			var lost_arr: Array = pdata.get("parts_lost", [])
			var is_alive := bool(pdata.get("is_alive", true))
			var is_conn := bool(pdata.get("is_connected", true))
			var status := "ALIVE" if is_alive else ("DISCONNECTED" if not is_conn else "SACRIFICED")

			var limb_str := ""
			for i in range(4):
				limb_str += "[X]" if (i in lost_arr) else ("[%s]" % part_codes[i])

			var char_label := "Default"
			var skin_label := "Default"
			var hair_label := "Default"
			if network_manager != null:
				if network_manager.has_method("get_character_id_for_peer"):
					var cid: StringName = network_manager.get_character_id_for_peer(pid)
					var catalog = network_manager.get("CHARACTER_CATALOG")
					if catalog != null and catalog.has_method("get_character"):
						var def = catalog.get_character(cid)
						if def != null:
							char_label = str(def.display_name)
				if network_manager.has_method("get_customization_for_peer"):
					var custom: Dictionary = network_manager.get_customization_for_peer(pid)
					skin_label = PlayerCustomization.get_skin_label(str(custom.get("skin", "default")))
					hair_label = PlayerCustomization.get_hair_label(str(custom.get("hair", "default")))

			lines.append("  - %s (%s) | Status: %s" % [pname, pcolor, status])
			lines.append("      Avatar: %s | Skin: %s | Hair: %s" % [char_label, skin_label, hair_label])
			lines.append("      Sacrificed: %d | Parts Lost: %d/4 %s" % [dep_cnt, lost_arr.size(), limb_str])

	lines.append("")
	lines.append("------------------------------------------------------------")
	lines.append("EVENT TIMELINE")
	lines.append("------------------------------------------------------------")

	var events: Array = game_manager.get("match_event_log")
	if events.is_empty():
		lines.append("  (No events recorded)")
	else:
		for ev in events:
			var t_str := _format_mmss(float(ev.get("elapsed_sec", 0.0)))
			var kind := str(ev.get("kind", "INFO"))
			var msg := str(ev.get("message", ""))
			lines.append("  [%s] [%-11s] %s" % [t_str, kind, msg])

	lines.append("============================================================")
	return "\n".join(lines) + "\n"


static func export_match_to_text_file(game_manager: Node, network_manager: Node = null) -> Dictionary:
	var abs_dir := ProjectSettings.globalize_path(EXPORT_DIR)
	var mk_err := DirAccess.make_dir_recursive_absolute(abs_dir)
	if mk_err != OK and mk_err != ERR_ALREADY_EXISTS:
		return {
			"ok": false,
			"user_path": "",
			"global_path": "",
			"file_name": "",
			"error": "Could not create export directory (err %d)" % mk_err
		}

	var stamp := Time.get_datetime_string_from_system(false, false).replace(":", "-").replace("T", "_")
	var file_name := "match_%s.txt" % stamp
	var user_path := "%s/%s" % [EXPORT_DIR, file_name]
	var global_path := ProjectSettings.globalize_path(user_path)

	var report := build_match_report(game_manager, network_manager)
	var f := FileAccess.open(user_path, FileAccess.WRITE)
	if f == null:
		return {
			"ok": false,
			"user_path": user_path,
			"global_path": global_path,
			"file_name": file_name,
			"error": "Failed to open file for writing (err %d)" % FileAccess.get_open_error()
		}
	f.store_string(report)
	f.close()
	print("MatchExporter: Exported match report to ", global_path)
	return {
		"ok": true,
		"user_path": user_path,
		"global_path": global_path,
		"file_name": file_name,
		"error": ""
	}
