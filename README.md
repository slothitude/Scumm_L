# SCUMM-L

A point-and-click adventure engine powered by LLMs, built in Godot 4.6. The AI acts as your Game Master — narrating the world, controlling NPCs, and responding to every action with dynamic, immersive prose. 3D rooms rendered with Kenney assets, AI-generated visuals via Bonsai FLUX + image_service.py pipeline.

## What It Does

- **LLM Game Master** — Every click and typed action goes to an LLM (Z.ai GLM-5.1, with LiteLLM/Ollama fallback). The LLM returns structured JSON: narration text + state changes (inventory, flags, room transitions, NPC mood).
- **3D Rooms** — Kenney asset packs provide GLB models for taverns, villages, characters, and props. Loaded at runtime via Godot's `GLTFDocument`. Click detection via raycasting.
- **Dynamic State** — Godot is the authority. The LLM proposes state changes; Godot validates before applying. Room transitions, inventory, puzzle flags, NPC disposition — all tracked server-side.
- **AI Art Pipeline** — Bonsai FLUX generates images via `image_service.py` (FastAPI on Lappy:8010). 11 image types with type-specific post-processing (transparency, pixelation, silhouettes, dialogue frames). Disk-cached after first generation.

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
                              ImageClient fires image_requests to image_service
                                     ↓
                              image_service.py (FastAPI, Lappy:8010)
                              Bonsai FLUX generation → type-specific post-processing
                              → base64 PNG → Godot disk cache → display
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
│   ├── image_client.gd        # Async HTTP client → image_service, disk cache
│   ├── image_cache.gd         # Disk cache: user://image_cache/{type}/{id}.png
│   └── constants.gd           # LLM endpoints, API keys, image service URL
├── services/
│   └── image_service.py       # FastAPI service — Bonsai FLUX proxy + post-processing
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
| 1 | NVIDIA NIM (cloud) | minimax-m2.7 | `constants.gd` → `NIM_URL`, `NIM_KEY` |
| 2 | LiteLLM proxy (Lappy:4000) | qwen3 | `constants.gd` → `LITELLM_URL`, `LITELLM_KEY` |
| 3 | Ollama direct (Lappy:11434) | qwen3 | `constants.gd` → `OLLAMA_URL` |

Set your API keys in `core/constants.gd`.

## Image Generation Pipeline

The LLM returns `image_requests` in its JSON response. Godot dispatches each to `image_service.py` on Lappy (port 8010), which proxies to Bonsai FLUX (port 8000) and applies type-specific post-processing.

**11 image types:**

| Type | Size | Processing |
|------|------|------------|
| `background` | 1280 | Color grade (warm), contrast boost, resize |
| `atmosphere` | 1280 | Same as background |
| `portrait` | 256 | Center crop to square, resize |
| `dialogue_frame` | 280 | Portrait + decorative border |
| `icon` | 64 | White→transparent, center crop, resize |
| `alpha` | 64 | Same as icon (transparent variant) |
| `closeup` | 512 | Resize |
| `pixelate` | 64 | Pixel art effect (8x downscale/upscale) |
| `cursor` | 32 | Transparent + tiny resize |
| `silhouette` | 256 | Grayscale threshold → dark shadow |
| `tile` | 256 | Resize |

Flow: `Bonsai FLUX (raw PNG) → Pillow post-processing → base64 → Godot → disk cache → display`

## Running

1. Open in **Godot 4.6+**
2. Press **F5**
3. Click on objects/NPCs in the 3D room, or type actions in the input field

Verbs recognized: `examine`, `look at`, `talk to`, `use`, `go`, `walk to`, `take`, `pick up`, or free text.

## Rooms

**The Rusty Anchor Tavern** — Bar counter, old chest, fireplace, door to village. An orc stranger broods in the corner. The human innkeeper polishes tankards.

**Village Square** — Crumbling fountain, market cart, stone bench. A skeleton merchant sells oddities. The tavern door leads back.

## Origin

SCUMM-L started as a pure-prompt project (`SCUMM-L_Enhanced_Immersive.txt`) — a 1377-line prompt that turned Claude/ChatGPT into a text adventure GM. This repo evolved it into a visual engine with real-time 3D rendering, state management, and a working AI art pipeline powered by Bonsai FLUX.

## License

MIT
