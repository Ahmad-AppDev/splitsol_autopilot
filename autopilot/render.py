"""Renders the reel: Ken Burns scenes + HUD + Day tag + word-by-word captions + vote end card."""
import subprocess
from functools import lru_cache
from PIL import Image, ImageDraw, ImageFont
from . import config as C

END_CARD = 2.2   # seconds of vote card after narration
GAP = 0.25       # pause between scenes


@lru_cache(None)
def font(weight, size):
    return ImageFont.truetype(str(C.FONTS / f"Poppins-{weight}.ttf"), size)


def rs(n):
    return f"Rs {int(n):,}"


def _text_w(d, s, f):
    return d.textlength(s, font=f)


def hud_layer(day, hud):
    im = Image.new("RGBA", (C.W, C.H), (0, 0, 0, 0))
    # top gradient for legibility
    grad = Image.new("L", (1, 760))
    for y in range(760):
        grad.putpixel((0, y), int(190 * (1 - y / 760) ** 1.6))
    im.paste(Image.new("RGBA", (C.W, 760), (0, 0, 0, 255)), (0, 0), grad.resize((C.W, 760)))
    d = ImageDraw.Draw(im)
    boxes = [("PAID", rs(hud["paid"]), (255, 255, 255)),
             ("YOUR SHARE", rs(hud["share"]), (255, 255, 255)),
             ("FRIENDSHIP", f"{int(hud['friendship'])}%", (255, 140, 110))]
    m, gap, top, bh = 56, 18, 130, 128
    bw = (C.W - 2 * m - 2 * gap) // 3
    for i, (label, val, col) in enumerate(boxes):
        x = m + i * (bw + gap)
        d.rounded_rectangle((x, top, x + bw, top + bh), 16, fill=(18, 18, 18, 215), outline=(255, 255, 255, 40), width=2)
        d.text((x + 20, top + 14), label, font=font("Medium", 22), fill=(190, 190, 190, 255))
        f = font("Bold", 44)
        while _text_w(d, val, f) > bw - 36:
            f = font("Bold", f.size - 2)
        d.text((x + 20, top + 50), val, font=f, fill=col)
        if label == "FRIENDSHIP":
            pct = max(0, min(100, hud["friendship"])) / 100
            d.rounded_rectangle((x + 20, top + bh - 14, x + bw - 20, top + bh - 8), 3, fill=(255, 255, 255, 50))
            d.rounded_rectangle((x + 20, top + bh - 14, x + 20 + int((bw - 40) * pct), top + bh - 8), 3, fill=C.TERRACOTTA + (255,))
    tag = f"DAY {day}"
    f = font("Bold", 34)
    tw = _text_w(d, tag, f)
    d.rounded_rectangle((m, top + bh + 22, m + tw + 36, top + bh + 22 + 56), 10, fill=C.TERRACOTTA + (255,))
    d.text((m + 18, top + bh + 24), tag, font=f, fill=C.CREAM)
    return im


