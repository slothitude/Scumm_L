"""SCUMM-L Image Service — proxies Bonsai FLUX generation with post-processing.

Runs on Lappy port 8010. Bonsai MCP stays on port 8000.
Endpoints:
  POST /generate/{type}  — generate image with type-specific processing
  GET  /health           — health check

Accepted types: background, atmosphere, portrait, dialogue_frame, icon, alpha,
                closeup, pixelate, cursor, silhouette, tile
"""

import io, base64, json, logging, time
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from PIL import Image, ImageFilter, ImageEnhance
import httpx

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
log = logging.getLogger("image_service")

app = FastAPI(title="SCUMM-L Image Service")

BONSAI_URL = "http://100.84.161.63:8000"
TIMEOUT = 300.0

# Type-specific Bonsai defaults
TYPE_CONFIG = {
    "background":  {"width": 1248, "height": 832,  "target_size": 1280},
    "atmosphere":  {"width": 1248, "height": 832,  "target_size": 1280},
    "portrait":    {"width": 512,  "height": 512,  "target_size": 256},
    "dialogue_frame": {"width": 512, "height": 512, "target_size": 280},
    "icon":        {"width": 512,  "height": 512,  "target_size": 64},
    "alpha":       {"width": 512,  "height": 512,  "target_size": 64},
    "closeup":     {"width": 1024, "height": 1024, "target_size": 512},
    "pixelate":    {"width": 512,  "height": 512,  "target_size": 64},
    "cursor":      {"width": 512,  "height": 512,  "target_size": 32},
    "silhouette":  {"width": 512,  "height": 512,  "target_size": 256},
    "tile":        {"width": 512,  "height": 512,  "target_size": 256},
}

# Style prefixes per type — prepended to the user prompt before sending to Bonsai
STYLE_PREFIX = {
    "background":    "Fantasy adventure game background, detailed digital painting, atmospheric lighting, ",
    "atmosphere":    "Moody atmospheric scene, cinematic lighting, digital painting, ",
    "portrait":      "Fantasy character portrait, detailed face, dramatic lighting, dark background, ",
    "dialogue_frame": "Fantasy character portrait for dialogue box, upper body, detailed face, ",
    "icon":          "Game item icon on white background, flat shading, clean edges, centered, ",
    "alpha":         "Game item on transparent white background, flat shading, clean edges, ",
    "closeup":       "Detailed close-up view, fantasy adventure game, dramatic lighting, ",
    "pixelate":      "Retro pixel art style game item, 16-bit, clean edges, centered, ",
    "cursor":         "Small game item cursor icon on white background, simple, centered, ",
    "silhouette":    "Dark mysterious shadowy figure silhouette, dark fantasy, minimal detail, ",
    "tile":          "Seamless texture tile, tiling pattern, digital painting, ",
}


class GenerateRequest(BaseModel):
    prompt: str = ""
    size: int = 64
    id: str = "test"


# ---- Pipeline functions ----

def make_transparent(img: Image.Image, threshold: int = 200) -> Image.Image:
    """Make near-white pixels transparent."""
    img = img.convert("RGBA")
    data = list(img.getdata())
    new_data = []
    for pixel in data:
        r, g, b = pixel[0], pixel[1], pixel[2]
        if r > threshold and g > threshold and b > threshold:
            new_data.append((r, g, b, 0))
        else:
            new_data.append((r, g, b, pixel[3]))
    img.putdata(new_data)
    return img


