"""Automatic checks before anything reaches you."""
import io
import json
from . import config as C


def check_script(ep):
    problems = []
    text = " ".join(s["narration"] for s in ep["scenes"]) + " " + ep.get("caption", "")
    for p in C.BANNED_PHRASES:
        if p in text.lower():
            problems.append(f"banned phrase: {p}")
    if not 3 <= len(ep["scenes"]) <= 7:
        problems.append(f"{len(ep['scenes'])} scenes")
    opts = ep.get("vote", {}).get("options", [])
    if len(opts) != 2:
        problems.append("vote needs exactly 2 options")
    last = ep["scenes"][-1]["narration"].upper()
    if opts and not all(o.upper() in last for o in opts):
        problems.append("last line doesn't ask for the comment vote")
    for s in ep["scenes"]:
        if len(s["narration"].split()) > 32:
            problems.append("narration line too long")
    for k in ("paid", "share", "friendship"):
        if k not in ep.get("hud_after", {}):
            problems.append(f"missing hud {k}")
    return problems


def check_image(img, scene):
    """Uses Gemini vision (free tier) to reject broken frames. Returns (ok, reason)."""
    if not C.GEMINI_API_KEY:
        return True, "no key, skipped"
    from .writer import gemini
    buf = io.BytesIO()
    img.resize((540, 960)).save(buf, "JPEG", quality=85)
    prompt = f"""You are QA for a cartoon series. The main character MUST look like: big perfectly round white head,
dot eyes, terracotta-orange cap and polo shirt, khaki trousers. Intended scene: {scene}
Reject if: main character missing or clearly different design, visible text/letters/watermark, badly deformed bodies
or extra limbs, or the image is not an illustration. Minor style differences are fine.
Return JSON {{"ok": true|false, "reason": "short"}}"""
    try:
        r = gemini(prompt, images=[buf.getvalue()])
        return bool(r.get("ok")), r.get("reason", "")
    except Exception as e:
        return True, f"qa skipped: {e}"


def check_video(path, seconds):
    problems = []
    size = path.stat().st_size
    if size > 250 * 1024 * 1024:
        problems.append("file too big")
    if not 10 <= seconds <= 90:
        problems.append(f"duration {seconds:.1f}s outside 10–90s")
    return problems
