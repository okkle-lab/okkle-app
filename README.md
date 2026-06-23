# Okkle — UK Courier Tax Tracker (iOS)

A React Native / Expo iPhone app for UK gig-economy delivery couriers (Uber Eats, Deliveroo, Just Eat, Stuart, Amazon Flex). Tracks mileage via GPS, estimates your HMRC Self Assessment bill in real time, and produces a one-tap Accountant Pack PDF — all on-device, zero server cost.

**Stack:** React Native · Expo SDK 54 · expo-router · expo-sqlite · expo-location · expo-print · expo-sharing · expo-notifications · TypeScript

---

## Features

### Trip tracking
- **Log weekly pay** — dedicated screen for logging weekly platform bank transfers (Uber Eats / Deliveroo / Just Eat all pay weekly, not per trip). Pre-fills the platform from your last selection.
- **Today's summary bar** — shows today's trips / miles / saved / earned on the trip setup screen as soon as you've completed a trip. Day-level view without leaving the tab.
- **One-tap GPS trips** — tap Start, ride, tap End. Distance accumulates via `watchPositionAsync` with a stationary jitter filter (ignores GPS drift when speed < 0.5 m/s or movement < 8 m).
- **Slide-to-end control** — PanResponder slide gesture (like Lime/Uber) prevents accidental trip endings with gloves on.
- **"Waiting…" indicator** — when stationary (speed < 0.5 mph), the activity ring shows "Waiting…" in amber so you know tracking is active and filtering GPS drift — it's not frozen.
- **Background GPS** — `UIBackgroundModes: location` + "Always" permission keeps tracking when the phone locks (active in EAS dev build; Expo Go foreground only).
- **Activity ring** — Apple-fitness-style daily goal ring showing miles driven today vs your target.
- **Pause / resume** — pause mid-trip (e.g. waiting at a restaurant) without losing distance.
- **Discard a trip** — × button on the live screen and a "Discard this trip" option on the summary screen, both with confirmation.
- **Screen stays awake** automatically during a trip (expo-keep-awake).
- **Remembers last platform and vehicle** so starting a trip is one tap.

### Expense categories (courier-specific)
Tap-to-select chips in the Log tab cover the most common allowable courier costs: Charging, Fuel, Maintenance/repairs, Tyres, Waterproof gear, Helmet/safety, Phone mount, Insulated bag, Insurance, Congestion charge, ULEZ charge, Parking, Phone/data, App subscription. Free-text override available.

### Mileage & earnings records
- Log trips manually or from GPS summary.
- Per-trip: platform, vehicle, miles, earnings (optional — pay is weekly, not per trip).
- **Edit or delete** any trip or expense — tap it in Records.
- **Receipt photos** — camera or library; stored on-device (no server).
- **Per-vehicle breakdown** — miles, trips and deduction per car / motorbike / bike / van.

### HMRC tax engine
- **Simplified mileage rates** (HMRC approved):
  - Car / Van: 45p/mi (first 10,000 mi), 25p/mi after
  - Motorbike: 24p/mi flat
  - Bicycle: 20p/mi flat
- **Actual costs comparison** — enter running costs, vehicle value and personal miles; Okkle works out which method saves more tax and shows the difference.
- **HMRC method-lock warning** — once you claim actual costs on a vehicle you cannot switch back; the app surfaces this clearly.
- **Capital allowances** (for actual costs): EV 100% FYA, low-emission car ≤50g 18% WDA, other car 6% WDA, van/motorbike 100% AIA.
- **Progressive income tax** with personal allowance (£12,570) and taper above £100k:
  - England / Wales / NI bands
  - Scottish bands (slightly higher higher rate)
- **Class 4 NIC** — 6% on profits £12,570–£50,270, 2% above.
- **£1,000 trading allowance** — automatically applied when it beats actual expenses.
- **Other income** field for marginal rate accuracy (e.g. PAYE job alongside courier work).
- **Payments on account** forecast (31 Jan / 31 Jul).

### Making Tax Digital (MTD)
- Four quarterly periods displayed with per-quarter income, expenses, profit and submission deadline:
  - Q1 6 Apr–5 Jul → deadline 7 Aug
  - Q2 6 Jul–5 Oct → deadline 7 Nov
  - Q3 6 Oct–5 Jan → deadline 7 Feb
  - Q4 6 Jan–5 Apr → deadline 7 May
- Current quarter highlighted. Ready for when MTD ITSA becomes mandatory.

