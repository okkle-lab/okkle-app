// NOTE: the `rate`/`rateAfter10k` below are the CURRENT tax year's rates, used
// only for at-a-glance display (e.g. onboarding chips). The source of truth for
// every actual calculation is RATE_SCHEDULES, which is versioned by tax year so
// back-dated records use the rate that applied on their date.
export const VEHICLES = [
  { key: 'car', label: 'Car', rate: 0.55, rateAfter10k: 0.25, icon: '🚗' },
  { key: 'motorbike', label: 'Motorbike', rate: 0.24, rateAfter10k: 0.24, icon: '🏍️' },
  { key: 'bike', label: 'E-bike / Bicycle', rate: 0.20, rateAfter10k: 0.20, icon: '🚲' },
  { key: 'van', label: 'Van', rate: 0.55, rateAfter10k: 0.25, icon: '🚐' },
] as const;

export type VehicleKey = typeof VEHICLES[number]['key'];

// HMRC simplified-expenses / AMAP mileage rates, versioned by tax year.
// From 6 April 2026 the car & van first-10,000-mile rate rose from 45p to 55p
// (25p after is unchanged); motorcycles stay 24p. Each record is valued at the
// rate that applied on its date, so historical entries stay correct.
//   Source: gov.uk "Increasing mileage rates" (effective 6 April 2026).
// HMRC's simplified flat-rate scheme formally covers cars, goods vehicles and
// motorcycles; cycle (bike/e-bike) flat rates follow the employee AMAP figure
// and self-employed cyclists may instead need the actual-cost method — treat the
// cycle figure as an estimate and verify before filing.
export const MILEAGE_THRESHOLD = 10000;

type RateBand = { first: number; after: number };
type RateSchedule = { from: string; rates: Record<string, RateBand> };

const RATE_SCHEDULES: RateSchedule[] = [
  { from: '2026-04-06', rates: {
    car: { first: 0.55, after: 0.25 }, van: { first: 0.55, after: 0.25 },
    motorbike: { first: 0.24, after: 0.24 }, bike: { first: 0.20, after: 0.20 },
  } },
  { from: '1900-01-01', rates: {
    car: { first: 0.45, after: 0.25 }, van: { first: 0.45, after: 0.25 },
    motorbike: { first: 0.24, after: 0.24 }, bike: { first: 0.20, after: 0.20 },
  } },
];

function isoDate(d: Date): string {
  // Guard against invalid dates → treat as today.
  return (isNaN(d.getTime()) ? new Date() : d).toISOString().slice(0, 10);
}

function rateBand(vehicle: string, date: Date): RateBand {
  const iso = isoDate(date);
  const sched = RATE_SCHEDULES.find(s => iso >= s.from) ?? RATE_SCHEDULES[RATE_SCHEDULES.length - 1];
  return sched.rates[vehicle] ?? sched.rates.car;
}

export const PLATFORMS = ['Uber Eats', 'Deliveroo', 'Just Eat', 'Stuart', 'Amazon Flex', 'Other'];

// Default daily mileage goal for the activity ring (a typical shift).
export const DAILY_GOAL_MILES = 40;

// Income tax differs for Scottish taxpayers; England, Wales & NI share one set.
// (HMRC mileage rates above are UK-wide and do NOT change by region.)
export const REGIONS = [
  { key: 'ruk', label: 'England, Wales or NI', basic: 0.20, higher: 0.40 },
  { key: 'scotland', label: 'Scotland', basic: 0.20, higher: 0.42 },
] as const;

export type RegionKey = typeof REGIONS[number]['key'];

export function regionRate(region: string, band: 'basic' | 'higher'): number {
  const r = REGIONS.find(x => x.key === region) ?? REGIONS[0];
  return band === 'higher' ? r.higher : r.basic;
}

export function regionLabel(region: string): string {
  return REGIONS.find(x => x.key === region)?.label ?? REGIONS[0].label;
}

// Map a reverse-geocoded administrative area to a tax region.
export function regionFromArea(area: string | null | undefined): RegionKey {
  if (!area) return 'ruk';
  return /scotland/i.test(area) ? 'scotland' : 'ruk';
}

export function mileageRate(vehicle: string, totalMilesSoFar = 0, date: Date = new Date()): number {
  const b = rateBand(vehicle, date);
  return totalMilesSoFar >= MILEAGE_THRESHOLD ? b.after : b.first;
}

// `date` selects the tax-year rate schedule (defaults to today). Pass the
// record's own date for back-dated entries so they use the rate from that year.
export function calcDeduction(miles: number, vehicle: string, totalBefore = 0, date: Date = new Date()): number {
  const b = rateBand(vehicle, date);
  if (totalBefore >= MILEAGE_THRESHOLD) return miles * b.after;
  const firstBracket = Math.max(0, Math.min(miles, MILEAGE_THRESHOLD - totalBefore));
  const secondBracket = miles - firstBracket;
  return firstBracket * b.first + secondBracket * b.after;
}

export function vehicleEmoji(vehicle: string): string {
  return VEHICLES.find(x => x.key === vehicle)?.icon ?? '🚗';
}

export function vehicleLabel(vehicle: string): string {
  return VEHICLES.find(x => x.key === vehicle)?.label ?? 'Car';
}

export function fmtGbp(amount: number): string {
  const neg = amount < 0;
  const body = Math.abs(amount).toFixed(2).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  return (neg ? '-£' : '£') + body;
}

// Whole-pound currency (no pence) — for large headline figures where pence is noise.
export function fmtGbpRound(amount: number): string {
  const neg = amount < 0;
  const body = Math.abs(Math.round(amount)).toFixed(0).replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  return (neg ? '-£' : '£') + body;
}

export function fmtMiles(miles: number): string {
  // Thousands separators; drop the decimal once we're into the thousands.
  const body = miles >= 1000
    ? Math.round(miles).toLocaleString('en-GB')
    : miles.toFixed(1);
  return body + ' mi';
}

// --- Consistent rate / time / percent formatting across every screen --------
// Per-hour and per-mile rates: always £X.XX (2dp).
export function fmtPerHour(value: number): string { return `£${value.toFixed(2)}/h`; }
export function fmtPerMile(value: number): string { return `£${value.toFixed(2)}/mi`; }

// Hours: 1dp but drop a trailing .0 (e.g. "12h", "12.5h").
export function fmtHours(value: number): string {
  const s = value.toFixed(1);
  return (s.endsWith('.0') ? s.slice(0, -2) : s) + 'h';
}

// Percent: whole number (e.g. "23%").
export function fmtPct(value0to1: number): string { return `${Math.round(value0to1 * 100)}%`; }

export function fmtDuration(seconds: number): string {
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = seconds % 60;
  if (h > 0) return `${h}h ${m}m`;
  if (m > 0) return `${m}m ${s}s`;
  return `${s}s`;
}

export function taxYearLabel(): string {
  const now = new Date();
  const year = now.getMonth() >= 3 ? now.getFullYear() : now.getFullYear() - 1;
  return `${year}/${String(year + 1).slice(2)}`;
}
