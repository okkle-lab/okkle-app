import * as SQLite from 'expo-sqlite';
import { fmtGbp, fmtMiles, fmtPerHour } from './tax';
import { taxPosition, PERSONAL_ALLOWANCE } from './taxcalc';

const db = SQLite.openDatabaseSync('okkle.db');

export function initDb() {
  db.execSync(`
    CREATE TABLE IF NOT EXISTS user (
      id INTEGER PRIMARY KEY,
      name TEXT,
      vehicle TEXT DEFAULT 'car',
      vehicles TEXT,
      tax_rate REAL DEFAULT 0.20,
      region TEXT DEFAULT 'ruk',
      platforms TEXT DEFAULT 'Uber Eats',
      reminder_enabled INTEGER DEFAULT 1,
      reminder_day TEXT DEFAULT 'sun',
      log_frequency TEXT DEFAULT 'weekly',
      onboarded INTEGER DEFAULT 0
    );

    CREATE TABLE IF NOT EXISTS trips (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      platform TEXT NOT NULL,
      vehicle TEXT NOT NULL,
      miles REAL NOT NULL,
      deduction REAL NOT NULL,
      earnings REAL,
      started_at TEXT NOT NULL,
      ended_at TEXT NOT NULL,
      route_json TEXT,
      created_at TEXT DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS kv (
      key TEXT PRIMARY KEY,
      value TEXT
    );

    CREATE TABLE IF NOT EXISTS records (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      record_type TEXT NOT NULL,
      platform TEXT,
      amount REAL,
      miles REAL,
      deduction REAL,
      category TEXT,
      period_start TEXT,
      period_end TEXT,
      receipt_uri TEXT,
      notes TEXT,
      vehicle TEXT,
      created_at TEXT DEFAULT (datetime('now'))
    );
  `);

  // Migrations: add newer columns to existing installs (ignore if present).
  const migrations = [
    `ALTER TABLE user ADD COLUMN region TEXT DEFAULT 'ruk'`,
    `ALTER TABLE user ADD COLUMN reminder_enabled INTEGER DEFAULT 1`,
    `ALTER TABLE user ADD COLUMN reminder_day TEXT DEFAULT 'sun'`,
    `ALTER TABLE user ADD COLUMN log_frequency TEXT DEFAULT 'weekly'`,
    `ALTER TABLE trips ADD COLUMN zone TEXT`,
    `ALTER TABLE user ADD COLUMN vehicles TEXT`,
    `ALTER TABLE records ADD COLUMN vehicle TEXT`,
  ];
  for (const sql of migrations) {
    try { db.execSync(sql); } catch { /* column already present */ }
  }
}

export type User = {
  id: number;
  name: string;
  vehicle: string;        // primary/default vehicle (used to prefill selections)
  vehicles: string | null; // comma-separated list the user actually owns/uses
  tax_rate: number;
  region: string;
  platforms: string;
  reminder_enabled: number;
  reminder_day: string;
  log_frequency: string;
  onboarded: number;
};

export type Trip = {
  id: number;
  platform: string;
  vehicle: string;
  miles: number;
  deduction: number;
  earnings: number | null;
  started_at: string;
  ended_at: string;
  created_at: string;
  route_json?: string | null;
  zone?: string | null;
};

export type Record = {
  id: number;
  record_type: string;
  platform: string | null;
  amount: number | null;
  miles: number | null;
  deduction: number | null;
  category: string | null;
  period_start: string | null;
  period_end: string | null;
  receipt_uri: string | null;
  notes: string | null;
  vehicle?: string | null;
  created_at: string;
};

export function getUser(): User | null {
  return db.getFirstSync<User>('SELECT * FROM user LIMIT 1');
}

export function saveUser(u: Partial<User>) {
  const existing = getUser();
  if (existing) {
    db.runSync(
      `UPDATE user SET name=?, vehicle=?, vehicles=?, tax_rate=?, region=?, platforms=?,
        reminder_enabled=?, reminder_day=?, log_frequency=?, onboarded=? WHERE id=?`,
      u.name ?? existing.name,
      u.vehicle ?? existing.vehicle,
      u.vehicles ?? existing.vehicles,
      u.tax_rate ?? existing.tax_rate,
      u.region ?? existing.region,
      u.platforms ?? existing.platforms,
      u.reminder_enabled ?? existing.reminder_enabled,
      u.reminder_day ?? existing.reminder_day,
      u.log_frequency ?? existing.log_frequency,
      u.onboarded ?? existing.onboarded,
      existing.id,
    );
  } else {
    db.runSync(
      `INSERT INTO user (name, vehicle, vehicles, tax_rate, region, platforms,
        reminder_enabled, reminder_day, log_frequency, onboarded)
       VALUES (?,?,?,?,?,?,?,?,?,?)`,
      u.name ?? '',
      u.vehicle ?? 'car',
      u.vehicles ?? null,
      u.tax_rate ?? 0.20,
      u.region ?? 'ruk',
      u.platforms ?? 'Uber Eats',
      u.reminder_enabled ?? 1,
      u.reminder_day ?? 'sun',
      u.log_frequency ?? 'weekly',
      u.onboarded ?? 0,
    );
  }
}

// The platforms the user actually works for (chosen at onboarding / in Settings).
// Logging screens show only these — not the full master list.
export function getPlatforms(): string[] {
  const raw = getUser()?.platforms ?? 'Uber Eats';
  const list = raw.split(',').map(s => s.trim()).filter(Boolean);
  return list.length ? Array.from(new Set(list)) : ['Uber Eats'];
}

// The vehicle(s) the user actually uses (chosen at onboarding / in Settings).
// Logging and trip screens show only these — not the full master list. Falls back
// to the single primary vehicle for users created before multi-vehicle support.
export function getVehicleKeys(): string[] {
  const u = getUser();
  const raw = (u?.vehicles && u.vehicles.trim()) ? u.vehicles : (u?.vehicle ?? 'car');
  const list = raw.split(',').map(s => s.trim()).filter(Boolean);
  return list.length ? Array.from(new Set(list)) : ['car'];
}

// Add a custom platform (e.g. via "Other") and persist it. Returns the new list.
export function addPlatform(name: string): string[] {
  const clean = name.trim();
  if (!clean) return getPlatforms();
  const list = getPlatforms();
  if (!list.some(p => p.toLowerCase() === clean.toLowerCase())) {
    list.push(clean);
    saveUser({ platforms: list.join(',') });
  }
  return list;
}

// On-device learning for receipts: remember which category the user picks for a
// given merchant, so next time we suggest it. Apple's OCR doesn't learn — this is
// Okkle's own memory, stored locally (no cloud).
export function getLearnedCategory(merchant: string | null): string | null {
  if (!merchant) return null;
  try {
    const map = JSON.parse(kvGet('merchant_categories') || '{}');
    return map[merchant.trim().toLowerCase()] ?? null;
  } catch { return null; }
}
export function learnCategory(merchant: string | null, category: string | null) {
  if (!merchant || !category) return;
  try {
    const map = JSON.parse(kvGet('merchant_categories') || '{}');
    map[merchant.trim().toLowerCase()] = category;
    kvSet('merchant_categories', JSON.stringify(map));
  } catch { /* ignore */ }
}

export function saveTrip(t: Omit<Trip, 'id' | 'created_at'>) {
  db.runSync(
    `INSERT INTO trips (platform, vehicle, miles, deduction, earnings, started_at, ended_at, route_json, zone)
     VALUES (?,?,?,?,?,?,?,?,?)`,
    t.platform, t.vehicle, t.miles, t.deduction, t.earnings ?? null,
    t.started_at, t.ended_at, t.route_json ?? null, t.zone ?? null,
  );
}

export function getTrips(limit = 50): Trip[] {
  return db.getAllSync<Trip>('SELECT * FROM trips ORDER BY created_at DESC LIMIT ?', limit);
}

export function getLastTrip(): Trip | null {
  return db.getFirstSync<Trip>('SELECT * FROM trips ORDER BY created_at DESC LIMIT 1');
}

// `createdAt` (ISO) lets users back-date an entry (e.g. a receipt from last month).
export function saveRecord(r: Omit<Record, 'id' | 'created_at'>, createdAt?: string) {
  if (createdAt) {
    db.runSync(
      `INSERT INTO records (record_type, platform, amount, miles, deduction, category,
        period_start, period_end, receipt_uri, notes, vehicle, created_at)
       VALUES (?,?,?,?,?,?,?,?,?,?,?,?)`,
      r.record_type, r.platform ?? null, r.amount ?? null, r.miles ?? null,
      r.deduction ?? null, r.category ?? null, r.period_start ?? null,
      r.period_end ?? null, r.receipt_uri ?? null, r.notes ?? null, r.vehicle ?? null, createdAt,
    );
    return;
  }
  db.runSync(
    `INSERT INTO records (record_type, platform, amount, miles, deduction, category,
      period_start, period_end, receipt_uri, notes, vehicle)
     VALUES (?,?,?,?,?,?,?,?,?,?,?)`,
    r.record_type, r.platform ?? null, r.amount ?? null, r.miles ?? null,
    r.deduction ?? null, r.category ?? null, r.period_start ?? null,
    r.period_end ?? null, r.receipt_uri ?? null, r.notes ?? null, r.vehicle ?? null,
  );
}

export function getRecords(limit = 100): Record[] {
  return db.getAllSync<Record>('SELECT * FROM records ORDER BY created_at DESC LIMIT ?', limit);
}