### Dashboard period switcher
- Toggle the home dashboard between **Today · Week · Month · Year** — take-home, miles, earnings and hours re-scope instantly.
- **Per-platform breakdown** for the selected period with a winner badge, so multi-platform couriers can see which app paid best that day/week/month/year.
- Week runs **Monday–Sunday** to match Uber Eats / Deliveroo / Just Eat weekly pay cycles. Year = UK tax year (6 Apr–5 Apr).

### Insights — where & when you earn most
- Trips capture an on-device GPS breadcrumb and a reverse-geocoded **area name**.
- **Hotspots heatmap** drawn on-device (works in Expo Go; real Google Maps can drop in on a dev build), a ranked **top earning / busiest areas** list, and a **best-hours** chart — all in a dedicated Insights screen (also previewed on Home).
- **Time-of-day filter** (All / Morning / Lunch / Afternoon / Dinner / Late) — compare where you earn most at each part of the day.

### Business insights
- Net pay per hour, gross pay per hour, earnings per mile, net margin (% kept after tax), hours tracked.
- Platform ranking by £/hour (not just total earnings).
- **"Best times to work"** heatmap — your strongest hours by average £/hour.
- **10,000-mile threshold tracker** — warns before the car/van rate drops from 45p to 25p.
- **Set aside for tax** card — your estimated bill so far so you're never caught short.

### Accountant Pack PDF
- One-tap PDF via expo-print, shared via native share sheet (email, AirDrop, Messages).
- Includes: cover + assumptions, SA103 summary, income by platform, full HMRC mileage log, expense breakdown, flagged review items, embedded receipt images (base64).
- Nothing leaves the phone except what the user sends.

### Gamification
- **Activity streak** — counts consecutive days you log a trip or entry; holds if you haven't logged yet today.
- **~99 3D-style medals** — a glossy disc with ribbon and a playful emoji centre. Each **category has its own colour** (Trips blue, Miles teal, Tax saved green, Earnings gold, Streaks fire, Hours indigo, Active days pink, Big days red, Long trips bronze, Platforms violet, Special mint), and tier adds the flair (gold gets a starburst + sparkles).
- **Streak header chip** on the dashboard (🔥 N) keeps the daily-return hook above the fold; tap it (or the "Your progress" card) to open the Medals screen.
- **Medals screen** — an Apple-Fitness-style grid grouped by category, with an earned/total ring, locked vs unlocked medals, per-medal progress and a tap-through detail card.
- **Gamified Trip tab** — the setup screen shows a daily-goal ring, streak pill and a "next medal" progress row.
- **XP & levels** — earn XP for activity (trips, active days, medals, streak, miles, expenses — never income). A Level + XP bar shows on the dashboard.
- **Weekly challenges** — four refreshing challenges (track 5 trips, cover 50 miles, keep a 5-day streak, log your weekly pay), each worth XP.
- **"Achievement unlocked" celebration** — a popup fires whenever you earn a new medal.

### Export filenames
All exports save with a consistent, readable name: `Okkle_<What>_TaxYear-2025-26_<date>.<ext>` — e.g. `Okkle_HMRC-Mileage-Log_TaxYear-2025-26_2026-06-23.csv`, `Okkle_Accountant-Pack_TaxYear-2025-26_2026-06-23.pdf`.

### Notifications
- **Playful, Duolingo-style copy** — rotating weekly reminders plus a daily streak-keeper nudge ("Your streak misses you 🥺") to keep your activity streak alive.
- Weekly/monthly logging reminders (configurable day).
- Yearly tax deadline reminders: Self Assessment registration, 31 Jan filing + payment, 31 Jul payment on account, all four MTD quarterly deadlines.

### Backup & restore
- Dumps entire record (profile, trips, records, settings) to a JSON file in iCloud/Files.
- Restore on a new or wiped phone. Zero server cost — file goes to the user's own cloud.

### Settings & onboarding
- Multi-step onboarding: name → vehicle → platforms → tax region (with GPS auto-detect).
- Edit everything in Settings: name, vehicle, platforms, tax region, income band, reminder preferences.
- Delete all data option.

---

## Project structure

