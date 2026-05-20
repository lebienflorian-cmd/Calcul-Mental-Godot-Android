extends Node
# ============================================================
# PROFILE MANAGER — Profils utilisateurs + sauvegarde JSON.
# Fichier : user://profiles_arith.json
# ============================================================

const FILE := "user://profiles_arith.json"
const DEFAULT_PROFILE := "Défaut"

var current_profile: String = DEFAULT_PROFILE
var profiles: Dictionary = {}   # name -> {options: {...}}

signal profile_changed(name: String)

func _ready() -> void:
	_load()
	# S'assurer que Défaut existe et est verrouillé
	if not profiles.has(DEFAULT_PROFILE):
		profiles[DEFAULT_PROFILE] = {"options": GameState.options_to_dict(), "locked": true, "mode": 0}
		_save()
	elif not profiles[DEFAULT_PROFILE].has("locked"):
		profiles[DEFAULT_PROFILE]["locked"] = true
		if not profiles[DEFAULT_PROFILE].has("mode"):
			profiles[DEFAULT_PROFILE]["mode"] = int(profiles[DEFAULT_PROFILE].get("options", {}).get("mode", 0))
		_save()
	# Charger les options du profil courant
	apply_current_to_state()

func _load() -> void:
	if not FileAccess.file_exists(FILE):
		profiles = {}
		current_profile = DEFAULT_PROFILE
		return
	var f := FileAccess.open(FILE, FileAccess.READ)
	if f == null: return
	var content := f.get_as_text()
	var parsed = JSON.parse_string(content)
	if typeof(parsed) == TYPE_DICTIONARY:
		profiles = parsed.get("profiles", {})
		current_profile = parsed.get("current", DEFAULT_PROFILE)
	else:
		profiles = {}
		current_profile = DEFAULT_PROFILE

func _save() -> void:
	var f := FileAccess.open(FILE, FileAccess.WRITE)
	if f == null: return
	var d := {"current": current_profile, "profiles": profiles}
	f.store_string(JSON.stringify(d, "\t"))

func list_profiles() -> Array:
	return profiles.keys()

func get_current() -> String:
	return current_profile

func apply_current_to_state() -> void:
	if profiles.has(current_profile):
		var p: Dictionary = profiles[current_profile]
		GameState.options_from_dict(p.get("options", {}))

func save_current_options() -> void:
	if not profiles.has(current_profile):
		profiles[current_profile] = {}
	profiles[current_profile]["options"] = GameState.options_to_dict()
	_save()

func switch_to(name: String) -> void:
	if not profiles.has(name): return
	if is_locked(current_profile):
		save_current_options()   # persist mode-param tweaks for locked profiles
	current_profile = name
	apply_current_to_state()
	_save()
	emit_signal("profile_changed", name)

func is_locked(name: String) -> bool:
	if not profiles.has(name): return false
	return bool(profiles[name].get("locked", false))

func get_profile_mode(name: String) -> int:
	if not profiles.has(name): return 0
	return int(profiles[name].get("mode", 0))

func lock_and_save(name: String) -> void:
	if not profiles.has(name): return
	profiles[name]["options"] = GameState.options_to_dict()
	profiles[name]["locked"]  = true
	profiles[name]["mode"]    = int(GameState.options.mode)
	_save()

func create_profile(name: String) -> bool:
	if name.strip_edges() == "": return false
	if profiles.has(name): return false
	profiles[name] = {"options": GameState.options_to_dict(), "locked": false, "mode": int(GameState.options.mode)}
	_save()
	return true

func rename_profile(old_name: String, new_name: String) -> bool:
	if old_name == DEFAULT_PROFILE: return false
	if not profiles.has(old_name): return false
	if profiles.has(new_name): return false
	if new_name.strip_edges() == "": return false
	profiles[new_name] = profiles[old_name]
	profiles.erase(old_name)
	if current_profile == old_name:
		current_profile = new_name
	_save()
	return true

func delete_profile(name: String) -> bool:
	if name == DEFAULT_PROFILE: return false
	if not profiles.has(name): return false
	profiles.erase(name)
	if current_profile == name:
		current_profile = DEFAULT_PROFILE
		apply_current_to_state()
	_save()
	emit_signal("profile_changed", current_profile)
	return true
