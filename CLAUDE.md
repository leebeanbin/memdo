# ⚠️ This is the canonical memdo (iOS) checkout

**Path**: `~/Developer/wlrma/memdo`

This checkout's `HEAD` matches `origin/main` on GitHub exactly. All feature work
(including the AppNoticeCenter refactor and Google Calendar two-way sync, done
2026-09-02) lives here. **Xcode should always open
`apps/ios/Memdo/Memdo.xcodeproj` from this path.**

## Known duplicate checkout — do not use

`~/Documents/Codex/2026-07-30/wlrma/memdo` is a **stale duplicate**, ~22
commits behind `origin/main` (missing bd18/bd26/fe4-fe15/fd7-fd16 and
everything since). It was originally kept as a backup; its only real
uncommitted work (fe4/fe5 dogfooding fixes) turned out to already be merged
upstream and present here. Do not open or build from that path — if Xcode
ever shows unexpected old behavior (missing UI text/buttons after a clean
rebuild), check **File → Open Recent** or right-click a file → **Show in
Finder** to confirm which checkout is actually loaded.
