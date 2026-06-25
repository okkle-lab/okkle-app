// Heuristic parse of receipt OCR text → a best-guess total + merchant.
// Deliberately simple and on-device; the user always confirms/corrects the
// amount, so we favour a sensible guess over cleverness.

export type ParsedReceipt = { amount: number | null; merchant: string | null; category: string | null; date: Date | null };

const MONTHS: Record<string, number> = {
  jan: 0, feb: 1, mar: 2, apr: 3, may: 4, jun: 5,
  jul: 6, aug: 7, sep: 8, oct: 9, nov: 10, dec: 11,
};

// Best-guess the receipt date. UK receipts are day-first (DD/MM/YYYY); also
// handles "25 Jun 2026" style. Returns null if none found.
function detectDate(lines: string[]): Date | null {
  const text = lines.join('  ');
  const noon = (y: number, m: number, d: number): Date | null => {
    if (d < 1 || d > 31 || m < 0 || m > 11) return null;
    const dt = new Date(y, m, d, 12, 0, 0, 0);
    if (isNaN(dt.getTime())) return null;
    if (dt.getTime() > Date.now() + 86400000) return null; // not in the future
    return dt;
  };

  // DD/MM/YYYY, DD-MM-YY, DD.MM.YYYY
  let m = text.match(/\b(\d{1,2})[\/.\-](\d{1,2})[\/.\-](\d{2,4})\b/);
  if (m) {
    let year = parseInt(m[3], 10); if (year < 100) year += 2000;
    const dt = noon(year, parseInt(m[2], 10) - 1, parseInt(m[1], 10));
    if (dt) return dt;
  }
  // DD Mon YYYY  (e.g. "25 Jun 2026", "25 June 2026")
  m = text.match(/\b(\d{1,2})\s+([A-Za-z]{3,9})\.?\s+(\d{2,4})\b/);
  if (m) {
    const mon = MONTHS[m[2].slice(0, 3).toLowerCase()];
    let year = parseInt(m[3], 10); if (year < 100) year += 2000;
    if (mon != null) { const dt = noon(year, mon, parseInt(m[1], 10)); if (dt) return dt; }
  }
  return null;
}

// Keyword → Okkle expense category. Names must match the chips in the Log tab.
const CATEGORY_HINTS: { category: string; keywords: string[] }[] = [
  { category: 'Fuel', keywords: ['shell', 'bp ', 'esso', 'texaco', 'gulf', 'jet ', 'applegreen', 'certas', 'petrol', 'fuel', 'diesel', 'unleaded', 'morrisons fuel', 'tesco petrol', 'sainsbury'] },
  { category: 'Charging', keywords: ['pod point', 'podpoint', 'instavolt', 'gridserve', 'bp pulse', 'shell recharge', 'osprey', 'ionity', 'supercharger', 'ev charge', 'kwh', 'charging'] },
  { category: 'Parking', keywords: ['ncp', 'ringo', 'justpark', 'paybyphone', 'parkingeye', 'car park', 'parking', 'apcoa'] },
  { category: 'Tyres', keywords: ['kwik fit', 'kwikfit', 'national tyres', 'tyre', 'tyres', 'protyre'] },
  { category: 'Maintenance / repairs', keywords: ['halfords', 'garage', 'mot', 'service', 'repair', 'auto centre', 'mechanic'] },
  { category: 'Insurance', keywords: ['insurance', 'insure', 'aviva', 'admiral', 'zego', 'hastings', 'churchill', 'direct line', 'policy'] },
  { category: 'Phone / data', keywords: ['vodafone', 'ee ', 'o2 ', 'three', 'giffgaff', 'tesco mobile', 'sim ', 'mobile'] },
  { category: 'Congestion charge', keywords: ['congestion charge', 'cc charge', 'tfl congestion'] },
  { category: 'ULEZ charge', keywords: ['ulez', 'low emission', 'clean air zone', 'caz'] },
  { category: 'Insulated bag', keywords: ['insulated bag', 'thermal bag', 'delivery bag'] },
  { category: 'Waterproof gear', keywords: ['waterproof', 'rain jacket', 'overtrousers'] },
];

