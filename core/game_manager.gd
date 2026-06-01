## Main scene orchestrator for SCUMM-L.
## Builds UI programmatically, wires signals, handles input → LLM → state update flow.
## Uses RoomRenderer for 3D scene with Kenney GLB models.
## Integrates image_client for AI-generated visuals.

extends Node

var game_state: Node
var llm_client: Node
var prompt_builder: Node
var response_parser: Node
var room_renderer: Node
var image_client: Node
var _ui_icons: RefCounted

# UI references
var root_control: Control
var room_title: Label
var room_area_host: Control  # Container that holds the SubViewportContainer
var narration_box: RichTextLabel
var input_field: LineEdit
var send_button: Button
var status_label: Label
var inventory_label: Label

# New UI references (image integration)
var verb_bar: HBoxContainer
var inventory_bar: HBoxContainer
var portrait_panel: TextureRect
var closeup_overlay: PanelContainer
var room_bg_texture: TextureRect

# Known image IDs (to avoid re-requesting)
var _known_image_ids: Array[String] = []


func _ready() -> void:
	game_state = get_node("/root/GameState")

	# Create core child nodes (not autoloads — owned by game_manager)
	prompt_builder = Node.new()
	prompt_builder.name = "PromptBuilder"
	prompt_builder.set_script(load("res://core/prompt_builder.gd"))
	add_child(prompt_builder)

	response_parser = Node.new()
	response_parser.name = "ResponseParser"
	response_parser.set_script(load("res://core/response_parser.gd"))
	add_child(response_parser)

	llm_client = Node.new()
	llm_client.name = "LLMClient"
	llm_client.set_script(load("res://core/llm_client.gd"))
	add_child(llm_client)

	room_renderer = Node.new()
	room_renderer.name = "RoomRenderer"
	room_renderer.set_script(load("res://core/room_renderer.gd"))
	add_child(room_renderer)

	image_client = Node.new()
	image_client.name = "ImageClient"
	image_client.set_script(load("res://core/image_client.gd"))
	add_child(image_client)

	_ui_icons = RefCounted.new()
	_ui_icons.set_script(load("res://core/ui_icons.gd"))

	_build_ui()
	_wire_signals()
	_show_room(game_state.current_room)


# ============================================================
# UI Construction
# ============================================================