// --- Exports: tax-year-scoped, cap-free getters --------------------------------
// The headline/SA figures are scoped to one tax year, so the CSV/pack exports
// MUST be too, or a returning user's export won't reconcile with their summary.
// No LIMIT here: list screens cap rows for performance, but exports must be
// complete. Records use the same overlap predicate as the aggregations so the
// exact same set of entries is included.
export function getTripsForTaxYear(start = taxYearStart(), end = taxYearEnd()): Trip[] {
  return db.getAllSync<Trip>(
    'SELECT * FROM trips WHERE date(started_at) BETWEEN ? AND ? ORDER BY started_at',
    start, end,
  );
}

export function getRecordsForTaxYear(start = taxYearStart(), end = taxYearEnd()): Record[] {
  return db.getAllSync<Record>(
    `SELECT * FROM records WHERE
       (period_start IS NOT NULL AND date(period_start) <= ? AND date(period_end) >= ?)
       OR (period_start IS NULL AND date(created_at) BETWEEN ? AND ?)
     ORDER BY created_at`,
    end, start, start, end,
  );
}

// Marker the passive shift tracker writes into `notes` for a freshly auto-logged
// shift the driver hasn't reviewed yet.
export const SHIFT_DRAFT_NOTE = 'Auto-tracked shift — tap to confirm';

export function getLatestDraftShift(): Record | null {
  return db.getFirstSync<Record>(
    `SELECT * FROM records WHERE record_type='mileage' AND notes=? ORDER BY created_at DESC LIMIT 1`,
    SHIFT_DRAFT_NOTE,
  );
}

export type WeeklySummary = {
  earnings: number;
  miles: number;
  deduction: number;
  takeHome: number;
  taxRate: number;
};

export function getWeeklySummary(): WeeklySummary {
  const user = getUser();
  const taxRate = user?.tax_rate ?? 0.20;

  const since = new Date();
  since.setDate(since.getDate() - since.getDay());
  const sinceStr = since.toISOString().slice(0, 10);

  const tripRows = db.getAllSync<{ miles: number; deduction: number; earnings: number | null }>(
    `SELECT miles, deduction, earnings FROM trips WHERE date(started_at) >= ?`, sinceStr,
  );
  const incomeRows = db.getAllSync<{ amount: number }>(
    `SELECT amount FROM records WHERE record_type='income' AND date(created_at) >= ?`, sinceStr,
  );

  const miles = tripRows.reduce((s, r) => s + r.miles, 0);
  const deduction = tripRows.reduce((s, r) => s + r.deduction, 0);
  const tripEarnings = tripRows.reduce((s, r) => s + (r.earnings ?? 0), 0);
  const manualEarnings = incomeRows.reduce((s, r) => s + (r.amount ?? 0), 0);
  const earnings = tripEarnings + manualEarnings;
  const takeHome = earnings - Math.max(0, earnings - deduction) * taxRate;

  return { earnings, miles, deduction, takeHome, taxRate };
}

// ---- Unified period summaries (Today · Week · Month · Year) ----------------

function taxYearLabelFor(ref: Date): string {
  const y = ref.getMonth() >= 3 ? ref.getFullYear() : ref.getFullYear() - 1;
  return `${y}/${String(y + 1).slice(2)}`;
}

export type Period = 'today' | 'week' | 'month' | 'year';

export type PeriodSummary = {
  period: Period;
  label: string;        // e.g. "June 2026", "This week", "Today"
  rangeStart: string;   // ISO date (yyyy-mm-dd), inclusive
  rangeEnd: string;     // ISO date, inclusive
  earnings: number;
  miles: number;
  deduction: number;
  expenses: number;
  trips: number;
  hours: number;
  takeHome: number;
  taxRate: number;
};

// Resolve a period to an inclusive [start, end] ISO-date range + a human label.
export function periodRange(period: Period, ref = new Date()): { start: string; end: string; label: string } {
  const iso = (d: Date) => d.toISOString().slice(0, 10);
  if (period === 'today') {
    return { start: iso(ref), end: iso(ref), label: 'Today' };
  }
  if (period === 'week') {
    // Pay weeks for Uber/Deliveroo/Just Eat run Monday–Sunday.
    const day = ref.getDay(); // 0=Sun..6=Sat
    const mondayOffset = day === 0 ? 6 : day - 1;
    const start = new Date(ref); start.setDate(ref.getDate() - mondayOffset);
    const end = new Date(start); end.setDate(start.getDate() + 6);
    return { start: iso(start), end: iso(end), label: 'This week' };
  }
  if (period === 'month') {
    const start = new Date(ref.getFullYear(), ref.getMonth(), 1);
    const end = new Date(ref.getFullYear(), ref.getMonth() + 1, 0);
    const label = ref.toLocaleDateString('en-GB', { month: 'long', year: 'numeric' });
    return { start: iso(start), end: iso(end), label };
  }
  // year = UK tax year (6 Apr – 5 Apr)
  const start = taxYearStart(ref);
  const sy = parseInt(start.slice(0, 4), 10);
  return { start, end: `${sy + 1}-04-05`, label: `Tax year ${taxYearLabelFor(ref)}` };
}

// ---- Weekly/period spreading -----------------------------------------------
// A record can cover a date range (e.g. a week's pay). These helpers spread its
// value evenly across the days it covers so daily/weekly views stay accurate,
// instead of dumping a lump on one day. Single-day records count as before.
function dnum(s: string): number { return Math.floor(new Date(s.slice(0, 10) + 'T00:00:00').getTime() / 86400000); }
function isoFromNum(n: number): string { return new Date(n * 86400000).toISOString().slice(0, 10); }

function spreadValue(value: number, ps: string | null, pe: string | null, createdAt: string, start: string, end: string): number {
  const S = dnum(start), E = dnum(end);
  if (ps && pe) {
    const A = dnum(ps), B = dnum(pe);
    if (B > A) { const ov = Math.min(B, E) - Math.max(A, S) + 1; return ov > 0 ? value * (ov / (B - A + 1)) : 0; }
  }
  const C = dnum(createdAt); return C >= S && C <= E ? value : 0;
}
function spreadIntoDays(addFn: (k: string, v: number) => void, value: number, ps: string | null, pe: string | null, createdAt: string, start: string, end: string) {
  const S = dnum(start), E = dnum(end);
  if (ps && pe) {
    const A = dnum(ps), B = dnum(pe);
    if (B > A) { const per = value / (B - A + 1); for (let d = Math.max(A, S); d <= Math.min(B, E); d++) addFn(isoFromNum(d), per); return; }
  }
  const c = createdAt.slice(0, 10); if (c >= start && c <= end) addFn(c, value);
}
type OverlapRec = { created_at: string; amount: number | null; miles: number | null; deduction: number | null; ps: string | null; pe: string | null };
function recordsOverlapping(type: string, start: string, end: string): OverlapRec[] {
  return db.getAllSync<OverlapRec>(
    `SELECT created_at, amount, miles, deduction, period_start AS ps, period_end AS pe FROM records
     WHERE record_type=? AND (
       (period_start IS NOT NULL AND date(period_start) <= ? AND date(period_end) >= ?)
       OR (period_start IS NULL AND date(created_at) BETWEEN ? AND ?))`,
    type, end, start, start, end);
}

export function getPeriodSummary(period: Period, ref = new Date()): PeriodSummary {
  const user = getUser();
  const taxRate = user?.tax_rate ?? 0.20;
  const { start, end, label } = periodRange(period, ref);

  const tripRows = db.getAllSync<{ miles: number; deduction: number; earnings: number | null; started_at: string; ended_at: string }>(
    `SELECT miles, deduction, earnings, started_at, ended_at FROM trips WHERE date(started_at) BETWEEN ? AND ?`, start, end,
  );
  // Income / mileage / expense records, spread across any period they cover.
  const incomeRows = recordsOverlapping('income', start, end);
  const mileRows = recordsOverlapping('mileage', start, end);
  const expRows = recordsOverlapping('expense', start, end);

  const miles = tripRows.reduce((s, r) => s + r.miles, 0)
    + mileRows.reduce((s, r) => s + spreadValue(r.miles ?? 0, r.ps, r.pe, r.created_at, start, end), 0);
  const deduction = tripRows.reduce((s, r) => s + r.deduction, 0)
    + mileRows.reduce((s, r) => s + spreadValue(r.deduction ?? 0, r.ps, r.pe, r.created_at, start, end), 0);
  const earnings = tripRows.reduce((s, r) => s + (r.earnings ?? 0), 0)
    + incomeRows.reduce((s, r) => s + spreadValue(r.amount ?? 0, r.ps, r.pe, r.created_at, start, end), 0);
  const expenses = expRows.reduce((s, r) => s + spreadValue(r.amount ?? 0, r.ps, r.pe, r.created_at, start, end), 0);
  const hours = tripRows.reduce((s, r) => {
    const ms = new Date(r.ended_at).getTime() - new Date(r.started_at).getTime();
    return s + (ms > 0 ? ms / 3600000 : 0);
  }, 0);
  const takeHome = earnings - Math.max(0, earnings - deduction - expenses) * taxRate;

  return {
    period, label, rangeStart: start, rangeEnd: end,
    earnings, miles, deduction, expenses, trips: tripRows.length, hours, takeHome, taxRate,
  };
}

// Time-series for the period chart: 7 days (week), ~weekly buckets (month), or
// 12 months (year). Supports earnings / miles / hours. Today returns [].
export type SeriesPoint = { label: string; value: number };
export type SeriesMetric = 'earnings' | 'miles' | 'hours';

