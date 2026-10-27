class_name PvpSnapshotCodec
extends RefCounted
## Compress the whole authoritative snapshot before multiplayer transport.
## Repeated descriptions, offers and purchased items otherwise consume tens
## of kilobytes per countdown tick. UI/rule dictionaries remain unchanged.

const MAX_BYTES := 4 * 1024 * 1024
const PACKED_KEY := "_compressed_state"

static func encode(state: Dictionary) -> Dictionary:
	var raw := var_to_bytes(state)
	if raw.size() < 512 or raw.size() > MAX_BYTES: return state
	var packed := raw.compress(FileAccess.COMPRESSION_ZSTD)
	if packed.is_empty() or packed.size() + 96 >= raw.size(): return state
	return {PACKED_KEY:packed, "raw_size":raw.size()}

static func decode(wire: Dictionary) -> Dictionary:
	if not wire.has(PACKED_KEY): return wire
	if not wire.get(PACKED_KEY) is PackedByteArray or not wire.get("raw_size") is int: return {}
	var size := int(wire.raw_size)
	var packed: PackedByteArray = wire[PACKED_KEY]
	if size <= 0 or size > MAX_BYTES or packed.is_empty() or packed.size() > MAX_BYTES: return {}
	var raw := packed.decompress(size, FileAccess.COMPRESSION_ZSTD)
	if raw.size() != size: return {}
	# bytes_to_var does not allow serialized objects/resources to execute code.
	var state: Variant = bytes_to_var(raw)
	return state if state is Dictionary else {}