func _build_ui() -> void:
	# Root fills the viewport
	root_control = Control.new()
	root_control.name = "RootUI"
	root_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root_control)

	# Dark background
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = GameConsts.COLOR_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_control.add_child(bg)

	# --- Top bar: room title + inventory ---
	var top_bar := HBoxContainer.new()
	top_bar.name = "TopBar"
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_bottom = 50
	top_bar.add_theme_constant_override("separation", 20)
	root_control.add_child(top_bar)

	room_title = Label.new()
	room_title.name = "RoomTitle"
	room_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	room_title.add_theme_font_size_override("font_size", 26)
	room_title.add_theme_color_override("font_color", GameConsts.COLOR_ACCENT)
	room_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(room_title)

	inventory_label = Label.new()
	inventory_label.name = "InventoryLabel"
	inventory_label.add_theme_font_size_override("font_size", 14)
	inventory_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.5))
	inventory_label.custom_minimum_size = Vector2(200, 0)
	inventory_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top_bar.add_child(inventory_label)
	_update_inventory_display()

	# --- Middle: room area host (holds 3D SubViewportContainer) ---
	room_area_host = Control.new()
	room_area_host.name = "RoomArea"
	room_area_host.anchor_left = 0.0
	room_area_host.anchor_top = 0.0
	room_area_host.anchor_right = 1.0
	room_area_host.anchor_bottom = 1.0
	room_area_host.offset_left = 40
	room_area_host.offset_top = 55
	room_area_host.offset_right = -40
	room_area_host.offset_bottom = -280  # Make room for verb bar + inventory bar
	# Dark background behind 3D viewport
	var room_bg := ColorRect.new()
	room_bg.name = "RoomBG"
	room_bg.color = Color(0.04, 0.03, 0.06)
	room_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	room_area_host.add_child(room_bg)

	# Room background texture (behind 3D viewport)
	room_bg_texture = TextureRect.new()
	room_bg_texture.name = "RoomBGTexture"
	room_bg_texture.set_anchors_preset(Control.PRESET_FULL_RECT)
	room_bg_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	room_bg_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	room_bg_texture.modulate = Color(1, 1, 1, 0.85)  # Visible behind 3D viewport
	room_bg_texture.visible = false
	room_area_host.add_child(room_bg_texture)

	root_control.add_child(room_area_host)

	# --- Verb action bar (icon toolbar) ---
	verb_bar = HBoxContainer.new()
	verb_bar.name = "VerbBar"
	verb_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	verb_bar.anchor_left = 0.0
	verb_bar.anchor_right = 1.0
	verb_bar.anchor_top = 1.0
	verb_bar.anchor_bottom = 1.0
	verb_bar.offset_left = 40
	verb_bar.offset_top = -230
	verb_bar.offset_right = -40
	verb_bar.offset_bottom = -200
	verb_bar.add_theme_constant_override("separation", 8)
	_build_verb_bar()
	root_control.add_child(verb_bar)

	# --- Inventory bar (icon slots) ---
	inventory_bar = HBoxContainer.new()
	inventory_bar.name = "InventoryBar"
	inventory_bar.alignment = BoxContainer.ALIGNMENT_BEGIN
	inventory_bar.anchor_left = 0.0
	verb_bar.anchor_top = 1.0
	inventory_bar.anchor_left = 0.0
	inventory_bar.anchor_right = 1.0
	inventory_bar.anchor_top = 1.0
	inventory_bar.anchor_bottom = 1.0
	inventory_bar.offset_left = 40
	inventory_bar.offset_top = -195
	inventory_bar.offset_right = -40
	inventory_bar.offset_bottom = -160
	inventory_bar.add_theme_constant_override("separation", 4)
	root_control.add_child(inventory_bar)

	# --- Portrait panel (NPC portrait in narration area) ---
	portrait_panel = TextureRect.new()
	portrait_panel.name = "PortraitPanel"
	portrait_panel.custom_minimum_size = Vector2(64, 64)
	portrait_panel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_panel.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_panel.visible = false
	root_control.add_child(portrait_panel)
	portrait_panel.z_index = 10  # Above other content
	# Position top-left of narration area
	portrait_panel.anchor_left = 0.0
	portrait_panel.anchor_top = 1.0
	portrait_panel.anchor_right = 0.0
	portrait_panel.anchor_bottom = 1.0
	portrait_panel.offset_left = 45
	portrait_panel.offset_top = -155
	portrait_panel.offset_right = 115
	portrait_panel.offset_bottom = -85

	# --- Closeup overlay (centered panel for object detail views) ---
	closeup_overlay = PanelContainer.new()
	closeup_overlay.name = "CloseupOverlay"
	closeup_overlay.set_anchors_preset(Control.PRESET_CENTER)
	closeup_overlay.offset_left = -280
	closeup_overlay.offset_top = -280
	closeup_overlay.offset_right = 280
	closeup_overlay.offset_bottom = 280
	closeup_overlay.visible = false
	var closeup_vbox := VBoxContainer.new()
	closeup_vbox.name = "CloseupVBox"
	closeup_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	closeup_overlay.add_child(closeup_vbox)

	var closeup_img := TextureRect.new()
	closeup_img.name = "CloseupImage"
	closeup_img.custom_minimum_size = Vector2(512, 512)
	closeup_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	closeup_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	closeup_vbox.add_child(closeup_img)

	var closeup_label := Label.new()
	closeup_label.name = "CloseupLabel"
	closeup_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	closeup_label.add_theme_font_size_override("font_size", 14)
	closeup_label.add_theme_color_override("font_color", GameConsts.COLOR_TEXT)
	closeup_vbox.add_child(closeup_label)

	var closeup_dismiss := Button.new()
	closeup_dismiss.name = "CloseupDismiss"
	closeup_dismiss.text = "Close"
	closeup_dismiss.custom_minimum_size = Vector2(100, 0)
	closeup_vbox.add_child(closeup_dismiss)

	root_control.add_child(closeup_overlay)

	# --- Narration box ---
	narration_box = RichTextLabel.new()
	narration_box.name = "NarrationBox"
	narration_box.bbcode_enabled = true
	narration_box.scroll_following = true
	narration_box.add_theme_font_size_override("normal_font_size", 17)
	narration_box.add_theme_color_override("default_color", GameConsts.COLOR_TEXT)
	narration_box.anchor_left = 0.0
	narration_box.anchor_right = 1.0
	narration_box.anchor_bottom = 1.0
	narration_box.anchor_top = 1.0
	narration_box.offset_left = 40
	narration_box.offset_top = -155
	narration_box.offset_right = -40
	narration_box.offset_bottom = -60
	# Background panel — sibling behind RichTextLabel, not a child
	var narr_bg := ColorRect.new()
	narr_bg.name = "NarrationBG"
	narr_bg.color = GameConsts.COLOR_NARRATION_BG
	narr_bg.anchor_left = 0.0
	narr_bg.anchor_right = 1.0
	narr_bg.anchor_bottom = 1.0
	narr_bg.anchor_top = 1.0
	narr_bg.offset_left = 40
	narr_bg.offset_top = -155
	narr_bg.offset_right = -40
	narr_bg.offset_bottom = -60
	root_control.add_child(narr_bg)
	root_control.add_child(narration_box)

	# --- Bottom bar: input + status ---
	var bottom_bar := HBoxContainer.new()
	bottom_bar.name = "BottomBar"
	bottom_bar.anchor_left = 0.0
	bottom_bar.anchor_right = 1.0
	bottom_bar.anchor_bottom = 1.0
	bottom_bar.anchor_top = 1.0
	bottom_bar.offset_left = 40
	bottom_bar.offset_top = -50
	bottom_bar.offset_right = -40
	bottom_bar.offset_bottom = -10
	bottom_bar.add_theme_constant_override("separation", 10)
	root_control.add_child(bottom_bar)

	input_field = LineEdit.new()
	input_field.name = "InputField"
	input_field.placeholder_text = "Type an action... (examine, talk, use, go, or free text)"
	input_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_field.add_theme_font_size_override("font_size", 16)
	bottom_bar.add_child(input_field)

	send_button = Button.new()
	send_button.name = "SendButton"
	send_button.text = "Send"
	send_button.custom_minimum_size = Vector2(90, 0)
	bottom_bar.add_child(send_button)

	status_label = Label.new()
	status_label.name = "StatusLabel"
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5))
	status_label.custom_minimum_size = Vector2(150, 0)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bottom_bar.add_child(status_label)


