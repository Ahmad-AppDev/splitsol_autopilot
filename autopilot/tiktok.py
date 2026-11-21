"""TikTok Content Posting API. mode=inbox sends to your TikTok inbox/drafts (works before app audit);
mode=direct posts publicly (needs an audited app)."""
import requests
from . import config as C

API = "https://open.tiktokapis.com/v2"


def access_token():
    r = requests.post(f"{API}/oauth/token/", headers={"Content-Type": "application/x-www-form-urlencoded"},
                      data={"client_key": C.TIKTOK_CLIENT_KEY, "client_secret": C.TIKTOK_CLIENT_SECRET,
                            "grant_type": "refresh_token", "refresh_token": C.TIKTOK_REFRESH_TOKEN}, timeout=60)
    j = r.json()
    if "access_token" not in j:
        raise RuntimeError(f"TikTok token refresh failed: {j}")
    rotated = j.get("refresh_token") and j["refresh_token"] != C.TIKTOK_REFRESH_TOKEN
    return j["access_token"], (j["refresh_token"] if rotated else None)


def upload(video_path, caption):
    token, new_refresh = access_token()
    size = video_path.stat().st_size
    source = {"source": "FILE_UPLOAD", "video_size": size, "chunk_size": size, "total_chunk_count": 1}
    if C.TIKTOK_MODE == "direct":
        url = f"{API}/post/publish/video/init/"
        body = {"post_info": {"title": caption[:2000], "privacy_level": "PUBLIC_TO_EVERYONE",
                              "disable_comment": False, "disable_duet": False, "disable_stitch": False,
                              "is_aigc": True},
                "source_info": source}
    else:
        url = f"{API}/post/publish/inbox/video/init/"
        body = {"source_info": source}
    r = requests.post(url, headers={"Authorization": f"Bearer {token}",
                                    "Content-Type": "application/json; charset=UTF-8"}, json=body, timeout=60)
    j = r.json()
    if j.get("error", {}).get("code") not in (None, "ok"):
        raise RuntimeError(f"TikTok init failed: {j}")
    up = j["data"]["upload_url"]
    with open(video_path, "rb") as f:
        r = requests.put(up, data=f, headers={"Content-Type": "video/mp4",
                                              "Content-Range": f"bytes 0-{size - 1}/{size}"}, timeout=600)
    if r.status_code >= 300:
        raise RuntimeError(f"TikTok upload failed: {r.status_code} {r.text}")
    return j["data"].get("publish_id"), new_refresh
