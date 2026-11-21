# SplitSol Autopilot — setup (one time, ~45 min)

Every day around 4:47 PM (Pakistan time) GitHub makes the next episode of THE TRIP, checks it, and sends it to
your Telegram. You tap ✅ and it posts to Instagram + TikTok. You tap 🔁 and you get a new version. If you type
a note first (like "make Bilal funnier"), the new version follows your note. Everything here is free.

## 1. GitHub repo (5 min)
1. Create a **public** repo, e.g. `splitsol-autopilot`. It has to be public because Instagram downloads the video
   from the repo's Releases, and public repos get unlimited free Actions minutes. Your keys stay private in Secrets.
2. Push this folder to it.
3. Settings → Actions → General → Workflow permissions → **Read and write**.

## 2. Telegram bot (3 min): your notifications + approve button
1. In Telegram, message **@BotFather** → `/newbot` → copy the token → secret `TELEGRAM_BOT_TOKEN`.
2. Send your new bot any message, then open `https://api.telegram.org/bot<TOKEN>/getUpdates`
   and copy `"chat":{"id": ...}` → secret `TELEGRAM_CHAT_ID`.

## 3. Gemini (2 min): writes the episodes + checks the images
aistudio.google.com → Get API key → secret `GEMINI_API_KEY`.

## 4. Images: Pollinations (testing phase, 5 min)
1. Go to **enter.pollinations.ai**, sign in (free) and create an API key. Add it as secret `POLLINATIONS_TOKEN`.
   You need the key: without it you get the low-quality anonymous model.
2. Check which models your credits can use at `https://gen.pollinations.ai/image/models` and set the repo
   variable `POLLINATIONS_MODEL` (start with `flux`, then compare `gptimage` / `kontext` / `seedream`, if listed).
3. Optional, for a consistent character: generate one good image of the main character, upload it anywhere
   public (e.g. a GitHub release in this repo), and put its URL in the repo variable `CHARACTER_REF_URL`.
   Models that accept a reference image (kontext / gptimage) will keep him looking the same.
4. When the free credits run out, you'll get a Telegram error. That's the point to decide between Gemini
   pay-per-image (~$5–6 a month) and the free code-drawn style.

## 5. Instagram (15 min)
1. Instagram app → Settings → Account type → switch @splitsol.app to **Creator** or **Business**.
2. developers.facebook.com → Create app → use case **"Manage messaging & content on Instagram"**
   (Instagram API with Instagram Login).
3. In API setup → add your Instagram account → **Generate token**. Permissions needed:
   `instagram_business_basic`, `instagram_business_content_publish`, `instagram_business_manage_comments`.
4. Secrets: `IG_ACCESS_TOKEN` (the token) and `IG_USER_ID` (shown next to the account in the dashboard).
   While the app is in development mode it can only post to your own account, which is all we need.
   The token lasts 60 days. The workflow refreshes it weekly. If Instagram ever fails, Telegram will tell you.

## 6. TikTok (15 min + waiting for TikTok's review)
1. developers.tiktok.com → Manage apps → Create app → add **Login Kit** + **Content Posting API**.
   Set a redirect URI (e.g. `https://splitsol.co/tiktok`). Copy the client key/secret → secrets
   `TIKTOK_CLIENT_KEY`, `TIKTOK_CLIENT_SECRET`.
2. Add @splitsol as a **sandbox / target user**.
3. On your computer: `pip install requests && python tools/tiktok_auth.py <key> <secret> <redirect_uri>`,
   log in as @splitsol, paste the redirect URL → secret `TIKTOK_REFRESH_TOKEN`.
4. Until TikTok approves your app, videos land in your **TikTok inbox**. Open TikTok, tap the notification,
   then tap Post. After approval, set the repo variable `TIKTOK_MODE` = `direct` and it posts by itself.

## 7. First run
Actions → SplitSol autopilot → Run workflow → command `generate`. Day 1 should reach your Telegram in ~5–10 min.
Tap ✅. It posts within 15 minutes, the next time the workflow checks for your taps.

## Daily life
- 🔔 Telegram: "Day N is ready" → watch → ✅ or 🔁.
- If you don't tap, the next day's run sends a reminder instead of making a new episode.
- To change the story direction: edit `story/bible.md`. To change the look: edit `story/style.md`.
- Voice: change repo variable `TTS_VOICE` (e.g. `en-US-GuyNeural`, `en-GB-RyanNeural`).
- Posting time: edit the first cron line in `.github/workflows/autopilot.yml` (UTC).

## Free-tier limits to know
- Pollinations free credits are for testing. They run out, and then the run sends you a Telegram error.
- The Gemini image fallback only works if your Gemini key has billing enabled. The Gemini *text* model
  (writing + image checks) stays free.
