# Movement-based trip detection (Feature 1)

Goal: when the user starts driving (or cycling), Okkle suggests **"On the move —
track this trip?"** so they never lose tax-free miles by forgetting to press
Start. It only ever *suggests* — the user confirms by tapping Start. Nothing is
recorded automatically.

This is a **dev-build / TestFlight feature** — it relies on "Always" location and
background execution, which **do not work in Expo Go**.

## What ships now (v1 — Expo-only, no custom native module)

Implemented in `src/autoTrip.ts`, wired through `app/_layout.tsx`,
`app/settings-auto-trip.tsx`, and the trip hook:

- **`expo-location` background updates** (`startLocationUpdatesAsync`) with a
  `expo-task-manager` task (`okkle-auto-trip-detect`). Low accuracy + `Balanced`,
  `pausesUpdatesAutomatically`, `activityType: AutomotiveNavigation`.
- **Speed heuristic**: when a background location reports speed ≥ ~15 mph and no
  trip is active, we schedule a local **suggestion notification**.
- **Cooldown + guards**: max one prompt per 30 min; suppressed while a trip is
  already running (`trip_active` kv flag set by the trip hook); only when the
  feature toggle is on (`auto_trip` kv flag).
- **Tap → confirm**: tapping the notification opens the Trip tab; the user hits
  Start (the GPS trail + the existing save flow take over). Mileage/deduction use
  the existing on-device calc — configurable per-tax-year rate, the 10,000-mile
  car/van threshold (lower band above it), separate bike rate, and the user's
  **actual** tax band (never a default 40%; below the personal allowance can mean
  no saving). All flagged as estimates.
- **Permission UX**: `settings-auto-trip.tsx` explains *why* "Always" is needed in
  reassuring language before requesting it, and routes to iOS Settings if the user
  needs to upgrade the permission.

### Honest limitations of v1
- Speed-from-GPS is a proxy for "driving", not true activity recognition — a bus,
  train, or passenger ride can trigger a nudge, and a very short hop may be missed.
  That's acceptable because it's only a *suggestion*.
- iOS controls when a backgrounded/killed app is woken; prompts aren't instant.

## The native upgrade (v2 — proper activity recognition)

For real automotive/cycling classification, add a small native module (config
plugin) wrapping:

- **`CMMotionActivityManager`** (Core Motion) — `startActivityUpdates` returns
  `CMMotionActivity` with `automotive`, `cycling`, `walking`, `running`,
  `stationary` + a confidence. This is the correct, low-power way to know the user
  is *driving* vs just moving fast. Requires **Motion & Fitness** permission
  (`NSMotionUsageDescription`).
- **Significant-location-change** (`CLLocationManager.startMonitoringSignificant
  LocationChanges`) — the canonical way to wake a killed app on ~500 m movement at
  near-zero battery cost. Combine with **region monitoring** for known hotspots.
- **`CLLocationManager`** with `allowsBackgroundLocationUpdates = true` and
  `activityType = .automotiveNavigation` for the precise trail *after* the user
  confirms a trip.

Flow: significant-change wakes the app → check `CMMotionActivity` → if `automotive`
/`cycling` with decent confidence and no active trip → fire the suggestion. This is
more accurate and lighter than the speed heuristic, at the cost of native code.

## Permissions

- **When In Use** → enough to track a trip the user starts manually.
- **Always** → required for background detection (the whole point of Feature 1).
  Justify it clearly and let the user opt in; expect extra App Store review notes.
- **Motion & Fitness** → only for the v2 Core Motion upgrade.

`app.json` already sets `UIBackgroundModes: ["location"]`, the location plugin's
`isIosBackgroundLocationEnabled`, and the Always/When-In-Use usage strings.

## Battery

- Use **significant-location-change** (v2) or **low-accuracy + `pausesUpdates
  Automatically`** (v1) for the always-on watch — both are designed for all-day use.
- Only switch to **full-accuracy GPS** once a trip is confirmed, and stop it the
  moment the trip ends.
- Core Motion (v2) is extremely low power — it's the recommended primary signal,
  with location used sparingly.

## Privacy

Everything is on-device. Location is used locally to estimate mileage; nothing is
uploaded. The user can turn detection off at any time in Settings → Auto-detect
trips.
