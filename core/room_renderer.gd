## 3D room renderer using SubViewport + Kenney GLB models.
## Builds a mini 3D scene per room with Camera3D, lighting, loaded models,
## and click-detection via raycasting against invisible StaticBody3D hitboxes.

extends Node

signal hotspot_clicked(hotspot_id: String)

var _viewport_container: SubViewportContainer
var _sub_viewport: SubViewport
var _room_root: Node3D
var _camera: Camera3D
var _objects_node: Node3D
var _click_areas_node: Node3D


func build_room(room_id: String, room_data: Dictionary) -> SubViewportContainer:
	_clear_room()

	# --- SubViewportContainer (2D host, sized by game_manager) ---
	_viewport_container = SubViewportContainer.new()
	_viewport_container.name = "RoomViewport"
	_viewport_container.stretch = true

	# --- SubViewport (3D world) ---
	_sub_viewport = SubViewport.new()
	_sub_viewport.name = "RoomSubViewport"
	_sub_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sub_viewport.transparent_bg = true
	_viewport_container.add_child(_sub_viewport)

	# --- Room root ---
	_room_root = Node3D.new()
	_room_root.name = "RoomRoot"
	_sub_viewport.add_child(_room_root)

	# --- Camera (add to tree first, then set transform) ---
	_camera = Camera3D.new()
	_camera.name = "RoomCamera"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = GameConsts.CAMERA_SIZE
	_room_root.add_child(_camera)
	# Set transform directly — look_at needs node in scene tree
	_camera.position = GameConsts.CAMERA_OFFSET
	_camera.rotation = Vector3(deg_to_rad(-30), 0, 0)

	# --- Lighting ---
	var dir_light := DirectionalLight3D.new()
	dir_light.name = "DirLight"
	dir_light.light_energy = GameConsts.LIGHT_ENERGY
	dir_light.rotation = Vector3(-0.8, -0.4, 0)
	_room_root.add_child(dir_light)

	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = GameConsts.AMBIENT_COLOR
	env.ambient_light_energy = 0.6
	world_env.environment = env
	_room_root.add_child(world_env)

	# --- Floor ---
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "Floor"
	var floor_quad := PlaneMesh.new()
	floor_quad.size = Vector2(20, 20)
	floor_mesh.mesh = floor_quad
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = GameConsts.FLOOR_COLOR
	floor_mat.roughness = 0.9
	floor_mesh.material_override = floor_mat
	floor_mesh.position = Vector3(0, -0.01, 0)
	_room_root.add_child(floor_mesh)

	# --- Containers ---
	_objects_node = Node3D.new()
	_objects_node.name = "Objects"
	_room_root.add_child(_objects_node)

	_click_areas_node = Node3D.new()
	_click_areas_node.name = "ClickAreas"
	_room_root.add_child(_click_areas_node)

	# --- Load hotspots ---
	var hotspots: Dictionary = room_data.get("hotspots", {})
	for hotspot_id in hotspots:
		var h: Dictionary = hotspots[hotspot_id]
		_build_hotspot(hotspot_id, h)

	# --- Handle click input on the container (not SubViewport.gui_input) ---
	_viewport_container.gui_input.connect(_on_viewport_input)

	return _viewport_container


func clear_room() -> void:
	_clear_room()


func _clear_room() -> void:
	if _viewport_container != null and _viewport_container.is_inside_tree():
		_viewport_container.queue_free()
	_viewport_container = null
	_sub_viewport = null
	_room_root = null
	_camera = null
	_objects_node = null
	_click_areas_node = null


func _build_hotspot(hotspot_id: String, data: Dictionary) -> void:
	# Load 3D model if specified
	var model_path: String = data.get("model", "")
	if model_path != "":
		var model: Node3D = _load_glb(model_path)
		if model != null:
			model.position = data.get("position", Vector3.ZERO)
			model.rotation = data.get("rotation", Vector3.ZERO)
			model.scale = data.get("scale", Vector3.ONE)
			model.name = "Obj_%s" % hotspot_id
			_objects_node.add_child(model)

	# Create invisible click area (always, even for models)
	var click_size: Vector3 = data.get("click_size", Vector3(1, 1.5, 1))
	var click_pos: Vector3 = data.get("position", Vector3.ZERO)
	# Offset click area center up by half height
	click_pos.y += click_size.y * 0.5

	var body := StaticBody3D.new()
	body.name = "Click_%s" % hotspot_id
	body.collision_layer = GameConsts.CLICK_LAYER
	body.collision_mask = GameConsts.CLICK_LAYER
	body.set_meta("hotspot_id", hotspot_id)
	body.position = click_pos

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = click_size
	shape.shape = box
	body.add_child(shape)

	_click_areas_node.add_child(body)

	# Add floating label
	var label_pos: Vector3 = data.get("position", Vector3.ZERO)
	label_pos.y += click_size.y + 0.3
	var label := Label3D.new()
	label.name = "Label_%s" % hotspot_id
	label.text = data.get("label", hotspot_id)
	label.font_size = 16
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = label_pos
	label.modulate = Color(1, 1, 0.8, 0.7)
	_click_areas_node.add_child(label)


func _load_glb(path: String) -> Node3D:
	# Use FileAccess to check existence — ResourceLoader.exists may not find unimported GLBs
	if not FileAccess.file_exists(path):
		print("[RoomRenderer] GLB file not found: %s" % path)
		return null

	var gltf_doc := GLTFDocument.new()
	var gltf_state := GLTFState.new()
	var err: int = gltf_doc.append_from_file(path, gltf_state)
	if err != OK:
		print("[RoomRenderer] Failed to load GLB %s: %s" % [path, error_string(err)])
		return null

	var scene: Node = gltf_doc.generate_scene(gltf_state)
	if scene == null:
		print("[RoomRenderer] generate_scene returned null for %s" % path)
		return null

	var node_3d: Node3D = null
	if scene is Node3D:
		node_3d = scene
	else:
		# Wrap in Node3D if needed
		node_3d = Node3D.new()
		node_3d.add_child(scene)

	return node_3d


func _on_viewport_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return

	if _camera == null or _room_root == null or not _room_root.is_inside_tree():
		return

	var space_state: PhysicsDirectSpaceState3D = _room_root.get_world_3d().direct_space_state
	var from: Vector3 = _camera.project_ray_origin(mb.position)
	var to: Vector3 = from + _camera.project_ray_normal(mb.position) * 50.0

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = GameConsts.CLICK_LAYER

	var result: Dictionary = space_state.intersect_ray(query)
	if result.size() > 0:
		var collider: Node = result.collider
		if collider.has_meta("hotspot_id"):
			hotspot_clicked.emit(str(collider.get_meta("hotspot_id")))
