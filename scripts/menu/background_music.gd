extends Node
## One persistent player across scenes. Load the supplied tracks off-thread.
const TRACKS := {
	"theme":"res://assets/audio/theme.ogg",
	"game":"res://assets/audio/game.ogg",
}
var player: AudioStreamPlayer
var current_track := ""
var _desired := ""
var _streams: Dictionary = {}
var _pending: Dictionary = {}
var _enabled := false

func _ready() -> void:
	set_process(false)
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"): return
	for argument in OS.get_cmdline_args():
		if argument.ends_with("scenes/pvp/server.tscn"): return
	_enabled = true
	player = AudioStreamPlayer.new()
	player.bus = &"Music"
	add_child(player)

func prepare() -> void:
	if not _enabled: return
	for track in TRACKS:
		if _streams.has(track) or _pending.has(track): continue
		var status := ResourceLoader.load_threaded_get_status(TRACKS[track])
		if status not in [ResourceLoader.THREAD_LOAD_IN_PROGRESS, ResourceLoader.THREAD_LOAD_LOADED]:
			if ResourceLoader.load_threaded_request(TRACKS[track], "AudioStreamOggVorbis") != OK:
				push_warning("Unable to load background music: " + track)
				continue
		_pending[track] = true
	set_process(not _pending.is_empty())

func play_theme() -> void: _select("theme")
func play_game() -> void: _select("game")

func _select(track: String) -> void:
	if not _enabled: return
	_desired = track
	prepare()
	_play_ready()

func _process(_delta: float) -> void:
	for track in _pending.keys():
		var status := ResourceLoader.load_threaded_get_status(TRACKS[track])
		if status in [ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE]:
			_pending.erase(track)
			push_warning("Unable to load background music: " + track)
		elif status == ResourceLoader.THREAD_LOAD_LOADED:
			var stream := ResourceLoader.load_threaded_get(TRACKS[track]) as AudioStreamOggVorbis
			_pending.erase(track)
			if stream != null:
				stream.loop = true
				stream.loop_offset = 0
				_streams[track] = stream
	_play_ready()
	set_process(not _pending.is_empty())

func _play_ready() -> void:
	if not _streams.has(_desired): return
	if current_track == _desired and player.playing: return
	player.stop()
	player.stream = _streams[_desired]
	current_track = _desired
	player.play()
