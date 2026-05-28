## Validates and repairs LLM JSON responses.
## Falls back to treating raw text as narration if JSON parsing fails.

extends Node


func parse_response(raw_text: String) -> Dictionary:
	var text := raw_text.strip_edges()

	# Strip markdown code fences: ```json ... ``` or ``` ... ```
	if text.begins_with("```"):
		var newline_pos := text.find("\n")
		if newline_pos >= 0:
			text = text.substr(newline_pos + 1)
		if text.ends_with("```"):
			text = text.substr(0, text.length() - 3)
		text = text.strip_edges()

	# Attempt direct JSON parse
	var parsed := _try_parse_json(text)
	if parsed.is_empty():
		# Try to extract JSON object embedded in text
		parsed = _extract_json_object(text)

	if parsed.is_empty():
		# Total failure — treat whole response as narration
		return _make_narration_only(raw_text)

	# Validate and normalize the structure
	return _normalize_response(parsed, raw_text)


func _try_parse_json(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) == OK and json.data is Dictionary:
		return json.data
	return {}


func _extract_json_object(text: String) -> Dictionary:
	# Find the outermost { ... } brace pair
	var depth := 0
	var start := -1
	for i in range(text.length()):
		var ch := text[i]
		if ch == "{":
			if depth == 0:
				start = i
			depth += 1
		elif ch == "}":
			depth -= 1
			if depth == 0 and start >= 0:
				var substring := text.substr(start, i - start + 1)
				var json := JSON.new()
				if json.parse(substring) == OK and json.data is Dictionary:
					return json.data
				# Reset and keep looking
				start = -1
	return {}


func _normalize_response(data: Dictionary, raw_text: String) -> Dictionary:
	# Ensure "narration" key exists
	if not data.has("narration"):
		data["narration"] = raw_text

	# Ensure narration is a string
	if data.narration is not String:
		data["narration"] = str(data.narration)

	# Ensure "state_changes" exists and is a Dictionary
	if not data.has("state_changes"):
		data["state_changes"] = {}

	if data.state_changes is not Dictionary:
		data["state_changes"] = {}

	var sc: Dictionary = data.state_changes

	# Normalize each state_changes sub-key
	sc["flags"] = _ensure_dict(sc, "flags")
	sc["inventory_add"] = _ensure_string_array(sc, "inventory_add")
	sc["inventory_remove"] = _ensure_string_array(sc, "inventory_remove")
	sc["npc_updates"] = _ensure_dict(sc, "npc_updates")

	# Normalize new_room
	if sc.has("new_room"):
		if sc.new_room == null or sc.new_room == "":
			sc["new_room"] = null
		elif sc.new_room is String:
			pass  # valid
		else:
			sc["new_room"] = str(sc.new_room)
	else:
		sc["new_room"] = null

	return data


func _ensure_dict(parent: Dictionary, key: String) -> Dictionary:
	if parent.has(key) and parent[key] is Dictionary:
		return parent[key]
	return {}


func _ensure_string_array(parent: Dictionary, key: String) -> Array:
	if not parent.has(key) or parent[key] is not Array:
		return []
	var result: Array = []
	for item in parent[key]:
		if item is String:
			result.append(item)
	return result


func _make_narration_only(text: String) -> Dictionary:
	return {
		"narration": text,
		"state_changes": {
			"flags": {},
			"inventory_add": [],
			"inventory_remove": [],
			"new_room": null,
			"npc_updates": {},
		}
	}
