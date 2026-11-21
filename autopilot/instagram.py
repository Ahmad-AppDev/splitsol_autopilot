"""Instagram API with Instagram Login: publish Reels, read comment votes, refresh token."""
import time
import requests
from . import config as C


def _get(path, **params):
    params["access_token"] = C.IG_ACCESS_TOKEN
    r = requests.get(f"{C.IG_GRAPH}/{path}", params=params, timeout=60)
    r.raise_for_status()
    return r.json()


def _post(path, **params):
    params["access_token"] = C.IG_ACCESS_TOKEN
    r = requests.post(f"{C.IG_GRAPH}/{path}", data=params, timeout=60)
    if r.status_code >= 400:
        raise RuntimeError(f"Instagram error: {r.text}")
    return r.json()


def publish_reel(video_url, caption):
    c = _post(f"{C.IG_USER_ID}/media", media_type="REELS", video_url=video_url, caption=caption, share_to_feed="true")
    cid = c["id"]
    for _ in range(60):  # up to ~10 min processing
        st = _get(cid, fields="status_code,status").get("status_code")
        if st == "FINISHED":
            break
        if st == "ERROR":
            raise RuntimeError(f"Instagram processing failed: {_get(cid, fields='status')}")
        time.sleep(10)
    else:
        raise RuntimeError("Instagram processing timed out")
    return _post(f"{C.IG_USER_ID}/media_publish", creation_id=cid)["id"]


def count_votes(media_id, options):
    counts = {o: 0 for o in options}
    seen = set()
    url_params = {"fields": "text,username", "limit": 100}
    page = _get(f"{media_id}/comments", **url_params)
    while True:
        for c in page.get("data", []):
            who = c.get("username") or c.get("id")
            words = c.get("text", "").upper().replace("-", "").split()
            for o in options:
                if o.upper().replace("-", "") in words and (who, o) not in seen:
                    seen.add((who, o))
                    counts[o] += 1
        nxt = page.get("paging", {}).get("next")
        if not nxt:
            break
        page = requests.get(nxt, timeout=60).json()
    return counts


def refresh_token():
    r = requests.get("https://graph.instagram.com/refresh_access_token",
                     params={"grant_type": "ig_refresh_token", "access_token": C.IG_ACCESS_TOKEN}, timeout=60)
    return r.ok
