## Authoritative game state manager.
## All mutable state lives here. Property setters emit signals.
## LLM proposes changes as JSON; GameState validates before applying.

extends Node

signal room_changed(room_id: String)
signal inventory_changed(item: String, added: bool)
signal flag_set(flag_name: String, value: Variant)
signal narration_received(text: String)
signal npc_state_changed(npc_name: String, property: String, value: Variant)

var current_room: String = "tavern":
	set(v):
		if v != current_room:
			current_room = v
			room_changed.emit(v)

var inventory: Array[String] = []
var flags: Dictionary = {}
var npc_states: Dictionary = {}
var action_history: Array[Dictionary] = []
var rooms: Dictionary = {}


func _ready() -> void:
	_init_test_game()


func _init_test_game() -> void:
	rooms = {
		"tavern": {
			"name": "The Rusty Anchor Tavern",
			"description": "A dimly lit tavern. The smell of stale ale and wood smoke fills the air. Shadows dance across the stone walls.",
			"hotspots": {
				"bar_counter": {
					"label": "Bar Counter",
					"description": "A long oak bar, stained with years of spilled drinks. Barrels line the wall behind it.",
					"model": GameConsts.ASSETS_MODELS + "mini-dungeon/barrel.glb",
					"position": Vector3(-3, 0, -2),
					"rotation": Vector3(0, deg_to_rad(90), 0),
					"scale": Vector3(2, 1, 1),
					"click_size": Vector3(3, 1.5, 1.5)
				},
				"chest": {
					"label": "Old Chest",
					"description": "A dusty wooden chest tucked under the bar. Something glints inside.",
					"model": GameConsts.ASSETS_MODELS + "mini-dungeon/chest.glb",
					"position": Vector3(-1.5, 0, -1),
					"rotation": Vector3.ZERO,
					"scale": Vector3.ONE,
					"click_size": Vector3(1, 0.8, 1)
				},
				"fireplace": {
					"label": "Fireplace",
					"description": "A crackling fire casts dancing shadows on the stone wall. Candles flicker on the mantle.",
					"model": GameConsts.ASSETS_MODELS + "graveyard-kit/candle-multiple.glb",
					"position": Vector3(3, 0.5, -3),
					"rotation": Vector3.ZERO,
					"scale": Vector3(1.5, 1.5, 1.5),
					"click_size": Vector3(1.5, 2, 1)
				},
				"door": {
					"label": "Door to Village",
					"description": "A heavy wooden door leading outside to the village square.",
					"model": GameConsts.ASSETS_MODELS + "mini-dungeon/gate.glb",
					"position": Vector3(5, 0, 0),
					"rotation": Vector3.ZERO,
					"scale": Vector3.ONE,
					"click_size": Vector3(1, 2.5, 1.5)
				},
				"stranger": {
					"label": "Mysterious Stranger",
					"description": "A cloaked figure sitting alone in the corner, nursing a drink. An orc, unusually quiet.",
					"model": GameConsts.ASSETS_MODELS + "mini-dungeon/character-orc.glb",
					"position": Vector3(2, 0, 1),
					"rotation": Vector3(0, deg_to_rad(-30), 0),
					"scale": Vector3.ONE,
					"click_size": Vector3(1, 2, 1)
				},
				"innkeeper": {
					"label": "Innkeeper",
					"description": "The burly innkeeper polishes a tankard behind the bar. He seems to know everyone who comes through.",
					"model": GameConsts.ASSETS_MODELS + "mini-dungeon/character-human.glb",
					"position": Vector3(-3, 0, 0),
					"rotation": Vector3(0, deg_to_rad(60), 0),
					"scale": Vector3.ONE,
					"click_size": Vector3(1, 2, 1)
				}
			},
			"exits": {
				"door": "village"
			},
			"npcs": ["stranger", "innkeeper"]
		},
		"village": {
			"name": "Village Square",
			"description": "A small village square with a crumbling fountain at its center. The tavern looms behind you. A hedge marks the edge of town.",
			"hotspots": {
				"fountain": {
					"label": "Fountain",
					"description": "An old stone fountain. Water trickles weakly from a weathered cherub.",
					"model": GameConsts.ASSETS_MODELS + "fantasy-town/fountain-round.glb",
					"position": Vector3(0, 0, -2),
					"rotation": Vector3.ZERO,
					"scale": Vector3.ONE,
					"click_size": Vector3(2, 1.5, 2)
				},
				"tavern_door": {
					"label": "Back to Tavern",
					"description": "The heavy door of The Rusty Anchor.",
					"model": GameConsts.ASSETS_MODELS + "mini-dungeon/gate.glb",
					"position": Vector3(-5, 0, 0),
					"rotation": Vector3.ZERO,
					"scale": Vector3.ONE,
					"click_size": Vector3(1, 2.5, 1.5)
				},
				"market_stall": {
					"label": "Market Stall",
					"description": "A rickety stall with a few wares on display. A skeleton runs the stand — surprisingly articulate.",
					"model": GameConsts.ASSETS_MODELS + "fantasy-town/cart.glb",
					"position": Vector3(3.5, 0, -1),
					"rotation": Vector3(0, deg_to_rad(-45), 0),
					"scale": Vector3.ONE,
					"click_size": Vector3(2.5, 1.5, 2)
				},
				"merchant": {
					"label": "Skeleton Merchant",
					"description": "A well-dressed skeleton selling oddities from a cart. His eye sockets gleam with intelligence.",
					"model": GameConsts.ASSETS_MODELS + "graveyard-kit/character-skeleton.glb",
					"position": Vector3(4, 0, 0),
					"rotation": Vector3(0, deg_to_rad(-90), 0),
					"scale": Vector3.ONE,
					"click_size": Vector3(1, 2, 1)
				},
				"bench": {
					"label": "Bench",
					"description": "A weathered stone bench near the fountain. Someone carved initials into it long ago.",
					"model": GameConsts.ASSETS_MODELS + "graveyard-kit/bench.glb",
					"position": Vector3(-2, 0, 0),
					"rotation": Vector3.ZERO,
					"scale": Vector3.ONE,
					"click_size": Vector3(2, 1, 1)
				},
				"banner": {
					"label": "Tavern Sign",
					"description": "A faded red banner hanging above the tavern door. The symbol of a rusted anchor is barely visible.",
					"model": GameConsts.ASSETS_MODELS + "fantasy-town/banner-red.glb",
					"position": Vector3(-5, 2.5, -0.5),
					"rotation": Vector3.ZERO,
					"scale": Vector3.ONE,
					"click_size": Vector3(1.5, 1.5, 0.5)
				}
			},
			"exits": {
				"tavern_door": "tavern"
			},
			"npcs": ["merchant"]
		}
	}


