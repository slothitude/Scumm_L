## Modular prompt assembly for LLM requests.
## Builds: system prompt + world context + action history + current action.

extends Node

const SYSTEM_PROMPT := """You are the AI Game Master (AGM) for a point-and-click adventure game. You narrate the world, control NPCs, and respond to player actions with vivid, immersive prose.

RULES:
- Always respond in valid JSON format (see below)
- Keep narration vivid but concise (2-4 sentences for examine, 3-6 for dialogue)
- Reward player creativity and lateral thinking
- Track what the player has learned or discovered
- Maintain internal consistency with previously established facts
- Never break the fourth wall or mention being an AI

RESPONSE FORMAT — always return a single JSON object:
{
  "narration": "Your vivid description of what happens",
  "state_changes": {
    "flags": {"flag_name": true},
    "inventory_add": ["item_name"],
    "inventory_remove": ["item_name"],
    "new_room": null,
    "npc_updates": {"npc_name": {"mood": "friendly"}}
  }
}

- Only include state_changes that are relevant to this action.
- If nothing changes, use empty objects/arrays and null for new_room.
- flags track discoveries, puzzle progress, and world state.
- inventory_add: give items when the player finds or receives them.
- inventory_remove: take items when the player uses or loses them.
- new_room: set to a room ID only when the player actually moves to a new location.
- npc_updates: change NPC properties like mood, disposition, or knowledge."""


func build_messages(action: String, target: String, game_state: Node) -> Array:
	var messages: Array = []
	messages.append({"role": "system", "content": SYSTEM_PROMPT})
	messages.append({"role": "system", "content": _build_world_context(game_state)})

	# Recent action history for context continuity
	var history: Array = _get_recent_history(game_state)
	for msg in history:
		messages.append(msg)

	# Current player action
	messages.append({"role": "user", "content": _build_action_message(action, target, game_state)})

	return messages


func _build_world_context(game_state: Node) -> String:
	var room: Dictionary = game_state.get_room_data()
	var context := "=== CURRENT WORLD STATE ===\n"
	context += "Room: %s\n" % room.get("name", "Unknown")
	context += "Room Description: %s\n" % room.get("description", "")
	context += "Player Inventory: %s\n" % (str(game_state.inventory) if game_state.inventory.size() > 0 else "(empty)")

	# Active flags (abbreviated — only true ones)
	var true_flags: Array = []
	for key in game_state.flags:
		if game_state.flags[key]:
			true_flags.append(key)
	if true_flags.size() > 0:
		context += "Active Flags: %s\n" % str(true_flags)

	# Visible hotspots
	context += "Visible Objects: "
	var hotspots: Dictionary = room.get("hotspots", {})
	var labels: Array = []
	for key in hotspots:
		labels.append(hotspots[key].get("label", key))
	context += ", ".join(labels) + "\n"

	# NPC states
	if game_state.npc_states.size() > 0:
		context += "NPC States: %s\n" % str(game_state.npc_states)

	# Available exits
	var exits: Dictionary = room.get("exits", {})
	if exits.size() > 0:
		context += "Exits: %s\n" % str(exits)

	return context


func _get_recent_history(game_state: Node) -> Array:
	var all_history: Array = game_state.action_history
	var max_msgs := GameConsts.MAX_HISTORY_MESSAGES
	var start := maxi(0, all_history.size() - max_msgs)
	var recent: Array = []
	for i in range(start, all_history.size()):
		recent.append(all_history[i])
	return recent


func _build_action_message(action: String, target: String, game_state: Node) -> String:
	# Check if target matches a known hotspot
	var hotspot: Dictionary = game_state.get_hotspot_data(target)
	var target_name: String = hotspot.get("label", target) if not hotspot.is_empty() else target
	var target_desc: String = hotspot.get("description", "") if not hotspot.is_empty() else ""

	match action:
		"examine":
			if target_desc != "":
				return "Player action: Examine \"%s\".\nObject description: %s" % [target_name, target_desc]
			return "Player action: Examine \"%s\"." % target_name
		"use":
			return "Player action: Use \"%s\".\nObject description: %s" % [target_name, target_desc]
		"talk":
			return "Player action: Talk to \"%s\".\nCharacter description: %s" % [target_name, target_desc]
		"go":
			var exits: Dictionary = game_state.get_room_data().get("exits", {})
			# Check if target matches an exit
			for exit_id in exits:
				var exit_data: Dictionary = game_state.get_hotspot_data(exit_id)
				var exit_label: String = exit_data.get("label", exit_id) if not exit_data.is_empty() else exit_id
				if target.to_lower() == exit_label.to_lower() or target.to_lower() == exit_id:
					return "Player action: Go through \"%s\" to \"%s\"." % [exit_label, exits[exit_id]]
			return "Player action: Go to \"%s\"." % target_name
		"custom":
			return "Player says/does: %s" % target
		_:
			return "Player action: %s on \"%s\"." % [action, target_name]