func _build_verb_bar() -> void:
	var verbs := [
		{"verb": "examine", "label": "Look", "icon": _ui_icons.get_verb_icon("examine")},
		{"verb": "talk", "label": "Talk", "icon": _ui_icons.get_verb_icon("talk")},
		{"verb": "use", "label": "Use", "icon": _ui_icons.get_verb_icon("use")},
		{"verb": "take", "label": "Take", "icon": _ui_icons.get_verb_icon("take")},
		{"verb": "go", "label": "Go", "icon": _ui_icons.get_verb_icon("go")},
	]
	for v in verbs:
		var btn := Button.new()
		btn.name = "Verb_%s" % v.verb
		btn.text = v.label
		btn.tooltip_text = v.label
		btn.custom_minimum_size = Vector2(60, 0)
		# Load icon texture
		var tex := load(v.icon) if ResourceLoader.exists(v.icon) else null
		if tex:
			btn.icon = tex
			btn.flat = true
		btn.pressed.connect(_on_verb_pressed.bind(v.verb))
		verb_bar.add_child(btn)


# ============================================================
# Signal Wiring
# ============================================================

func _wire_signals() -> void:
	send_button.pressed.connect(_on_send_pressed)
	input_field.text_submitted.connect(_on_text_submitted)

	llm_client.response_received.connect(_on_llm_response)
	llm_client.request_failed.connect(_on_llm_failed)
	llm_client.request_status.connect(_on_llm_status)

	room_renderer.hotspot_clicked.connect(_on_hotspot_clicked)

	game_state.room_changed.connect(_on_room_changed)
	game_state.inventory_changed.connect(_on_inventory_changed)

	# Image client signals
	image_client.image_received.connect(_on_image_received)
	image_client.image_failed.connect(_on_image_failed)

	# Closeup dismiss button
	var dismiss_btn = closeup_overlay.get_node("CloseupVBox/CloseupDismiss")
	dismiss_btn.pressed.connect(func(): closeup_overlay.visible = false)


