extends Node
## Client transport and protocol declarations. No server implementation.
signal state_received(state: Dictionary)
signal notice(text: String)
signal connection_changed(text: String)
signal command_finished(result: Dictionary)
signal server_status_changed
signal map_submission_result(request_id: int, result: Dictionary)
signal news_summary_received(result: Dictionary)
const DEFAULT_PORT := 24567
const History = preload("res://scripts/menu/battle_history.gd")
const DEFAULT_TRANSPORT := "enet"
const PROTOCOL := 11
const ENET_CHANNELS := 3
const VERSION_MISMATCH_NOTICE := "客户端与服务器版本不一致。"
const SERVER_CONFIG := "res://assets/network/server.json"
const STATUS_INTERVAL_MS := 1000
const STATUS_TIMEOUT_MS := 20000
const SESSION_TIMEOUT_MS := 30000
const SERVER_IDLE_TIMEOUT_MS := 45000
const STATUS_RETRY_MS := 5000
const MAX_CONNECTIONS := PvpProtocol.MAX_CONNECTIONS
const RECONNECT_GRACE_MS := PvpProtocol.RECONNECT_GRACE_MS
const RECONNECT_RETRY_MS := 2000
const STATE_SYNC_INTERVAL_MS := 2000
const server_mode := false
var latest: Dictionary = {}
var requested_hero := "warrior"
var requested_name := ""
var connection_state := "disconnected"
var game_version: String = str(ProjectSettings.get_setting("application/config/version", ""))
var server_version := ""
var latency_ms := -1
var online_count := -1
var _endpoint: Dictionary = {}
var _endpoint_loaded := false
var _monitor_only := false
var _joining_match := false
var _retry_at := 0
var _connected_at := 0
var _last_probe := -1
var _probe_stamps: Dictionary = {}
var _last_reply := -1
var _command_serial := 0
var _deferred_acks: Array[Dictionary] = []
var _last_server_message := -1
var _resume_token := ""
var _reconnecting := false
var _resume_deadline := 0
var _resume_sent := false
var _await_resume_state := false
var _resume_state_received := false
var _backgrounded := false
var _leaving := false
var _leave_confirmed := false
var _pending_cancel_token := "" # Survives leave/transport replacement until server confirmation.
var _cancel_sent_at := -1
var _map_serial := 0

func _ready() -> void:
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(_connection_failed)
	multiplayer.server_disconnected.connect(_server_lost)

func _websocket_peer() -> WebSocketMultiplayerPeer:
	var peer := WebSocketMultiplayerPeer.new()
	peer.handshake_timeout = STATUS_TIMEOUT_MS / 1000.0
	# The default 64 KiB buffer is too small for a burst of reliable snapshots.
	peer.inbound_buffer_size = 1024 * 1024
	peer.outbound_buffer_size = 1024 * 1024
	return peer

func request_map_submissions(request: Dictionary) -> int:
	if not is_server_ready(): return 0
	_map_serial += 1
	_map_submission_request.rpc_id(1,PROTOCOL,game_version,_map_serial,request)
	return _map_serial

func request_battle_history(index: int = 0) -> int:
	return request_map_submissions({"op":"battle_history", "index":index})

func request_news(revision: String = "") -> int:
	return request_map_submissions({"op":"news", "revision":revision})

func request_news_summary() -> int:
	return request_map_submissions({"op":"news_watch"})

@rpc("any_peer", "call_remote", "reliable", 2)
func _map_submission_request(protocol: int, version: String, request_id: int, request: Dictionary) -> void:
	pass # Protocol declaration only; this client never handles server requests.

@rpc("authority", "call_remote", "reliable", 2)
func _map_submission_reply(request_id: int, result: Dictionary) -> void:
	if server_mode: return
	_last_server_message = Time.get_ticks_msec()
	if result.get("op") == "news_summary":
		news_summary_received.emit(result)
		return
	if request_id == 0: return
	map_submission_result.emit(request_id,result)

## Promote the existing menu connection to a match seat; never reconnect here.
func join_match(hero: String, player_name: String, mode: String = "public", code: String = "") -> Error:
	if not is_server_ready(): return ERR_UNAVAILABLE
	if not _monitor_only or _joining_match: return ERR_BUSY
	if hero not in HeroAssets.HERO_KEYS: return ERR_INVALID_PARAMETER
	if mode not in ["public", "create", "private"]: return ERR_INVALID_PARAMETER
	requested_hero = hero
	requested_name = player_name.strip_edges().left(16)
	# Know the secret before sending JOIN, including when its reply is lost.
	_resume_token = Crypto.new().generate_random_bytes(32).hex_encode()
	_monitor_only = false
	_joining_match = true
	connection_changed.emit("已连接，等待另一位玩家…")
	_join.rpc_id(1, PROTOCOL, requested_hero, requested_name, game_version, mode, code, _resume_token)
	return OK