// Which part of the day an hour falls into (matches the Insights time buckets).
function dayPartIndex(h: number): number {
  if (h >= 5 && h < 11) return 0;   // Morning
  if (h < 14) return 1;             // Lunch
  if (h < 17) return 2;             // Afternoon
  if (h < 21) return 3;            // Evening
  return 4;                         // Late (21:00–05:00)
}
const DAY_PARTS = ['6am', '11am', '2pm', '5pm', '9pm'];

export function getPeriodSeries(period: Period, metric: SeriesMetric = 'earnings', ref = new Date()): SeriesPoint[] {
  if (period === 'today') {
    // Today has no day-by-day shape, so break it down by part of the day —
    // turns a blank card into a useful "when did I earn today" view.
    const sums = [0, 0, 0, 0, 0];
    const { start, end } = periodRange('today', ref);
    for (const t of db.getAllSync<{ started_at: string; ended_at: string; earnings: number | null; miles: number }>(
      `SELECT started_at, ended_at, earnings, miles FROM trips WHERE date(started_at) BETWEEN ? AND ?`, start, end)) {
      const idx = dayPartIndex(new Date(t.started_at).getHours());
      if (metric === 'earnings') sums[idx] += t.earnings ?? 0;
      else if (metric === 'miles') sums[idx] += t.miles;
      else { const ms = new Date(t.ended_at).getTime() - new Date(t.started_at).getTime(); sums[idx] += ms > 0 ? ms / 3600000 : 0; }
    }
    if (metric === 'earnings') {
      // Only single-day income has a time-of-day; multi-day (weekly) entries are
      // excluded from this "when today" chart (they have no hour).
      for (const r of db.getAllSync<{ created_at: string; amount: number | null }>(
        `SELECT created_at, amount FROM records WHERE record_type='income' AND period_start IS NULL AND date(created_at) BETWEEN ? AND ?`, start, end)) {
        sums[dayPartIndex(new Date(r.created_at).getHours())] += r.amount ?? 0;
      }
    }
    return DAY_PARTS.map((label, i) => ({ label, value: sums[i] }));
  }
  const { start, end } = periodRange(period, ref);
  const byDay: { [d: string]: number } = {};
  const add = (k: string, v: number) => { byDay[k] = (byDay[k] ?? 0) + v; };

  for (const t of db.getAllSync<{ started_at: string; ended_at: string; earnings: number | null; miles: number }>(
    `SELECT started_at, ended_at, earnings, miles FROM trips WHERE date(started_at) BETWEEN ? AND ?`, start, end)) {
    const k = t.started_at.slice(0, 10);
    if (metric === 'earnings') add(k, t.earnings ?? 0);
    else if (metric === 'miles') add(k, t.miles);
    else { const ms = new Date(t.ended_at).getTime() - new Date(t.started_at).getTime(); add(k, ms > 0 ? ms / 3600000 : 0); }
  }
  if (metric === 'earnings') {
    for (const r of recordsOverlapping('income', start, end)) {
      spreadIntoDays(add, r.amount ?? 0, r.ps, r.pe, r.created_at, start, end);
    }
  } else if (metric === 'miles') {
    for (const r of recordsOverlapping('mileage', start, end)) {
      spreadIntoDays(add, r.miles ?? 0, r.ps, r.pe, r.created_at, start, end);
    }
  }
  const iso = (d: Date) => d.toISOString().slice(0, 10);

  if (period === 'week') {
    const s = new Date(start);
    const L = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Array.from({ length: 7 }, (_, i) => {
      const d = new Date(s); d.setDate(s.getDate() + i);
      return { label: L[i], value: byDay[iso(d)] ?? 0 };
    });
  }

  if (period === 'month') {
    const s = new Date(start), e = new Date(end);
    const buckets: SeriesPoint[] = [];
    let cur = new Date(s);
    while (cur <= e) {
      const wkEnd = new Date(cur); wkEnd.setDate(cur.getDate() + 6);
      const last = wkEnd > e ? e : wkEnd;
      let sum = 0;
      for (let d = new Date(cur); d <= last; d.setDate(d.getDate() + 1)) sum += byDay[iso(d)] ?? 0;
      buckets.push({ label: `${cur.getDate()}–${last.getDate()}`, value: sum });
      cur = new Date(wkEnd); cur.setDate(wkEnd.getDate() + 1);
    }
    return buckets;
  }

  // year: 12 calendar months from the tax-year start (Apr → Mar)
  const byMonth: { [m: string]: number } = {};
  for (const [k, v] of Object.entries(byDay)) byMonth[k.slice(0, 7)] = (byMonth[k.slice(0, 7)] ?? 0) + v;
  const s = new Date(start);
  return Array.from({ length: 12 }, (_, i) => {
    const d = new Date(s.getFullYear(), s.getMonth() + i, 1);
    const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
    return { label: d.toLocaleDateString('en-GB', { month: 'short' })[0], value: byMonth[key] ?? 0 };
  });
}

// Per-platform breakdown for a given period — answers "which platform won this month?"
export function getPlatformStatsForPeriod(period: Period, ref = new Date()): PlatformStat[] {
  const { start, end } = periodRange(period, ref);
  const agg: { [p: string]: { miles: number; earnings: number; hours: number } } = {};
  const bump = (p: string, miles: number, earnings: number, hours: number) => {
    const key = p || 'Other';
    if (!agg[key]) agg[key] = { miles: 0, earnings: 0, hours: 0 };
    agg[key].miles += miles; agg[key].earnings += earnings; agg[key].hours += hours;
  };
  // Trips are platform-agnostic now (a day can span several apps), so they don't
  // feed the per-platform breakdown — that comes from your earnings records.
  for (const t of db.getAllSync<Trip>('SELECT * FROM trips WHERE date(started_at) BETWEEN ? AND ?', start, end)) {
    if (t.platform) bump(t.platform, t.miles, t.earnings ?? 0, tripHours(t));
  }
  for (const r of db.getAllSync<Record>(`SELECT * FROM records WHERE record_type IN ('income','mileage') AND date(created_at) BETWEEN ? AND ?`, start, end)) {
    bump(r.platform ?? 'Other', r.record_type === 'mileage' ? (r.miles ?? 0) : 0,
      r.record_type === 'income' ? (r.amount ?? 0) : 0, 0);
  }
  return Object.entries(agg)
    .map(([platform, v]) => ({
      platform, miles: v.miles, earnings: v.earnings, hours: v.hours,
      perMile: v.miles > 0 ? v.earnings / v.miles : 0,
      perHour: v.hours > 0 ? v.earnings / v.hours : 0,
    }))
    .filter(s => s.miles > 0 || s.earnings > 0)
    .sort((a, b) => b.earnings - a.earnings);
}

// UK tax year starts 6 April.
export function taxYearStart(ref = new Date()): string {
  const y = (ref.getMonth() > 3 || (ref.getMonth() === 3 && ref.getDate() >= 6))
    ? ref.getFullYear() : ref.getFullYear() - 1;
  return `${y}-04-06`;
}

// ...and ends 5 April the following year.
export function taxYearEnd(ref = new Date()): string {
  const startY = parseInt(taxYearStart(ref).slice(0, 4), 10);
  return `${startY + 1}-04-05`;
}

// Cumulative business miles this tax year — drives the 10,000-mile threshold.
export function getTaxYearMiles(): number {
  const start = taxYearStart(), end = taxYearEnd();
  const trips = db.getFirstSync<{ m: number }>(
    `SELECT COALESCE(SUM(miles),0) AS m FROM trips WHERE date(started_at) BETWEEN ? AND ?`, start, end,
  );
  // Records use period-overlap so a weekly entry spanning 6 April is split
  // correctly between tax years (not bucketed wholesale by created_at).
  let recMiles = 0;
  for (const r of recordsOverlapping('mileage', start, end)) {
    recMiles += spreadValue(r.miles ?? 0, r.ps, r.pe, r.created_at, start, end);
  }
  return (trips?.m ?? 0) + recMiles;
}

export type TaxYearSummary = {
  miles: number;
  deduction: number;
  taxSaved: number;
  earnings: number;
  taxRate: number;
};

// Cumulative tax-year figures — drives the headline "tax saved" counter.
export function getTaxYearSummary(): TaxYearSummary {
  const user = getUser();
  const taxRate = user?.tax_rate ?? 0.20;
  const start = taxYearStart(), end = taxYearEnd();

  const trips = db.getFirstSync<{ miles: number; deduction: number; earnings: number }>(
    `SELECT COALESCE(SUM(miles),0) AS miles, COALESCE(SUM(deduction),0) AS deduction,
            COALESCE(SUM(earnings),0) AS earnings
     FROM trips WHERE date(started_at) BETWEEN ? AND ?`, start, end,
  );
  // Records use period-overlap so weekly entries spanning the 6 April boundary
  // contribute only the portion that falls within this tax year.
  let recMiles = 0, recDeduction = 0, recEarnings = 0;
  for (const r of recordsOverlapping('mileage', start, end)) {
    recMiles += spreadValue(r.miles ?? 0, r.ps, r.pe, r.created_at, start, end);
    recDeduction += spreadValue(r.deduction ?? 0, r.ps, r.pe, r.created_at, start, end);
  }
  for (const r of recordsOverlapping('income', start, end)) {
    recEarnings += spreadValue(r.amount ?? 0, r.ps, r.pe, r.created_at, start, end);
  }

  const miles = (trips?.miles ?? 0) + recMiles;
  const deduction = (trips?.deduction ?? 0) + recDeduction;
  const earnings = (trips?.earnings ?? 0) + recEarnings;
  // Tax "saved" = the tax you don't pay on the mileage deduction.
  const taxSaved = deduction * taxRate;
  return { miles, deduction, taxSaved, earnings, taxRate };
}

