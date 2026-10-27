extends Node
## Load dependencies on a worker, then prime UI caches in an offscreen viewport.
const PATH := "res://scenes/pvp/client.tscn"
var scene: PackedScene
var prepared := false
var failed := false
var _started := false
var _viewport: SubViewport
var _client: Control
var _draw_frames := 0

func _ready() -> void:
	set_process(false)

func prepare() -> void:
	if _started: return
	_started = true
	var status := ResourceLoader.load_threaded_get_status(PATH)
	if status not in [ResourceLoader.THREAD_LOAD_IN_PROGRESS,ResourceLoader.THREAD_LOAD_LOADED] and ResourceLoader.load_threaded_request(PATH,"PackedScene",true)!=OK:
		failed = true
		return
	set_process(true)

func _process(_delta: float) -> void:
	if scene==null:
		var status := ResourceLoader.load_threaded_get_status(PATH)
		if status==ResourceLoader.THREAD_LOAD_FAILED or status==ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			failed = true
			set_process(false)
			return
		if status!=ResourceLoader.THREAD_LOAD_LOADED: return
		scene = ResourceLoader.load_threaded_get(PATH) as PackedScene
		if scene == null or not scene.can_instantiate():
			failed = true
			set_process(false)
			return
		_viewport = SubViewport.new()
		_viewport.size = Vector2i(get_viewport().get_visible_rect().size)
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(_viewport)
		_client = scene.instantiate() as Control
		_client.set_meta("prewarm",true)
		_client.process_mode = Node.PROCESS_MODE_DISABLED
		_viewport.add_child(_client)
	if not _client.get("_prewarm_finished"): return
	# One offscreen draw primes font/shader caches without showing a spare lobby.
	if _draw_frames==0: _viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_draw_frames += 1
	if _draw_frames<3: return
	set_process(false)
	var retiring := _viewport
	_viewport = null
	_client = null
	retiring.queue_free()
	# Complete deletion and a frame before revealing the menu. Previously the
	# ready flag preceded this cleanup, allowing it to hitch the visible menu.
	await retiring.tree_exited
	await get_tree().process_frame
	prepared = true

func retry() -> void:
	if not failed: return
	failed = false
	_started = false
	scene = null
	_draw_frames = 0
	prepare()