func is_reconnecting() -> bool:
	return _reconnecting

func reconnect_remaining_msec() -> int:
	return maxi(0, _resume_deadline-Time.get_ticks_msec()) if _reconnecting else 0

func is_server_ready() -> bool:
	return not server_mode and connection_state == "connected" \
		and not _leaving and _pending_cancel_token.is_empty() \
		and not game_version.is_empty() and server_version == game_version \
		and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer) \
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED \
		and _last_reply >= 0 and Time.get_ticks_msec() - _last_reply < STATUS_TIMEOUT_MS

## Shipped with the client. No player preference or command-line address override.
func configured_endpoint() -> Dictionary:
	if not _endpoint_loaded:
		_endpoint_loaded = true
		var config: Variant = JSON.parse_string(FileAccess.get_file_as_string(SERVER_CONFIG))
		if config is Dictionary:
			var address := str(config.get("address", "")).strip_edges()
			var port := int(config.get("port", DEFAULT_PORT))
			var transport := str(config.get("transport", DEFAULT_TRANSPORT))
			var url := str(config.get("url", ""))
			if not address.is_empty() and port >= 1024 and port <= 65535 and transport in ["websocket", "enet"]:
				_endpoint = {"address":address, "port":port, "transport":transport}
				if url.begins_with("ws://") or url.begins_with("wss://"): _endpoint.url = url
	return _endpoint.duplicate()

func monitor_server() -> void:
	if server_mode: return
	if configured_endpoint().is_empty():
		_set_server_status("unconfigured")
		return
	# Keep the same connection while choosing a hero and waiting for an opponent.
	if _monitor_only or _reconnecting or not _resume_token.is_empty(): return
	leave()
	_monitor_only = true
	_open_client(str(_endpoint.address), int(_endpoint.port))

func _open_client(address: String, port: int) -> Error:
	var peer: MultiplayerPeer
	var error := ERR_INVALID_PARAMETER
	var transport := str(_endpoint.get("transport", DEFAULT_TRANSPORT))
	if transport == "websocket":
		var socket := _websocket_peer()
		var host := "[%s]" % address if ":" in address else address
		var url := str(_endpoint.get("url", "ws://%s:%d" % [host, port]))
		error = socket.create_client(url)
		peer = socket
	elif transport == "enet":
		var udp := ENetMultiplayerPeer.new()
		error = udp.create_client(address, port, ENET_CHANNELS)
		peer = udp
	if error != OK:
		_set_server_status("failed")
		_retry_at = Time.get_ticks_msec() + STATUS_RETRY_MS
		return error
	multiplayer.multiplayer_peer = peer
	_connected_at = Time.get_ticks_msec()
	_set_server_status("reconnecting" if _reconnecting else "connecting")
	if not _monitor_only: connection_changed.emit("正在连接服务器…")
	return OK

func _connected() -> void:
	_last_server_message = Time.get_ticks_msec()
	_configure_enet_timeout(1)
	# RPC status probes already keep the TCP connection alive. Do not enable
	# a shorter WebSocket ping watchdog that could override the stall grace.
	_probe_server()

func _set_server_status(value: String, ping: int = -1, count: int = -1) -> void:
	connection_state = value
	latency_ms = ping
	online_count = count
	server_status_changed.emit()

func _probe_server() -> void:
	_last_probe = Time.get_ticks_msec()
	for stamp in _probe_stamps.keys():
		if _last_probe - int(stamp) >= STATUS_TIMEOUT_MS: _probe_stamps.erase(stamp)
	_probe_stamps[_last_probe] = true
	_server_probe.rpc_id(1, PROTOCOL, _last_probe)

# A lost heartbeat is replaced next second, never queued behind old snapshots.
@rpc("any_peer", "call_remote", "unreliable", 0)
func _server_probe(protocol: int, stamp: int) -> void:
	pass # Protocol declaration only; this client never handles server requests.

