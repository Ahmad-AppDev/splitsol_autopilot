"""Entry point (run by GitHub Actions, triggered by schedule or by the SplitSol Studio Mac app).
  generate  # daily: make next episode, verify, mark it pending (the app notifies you)
  approve   # you tapped Approve in the app: post it, move to the next day
  redo      # you tapped Redo: make a new version (FEEDBACK env = your note)
  poll      # optional Telegram mode
"""
import datetime
import os
import json
import subprocess
import sys
import traceback
import requests
from . import config as C
from . import telegram as tg

STATE = C.STORY / "state.json"


def load():
    return json.loads(STATE.read_text())


def save(s):
    STATE.write_text(json.dumps(s, indent=2, ensure_ascii=False) + "\n")


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")


# ---------- generate ----------

def decide_vote(state):
    lp = state.get("last_posted")
    if not lp or not lp.get("ig_media_id") or not C.IG_ACCESS_TOKEN:
        return None
    from . import instagram
    counts = instagram.count_votes(lp["ig_media_id"], lp["options"])
    winner = max(counts, key=counts.get) if any(counts.values()) else lp["options"][0]
    if state["history"]:
        state["history"][-1]["chosen"] = winner
        state["history"][-1]["votes"] = counts
    return f"{winner} won ({', '.join(f'{k}: {v}' for k, v in counts.items())})"


def make_script(state, vote_result, feedback):
    from . import writer, verify
    if state["day"] == 1 and not state["history"] and not feedback:
        ep = json.loads((C.STORY / "day1.json").read_text())
        return ep
    last_problems = None
    for _ in range(3):
        ep = writer.write_episode(state, vote_result, feedback)
        problems = verify.check_script(ep)
        if not problems:
            return ep
        last_problems = problems
        feedback = (feedback or "") + " Fix these problems: " + "; ".join(problems)
    raise RuntimeError(f"Script failed checks: {last_problems}")


def generate(feedback=None):
    from . import images, voice, render, verify
    state = load()
    vote_result = decide_vote(state)
    ep = make_script(state, vote_result, feedback)
    day = state["day"]
    work = C.OUT / f"day{day}"
    work.mkdir(parents=True, exist_ok=True)

    scenes, clips, qa_notes = [], [], []
    for i, sc in enumerate(ep["scenes"]):
        seed = C.CHARACTER_SEED + day * 100 + i * 7 + (len(feedback) if feedback else 0)
        img, ok, why = None, False, ""
        for attempt in range(3):
            img = images.generate(sc["image"], seed + attempt * 1000)
            ok, why = verify.check_image(img, sc["image"])
            if ok:
                break
        if not ok:
            qa_notes.append(f"⚠️ scene {i + 1} may look off: {why}")
        img.save(work / f"scene{i + 1}.jpg", quality=90)
        mp3 = work / f"scene{i + 1}.mp3"
        words, secs = voice.speak(sc["narration"], mp3)
        scenes.append({"img": img, "words": words, "seconds": secs})
        clips.append((mp3, secs))

    wav = work / "voice.wav"
    render.build_audio(clips, wav)
    mp4 = work / f"splitsol-the-trip-day{day}.mp4"
    total = render.render(ep, day, state["hud"], scenes, mp4, wav)
    problems = verify.check_video(mp4, total)
    if problems:
        raise RuntimeError(f"Video failed checks: {problems}")

    # cover frame for reference
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-ss", "1.5", "-i", str(mp4), "-frames:v", "1",
                    str(work / "cover.jpg")], check=True)

    attempt = (state.get("pending") or {}).get("attempt", 0) + 1 if (state.get("pending") or {}).get("day") == day else 1
    tag = f"day{day}-v{attempt}"
    subprocess.run(["gh", "release", "create", tag, str(mp4), "--title", f"THE TRIP · Day {day} (v{attempt})",
                    "--notes", ep["caption"]], check=True)
    video_url = f"https://github.com/{C.GITHUB_REPOSITORY}/releases/download/{tag}/{mp4.name}"

    state["pending"] = {"day": day, "attempt": attempt, "episode": ep, "video_url": video_url,
                        "hud_before": state["hud"], "notes": [], "qa": qa_notes, "vote_result": vote_result,
                        "feedback": feedback, "created_at": now()}
    state["last_error"] = None
    save(state)
    notes = "\n".join(qa_notes + ([f"🗳 Yesterday: {vote_result}"] if vote_result else []))
    if C.TELEGRAM_BOT_TOKEN and C.TELEGRAM_CHAT_ID:
        tg.send_for_approval(mp4, day, ep["caption"], notes)
    print("Sent Day", day, "for approval:", video_url)