def title_layer(title):
    im = Image.new("RGBA", (C.W, C.H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    f = font("Bold", 124)
    while _text_w(d, title, f) > C.W - 100:
        f = font("Bold", f.size - 4)
    tw = _text_w(d, title, f)
    d.text(((C.W - tw) / 2, 400), title, font=f, fill="white", stroke_width=8, stroke_fill=(0, 0, 0))
    return im


def chunk_words(words, n=4):
    chunks, cur = [], []
    for w in words:
        cur.append(w)
        if len(cur) == n or w["w"].endswith((".", ",", "?", "!")):
            chunks.append(cur)
            cur = []
    if cur:
        chunks.append(cur)
    return chunks


def caption_layer(chunk, spoken):
    im = Image.new("RGBA", (C.W, C.H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    f = font("Bold", 74)
    words = [w["w"] for w in chunk]
    space = _text_w(d, " ", f)
    widths = [_text_w(d, w, f) for w in words]
    total = sum(widths) + space * (len(words) - 1)
    while total > C.W - 120:
        f = font("Bold", f.size - 4)
        space = _text_w(d, " ", f)
        widths = [_text_w(d, w, f) for w in words]
        total = sum(widths) + space * (len(words) - 1)
    x, y = (C.W - total) / 2, 1480
    d.rounded_rectangle((x - 30, y - 14, x + total + 30, y + f.size + 30), 22, fill=(0, 0, 0, 120))
    for i, (w, wd) in enumerate(zip(words, widths)):
        col = (255, 255, 255, 255) if i < spoken else (190, 190, 190, 200)
        d.text((x, y), w, font=f, fill=col, stroke_width=6, stroke_fill=(0, 0, 0, 255))
        x += wd + space
    return im


def end_card(options):
    im = Image.new("RGBA", (C.W, C.H), (0, 0, 0, 150))
    d = ImageDraw.Draw(im)
    small = font("Medium", 46)
    t = "COMMENT"
    d.text(((C.W - _text_w(d, t, small)) / 2, 760), t, font=small, fill=C.CREAM)
    big = font("Bold", 112)
    a, b = options
    for i, word in enumerate([a, "or", b]):
        f = font("Medium", 60) if word == "or" else big
        while _text_w(d, word, f) > C.W - 120:
            f = font("Bold", f.size - 4)
        y = [850, 990, 1080][i]
        fill = C.CREAM if word == "or" else "white"
        d.text(((C.W - _text_w(d, word, f)) / 2, y), word, font=f, fill=fill, stroke_width=0 if word == "or" else 6, stroke_fill=C.TERRACOTTA)
    # SplitSol wordmark with cream slab
    wm = font("Bold", 56)
    s1, s2 = "split", "sol"
    w1, w2 = _text_w(d, s1, wm), _text_w(d, s2, wm)
    x = (C.W - (w1 + w2 + 16)) / 2
    y = 1500
    d.text((x, y), s1, font=wm, fill=C.CREAM)
    d.rounded_rectangle((x + w1 + 4, y + 8, x + w1 + w2 + 22, y + 78), 10, fill=C.CREAM)
    d.text((x + w1 + 12, y), s2, font=wm, fill=C.TERRACOTTA)
    sub = font("Medium", 32)
    st = "next episode follows the winner"
    d.text(((C.W - _text_w(d, st, sub)) / 2, 1610), st, font=sub, fill=(230, 230, 230))
    return im


def ken_burns(img, t):
    """t in 0..1 -> slow push-in."""
    z = 1.0 + 0.08 * t
    cw, ch = C.W / z, C.H / z
    l, top = (C.W - cw) / 2, (C.H - ch) * 0.45
    return img.crop((int(l), int(top), int(l + cw), int(top + ch))).resize((C.W, C.H), Image.BILINEAR)


def build_audio(clips, out_wav):
    """clips: list of (mp3_path, seconds). Concats with gaps + end-card silence."""
    inputs, filt = [], []
    for i, (p, _) in enumerate(clips):
        inputs += ["-i", str(p)]
        filt.append(f"[{i}:a]aresample=44100,apad=pad_dur={GAP}[a{i}]")
    cat = "".join(f"[a{i}]" for i in range(len(clips)))
    filt.append(f"{cat}concat=n={len(clips)}:v=0:a=1,apad=pad_dur={END_CARD}[out]")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", *inputs, "-filter_complex", ";".join(filt),
                    "-map", "[out]", str(out_wav)], check=True)


def render(ep, day, hud_before, scenes, out_mp4, audio_wav):
    """scenes: list of dicts {img: PIL, words: [...], seconds: float} (word times relative to scene)."""
    hud_after = ep["hud_after"]
    seg = [s["seconds"] + GAP for s in scenes]
    total = sum(seg) + END_CARD
    nframes = int(total * C.FPS)
    title = title_layer(ep.get("title", "THE TRIP"))
    endc = end_card(ep["vote"]["options"])
    hud_cache = {}

    proc = subprocess.Popen(["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24",
                             "-s", f"{C.W}x{C.H}", "-r", str(C.FPS), "-i", "-", "-i", str(audio_wav),
                             "-c:v", "libx264", "-preset", "veryfast", "-crf", "20", "-pix_fmt", "yuv420p",
                             "-c:a", "aac", "-b:a", "160k", "-shortest", "-movflags", "+faststart", str(out_mp4)],
                            stdin=subprocess.PIPE)
    starts = [sum(seg[:i]) for i in range(len(seg))]
    chunks = [chunk_words(s["words"]) for s in scenes]
    for fi in range(nframes):
        t = fi / C.FPS
        si = max(i for i, s0 in enumerate(starts) if t >= s0) if t < sum(seg) else len(scenes) - 1
        local = t - starts[si]
        sc = scenes[si]
        frame = ken_burns(sc["img"], min(1, local / seg[si])).convert("RGBA")
        # HUD: animate to new values during the last scene
        if si == len(scenes) - 1:
            k = min(1.0, max(0.0, local / max(1.0, seg[si] * 0.6)))
        else:
            k = 0.0
        hud = {key: round(hud_before[key] + (hud_after[key] - hud_before[key]) * k) for key in hud_after}
        if 0 < k < 1:
            hud["paid"], hud["share"] = round(hud["paid"], -2), round(hud["share"], -2)
        key = (day, hud["paid"], hud["share"], hud["friendship"])
        if key not in hud_cache:
            hud_cache[key] = hud_layer(day, hud)
        frame.alpha_composite(hud_cache[key])
        if si == 0:
            frame.alpha_composite(title)
        if t < sum(seg):
            for ch in chunks[si]:
                if ch[0]["start"] - 0.05 <= local <= ch[-1]["end"] + 0.25:
                    spoken = sum(1 for w in ch if w["start"] <= local)
                    frame.alpha_composite(caption_layer(ch, spoken))
                    break
        else:
            frame.alpha_composite(endc)
        proc.stdin.write(frame.convert("RGB").tobytes())
    proc.stdin.close()
    proc.wait()
    if proc.returncode:
        raise RuntimeError("ffmpeg failed")
    return total
