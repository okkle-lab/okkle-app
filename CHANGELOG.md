# Changelog

All notable changes to the Okkle app are recorded here. Most recent first.

## 2026-06-22

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
