# Apple Intelligence — on-device receipt parsing (branch: `apple-intelligence`)

Uses iOS 26's **Foundation Models** framework (the on-device Apple Intelligence
LLM) to read a receipt's OCR text into `{merchant, amount, date, category}` far
more robustly than keyword heuristics — and **entirely on-device**, nothing
uploaded.

## Pieces
- `modules/okkle-ai` — local Expo module wrapping `LanguageModelSession`
  (`OkkleAIModule.swift`); `isAvailable()` + `respond(instructions, prompt)`.
- `modules/okkle-ai/index.ts` — `aiParseReceipt(ocrText)` prompts the model for
  minified JSON and validates it.
- Log expense scan: heuristic parse first, then **AI refines** amount/date/
  category/merchant where available; learned merchant→category still wins.

## Graceful degradation
`requireOptionalNativeModule` + an availability check mean it's a no-op on:
- Expo Go / before a dev build,
- devices without Apple Intelligence (older iPhones, pre-iOS 26),
- when the model is downloading/unavailable.
In all those cases the existing Vision OCR + keyword/learned parser is used.

## ⚠️ Validation
- Needs a **dev/EAS build** (native module) — can't run in Expo Go, not compiled
  here yet. Validate after the `okkle-vision`/`okkle-motion` modules are proven.
- Requires an **Apple-Intelligence-capable device + iOS 26** to actually invoke
  the model; otherwise it falls back silently.
- Kept on this branch so `master` stays clean for TestFlight. Merge once the
  other native modules build cleanly, then validate this one.