# ============================================================
# Room Rendering (3D)
# ============================================================

func _show_room(room_id: String) -> void:
	var room: Dictionary = game_state.get_room_data(room_id)
	if room.is_empty():
		narration_box.append_text("[color=red]Error: Room '%s' not found.[/color]\n" % room_id)
		return

	room_title.text = room.get("name", "Unknown")

	# Clear previous room viewport
	for child in room_area_host.get_children():
		if child.name != "RoomBG" and child.name != "RoomBGTexture":
			child.queue_free()

	# Build 3D room via room_renderer
	var viewport_container: SubViewportContainer = room_renderer.build_room(room_id, room)
	viewport_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	room_area_host.add_child(viewport_container)

	# Show room description on first visit
	if not game_state.has_flag("visited_%s" % room_id):
		narration_box.append_text("[i]%s[/i]\n\n" % room.get("description", ""))
		game_state.set_flag("visited_%s" % room_id, true)
	else:
		narration_box.append_text("[i]You return to %s.[/i]\n" % room.get("name", ""))


# ============================================================
# Player Input Handling
# ============================================================

func _on_hotspot_clicked(hotspot_id: String) -> void:
	if llm_client.is_busy():
		return

	var hotspot: Dictionary = game_state.get_hotspot_data(hotspot_id)
	var label: String = hotspot.get("label", hotspot_id) if not hotspot.is_empty() else hotspot_id

	narration_box.append_text("\n[color=aqua]> Examining [b]%s[/b]...[/color]\n" % label)
	game_state.add_to_history("user", "I examine the %s." % label)

	var messages: Array = prompt_builder.build_messages("examine", hotspot_id, game_state)
	llm_client.send_prompt(messages)


func _on_verb_pressed(verb: String) -> void:
	input_field.text = verb + " "
	input_field.grab_focus()


func _on_send_pressed() -> void:
	var text := input_field.text.strip_edges()
	if text == "" or llm_client.is_busy():
		return
	input_field.text = ""
	_submit_action(text)


func _on_text_submitted(text: String) -> void:
	var stripped := text.strip_edges()
	if stripped == "" or llm_client.is_busy():
		return
	input_field.text = ""
	_submit_action(stripped)


func _submit_action(text: String) -> void:
	narration_box.append_text("\n[color=aqua]> %s[/color]\n" % text)
	game_state.add_to_history("user", text)

	var action: Dictionary = _parse_action(text)
	var messages: Array = prompt_builder.build_messages(action["action"], action["target"], game_state)
	llm_client.send_prompt(messages)


