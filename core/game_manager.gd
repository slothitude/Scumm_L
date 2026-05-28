## Main scene orchestrator for SCUMM-L.
## Builds UI programmatically, wires signals, handles input → LLM → state update flow.
## Uses RoomRenderer for 3D scene with Kenney GLB models.

extends Node

var game_state: Node
var llm_client: Node
var prompt_builder: Node
var response_parser: Node
var room_renderer: Node

# UI references
var root_control: Control
var room_title: Label
var room_area_host: Control  # Container that holds the SubViewportContainer
var narration_box: RichTextLabel
var input_field: LineEdit
var send_button: Button
var status_label: Label
var inventory_label: Label


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
	room_area_host.offset_bottom = -200
	# Dark background behind 3D viewport
	var room_bg := ColorRect.new()
	room_bg.name = "RoomBG"
	room_bg.color = Color(0.04, 0.03, 0.06)
	room_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	room_area_host.add_child(room_bg)
	root_control.add_child(room_area_host)

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
	narration_box.offset_top = -190
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
	narr_bg.offset_top = -190
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
		if child.name != "RoomBG":
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

	# Apply validated state changes
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

	# Re-enable input
	input_field.editable = true
	send_button.disabled = false
	input_field.grab_focus()


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
	if added:
		narration_box.append_text("[color=green]  Acquired: %s[/color]\n" % item)
	else:
		narration_box.append_text("[color=yellow]  Lost: %s[/color]\n" % item)


func _update_inventory_display() -> void:
	if game_state.inventory.is_empty():
		inventory_label.text = "Inventory: (empty)"
	else:
		inventory_label.text = "Inventory: " + ", ".join(game_state.inventory)
