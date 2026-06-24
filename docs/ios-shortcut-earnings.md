# Screenshot → earnings (Apple Shortcut)

A fully **on-device** way to log earnings: the user screenshots a delivery app's
earnings screen, an Apple Shortcut reads the figure with **Apple's built-in OCR**
(nothing is uploaded, no AI, no server), and opens Okkle pre-filled for the user
to **confirm and save**.

This pairs with the in-app screen at `app/log-earnings.tsx`.

## Deep-link contract (app side — already built)

The Shortcut opens Okkle with:

```
okkle://log-earnings?amount=84.50&period=week&platform=Uber%20Eats
```

| param      | values                         | notes                                              |
|------------|--------------------------------|----------------------------------------------------|
| `amount`   | number (£ stripped in-app)     | required; the figure OCR found                     |
| `period`   | `day` \| `week`                | optional, default `day`; detected from screenshot  |
| `platform` | platform name                  | optional; matched to the app's platform list       |
| `date`     | ISO date                       | optional, default today                            |

Okkle shows a confirm card (editable amount, Day/Week toggle, platform, date).
**Nothing is written until the user taps Save** — the deep link only pre-fills.

> Requires a real install (dev build / TestFlight) for the custom `okkle://`
> scheme. It will not open from Expo Go.

## Build the Shortcut (Shortcuts app → new Shortcut)

Action sequence:

1. **Shortcut Input** (Images) — or **Take Screenshot** if run manually.
2. **Extract Text from Image** → input = the screenshot. *(This is Apple's
   on-device OCR — the image never leaves the phone.)*
3. **Match Text** on the extracted text with regex for the money figure:
   `£?\s?\d[\d,]*\.\d{2}` → take the **first / largest** match. Store as `Amount`.
   - Strip the `£` and commas (the app also cleans it, so either is fine).
4. **If** the text **contains** `week` (case-insensitive) → set `Period` = `week`,
   **Otherwise if** it contains `today` or `daily` → `Period` = `day`,
   **Otherwise** → `Period` = `day` (the user can flip it in the confirm card).
5. *(Optional)* **If** text contains `Uber`/`Deliveroo`/`Just Eat`/`Amazon` → set
   `Platform` accordingly; else leave blank.
6. **URL** action → build:
   `okkle://log-earnings?amount=[Amount]&period=[Period]&platform=[Platform]`
   (URL-encode `Platform`).
7. **Open URLs** → opens Okkle on the confirm card.

## Trigger it automatically

Shortcuts app → **Automation** → **Create Personal Automation**:

- **Screenshot Taken** — runs whenever the user screenshots (the common case).
- *(Optional)* **App Closed → [the delivery app]** — catches "I just finished a
  shift" moments.

Point the automation at the Shortcut above.

## The "user confirms" guarantees (important)

There are **two** confirm points, by design:

1. **iOS automation confirmation.** With **"Ask Before Running" ON** (default for
   most automations), iOS shows a "Run Okkle Earnings?" banner before it does
   anything. On newer iOS some triggers can run without asking — but our flow does
   **not** rely on that, because:
2. **In-app confirm.** Okkle's `log-earnings` screen never writes the entry until
   the user taps **Save**. Even if the automation runs silently, the user still has
   to confirm the figure.

So the "user confirms a figure before it's written" guardrail holds regardless of
iOS version or the Ask-Before-Running setting.

## Opt in / out

This is a **power-user, optional** tool:

- **Opt in:** the user installs the shared iCloud Shortcut link and enables the
  automation (and grants the one-time "allow this shortcut to access photos/run"
  prompts).
- **Opt out:** delete the automation (or the Shortcut). Okkle itself does nothing
  automatically — it only ever reacts to the deep link.

## Limitations (be honest with users)

- OCR can misread a figure or grab the wrong number across the many delivery-app
  layouts — that's exactly why the amount is **editable** on the confirm card.
- Daily vs weekly is a best-guess from keywords; the toggle lets the user correct it.
- We deliberately do **not** send the screenshot anywhere or use AI — accuracy is
  traded for privacy and zero cost, with the user as the final check.
