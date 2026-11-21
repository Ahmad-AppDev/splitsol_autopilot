"""Offline test: renders Day 1 with placeholder art + silent audio to check layout/timing.
python tools/test_render.py
"""
import json
import subprocess
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from PIL import Image, ImageDraw
import shutil
from autopilot import config as C, render
from autopilot.voice import duration as voice_duration

ep = json.loads((C.STORY / "day1.json").read_text())
work = C.OUT / "test"
work.mkdir(parents=True, exist_ok=True)
scenes, clips = [], []
for i, sc in enumerate(ep["scenes"]):
    img = Image.new("RGB", (C.W, C.H))
    d = ImageDraw.Draw(img)
    for y in range(C.H):
        k = y / C.H
        d.line([(0, y), (C.W, y)], fill=(int(120 + 80 * k), int(150 + 40 * k), int(190 - 90 * k)))
    d.polygon([(0, 1100), (300, 700), (600, 1000), (850, 650), (1080, 950), (1080, 1920), (0, 1920)], fill=(90, 110, 90))
    cx, cy = 540, 1150
    d.ellipse((cx - 130, cy - 130, cx + 130, cy + 130), fill="white", outline="black", width=6)
    d.rectangle((cx - 90, cy + 120, cx + 90, cy + 420), fill=C.TERRACOTTA, outline="black", width=6)
    d.ellipse((cx - 45, cy - 20, cx - 25, cy), fill="black"); d.ellipse((cx + 25, cy - 20, cx + 45, cy), fill="black")
    mp3 = work / f"s{i}.wav"
    if shutil.which("espeak-ng"):  # robotic offline voice, just for previews
        subprocess.run(["espeak-ng", "-v", "en-us+m3", "-s", "165", "-w", str(mp3), sc["narration"]], check=True)
        secs = voice_duration(mp3)
    else:
        secs = None
    toks = sc["narration"].split()
    weights = [len(w) + 2 for w in toks]
    span = (secs - 0.3) if secs else sum(0.16 + 0.055 * len(w) for w in toks)
    words, t = [], 0.1
    for w, wt in zip(toks, weights):
        dur = span * wt / sum(weights)
        words.append({"w": w, "start": t, "end": t + dur * 0.9}); t += dur
    if not secs:
        secs = t + 0.2
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "lavfi", "-i", "anullsrc=r=44100:cl=mono",
                        "-t", f"{secs:.2f}", str(mp3)], check=True)
    scenes.append({"img": img, "words": words, "seconds": secs}); clips.append((mp3, secs))
wav = work / "voice.wav"
render.build_audio(clips, wav)
out = work / "day1_test.mp4"
total = render.render(ep, 1, json.loads((C.STORY / "state.json").read_text())["hud"], scenes, out, wav)
print("rendered", out, f"{total:.1f}s")
