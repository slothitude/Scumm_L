# SCUMM-L

A point-and-click adventure engine powered by LLMs, built in Godot 4.6. The AI acts as your Game Master — narrating the world, controlling NPCs, and responding to every action with dynamic, immersive prose. 3D rooms rendered with Kenney assets, with a pipeline for AI-generated visuals via ComfyUI + Hunyuan3D.

## What It Does

- **LLM Game Master** — Every click and typed action goes to an LLM (Z.ai GLM-5.1, with LiteLLM/Ollama fallback). The LLM returns structured JSON: narration text + state changes (inventory, flags, room transitions, NPC mood).
- **3D Rooms** — Kenney asset packs provide GLB models for taverns, villages, characters, and props. Loaded at runtime via Godot's `GLTFDocument`. Click detection via raycasting.
- **Dynamic State** — Godot is the authority. The LLM proposes state changes; Godot validates before applying. Room transitions, inventory, puzzle flags, NPC disposition — all tracked server-side.
- **AI Art Pipeline** (planned) — ComfyUI generates 2D sprites/backgrounds, Hunyuan3D 2.1 converts to 3D GLB. Cached to disk after first generation.

## Architecture

```
Player Click/Type → InputRouter → GameState builds context
                                     ↓
                              LLMClient (3-tier fallback)
                              Z.ai → LiteLLM → Ollama
                                     ↓
                              ResponseParser (JSON validate/repair)
                                     ↓
                              GameState applies validated mutations
                                     ↓
                              RoomRenderer (3D SubViewport + GLB models)
```

## Project Structure

```
scumm_l/
├── project.godot              # Godot config (GameState + GameConsts autoloads)
├── main.tscn                  # Root scene
├── core/
│   ├── game_manager.gd        # Orchestrator: UI, signals, input → LLM flow
│   ├── game_state.gd          # Authoritative state + signal-driven setters
│   ├── llm_client.gd          # HTTPRequest with 3-tier fallback cascade
│   ├── response_parser.gd     # JSON validation/repair for LLM output
│   ├── prompt_builder.gd      # Modular prompt assembly (system + world + history + action)
│   ├── room_renderer.gd       # SubViewport3D builder, GLB loader, click raycasting
│   └── constants.gd           # LLM endpoints, API keys, UI colors, 3D defaults
├── assets/
│   └── models/                # Kenney GLB models (per-kit subdirs + textures)
│       ├── mini-dungeon/      # Characters, barrels, chests, walls, weapons
│       ├── graveyard-kit/     # Skeleton, ghost, vampire, keeper, candles, crypts
│       ├── fantasy-town/      # Fountains, carts, banners, fences, hedges
│       └── pirate-kit/        # Barrels, chests, flags, cannons
├── SCUMM-L_Enhanced_Immersive.txt  # Original prompt-only version
└── .gitignore
```

## LLM Configuration

Three-tier fallback cascade — if the primary endpoint fails, it tries the next:

| Tier | Endpoint | Model | Config |
|------|----------|-------|--------|
| 1 | Z.ai API | GLM-5.1 | `constants.gd` → `ZAI_URL`, `ZAI_KEY` |
| 2 | LiteLLM proxy | qwen3 | `constants.gd` → `LITELLM_URL`, `LITELLM_KEY` |
| 3 | Ollama direct | qwen3 | `constants.gd` → `OLLAMA_URL` |

Set your API keys in `core/constants.gd`.

## Running

1. Open in **Godot 4.6+**
2. Press **F5**
3. Click on objects/NPCs in the 3D room, or type actions in the input field

Verbs recognized: `examine`, `look at`, `talk to`, `use`, `go`, `walk to`, `take`, `pick up`, or free text.

## Rooms

**The Rusty Anchor Tavern** — Bar counter, old chest, fireplace, door to village. An orc stranger broods in the corner. The human innkeeper polishes tankards.

**Village Square** — Crumbling fountain, market cart, stone bench. A skeleton merchant sells oddities. The tavern door leads back.

## Origin

SCUMM-L started as a pure-prompt project (`SCUMM-L_Enhanced_Immersive.txt`) — a 1377-line prompt that turned Claude/ChatGPT into a text adventure GM. This repo evolved it into a visual engine with real-time 3D rendering, state management, and an AI art pipeline.

## License

MIT
