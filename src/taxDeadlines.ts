// Single source of truth for UK tax deadlines — used by the notification
// scheduler, the in-app "due soon" banner, and the Deadlines screen.
import { kvGet } from './db';

export type DeadlineKind = 'sa' | 'mtd';
export type TaxDeadline = { month: number; day: number; title: string; body: string; kind: DeadlineKind };

// month is 1-12. Real HMRC Self Assessment + MTD for Income Tax dates.
export const TAX_DEADLINES: TaxDeadline[] = [
  { month: 10, day: 5, kind: 'sa', title: 'Register for Self Assessment', body: 'First year self-employed? Pop over to HMRC and register by 5 October — it only takes a few minutes 🙂' },
  { month: 1, day: 31, kind: 'sa', title: 'Self Assessment: file & pay', body: 'Time to file and settle up by 31 January. Your Okkle figures and Accountant Pack are ready whenever you are 🛵' },
  { month: 7, day: 31, kind: 'sa', title: 'Second payment on account', body: 'Heads-up — if HMRC asked for payments on account, your second one is due 31 July. No surprises this way 👍' },
  { month: 8, day: 7, kind: 'mtd', title: 'MTD quarterly update — Q1', body: 'Your 6 Apr–5 Jul update is due 7 August. A couple of minutes keeps Making Tax Digital ticking along ✨' },
  { month: 11, day: 7, kind: 'mtd', title: 'MTD quarterly update — Q2', body: 'Your 6 Jul–5 Oct update is due 7 November. Quick one to stay on track with HMRC 🙌' },
  { month: 2, day: 7, kind: 'mtd', title: 'MTD quarterly update — Q3', body: 'Your 6 Oct–5 Jan update is due 7 February. A couple of minutes keeps everything tidy 📒' },
  { month: 5, day: 7, kind: 'mtd', title: 'MTD quarterly update — Q4', body: 'Your 6 Jan–5 Apr update is due 7 May — the last one of the year. Nearly there! 🎉' },
];

// Lead-time options the user can pick (how far ahead to be reminded).
export const LEAD_OPTIONS: { label: string; days: number }[] = [
  { label: '1 month', days: 30 },
  { label: '2 weeks', days: 14 },
  { label: '1 week', days: 7 },
  { label: '1 day', days: 1 },
];
// Default: remind at every lead time — 1 month, 2 weeks, 1 week and 1 day before.
const DEFAULT_LEAD_DAYS = [30, 14, 7, 1];

export function getLeadDays(): number[] {
  try {
    const raw = JSON.parse(kvGet('deadline_lead_days') || '[]');
    const valid = Array.isArray(raw) ? raw.filter((n: unknown) => LEAD_OPTIONS.some(o => o.days === n)) : [];
    return valid.length ? valid : DEFAULT_LEAD_DAYS;
  } catch {
    return DEFAULT_LEAD_DAYS;
  }
}

// The next future date for a given month/day (this year, or next year if passed).
export function nextOccurrence(month: number, day: number): Date {
  const now = new Date();
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  let d = new Date(now.getFullYear(), month - 1, day);
  if (d < today) d = new Date(now.getFullYear() + 1, month - 1, day);
  return d;
}

export function daysUntil(d: Date): number {
  const now = new Date();
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  return Math.round((d.getTime() - today.getTime()) / 86_400_000);
}

// month/day that falls `n` days before the given month/day (for YEARLY triggers).
// Uses a fixed non-leap reference year so the result repeats cleanly each year.
export function dateMinusDays(month: number, day: number, n: number): { month: number; day: number } {
  const ref = new Date(2027, month - 1, day); // 2027 is a non-leap year
  ref.setDate(ref.getDate() - n);
  return { month: ref.getMonth() + 1, day: ref.getDate() };
}

// The soonest upcoming deadline within `withinDays` — drives the in-app banner.
export function upcomingDeadline(withinDays = 30): { title: string; date: Date; days: number } | null {
  let best: { title: string; date: Date; days: number } | null = null;
  for (const d of TAX_DEADLINES) {
    const date = nextOccurrence(d.month, d.day);
    const days = daysUntil(date);
    if (days >= 0 && days <= withinDays && (!best || days < best.days)) {
      best = { title: d.title, date, days };
    }
  }
  return best;
}