@rpc("authority", "call_remote", "unreliable", 0)
func _server_status(protocol: int, stamp: int, count: int, version: String = "") -> void:
	if server_mode or not _probe_stamps.has(stamp): return
	_probe_stamps.erase(stamp)
	_last_server_message = Time.get_ticks_msec()
	_last_reply = Time.get_ticks_msec()
	server_version = version
	if protocol != PROTOCOL or game_version.is_empty() or version != game_version:
		if _reconnecting:
			_reconnect_failed(VERSION_MISMATCH_NOTICE)
			return
		_set_server_status("incompatible")
		return
	if _reconnecting:
		_set_server_status("reconnecting")
		if not _resume_sent:
			_resume_sent = true
			_resume.rpc_id(1, PROTOCOL, _resume_token, game_version)
		return
	_set_server_status("connected" if _pending_cancel_token.is_empty() else "cancelling", maxi(0, _last_reply - stamp), clampi(count, 0, MAX_CONNECTIONS))
	_send_pending_cancel()

func _send_pending_cancel() -> void:
	if _pending_cancel_token.is_empty() or _leaving: return
	var now := Time.get_ticks_msec()
	if _cancel_sent_at >= 0 and now - _cancel_sent_at < RECONNECT_RETRY_MS: return
	_cancel_sent_at = now
	_cancel_session.rpc_id(1, PROTOCOL, _pending_cancel_token, game_version)

@rpc("authority", "call_remote", "unreliable", 0)
func _presence_changed(count: int) -> void:
	if server_mode or connection_state != "connected": return
	online_count = clampi(count, 0, MAX_CONNECTIONS)
	server_status_changed.emit()

func _poll_server_status() -> void:
	if _leaving: return
	var now := Time.get_ticks_msec()
	var status := multiplayer.multiplayer_peer.get_connection_status()
	if _reconnecting:
		if now >= _resume_deadline:
			_reconnect_failed("等待重连已超时，请返回主菜单。")
			return
		if multiplayer.multiplayer_peer is OfflineMultiplayerPeer or status == MultiplayerPeer.CONNECTION_DISCONNECTED:
			if now >= _retry_at and not _endpoint.is_empty():
				_resume_sent = false
				_retry_at = now + RECONNECT_RETRY_MS
				_open_client(str(_endpoint.address), int(_endpoint.port))
			return
		if now-maxi(_connected_at, _last_server_message) >= 5000:
			_retry_reconnect()
			return
	if _monitor_only and (multiplayer.multiplayer_peer is OfflineMultiplayerPeer or status == MultiplayerPeer.CONNECTION_DISCONNECTED):
		if now >= _retry_at: _open_client(str(_endpoint.address), int(_endpoint.port))
		return
	if _monitor_only and now - maxi(_connected_at, _last_reply) >= STATUS_TIMEOUT_MS:
		_connection_failed()
		return
	if not _monitor_only and not _reconnecting and not _resume_token.is_empty() and status == MultiplayerPeer.CONNECTION_DISCONNECTED:
		_begin_reconnect()
		return
	if status != MultiplayerPeer.CONNECTION_CONNECTED or multiplayer.multiplayer_peer is OfflineMultiplayerPeer: return
	# During a match, a short stall must not close an otherwise healthy
	# connection. A genuinely silent connection still has a bounded lifetime.
	if not _monitor_only and now - maxi(_connected_at, _last_server_message) >= SESSION_TIMEOUT_MS:
		print("PVP_CLIENT_SESSION_TIMEOUT silent_ms=%d" % (now - _last_server_message))
		_server_lost()
		return
	if _last_probe < 0 or now - _last_probe >= STATUS_INTERVAL_MS: _probe_server()

@rpc("any_peer", "call_remote", "reliable", 2)
func _join(protocol: int, hero: String, player_name: String, version: String = "", mode: String = "public", code: String = "", token: String = "") -> void:
	pass # Protocol declaration only; this client never handles server requests.

@rpc("authority", "call_remote", "reliable", 2)
func _session(token: String, resumed: bool) -> void:
	if server_mode or _leaving or not _pending_cancel_token.is_empty(): return
	if not resumed and (_monitor_only or token != _resume_token): return
	_resume_token = token
	_last_server_message = Time.get_ticks_msec()
	if resumed:
		_await_resume_state = true
		# Credentials and full snapshots use different reliable channels.
		# Either may arrive first; unlock only after receiving both.
		if _reconnecting and _resume_state_received:
			_complete_resume()
			connection_changed.emit("已恢复对局。")

func _complete_resume() -> void:
	_reconnecting = false
	_await_resume_state = false
	_resume_state_received = false
	_resume_sent = false
	_deferred_acks.clear()
	_command_serial = 0
	_set_server_status("connected")

@rpc("any_peer", "call_remote", "reliable", 2)
func _resume(protocol: int, token: String, version: String) -> void:
	pass # Protocol declaration only; this client never handles server requests.

