# WndSettings / SPDSettings adaptation, GPL-3.0-or-later.
# Client presentation only. Never changes authoritative match rules.
extends Node
const L10n = preload("res://scripts/menu/game_locale.gd")

signal changed(key: StringName)
signal save_finished(success: bool)

const FILE := "user://client_settings.cfg"
const DEFAULTS := {
	"fullscreen": false,
	"brightness": 0,
	"visual_grid": 0,
	"sfx_volume": 10,
	"music_volume": 5,
	"sfx_enabled": true,
	"language": "zh",
	"player_name": "",
}
var _values: Dictionary = DEFAULTS.duplicate()
var _session_name_initialized := false
var _session_player_name := ""

func _ready() -> void:
	# Dedicated servers must not read or apply a player's window/audio settings.
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		L10n.set_language("zh")
		return
	for argument in OS.get_cmdline_args():
		if argument.ends_with("scenes/pvp/server.tscn"): return
	var config := ConfigFile.new()
	if config.load(FILE) == OK:
		for key in DEFAULTS:
			var stored: Variant = config.get_value("client", key, DEFAULTS[key])
			if typeof(stored) == typeof(DEFAULTS[key]):
				_values[key] = _validated(key, stored)
	_apply_window()
	_apply_audio()
	L10n.set_language(str(_values.language))

func value(key: StringName) -> Variant:
	return _values.get(String(key))

func session_player_name() -> String:
	# Launcher identities initialize this process once, never every scene entry.
	# Manual edits (including clearing the field) replace this session value.
	if not _session_name_initialized:
		_session_player_name = str(value(&"player_name"))
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--name="):
				_session_player_name = str(_validated("player_name", argument.trim_prefix("--name=")))
		_session_name_initialized = true
	return _session_player_name

func set_value(key: StringName, selected: Variant) -> void:
	var name := String(key)
	if not DEFAULTS.has(name): return
	var next: Variant = _validated(name, selected)
	# Update before the equality check: the saved name can already equal the
	# typed value while the current session still contains a launcher override.
	if name == "player_name":
		_session_player_name = str(next)
		_session_name_initialized = true
	if _values[name] == next: return
	_values[name] = next
	if name == "fullscreen": _apply_window()
	if name in ["sfx_volume", "sfx_enabled", "music_volume"]: _apply_audio()
	if name == "language": L10n.set_language(str(next))
	changed.emit(key)
	var config := ConfigFile.new()
	for setting in _values:
		config.set_value("client", setting, _values[setting])
	save_finished.emit(config.save(FILE) == OK)

func _validated(key: String, selected: Variant) -> Variant:
	match key:
		"brightness": return clampi(int(selected), -1, 1)
		"visual_grid": return clampi(int(selected), -1, 2)
		"sfx_volume", "music_volume": return clampi(int(selected), 0, 10)
		"language": return "en" if str(selected) == "en" else "zh"
		"player_name": return str(selected).left(16)
		_: return bool(selected)

func _apply_window() -> void:
	if OS.has_feature("mobile"): return
	var window := get_window()
	if bool(_values.fullscreen):
		window.mode = Window.MODE_FULLSCREEN
	elif window.mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]:
		window.mode = Window.MODE_WINDOWED

func _apply_audio() -> void:
	# Keep the original quadratic volume curve, with independent bus controls.
	for spec in [["SFX", "sfx_volume"], ["Music", "music_volume"]]:
		var index := AudioServer.get_bus_index(spec[0])
		if index < 0: continue
		var volume := float(_values[spec[1]])
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(0.000001, volume * volume / 100.0)))
		AudioServer.set_bus_mute(index, volume == 0 or spec[0] == "SFX" and not bool(_values.sfx_enabled))
