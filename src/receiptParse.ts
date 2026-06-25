// Heuristic parse of receipt OCR text → a best-guess total + merchant.
// Deliberately simple and on-device; the user always confirms/corrects the
// amount, so we favour a sensible guess over cleverness.

export type ParsedReceipt = { amount: number | null; merchant: string | null };

// Matches "12.34", "£12.34", "1,234.56" etc.
const MONEY = /(\d{1,3}(?:[,\d]{0,8})?[.,]\d{2})\b/g;

function toNumber(s: string): number {
  // normalise "1,234.56" / "1.234,56" → 1234.56
  const cleaned = s.replace(/[^\d.,]/g, '');
  // if both separators present, assume last one is the decimal
  if (cleaned.includes(',') && cleaned.includes('.')) {
    return parseFloat(cleaned.replace(/,/g, ''));
  }
  // a lone comma as decimal (e.g. "12,34")
  if (/,\d{2}$/.test(cleaned) && !cleaned.includes('.')) {
    return parseFloat(cleaned.replace(',', '.'));
  }
  return parseFloat(cleaned.replace(/,/g, ''));
}

export function parseReceipt(lines: string[]): ParsedReceipt {
  const totalCandidates: number[] = [];
  const allCandidates: number[] = [];

  for (const raw of lines) {
    const line = raw.trim();
    const matches = line.match(MONEY);
    if (!matches) continue;
    const nums = matches.map(toNumber).filter(n => !isNaN(n) && n > 0 && n < 100000);
    if (!nums.length) continue;

    const isTotal = /\b(total|amount due|balance due|to pay|grand total|amount paid)\b/i.test(line)
      && !/\b(sub.?total|subtotal)\b/i.test(line);

    allCandidates.push(...nums);
    if (isTotal) totalCandidates.push(...nums);
  }

  // Prefer the largest figure on a "total" line; otherwise the largest figure overall.
  let amount: number | null = null;
  if (totalCandidates.length) amount = Math.max(...totalCandidates);
  else if (allCandidates.length) amount = Math.max(...allCandidates);

  // Merchant: first meaningful text line near the top (skip pure-number / symbol lines).
  const merchant = lines
    .map(l => l.trim())
    .find(l => l.length > 2 && /[a-z]/i.test(l) && !/^[\d.,£$\s-]+$/.test(l)) ?? null;

  return { amount, merchant };
}
