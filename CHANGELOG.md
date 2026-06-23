# Changelog

All notable changes to the Okkle app are recorded here. Most recent first.

## 2026-06-23 (spotlight app tour)

### First-run coachmarks
- A **spotlight tour** runs once after onboarding: it dims the screen and highlights real elements one at a time — **Start a trip → Level/XP → your streak → "there's more below"** (Insights + tabs) — so new users learn exactly where to tap.
- Added **Settings → Help → "Replay the app tour"** to run it again anytime.

## 2026-06-23 (onboarding redesign)

### Onboarding that sells the whole app
- Reframed the welcome from "mileage tracking" to the full value: **track trips, see where you earn most, stay HMRC-ready, and play** (streaks, medals, levels) — with confident, professional copy.
- Clearer per-step purpose (vehicle sets your mileage rate; platforms → we show which pays best/hour; region sharpens take-home).
- New **"You're set" final step** that tells users exactly what to do first (start a trip → log weekly pay → check Insights) and sets the gamification expectation, with a CTA that jumps straight into a first trip.

## 2026-06-23 (UX pass: clarity & flow)

### Clearer & more intentional
- **Log page** now leads with **Expense → Earnings → Mileage** (manual mileage last, with a GPS nudge) so GPS tracking is the encouraged way to record miles.
- **Period switcher** shows the **actual date range** underneath (e.g. "Mon 17 – Sun 23 Jun") instead of a vague repeated label.
- **Trip "Today's goal"** is bigger and explained — it's your daily mileage goal that keeps your streak alive.
- **XP & levels now mean something**: named ranks (Rookie → Regular → Pro → Veteran → Legend) and a one-line explainer of how you earn XP.
- **Tax tab spacing** evened out between every section.
- **Accountant Pack** document renamed to *"Self Assessment — Income & Expenses Summary"* so accountants understand it (the app button stays "Accountant Pack").

## 2026-06-23 (best-spot tip, Home/Tax split, spacing)

### Best zone × best time
- A headline tip on Insights tells you your most lucrative combination — e.g. **"You earn most around Wimbledon on evenings · £14.20/h"** — and a short version shows on the Home insights preview.

### Clearer Home vs Tax
- **Home** now owns your work & the game (earnings, gamification, hotspots, recent trips). **Tax** owns what you owe: **"Set aside for tax"** moved off Home and is now the headline at the top of the Tax tab.
- Insights lives with Home; the Tax tab has one clear **"Send to your accountant" → Export** action. No more overlap between the two screens.

### Even spacing
- Fixed uneven gaps between Home cards (a double-margin was creating a 40px gap in one place and almost none in another) — the rhythm is now consistent.

## 2026-06-23 (colourful medals + time-based insights)

### Medals get their own colours
- Each medal category now has a **distinct colour** (Trips blue, Miles teal, Tax saved green, Earnings gold, Streaks fire-orange, Hours indigo, Active days pink, Big days red, Long trips bronze, Platforms violet, Special mint) — so they no longer all look the same. Tier still adds the "fancy" (gold gets a starburst + sparkles).

### Insights by time of day
- A horizontal **time-of-day filter** (All / Morning / Lunch / Afternoon / Dinner / Late) on the Insights screen — scroll and tap to compare where your hotspots and top areas are at each part of the day.

### Polish
- Redesigned the weekly-challenge rows (no more wrapping "+100 XP"), bigger Home greeting, and a hotspots heatmap preview promoted onto the Home screen.

## 2026-06-23 (location heatmap + subscreens)

### Where you earn most
- Trips now capture an on-device GPS breadcrumb and are tagged with a friendly **area name** (reverse-geocoded at save time).
- New **Insights** screen: a **hotspots heatmap** (your busiest areas, drawn on-device — works in Expo Go, no map account needed), a ranked **top earning / busiest areas** list, and your **best hours**.

### Calmer Tax tab
- Moved all exports into a dedicated **Export & share** screen (Accountant Pack, FreeAgent, mileage log, CSV).
- The Tax tab now ends with a tidy **Explore** card linking to Insights and Export; Home gained a **"Where you earn most"** entry.

## 2026-06-23 (review pass: medals, home order, tax honesty)