@rpc("any_peer", "call_remote", "reliable", 2)
func _abandon() -> void:
	pass # Protocol declaration only; this client never handles server requests.

@rpc("authority", "call_remote", "reliable", 2)
func _abandoned() -> void:
	if not server_mode: _leave_confirmed = true

@rpc("any_peer", "call_remote", "reliable", 2)
func _cancel_session(protocol: int, token: String, version: String) -> void:
	pass # Protocol declaration only; this client never handles server requests.

@rpc("authority", "call_remote", "reliable", 2)
func _cancelled(token: String) -> void:
	if server_mode or token != _pending_cancel_token: return
	_pending_cancel_token = ""
	_cancel_sent_at = -1
	if not _leaving and connection_state == "cancelling":
		_set_server_status("connected", latency_ms, online_count)
	else:
		server_status_changed.emit()

@rpc("authority", "call_remote", "reliable", 2)
func _reject(text: String) -> void:
	if _reconnecting:
		_reconnect_failed(text)
		return
	_joining_match = false
	_resume_token = ""
	_monitor_only = true
	if text == VERSION_MISMATCH_NOTICE: _set_server_status("incompatible")
	connection_changed.emit(text)

func send_intent(intent: Dictionary) -> void:
	if _reconnecting:
		notice.emit("正在等待恢复连接。")
		return
	if latest.is_empty() or multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		notice.emit("尚未连接到对局。")
		return
	var request := intent.duplicate(true)
	request.match_id = latest.get("match_id", "")
	request.turn_token = latest.get("turn_token", -1)
	if latest.has("draft"):
		request.draft_turn = latest.draft.turn
	_command_serial += 1
	request.request_id = _command_serial
	_request.rpc_id(1, request)

## Read-only recovery uses the existing RPC, without an action serial or ACK.
func request_match_state(match_id: String) -> Error:
	if server_mode or _leaving or _reconnecting or _monitor_only or connection_state != "connected": return ERR_UNAVAILABLE
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED: return ERR_UNAVAILABLE
	if match_id.is_empty() or str(latest.get("match_id", "")) != match_id: return ERR_INVALID_PARAMETER
	_request.rpc_id(1, {"kind":"sync", "match_id":match_id})
	return OK

## A live heartbeat does not prove the reliable state channel is progressing.
func recover_match_connection(match_id: String) -> Error:
	if server_mode or _leaving or _reconnecting or _monitor_only or _resume_token.is_empty(): return ERR_UNAVAILABLE
	if match_id.is_empty() or str(latest.get("match_id", "")) != match_id: return ERR_INVALID_PARAMETER
	_begin_reconnect()
	return OK

@rpc("any_peer", "call_remote", "reliable", 2)
func _request(request: Dictionary) -> void:
	pass # Protocol declaration only; this client never handles server requests.

@rpc("authority", "call_remote", "reliable", 1)
func _receive(state: Dictionary) -> void:
	if server_mode or _leaving or not _pending_cancel_token.is_empty(): return
	var decoded := PvpSnapshotCodec.decode(state)
	if decoded.is_empty():
		push_error("PVP_INVALID_SNAPSHOT")
		return
	latest = decoded
	History.observe(decoded)
	_last_server_message = Time.get_ticks_msec()
	if _reconnecting: _resume_state_received = true
	var resumed := _reconnecting and _await_resume_state
	if resumed:
		_complete_resume()
	state_received.emit(decoded)
	if resumed: connection_changed.emit("已恢复对局。")
	for result in _deferred_acks.duplicate():
		if _ack_needs_state(result): continue
		_deferred_acks.erase(result)
		_finish_ack(result)

@rpc("authority", "call_remote", "reliable", 2)
func _ack(result: Dictionary) -> void:
	_last_server_message = Time.get_ticks_msec()
	if _ack_needs_state(result):
		_deferred_acks.append(result)
		return
	_finish_ack(result)

func _ack_needs_state(result: Dictionary) -> bool:
	if not result.has("revision"): return false
	return result.get("match_id", "") != latest.get("match_id", "") or int(result.revision) > int(latest.get("revision", -1))

func _finish_ack(result: Dictionary) -> void:
	command_finished.emit(result)
	if result.has("error"): notice.emit(str(result.error))

func _process(_delta: float) -> void:
	_poll_server_status()

