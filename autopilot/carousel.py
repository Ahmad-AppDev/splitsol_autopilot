"""Daily listicle carousel: Gemini writes it, Pollinations draws it, Pillow lays out the slides (1080x1350)."""
from functools import lru_cache
from PIL import Image, ImageDraw, ImageFont, ImageFilter
from . import config as C

CW, CH = 1080, 1350
IMG_STYLE = ("colorful hand-drawn comic illustration, bold black ink outlines, warm painterly colors, "
             "simple cartoon people, clean background, no text, no letters, no numbers")


@lru_cache(None)
def font(weight, size):
    return ImageFont.truetype(str(C.FONTS / f"Poppins-{weight}.ttf"), size)


# ---------- writing ----------

def write(state, feedback=None):
    from .writer import gemini
    from . import verify
    bible = (C.STORY / "carousel_bible.md").read_text()
    past = [h.get("title", "") for h in state.get("carousels", [])]
    prompt = f"""You write daily Instagram/TikTok carousels for SplitSol, a bill-splitting app.

{bible}

Titles already used (never repeat or closely copy): {past or 'none yet'}
{('Direction from the creator: ' + feedback) if feedback else ''}

Return ONLY JSON:
{{"title": "8 Things That Ruin Every Group Trip",
  "cover_image": "illustration description for the cover",
  "points": [{{"headline": "...", "body": "...", "image": "illustration description"}}],
  "caption": "..."}}"""
    last = None
    for _ in range(3):
        c = gemini(prompt)
        problems = check(c)
        if not problems:
            return c
        last = problems
        prompt += "\nFix these problems: " + "; ".join(problems)
    raise RuntimeError(f"Carousel failed checks: {last}")


def check(c):
    problems = []
    text = " ".join([c.get("title", ""), c.get("caption", "")] +
                    [p.get("headline", "") + " " + p.get("body", "") for p in c.get("points", [])]).lower()
    for b in C.BANNED_PHRASES:
        if b in text:
            problems.append(f"banned phrase: {b}")
    n = len(c.get("points", []))
    if not 5 <= n <= 9:
        problems.append(f"{n} points (need 6-8)")
    for p in c.get("points", []):
        if len(p.get("headline", "").split()) > 10:
            problems.append("headline too long")
        if len(p.get("body", "").split()) > 30:
            problems.append("body too long")
    if not c.get("title"):
        problems.append("missing title")
    return problems


# ---------- drawing ----------

def draw_images(c, seed):
    from . import images
    out = []
    scenes = [c["cover_image"]] + [p["image"] for p in c["points"]]
    for i, scene in enumerate(scenes):
        size = (CW, 900) if i == 0 else (CW, 760)
        out.append(images.generate(scene, seed + i * 11, size=size, raw_prompt=f"{scene}. {IMG_STYLE}."))
    return out


# ---------- layout ----------

def _wrap(d, text, f, max_w):
    words, lines, cur = text.split(), [], ""
    for w in words:
        t = (cur + " " + w).strip()
        if d.textlength(t, font=f) <= max_w:
            cur = t
        else:
            lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines


def _fit_text(d, text, weight, start, min_size, max_w, max_lines):
    size = start
    while size > min_size:
        f = font(weight, size)
        lines = _wrap(d, text, f, max_w)
        if len(lines) <= max_lines:
            return f, lines
        size -= 4
    f = font(weight, min_size)
    return f, _wrap(d, text, f, max_w)


def _brand_row(d, y, color_line, text_color):
    wm = font("Bold", 30)
    s1, s2 = "split", "sol"
    w1, w2 = d.textlength(s1, font=wm), d.textlength(s2, font=wm)
    total = w1 + w2 + 14
    x = (CW - total) / 2
    d.line((150, y + 22, x - 24, y + 22), fill=color_line, width=3)
    d.line((x + total + 24, y + 22, CW - 150, y + 22), fill=color_line, width=3)
    d.text((x, y), s1, font=wm, fill=text_color)
    d.rounded_rectangle((x + w1 + 2, y + 4, x + w1 + w2 + 14, y + 44), 7, fill=C.CREAM)
    d.text((x + w1 + 8, y), s2, font=wm, fill=C.TERRACOTTA)


