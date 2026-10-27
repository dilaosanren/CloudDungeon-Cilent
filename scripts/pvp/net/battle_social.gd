# Shared plaintext limits for in-match conversation.
extends RefCounted
const MAX_TEXT_LENGTH := 80
const MAX_MESSAGES := 30
const MESSAGE_INTERVAL_MSEC := 1000

static func valid_text(value: Variant) -> bool:
	if not value is String or value.length() > MAX_TEXT_LENGTH or value.strip_edges().is_empty(): return false
	for i in value.length():
		if value.unicode_at(i) < 32 or value.unicode_at(i) == 127: return false
	return true