func _parse_action(text: String) -> Dictionary:
	var lower := text.to_lower()

	# Detect verb patterns — multi-word verbs checked first with explicit offsets
	if lower.begins_with("look at "):
		return {"action": "examine", "target": text.substr(8).strip_edges()}
	if lower.begins_with("talk to "):
		return {"action": "talk", "target": text.substr(8).strip_edges()}
	if lower.begins_with("walk to "):
		return {"action": "go", "target": text.substr(8).strip_edges()}
	if lower.begins_with("pick up "):
		return {"action": "examine", "target": text.substr(8).strip_edges()}
	if lower.begins_with("go to "):
		return {"action": "go", "target": text.substr(6).strip_edges()}

	# Single-word verbs
	if lower.begins_with("examine "):
		return {"action": "examine", "target": text.substr(8).strip_edges()}
	if lower.begins_with("look "):
		return {"action": "examine", "target": text.substr(5).strip_edges()}
	if lower.begins_with("talk "):
		return {"action": "talk", "target": text.substr(5).strip_edges()}
	if lower.begins_with("use "):
		return {"action": "use", "target": text.substr(4).strip_edges()}
	if lower.begins_with("go "):
		return {"action": "go", "target": text.substr(3).strip_edges()}
	if lower.begins_with("walk "):
		return {"action": "go", "target": text.substr(5).strip_edges()}
	if lower.begins_with("take "):
		return {"action": "examine", "target": text.substr(5).strip_edges()}
	if lower.begins_with("grab "):
		return {"action": "examine", "target": text.substr(5).strip_edges()}

	# Default: free-text action
	return {"action": "custom", "target": text}


# ============================================================
# LLM Response Handling
# ============================================================

func _on_llm_response(raw_text: String) -> void:
	var parsed: Dictionary = response_parser.parse_response(raw_text)

	# Display narration
	var narration: String = parsed.get("narration", raw_text)
	narration_box.append_text("\n%s\n" % narration)
	game_state.add_to_history("assistant", narration)

	# Apply validated state changes immediately (don't wait for images)
	var changes: Dictionary = parsed.get("state_changes", {})

	# Validate room transition before applying
	var new_room = changes.get("new_room")
	if new_room != null and new_room != "":
		if game_state.rooms.has(new_room):
			game_state.apply_llm_changes(changes)
		else:
			# LLM hallucinated a room — skip room change, apply rest
			narration_box.append_text("[color=yellow](Unknown location mentioned — staying here.)[/color]\n")
			changes["new_room"] = null
			game_state.apply_llm_changes(changes)
	else:
		game_state.apply_llm_changes(changes)

	# Dispatch image requests (fire-and-forget)
	var image_requests: Array = parsed.get("image_requests", [])
	for req in image_requests:
		_dispatch_image_request(req)

	# Re-enable input
	input_field.editable = true
	send_button.disabled = false
	input_field.grab_focus()


func _dispatch_image_request(req: Dictionary) -> void:
	var img_type: String = req.get("type", "icon")
	var img_id: String = req.get("id", "")
	var prompt: String = req.get("prompt", "")
	var size: int = int(req.get("size", 64))

	if img_id == "" or prompt == "":
		return

	# Skip if already known
	if img_id in _known_image_ids:
		return

	image_client.request(img_id, img_type, prompt, size)


# ============================================================
# Image Response Handling
# ============================================================

func _on_image_received(img_id: String, img_type: String, texture: Texture2D) -> void:
	_known_image_ids.append(img_id)

	match img_type:
		"icon":
			_update_inventory_bar()
		"portrait":
			_show_portrait(img_id, texture)
		"dialogue_frame":
			_show_dialogue_frame(texture)
		"background":
			_show_room_background(texture)
		"atmosphere":
			_show_room_background(texture)
		"closeup":
			_show_closeup(texture)
		"pixelate":
			_update_inventory_bar()
		"cursor":
			_update_inventory_bar()
		"silhouette":
			_show_portrait(img_id, texture)
		"alpha":
			_show_portrait(img_id, texture)


func _on_image_failed(img_id: String, img_type: String, error: String) -> void:
	print("[ImageClient] Failed: %s/%s — %s" % [img_type, img_id, error])
	# Show placeholder on failure
	var placeholder := _make_placeholder(img_type, img_id)
	if placeholder:
		match img_type:
			"portrait":
				_show_portrait(img_id, placeholder)
			"dialogue_frame":
				_show_dialogue_frame(placeholder)
			"silhouette":
				_show_portrait(img_id, placeholder)
			"closeup":
				_show_closeup(placeholder)


