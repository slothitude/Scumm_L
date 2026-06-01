## Async HTTP client for the image generation service.
## Dispatches generation requests to image_service.py (port 8010).
## Checks disk cache first, decodes base64 PNG to Texture2D.

extends Node

signal image_received(img_id: String, img_type: String, texture: Texture2D)
signal image_failed(img_id: String, img_type: String, error: String)

var _cache: Node
var _pending: Array[Dictionary] = []
var _request_nodes: Array[HTTPRequest] = []
const POOL_SIZE := 3


func _ready() -> void:
	_cache = Node.new()
	_cache.name = "ImageCache"
	_cache.set_script(load("res://core/image_cache.gd"))
	add_child(_cache)

	for i in range(POOL_SIZE):
		var http := HTTPRequest.new()
		http.name = "ImgHTTP_%d" % i
		http.timeout = GameConsts.IMAGE_GENERATION_TIMEOUT
		add_child(http)
		_request_nodes.append(http)


func request(img_id: String, img_type: String, prompt: String, size: int = 64) -> void:
	# Check disk cache first
	if _cache.is_cached(img_id, img_type):
		var tex: Texture2D = _cache.get_cached_texture(img_id, img_type)
		if tex != null:
			image_received.emit(img_id, img_type, tex)
			return

	# Find available HTTPRequest node
	var http: HTTPRequest = _get_available_node()
	if http == null:
		image_failed.emit(img_id, img_type, "No available request slots (max %d concurrent)" % POOL_SIZE)
		return

	var endpoint := "/generate/%s" % img_type
	var url := GameConsts.IMAGE_SERVICE_URL + endpoint
	var body := JSON.stringify({"prompt": prompt, "size": size, "id": img_id})
	var headers := PackedStringArray(["Content-Type: application/json"])

	var err := http.request_raw(url, headers, HTTPClient.METHOD_POST, body.to_utf8_buffer())
	if err != OK:
		image_failed.emit(img_id, img_type, "HTTP request failed: %d" % err)
		return

	_pending.append({"http": http, "img_id": img_id, "img_type": img_type})

	var cb := func(r: int, c: int, _h: PackedStringArray, b: PackedByteArray):
		_handle_completed(http, img_id, img_type, r, c, b)
	http.request_completed.connect(cb, CONNECT_ONE_SHOT)


func _get_available_node() -> HTTPRequest:
	for node in _request_nodes:
		var busy := false
		for p in _pending:
			if p["http"] == node:
				busy = true
				break
		if not busy:
			return node
	return null


func _handle_completed(http: HTTPRequest, img_id: String, img_type: String,
		result: int, code: int, body: PackedByteArray) -> void:
	# Remove from pending
	for i in range(_pending.size() - 1, -1, -1):
		if _pending[i]["http"] == http:
			_pending.remove_at(i)
			break

	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		image_failed.emit(img_id, img_type, "HTTP error: result=%d code=%d" % [result, code])
		return

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		image_failed.emit(img_id, img_type, "Failed to parse response JSON")
		return

	var data: Dictionary = json.data
	var img_b64: String = data.get("image_b64", "")

	if img_b64 == "":
		image_failed.emit(img_id, img_type, "Empty image data in response")
		return

	var raw := Marshalls.base64_to_raw(img_b64)
	var img := Image.new()
	if img.load_png_from_buffer(raw) != OK:
		image_failed.emit(img_id, img_type, "Failed to decode PNG")
		return

	var texture := ImageTexture.create_from_image(img)
	_cache.save_to_cache(img_id, img_type, texture)
	image_received.emit(img_id, img_type, texture)