def center_crop(img: Image.Image, tw: int, th: int) -> Image.Image:
    """Center-crop to target dimensions."""
    w, h = img.size
    left = max(0, (w - tw) // 2)
    top = max(0, (h - th) // 2)
    right = min(w, left + tw)
    bottom = min(h, top + th)
    return img.crop((left, top, right, bottom)).resize((tw, th), Image.LANCZOS)


def pixelate_effect(img: Image.Image, pixel_size: int = 8) -> Image.Image:
    """Downscale then upscale for pixel art."""
    sw = max(1, img.width // pixel_size)
    sh = max(1, img.height // pixel_size)
    return img.resize((sw, sh), Image.NEAREST).resize((img.width, img.height), Image.NEAREST)


def process_background(raw: Image.Image, target_w: int = 1280) -> Image.Image:
    raw = ImageEnhance.Color(raw).enhance(0.85)
    raw = ImageEnhance.Contrast(raw).enhance(1.15)
    w, h = raw.size
    new_h = int(h * target_w / w)
    return raw.resize((target_w, new_h), Image.LANCZOS)


def process_portrait(raw: Image.Image, size: int = 256) -> Image.Image:
    side = min(raw.width, raw.height)
    cropped = center_crop(raw, side, side)
    return cropped.resize((size, size), Image.LANCZOS)


def process_icon(raw: Image.Image, size: int = 64) -> Image.Image:
    raw = make_transparent(raw)
    side = min(raw.width, raw.height)
    cropped = center_crop(raw, side, side)
    return cropped.resize((size, size), Image.LANCZOS)


def process_silhouette(raw: Image.Image, size: int = 256) -> Image.Image:
    gray = raw.convert("L")
    mask = gray.point(lambda x: 255 if x < 100 else int(255 * (1 - x / 255)))
    result = Image.new("RGBA", raw.size, (20, 15, 30, 220))
    result.putalpha(mask)
    side = min(result.width, result.height)
    cropped = center_crop(result, side, side)
    return cropped.resize((size, size), Image.LANCZOS)


def process_dialogue_frame(raw: Image.Image, size: int = 280) -> Image.Image:
    """Portrait with decorative frame."""
    portrait = process_portrait(raw, size)
    border = 8
    framed = Image.new("RGBA",
                       (portrait.width + border * 2, portrait.height + border * 2 + 20),
                       (40, 30, 55, 230))
    framed.paste(portrait, (border, border))
    return framed


def process_pixelate(raw: Image.Image, size: int = 64, pixel_size: int = 8) -> Image.Image:
    side = min(raw.width, raw.height)
    cropped = center_crop(raw, side, side)
    cropped = cropped.resize((size, size), Image.LANCZOS)
    return pixelate_effect(cropped, pixel_size)


def process_cursor(raw: Image.Image, size: int = 32) -> Image.Image:
    raw = make_transparent(raw)
    side = min(raw.width, raw.height)
    cropped = center_crop(raw, side, side)
    return cropped.resize((size, size), Image.LANCZOS)


def process_tile(raw: Image.Image, size: int = 256) -> Image.Image:
    return raw.resize((size, size), Image.LANCZOS)


def process_closeup(raw: Image.Image, size: int = 512) -> Image.Image:
    return raw.resize((size, size), Image.LANCZOS)


PROCESSORS = {
    "background":    lambda img, cfg: process_background(img, cfg["target_size"]),
    "atmosphere":    lambda img, cfg: process_background(img, cfg["target_size"]),
    "portrait":      lambda img, cfg: process_portrait(img, cfg["target_size"]),
    "dialogue_frame": lambda img, cfg: process_dialogue_frame(img, cfg["target_size"]),
    "icon":          lambda img, cfg: process_icon(img, cfg["target_size"]),
    "alpha":         lambda img, cfg: process_icon(img, cfg["target_size"]),
    "closeup":       lambda img, cfg: process_closeup(img, cfg["target_size"]),
    "pixelate":      lambda img, cfg: process_pixelate(img, cfg["target_size"]),
    "cursor":        lambda img, cfg: process_cursor(img, cfg["target_size"]),
    "silhouette":    lambda img, cfg: process_silhouette(img, cfg["target_size"]),
    "tile":          lambda img, cfg: process_tile(img, cfg["target_size"]),
}


def img_to_b64(img: Image.Image) -> str:
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return base64.b64encode(buf.getvalue()).decode("utf-8")


# ---- Bonsai proxy ----

async def call_bonsai(prompt: str, width: int, height: int) -> Image.Image:
    """Call Bonsai service and return PIL Image. Handles both raw PNG and JSON responses."""
    payload = {"prompt": prompt, "width": width, "height": height}

    async with httpx.AsyncClient(timeout=TIMEOUT) as client:
        resp = await client.post(f"{BONSAI_URL}/generate", json=payload)
        resp.raise_for_status()
        content_type = resp.headers.get("content-type", "")

    if "image" in content_type or resp.content[:4] == b"\x89PNG":
        # Raw PNG bytes
        img = Image.open(io.BytesIO(resp.content))
    else:
        # JSON response with path or base64
        data = resp.json()
        img_path = data.get("path", "")
        if img_path:
            img = Image.open(img_path)
        elif "image_b64" in data:
            raw = base64.b64decode(data["image_b64"])
            img = Image.open(io.BytesIO(raw))
        else:
            raise HTTPException(500, f"Cannot parse Bonsai response: {list(data.keys())}")

    if img.mode == "RGB":
        img = img.convert("RGBA")
    return img


# ---- Routes ----

@app.get("/health")
async def health():
    return {"status": "ok", "service": "scumm-l-image-service", "bonsai": BONSAI_URL}


@app.post("/generate/{img_type}")
async def generate(img_type: str, req: Request):
    if img_type not in TYPE_CONFIG:
        raise HTTPException(400, f"Unknown image type: {img_type}. Valid: {list(TYPE_CONFIG.keys())}")

    body = await req.json()
    prompt = body.get("prompt", "")
    size = body.get("size", 64)
    img_id = body.get("id", "unknown")

    if not prompt:
        raise HTTPException(400, "prompt is required")

    cfg = TYPE_CONFIG[img_type]
    style = STYLE_PREFIX.get(img_type, "")
    full_prompt = style + prompt

    log.info(f"[{img_type}] id={img_id} prompt=\"{prompt[:50]}\" -> Bonsai {cfg['width']}x{cfg['height']}")

    t0 = time.time()
    try:
        raw_img = await call_bonsai(full_prompt, cfg["width"], cfg["height"])
    except httpx.HTTPStatusError as e:
        log.error(f"Bonsai HTTP error: {e.response.status_code}")
        raise HTTPException(502, f"Bonsai error: {e.response.status_code}")
    except Exception as e:
        log.error(f"Bonsai call failed: {e}")
        raise HTTPException(502, f"Bonsai call failed: {e}")

    # Apply type-specific processing
    processor = PROCESSORS.get(img_type)
    if processor:
        result_img = processor(raw_img, cfg)
    else:
        result_img = raw_img

    elapsed = time.time() - t0
    log.info(f"[{img_type}] id={img_id} done in {elapsed:.1f}s -> {result_img.size}")

    return {"image_b64": img_to_b64(result_img)}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8010, log_level="info")
