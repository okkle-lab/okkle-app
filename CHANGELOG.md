# Changelog

All notable changes to the Okkle app are recorded here. Most recent first.

## 2026-06-22

### Dev build scaffolding (EAS) + background GPS config
- Added `eas.json` (development / preview / production profiles) for EAS cloud builds.
- Enabled **background location** in app config: `UIBackgroundModes: location` and the expo-location background flags, plus an "Always" permission request when a trip starts — so tracking continues when the phone is locked. Only active in a real dev build; Expo Go is unaffected.

### Milestones, heatmap, set-aside, trip exit & manual compare
- **Discard a trip**: an × on the live screen and a "Discard this trip" option after ending — you can now bail out without saving (UX fix).
- **Milestone celebrations**: a cheerful popup when your tax saved crosses £50, £100, £250, £500, £1,000…
- **Best times to work** heatmap on the dashboard — your strongest hours by £/hour (or trip count until you log earnings).
- **Set aside for tax** card on the dashboard — your estimated bill so far, so you don't get caught short.
- **Compare with manual input**: in the method comparison you can now enter business miles and vehicle by hand to test last year's figures, not just your tracked data.
- **Onboarding polish**: a friendlier welcome screen with what-you-get highlights.

### Business insights & delight
- **Analyst-grade insights** on the Tax tab: effective net pay per hour, gross pay per hour, earnings per mile, net margin (% kept after tax), and hours tracked — your courier work as a P&L.
- **"Which platform pays best?"** — ranks platforms by £/hour (not just £/mile), so you can see Deliveroo vs Uber Eats on what actually matters.
- **Animated tax-saved counter** on the home hero — the headline number now counts up when you open the app.
- **Receipt viewing** — open any expense in Records to see its attached receipt photo.

### Tax deadline reminders & visual polish
- Added **tax-deadline reminders**: yearly notifications ahead of registering for Self Assessment, the 31 Jan filing & payment, the 31 Jul payment on account, and all four MTD quarterly deadlines. Toggle in Settings.
- **Visual polish** to bring depth and warmth back: soft elevation on cards, and colour returns via tinted icon badges (metric cards, export rows, backup/restore). Flat stays for controls; surfaces now have hierarchy.

### Backup & restore
- Added **Backup & restore** in Settings. Back up your entire record (profile, trips, records, settings) to a JSON file saved in your own iCloud/Files, and restore it on a new or wiped phone.
- Protects against losing records if a phone is lost — HMRC expects records kept 5+ years. Still zero server cost: the file goes to the user's own cloud, not ours.

### MTD quarterly updates & accurate capital allowances
- Added the **Making Tax Digital quarterly updates** section to the Tax tab — the four HMRC quarters with their submission deadlines, per-quarter income/expenses/profit, and the current quarter highlighted. Future-proofs for mandatory MTD ITSA.
- Made **capital allowances HMRC-accurate**: pick your vehicle basis in the compare tool — new electric car (100% first-year allowance), low-emission car ≤50g (18% WDA), other car (6% WDA), or van/motorbike (100% AIA). Flows through to the comparison and Accountant Pack.

### Accountant Pack (PDF)
- One-tap **Accountant Pack**: a single, styled PDF with the cover/assumptions, Self Assessment summary (SA103 figures), income by platform, full HMRC mileage log, expense breakdown, an "items flagged for review" section (likely vehicle running costs), and embedded receipt images.
- Generated on-device with expo-print and shared via the native share sheet (email, AirDrop, Messages) — nothing leaves the phone except what the user sends.

### Clearer method comparison & more accurate tax
- Split the confusing all-in-one method card into a clean summary on the Tax tab plus a dedicated **"Compare methods"** tool (its own focused screen) — progressive disclosure, one job per screen.
- Default everyone to the simplified method; actual-costs is now an opt-in check.
- Added an **"other income"** input so courier profit is taxed at the correct marginal rate when you also have a job (PAYE wages) — a real accuracy fix.

