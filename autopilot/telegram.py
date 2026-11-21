"""Telegram bot: sends you the reel with Approve / Redo buttons, reads your taps."""
import json
import requests
from . import config as C


def _api(method, **kw):
    r = requests.post(f"https://api.telegram.org/bot{C.TELEGRAM_BOT_TOKEN}/{method}", timeout=120, **kw)
    r.raise_for_status()
    return r.json()["result"]


def send(text):
    if C.TELEGRAM_BOT_TOKEN and C.TELEGRAM_CHAT_ID:
        _api("sendMessage", data={"chat_id": C.TELEGRAM_CHAT_ID, "text": text[:4000]})
    else:
        print("[telegram]", text)


def send_for_approval(video_path, day, caption, notes=""):
    kb = {"inline_keyboard": [[{"text": "✅ Post it", "callback_data": f"approve:{day}"},
                               {"text": "🔁 Redo", "callback_data": f"redo:{day}"}]]}
    text = (f"🎬 SplitSol · THE TRIP · Day {day} is ready.\n\n{caption}\n\n{notes}\n"
            "Tap ✅ to post to Instagram + TikTok, or 🔁 to make a new version. "
            "To change something, reply with text (e.g. 'make Bilal funnier') and then tap 🔁.")
    with open(video_path, "rb") as f:
        _api("sendVideo", data={"chat_id": C.TELEGRAM_CHAT_ID, "caption": text[:1024],
                                "reply_markup": json.dumps(kb), "supports_streaming": "true"},
             files={"video": f})


def updates(offset):
    """Returns (taps, notes, new_offset). taps: [(action, day)] ; notes: free-text replies from you."""
    res = _api("getUpdates", data={"offset": offset, "timeout": 0,
                                   "allowed_updates": json.dumps(["callback_query", "message"])})
    taps, notes = [], []
    for u in res:
        offset = u["update_id"] + 1
        if "callback_query" in u:
            cq = u["callback_query"]
            if str(cq["message"]["chat"]["id"]) != str(C.TELEGRAM_CHAT_ID):
                continue
            action, day = cq["data"].split(":")
            taps.append((action, int(day)))
            try:
                _api("answerCallbackQuery", data={"callback_query_id": cq["id"], "text": "Got it ✔"})
            except Exception:
                pass
        elif "message" in u and str(u["message"]["chat"]["id"]) == str(C.TELEGRAM_CHAT_ID):
            txt = u["message"].get("text", "")
            if txt and not txt.startswith("/"):
                notes.append(txt)
    return taps, notes, offset