export type PlatformStat = {
  platform: string; miles: number; earnings: number; hours: number;
  perMile: number; perHour: number;
};

function tripHours(t: Trip): number {
  const ms = new Date(t.ended_at).getTime() - new Date(t.started_at).getTime();
  return ms > 0 ? ms / 3600000 : 0;
}

// Earnings per mile AND per hour by platform — the headline analytics.
export function getPlatformStats(): PlatformStat[] {
  const agg: { [p: string]: { miles: number; earnings: number; hours: number } } = {};
  const bump = (p: string, miles: number, earnings: number, hours: number) => {
    const key = p || 'Other';
    if (!agg[key]) agg[key] = { miles: 0, earnings: 0, hours: 0 };
    agg[key].miles += miles;
    agg[key].earnings += earnings;
    agg[key].hours += hours;
  };
  for (const t of db.getAllSync<Trip>('SELECT * FROM trips')) {
    if (t.platform) bump(t.platform, t.miles, t.earnings ?? 0, tripHours(t));
  }
  for (const r of db.getAllSync<Record>(`SELECT * FROM records WHERE record_type IN ('income','mileage')`)) {
    bump(r.platform ?? 'Other', r.record_type === 'mileage' ? (r.miles ?? 0) : 0,
      r.record_type === 'income' ? (r.amount ?? 0) : 0, 0);
  }
  return Object.entries(agg)
    .map(([platform, v]) => ({
      platform, miles: v.miles, earnings: v.earnings, hours: v.hours,
      perMile: v.miles > 0 ? v.earnings / v.miles : 0,
      perHour: v.hours > 0 ? v.earnings / v.hours : 0,
    }))
    .filter(s => s.miles > 0 || s.earnings > 0)
    .sort((a, b) => b.perMile - a.perMile);
}

export type TimeBucket = { label: string; earnings: number; hours: number; trips: number; perHour: number };

// Earnings by time of day — "best hours to work" heatmap.
const TIME_BUCKETS: { label: string; from: number; to: number }[] = [
  { label: 'Morning', from: 6, to: 11 },
  { label: 'Lunch', from: 11, to: 14 },
  { label: 'Afternoon', from: 14, to: 17 },
  { label: 'Dinner', from: 17, to: 21 },
  { label: 'Late', from: 21, to: 30 }, // wraps past midnight (handled below)
];

// Estimate £ earned per trip by spreading each income record across the trips in
// its period, weighted by trip duration. Earnings are entered as period lumps
// (daily/weekly/monthly) and trips are platform-agnostic, so any per-trip / zone
// / hour £ figure is necessarily an ESTIMATE — surface it as such in the UI.
function estimatedTripEarnings(): Map<number, number> {
  const result = new Map<number, number>();
  const trips = db.getAllSync<{ id: number; started_at: string; ended_at: string }>('SELECT id, started_at, ended_at FROM trips');
  if (!trips.length) return result;
  const incomes = db.getAllSync<Record>(`SELECT * FROM records WHERE record_type='income'`);
  const dur = (t: { started_at: string; ended_at: string }) => {
    const ms = new Date(t.ended_at).getTime() - new Date(t.started_at).getTime();
    return ms > 0 ? ms / 3600000 : 0;
  };
  for (const inc of incomes) {
    const ws = (inc.period_start ?? inc.created_at ?? '').slice(0, 10);
    const we = (inc.period_end ?? inc.created_at ?? '').slice(0, 10);
    if (!ws || !we) continue;
    const inWin = trips.filter(t => { const d = t.started_at.slice(0, 10); return d >= ws && d <= we; });
    const totalH = inWin.reduce((s, t) => s + dur(t), 0);
    if (totalH <= 0) continue;
    for (const t of inWin) {
      result.set(t.id, (result.get(t.id) ?? 0) + (inc.amount ?? 0) * (dur(t) / totalH));
    }
  }
  return result;
}

function hourBucketIdx(ms: number): number {
  const h = new Date(ms).getHours();
  const norm = h < 6 ? h + 24 : h; // 0-5am wraps into the Late bucket (21-30)
  return TIME_BUCKETS.findIndex(b => norm >= b.from && norm < b.to);
}

function haversineMiles(aLat: number, aLng: number, bLat: number, bLng: number): number {
  const R = 6371, rad = (d: number) => (d * Math.PI) / 180;
  const dLat = rad(bLat - aLat), dLon = rad(bLng - aLng);
  const x = Math.sin(dLat / 2) ** 2 + Math.cos(rad(aLat)) * Math.cos(rad(bLat)) * Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(x), Math.sqrt(1 - x)) * 0.621371;
}

// Best-times analysis. For trips with timestamped GPS points we walk each segment
// and credit the real hour-of-day with its DISTANCE (activity) and its DURATION
// including waiting gaps (presence) — then apportion the trip's estimated earnings
// across hours by distance. £/hour = earnings ÷ presence, so an hour spent mostly
// waiting (high presence, low distance) correctly scores low. Trips logged before
// timestamps fall back to start-hour bucketing.
export function getEarningsByTimeOfDay(): TimeBucket[] {
  const est = estimatedTripEarnings();
  const acc = TIME_BUCKETS.map(b => ({ ...b, earnings: 0, hours: 0, trips: 0 }));
  for (const t of db.getAllSync<Trip>('SELECT * FROM trips')) {
    const E = est.get(t.id) ?? 0;
    let pts: { lat: number; lng: number; t?: number }[] = [];
    try { pts = t.route_json ? JSON.parse(t.route_json) : []; } catch { /* ignore */ }
    const timed = pts.filter(p => typeof p?.t === 'number');
    const startIdx = hourBucketIdx(new Date(t.started_at).getTime());
    if (startIdx >= 0) acc[startIdx].trips += 1;

    if (timed.length >= 2) {
      const segs: { idx: number; presence: number; dist: number }[] = [];
      let tripDist = 0;
      for (let i = 1; i < timed.length; i++) {
        const p0 = timed[i - 1], p1 = timed[i];
        const durH = (p1.t! - p0.t!) / 3600000;
        if (durH <= 0) continue;
        const idx = hourBucketIdx((p0.t! + p1.t!) / 2);
        if (idx < 0) continue;
        const dist = haversineMiles(p0.lat, p0.lng, p1.lat, p1.lng);
        // Cap a single gap at 2h so a tracking dropout can't masquerade as presence.
        segs.push({ idx, presence: Math.min(durH, 2), dist });
        tripDist += dist;
      }
      for (const sg of segs) {
        acc[sg.idx].hours += sg.presence;
        acc[sg.idx].earnings += tripDist > 0 ? E * (sg.dist / tripDist) : 0;
      }
    } else if (startIdx >= 0) {
      acc[startIdx].hours += tripHours(t);
      acc[startIdx].earnings += E;
    }
  }
  return acc.map(b => ({
    label: b.label, earnings: b.earnings, hours: b.hours, trips: b.trips,
    perHour: b.hours > 0 ? b.earnings / b.hours : 0,
  }));
}

// Total hours tracked this tax year (from trip durations).
export function getHoursWorked(): number {
  const start = taxYearStart(), end = taxYearEnd();
  const trips = db.getAllSync<Trip>('SELECT * FROM trips WHERE date(started_at) BETWEEN ? AND ?', start, end);
  return trips.reduce((s, t) => s + tripHours(t), 0);
}

// Today's total miles (saved trips) — feeds the daily goal ring.
export function getTodayMiles(): number {
  const today = new Date().toISOString().slice(0, 10);
  const row = db.getFirstSync<{ m: number }>(
    `SELECT COALESCE(SUM(miles),0) AS m FROM trips WHERE date(started_at) = ?`, today,
  );
  return row?.m ?? 0;
}

export type VehicleStat = { vehicle: string; miles: number; deduction: number; trips: number };

// Per-vehicle breakdown (multi-vehicle support).
export function getVehicleStats(): VehicleStat[] {
  const agg: { [v: string]: VehicleStat } = {};
  const bump = (v: string, miles: number, deduction: number, isTrip: boolean) => {
    const key = v || 'car';
    if (!agg[key]) agg[key] = { vehicle: key, miles: 0, deduction: 0, trips: 0 };
    agg[key].miles += miles;
    agg[key].deduction += deduction;
    if (isTrip) agg[key].trips += 1;
  };
  for (const t of db.getAllSync<Trip>('SELECT * FROM trips')) {
    bump(t.vehicle, t.miles, t.deduction, true);
  }
  for (const r of db.getAllSync<Record>(`SELECT * FROM records WHERE record_type='mileage'`)) {
    bump(r.vehicle ?? 'car', r.miles ?? 0, r.deduction ?? 0, false);
  }
  return Object.values(agg).filter(v => v.miles > 0).sort((a, b) => b.miles - a.miles);
}

export function getTrip(id: number): Trip | null {
  return db.getFirstSync<Trip>('SELECT * FROM trips WHERE id = ?', id);
}

