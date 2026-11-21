# SplitSol Studio (macOS)

Your desktop control room for the daily THE TRIP reels.

- 🔔 Mac notification when today's reel is ready (and when it's posted, or if a run fails)
- 🖼 Swipe through today's carousel, or ▶️ watch today's reel
- ⏭ Skip something you don't want to post
- ✅ **Approve & Post** → GitHub posts to Instagram + TikTok (or marks it posted, so you can post it by hand)
- 🔁 **Redo** with a note ("make Bilal funnier") → a new version arrives in ~10 min
- 📚 History of every posted day, with video, caption and results
- 📋 Copy caption / ⬇️ Download video, for posting by hand

## Build (one time, ~5 min)

```bash
cd studio
flutter create --platforms=macos --project-name splitsol_studio .   # adds the macOS project, keeps our files
rm -rf test                                                          # template test we don't need
flutter pub get
flutter run -d macos          # try it
flutter build macos --release # → build/macos/Build/Products/Release/splitsol_studio.app
```

Drag `splitsol_studio.app` into **Applications**. To have it start with your Mac:
System Settings → General → Login Items → **+** → splitsol_studio.

If `flutter run` complains about the macOS deployment target for a plugin, open
`macos/Podfile` and set `platform :osx, '10.15'`, then run `flutter run -d macos` again.

## Connect it (first launch)

The app asks for:
1. **Repo:** `Ahmad-AppDev/splitsol_autopilot` (already filled in)
2. **GitHub token:** create one at github.com/settings/personal-access-tokens → *Fine-grained token*
   → Repository access: **Only select repositories → splitsol_autopilot**
   → Repository permissions: **Actions**, **Secrets**, **Variables** = Read and write · **Contents** = Read-only
   → Generate → paste it in the app.
3. **AI keys** (same Settings screen): paste your **Gemini** key and **Pollinations** key. The app saves them
   as encrypted GitHub secrets. You never have to open GitHub settings. A ✓ shows next to keys that are saved.
4. **Daily post:** Carousel (default) or Story reel.

Allow notifications when macOS asks.

## How it runs

- Every day at ~4:47 PM GitHub makes the next episode. The app checks every 5 minutes and notifies you.
- Closing the window keeps the app running in the background (click the Dock icon to reopen it).
  Quit with ⌘Q.
- After you approve or redo, the app checks every 20 seconds until the run finishes.