### Tax tab — method comparison & full Self Assessment estimate
- New **Tax** tab (replacing the Export tab — keeps the bar at 5).
- **Killer feature: simplified vs actual-cost comparison** — enter personal miles, running costs and vehicle value, and Okkle shows which method saves more, with a clear winner and the difference. Includes the HMRC method-lock warning (you can't switch back to simplified once you claim actual costs on a vehicle).
- **Self Assessment summary**: turnover, allowable expenses, net profit.
- **Income Tax + Class 4 NIC estimate** with progressive bands (England/Wales/NI and Scotland), effective rate, and a Class 2 note.
- **£1,000 trading allowance** automatically applied when it beats your expenses.
- **Payments on account** forecast (31 Jan / 31 Jul).
- **Insights**: gross earnings per mile, personal allowance remaining, profit after tax.
- **Year-end checklist** with HMRC deadlines and an MTD note.
- Export (SA summary, mileage log, CSV) moved into the Tax tab.

### Mint theme, activity ring, edit/delete & multi-vehicle
- New **mint** colour theme (replacing orange) — fresh and friendly.
- Replaced the speedometer with an **Apple-fitness-style daily goal ring** on the live trip screen — ambient and safe to glance at while riding.
- **Edit and delete** any trip or logged entry — tap it in Records to change details or remove it.
- **Per-vehicle breakdown** in Records (miles, trips and deduction per car/bike/motorbike/van).

### Flat icons, tax-saved hero & speedometer
- Replaced all 3D emoji with flat line icons (Feather + Material Community) — tab bar, settings gear, vehicles, buttons, metric cards.
- Added a **"Tax saved this year"** hero on the dashboard — the headline number, front and centre, so the value is obvious at a glance.
- Added a **live speedometer** (mph) to the trip screen while you ride.
- Cut wordiness: icon-led metric cards, vehicle chips and log tabs.

### Settings, analytics & legitimacy features
- Added a **Settings** screen (gear on the home header): edit name, vehicle, platforms, tax region/band, and reminder preferences; plus an About section explaining the HMRC rates, and a "delete all my data" option.
- **Weekly/monthly logging reminders** via local notifications, with a chosen day.
- **10,000-mile threshold tracker** on the dashboard — shows progress and warns before the car/van rate drops from 45p to 25p.
- **Earnings-per-mile by platform** — ranks Uber Eats vs Deliveroo vs Just Eat by what each pays per mile driven.
- **HMRC mileage log export** — a dated, HMRC-formatted log of every trip.
- **Receipt photo capture** for expenses (camera or library), stored on-device.
- **Quick-start** "Start a trip" button on the home screen.
- **Auto-pause / jitter filter** — stationary GPS drift (e.g. waiting at a restaurant) no longer inflates trip distance.

### Trip flow & one-finger usability
- Redesigned the trip tab into a smooth three-phase flow: **setup → live → quick earnings**.
- Start screen now remembers your last platform and vehicle, so starting a trip is a single tap.
- Added an oversized **Start trip** button and a large **Pause** toggle — easy to hit one-handed on a mounted phone.
- Added a **slide-to-end** control (like Lime/Uber) so cyclists and motorbike riders can't end a trip by accident, even with gloves.
- The screen now **stays awake** automatically while a trip is running.
- After ending, earnings entry is optional with a clear **Skip** — reflecting that couriers are paid weekly, not per trip.

### Theme & consistency
- Warmer, Airbnb-style palette (cream backgrounds, terracotta accent, warm text).
- Introduced a shared type scale so font sizes are consistent across every screen.
- Made platform, vehicle and region chips larger and easier to tap.

### Tax
- Added region-based income tax rates (Scotland vs rest of UK) with optional GPS region detection during onboarding.

### Foundations
- Initial build: GPS trip tracking, manual logging (mileage / earnings / expenses), dashboard, records list, CSV & summary export, on-device SQLite storage.
