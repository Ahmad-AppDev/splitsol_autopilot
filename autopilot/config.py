import os
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STORY = ROOT / "story"
FONTS = ROOT / "assets" / "fonts"
OUT = ROOT / "out"

def env(name, default=None, required=False):
    v = os.environ.get(name, default)
    if required and not v:
        raise SystemExit(f"Missing env/secret: {name}")
    return v

GEMINI_API_KEY = env("GEMINI_API_KEY")
GEMINI_MODEL = env("GEMINI_MODEL", "gemini-2.5-flash")
VOICE = env("TTS_VOICE", "en-US-AndrewMultilingualNeural")
IMAGE_PROVIDER = env("IMAGE_PROVIDER", "pollinations")  # pollinations | gemini
POLLINATIONS_MODEL = env("POLLINATIONS_MODEL", "flux")  # try gptimage / kontext / seedream for better art
POLLINATIONS_TOKEN = env("POLLINATIONS_TOKEN")  # key from enter.pollinations.ai (free starter credits)
CHARACTER_SEED = int(env("CHARACTER_SEED", "4242"))

TELEGRAM_BOT_TOKEN = env("TELEGRAM_BOT_TOKEN")
TELEGRAM_CHAT_ID = env("TELEGRAM_CHAT_ID")

IG_USER_ID = env("IG_USER_ID")
IG_ACCESS_TOKEN = env("IG_ACCESS_TOKEN")
IG_GRAPH = env("IG_GRAPH", "https://graph.instagram.com/v21.0")

TIKTOK_CLIENT_KEY = env("TIKTOK_CLIENT_KEY")
TIKTOK_CLIENT_SECRET = env("TIKTOK_CLIENT_SECRET")
TIKTOK_REFRESH_TOKEN = env("TIKTOK_REFRESH_TOKEN")
TIKTOK_MODE = env("TIKTOK_MODE", "inbox")  # inbox = goes to TikTok drafts/inbox; direct = posts (needs audited app)

GITHUB_REPOSITORY = env("GITHUB_REPOSITORY")

BANNED_PHRASES = ["who owes who", "who owes whom"]

# Brand
TERRACOTTA = (200, 85, 61)
CREAM = (246, 238, 224)
INK = (20, 18, 16)
W, H, FPS = 1080, 1920, 30
