## LLM endpoint configuration and game constants.
## Registered as autoload in project.godot — access globally via GameConsts.CONSTANT_NAME.

extends Node

# --- LLM Endpoints (3-tier fallback cascade) ---

# Tier 1: Z.ai primary
const ZAI_URL: String = "https://api.z.ai/api/coding/paas/v4/chat/completions"
const ZAI_MODEL: String = "glm-5.1"
const ZAI_KEY: String = "a63a2a7ee2d5431d929c776122e3b706.hzHjrJlnfPd7cYfj"

# Tier 2: LiteLLM proxy on Lappy
const LITELLM_URL: String = "http://192.168.0.33:4000/v1/chat/completions"
const LITELLM_MODEL: String = "qwen3"
const LITELLM_KEY: String = "sk-litellm-b15241627ba17201797f1446b25d82a9"

# Tier 3: Ollama direct on Lappy
const OLLAMA_URL: String = "http://192.168.0.33:11434/v1/chat/completions"
const OLLAMA_MODEL: String = "qwen3"
const OLLAMA_KEY: String = "ollama"

# --- LLM Settings ---
const LLM_TIMEOUT: float = 120.0
const MAX_HISTORY_MESSAGES: int = 10  # Recent messages sent to LLM
const LLM_TEMPERATURE: float = 0.8

# --- Image Generation ---
const IMAGE_URL: String = "http://192.168.0.33:4000/v1/images/generations"
const IMAGE_MODEL: String = "schnell"

# --- Asset Paths ---
const ASSETS_MODELS: String = "res://assets/models/"

# --- 3D Scene Defaults ---
const CAMERA_OFFSET: Vector3 = Vector3(0, 4, 7)
const CAMERA_SIZE: float = 6.0
const LIGHT_DIRECTION: Vector3 = Vector3(-0.5, -1, -0.3)
const LIGHT_ENERGY: float = 1.2
const AMBIENT_COLOR: Color = Color(0.3, 0.25, 0.35)
const CLICK_LAYER: int = 2  # Physics layer for hotspot click detection
const FLOOR_COLOR: Color = Color(0.15, 0.12, 0.1)

# --- UI Colors ---
const COLOR_BG: Color = Color(0.08, 0.06, 0.12)
const COLOR_TEXT: Color = Color(0.9, 0.85, 0.75)
const COLOR_ACCENT: Color = Color(1.0, 0.9, 0.7)
const COLOR_INPUT: Color = Color(0.12, 0.1, 0.18)
const COLOR_NARRATION_BG: Color = Color(0.05, 0.04, 0.08, 0.9)
const COLOR_HOTSPOT_BORDER: Color = Color(1, 1, 1, 0.3)
const COLOR_HOTSPOT_HOVER: Color = Color(1, 1, 0.5, 0.6)
