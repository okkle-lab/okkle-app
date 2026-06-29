# Release / build notes

Read this before cutting a dev build, EAS build, or TestFlight submit.

## Branches
- **`master`** — the real app, **Expo SDK 56** (RN 0.85). Source of truth. Build & ship from here.
- **`sdk54-expo-go`** — a downgraded **SDK 54** copy, *only* so the app can run in
  the public Expo Go on older phones. It uses a classic JS tab bar and pruned
  plugins. **Do not merge it into master** (different SDK) and don't release from it.

## Native module validation
Two local Swift modules are included in production builds. They are wired
optionally (`requireOptionalNativeModule`) so the JS app can degrade gracefully at
runtime, but a malformed module or podspec can still fail a native build.

Validation status on `master`:
- `npx expo prebuild --platform ios --no-install` succeeded on 2026-06-29.
- `pod install` autolinked both `OkkleVision` and `OkkleMotion` on 2026-06-29.
- Xcode Debug and Release iOS Simulator builds succeeded on 2026-06-29.

- **`modules/okkle-vision`** — Apple Vision on-device receipt OCR
  (`VNRecognizeTextRequest`). Used by the Log expense flow to pre-fill the amount
  from a receipt photo (`src/receiptParse.ts` parses the text). No extra permission.
- **`modules/okkle-motion`** — `CMMotionActivityManager` for accurate
  driving/cycling detection. It adds a **Motion & Fitness** permission
  (`NSMotionUsageDescription`, already in `app.json`).

## Features that require a dev build / TestFlight (do NOT work in Expo Go)
- **Auto-detect trips** (Feature 1): background location + Core Motion + "Always"
  permission. Expo Go can't do background location wake-ups.
- **`okkle://` deep links**: the screenshot→earnings confirm screen
  (`okkle://log-earnings?...`) and the in-app "Preview confirm card" button. Custom
  URL schemes need a real install.
- Test these on a dev build or TestFlight, not Expo Go.

## Pending content (intentional placeholders)
- **`app/settings-earnings-shortcut.tsx` → `SHORTCUT_ICLOUD_URL`** is empty, so the
  earnings shortcut route is not linked from Settings in this release. Paste the
  iCloud share link of the Okkle "Log earnings" shortcut (built per
  `docs/ios-shortcut-earnings.md`) before exposing that route in-app.

## EAS / TestFlight
- EAS project: `b6fffded-a938-4183-9753-f5bccf749033`, owned by
  **henryhikaru93**.
- iOS bundle identifier: `okklelab.app`; Android package: `uk.okkle.app`.
  Building/submitting requires membership of that Expo account **and** the Apple
  Developer account ($99/yr) for the app.
- Before cutting a release, run:
  ```
  npm run check
  npm run audit:prod
  ```
  `audit:prod` should be clean. A targeted `uuid@11.1.1` override is kept in
  `package.json` for Expo's `xcode` tooling path; remove it only after upstream
  Expo dependencies no longer need it.
- Commands (from `master`):
  ```
  eas build  --platform ios --profile production
  eas submit --platform ios --profile production --latest
  ```

## Design docs
- `docs/ios-motion-capture.md` — movement-based trip detection (v1 speed fallback + v2 Core Motion).
- `docs/ios-shortcut-earnings.md` — the screenshot→earnings Shortcut + deep-link contract.