func add_to_inventory(item: String) -> void:
	if item not in inventory:
		inventory.append(item)
		inventory_changed.emit(item, true)


func remove_from_inventory(item: String) -> void:
	var idx := inventory.find(item)
	if idx >= 0:
		inventory.remove_at(idx)
		inventory_changed.emit(item, false)


func set_flag(flag_name: String, value: Variant = true) -> void:
	flags[flag_name] = value
	flag_set.emit(flag_name, value)


func has_flag(flag_name: String) -> bool:
	return flags.get(flag_name, false)


func add_to_history(role: String, content: String) -> void:
	action_history.append({"role": role, "content": content})
	# Keep history bounded
	while action_history.size() > 30:
		action_history.pop_front()


func get_room_data(room_id: String = "") -> Dictionary:
	var rid := room_id if room_id != "" else current_room
	return rooms.get(rid, {})


func get_hotspot_data(hotspot_id: String) -> Dictionary:
	var room := get_room_data()
	return room.get("hotspots", {}).get(hotspot_id, {})


func apply_llm_changes(changes: Dictionary) -> void:
	if changes.has("flags") and changes.flags is Dictionary:
		for key in changes.flags:
			set_flag(key, changes.flags[key])

	if changes.has("inventory_add") and changes.inventory_add is Array:
		for item in changes.inventory_add:
			if item is String:
				add_to_inventory(item)

	if changes.has("inventory_remove") and changes.inventory_remove is Array:
		for item in changes.inventory_remove:
			if item is String:
				remove_from_inventory(item)

	if changes.has("new_room") and changes.new_room != null:
		var new_room: String = str(changes.new_room)
		if new_room != "" and rooms.has(new_room):
			current_room = new_room

	if changes.has("npc_updates") and changes.npc_updates is Dictionary:
		for npc_name in changes.npc_updates:
			if changes.npc_updates[npc_name] is Dictionary:
				if not npc_states.has(npc_name):
					npc_states[npc_name] = {}
				for prop in changes.npc_updates[npc_name]:
					npc_states[npc_name][prop] = changes.npc_updates[npc_name][prop]
					npc_state_changed.emit(npc_name, prop, changes.npc_updates[npc_name][prop])


func get_serializable_state() -> Dictionary:
	return {
		"current_room": current_room,
		"inventory": inventory,
		"flags": flags,
		"npc_states": npc_states,
		"action_history": action_history,
	}