// Guess the expense category from the receipt's text.
function detectCategory(lines: string[]): string | null {
  const hay = lines.join(' \n ').toLowerCase();
  for (const { category, keywords } of CATEGORY_HINTS) {
    if (keywords.some(k => hay.includes(k))) return category;
  }
  return null;
}

// Matches "12.34", "£12.34", "1,234.56", and OCR-split totals like "8 49".
const MONEY_PATTERNS = [
  /(?:^|[^\d])(?:£\s*)?(\d{1,3}(?:[,\s]\d{3})*[.,]\d{2})(?!\d)/g,
  /(?:^|[^\d])(?:£\s*)?(\d+)\s(\d{2})(?!\d)/g,
] as const;
const TOTALISH = /\b(total|amount due|balance due|grand total|to pay|amount paid|paid|card|debit|credit|visa|mastercard)\b/i;
const EXCLUDE_TOTALISH = /\b(sub.?total|subtotal|vat|tax|discount|saving|savings|change|cashback|points|loyalty|refund)\b/i;
const QUANTITYISH = /\b(qty|quantity|items?|unit|litres?|liter|ltr|kwh|kw|gallons?)\b/i;

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

function normaliseLine(line: string): string {
  return line
    .replace(/\s+/g, ' ')
    .replace(/[|]/g, '1')
    .trim();
}

function extractMoney(line: string): number[] {
  const out: number[] = [];
  for (const pattern of MONEY_PATTERNS) {
    for (const match of line.matchAll(pattern)) {
      const raw = match[2] ? `${match[1]}.${match[2]}` : match[1];
      const value = toNumber(raw);
      if (!isNaN(value) && value > 0 && value < 100000) out.push(value);
    }
  }
  return out;
}

function candidateScore(amount: number, line: string, index: number, totalLines: number, neighborHint: boolean): number {
  let score = 0;
  if (TOTALISH.test(line)) score += 90;
  if (neighborHint) score += 70;
  if (EXCLUDE_TOTALISH.test(line)) score -= 80;
  if (QUANTITYISH.test(line)) score -= 35;
  if (/\b(auth|approval|transaction|invoice|table|order|receipt no|ref)\b/i.test(line)) score -= 25;
  if (/£/.test(line)) score += 8;
  if (index >= totalLines * 0.55) score += 12;
  if (index >= totalLines * 0.75) score += 12;
  if (amount < 1) score -= 25;
  if (amount > 5000) score -= 60;
  return score;
}

export function parseReceipt(lines: string[]): ParsedReceipt {
  const cleaned = lines.map(normaliseLine).filter(Boolean);
  const candidates: { amount: number; score: number; index: number }[] = [];

  for (let i = 0; i < cleaned.length; i++) {
    const line = cleaned[i];
    const prev = cleaned[i - 1] ?? '';
    const next = cleaned[i + 1] ?? '';
    const lineAmounts = extractMoney(line);
    const prevHint = TOTALISH.test(prev) && !EXCLUDE_TOTALISH.test(prev);
    const nextHint = TOTALISH.test(next) && !EXCLUDE_TOTALISH.test(next);

    for (const amount of lineAmounts) {
      candidates.push({
        amount,
        score: candidateScore(amount, line, i, cleaned.length, false),
        index: i,
      });
      if (prevHint || nextHint) {
        candidates.push({
          amount,
          score: candidateScore(amount, line, i, cleaned.length, true),
          index: i,
        });
      }
    }
  }

  let amount: number | null = null;
  if (candidates.length) {
    candidates.sort((a, b) => b.score - a.score || b.index - a.index || b.amount - a.amount);
    amount = candidates[0].amount;
  }

  // Merchant: first meaningful text line near the top (skip pure-number / symbol lines).
  const merchant = cleaned
    .map(l => l.trim())
    .find(l => l.length > 2
      && /[a-z]/i.test(l)
      && !/^[\d.,£$\s-]+$/.test(l)
      && !/\b(vat|subtotal|total|receipt|invoice|thank you)\b/i.test(l)) ?? null;

  return { amount, merchant, category: detectCategory(cleaned), date: detectDate(cleaned) };
}