func _configure_enet_timeout(peer_id: int) -> void:
	var transport := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if transport == null: return
	var peer := transport.get_peer(peer_id)
	# Let the existing application watchdogs handle short stalls first.
	if peer != null: peer.set_timeout(32, SESSION_TIMEOUT_MS, SERVER_IDLE_TIMEOUT_MS)

func _server_lost() -> void:
	if server_mode: return
	if _leaving: return
	print("PVP_CLIENT_SERVER_LOST phase=%d last_status_ago_ms=%d" % [latest.get("phase", -1), Time.get_ticks_msec() - _last_reply])
	if not _resume_token.is_empty():
		_begin_reconnect()
		return
	var monitoring := _monitor_only
	leave()
	_monitor_only = monitoring
	_retry_at = Time.get_ticks_msec() + STATUS_RETRY_MS
	connection_changed.emit("服务器已断开连接。")

func _connection_failed() -> void:
	if server_mode: return
	if _leaving: return
	if _reconnecting:
		_retry_reconnect()
		return
	var monitoring := _monitor_only
	leave()
	_monitor_only = monitoring
	_retry_at = Time.get_ticks_msec() + STATUS_RETRY_MS
	_set_server_status("failed")
	connection_changed.emit("连接失败：请先启动服务器并检查地址／端口。")

func _begin_reconnect() -> void:
	if not _reconnecting:
		_reconnecting = true
		_resume_deadline = Time.get_ticks_msec() + RECONNECT_GRACE_MS
	_retry_reconnect()
	_retry_at = Time.get_ticks_msec()
	connection_changed.emit("连接暂时中断，正在恢复对局。")

func _retry_reconnect() -> void:
	var peer := multiplayer.multiplayer_peer
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if peer != null: peer.close()
	_resume_sent = false
	_await_resume_state = false
	_resume_state_received = false
	_probe_stamps.clear()
	_retry_at = Time.get_ticks_msec() + RECONNECT_RETRY_MS
	_set_server_status("reconnecting")

func _reconnect_failed(text: String) -> void:
	# Retire our own failed attempt before a later match, even if the reconnect
	# reply was lost. The cancellation can only affect this secret's session.
	if not _resume_token.is_empty(): _pending_cancel_token = _resume_token
	_resume_token = ""
	leave()
	_set_server_status("incompatible" if text == VERSION_MISMATCH_NOTICE else "failed")
	connection_changed.emit(text)

func _notification(what: int) -> void:
	if server_mode: return
	if what == NOTIFICATION_APPLICATION_PAUSED:
		_backgrounded = true
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		_backgrounded = false
		# Give the resumed transport a chance to poll queued heartbeats before
		# interpreting the entire OS suspension as a live connection timeout.
		_last_server_message = Time.get_ticks_msec()
		_connected_at = Time.get_ticks_msec()
		_last_probe = -1
		if _reconnecting: _retry_at = Time.get_ticks_msec()

func leave() -> void:
	if _leaving: return
	if not server_mode and not _resume_token.is_empty():
		_pending_cancel_token = _resume_token
		_cancel_sent_at = -1
	if not server_mode and not _resume_token.is_empty() and not _reconnecting \
			and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_leaving = true
		_leave_confirmed = false
		# The cancellation is authenticated by the session, not the old peer ID.
		_cancel_session.rpc_id(1, PROTOCOL, _pending_cancel_token, game_version)
		var deadline := Time.get_ticks_msec()+1000
		while not _pending_cancel_token.is_empty() and Time.get_ticks_msec() < deadline and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			await get_tree().process_frame
		# Let SceneMultiplayer finish its RPC path-cache acknowledgement before
		# retiring the ENet peer that delivered the explicit-leave reply.
		if _pending_cancel_token.is_empty(): await get_tree().process_frame
		var transport := multiplayer.multiplayer_peer as ENetMultiplayerPeer
		if transport != null and transport.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			transport.disconnect_peer(1)
			await get_tree().create_timer(0.1).timeout
		_leaving = false
	if not server_mode: History.interrupted()
	var old_transport := multiplayer.multiplayer_peer
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if old_transport != null: old_transport.close()
	latest.clear()
	_deferred_acks.clear()
	_command_serial = 0
	_monitor_only = false
	_joining_match = false
	_retry_at = 0
	_connected_at = 0
	_last_probe = -1
	_probe_stamps.clear()
	_last_reply = -1
	_last_server_message = -1
	_resume_token = ""
	_reconnecting = false
	_resume_deadline = 0
	_resume_sent = false
	_await_resume_state = false
	_resume_state_received = false
	_backgrounded = false
	_leave_confirmed = false
	server_version = ""
	_set_server_status("disconnected")
