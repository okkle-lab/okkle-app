# Changelog

All notable changes to the Okkle app are recorded here. Most recent first.

## 1.0 (42) - 2026-06-28 (Launch release)

- **Launch version.** App/package version bumped to 1.0 for release.
- **Bug reports go to Okkle Lab.** In-app problem reports now compose to `admin@okklelab.com`, with the old support inbox removed from the fallback messages.
- **Removed the standalone Diagnostics settings screen** from the launch UI while keeping lightweight internal error logging available for explicit bug reports and future automated diagnostics work.
- **Fixed Insights crash on open.** The hotspot map no longer renders the native `AIRMapHeatmap` view, which is unavailable in some iOS map-provider builds; it now uses an app-owned SVG density map.

## 0.3 (42) - 2026-06-28 (Calendar fix + live-map alignment)

- **Fixed "Add to calendar".** The calendar permission was never actually being requested — `expo-calendar`'s default permission method is deprecated in this SDK and throws, so the prompt never showed and no Calendars toggle appeared in Settings. Switched to the supported legacy API; tapping Add now requests access properly. (Diagnosed via the new Diagnostics log.)
- **Live trip screen — map alignment.** The route map was bleeding to the screen edges (out of line with the stats) and the "earned back" chip below it was getting clipped. The map now aligns with the rest of the content, it's slightly shorter, and nothing is cut off.

## 0.3 (41) - 2026-06-28 (In-app diagnostics)

- **New Settings → Diagnostics screen.** When anything breaks, it captures what happened (crashes, calendar failures, and any fatal JS error) into an on-device log — with app version/build, OS, context and stack — and lets you send it all in one tap with **Share diagnostics**. No backend; nothing leaves the phone until you share it. This replaces having to reproduce a bug on cue and screenshot a fleeting alert.

## 0.3 (40) - 2026-06-28 (Log flow fixes)

- **Fixed the blank/white Log screen.** A step's content opacity was tied to its slide-in animation; if that animation was interrupted (by the keyboard appearing mid-transition) it could stick at 0 and render the whole step invisible until you left and came back. Content is now always visible.
- **You can reach "Continue" with the keyboard up.** The Back/Continue footer now floats just above the keyboard, so it's no longer stranded behind the number pad.
- **Trip live screen spacing.** Added breathing room between the "earned back" chip and the four stats.

## 0.3 (39) - 2026-06-28 (Diagnostics for the crash + calendar issue)

- **The "Something went wrong" screen now shows the actual error** (message + stack) and saves it, so a crash on a real device can be screenshotted and fixed — release builds otherwise hide the cause.
- **Calendar "Add" now reports why it failed** — the alert includes a short `[diag: …]` reason (permission status / exception / no writable calendar) so we can see why the Calendars toggle isn't appearing in Settings. Temporary diagnostic.

## 0.3 (38) - 2026-06-28 (Live tracking notification)

- **The tracking notification now shows live miles.** While a trip records, the lock-screen/notification updates (quietly, about once a minute) with your distance and tax back so far — a clear sign Okkle is still working in the background. (A full Dynamic Island Live Activity needs a native widget extension — noted as a follow-up.)

## 0.3 (37) - 2026-06-28 (Background trip tracking + onboarding cleanup)

- **Trips now keep tracking in the background.** Live trip state is saved to the database and driven by a registered background location task, so a trip no longer lives only in memory. This fixes three things at once:
  - **Locked-screen tracking.** The whole route is recorded while the phone is locked — not just the start and end with a straight line between.
  - **You can leave the tracking screen.** The live screen no longer takes over the whole app — switch tabs (or tap the new minimise control) and the trip keeps recording; returning drops you back into it.
  - **Trips survive the app closing.** Leave the app, get killed by iOS, or reopen later — an in-progress trip is restored and carries on instead of vanishing.
- **Only one location stream at a time.** Starting a trip stands down the low-power auto-trip detector and brings it back when the trip ends, so they don't fight over GPS.
- **Onboarding cleanup.** Removed the app icon and the PAYE/employment note from the welcome screen (the employed-vs-self-employed note now lives on the tax-band step), and the onboarding flow no longer scrolls.

## 0.3 (36) - 2026-06-28 (Log save polish & number-input hardening)

- **Save confirmation auto-dismisses.** The "Saved to Records" card no longer has a floating "Done" button — it confirms the save, then clears itself and returns to a fresh Log form.
- **Number inputs are sanitised.** Miles and amount fields now accept only digits and a single decimal point (guards pastes and malformed values like "1.2.3"), and a log can't be saved unless the value is a real number greater than zero — so a stray or empty value can never reach your records.

## 0.3 (17) - 2026-06-27 (Deadlines layer, log polish & notification fix)