def cover(img, title):
    im = Image.new("RGB", (CW, CH), C.INK)
    im.paste(img, (0, 0))
    # soft fade from image into the dark panel
    fade = Image.new("L", (CW, 220))
    for y in range(220):
        fade.paste(int(255 * (y / 220) ** 1.3), (0, y, CW, y + 1))
    im.paste(Image.new("RGB", (CW, 220), C.INK), (0, 900 - 220), fade)
    d = ImageDraw.Draw(im)
    _brand_row(d, 905, C.TERRACOTTA, C.CREAM)
    f, lines = _fit_text(d, title, "Bold", 84, 56, CW - 140, 3)
    lh = int(f.size * 1.12)
    y = 975 + (CH - 975 - 40 - lh * len(lines)) / 2
    for line in lines:
        d.text(((CW - d.textlength(line, font=f)) / 2, y), line, font=f, fill="white")
        y += lh
    return im


def point(img, n, total, headline, body):
    im = Image.new("RGB", (CW, CH), C.CREAM)
    im.paste(img, (0, 0))
    d = ImageDraw.Draw(im)
    # number badge overlapping the image edge
    d.ellipse((70, 700, 190, 820), fill=C.TERRACOTTA, outline=C.CREAM, width=6)
    nf = font("Bold", 58)
    ns = str(n)
    d.text((130 - d.textlength(ns, font=nf) / 2, 718), ns, font=nf, fill=C.CREAM)
    hf, hl = _fit_text(d, headline, "Bold", 64, 44, CW - 140, 2)
    y = 850
    for line in hl:
        d.text((70, y), line, font=hf, fill=C.INK)
        y += int(hf.size * 1.12)
    bf, bl = _fit_text(d, body, "Regular", 40, 30, CW - 140, 4)
    y += 18
    for line in bl:
        d.text((70, y), line, font=bf, fill=(70, 62, 55))
        y += int(bf.size * 1.4)
    # footer
    sf = font("Medium", 26)
    d.text((70, CH - 70), f"{n}/{total}", font=sf, fill=(150, 140, 128))
    wm = font("Bold", 28)
    w1, w2 = d.textlength("split", font=wm), d.textlength("sol", font=wm)
    x = CW - 70 - (w1 + w2 + 12)
    d.text((x, CH - 74), "split", font=wm, fill=C.INK)
    d.rounded_rectangle((x + w1 + 2, CH - 70, x + w1 + w2 + 12, CH - 32), 6, fill=C.TERRACOTTA)
    d.text((x + w1 + 7, CH - 74), "sol", font=wm, fill=C.CREAM)
    return im


def cta():
    im = Image.new("RGB", (CW, CH), C.TERRACOTTA)
    d = ImageDraw.Draw(im)
    big = font("Bold", 92)
    y = 360
    for line in ["Stop doing", "the maths."]:
        d.text(((CW - d.textlength(line, font=big)) / 2, y), line, font=big, fill=C.CREAM)
        y += 110
    body = font("Medium", 40)
    for line in ["SplitSol splits every bill fairly —", "to the paisa. Then settles it in one tap."]:
        d.text(((CW - d.textlength(line, font=body)) / 2, y + 40), line, font=body, fill=(255, 235, 222))
        y += 56
    wm = font("Bold", 96)
    w1, w2 = d.textlength("split", font=wm), d.textlength("sol", font=wm)
    x = (CW - (w1 + w2 + 30)) / 2
    yy = 830
    d.text((x, yy), "split", font=wm, fill=C.CREAM)
    d.rounded_rectangle((x + w1 + 6, yy + 18, x + w1 + w2 + 30, yy + 128), 16, fill=C.CREAM)
    d.text((x + w1 + 18, yy), "sol", font=wm, fill=C.TERRACOTTA)
    pill = "Download free · link in bio"
    pf = font("Bold", 38)
    pw = d.textlength(pill, font=pf)
    d.rounded_rectangle(((CW - pw) / 2 - 40, 1040, (CW + pw) / 2 + 40, 1120), 40, fill=C.INK)
    d.text(((CW - pw) / 2, 1056), pill, font=pf, fill=C.CREAM)
    return im


def render(c, imgs, out_dir):
    out_dir.mkdir(parents=True, exist_ok=True)
    pts = c["points"]
    total = len(pts) + 2
    slides = [cover(imgs[0], c["title"])]
    for i, (p, img) in enumerate(zip(pts, imgs[1:]), start=1):
        slides.append(point(img, i, len(pts), p["headline"], p["body"]))
    slides.append(cta())
    paths = []
    for i, s in enumerate(slides, start=1):
        path = out_dir / f"slide{i:02d}.jpg"
        s.save(path, "JPEG", quality=92)
        paths.append(path)
    assert len(paths) == total
    return paths
