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
    `INSERT INTO trips (platform, vehicle, miles, deduction, earnings, started_at, ended_at)
     VALUES (?,?,?,?,?,?,?)`,
    t.platform, t.vehicle, t.miles, t.deduction, t.earnings ?? null,
    t.started_at, t.ended_at,
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
        `INSERT INTO trips (platform, vehicle, miles, deduction, earnings, started_at, ended_at, route_json, created_at)
         VALUES (?,?,?,?,?,?,?,?,?)`,
        t.platform, t.vehicle, t.miles, t.deduction, t.earnings ?? null,
        t.started_at, t.ended_at, (t as any).route_json ?? null, t.created_at,
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
