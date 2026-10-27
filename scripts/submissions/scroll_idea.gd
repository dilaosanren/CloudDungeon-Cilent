# Shared plaintext submission validation; never executes a player's idea.
extends RefCounted
const MAX_LENGTH := 150
const MAX_AUTHOR := 16

static func validate(value: Dictionary) -> Dictionary:
	if not value.get("idea") is String or not value.get("author", "") is String:
		return {"error":"投稿格式无效。"}
	var text: String = value.idea
	var author: String = value.get("author", "")
	if text.length() > MAX_LENGTH: return {"error":"秘卷设计想法最多150字。"}
	text = text.replace("\r\n", "\n").replace("\r", "\n")
	if author.length() > MAX_AUTHOR: return {"error":"玩家名字最多16字。"}
	for i in text.length():
		if text.unicode_at(i) < 32 and text.unicode_at(i) not in [9, 10]: return {"error":"投稿格式无效。"}
	for i in author.length():
		if author.unicode_at(i) < 32: return {"error":"投稿格式无效。"}
	text = text.strip_edges()
	if text.is_empty(): return {"error":"请先填写秘卷设计想法。"}
	return {"data":{"idea":text, "author":author.strip_edges()}}

static func identity(data: Dictionary) -> String:
	return JSON.stringify([data.author, data.idea]).sha256_text().left(32)
