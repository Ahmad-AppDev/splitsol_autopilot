"""Writes the next episode with the Gemini API (free tier)."""
import json
import re
import requests
from . import config as C

SCHEMA_HINT = """Return ONLY JSON with this shape:
{
  "title": "THE TRIP",
  "scenes": [{"narration": "...", "image": "scene description for the illustrator"}],   // 4-6 scenes
  "hud_after": {"paid": int, "share": int, "friendship": int},
  "vote": {"question": "...", "options": ["WORD1", "WORD2"]},
  "caption": "Instagram/TikTok caption, ends with the comment ask, then 'SplitSol — link in bio' and 3-5 hashtags"
}"""


API = "https://generativelanguage.googleapis.com/v1beta"
_model = None


def _headers():
    # key goes in a header, never in the URL, so it can't leak into logs or error messages
    return {"x-goog-api-key": C.GEMINI_API_KEY, "Content-Type": "application/json"}


def _version(name):
    m = re.search(r"gemini-(\d+(?:\.\d+)?)", name)
    return float(m.group(1)) if m else 0.0


def pick_model():
    """Newest text 'flash' model this key can call (Google renames models often)."""
    global _model
    if _model:
        return _model
    if C.GEMINI_MODEL:
        _model = C.GEMINI_MODEL
        return _model
    r = requests.get(f"{API}/models", params={"pageSize": 1000}, headers=_headers(), timeout=60)
    if r.status_code >= 400:
        raise RuntimeError(f"Gemini model list failed ({r.status_code}): {r.text[:300]}")
    names = []
    for m in r.json().get("models", []):
        name = m["name"].split("/", 1)[1]
        if "generateContent" not in m.get("supportedGenerationMethods", []):
            continue
        if "flash" not in name or any(b in name for b in ("image", "tts", "audio", "live", "embedding", "vision")):
            continue
        names.append(name)
    if not names:
        raise RuntimeError("No Gemini Flash model available for this key")
    stable = [n for n in names if not any(t in n for t in ("preview", "exp", "lite"))]
    pool = stable or names
    _model = sorted(pool, key=lambda n: (_version(n), "latest" not in n, -len(n)), reverse=True)[0]
    print(f"[gemini] using model {_model}")
    return _model


def gemini(prompt, images=None, json_mode=True, model=None):
    if not C.GEMINI_API_KEY:
        raise SystemExit("Missing GEMINI_API_KEY")
    parts = [{"text": prompt}]
    for img in images or []:
        import base64
        parts.append({"inline_data": {"mime_type": "image/jpeg", "data": base64.b64encode(img).decode()}})
    body = {"contents": [{"parts": parts}]}
    if json_mode:
        body["generationConfig"] = {"responseMimeType": "application/json", "temperature": 0.9}
    r = requests.post(f"{API}/models/{model or pick_model()}:generateContent", headers=_headers(), json=body, timeout=180)
    if r.status_code >= 400:
        raise RuntimeError(f"Gemini error {r.status_code}: {r.text[:400]}")
    text = r.json()["candidates"][0]["content"]["parts"][0]["text"]
    return json.loads(text) if json_mode else text


def write_episode(state, vote_result, feedback=None):
    bible = (C.STORY / "bible.md").read_text()
    history = "\n".join(f"Day {h['day']}: {h['summary']} -> audience chose {h.get('chosen')}" for h in state["history"])
    prompt = f"""You write a daily vertical-video story series for the SplitSol app (bill-splitting app for friends).

SERIES BIBLE:
{bible}

STORY SO FAR:
{history or '(nothing yet)'}

Current stats before today: PAID Rs {state['hud']['paid']}, YOUR SHARE Rs {state['hud']['share']}, FRIENDSHIP {state['hud']['friendship']}%.
Yesterday's audience vote result: {vote_result or 'no vote data, pick the funnier option'}.
Today is DAY {state['day']}. Continue the story directly from the winning choice.
{('Extra direction from the creator: ' + feedback) if feedback else ''}

Rules: second person narrator, each narration line under 25 words, last narration line ends with "Comment X or Y."
using the two vote options. Image descriptions mention 'YOU' for the main character and friends by name; describe
action, expression, place and lighting; no text in the image. Never write "who owes who".
{SCHEMA_HINT}"""
    ep = gemini(prompt)
    ep.setdefault("title", "THE TRIP")
    return ep