# ---------- post ----------

def post(state):
    p = state["pending"]
    ep = p["episode"]
    results, ig_id = [], None
    if C.IG_ACCESS_TOKEN and C.IG_USER_ID:
        from . import instagram
        try:
            ig_id = instagram.publish_reel(p["video_url"], ep["caption"])
            results.append("✅ Instagram posted")
        except Exception as e:
            results.append(f"❌ Instagram failed: {e}")
    if C.TIKTOK_REFRESH_TOKEN:
        from . import tiktok
        try:
            local = C.OUT / "upload.mp4"
            local.parent.mkdir(parents=True, exist_ok=True)
            with requests.get(p["video_url"], stream=True, timeout=300) as r:
                r.raise_for_status()
                local.write_bytes(r.content)
            _, rotated = tiktok.upload(local, ep["caption"])
            results.append("✅ TikTok posted" if C.TIKTOK_MODE == "direct"
                           else "✅ TikTok: sent to your TikTok inbox — open TikTok and tap Post")
            if rotated:
                results.append(f"⚠️ Update the TIKTOK_REFRESH_TOKEN secret to: {rotated}")
        except Exception as e:
            results.append(f"❌ TikTok failed: {e}")

    if not results:
        results.append("📋 Marked as posted — post it manually (no Instagram/TikTok keys set yet)")
    state["history"].append({"day": p["day"], "summary": ep["vote"]["question"] + " | " + ep["caption"].split("\n")[0],
                             "options": ep["vote"]["options"], "ig_media_id": ig_id,
                             "video_url": p["video_url"], "caption": ep["caption"],
                             "hud_after": ep["hud_after"], "posted_at": now(), "results": results})
    state["hud"] = ep["hud_after"]
    state["last_posted"] = {"day": p["day"], "ig_media_id": ig_id, "options": ep["vote"]["options"]}
    state["day"] = p["day"] + 1
    state["pending"] = None
    save(state)
    tg.send(f"Day {p['day']}:\n" + "\n".join(results))


def poll():
    state = load()
    taps, notes, state["telegram_offset"] = tg.updates(state.get("telegram_offset", 0))
    if notes and state.get("pending"):
        state["pending"].setdefault("notes", []).extend(notes)
    save(state)
    p = state.get("pending")
    for action, day in taps:
        if not p or day != p["day"]:
            continue
        if action == "approve":
            tg.send(f"Posting Day {day}… ⏳")
            post(state)
            return
        if action == "redo":
            feedback = " ".join(p.get("notes", [])) or "Make a different, funnier version."
            tg.send(f"Making a new version of Day {day}… ⏳ (direction: {feedback})")
            generate(feedback=feedback)
            return


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "generate"
    if cmd == "poll" and not (C.TELEGRAM_BOT_TOKEN and C.TELEGRAM_CHAT_ID):
        print("Telegram not set up yet — nothing to poll.")
        return
    try:
        if cmd == "generate":
            state = load()
            if state.get("pending"):
                tg.send(f"⏰ Day {state['pending']['day']} is still waiting for approval.")
                return
            generate()
        elif cmd == "approve":
            state = load()
            if not state.get("pending"):
                raise SystemExit("Nothing pending to approve.")
            post(state)
        elif cmd == "redo":
            state = load()
            if not state.get("pending"):
                raise SystemExit("Nothing pending to redo.")
            generate(feedback=os.environ.get("FEEDBACK") or "Make a different, funnier version.")
        elif cmd == "poll":
            poll()
        elif cmd == "refresh":
            if C.IG_ACCESS_TOKEN:
                from . import instagram
                instagram.refresh_token()
        else:
            raise SystemExit(f"unknown command {cmd}")
    except Exception as e:
        try:
            st = load()
            st["last_error"] = {"command": cmd, "message": str(e)[:500], "at": now()}
            save(st)
        except Exception:
            pass
        tg.send(f"❌ SplitSol autopilot ({cmd}) failed:\n{e}\n\n{traceback.format_exc()[-1500:]}")
        raise


if __name__ == "__main__":
    main()
