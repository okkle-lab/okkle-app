import { requireOptionalNativeModule } from 'expo-modules-core';

// Optional — null in Expo Go / before a dev build, or on devices without Apple
// Intelligence (older iPhones / pre-iOS 26). Callers fall back to the heuristic
// parsers, so nothing breaks.
const Native = requireOptionalNativeModule('OkkleAI');

export const hasAppleIntelligence = !!Native;

export function aiAvailable(): boolean {
  try { return Native?.isAvailable?.() ?? false; } catch { return false; }
}

// One-shot prompt with system instructions → the model's text (on-device).
export async function aiRespond(instructions: string, prompt: string): Promise<string> {
  if (!Native) return '';
  try {
    const r = await Native.respond(instructions, prompt);
    return r?.available ? (r.text ?? '') : '';
  } catch {
    return '';
  }
}

export type AIReceipt = { amount: number | null; date: string | null; category: string | null; merchant: string | null };

const CATEGORIES = 'Fuel, Charging, Parking, Phone / data, Insurance, Maintenance / repairs, Tyres, Congestion charge, ULEZ charge, Insulated bag, Waterproof gear';

// Ask the on-device model to read a receipt's OCR text into structured fields.
// Returns null when Apple Intelligence isn't available (caller falls back).
export async function aiParseReceipt(ocrText: string): Promise<AIReceipt | null> {
  if (!aiAvailable() || !ocrText.trim()) return null;
  const instructions =
    `You extract structured data from a UK delivery driver's expense receipt. ` +
    `Reply with ONLY minified JSON, no prose: ` +
    `{"merchant":string|null,"amount":number|null,"date":"YYYY-MM-DD"|null,"category":string|null}. ` +
    `"amount" is the final total paid (a number, no currency symbol). ` +
    `"category" must be exactly one of: ${CATEGORIES} — or null if unsure.`;
  const text = await aiRespond(instructions, ocrText.slice(0, 4000));
  if (!text) return null;
  try {
    const j = JSON.parse(text.replace(/```json|```/g, '').trim());
    return {
      amount: typeof j.amount === 'number' ? j.amount : null,
      date: typeof j.date === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(j.date) ? j.date : null,
      category: typeof j.category === 'string' && j.category ? j.category : null,
      merchant: typeof j.merchant === 'string' && j.merchant ? j.merchant : null,
    };
  } catch {
    return null;
  }
}
