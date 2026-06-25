# Release / build notes

Read this before cutting a dev build, EAS build, or TestFlight submit.

## Branches
- **`master`** — the real app, **Expo SDK 56** (RN 0.85). Source of truth. Build & ship from here.
- **`sdk54-expo-go`** — a downgraded **SDK 54** copy, *only* so the app can run in
  the public Expo Go on older phones. It uses a classic JS tab bar and pruned
  plugins. **Do not merge it into master** (different SDK) and don't release from it.

## 🚑 If the iOS build FAILS on a native module (fast fallback)
Both modules below are **optional at runtime** — the app runs fine without them
(you just lose auto-trip detection / receipt OCR). So if the native build errors
in `modules/okkle-vision` or `modules/okkle-motion`, the quickest way to still get
a testable build is to **temporarily remove the offending module folder** and
rebuild:
```
rm -rf modules/okkle-vision    # (or modules/okkle-motion)
```
Everything else (live trip, slider, platforms, receipt-first UI, lock-screen
notification, tour) still works. Re-add it once the Swift/scaffold is sorted.

## ⚠️ Needs validation on the first dev/EAS build
Two local Swift modules have **not been compiled yet**. Both are wired optionally
(`requireOptionalNativeModule`) so they can't break the JS app at runtime — but a
malformed module/podspec **can fail a native build**. Validate both on the first
`npx expo prebuild` / EAS build:
- **`modules/okkle-vision`** — Apple Vision on-device receipt OCR
  (`VNRecognizeTextRequest`). Used by the Log expense flow to pre-fill the amount
  from a receipt photo (`src/receiptParse.ts` parses the text). No extra permission.
- **`modules/okkle-motion`** — `CMMotionActivityManager` for accurate
  driving/cycling detection. On the first build:
  1. Confirm it autolinks and compiles.
  2. If autolinking is fussy, regenerate the scaffold with
     `npx create-expo-module@latest --local okkle-motion` and port the Swift in
     `ios/OkkleMotionModule.swift` across.
  3. It adds a **Motion & Fitness** permission (`NSMotionUsageDescription`, already
     in `app.json`).

## Features that require a dev build / TestFlight (do NOT work in Expo Go)
- **Auto-detect trips** (Feature 1): background location + Core Motion + "Always"
  permission. Expo Go can't do background location wake-ups.
- **`okkle://` deep links**: the screenshot→earnings confirm screen
  (`okkle://log-earnings?...`) and the in-app "Preview confirm card" button. Custom
  URL schemes need a real install.
- Test these on a dev build or TestFlight, not Expo Go.

## Pending content (intentional placeholders)
- **`app/settings-earnings-shortcut.tsx` → `SHORTCUT_ICLOUD_URL`** is empty, so the
  earnings shortcut shows a **"coming soon"** state. Paste the iCloud share link of
  the Okkle "Log earnings" shortcut (built per `docs/ios-shortcut-earnings.md`) to
  switch it to a live one-tap download. No other code change needed.

## EAS / TestFlight
- Project: `uk.okkle.app`, EAS project owned by **henryhikaru93** (`b6fffded-…`).
  Building/submitting requires membership of that Expo account **and** the Apple
  Developer account ($99/yr) for the app.
- Commands (from `master`):
  ```
  eas build  --platform ios --profile production
  eas submit --platform ios --profile production --latest
  ```

## Design docs
- `docs/ios-motion-capture.md` — movement-based trip detection (v1 speed fallback + v2 Core Motion).
- `docs/ios-shortcut-earnings.md` — the screenshot→earnings Shortcut + deep-link contract.
