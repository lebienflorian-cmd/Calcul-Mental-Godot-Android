extends Node
# ============================================================
# SCORE MANAGER — Persistance des scores + daily bests.
# Fichier : user://scores_arith.json ou scores_arith_<profil>.json
# ============================================================

const MAX_ROWS := 800

func _file_for_current() -> String:
	var p: String = ProfileManager.current_profile
	if p == ProfileManager.DEFAULT_PROFILE:
		return "user://scores_arith.json"
	return "user://scores_arith_%s.json" % _sanitize(p)

func _sanitize(s: String) -> String:
	var out := ""
	for c in s:
		var code := c.unicode_at(0)
		var is_alpha := (code >= 65 and code <= 90) or (code >= 97 and code <= 122)
		var is_digit := (code >= 48 and code <= 57)
		if is_alpha or is_digit or c == "_":
			out += c
		elif c == " ":
			out += "_"
	if out == "": out = "profil"
	return out

# ---- Lecture ----
func load_all() -> Dictionary:
	var path := _file_for_current()
	if not FileAccess.file_exists(path):
		return {"sessions": [], "daily_bests": {}}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {"sessions": [], "daily_bests": {}}
	var content := f.get_as_text()
	var parsed = JSON.parse_string(content)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"sessions": [], "daily_bests": {}}
	if not parsed.has("sessions"): parsed["sessions"] = []
	if not parsed.has("daily_bests"): parsed["daily_bests"] = {}
	return parsed

func save_all(data: Dictionary) -> void:
	var f := FileAccess.open(_file_for_current(), FileAccess.WRITE)
	if f == null: return
	f.store_string(JSON.stringify(data, "\t"))

# ---- Sessions ----
func add_session(stats: Dictionary) -> void:
	var data := load_all()
	# Construire l'entrée
	var entry := {
		"date": stats.date,
		"mode": stats.mode,
		"level": stats.level,
		"duration": stats.elapsed,
		"calculations": stats.total,
		"correct": stats.correct,
		"accuracy": stats.accuracy,
		"avg_time": stats.avg_time,
		"score": stats.score,
		"ops": _active_ops_str(),
	}
	if stats.mode == GameState.Mode.FLASH_ANZAN:
		entry["flash_numbers"] = GameState.options.flash_count
		entry["flash_series"]  = GameState.options.flash_series
	if stats.mode == GameState.Mode.INFERNAL:
		entry["n_back"] = GameState.options.infernal_n
		entry["speed"]  = GameState.options.infernal_tempo
	data.sessions.append(entry)
	# Limiter
	if data.sessions.size() > MAX_ROWS:
		data.sessions = data.sessions.slice(data.sessions.size() - MAX_ROWS)
	save_all(data)

func _active_ops_str() -> String:
	var l := []
	if GameState.options.op_add: l.append("+")
	if GameState.options.op_sub: l.append("−")
	if GameState.options.op_mul: l.append("×")
	if GameState.options.op_div: l.append("÷")
	return "".join(l)

# ---- Daily bests ----
func _today_key() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]

func get_daily_best(mode: int) -> int:
	var data := load_all()
	var key := "%s_m%d" % [_today_key(), mode]
	return int(data.daily_bests.get(key, 0))

func set_daily_best_if_better(mode: int, score: int) -> bool:
	var data := load_all()
	var key := "%s_m%d" % [_today_key(), mode]
	var cur := int(data.daily_bests.get(key, 0))
	if score > cur:
		data.daily_bests[key] = score
		save_all(data)
		return true
	return false

# ---- Sessions par mode ----
func sessions_for_mode(mode: int) -> Array:
	var data := load_all()
	var out := []
	for s in data.sessions:
		if int(s.mode) == mode:
			out.append(s)
	return out

func daily_bests_history(mode: int) -> Array:
	# Retourne tableau [{date, score}] des meilleurs scores du jour pour ce mode
	var data := load_all()
	var out := []
	for key in data.daily_bests.keys():
		var key_str: String = str(key)
		if key_str.ends_with("_m%d" % mode):
			var date: String = key_str.substr(0, key_str.length() - ("_m%d" % mode).length())
			out.append({"date": date, "score": int(data.daily_bests[key])})
	out.sort_custom(func(a, b): return a.date < b.date)
	return out

func clear_scores_for_mode(mode: int) -> void:
	var data := load_all()
	data.sessions = data.sessions.filter(func(s): return int(s.mode) != mode)
	# Supprimer aussi les daily bests de ce mode
	var to_remove := []
	for k in data.daily_bests.keys():
		if k.ends_with("_m%d" % mode):
			to_remove.append(k)
	for k in to_remove:
		data.daily_bests.erase(k)
	save_all(data)