```
app/
  (tabs)/
    index.tsx       — Home dashboard (hero, heatmap, set-aside, milestones)
    trip.tsx        — Trip flow: setup → live → summary
    records.tsx     — Trip & expense log with vehicle breakdown
    tax.tsx         — Tax tab: MTD quarters, SA estimate, insights, Accountant Pack
  compare.tsx       — Method comparison modal (simplified vs actual costs)
  edit.tsx          — Edit / delete individual trip or record
  onboarding.tsx    — Multi-step onboarding
  settings.tsx      — Settings modal

src/
  db/
    index.ts        — SQLite layer (initDb, all queries, backup/restore)
    tax.ts          — HMRC rates, vehicles, platforms, regions
    taxcalc.ts      — Full UK tax engine (income tax, NIC, compareMethods, taxPosition)
  hooks/
    useTrip.ts      — GPS trip tracking hook (start/pause/resume/end)
  components/
    Card.tsx        — Soft-shadow card surface
    Chip.tsx        — Selectable chip (md/lg)
    MetricCard.tsx  — Icon + value metric card
    PrimaryButton.tsx — Button variants (primary/danger/ghost/warning)
    SlideToConfirm.tsx — PanResponder slide-to-end gesture
    ProgressRing.tsx  — SVG activity ring (react-native-svg)
    Icon.tsx / VehicleIcon.tsx — Flat Feather + MaterialCommunity icons
    CountUp.tsx     — Animated count-up (requestAnimationFrame, ease-out cubic)
    IconBadge.tsx   — Tinted circle icon badge (mint/green/amber/red/neutral)
  theme/
    index.ts        — Mint colour palette + shared type scale
  accountantPack.ts — HTML→PDF generation
  backup.ts         — Backup / restore logic
  notifications.ts  — Reminders + tax deadline notifications
```

---

## Colour palette (Mint)

| Token | Hex | Use |
|-------|-----|-----|
| `brand` | `#1FB89A` | Primary actions, hero numbers |
| `brandDeep` | `#0E8E78` | Pressed states, dark text on mint |
| `brandLight` | `#E2F6F1` | Tinted backgrounds |
| `bg` | `#FBF9F6` | Warm screen background |
| `bgCard` | `#FFFFFF` | Card surfaces |
| `green` | `#2FA36B` | Positive / savings |
| `amber` | `#E0961F` | Warnings / set-aside |
| `red` | `#E2604A` | Danger / loss |

---

## Run locally (Expo Go)

**Easiest — double-click the launcher:** in Finder, open `launch.command` (first time: right-click → Open). It detects your WiFi IP, opens a QR page, and starts the server. Scan the QR with the iPhone Camera or Expo Go.

**Or manually:**

```bash
cd ~/Documents/okkle
npx expo start
```

Scan the QR with **Expo Go** on iPhone (same WiFi). Background GPS is not active in Expo Go — foreground tracking only.

## EAS dev build (background GPS + full features)

```bash
npm install -g eas-cli
eas login
eas device:create          # register your iPhone (one-time)
eas build --profile development --platform ios
```

Install via the QR / link EAS provides, then:

```bash
npx expo start --dev-client
```

Open the installed **Okkle** app (not Expo Go) and scan.

EAS project ID: `8d4fc276-a589-4340-bcde-0263c4a1b51d`  
Bundle identifier: `uk.okkle.app`

---

## Planned / future

- **Accounting auto-sync (FreeAgent / Xero / QuickBooks)** — CSV export to FreeAgent ships today (no backend). Live API push is a paid Phase-2 feature needing a backend (OAuth2 + per-provider developer registration). FreeAgent is the priority (best courier fit).
- **AI receipt scanning & categorization** — planned as a **subscription** (~£3.49/mo) because each scan has a recurring inference cost; needs a Claude API proxy server.
- **HMRC MTD API submission** — quarterly data is computed and ready; the submission pipe needs a backend server (OAuth2, fraud-prevention headers, client secret proxy).
- **Open Banking** (TrueLayer / Plaid) — auto-import courier deposits from bank feed (requires subscription backend).
- **AI receipt OCR** — Claude vision for receipt scanning (requires API key proxy server).
- **Live Activities / Lock Screen widget** — real-time trip display on the lock screen (needs dev build + entitlement).
- **DVLA vehicle lookup** — auto-fill vehicle type and CO2 band for actual-cost comparison.
- **Monetisation**: free core + £29 one-off Tax Year Pack + £3.49/mo subscription for bank sync + unlimited AI scanning.

---

## Legal note

Okkle is a mileage and record-keeping tool, not tax advice. All estimates are based on published HMRC rates. Your accountant confirms final figures. Records should be kept for 5+ years as HMRC may request them.