export function updateTrip(id: number, t: Partial<Trip>) {
  const cur = getTrip(id);
  if (!cur) return;
  db.runSync(
    'UPDATE trips SET platform=?, vehicle=?, miles=?, deduction=?, earnings=?, started_at=? WHERE id=?',
    t.platform ?? cur.platform,
    t.vehicle ?? cur.vehicle,
    t.miles ?? cur.miles,
    t.deduction ?? cur.deduction,
    t.earnings ?? cur.earnings,
    t.started_at ?? cur.started_at,
    id,
  );
}

export function deleteTrip(id: number) {
  db.runSync('DELETE FROM trips WHERE id = ?', id);
}

export function getRecord(id: number): Record | null {
  return db.getFirstSync<Record>('SELECT * FROM records WHERE id = ?', id);
}

export function updateRecord(id: number, r: Partial<Record>) {
  const cur = getRecord(id);
  if (!cur) return;
  db.runSync(
    'UPDATE records SET platform=?, amount=?, miles=?, deduction=?, category=?, notes=?, vehicle=?, created_at=? WHERE id=?',
    r.platform ?? cur.platform,
    r.amount ?? cur.amount,
    r.miles ?? cur.miles,
    r.deduction ?? cur.deduction,
    r.category ?? cur.category,
    r.notes ?? cur.notes,
    r.vehicle ?? cur.vehicle ?? null,
    r.created_at ?? cur.created_at,
    id,
  );
}

export function deleteRecord(id: number) {
  db.runSync('DELETE FROM records WHERE id = ?', id);
}

// Key-value store for actual-cost method inputs etc.
export function kvGet(key: string): string | null {
  return db.getFirstSync<{ value: string }>('SELECT value FROM kv WHERE key=?', key)?.value ?? null;
}
export function kvGetNum(key: string, fallback = 0): number {
  const v = kvGet(key);
  return v == null ? fallback : (parseFloat(v) || fallback);
}
export function kvSet(key: string, value: string | number) {
  db.runSync('INSERT OR REPLACE INTO kv (key, value) VALUES (?,?)', key, String(value));
}

// Non-vehicle expense total this tax year (counts toward Self Assessment).
export function getTaxYearExpenses(): number {
  const start = taxYearStart(), end = taxYearEnd();
  let total = 0;
  for (const r of recordsOverlapping('expense', start, end)) {
    total += spreadValue(r.amount ?? 0, r.ps, r.pe, r.created_at, start, end);
  }
  return total;
}

export type QuarterSummary = {
  label: string;
  start: string;
  end: string;
  deadline: string;
  income: number;
  expenses: number;
  profit: number;
  isCurrent: boolean;
};

// MTD for Income Tax standard quarterly periods (tax year to 5 April) with the
// "1 month and 7 days after quarter end" submission deadlines.
export function getQuarterlySummaries(): QuarterSummary[] {
  const start = taxYearStart();
  const baseYear = parseInt(start.slice(0, 4), 10);
  const quarters = [
    { label: 'Q1', start: `${baseYear}-04-06`, end: `${baseYear}-07-05`, deadline: `7 Aug ${baseYear}` },
    { label: 'Q2', start: `${baseYear}-07-06`, end: `${baseYear}-10-05`, deadline: `7 Nov ${baseYear}` },
    { label: 'Q3', start: `${baseYear}-10-06`, end: `${baseYear + 1}-01-05`, deadline: `7 Feb ${baseYear + 1}` },
    { label: 'Q4', start: `${baseYear + 1}-01-06`, end: `${baseYear + 1}-04-05`, deadline: `7 May ${baseYear + 1}` },
  ];
  const today = new Date().toISOString().slice(0, 10);

  return quarters.map(q => {
    const tripInc = db.getFirstSync<{ inc: number; ded: number }>(
      `SELECT COALESCE(SUM(earnings),0) AS inc, COALESCE(SUM(deduction),0) AS ded
       FROM trips WHERE date(started_at) BETWEEN ? AND ?`, q.start, q.end);
    // Records use period-overlap so weekly entries crossing a quarter boundary
    // contribute only the portion that falls inside this quarter.
    let recIncome = 0, recMileDed = 0, recExp = 0;
    for (const r of recordsOverlapping('income', q.start, q.end))
      recIncome += spreadValue(r.amount ?? 0, r.ps, r.pe, r.created_at, q.start, q.end);
    for (const r of recordsOverlapping('mileage', q.start, q.end))
      recMileDed += spreadValue(r.deduction ?? 0, r.ps, r.pe, r.created_at, q.start, q.end);
    for (const r of recordsOverlapping('expense', q.start, q.end))
      recExp += spreadValue(r.amount ?? 0, r.ps, r.pe, r.created_at, q.start, q.end);

    const income = (tripInc?.inc ?? 0) + recIncome;
    const expenses = (tripInc?.ded ?? 0) + recMileDed + recExp;
    return {
      label: q.label, start: q.start, end: q.end, deadline: q.deadline,
      income, expenses, profit: income - expenses,
      isCurrent: today >= q.start && today <= q.end,
    };
  });
}

// ---- Gamification: streak + achievements -----------------------------------

// The longest single trip recorded so far (miles). Used to detect a new
// personal-best trip on the post-trip scorecard — call BEFORE saving the new
// trip so it returns the previous best.
export function getLongestTrip(): number {
  const r = db.getFirstSync<{ m: number }>(`SELECT COALESCE(MAX(miles),0) AS m FROM trips`);
  return r?.m ?? 0;
}

// Consecutive-day activity streak (any trip or logged entry counts).
export function getStreak(): number {
  const rows = db.getAllSync<{ d: string }>(`
    SELECT d FROM (
      SELECT DISTINCT date(started_at) AS d FROM trips
      UNION
      SELECT DISTINCT date(created_at) AS d FROM records
    ) ORDER BY d DESC`);
  const days = new Set(rows.map(r => r.d));
  if (days.size === 0) return 0;
  const iso = (dt: Date) => dt.toISOString().slice(0, 10);
  const cur = new Date();
  // Allow the streak to "hold" if there's been no activity yet today.
  if (!days.has(iso(cur))) {
    cur.setDate(cur.getDate() - 1);
    if (!days.has(iso(cur))) return 0;
  }
  let streak = 0;
  while (days.has(iso(cur))) { streak++; cur.setDate(cur.getDate() - 1); }
  return streak;
}

export type LifetimeStats = { trips: number; miles: number; deduction: number; taxSaved: number; earnings: number };

export function getLifetimeStats(): LifetimeStats {
  const rate = getUser()?.tax_rate ?? 0.20;
  const t = db.getFirstSync<{ n: number; m: number; d: number; e: number }>(
    `SELECT COUNT(*) AS n, COALESCE(SUM(miles),0) AS m, COALESCE(SUM(deduction),0) AS d, COALESCE(SUM(earnings),0) AS e FROM trips`);
  const r = db.getFirstSync<{ m: number; d: number }>(
    `SELECT COALESCE(SUM(miles),0) AS m, COALESCE(SUM(deduction),0) AS d FROM records WHERE record_type='mileage'`);
  const inc = db.getFirstSync<{ e: number }>(
    `SELECT COALESCE(SUM(amount),0) AS e FROM records WHERE record_type='income'`);
  const miles = (t?.m ?? 0) + (r?.m ?? 0);
  const deduction = (t?.d ?? 0) + (r?.d ?? 0);
  const earnings = (t?.e ?? 0) + (inc?.e ?? 0);
  return { trips: t?.n ?? 0, miles, deduction, taxSaved: deduction * rate, earnings };
}

export type AchievementTier = 'bronze' | 'silver' | 'gold' | 'special';
export type Achievement = {
  key: string; label: string; desc: string; icon: string; emoji: string;
  category: string; tier: AchievementTier;
  unlocked: boolean; progress: number; // 0..1
  target?: number; value?: number;
};

type GamiStats = {
  trips: number; miles: number; taxSaved: number; earnings: number; hours: number;
  activeDays: number; bestDayMiles: number; longestTrip: number; platforms: number;
  night: number; dawn: number; weekend: number; expenses: number; receipts: number;
};

// One pass over trips + records to compute everything the medals need.
function getGamiStats(): GamiStats {
  const rate = getUser()?.tax_rate ?? 0.20;
  const trips = db.getAllSync<Trip>('SELECT * FROM trips');
  const records = db.getAllSync<Record>('SELECT * FROM records');

  let miles = 0, deduction = 0, earnings = 0, hours = 0, night = 0, dawn = 0, weekend = 0, longestTrip = 0;
  const days = new Set<string>();
  const milesByDay: { [d: string]: number } = {};
  const platforms = new Set<string>();

  for (const t of trips) {
    miles += t.miles; deduction += t.deduction; earnings += t.earnings ?? 0;
    longestTrip = Math.max(longestTrip, t.miles);
    const d = new Date(t.started_at);
    const ms = new Date(t.ended_at).getTime() - d.getTime();
    if (ms > 0) hours += ms / 3600000;
    const hr = d.getHours(), dow = d.getDay();
    if (hr >= 22 || hr < 5) night++;
    if (hr >= 5 && hr < 8) dawn++;
    if (dow === 0 || dow === 6) weekend++;
    const ds = t.started_at.slice(0, 10);
    days.add(ds);
    milesByDay[ds] = (milesByDay[ds] ?? 0) + t.miles;
    if (t.platform) platforms.add(t.platform);
  }
  let expenses = 0, receipts = 0;
  for (const r of records) {
    days.add(r.created_at.slice(0, 10));
    if (r.record_type === 'mileage') { miles += r.miles ?? 0; deduction += r.deduction ?? 0; }
    if (r.record_type === 'income') { earnings += r.amount ?? 0; if (r.platform) platforms.add(r.platform); }
    if (r.record_type === 'expense') { expenses++; if (r.receipt_uri) receipts++; }
  }
  const bestDayMiles = Object.values(milesByDay).reduce((m, v) => Math.max(m, v), 0);

  return {
    trips: trips.length, miles, taxSaved: deduction * rate, earnings, hours,
    activeDays: days.size, bestDayMiles, longestTrip, platforms: platforms.size,
    night, dawn, weekend, expenses, receipts,
  };
}