### Fancier medals
- Medals now get visibly cooler as they get harder: bronze is a clean disc, silver gets a studded rim, **gold gets a 16-point starburst with sparkles**, and special tiers get a 12-point burst, sparkles and a distinct purple ribbon — Apple-Health style.

### Home reorder (play-first)
- Reordered so the app feels like a game, not a tax chore: hero → Start a trip → **Level & weekly challenges** → your numbers → **Set aside for tax moved lower** (off the top so it isn't an anxiety trigger) → medal collection.

### Gamification correctness
- Weekly-challenge XP is now **real** — finishing a challenge credits XP once per week (previously the "+XP" was cosmetic).

### Tax honesty
- The app previously showed a 2026/27 position using 2025/26 rates labelled as such. It now clearly states figures are **estimated using 2025/26 HMRC rates (allowances frozen to 2027/28)** in both the Tax tab and the Accountant Pack.

## 2026-06-23 (XP, levels & weekly challenges)

### Levels and challenges
- **XP & levels** — earn XP for activity (trips, active days, medals, streak, miles, expenses — never income, so it stays fair and private). A Level + XP bar appears on the dashboard.
- **Weekly challenges** — four challenges that refresh each week (track 5 trips, cover 50 miles, keep a 5-day streak, log your weekly pay), each worth XP with progress bars.
- Local-first groundwork for future anonymous XP/streak leagues.

## 2026-06-23 (~100 medals)

### Way more medals
- Expanded from 26 to **~99 medals** across 11 categories: Trips, Miles, Tax saved, Earnings, Streaks, Hours, Active days, Big days (best single day), Long trips, Platforms and Special habits (night owl, early bird, weekend warrior, paper trail, safe keeper, all-rounder…).
- All driven by a single-pass stats gatherer, so the collection stays fast.

## 2026-06-23 (3D medals + gamified Trip tab)

### Real medals
- Medals are now **3D-style** — a glossy metallic disc with a ribbon and a playful emoji centre (bronze / silver / gold / special finishes), instead of flat line icons.

### Placement
- Your **streak moved to a header chip** (🔥 7) on the dashboard, so the daily-return hook is glanceable above the fold; the medal collection stays a browse-y card lower down. Both tap through to the Medals screen.

### Gamified Trip tab
- The trip setup screen now has a **goal card**: a daily-goal ring (today's miles vs target), a streak pill, and a "next medal" progress row that taps through to your medals — so the Trip tab no longer feels bland.

## 2026-06-23 (medals + number overflow fix)

### Medals (Apple-Fitness-style)
- Expanded from 10 to **26 medals** across Trips, Miles, Tax saved, Earnings, Streaks and Special habits (night owl, early bird, multi-platform, receipt keeper…), each a bronze / silver / gold / special tier.
- New **Medals screen** — an Apple-Fitness-style grid grouped by category, with an earned/total ring, locked vs unlocked medals, per-medal progress, and a tap-through detail card.
- The dashboard "Your progress" card now links straight to it ("See all medals") and previews the medals you're closest to earning.

### Number fix
- Fixed large figures running off-screen: mileage values now use thousands separators (e.g. "6,592,261 mi") and the mileage-method amount shrinks to fit instead of overflowing the card.

## 2026-06-23 (fun notifications, warmer UI, GPS basis)

### Notifications with personality
- Weekly reminders now use rotating, playful copy instead of one robotic line.
- New **daily streak-keeper** nudge (Duolingo-style) — a cheeky 7:30pm reminder ("Your streak misses you 🥺") that helps you keep your activity streak alive. Varies each time so it never gets stale.

### Warmer UI
- Added small mint **icons to section headers** across Home, Tax, Records and Trip, so the screens feel friendlier and less clinical.

### GPS mileage basis
- The mileage-log export and Accountant Pack now state that distances are **GPS-measured** — a contemporaneous record HMRC accepts — so the basis is explicit to your accountant or in any HMRC enquiry.

## 2026-06-23 (gamification + clear export filenames)

### Gamification
- **Activity streak** — a daily streak that counts consecutive days you log a trip or entry, shown on the dashboard (and holds if you haven't logged yet today).
- **Achievement badges** — 10 collectible badges across trips, miles, tax saved, streaks and exporting your first Accountant Pack. The dashboard shows your unlocked/total count and a badge collection; locked badges show a progress bar.
- **"Achievement unlocked" celebration** — a single, richer popup replaces the old tax-saved-only milestone, and fires for any newly earned badge.

### Clear export filenames
- All exports now save with a consistent, readable name: `Okkle_<What>_TaxYear-2025-26_<date>.<ext>` (e.g. `Okkle_HMRC-Mileage-Log_TaxYear-2025-26_2026-06-23.csv`). Previously the share title wasn't a real filename, so files landed with confusing names.
- Covers the Self Assessment summary, mileage log, FreeAgent import, all-data CSV, the Accountant Pack PDF, and backups.

## 2026-06-23 (FreeAgent export, audit-grade pack, day-bar fix)

### Accounting & audit
- **FreeAgent CSV export** — export earnings and expenses in FreeAgent's bank-statement import format (Date / Amount / Description), ready to upload. The free-tier hook ahead of paid auto-sync.
- **Audit-grade Accountant Pack** — reviewed as an external auditor would: explicit accounting period and client reference on the cover, a "Basis of preparation" section with record-count completeness totals, SA103S box-number mapping (boxes 9 / 20 / 31), footing totals on every table, consistent GBP formatting, UK dates, and clean page breaks.

### Formatting
- **Day-bar fix** — today's strip on the Trip screen now shows whole pounds and auto-shrinks so large figures (e.g. £6,464) no longer wrap and look broken.

## 2026-06-23 (number & alignment polish)

### Cleaner numbers and layout
- **Consistent number formatting everywhere** — per-hour, per-mile, hours and percentages now render the same way on every screen (previously per-hour appeared three different ways). New shared formatters: `fmtPerHour`, `fmtPerMile`, `fmtHours`, `fmtPct`.
- **Tabular figures** — all numbers now use monospaced digits so they line up in even columns and stop jittering as values change.
- **Metric cards** — large currency values shrink to fit instead of wrapping or overflowing, and paired cards now stay equal height and aligned.
- **Tax tab rows** — labels and right-aligned values are properly columned.
- Negative amounts now format cleanly (e.g. `-£12.34`).

### Expo Go launcher
- Added `launch.command` — double-click it in Finder to auto-detect your WiFi IP, pop up a branded QR page with scan instructions, and start the dev server. Makes it one click for anyone to open the app in Expo Go.

## 2026-06-22 (period switcher)

### Daily / weekly / monthly / yearly views
- **Period switcher on the dashboard** — tap Today, Week, Month or Year to re-scope your take-home, miles, earnings and hours. Previously the dashboard was locked to "this week" and there was no monthly view at all.
- **Monthly summaries** — full calendar-month figures for budgeting, closing the biggest gap found in testing.
- **Per-platform breakdown for the selected period** — see which platform (Uber Eats / Deliveroo / Just Eat) earned most *this month* (or day/week/year), with a winner badge. Replaces the old all-time-only "earnings per mile" card.
- **Week now runs Monday–Sunday** to match Uber Eats / Deliveroo / Just Eat weekly pay cycles (was Sunday-based).

## 2026-06-22 (courier UX fixes)

### Real-world courier improvements
- **Log weekly pay** — dedicated flow on the Trip screen for logging Uber Eats / Deliveroo / Just Eat weekly bank transfers. Previously there was no clean way to record weekly pay separate from GPS trips.
- **Today's summary bar** — after the first trip of the day, a "trips / miles / saved / earned" bar appears on the trip setup screen so you can see your shift at a glance without opening the dashboard.
- **"Waiting…" ring indicator** — when you're stationary (e.g. waiting outside a restaurant), the activity ring chip now shows "Waiting…" in amber instead of the goal percentage, so you know tracking is active and filtering GPS drift correctly.
- **E-bike / Bicycle label** — renamed "Bicycle" to "E-bike / Bicycle" so e-bike couriers know the 20p/mi HMRC rate applies to them too.
- **Courier expense categories** — the Log tab's expense screen now shows tap-to-select chips for the most common courier costs: Charging, Fuel, Maintenance/repairs, Tyres, Waterproof gear, Helmet/safety, Phone mount, Insulated bag, Insurance, Congestion charge, ULEZ charge, Parking, Phone/data, App subscription.

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