- **One Deadlines layer.** MTD quarterly updates and the HMRC Self Assessment dates now sit on the same screen, each row with a "Remind" button that adds the deadline to your calendar (MTD deadlines previously had no reminder). Each section has a tappable (?) with a plain-English explanation, replacing the long footnotes.
- **Plain-English (?) tooltips on the tax screens.** The estimated-bill section (Income Tax, Class 4 NIC, effective rate, payments on account) and the Self Assessment summary (turnover, allowable expenses, net profit, trading allowance) now each have a (?) explaining the jargon.
- **Deadline polish.** Dropped the heavy green highlight on the current MTD quarter (which hid its button); buttons are now a clear "Add" with a calendar icon, and Settings → Reminders opens the same unified Deadlines screen (MTD + HMRC) instead of a separate, differently-styled list.
- **Fixed Tax saved screen spacing** — even rhythm between the cards (in-card notes no longer add a dangling bottom gap).
- **Log flow:** removed the redundant on-screen "Done" button (the keyboard's own Done remains); leaving a Log step with nothing entered resets it, while an in-progress entry is preserved as a draft.
- **Fixed stale trip notifications.** If the app was killed mid-trip, the "Finished this trip?" nudge could fire with no trip running, and the "track this trip?" prompt could be silently suppressed forever. A cold-launch cleanup now clears the leftover tracking flag and notifications.

## 0.3 (35) - 2026-06-28 (Calendar add reliability)

- **"Open Settings" now appears on every calendar failure, not just a clean "denied".** On iOS, restricted/write-only access can surface as a hard error rather than a tidy "denied"; that case used to leave you at an OK-only dead end. Both the Deadlines and Key tax dates screens now always offer "Open Settings".
- **Clearer prompt copy.** The dialog now says "Tap Open Settings, then turn on Calendars" so there's no hunting — Open Settings lands on Okkle's own permission page where the Calendars toggle lives.
- **More reliable event creation.** Okkle now falls back to the first writable calendar when there's no default-for-new-events calendar (or it can't be read under limited access), instead of giving up.
- **Lighter permission where supported.** Okkle only ever *adds* events, so it requests write-only calendar access on builds that expose it (with the matching `NSCalendarsWriteOnlyAccessUsageDescription` key), falling back to standard access otherwise.

## 0.3 (34) - 2026-06-28 (Calendar permission escape hatch)