function tierFor(i: number, n: number): AchievementTier {
  return i < n / 3 ? 'bronze' : i < (2 * n) / 3 ? 'silver' : 'gold';
}

export function getAchievements(): Achievement[] {
  const g = getGamiStats();
  const streak = getStreak();
  const packDone = kvGetNum('pack_exported') > 0;
  const backupDone = kvGetNum('backup_made') > 0;

  const out: Achievement[] = [];
  type Spec = [number, string, string]; // [threshold, label, emoji]

  // Count-based tiered medals (e.g. trips, miles).
  const tiered = (prefix: string, category: string, icon: string, unit: string, value: number, specs: Spec[], money = false) => {
    specs.forEach(([target, label, emoji], i) => {
      const amount = money ? '£' + target.toLocaleString() : target.toLocaleString();
      out.push({
        key: `${prefix}_${target}`, label,
        desc: `${amount} ${unit}`, icon, emoji, category,
        tier: tierFor(i, specs.length),
        value, target,
        unlocked: value >= target,
        progress: Math.max(0, Math.min(1, value / target)),
      });
    });
  };
  const flag = (key: string, label: string, desc: string, emoji: string, category: string, tier: AchievementTier, done: boolean) =>
    out.push({ key, label, desc, icon: 'award', emoji, category, tier, unlocked: done, progress: done ? 1 : 0 });

  tiered('trips', 'Trips', 'navigation', 'trips tracked', g.trips, [
    [1, 'First trip', '🚀'], [5, 'Five down', '🪧'], [10, 'Getting rolling', '🛵'], [25, 'Quarter ton', '📦'],
    [50, 'Seasoned rider', '🏍️'], [100, 'Centurion', '💯'], [150, 'Regular', '🔁'], [200, 'Double ton', '🎯'],
    [250, 'Road warrior', '🛡️'], [500, 'Veteran', '🏅'], [750, 'Elite', '⭐'], [1000, 'Legend', '👑'],
  ]);
  tiered('miles', 'Miles', 'map', 'business miles', g.miles, [
    [50, 'First fifty', '📍'], [100, 'First century', '🛣️'], [250, 'Pathfinder', '🧭'], [500, 'Half-grand', '🗺️'],
    [1000, 'Long hauler', '🛤️'], [2500, 'Explorer', '🌄'], [5000, 'Marathoner', '🏔️'], [7500, 'Globetrotter', '✈️'],
    [10000, 'Ten-K club', '🌍'], [15000, 'Road master', '🌟'], [20000, 'Distance demon', '🔥'], [25000, 'Odometer legend', '👑'],
  ]);
  tiered('saved', 'Tax saved', 'shield', 'saved in tax', g.taxSaved, [
    [50, 'First £50', '🪙'], [100, 'First £100', '💷'], [250, 'Saver', '💵'], [500, 'Smart saver', '💰'],
    [1000, 'Grand saver', '🤑'], [1500, 'Tactician', '🧮'], [2000, 'Optimiser', '📊'], [2500, 'Tax ninja', '🥷'],
    [5000, 'Tax wizard', '🧙'], [7500, 'Tax master', '🎩'], [10000, 'Tax legend', '👑'],
  ], true);
  tiered('earned', 'Earnings', 'dollar-sign', 'earnings logged', g.earnings, [
    [250, 'First earnings', '💵'], [500, 'Pocketing it', '💸'], [1000, 'Earner', '💲'], [2500, 'Grinder', '⚙️'],
    [5000, 'High roller', '🎰'], [10000, 'Five figures', '🏦'], [15000, 'Big league', '🏟️'], [20000, 'Boss mode', '😎'],
    [25000, 'Mogul', '🤵'], [50000, 'Tycoon', '🏰'],
  ], true);
  tiered('streak', 'Streaks', 'zap', 'day streak', streak, [
    [2, 'Two in a row', '✌️'], [3, 'Warming up', '🔥'], [5, 'On a roll', '🎲'], [7, 'One week strong', '📅'],
    [14, 'Fortnight', '🗓️'], [21, 'Habit formed', '🧠'], [30, 'Unstoppable', '⚡'], [50, 'Ironclad', '🛡️'],
    [75, 'Relentless', '🐉'], [100, 'Centurion streak', '💯'], [150, 'Machine', '🤖'], [200, 'Phenomenon', '🌠'], [365, 'Year-long legend', '👑'],
  ]);
  tiered('hours', 'Hours', 'clock', 'hours tracked', g.hours, [
    [5, 'First shift', '⏱️'], [10, 'Clocking in', '🕐'], [25, 'Grafter', '💪'], [50, 'Workhorse', '🐴'],
    [100, 'Century of hours', '💯'], [250, 'Dedicated', '🎖️'], [500, 'Tireless', '🔋'], [1000, 'Time lord', '⏳'],
  ]);
  tiered('days', 'Active days', 'calendar', 'active days', g.activeDays, [
    [3, 'Showing up', '👋'], [5, 'Reliable', '📌'], [10, 'Committed', '🤝'], [25, 'Devoted', '💚'],
    [50, 'Half-ton days', '🗓️'], [100, 'Hundred days', '💯'], [200, 'Mainstay', '🏛️'], [365, 'All year', '🎆'],
  ]);
  tiered('bestday', 'Big days', 'trending-up', 'miles in a day', g.bestDayMiles, [
    [15, 'Busy day', '📈'], [25, 'Big day', '🚀'], [40, 'Goal smasher', '🎯'], [60, 'Monster day', '💥'], [100, 'Century day', '🏆'],
  ]);
  tiered('longest', 'Long trips', 'navigation', 'miles in one trip', g.longestTrip, [
    [5, 'Long run', '🏃'], [10, 'Cross-town', '🛣️'], [15, 'The big one', '🗺️'], [25, 'Epic ride', '🏔️'], [40, 'Ultra trip', '🌟'],
  ]);
  tiered('platforms', 'Platforms', 'grid', 'platforms worked', g.platforms, [
    [2, 'Two-timer', '🔀'], [3, 'Multi-tasker', '🎯'], [4, 'Quad threat', '🃏'], [5, 'Omnipresent', '🌐'],
  ]);

  // Special one-off flags.
  flag('night_owl', 'Night owl', 'A trip after 10pm', '🦉', 'Special', 'special', g.night > 0);
  flag('early_bird', 'Early bird', 'A trip before 8am', '🌅', 'Special', 'special', g.dawn > 0);
  flag('weekend_warrior', 'Weekend warrior', 'A trip on a weekend', '🏖️', 'Special', 'special', g.weekend > 0);
  flag('first_expense', 'Bookkeeper', 'Log your first expense', '🧾', 'Special', 'bronze', g.expenses >= 1);
  flag('ten_expenses', 'Diligent', 'Log 10 expenses', '📚', 'Special', 'silver', g.expenses >= 10);
  flag('fifty_expenses', 'Meticulous', 'Log 50 expenses', '🗄️', 'Special', 'gold', g.expenses >= 50);
  flag('receipt_keeper', 'Receipt keeper', 'Attach a receipt photo', '📸', 'Special', 'bronze', g.receipts >= 1);
  flag('ten_receipts', 'Paper trail', 'Attach 10 receipts', '🖼️', 'Special', 'silver', g.receipts >= 10);
  flag('first_pack', 'Audit-ready', 'Export an Accountant Pack', '🏅', 'Special', 'gold', packDone);
  flag('first_backup', 'Safe keeper', 'Back up your data', '💾', 'Special', 'silver', backupDone);
  flag('all_rounder', 'All-rounder', 'Track, earn, expense & export', '🌈', 'Special', 'gold',
    g.trips > 0 && g.earnings > 0 && g.expenses > 0 && packDone);

  return out;
}

export function achievementCount(): number { return getAchievements().length; }

// ---- Location insights: zones + heatmap points -----------------------------

export type ZoneStat = { zone: string; trips: number; miles: number; earnings: number; deduction: number; hours: number; perHour: number };

// Time-of-day filters used by the Insights screen so people can compare where
// they earn at different parts of the day.
export type TimeFilter = 'all' | 'morning' | 'lunch' | 'afternoon' | 'dinner' | 'late';
export const TIME_FILTERS: { key: TimeFilter; label: string }[] = [
  { key: 'all', label: 'All day' },
  { key: 'morning', label: 'Morning' },
  { key: 'lunch', label: 'Lunch' },
  { key: 'afternoon', label: 'Afternoon' },
  { key: 'dinner', label: 'Dinner' },
  { key: 'late', label: 'Late' },
];

// Does a trip's start hour fall in the given filter? (local time)
function hourInFilter(startedAt: string, f: TimeFilter): boolean {
  if (f === 'all') return true;
  const h = new Date(startedAt).getHours();
  switch (f) {
    case 'morning': return h >= 6 && h < 11;
    case 'lunch': return h >= 11 && h < 14;
    case 'afternoon': return h >= 14 && h < 17;
    case 'dinner': return h >= 17 && h < 21;
    case 'late': return h >= 21 || h < 6;
  }
}

