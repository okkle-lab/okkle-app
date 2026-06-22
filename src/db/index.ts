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

export type PlatformStat = { platform: string; miles: number; earnings: number; perMile: number };

// Earnings-per-mile by platform — the headline analytic competitors lack.
export function getPlatformStats(): PlatformStat[] {
  const agg: { [p: string]: { miles: number; earnings: number } } = {};
  const bump = (p: string, miles: number, earnings: number) => {
    const key = p || 'Other';
    if (!agg[key]) agg[key] = { miles: 0, earnings: 0 };
    agg[key].miles += miles;
    agg[key].earnings += earnings;
  };
  for (const t of db.getAllSync<Trip>('SELECT * FROM trips')) {
    bump(t.platform, t.miles, t.earnings ?? 0);
  }
  for (const r of db.getAllSync<Record>(`SELECT * FROM records WHERE record_type IN ('income','mileage')`)) {
    bump(r.platform ?? 'Other', r.record_type === 'mileage' ? (r.miles ?? 0) : 0,
      r.record_type === 'income' ? (r.amount ?? 0) : 0);
  }
  return Object.entries(agg)
    .map(([platform, v]) => ({
      platform, miles: v.miles, earnings: v.earnings,
      perMile: v.miles > 0 ? v.earnings / v.miles : 0,
    }))
    .filter(s => s.miles > 0 || s.earnings > 0)
    .sort((a, b) => b.perMile - a.perMile);
}

export function resetAllData() {
  db.execSync('DELETE FROM trips; DELETE FROM records; DELETE FROM user;');
}

initDb();

export { db };
