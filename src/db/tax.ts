export const VEHICLES = [
  { key: 'car', label: 'Car', rate: 0.45, rateAfter10k: 0.25, icon: '🚗' },
  { key: 'motorbike', label: 'Motorbike', rate: 0.24, rateAfter10k: 0.24, icon: '🏍️' },
  { key: 'bike', label: 'E-bike / Bicycle', rate: 0.20, rateAfter10k: 0.20, icon: '🚲' },
  { key: 'van', label: 'Van', rate: 0.45, rateAfter10k: 0.25, icon: '🚐' },
] as const;

export type VehicleKey = typeof VEHICLES[number]['key'];

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

export function mileageRate(vehicle: string, totalMilesSoFar = 0): number {
  const v = VEHICLES.find(x => x.key === vehicle) ?? VEHICLES[0];
  return totalMilesSoFar >= 10000 ? v.rateAfter10k : v.rate;
}

export function calcDeduction(miles: number, vehicle: string, totalBefore = 0): number {
  const v = VEHICLES.find(x => x.key === vehicle) ?? VEHICLES[0];
  if (totalBefore >= 10000) return miles * v.rateAfter10k;
  const firstBracket = Math.max(0, Math.min(miles, 10000 - totalBefore));
  const secondBracket = miles - firstBracket;
  return firstBracket * v.rate + secondBracket * v.rateAfter10k;
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
  return miles.toFixed(1) + ' mi';
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