// Ranked "where you work" zones, optionally restricted to a time of day.
// Ranked by £/hour where we have the data (the actionable metric), else by
// earnings, else by miles.
export function getZoneStats(filter: TimeFilter = 'all'): ZoneStat[] {
  const est = estimatedTripEarnings(); // apportioned £ per trip (estimate)
  const rows = db.getAllSync<{ id: number; zone: string | null; miles: number; deduction: number; started_at: string; ended_at: string }>(
    `SELECT id, zone, miles, deduction, started_at, ended_at FROM trips WHERE zone IS NOT NULL AND zone <> ''`);
  const agg: { [z: string]: ZoneStat } = {};
  for (const r of rows) {
    if (!hourInFilter(r.started_at, filter)) continue;
    const z = r.zone as string;
    if (!agg[z]) agg[z] = { zone: z, trips: 0, miles: 0, earnings: 0, deduction: 0, hours: 0, perHour: 0 };
    agg[z].trips += 1;
    agg[z].miles += r.miles;
    agg[z].earnings += est.get(r.id) ?? 0;
    agg[z].deduction += r.deduction;
    const ms = new Date(r.ended_at).getTime() - new Date(r.started_at).getTime();
    agg[z].hours += ms > 0 ? ms / 3600000 : 0;
  }
  const list = Object.values(agg);
  // Only compute £/hour with real tracked time — under ~15 min it explodes into
  // nonsense (e.g. £400k/hr from a trip logged with no duration).
  for (const z of list) z.perHour = z.hours >= 0.25 ? z.earnings / z.hours : 0;
  const anyPerHour = list.some(z => z.perHour > 0);
  const anyEarnings = list.some(z => z.earnings > 0);
  return list.sort((a, b) =>
    anyPerHour ? b.perHour - a.perHour : anyEarnings ? b.earnings - a.earnings : b.miles - a.miles);
}

// The single best "where + when" combination by £/hour — the headline tip.
// vsAverage = how much more £/hour this spot earns than your overall average.
export type BestSpot = { zone: string; timeLabel: string; perHour: number; earnings: number; hours: number; trips: number; vsAverage: number };

function bucketLabel(hour: number): string {
  if (hour >= 6 && hour < 11) return 'mornings';
  if (hour >= 11 && hour < 14) return 'lunchtimes';
  if (hour >= 14 && hour < 17) return 'afternoons';
  if (hour >= 17 && hour < 21) return 'evenings';
  return 'late nights';
}

export function getBestSpot(): BestSpot | null {
  const est = estimatedTripEarnings();
  const rows = db.getAllSync<{ id: number; zone: string | null; started_at: string; ended_at: string }>(
    `SELECT id, zone, started_at, ended_at FROM trips WHERE zone IS NOT NULL AND zone <> ''`);
  const agg: { [k: string]: BestSpot } = {};
  let totalEarnings = 0, totalHours = 0;
  for (const r of rows) {
    const e = est.get(r.id) ?? 0;
    if (e <= 0) continue;
    const d = new Date(r.started_at);
    const time = bucketLabel(d.getHours());
    const key = `${r.zone}|${time}`;
    if (!agg[key]) agg[key] = { zone: r.zone as string, timeLabel: time, perHour: 0, earnings: 0, hours: 0, trips: 0, vsAverage: 0 };
    const ms = new Date(r.ended_at).getTime() - d.getTime();
    const hrs = ms > 0 ? ms / 3600000 : 0;
    agg[key].earnings += e;
    agg[key].hours += hrs;
    agg[key].trips += 1;
    totalEarnings += e;
    totalHours += hrs;
  }
  const avgPerHour = totalHours > 0 ? totalEarnings / totalHours : 0;
  const candidates = Object.values(agg)
    .filter(s => s.hours >= 0.25)
    .map(s => ({ ...s, perHour: s.earnings / s.hours, vsAverage: s.earnings / s.hours - avgPerHour }))
    .sort((a, b) => b.perHour - a.perHour);
  return candidates[0] ?? null;
}

export type HeatPoint = { lat: number; lng: number; w: number };

// All saved GPS breadcrumb points, optionally restricted to a time of day, each
// weighted (earnings/point when known, else 1). Feeds the location heatmap.
export function getHeatPoints(filter: TimeFilter = 'all'): HeatPoint[] {
  const est = estimatedTripEarnings(); // £-weight the map by apportioned earnings
  const rows = db.getAllSync<{ id: number; route_json: string | null; started_at: string }>(
    `SELECT id, route_json, started_at FROM trips WHERE route_json IS NOT NULL`);
  const out: HeatPoint[] = [];
  for (const r of rows) {
    if (!hourInFilter(r.started_at, filter)) continue;
    let pts: { lat: number; lng: number }[] = [];
    try { pts = JSON.parse(r.route_json as string); } catch { continue; }
    if (!Array.isArray(pts) || pts.length === 0) continue;
    const e = est.get(r.id) ?? 0;
    const w = e > 0 ? e / pts.length : 1;
    for (const p of pts) {
      if (typeof p?.lat === 'number' && typeof p?.lng === 'number') out.push({ lat: p.lat, lng: p.lng, w });
    }
  }
  return out;
}

// ---- XP / levels (local, no backend) ---------------------------------------
// XP rewards engagement (activity), never income — keeps it fair and private.
export type XpInfo = { xp: number; level: number; into: number; span: number; progress: number; medals: number };

export function getXp(): XpInfo {
  const ach = getAchievements();
  const medals = ach.filter(a => a.unlocked).length;
  const streak = getStreak();
  const tripsN = db.getFirstSync<{ n: number }>(`SELECT COUNT(*) AS n FROM trips`)?.n ?? 0;
  const miles = db.getFirstSync<{ m: number }>(`SELECT COALESCE(SUM(miles),0) AS m FROM trips`)?.m ?? 0;
  const expenses = db.getFirstSync<{ n: number }>(`SELECT COUNT(*) AS n FROM records WHERE record_type='expense'`)?.n ?? 0;
  const days = db.getAllSync<{ d: string }>(
    `SELECT d FROM (SELECT DISTINCT date(started_at) AS d FROM trips UNION SELECT DISTINCT date(created_at) AS d FROM records)`).length;

  const base = tripsN * 10 + days * 20 + medals * 40 + streak * 8 + Math.round(miles) + expenses * 10;
  const xp = base + kvGetNum('bonus_xp'); // bonus from completed weekly challenges

  let level = 1, need = 120, acc = 0;
  while (xp >= acc + need) { acc += need; level++; need = Math.round(need * 1.3); }
  return { xp, level, into: xp - acc, span: need, progress: (xp - acc) / need, medals };
}

// ---- Your business: year P&L (performance, lives on the Insights screen) ----
export type YearPnL = { netPerHour: number; grossPerHour: number; perMile: number; marginPct: number; hours: number; allowanceLeft: number; hasData: boolean };

export function getYearPnL(): YearPnL {
  const y = getTaxYearSummary();
  const hours = getHoursWorked();
  const expenses = getTaxYearExpenses();
  const region = getUser()?.region ?? 'ruk';
  const pos = taxPosition(y.earnings, y.deduction + expenses, region, kvGetNum('other_income'));
  const net = pos.profit - pos.totalDue;
  return {
    netPerHour: hours > 0 ? net / hours : 0,
    grossPerHour: hours > 0 ? y.earnings / hours : 0,
    perMile: y.miles > 0 ? y.earnings / y.miles : 0,
    marginPct: y.earnings > 0 ? net / y.earnings : 0,
    hours,
    allowanceLeft: Math.max(0, PERSONAL_ALLOWANCE - pos.profit),
    hasData: hours > 0 || y.earnings > 0,
  };
}

// ---- Personal records — beat your own best (real outcomes, not points) ------
export type PersonalRecord = { key: string; icon: string; tone: string; label: string; value: string; sub: string; set: boolean };