- **"Add to calendar" now offers Open Settings if access is denied.** Previously if calendar access was off, tapping Add just showed "couldn't add it" and left you stuck (iOS won't re-prompt once denied). Now it shows an "Open Settings" button to enable it directly.

## 0.3 (33) - 2026-06-28 (Home greeting)

- **Home now greets you by name and time of day** — "Morning, / Afternoon, / Evening, {name}" instead of just the bare name. Kept compact (first name only, no "Good") so it stays on one line and Home still fits without scrolling.

## 0.3 (32) - 2026-06-28 (Home fits on one screen)

- **Home is non-scrolling again and fits cleanly.** Removed the redundant "Estimates only — not tax advice" line from Home (the Tax section, exports and Accountant Pack already carry it), so the hero + weekly goals now fit on one screen with nothing clipped by the tab bar.

## 0.3 (31) - 2026-06-28 (Header subtitle gutter)

- **Header subtitle no longer runs under the settings gear.** The subtitle now wraps before the gear's column (matching the title), so the title + subtitle form a clean left-aligned block with the gear in its own top-right gutter.

## 0.3 (29) - 2026-06-28 (Consistent header gear)

- **Settings gear now vertically centred on the title and in the same place on every tab.** Nudged the gear to sit centred on the 26px title line, and removed the Log screen's "Log entry" eyebrow so its header matches Home/Insights/Records (title + gear) instead of the gear sitting higher.

## 0.3 (28) - 2026-06-28 (Header alignment, onboarding spacing + permission priming)

- **Compact, aligned headers.** The screen title now sits on the same row as the settings gear instead of floating far below it, removing the large empty gap at the top of Home, Insights and Records.
- **Fixed Home's bottom disclaimer being clipped by the tab bar** — Home scrolls again (its goals + disclaimer are too tall for one screen), so nothing hides behind the tab bar.
- **Fixed onboarding bottom text cramped under the button.** Content now scrolls if a step is tall, with the "Get started" button pinned to the bottom (safe-area aware) with a divider — so nothing hides behind it.
- **Onboarding now asks for permissions up front.** On the final step Okkle requests notifications, location ("Always", so GPS tracks while locked) and calendar access — so trip nudges, deadline reminders and "Add to calendar" just work later instead of erroring the first time.

## 0.3 (27) - 2026-06-27 (Simplified-method clarity)

- **Expense categories reordered for the simplified method.** Costs you can claim on top of flat-rate mileage (parking, phone, congestion/ULEZ, kit) now lead; the vehicle running costs the flat rate already covers (fuel, charging, insurance, servicing, tyres) moved to the end since they're flagged as double-claims.
- **Clearer onboarding claim.** The welcome screen now says Okkle estimates your tax using HMRC's simplified flat-rate mileage and gets you ready for Self Assessment — and that you/your accountant still file the return — instead of implying it does full Self Assessment.

## 0.3 (26) - 2026-06-27 (Log screen polish)

- **Fixed the Log header tucking under the status bar / Dynamic Island** — it now uses the full safe-area top clearance.
- **Removed the in-amount "Done" pill** when entering earnings/expense amounts — it looked out of place; the keyboard's own Done dismisses the keypad.

## 0.3 (25) - 2026-06-27 (Onboarding layout fix)

- **Fixed the onboarding "Get started" button sitting too low / steps scrolling.** Each onboarding step is now a fixed (non-scrolling) layout with the button pinned above the home indicator using the safe-area inset, instead of a scroll view that pushed the button to the bottom edge.

## 0.3 (24) - 2026-06-27 (White-screen fix verified on device)

- **Fixed the TestFlight white screen** — the committed native `ios/` project was a stale prebuild that no longer matched `expo-modules-core`, so Expo's native modules (ExpoAsset, ExpoConstants…) failed to register at launch and the JS threw before rendering. Regenerated the native project (`expo prebuild --clean`); verified on a simulator that a fresh/empty install launches correctly. (EAS Build does this clean prebuild automatically — the recommended way to ship.)
- **Locked to light appearance** — Okkle is designed light-first; following the system theme rendered blank on dark-mode phones. Now always light.
- **Crash hardening** — a root error boundary shows a friendly "something went wrong — try again" screen instead of a blank white screen if anything ever throws in a release build, plus the deadline alert is wrapped in a safe-area provider and try/catch.

## 0.3 (19) - 2026-06-27 (Global deadline alert + grid-cell hotspots)

- **Unmissable deadline alert.** When a tax deadline is within 14 days, a banner now drops in from the top over any screen (re-checks when you reopen the app, dismissible per deadline). The Tax screen's Deadlines row also shows the countdown, turning red within 14 days.
- **Smarter hotspots.** The "Where" ranking now clusters your GPS breadcrumb into ~450m cells instead of tagging each trip to one area — so it stays accurate even when you track a whole shift as a single trip. Areas are reverse-geocoded to friendly names (cached) and £-weighted by your logged pay.

## 0.3 (18) - 2026-06-27 (Configurable deadline reminders + in-app banner)

- **Choose your reminder lead times.** Settings → Reminders now lets you pick how far ahead to be nudged about tax deadlines — 1 month / 2 weeks / 1 week / 1 day — and you can pick several, so you get staged reminders (default: all four). Each fires as its own notification before every Self Assessment and MTD date.
- **In-app deadline banner.** The Tax screen now shows a "due in X days" banner for the nearest upcoming deadline (within 30 days), so you're reminded even if a push notification was missed — tap it to open the Deadlines screen.
- Single source of truth for all tax deadlines (`src/taxDeadlines.ts`), shared by the scheduler, the banner and the Deadlines screen.

## 0.3 (16) - 2026-06-27 (Export accuracy: tax-year-scoped, cap-free exports)

- **Fixed exports not reconciling with the tax summary.** The FreeAgent CSV, HMRC mileage log, all-data CSV and Accountant Pack are now scoped to the tax year (like the Self Assessment figures), instead of dumping all history — so a returning user's export totals match their summary.
- **Removed silent row caps on exports.** Exports previously truncated to the newest 500/1,000 rows, dropping older entries for high-volume couriers. Exports are now complete (new `getTripsForTaxYear` / `getRecordsForTaxYear` DB getters, no LIMIT).

## 0.3 (15) - 2026-06-27 (Polish: fixed tax tab, expense autocorrect & food/drink)

- **Home screen no longer scrolls** — it's a fixed, glanceable view (nothing to scroll).
- **Insights scrolls back to the top** when you leave the tab and return.
- **Records → Tax tab no longer scrolls** — the tax summary is a fixed, glanceable view; History still scrolls and pull-to-refreshes.
- **Fixed expense description being autocorrected.** The category field disabled iOS autocorrect/spellcheck, so what you type is kept exactly (it was sometimes swapped for a different word).
- **Added "Food & drink" expense category** — flagged for accountant review, since subsistence is only allowable for the self-employed in limited cases (itinerant work / longer shifts away from your normal area), not routine meals.
- **Hid the actual-cost method comparison** while Okkle is simplified-only (the `/compare` screen and engine are kept, just not linked).

## 0.3 (14) - 2026-06-27 (Self-employed clarity, accountant pack & insights automation)


- **Tax section redesigned.** Records → Tax is now a glanceable summary — a "set aside for tax" hero with tap-to-detail cards (bill, tax saved, this year, deadlines) instead of one long scroll. All the detail is preserved behind taps. Tax inputs are consolidated into **Settings → Tax settings** (region, band, other income, method).
- **Clearer that Okkle is for self-employed couriers.** Onboarding now states it's for couriers who file their own Self Assessment, with a note that employed (PAYE) drivers are taxed differently and the estimates won't apply. Tax support is simplified-mileage-only, made explicit in onboarding.
- **Bicycle / e-bike mileage is flagged for review.** HMRC's simplified flat-rate scheme doesn't cover cycles for the self-employed (the 20p/mile is the employee rate), so Okkle keeps it as an estimate and flags it across onboarding, logging, the edit screen and the Accountant Pack — for the accountant to confirm actual-cost treatment.
- **Expenses the flat rate already covers are flagged.** Logging a vehicle running cost (fuel, insurance, repairs…) on the simplified method now warns it's covered by the mileage rate and flags it for accountant review rather than double-claiming.
- **"Business miles" wording.** The mileage step now asks for *business* miles (leave out personal trips) instead of asking users to guess a personal-mileage deduction.
- **Export & share rebuilt.** Clear sections (Accountant Pack / Individual files). The Accountant Pack can be shared as a **PDF**, or as a **PDF + importable transactions CSV bundled in one ZIP** — review pack and raw data in a single share.
- **Accountant details live in Profile.** UTR, NI number, address and nature of business are edited in Settings → Profile and added to the pack's cover page. Export shows a short "add your details" prompt only while they're incomplete, then hides it.
- **Insights stays insights — with optional automation.** Trip nudges and reminders panels moved back to Settings; Insights now offers inline **Turn on** prompts for Trip nudges and Logging reminders that disappear once enabled.
- **GPS accuracy fix.** Trip tracking now rejects low-accuracy fixes and impossible "teleport" jumps and uses best-for-navigation accuracy, so routes no longer cut across blocks and miles aren't inflated by stray points.
- **Bottom tab order** is now Home · Insights · Trip · Log · Records.

## 2.0.0 - 2026-06-25 (Guided logging and liquid glass UI)

- **Redesigned Log as a guided flow.** Logging now asks one question per page, supports receipt/photo upload first, attempts on-device receipt parsing, and resets cleanly after saving or navigating to Records.
- **Added liquid-glass material language.** Shared glass panels and green/neutral native-style buttons now power the log number inputs, tax headline value, Start Trip button, and the logged confirmation sheet.
- **Improved trip and log ergonomics.** Start Trip uses a darker glass button, Log and Trip tab order is updated, numeric-keyboard flows have a done path, and the submitted-log confirmation slides up as a transparent glass bottom sheet.

## 2026-06-25 (Two-way trip nudges; removed automatic shift tracking)

- **Removed automatic (passive) shift tracking.** Motion-based auto-tracking could pick up personal drives (commute, school run) and pile up drafts to discard, so it's gone — along with the background shift accumulator, the shift-review screen, and the "Track my shift automatically" toggle.
- **Trip nudges are now two-way.** Okkle nudges you to **start** a trip when it senses you've started driving (as before) and now also nudges you to **end** it once you've been parked a while (~18 min): a re-armed scheduled notification fires after your last movement, and tapping it opens the live screen to end and save. Nothing is recorded without your tap, so personal drives are simply ignored.
- Settings: "Automatic shift tracking" is now "**Trip nudges**" — one toggle for the two-way reminder.

## 2026-06-25 (Settings consistency: headers, tour, layout)

- **One consistent header everywhere** (`ModalHeader`): every settings/modal layer now has the same left-arrow back button and the same centred title font. Removes the old mix of "Cancel"/"Done" text buttons and differing title styles.
- **Settings menu opens to the top and closes with an ✕** instead of a half-down sheet with a "Done" text button.
- **First-run tour is now five clean cards — one per bottom tab** (Home, Trip, Log, Records, Tax). Dropped the mid-screen spotlights: the tour renders as a modal over the native tab bar, so highlighting elements there looked messy.
- **Profile & tax fits without scrolling**: moved "Key tax dates & HMRC deadlines" into the Reminders screen (where it belongs), and vehicles/platforms are now single-row horizontal chip scrollers instead of multi-row wraps.

## 2026-06-25 (Consistent full-screen modals; pinned Send)

- **All pop-up layers now go full-screen to the top** for a consistent feel. Previously some settings/forms were full-screen and others (Automatic shift tracking, Export, Key tax dates, etc.) were the iOS half-sheet that floated below the top. Standardised every modal to full-screen.
- **Report a problem: Send is now pinned to the bottom** so it can never be cut off, and the form was compacted (tighter diagnostics, removed the extra disclaimer paragraph) so it fits without scrolling.

## 2026-06-25 (Hybrid spotlight tour)

- **Brought back the spotlight in the first-run tour, where it can work.** Steps about on-screen Home elements now dim the screen and highlight the real element — the "Tax saved this year" hero and the Earnings card. Steps about other tabs (Trip / Log / Tax) stay as centred cards, because the native tab bar can't be measured from JavaScript to spotlight reliably. Reordered so the two spotlight steps come first.

## 2026-06-25 (Full-screen settings/forms; fix Replay tour)

- **Settings sub-screens and the feedback form are now full-screen** instead of the iOS half-sheet that peeked the parent and wasted ~180px of height. Profile & tax now fits without scrolling; Report a problem is much shorter (also tightened spacing and the message box). Opaque backgrounds set for the full-screen presentation.
- **Fixed "Replay app tour".** It cleared the flag but only `replace()`d the route, leaving the Settings sheet on top so the tour never appeared. It now dismisses the Settings modals and returns to the tabs; Home re-checks on focus and replays the coach marks.

## 2026-06-25 (Settings flattened — no deep menus, no scrolling)

- **Removed the over-nested settings hierarchy.** "Profile & tax" no longer opens a sub-menu of single-field pages (Personal details / Vehicles / Platforms / Tax region) — it's one consolidated screen again (name, vehicles, platforms, tax region & band, plus a Key tax dates link). Deleted the redundant intermediate menus and leaf pages.
- **Main Settings is one flat, non-scrolling menu** of direct rows: Profile & tax · Automatic shift tracking · Reminders · Export & share · Data & backup · Help & feedback. No menu layer requires scrolling.
- **Automatic shift tracking now explains itself.** Each toggle has a plain description: what "Automatic shift tracking" does (counts miles in the background, saves a draft to confirm) and what "Trip start nudges" does (notifies you to start a trip yourself), including that the two are mutually exclusive.

## 2026-06-25 (Verified 2026/27 tax bands; fixed Scottish bands)

- **Confirmed and relabelled the income-tax/NI basis to 2026/27** after checking GOV.UK: the UK personal allowance (£12,570) and basic-rate limit (£37,700) are frozen to 2027/28, and Class 4 NIC is unchanged (6% / 2% at £12,570 / £50,270) — so the existing figures were correct; only the year label was stale.
- **Fixed the Scottish income-tax bands.** The table was missing the "advanced" 45% band (£75,001–£125,140) introduced in 2024/25 and used stale thresholds, which under-estimated tax for some Scottish higher earners. Updated to the verified gov.scot 2026/27 bands: starter 19%, basic 20%, intermediate 21% (thresholds raised to £16,537 / £29,526), higher 42%, advanced 45%, top 48%.
- Updated the Class 2 Small Profits Threshold note to the 2026/27 figure (£7,105).

## 2026-06-25 (Tax-year bucketing, payment-on-account, settings sync)

- **Platforms/vehicles added in Settings now appear immediately** in the Trip and Log tabs. Those tabs re-read your chosen lists whenever they regain focus, so a platform or vehicle added in Settings shows up without restarting the app.
- **Payment on account is no longer over-warned (feedback #3).** It now applies HMRC's *two* conditions — bill over £1,000 **and** less than 80% of tax already collected at source (PAYE/CIS). Pure self-employed couriers are unaffected; mixed PAYE + self-employed users whose tax is mostly collected at source are no longer told to make payments on account.
- **Tax-year and quarter totals use period-overlap consistently (feedback #4).** Tax-year miles / deduction / earnings / expenses / hours and the MTD quarterly summaries previously bucketed records by `created_at`, so a weekly entry spanning the 6 April (or a quarter) boundary landed wholly in one period. They now split each record by its `period_start`/`period_end`, and trips are bounded to the tax-year window.

## 2026-06-25 (Platform management lives in Settings)

- Removed the "Add platform" chip from the **Trip** and **Log** tabs. Those tabs now only show the platforms chosen at onboarding; adding or editing your platforms is done in **Settings → Profile & tax**, keeping one clear place to manage them.

## 2026-06-25 (Compliance pass — mileage rates & honest wording)

- **Mileage rates are now versioned by tax year and updated for 2026/27.** HMRC raised the car & van first-10,000-mile simplified/AMAP rate from 45p to 55p (25p after, unchanged) effective 6 April 2026; motorcycles stay 24p. `calcDeduction`/`mileageRate` now pick the rate schedule by the record's date, so back-dated entries keep the old rate while current trips use 55p. (Source: gov.uk "Increasing mileage rates".) Previously the app hard-coded 45p and under-claimed for the current year.
- **Cycle treatment clarified.** The simplified flat-rate scheme formally covers cars, goods vehicles and motorcycles; the e-bike/bicycle figure follows the employee rate and self-employed cyclists may need actual costs — now flagged as an estimate to verify.
- **Disclaimers added** ("estimates — verify current HMRC rates before filing") in About.
- **Softened over-claiming wording:** the Accountant Pack is now framed as an "Accountant Review Pack — not a final filing pack"; GPS language no longer implies it "satisfies" HMRC (now: supports a contemporaneous log, still needs review).
- **Actual-cost honesty:** the method comparison now states it uses one set of figures and does not track the method per individual vehicle, so multi-vehicle users are told to confirm per-vehicle treatment.
- **Exports clarified:** "FreeAgent bank-import CSV" (income & expenses only — skip rows already on your bank feed) is clearly separated from the "HMRC mileage log (CSV)" so mileage stays out of the bank-import stream.

## 2026-06-25 (Hotspot map, live-trip numbers, tidier Settings)

- **Real Apple Maps hotspot.** On iOS, Insights → Hotspot map now renders on an actual Apple Maps street map with a native weighted heatmap overlay (via the already-bundled `react-native-maps`, same as the live trip route). The SVG density grid stays as the Android / Expo Go fallback. No new native dependency.
- **Fixed tiny live-trip numbers.** The big number on the active-trip screen (miles this trip, average mph, miles today, etc.) was collapsing to a small size — an iOS conflict between an explicit `lineHeight` and `adjustsFontSizeToFit`. Removed the explicit line height so the number renders full-size and only auto-shrinks for long values.
- **Categorised Settings.** The settings list is now grouped under labelled sections — Account & tax, Tracking & logging, Your data, Help & feedback — so it's easier to scan.

## 2026-06-25 (Vehicles match platforms — only show what you chose)

- **Vehicles are now multi-select at onboarding** and only the ones you picked appear in the **Log** and **Trip** tabs — exactly like platforms. A courier who only rides a bike no longer wades through car/van/motorbike when logging mileage.
- New `vehicles` column (comma-separated) with a `getVehicleKeys()` helper; the existing single `vehicle` stays as the primary/default used to pre-fill selections. Backward-compatible: users created before this fall back to their single vehicle.
- **Settings → Profile & tax** now manages your vehicles as a multi-select ("Vehicles you use"), mirroring platform management. Backup/restore carries the list.
- Comparison and the trip-edit screens still show the full vehicle list (comparison needs every rate; editing an old trip may reference a vehicle you no longer use).

## 2026-06-25 (Passive whole-shift mileage tracking)

- **Added hands-free shift tracking** (`src/shift.ts`): Okkle now counts every business mile of a delivery shift in the background — driving to the restaurant, to the customer, and the "dead" miles cruising between offers — without the courier tapping anything mid-delivery. This matches the UK simplified-expenses model, where all of those are simply business miles (no per-leg split needed).
- **Auto start/stop, break-aware:** a shift starts when Core Motion (or a GPS-speed fallback) detects sustained driving. A short stop (lunch, a wait at a busy restaurant, an errand) does **not** end it — those are just 0-mile gaps inside one shift. The shift only finalises after a long idle (~2h), on manual End, or when a much later drive proves it ended back when movement stopped. It then logs the miles as a draft and fires a "Shift logged — tap to review" notification. Nothing is finalised without the driver confirming.
- **No double-counting:** the passive tracker stands down while a manual trip (the classic Start/End flow, which is unchanged and always available) is running.
- **"Done for the day?" prompt:** a scheduled notification re-armed on every movement, set to fire ~40 min after your *last* movement, so it reliably asks you to end (even if the app is suspended) instead of waiting for a background wake-up. Tapping it finalises the shift and opens the review; ignoring it (e.g. a long lunch) leaves the shift open and still counting.
- **On-device learning (first slice):** the review screen remembers the app(s) you tagged last time and pre-selects them, so a single-platform driver just taps Confirm. Stays entirely on the phone.
- **Battery-first design:** reuses the existing low-power background location task (Balanced accuracy, automotive activity type, 60s deferred/batched updates, `pausesUpdatesAutomatically`) instead of a continuous high-accuracy GPS fix or keeping a screen awake.
- **End-of-shift review** (`app/shift-review.tsx`): tapping the "Shift logged" notification opens a one-tap **Confirm** screen showing the miles + estimated tax back. The driver can optionally tag **which app(s)** the shift was on (multi-select for multi-apping) and, **only for a single-app shift**, record what they earned — multi-app shifts ask the driver to log pay weekly instead, since earnings can't be honestly split per mile. A **Discard** option handles a personal drive that got caught.
- **Platform attribution is insight-only, not tax:** totals (income + miles) stay platform-agnostic so the HMRC calculation is always correct; per-platform tagging exists purely to power a "which platform pays best" comparison, and only clean single-app shifts feed that comparison.
- **Settings:** "Auto-detect trips" now leads with a **Track my shift automatically** toggle (recommended), with the older tap-to-start nudge kept as a fallback. The two are mutually exclusive.

## 1.0.1 - 2026-06-23 (iOS 26 polish, dark mode and native testing)

- **Upgraded to Expo SDK 56** and aligned the app for native iPhone simulator/TestFlight development.
- **Added system dark mode support**, including a dark-aware Tax saved hero card and cleaner light-mode white app background.
- **Polished the iOS 26-style interface** with a floating liquid-glass tab bar, glass settings button, and a collapsing header whose fade now lives inside the header chrome instead of covering page content.
- **Improved core controls and readability**: numeric keyboards now have a Done accessory, the active trip screen has a darker driving-focused treatment, and live mileage is easier to read.
- **Refined visual hierarchy** across buttons, medals, log panels and summary cards, including clearer income/expense/mileage colour treatment.

## 2026-06-23 (Real weekly entries)

- **Weekly logging is now a real feature**, not just a lump on one day. The Log tab has a **Day / Week** toggle for earnings, mileage and expenses. A weekly entry stores its Mon–Sun range (`period_start`/`period_end`).
- **Reports spread weekly entries across their days** — `getPeriodSummary`, `getPeriodSeries` (charts) and `getDailyStats` now distribute a weekly amount evenly over the 7 days it covers and clip to the view window, so the daily/weekly breakdowns stay accurate (no false spike on payday; "today" shows ~1/7).
- Week mode offers **This week / Last week** quick presets and shows the covered range; **Records** labels weekly entries "Week of X–Y".

## 2026-06-23 (Log: daily earnings + smarter categories)

- **Earnings can be daily or weekly** — dropped the "weekly" framing and added **Today / Yesterday** quick-date chips so logging a single day's takings (or back-dating) is one tap.
- **Expense categories are now icon chips, sorted by how often you use them** — like benchmark accounting apps (QuickBooks Self-Employed, Coconut), the ones you reach for most float to the front so you're not hunting. Each category has a Feather icon for fast scanning, and a sensible courier-priority default order (Fuel, Charging, Parking, Phone, Insurance…).

## 2026-06-23 (Log tab redesign)

- **Redesigned the Log tab** in the Home/Trip design language. The type switcher (Expense · Earnings · Mileage) now has a **smooth animated sliding pill**, and switching type **cross-fades/slides** the form in.
- **The amount is now the hero** — a big gradient input card (green for earnings, amber for expenses, brand for mileage) shows what you're logging front-and-centre, with live context (mileage deduction, "gross pay before deductions", etc.).
- **Easier to log** — a friendly type header ("Add an expense", with a gradient icon), prominent number entry, a compact inline **Date** row instead of a separate card, and a **gradient Save button** that turns green on success.

## 2026-06-23 (Bigger live map, finer areas, pay logging moved to Log)

- **The live Map view is now much bigger** (~42% of screen height) when you swap it into the hero spot.
- **More specific area names** in Insights — trips now record the road + outward postcode (e.g. "Kingston Road · SW19") instead of a whole borough like "Merton". Applies to newly tracked trips.
- **Removed the duplicated weekly-pay flow from Trip.** The Log tab already has an Earnings mode, so the Trip "Log weekly pay" tile now jumps straight to **Log → Earnings** (deep-linked) rather than maintaining a second copy of the same screen.

## 2026-06-23 (Swappable live metrics, live map, finish scorecard)

- **Tap any live stat to make it the hero** — the big number can now be miles, time, avg mph or miles-today; tapping a cell in the strip swaps it into the big spot.
- **Live route map** — one of the swappable views is a **Map** that draws your GPS breadcrumb as you ride (the breadcrumb is now exposed live from the trip hook).
- **Celebratory finish scorecard** — ending a trip now opens a motivational summary: a headline ("New personal best!" / "Nice ride!"), how much you earned back, and **gamification hooks** — a **new-longest-trip** record banner (beats your old best) and a **streak** nudge.
- Replaced the route-map placeholder emoji with a Feather icon.

## 2026-06-23 (Live "earn it back" gamification)

- The live trip screen now has an **"earn it back" milestone bar**: it fills toward the next £5 of mileage money earned back, and each time you cross a milestone it fires a **success haptic** and a brief **"£X earned back!" celebration**. Turns the money figure into a live, motivating game instead of a static number.

## 2026-06-23 (Live trip revamp + slider fix)

- **Fixed the slide-to-end slider** (and pause button) not responding — the new gradient background's SVG layer was swallowing touches; it's now `pointerEvents="none"`. This also makes every gradient card (Home hero, Start) reliably tappable.
- **Revamped the live tracking screen.** Dropped the arbitrary "% of daily goal" activity ring — mid-trip there's no fixed distance target — in favour of what couriers actually glance at: a **big live distance**, the **tax deduction it's earning** (amber chip), and a glass strip of **time · avg mph · miles today**, with a clear **Recording / Waiting / Paused** status pill.

## 2026-06-23 (Trip screen redesign)

- **Redesigned the Trip start screen** in the Home design language. Platform + vehicle are now in **one calm card** (with gradient `IconBadge` labels) instead of two stacked sections, **Start trip is a gradient hero card** with the selected platform/vehicle summarised, and **Log pay / Accept-or-skip are clean tiles** rather than competing bordered buttons. Same capabilities, far less button noise.
- **Live tracking screen** now has a subtle dark→green **gradient background** for depth, and the trip-saved **success check is a gradient** — consistent with the rest of the app.

## 2026-06-23 (Smooth carousels, heatmap on Home, £/h fix)

- **Fixed another £/hour explosion** — zone stats (and the best-spot tip) were showing things like £402,613/h when a trip had earnings but ~no tracked time. Now ignored under ~15 min; those areas rank and display by earnings instead.
- **"Where & when you earn" carousel now includes a Hotspot map page** and richer ranked lists (Areas · Map · Best times · Best platforms), so it's no longer one lonely card.
- **All Home carousels now use a smooth sliding dot indicator** (`AnimatedDots`) that tracks your finger — same premium feel as the Today/Week/Month/Year switcher. Applies to Earnings, Progress and the insights carousel.
- **Clearer Today time labels** — now `6am · 11am · 2pm · 5pm · 9pm` instead of `6–11a`.
- **The medals card (Progress page 2) is no longer empty** — it now shows a "Closest to unlocking" list with progress bars for the next medals you'll earn.

## 2026-06-23 ("Accept or skip?" order checker)

- New **"Accept or skip?" order checker** (Trip tab): enter an offer's pay + distance and it shows the **£/mile** (and £/hour with an optional time estimate) plus a clear *Worth it / Skip it* verdict against your **minimum £/mile** — seeded from your own historical average and adjustable. This replaces the passive "Tips" tab with an actual decision tool couriers use on every order.
- Removed the Insights **Tips** tab (advice, not a feature) in favour of the above.

## 2026-06-23 (Insights carousel, Tips tab, clearer time labels)

- **"Where & when you earn" is now a swipeable carousel** on Home — Top areas · Best times · Best platforms, each ranked 1·2·3, with the best spot pinned above and dot indicators.
- **Earnings carousel now shows dot indicators** so it's obvious you can swipe between Today/Week/Month/Year.
- **New "Tips" tab in Insights** — tactics couriers use to earn more (multi-apping, positioning at your best hotspot, cherry-picking by £/mile, working peak windows, favouring the better-paying app, the 10k-mile rule, quests/bonuses, banking tax). Personalised from your own numbers.
- **Clearer Today time labels** — the by-time chart now reads 6–11a · 11–2p · 2–5p · 5–9p · 9p+ instead of "Morn/Lunch/Aft".

## 2026-06-23 (Today chart, period-swipe fix, finer areas)

- **Today earnings is no longer blank** — it now shows a "when you earned today" chart broken into Morning / Lunch / Afternoon / Evening / Late.
- **Fixed the period switcher** jumping to the wrong period (tapping Week landed on Month) — removed a controlled scroll offset that fought the animated scroll.
- **Finer area names** in "Where you earn most": trips now prefer the neighbourhood/street and add the town for context ("Shoreditch, London" instead of a bare "London"). Applies to newly tracked trips.

## 2026-06-23 (Swipeable earnings, tappable tax, categorised Insights)

### Home
- **Tax saved → tap through** to the full Tax breakdown (with a chevron + "see breakdown" hint).
- **Earnings is now swipeable**: swipe sideways to move between Today · Week · Month · Year. The period switcher has an **animated sliding pill** driven by the swipe — buttery, premium feel.
- **By-platform now ranks 1 · 2 · 3** with numbered badges (the leader highlighted).
- **"Where you earn most" leads with numbers** instead of a map: your best zone + £/hour, then a ranked top-3 of areas. The full hotspot map stays in Insights.

### Insights — categorised, no longer one long scroll
- Split into three focused tabs — **Where** (ranked areas + hotspot map), **When** (best hours), **Money** (platform ranking + business P&L) — with the headline takeaway pinned above. One view at a time.

## 2026-06-23 (Starling-style headers + number fixes)

### Animated collapsing headers on every tab
- New `CollapsingHeader`: the tab title sits large at the top and **slides away as you scroll**, while a compact pinned title + a solid bar fade in (Starling-style, native-driven). Applied to **Home, Trip, Log, Records and Tax** — the title now always stays at the top, and the settings gear stays pinned.

### Home — fixed the broken numbers
- **£/hour no longer explodes** when there's earnings but almost no tracked time (it was showing things like £1,585,899/hr). Below ~15 min of tracked time it now shows "—". The net-per-hour line follows the same rule.
- Stat values **auto-shrink to one line** instead of wrapping mid-number, and the "vs last period" trend only shows when there's a real prior period to compare against.

### Records — filters no longer overflow
- The segmented filter now spans the **full width** (no more "Earnings Expens…" truncation) and the month control collapses to a **compact calendar pill** that only shows the month name once you've picked one.

### Home — one earnings card instead of three blocks
- Merged the **Earned-per-hour** card, the **Earnings/Miles/Hours** carousel and the **By-platform** list into a **single Earnings card**: the headline number + trend, a three-stat strip (£/hour · miles & tax back · hours), the earnings chart, and the top-3 platforms — all in one place. Much shorter, one glance.
- The hero "Tax saved" card now uses a **real gradient** (brand → deep → dark) for depth instead of a flat fill, via a new `GradientCard` (SVG-based, works in Expo Go).

### Records — one filter row, not two
- Replaced the two stacked scrolling chip rows with a **single segmented control** (All · Trips · Earnings · Expenses) plus a compact **month picker** pill. "Trips" now covers GPS + manual mileage together, and each row keeps its GPS / Manual tag so they're still distinguishable.

### Insights — compact, gradient icons
- Folded the headline "you earn most…" tip **into** the hotspots card (one card, not two stacked), and swapped the 💡 and 📍 emoji for gradient **IconBadge** glyphs.

## 2026-06-23 (Declutter pass 2: premium icons, trip, tax, edit confirm)

### Icons — our own, not emoji
- Replaced every emoji-as-icon with our **gradient icon system** (IconBadge / Medal): medals now render a Feather glyph on a category-coloured gradient disc, and Personal bests use IconBadge tiles. No more flat, cheap emoji.
- **Home** lost the fire-emoji streak chip and the "Start a trip" button (starting a trip belongs on the Trip tab). Weekly goals + medals are now a single swipeable **Progress** carousel.

### Trip — only what you need to start
- Stripped the start screen down to the essentials: platform → vehicle → **Start** → log pay. Removed the goal ring, streak pill (with emoji) and the four-stat trips/miles/saved/earned bar — replaced by one quiet "Today" line.

### Tax — shorter
- Moved **Key tax dates** off the Tax tab into **Settings → Key tax dates** (its own screen, with add-to-calendar). The Tax tab now stays focused on what you owe.

### Editing — confirm before you change figures
- Saving an edit now asks for **confirmation**, with an extra warning when you edit a **GPS-tracked trip** (it overwrites the original recorded mileage used for tax).

## 2026-06-23 (IA cleanup: Settings, Log, Home)

### Settings — a clean menu
- Replaced the long stacked settings with a **profile summary + tappable category rows** (Profile & tax · Reminders · Data & backup · Report a problem · Suggest an improvement · About), each opening a focused sub-screen. Starling-style.

### Log — compact entry
- The chip pickers (14 expense categories, platforms, vehicles) now **scroll in one row** instead of wrapping into many — an entry fits on screen.

### Home — less stacked
- Moved **Personal bests** onto the Medals screen, so Home keeps just the weekly goals + medals preview. Cleaner flow.

## 2026-06-23 (Trip flow + Records month filter)

### Trip — start without scrolling
- The **Start a trip** button now sits right under the platform/vehicle pickers (the goal ring and today's summary moved below it). No more scrolling past gamification to begin a trip.

### Records — filter by month
- Added a **month filter** (All time / Jun 2026 / May 2026 …) above the type filter, Starling-style — slice a long history by month and type together.

## 2026-06-23 (trip route map + records filter)

### Premium trip detail
- Tapping a GPS trip now shows a **route map** of the journey (drawn on-device from the GPS breadcrumb, with start/finish markers) plus a stat strip — distance · time · tax saved — and the area. Real Google Maps can drop in on a dev build.

### Records categorisation
- A **filter** above the entries list (All / GPS trips / Earnings / Expenses / Manual miles) makes a long mixed list scannable — the right Starling-style pattern for slicing the same data.

## 2026-06-23 (premium icons, Starling-inspired)

### Richer icons, less flat
- Replaced the flat tinted icon circles with **soft gradient discs** — a top highlight and a coloured glow give them depth and warmth (Starling-style). Added blue + violet tones for variety, so it's no longer all-mint (earnings green, miles mint, hours blue, etc.).
- One shared component, so Records, Settings, Export, Insights and the Home cards all lift at once.
- **Medals** gained a soft glow halo so they pop off the surface.

## 2026-06-23 (combined cards + cleaner Records)

### Home — value + chart in one card (Trading-212 style)
- £/hour stays a prominent hero card; the metric carousel now **combines each value with its own chart** — swipe **Earnings / Miles / Hours**, each with the big number, trend and a bar chart of that metric over the period. The separate graph section is gone.

### Records — cleaner, clearer
- Replaced ragged text badges with a **consistent leading icon** per type and aligned columns (amounts no longer wrap).
- Distance entries now show an explicit **GPS vs Manual** tag, so it's obvious what was tracked automatically versus typed in.

## 2026-06-23 (in-app feedback)

### Report a problem / Suggest an improvement
- New feedback flow in **Settings → Help & feedback** — pick a category (problem mode), describe it, optionally attach a screenshot and your email, and send. Composes an email to support (no backend).
- **Privacy-first diagnostics** behind a toggle (app version, OS, device, screen, time) — never attaches your earnings, receipts, location or tax records.

## 2026-06-23 (best zones by £/hour)

### Where you earn most — now in £/hour
- The Insights areas list ranks your zones by **£/hour** (the number that matters), showing it as the headline figure with trips · miles · total earnings underneath.
- The headline tip now ties location to your KPI: **"You earn most around Wimbledon on evenings — £14.20/h · £4.10/h above your average."**

## 2026-06-23 (Home information-architecture overhaul)

### Shorter, ordered Home
- The £/hour KPI and the four metric cards are now **one swipeable carousel** — swipe through £/hour → Take-home → Earnings → Miles → Hours, each with a vs-last-period trend and page dots.
- **Moved off Home:** the 10,000-mile threshold now lives on the **Tax tab** (it's a tax detail); "Recent trips" removed (Records already lists them).
- **Reordered** into one coherent flow: tax saved → start a trip → period performance (carousel + graph + platform) → gamification (bests, goals, medals) → insights. No more random order.

## 2026-06-23 (graphs + gamification rethink)

### Period graphs
- Week / Month / Year on Home now show an **earnings bar chart** (daily / weekly / monthly), with the best bar highlighted ("Best: Fri · £x").

### Gamification: real progress over points
- **Dropped abstract XP & levels** — they were shallow (a level number meant nothing).
- New **"Your personal bests"** — best day, best week, best £/hour, most miles in a day, longest streak, most trips in a day — beating your own real numbers (Nike-style), tied to money and effort.
- Weekly "challenges" reframed as **"This week's goals"** (habit nudges, no points). Streaks and medals unchanged.

## 2026-06-23 (the £/hour KPI)

### The number couriers care about
- A prominent **"Earned per hour"** card on Home, tied to the period switcher: big **£X/hr**, a plain **"£Y/hr after tax & costs"** line (take-home minus real expenses), and a **week-over-week trend** ("up £1.10/hr vs last week").
- No jargon — the one metric couriers actually optimise. The detailed P&L (margins, effective rate) stays on the Tax tab.

## 2026-06-23 (spotlight app tour)

### First-run coachmarks
- A **spotlight tour** runs once after onboarding: it dims the screen and walks across the **five tabs** — Home, Trip, Log, Records, Tax — telling you what each does, so you know where everything is. Quick, not a spotlight on every element.
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
