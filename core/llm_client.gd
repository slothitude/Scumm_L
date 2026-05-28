## HTTP-based LLM client with 3-tier fallback cascade.
## Tier 1: Z.ai GLM-5.1 → Tier 2: LiteLLM proxy → Tier 3: Ollama direct
## Pattern reused from rabbit_reporter.py and exploring/note/agent_node.gd

extends Node

signal response_received(raw_text: String)
signal request_failed(error: String)
signal request_status(status: String)

var _http: HTTPRequest
var _fallback_tier: int = 0
var _current_messages: Array = []
var _is_busy: bool = false


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = GameConsts.LLM_TIMEOUT
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)


func send_prompt(messages: Array) -> void:
	if _is_busy:
		request_failed.emit("LLM is busy — please wait")
		return

	_is_busy = true
	_fallback_tier = 0
	_current_messages = messages
	request_status.emit("Thinking (Z.ai)...")
	_send_to_current_tier()


func is_busy() -> bool:
	return _is_busy


func _send_to_current_tier() -> void:
	var config := _get_tier_config()
	if config.url == "":
		_finish_failure("No LLM endpoint configured")
		return

	var headers := ["Content-Type: application/json"]
	if config.api_key != "":
		headers.append("Authorization: Bearer %s" % config.api_key)

	var body := JSON.stringify({
		"model": config.model,
		"messages": _current_messages,
		"stream": false,
		"temperature": GameConsts.LLM_TEMPERATURE,
	})

	var err := _http.request(config.url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		print("[LLM] Request error %d" % err)
		_try_fallback()


func _get_tier_config() -> Dictionary:
	match _fallback_tier:
		0:
			return {
				"url": GameConsts.ZAI_URL,
				"model": GameConsts.ZAI_MODEL,
				"api_key": GameConsts.ZAI_KEY,
			}
		1:
			return {
				"url": GameConsts.LITELLM_URL,
				"model": GameConsts.LITELLM_MODEL,
				"api_key": GameConsts.LITELLM_KEY,
			}
		2:
			return {
				"url": GameConsts.OLLAMA_URL,
				"model": GameConsts.OLLAMA_MODEL,
				"api_key": GameConsts.OLLAMA_KEY,
			}
		_:
			return {"url": "", "model": "", "api_key": ""}


func _try_fallback() -> void:
	_fallback_tier += 1
	if _fallback_tier <= 2:
		var tier_names := ["Z.ai", "LiteLLM", "Ollama"]
		print("[LLM] Falling back to tier %d (%s)" % [_fallback_tier, tier_names[_fallback_tier]])
		request_status.emit("Trying %s..." % tier_names[_fallback_tier])
		_send_to_current_tier()
	else:
		_finish_failure("All LLM endpoints failed")


func _on_request_completed(_result: int, _code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if not _is_busy:
		return

	# Connection/transport error
	if _result != HTTPRequest.RESULT_SUCCESS:
		print("[LLM] Transport error (result=%d)" % _result)
		_try_fallback()
		return

	# HTTP error (4xx, 5xx)
	if _code >= 400:
		var response_text := body.get_string_from_utf8()
		print("[LLM] HTTP %d: %s" % [_code, response_text.left(200)])
		_try_fallback()
		return

	var response_str := body.get_string_from_utf8()
	var json := JSON.new()
	var parse_err := json.parse(response_str)
	if parse_err != OK:
		print("[LLM] Invalid JSON response")
		_try_fallback()
		return

	var data: Dictionary = json.data
	var content: String = ""

	# OpenAI format: {choices: [{message: {content: "..."}}]}
	if data.has("choices") and data.choices.size() > 0:
		content = data.choices[0].get("message", {}).get("content", "")
	# Ollama format: {message: {content: "..."}}
	elif data.has("message"):
		content = data.message.get("content", "")

	if content == "":
		print("[LLM] Empty content in response")
		_try_fallback()
		return

	_is_busy = false
	request_status.emit("")
	response_received.emit(content)


func _finish_failure(error: String) -> void:
	_is_busy = false
	request_status.emit("Error")
	print("[LLM] Failed: %s" % error)
	request_failed.emit(error)