export function getPersonalRecords(): PersonalRecord[] {
  type Day = { earnings: number; miles: number; hours: number; trips: number };
  const days: { [d: string]: Day } = {};
  const touch = (d: string) => (days[d] ??= { earnings: 0, miles: 0, hours: 0, trips: 0 });

  for (const t of db.getAllSync<Trip>('SELECT * FROM trips')) {
    const d = touch(t.started_at.slice(0, 10));
    d.earnings += t.earnings ?? 0; d.miles += t.miles; d.trips += 1;
    const ms = new Date(t.ended_at).getTime() - new Date(t.started_at).getTime();
    d.hours += ms > 0 ? ms / 3600000 : 0;
  }
  for (const r of db.getAllSync<Record>(`SELECT * FROM records WHERE record_type IN ('income','mileage')`)) {
    const d = touch(r.created_at.slice(0, 10));
    if (r.record_type === 'income') d.earnings += r.amount ?? 0;
    if (r.record_type === 'mileage') d.miles += r.miles ?? 0;
  }

  const allDays = Object.entries(days);
  const best = (fn: (d: Day) => number): { v: number; date: string } =>
    allDays.reduce((acc, [date, d]) => fn(d) > acc.v ? { v: fn(d), date } : acc, { v: 0, date: '' });

  const bestDay = best(d => d.earnings);
  const mostMiles = best(d => d.miles);
  const mostTrips = best(d => d.trips);
  const bestRate = allDays
    .filter(([, d]) => d.hours > 0.5 && d.earnings > 0)
    .reduce((acc, [date, d]) => (d.earnings / d.hours > acc.v ? { v: d.earnings / d.hours, date } : acc), { v: 0, date: '' });

  // Best week (Mon–Sun) by earnings.
  const weeks: { [monday: string]: number } = {};
  for (const [date, d] of allDays) {
    const dt = new Date(date); const dow = dt.getDay(); const off = dow === 0 ? 6 : dow - 1;
    const mon = new Date(dt); mon.setDate(dt.getDate() - off);
    const key = mon.toISOString().slice(0, 10);
    weeks[key] = (weeks[key] ?? 0) + d.earnings;
  }
  const bestWeek = Object.values(weeks).reduce((m, v) => Math.max(m, v), 0);

  // Longest streak ever (consecutive active days).
  const sorted = Object.keys(days).sort();
  let longest = 0, run = 0, prev: string | null = null;
  for (const d of sorted) {
    if (prev) {
      const gap = (new Date(d).getTime() - new Date(prev).getTime()) / 86400000;
      run = gap === 1 ? run + 1 : 1;
    } else run = 1;
    longest = Math.max(longest, run); prev = d;
  }

  const dateStr = (iso: string) => iso ? new Date(iso).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' }) : '';
  return [
    { key: 'best_day', icon: 'dollar-sign', tone: 'green', label: 'Best day', value: fmtGbp(bestDay.v), sub: bestDay.date ? `on ${dateStr(bestDay.date)}` : 'Not set yet', set: bestDay.v > 0 },
    { key: 'best_week', icon: 'calendar', tone: 'blue', label: 'Best week', value: fmtGbp(bestWeek), sub: bestWeek > 0 ? 'earnings in a week' : 'Not set yet', set: bestWeek > 0 },
    { key: 'best_rate', icon: 'zap', tone: 'amber', label: 'Best £/hour', value: bestRate.v > 0 ? fmtPerHour(bestRate.v) : '—', sub: bestRate.date ? `on ${dateStr(bestRate.date)}` : 'Track a trip + pay', set: bestRate.v > 0 },
    { key: 'most_miles', icon: 'map', tone: 'mint', label: 'Most miles in a day', value: mostMiles.v > 0 ? fmtMiles(mostMiles.v) : '—', sub: mostMiles.date ? `on ${dateStr(mostMiles.date)}` : 'Not set yet', set: mostMiles.v > 0 },
    { key: 'longest_streak', icon: 'trending-up', tone: 'red', label: 'Longest streak', value: longest > 0 ? `${longest} ${longest === 1 ? 'day' : 'days'}` : '—', sub: longest > 0 ? 'in a row' : 'Track daily to build it', set: longest > 0 },
    { key: 'most_trips', icon: 'navigation', tone: 'violet', label: 'Most trips in a day', value: mostTrips.v > 0 ? String(mostTrips.v) : '—', sub: mostTrips.date ? `on ${dateStr(mostTrips.date)}` : 'Not set yet', set: mostTrips.v > 0 },
  ];
}

// ---- Weekly challenges (local, reset implicitly each week) ------------------
export type Challenge = { key: string; label: string; icon: string; tone: string; value: number; target: number; progress: number; done: boolean; xp: number };

export function getWeeklyChallenges(): Challenge[] {
  const w = getPeriodSummary('week');
  const streak = getStreak();
  const defs: [string, string, string, string, number, number, number][] = [
    ['trips', 'Track 5 trips', 'navigation', 'mint', w.trips, 5, 100],
    ['miles', 'Cover 50 miles', 'map', 'blue', Math.round(w.miles), 50, 100],
    ['streak', 'Keep a 5-day streak', 'zap', 'amber', streak, 5, 150],
    ['pay', 'Log your weekly pay', 'dollar-sign', 'green', w.earnings > 0 ? 1 : 0, 1, 80],
  ];
  return defs.map(([key, label, icon, tone, value, target, xp]) => ({
    key, label, icon, tone, value, target, xp,
    progress: Math.max(0, Math.min(1, value / target)),
    done: value >= target,
  }));
}

// Credit XP for challenges completed this week (once each). Old-week entries are
// pruned automatically so the ledger stays small. Returns XP newly awarded.
export function creditCompletedChallenges(): number {
  const weekStart = periodRange('week').start;
  const credited = new Set((kvGet('chall_credited') ?? '').split(',').filter(s => s.startsWith(weekStart)));
  let added = 0;
  for (const c of getWeeklyChallenges()) {
    const id = `${weekStart}:${c.key}`;
    if (c.done && !credited.has(id)) { credited.add(id); added += c.xp; }
  }
  if (added > 0) {
    kvSet('chall_credited', [...credited].join(','));
    kvSet('bonus_xp', kvGetNum('bonus_xp') + added);
  }
  return added;
}

// Returns achievements newly unlocked since last check, and marks them seen.
export function popNewAchievements(): Achievement[] {
  const seen = new Set((kvGet('ach_seen') ?? '').split(',').filter(Boolean));
  const justUnlocked = getAchievements().filter(a => a.unlocked && !seen.has(a.key));
  if (justUnlocked.length) {
    justUnlocked.forEach(a => seen.add(a.key));
    kvSet('ach_seen', [...seen].join(','));
  }
  return justUnlocked;
}

export type DailyStats = {
  miles: number;
  deduction: number;
  earnings: number;
  trips: number;
  hours: number;
};

export function getDailyStats(dateStr?: string): DailyStats {
  const d = dateStr ?? new Date().toISOString().slice(0, 10);
  const tripRows = db.getAllSync<{ miles: number; deduction: number; earnings: number | null; started_at: string; ended_at: string }>(
    `SELECT miles, deduction, earnings, started_at, ended_at FROM trips WHERE date(started_at) = ?`, d,
  );
  const incRows = recordsOverlapping('income', d, d);
  const miles = tripRows.reduce((s, r) => s + r.miles, 0);
  const deduction = tripRows.reduce((s, r) => s + r.deduction, 0);
  const tripEarnings = tripRows.reduce((s, r) => s + (r.earnings ?? 0), 0);
  const manualEarnings = incRows.reduce((s, r) => s + spreadValue(r.amount ?? 0, r.ps, r.pe, r.created_at, d, d), 0);
  const hours = tripRows.reduce((s, r) => {
    const ms = new Date(r.ended_at).getTime() - new Date(r.started_at).getTime();
    return s + (ms > 0 ? ms / 3600000 : 0);
  }, 0);
  return { miles, deduction, earnings: tripEarnings + manualEarnings, trips: tripRows.length, hours };
}

export function resetAllData() {
  db.execSync('DELETE FROM trips; DELETE FROM records; DELETE FROM user; DELETE FROM kv;');
}

export const BACKUP_VERSION = 1;

export type BackupPayload = {
  app: 'okkle';
  version: number;
  exportedAt: string;
  user: User | null;
  trips: Trip[];
  records: Record[];
  kv: { key: string; value: string }[];
};

export function dumpData(): BackupPayload {
  return {
    app: 'okkle',
    version: BACKUP_VERSION,
    exportedAt: new Date().toISOString(),
    user: getUser(),
    trips: db.getAllSync<Trip>('SELECT * FROM trips'),
    records: db.getAllSync<Record>('SELECT * FROM records'),
    kv: db.getAllSync<{ key: string; value: string }>('SELECT * FROM kv'),
  };
}

export function restoreData(p: BackupPayload) {
  if (p?.app !== 'okkle' || !Array.isArray(p.trips) || !Array.isArray(p.records)) {
    throw new Error('Not a valid Okkle backup file');
  }
  db.withTransactionSync(() => {
    db.execSync('DELETE FROM trips; DELETE FROM records; DELETE FROM user; DELETE FROM kv;');

    if (p.user) {
      saveUser({
        name: p.user.name, vehicle: p.user.vehicle, vehicles: p.user.vehicles,
        tax_rate: p.user.tax_rate,
        region: p.user.region, platforms: p.user.platforms,
        reminder_enabled: p.user.reminder_enabled, reminder_day: p.user.reminder_day,
        log_frequency: p.user.log_frequency, onboarded: p.user.onboarded,
      });
    }
    for (const t of p.trips) {
      db.runSync(
        `INSERT INTO trips (platform, vehicle, miles, deduction, earnings, started_at, ended_at, route_json, zone, created_at)
         VALUES (?,?,?,?,?,?,?,?,?,?)`,
        t.platform, t.vehicle, t.miles, t.deduction, t.earnings ?? null,
        t.started_at, t.ended_at, (t as any).route_json ?? null, (t as any).zone ?? null, t.created_at,
      );
    }
    for (const r of p.records) {
      db.runSync(
        `INSERT INTO records (record_type, platform, amount, miles, deduction, category,
          period_start, period_end, receipt_uri, notes, vehicle, created_at)
         VALUES (?,?,?,?,?,?,?,?,?,?,?,?)`,
        r.record_type, r.platform ?? null, r.amount ?? null, r.miles ?? null,
        r.deduction ?? null, r.category ?? null, r.period_start ?? null,
        r.period_end ?? null, r.receipt_uri ?? null, r.notes ?? null, r.vehicle ?? null, r.created_at,
      );
    }
    for (const row of (p.kv ?? [])) {
      db.runSync('INSERT OR REPLACE INTO kv (key, value) VALUES (?,?)', row.key, row.value);
    }
  });
}

initDb();

export { db };