func _make_placeholder(img_type: String, img_id: String) -> Texture2D:
	var size := 64
	match img_type:
		"portrait": size = 256
		"dialogue_frame": size = 280
		"silhouette": size = 256
		"closeup": size = 512
		"background": size = 256
		"atmosphere": size = 256
		"pixelate": size = 64
		"cursor": size = 32
		"tile": size = 256

	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.15, 0.3, 0.8))
	return ImageTexture.create_from_image(img)


# ============================================================
# Image Display Methods
# ============================================================

func _show_portrait(img_id: String, texture: Texture2D) -> void:
	portrait_panel.texture = texture
	portrait_panel.visible = true
	var timer := get_tree().create_timer(10.0)
	timer.timeout.connect(func(): portrait_panel.visible = false)


func _show_dialogue_frame(texture: Texture2D) -> void:
	portrait_panel.texture = texture
	portrait_panel.visible = true
	# Dialogue frames stay longer — 15 seconds
	var timer := get_tree().create_timer(15.0)
	timer.timeout.connect(func(): portrait_panel.visible = false)


func _show_room_background(texture: Texture2D) -> void:
	room_bg_texture.texture = texture
	room_bg_texture.visible = true


func _show_closeup(texture: Texture2D) -> void:
	var closeup_img = closeup_overlay.get_node("CloseupVBox/CloseupImage")
	closeup_img.texture = texture
	closeup_overlay.visible = true


func _update_inventory_bar() -> void:
	# Clear existing inventory icons
	for child in inventory_bar.get_children():
		child.queue_free()

	if game_state.inventory.is_empty():
		var empty_label := Label.new()
		empty_label.text = "  (no items)"
		empty_label.add_theme_font_size_override("font_size", 12)
		empty_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.4))
		inventory_bar.add_child(empty_label)
		return

	for item in game_state.inventory:
		var slot := TextureRect.new()
		slot.name = "InvSlot_%s" % item
		slot.custom_minimum_size = Vector2(32, 32)
		slot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		slot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		slot.tooltip_text = item

		# Try to load cached icon texture
		if image_client and image_client._cache:
			var tex: Texture2D = image_client._cache.get_cached_texture(item, "icon")
			if tex:
				slot.texture = tex
			else:
				slot.texture = load(_ui_icons.ICON_ADD) if ResourceLoader.exists(_ui_icons.ICON_ADD) else null

		slot.gui_input.connect(func(event):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				input_field.text = "use " + item + " "
				input_field.grab_focus()
		)
		inventory_bar.add_child(slot)

		# Item name label below icon
		var name_label := Label.new()
		name_label.text = item
		name_label.add_theme_font_size_override("font_size", 10)
		name_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.5))
		var label_vbox := VBoxContainer.new()
		label_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		# Swap: remove slot from inventory_bar, reparent into vbox
		inventory_bar.remove_child(slot)
		label_vbox.add_child(slot)
		label_vbox.add_child(name_label)
		inventory_bar.add_child(label_vbox)


# ============================================================
# LLM Status/Error Handlers
# ============================================================

func _on_llm_failed(error: String) -> void:
	narration_box.append_text("\n[color=red]Error: %s[/color]\n" % error)
	input_field.editable = true
	send_button.disabled = false


func _on_llm_status(status: String) -> void:
	status_label.text = status
	if status != "" and status != "Error":
		input_field.editable = false
		send_button.disabled = true


# ============================================================
# State Change Handlers
# ============================================================

func _on_room_changed(room_id: String) -> void:
	_show_room(room_id)


func _on_inventory_changed(item: String, added: bool) -> void:
	_update_inventory_display()
	_update_inventory_bar()
	if added:
		narration_box.append_text("[color=green]  Acquired: %s[/color]\n" % item)
	else:
		narration_box.append_text("[color=yellow]  Lost: %s[/color]\n" % item)


func _update_inventory_display() -> void:
	if game_state.inventory.is_empty():
		inventory_label.text = "Inventory: (empty)"
	else:
		inventory_label.text = "Inventory: " + ", ".join(game_state.inventory)
