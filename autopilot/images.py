"""Free image generation with a locked style + character description."""
import io
import time
import urllib.parse
import requests
from PIL import Image
from . import config as C

def _style():
    """Reads story/style.md: CHARACTER, STYLE and FRIENDS lines."""
    out = {"CHARACTER": "", "STYLE": "", "FRIENDS": {}}
    for line in (C.STORY / "style.md").read_text().splitlines():
        line = line.strip()
        if line.startswith("CHARACTER:"):
            out["CHARACTER"] = line.split(":", 1)[1].strip()
        elif line.startswith("STYLE:"):
            out["STYLE"] = line.split(":", 1)[1].strip()
        elif "=" in line:
            k, v = line.split("=", 1)
            out["FRIENDS"][k.strip()] = v.strip()
    return out


def full_prompt(scene):
    """Scene FIRST (image models only read ~70 words), then who's who, then style. Kept short."""
    st = _style()
    text = scene.replace("YOU", "the round-headed hero")
    friends = [f"{name}: {desc}" for name, desc in st["FRIENDS"].items() if name in scene]
    parts = [text, f"Hero: {st['CHARACTER']}"] + friends + [st["STYLE"]]
    return ". ".join(p.rstrip(".") for p in parts if p) + "."


_last_call = 0.0


def _pollinations(prompt, seed, size):
    """gen.pollinations.ai with your key (free credits from enter.pollinations.ai).
    Without a key it falls back to the anonymous endpoint (1 image / 45s, low quality)."""
    global _last_call
    wait = (0 if C.POLLINATIONS_TOKEN else 46) - (time.time() - _last_call)
    if wait > 0:
        time.sleep(wait)
    params = {"width": size[0], "height": size[1], "seed": seed, "model": C.POLLINATIONS_MODEL, "nologo": "true"}
    ref = C.env("CHARACTER_REF_URL")  # optional: public URL of the character reference image
    if ref and size == (C.W, C.H):
        params["image"] = ref
    if C.POLLINATIONS_TOKEN:
        url = "https://gen.pollinations.ai/image/" + urllib.parse.quote(prompt[:1800])
        headers = {"Authorization": f"Bearer {C.POLLINATIONS_TOKEN}"}
    else:
        url = "https://image.pollinations.ai/prompt/" + urllib.parse.quote(prompt[:1800])
        headers = {}
    r = requests.get(url, params=params, headers=headers, timeout=240)
    _last_call = time.time()
    if r.status_code >= 400:
        raise RuntimeError(f"Pollinations {r.status_code}: {r.text[:300]}")
    return r.content


def _gemini_image(prompt, seed):
    import base64
    model = C.env("GEMINI_IMAGE_MODEL", "gemini-2.5-flash-image")
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
    body = {"contents": [{"parts": [{"text": prompt + " Vertical 9:16 image."}]}]}
    r = requests.post(url, headers={"x-goog-api-key": C.GEMINI_API_KEY}, json=body, timeout=180)
    if r.status_code >= 400:
        raise RuntimeError(f"Gemini image error {r.status_code}: {r.text[:300]}")
    for p in r.json()["candidates"][0]["content"]["parts"]:
        if "inlineData" in p:
            return base64.b64decode(p["inlineData"]["data"])
    raise RuntimeError("Gemini returned no image")


def generate(scene, seed, size=None, raw_prompt=None):
    """Returns a PIL image cover-cropped to size (default the 9:16 reel size).
    raw_prompt: use this exact prompt instead of the story-character prompt (carousels)."""
    size = size or (C.W, C.H)
    prompt = raw_prompt or full_prompt(scene)
    providers = [C.IMAGE_PROVIDER] + [p for p in ("pollinations", "gemini") if p != C.IMAGE_PROVIDER]
    last = None
    for provider in providers:
        for attempt in range(3):
            try:
                raw = _pollinations(prompt, seed + attempt, size) if provider == "pollinations" else _gemini_image(prompt, seed)
                img = Image.open(io.BytesIO(raw)).convert("RGB")
                return fit(img, size)
            except Exception as e:  # rate limit / timeout -> back off and retry
                last = e
                print(f"[images] {provider} attempt {attempt + 1} failed: {e}")
                time.sleep(20 * (attempt + 1))
    raise RuntimeError(f"All image providers failed: {last}")


def fit(img, size=None):
    """Cover-crop to exactly size."""
    w, h = size or (C.W, C.H)
    s = max(w / img.width, h / img.height)
    img = img.resize((round(img.width * s), round(img.height * s)), Image.LANCZOS)
    l = (img.width - w) // 2
    t = (img.height - h) // 2
    return img.crop((l, t, l + w, t + h))
