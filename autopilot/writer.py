"""Writes the next episode with the Gemini API (free tier)."""
import json
import re
import time
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
_models = None


def _headers():
    # key goes in a header, never in the URL, so it can't leak into logs or error messages
    return {"x-goog-api-key": C.GEMINI_API_KEY, "Content-Type": "application/json"}


def _version(name):
    m = re.search(r"gemini-(\d+(?:\.\d+)?)", name)
    return float(m.group(1)) if m else 0.0


def models():
    """Flash models this key can call, best first (Google renames models often)."""
    global _models
    if _models:
        return _models
    if C.GEMINI_MODEL:
        _models = [C.GEMINI_MODEL]
        return _models
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

    def rank(n):
        unstable = any(t in n for t in ("preview", "exp"))
        return (not unstable, _version(n), "lite" not in n, "latest" not in n, -len(n))

    _models = sorted(names, key=rank, reverse=True)[:4]
    print(f"[gemini] models to try: {_models}")
    return _models


def pick_model():
    return models()[0]


def _call(model, body, light_thinking):
    b = dict(body)
    if light_thinking:
        gc = dict(b.get("generationConfig", {}))
        gc["thinkingConfig"] = {"thinkingLevel": "low"} if _version(model) >= 3 else {"thinkingBudget": 0}
        b["generationConfig"] = gc
    return requests.post(f"{API}/models/{model}:generateContent", headers=_headers(), json=b, timeout=300)


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
    last = None
    for m in ([model] if model else models()):
        for attempt in range(2):
            try:
                r = _call(m, body, light_thinking=True)
                if r.status_code == 400 and "thinking" in r.text.lower():
                    r = _call(m, body, light_thinking=False)  # model doesn't take thinking settings
                if r.status_code in (429, 500, 502, 503, 504):
                    last = f"{m}: {r.status_code} {r.text[:200]}"
                    time.sleep(10 * (attempt + 1))
                    continue
                if r.status_code >= 400:
                    raise RuntimeError(f"Gemini error {r.status_code} ({m}): {r.text[:400]}")
                cand = r.json()["candidates"][0]["content"]["parts"]
                text = "".join(p.get("text", "") for p in cand if not p.get("thought"))
                return json.loads(text) if json_mode else text
            except requests.exceptions.Timeout:
                last = f"{m}: timed out"
                print(f"[gemini] {m} timed out (attempt {attempt + 1})")
        print(f"[gemini] giving up on {m}, trying next model")
    raise RuntimeError(f"Gemini failed on all models: {last}")


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
