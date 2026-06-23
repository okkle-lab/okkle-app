import * as SQLite from 'expo-sqlite';

const db = SQLite.openDatabaseSync('okkle.db');

export function initDb() {
  db.execSync(`
    CREATE TABLE IF NOT EXISTS user (
      id INTEGER PRIMARY KEY,
      name TEXT,
      vehicle TEXT DEFAULT 'car',
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
  ];
  for (const sql of migrations) {
    try { db.execSync(sql); } catch { /* column already present */ }
  }
}

export type User = {
  id: number;
  name: string;
  vehicle: string;
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
  created_at: string;
};

export function getUser(): User | null {
  return db.getFirstSync<User>('SELECT * FROM user LIMIT 1');
}

export function saveUser(u: Partial<User>) {
  const existing = getUser();
  if (existing) {
    db.runSync(
      `UPDATE user SET name=?, vehicle=?, tax_rate=?, region=?, platforms=?,
        reminder_enabled=?, reminder_day=?, log_frequency=?, onboarded=? WHERE id=?`,
      u.name ?? existing.name,
      u.vehicle ?? existing.vehicle,
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
      `INSERT INTO user (name, vehicle, tax_rate, region, platforms,
        reminder_enabled, reminder_day, log_frequency, onboarded)
       VALUES (?,?,?,?,?,?,?,?,?)`,
      u.name ?? '',
      u.vehicle ?? 'car',
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

export function saveRecord(r: Omit<Record, 'id' | 'created_at'>) {
  db.runSync(
    `INSERT INTO records (record_type, platform, amount, miles, deduction, category,
      period_start, period_end, receipt_uri, notes)
     VALUES (?,?,?,?,?,?,?,?,?,?)`,
    r.record_type, r.platform ?? null, r.amount ?? null, r.miles ?? null,
    r.deduction ?? null, r.category ?? null, r.period_start ?? null,
    r.period_end ?? null, r.receipt_uri ?? null, r.notes ?? null,
  );
}

export function getRecords(limit = 100): Record[] {
  return db.getAllSync<Record>('SELECT * FROM records ORDER BY created_at DESC LIMIT ?', limit);
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

export function getPeriodSummary(period: Period, ref = new Date()): PeriodSummary {
  const user = getUser();
  const taxRate = user?.tax_rate ?? 0.20;
  const { start, end, label } = periodRange(period, ref);

  const tripRows = db.getAllSync<{ miles: number; deduction: number; earnings: number | null; started_at: string; ended_at: string }>(
    `SELECT miles, deduction, earnings, started_at, ended_at FROM trips WHERE date(started_at) BETWEEN ? AND ?`, start, end,
  );
  const incomeRows = db.getAllSync<{ amount: number }>(
    `SELECT amount FROM records WHERE record_type='income' AND date(created_at) BETWEEN ? AND ?`, start, end,
  );
  const mileRows = db.getAllSync<{ miles: number; deduction: number }>(
    `SELECT miles, deduction FROM records WHERE record_type='mileage' AND date(created_at) BETWEEN ? AND ?`, start, end,
  );
  const expRow = db.getFirstSync<{ exp: number }>(
    `SELECT COALESCE(SUM(amount),0) AS exp FROM records WHERE record_type='expense' AND date(created_at) BETWEEN ? AND ?`, start, end,
  );

  const miles = tripRows.reduce((s, r) => s + r.miles, 0) + mileRows.reduce((s, r) => s + r.miles, 0);
  const deduction = tripRows.reduce((s, r) => s + r.deduction, 0) + mileRows.reduce((s, r) => s + (r.deduction ?? 0), 0);
  const earnings = tripRows.reduce((s, r) => s + (r.earnings ?? 0), 0) + incomeRows.reduce((s, r) => s + (r.amount ?? 0), 0);
  const expenses = expRow?.exp ?? 0;
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

// Per-platform breakdown for a given period — answers "which platform won this month?"
export function getPlatformStatsForPeriod(period: Period, ref = new Date()): PlatformStat[] {
  const { start, end } = periodRange(period, ref);
  const agg: { [p: string]: { miles: number; earnings: number; hours: number } } = {};
  const bump = (p: string, miles: number, earnings: number, hours: number) => {
    const key = p || 'Other';
    if (!agg[key]) agg[key] = { miles: 0, earnings: 0, hours: 0 };
    agg[key].miles += miles; agg[key].earnings += earnings; agg[key].hours += hours;
  };
  for (const t of db.getAllSync<Trip>('SELECT * FROM trips WHERE date(started_at) BETWEEN ? AND ?', start, end)) {
    bump(t.platform, t.miles, t.earnings ?? 0, tripHours(t));
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

// Cumulative business miles this tax year — drives the 10,000-mile threshold.
export function getTaxYearMiles(): number {
  const start = taxYearStart();
  const trips = db.getFirstSync<{ m: number }>(
    `SELECT COALESCE(SUM(miles),0) AS m FROM trips WHERE date(started_at) >= ?`, start,
  );
  const recs = db.getFirstSync<{ m: number }>(
    `SELECT COALESCE(SUM(miles),0) AS m FROM records WHERE record_type='mileage' AND date(created_at) >= ?`, start,
  );
  return (trips?.m ?? 0) + (recs?.m ?? 0);
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
  const start = taxYearStart();

  const trips = db.getFirstSync<{ miles: number; deduction: number; earnings: number }>(
    `SELECT COALESCE(SUM(miles),0) AS miles, COALESCE(SUM(deduction),0) AS deduction,
            COALESCE(SUM(earnings),0) AS earnings
     FROM trips WHERE date(started_at) >= ?`, start,
  );
  const mil = db.getFirstSync<{ miles: number; deduction: number }>(
    `SELECT COALESCE(SUM(miles),0) AS miles, COALESCE(SUM(deduction),0) AS deduction
     FROM records WHERE record_type='mileage' AND date(created_at) >= ?`, start,
  );
  const inc = db.getFirstSync<{ earnings: number }>(
    `SELECT COALESCE(SUM(amount),0) AS earnings
     FROM records WHERE record_type='income' AND date(created_at) >= ?`, start,
  );

  const miles = (trips?.miles ?? 0) + (mil?.miles ?? 0);
  const deduction = (trips?.deduction ?? 0) + (mil?.deduction ?? 0);
  const earnings = (trips?.earnings ?? 0) + (inc?.earnings ?? 0);
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
    bump(t.platform, t.miles, t.earnings ?? 0, tripHours(t));
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

export function getEarningsByTimeOfDay(): TimeBucket[] {
  const acc = TIME_BUCKETS.map(b => ({ ...b, earnings: 0, hours: 0, trips: 0 }));
  for (const t of db.getAllSync<Trip>('SELECT * FROM trips')) {
    const h = new Date(t.started_at).getHours();
    const hourNorm = h < 6 ? h + 24 : h; // group 0-5am into the Late bucket (21-30)
    const idx = acc.findIndex(b => hourNorm >= b.from && hourNorm < b.to);
    if (idx >= 0) {
      acc[idx].earnings += t.earnings ?? 0;
      acc[idx].hours += tripHours(t);
      acc[idx].trips += 1;
    }
  }
  return acc.map(b => ({
    label: b.label, earnings: b.earnings, hours: b.hours, trips: b.trips,
    perHour: b.hours > 0 ? b.earnings / b.hours : 0,
  }));
}

// Total hours tracked this tax year (from trip durations).
export function getHoursWorked(): number {
  const start = taxYearStart();
  const trips = db.getAllSync<Trip>('SELECT * FROM trips WHERE date(started_at) >= ?', start);
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
    bump((r as any).vehicle ?? 'car', r.miles ?? 0, r.deduction ?? 0, false);
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
    'UPDATE trips SET platform=?, vehicle=?, miles=?, deduction=?, earnings=? WHERE id=?',
    t.platform ?? cur.platform,
    t.vehicle ?? cur.vehicle,
    t.miles ?? cur.miles,
    t.deduction ?? cur.deduction,
    t.earnings ?? cur.earnings,
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
    'UPDATE records SET platform=?, amount=?, miles=?, deduction=?, category=?, notes=? WHERE id=?',
    r.platform ?? cur.platform,
    r.amount ?? cur.amount,
    r.miles ?? cur.miles,
    r.deduction ?? cur.deduction,
    r.category ?? cur.category,
    r.notes ?? cur.notes,
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
  const start = taxYearStart();
  const row = db.getFirstSync<{ t: number }>(
    `SELECT COALESCE(SUM(amount),0) AS t FROM records
     WHERE record_type='expense' AND date(created_at) >= ?`, start,
  );
  return row?.t ?? 0;
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
    const recInc = db.getFirstSync<{ inc: number }>(
      `SELECT COALESCE(SUM(amount),0) AS inc FROM records
       WHERE record_type='income' AND date(created_at) BETWEEN ? AND ?`, q.start, q.end);
    const recMileDed = db.getFirstSync<{ ded: number }>(
      `SELECT COALESCE(SUM(deduction),0) AS ded FROM records
       WHERE record_type='mileage' AND date(created_at) BETWEEN ? AND ?`, q.start, q.end);
    const recExp = db.getFirstSync<{ exp: number }>(
      `SELECT COALESCE(SUM(amount),0) AS exp FROM records
       WHERE record_type='expense' AND date(created_at) BETWEEN ? AND ?`, q.start, q.end);

    const income = (tripInc?.inc ?? 0) + (recInc?.inc ?? 0);
    const expenses = (tripInc?.ded ?? 0) + (recMileDed?.ded ?? 0) + (recExp?.exp ?? 0);
    return {
      label: q.label, start: q.start, end: q.end, deadline: q.deadline,
      income, expenses, profit: income - expenses,
      isCurrent: today >= q.start && today <= q.end,
    };
  });
}

// ---- Gamification: streak + achievements -----------------------------------

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

export type ZoneStat = { zone: string; trips: number; miles: number; earnings: number; deduction: number };

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
export function getZoneStats(filter: TimeFilter = 'all'): ZoneStat[] {
  const rows = db.getAllSync<{ zone: string | null; miles: number; earnings: number | null; deduction: number; started_at: string }>(
    `SELECT zone, miles, earnings, deduction, started_at FROM trips WHERE zone IS NOT NULL AND zone <> ''`);
  const agg: { [z: string]: ZoneStat } = {};
  for (const r of rows) {
    if (!hourInFilter(r.started_at, filter)) continue;
    const z = r.zone as string;
    if (!agg[z]) agg[z] = { zone: z, trips: 0, miles: 0, earnings: 0, deduction: 0 };
    agg[z].trips += 1;
    agg[z].miles += r.miles;
    agg[z].earnings += r.earnings ?? 0;
    agg[z].deduction += r.deduction;
  }
  const anyEarnings = Object.values(agg).some(z => z.earnings > 0);
  return Object.values(agg).sort((a, b) => anyEarnings ? b.earnings - a.earnings : b.miles - a.miles);
}

export type HeatPoint = { lat: number; lng: number; w: number };

// All saved GPS breadcrumb points, optionally restricted to a time of day, each
// weighted (earnings/point when known, else 1). Feeds the location heatmap.
export function getHeatPoints(filter: TimeFilter = 'all'): HeatPoint[] {
  const rows = db.getAllSync<{ route_json: string | null; earnings: number | null; started_at: string }>(
    `SELECT route_json, earnings, started_at FROM trips WHERE route_json IS NOT NULL`);
  const out: HeatPoint[] = [];
  for (const r of rows) {
    if (!hourInFilter(r.started_at, filter)) continue;
    let pts: { lat: number; lng: number }[] = [];
    try { pts = JSON.parse(r.route_json as string); } catch { continue; }
    if (!Array.isArray(pts) || pts.length === 0) continue;
    const w = (r.earnings && r.earnings > 0) ? r.earnings / pts.length : 1;
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

// ---- Weekly challenges (local, reset implicitly each week) ------------------
export type Challenge = { key: string; label: string; emoji: string; value: number; target: number; progress: number; done: boolean; xp: number };

export function getWeeklyChallenges(): Challenge[] {
  const w = getPeriodSummary('week');
  const streak = getStreak();
  const defs: [string, string, string, number, number, number][] = [
    ['trips', 'Track 5 trips', '🛵', w.trips, 5, 100],
    ['miles', 'Cover 50 miles', '🛣️', Math.round(w.miles), 50, 100],
    ['streak', 'Keep a 5-day streak', '🔥', streak, 5, 150],
    ['pay', 'Log your weekly pay', '💷', w.earnings > 0 ? 1 : 0, 1, 80],
  ];
  return defs.map(([key, label, emoji, value, target, xp]) => ({
    key, label, emoji, value, target, xp,
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
  const incRows = db.getAllSync<{ amount: number }>(
    `SELECT amount FROM records WHERE record_type='income' AND date(created_at) = ?`, d,
  );
  const miles = tripRows.reduce((s, r) => s + r.miles, 0);
  const deduction = tripRows.reduce((s, r) => s + r.deduction, 0);
  const tripEarnings = tripRows.reduce((s, r) => s + (r.earnings ?? 0), 0);
  const manualEarnings = incRows.reduce((s, r) => s + (r.amount ?? 0), 0);
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
        name: p.user.name, vehicle: p.user.vehicle, tax_rate: p.user.tax_rate,
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
          period_start, period_end, receipt_uri, notes, created_at)
         VALUES (?,?,?,?,?,?,?,?,?,?,?)`,
        r.record_type, r.platform ?? null, r.amount ?? null, r.miles ?? null,
        r.deduction ?? null, r.category ?? null, r.period_start ?? null,
        r.period_end ?? null, r.receipt_uri ?? null, r.notes ?? null, r.created_at,
      );
    }
    for (const row of (p.kv ?? [])) {
      db.runSync('INSERT OR REPLACE INTO kv (key, value) VALUES (?,?)', row.key, row.value);
    }
  });
}

initDb();

export { db };
