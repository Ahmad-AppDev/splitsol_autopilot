"""Free voiceover with edge-tts, including per-word timings for the captions."""
import asyncio
import subprocess
from . import config as C


async def _speak(text, path):
    import edge_tts
    try:
        com = edge_tts.Communicate(text, C.VOICE, rate="+4%", boundary="WordBoundary")
    except TypeError:  # older edge-tts: word boundaries are the default
        com = edge_tts.Communicate(text, C.VOICE, rate="+4%")
    words = []
    with open(path, "wb") as f:
        async for chunk in com.stream():
            if chunk["type"] == "audio":
                f.write(chunk["data"])
            elif chunk["type"] == "WordBoundary":
                start = chunk["offset"] / 1e7
                words.append({"w": chunk["text"], "start": start, "end": start + chunk["duration"] / 1e7})
    return words


def duration(path):
    out = subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                                   "-of", "default=nw=1:nk=1", str(path)])
    return float(out.strip())


def speak(text, path):
    """Returns (words, seconds). words: [{w, start, end}] relative to clip start."""
    words = asyncio.run(_speak(text, path))
    return words, duration(path)
