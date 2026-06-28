import * as Location from 'expo-location';
import * as TaskManager from 'expo-task-manager';
import * as Notifications from 'expo-notifications';
import { calcDeduction } from './db/tax';
import { kvGet, kvSet } from './db';
import { setTripActive, suspendAutoTripUpdates, resumeAutoTripUpdates } from './autoTrip';

// ---------------------------------------------------------------------------
// Persistent, background-capable trip tracking.
//
// The live trip is stored in the kv table (SQLite) — NOT just in React state —
// so it survives leaving the Trip screen, backgrounding the app, the phone
// locking, and even the app being killed by iOS. A registered background
// location task keeps accumulating GPS while suspended, writing straight to the
// same kv record. The UI just reads that record once a second.
// ---------------------------------------------------------------------------

export const TRIP_TRACK_TASK = 'okkle-trip-track';
const ACTIVE_TRIP_KEY = 'active_trip';

const TRIP_NOTIF_ID = 'okkle-trip-active';
const TRIP_END_NUDGE_ID = 'okkle-trip-end-nudge';
const END_NUDGE_AFTER_S = 18 * 60; // ask "finished?" ~18 min after last movement

const MAX_GPS_ACCURACY_M = 45;
const MAX_REASONABLE_SPEED_MPS = 45; // ~100mph; above this is almost certainly a GPS jump

export type TripState = 'idle' | 'running' | 'paused';
export type GeoPoint = { lat: number; lng: number; t?: number };

export type LiveTrip = {
  state: TripState;
  platform: string;
  vehicle: string;
  miles: number;
  deduction: number;
  elapsedSeconds: number;
  speedMph: number;
  startedAt: Date | null;
  points?: GeoPoint[];
};

// What we actually persist between GPS updates.
type StoredPos = { lat: number; lng: number; t: number; acc: number | null; speed: number | null };
type ActiveTrip = {
  state: 'running' | 'paused';
  vehicle: string;
  startedAt: number;        // ms epoch
  pausedMs: number;         // total time spent paused
  pausedAt: number | null;  // ms when the current pause began
  miles: number;
  deduction: number;
  speedMph: number;
  points: GeoPoint[];       // downsampled breadcrumb for the map/heatmap
  lastPos: StoredPos | null;
  lastSample: { lat: number; lng: number } | null;
  lastMoveAt: number;
};

// --- persistence -----------------------------------------------------------
function readActive(): ActiveTrip | null {
  const raw = kvGet(ACTIVE_TRIP_KEY);
  if (!raw) return null;
  try { return JSON.parse(raw) as ActiveTrip; } catch { return null; }
}
function writeActive(t: ActiveTrip) { kvSet(ACTIVE_TRIP_KEY, JSON.stringify(t)); }
function clearActive() { kvSet(ACTIVE_TRIP_KEY, ''); }

export function hasActiveTrip(): boolean { return readActive() != null; }

function elapsedSeconds(t: ActiveTrip): number {
  const now = Date.now();
  const paused = t.pausedMs + (t.state === 'paused' && t.pausedAt ? now - t.pausedAt : 0);
  return Math.max(0, Math.floor((now - t.startedAt - paused) / 1000));
}

// --- geo helpers -----------------------------------------------------------
function haversineKm(a: { lat: number; lng: number }, b: { lat: number; lng: number }): number {
  const R = 6371;
  const dLat = deg2rad(b.lat - a.lat);
  const dLon = deg2rad(b.lng - a.lng);
  const x =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(deg2rad(a.lat)) * Math.cos(deg2rad(b.lat)) * Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(x), Math.sqrt(1 - x));
}
function deg2rad(d: number) { return d * (Math.PI / 180); }

function usable(c: Location.LocationObjectCoords): boolean {
  if (!Number.isFinite(c.latitude) || !Number.isFinite(c.longitude)) return false;
  if (c.accuracy != null && c.accuracy > MAX_GPS_ACCURACY_M) return false;
  if (c.speed != null && c.speed > MAX_REASONABLE_SPEED_MPS) return false;
  return true;
}

// Apply a batch of locations to the active trip (mutates `t`). Same filtering as
// before: drop bad fixes, ignore GPS jumps, don't count stationary jitter.
function ingest(t: ActiveTrip, locs: Location.LocationObject[]): { moved: boolean } {
  let moved = false;
  for (const loc of locs) {
    const c = loc.coords;
    if (!usable(c)) continue;
    const ts = loc.timestamp || Date.now();
    const spd = c.speed; // m/s; -1 or null when unknown
    const mph = spd != null && spd > 0 ? spd * 2.236936 : 0;
    const here = { lat: c.latitude, lng: c.longitude };

    if (t.lastPos) {
      const d = haversineKm(t.lastPos, here);
      const meters = d * 1000;
      const seconds = Math.max(1, (ts - t.lastPos.t) / 1000);
      if (meters / seconds > MAX_REASONABLE_SPEED_MPS) continue; // jumpy fix — skip
      const noiseFloor = Math.max(8, Math.min(30, ((t.lastPos.acc ?? 12) + (c.accuracy ?? 12)) / 2));
      const stationary = (spd != null && spd >= 0 && spd < 0.5) || meters < noiseFloor;
      if (!stationary) { t.miles += d * 0.621371; moved = true; t.lastMoveAt = ts; }
    }
    t.speedMph = mph;

    // Breadcrumb: keep a point roughly every 40m, capped so storage stays tiny.
    const farEnough = !t.lastSample || haversineKm(t.lastSample, here) * 1000 >= 40;
    if (farEnough && t.points.length < 400) {
      t.points.push({ lat: +here.lat.toFixed(5), lng: +here.lng.toFixed(5), t: ts });
      t.lastSample = here;
    }
    t.lastPos = { lat: here.lat, lng: here.lng, t: ts, acc: c.accuracy ?? null, speed: spd ?? null };
  }
  t.deduction = calcDeduction(t.miles, t.vehicle);
  return { moved };
}

// --- the background task ----------------------------------------------------
// Defined at module load so the headless background context can run it too.
TaskManager.defineTask(TRIP_TRACK_TASK, async ({ data, error }: any) => {
  if (error) return;
  const locations: Location.LocationObject[] = data?.locations ?? [];
  if (!locations.length) return;
  const t = readActive();
  if (!t || t.state !== 'running') return;
  const { moved } = ingest(t, locations);
  writeActive(t);
  if (moved) armEndNudge(); // push the "finished?" nudge back on movement
});

// --- lock-screen notification + end nudge ----------------------------------
function showTripNotification() {
  Notifications.scheduleNotificationAsync({
    identifier: TRIP_NOTIF_ID,
    content: {
      title: 'Tracking your trip',
      body: 'GPS is logging your miles. Tap to view.',
      data: { type: 'tripActive' },
      sticky: true,
    },
    trigger: null,
  }).catch(() => {});
}
function clearTripNotification() {
  Notifications.dismissNotificationAsync(TRIP_NOTIF_ID).catch(() => {});
  Notifications.cancelScheduledNotificationAsync(TRIP_NOTIF_ID).catch(() => {});
}
function armEndNudge() {
  Notifications.cancelScheduledNotificationAsync(TRIP_END_NUDGE_ID).catch(() => {});
  Notifications.scheduleNotificationAsync({
    identifier: TRIP_END_NUDGE_ID,
    content: {
      title: 'Finished this trip?',
      body: 'You’ve been parked a while — tap to end and save your miles.',
      data: { type: 'tripEnd' },
    },
    trigger: { type: Notifications.SchedulableTriggerInputTypes.TIME_INTERVAL, seconds: END_NUDGE_AFTER_S },
  }).catch(() => {});
}
function cancelEndNudge() {
  Notifications.cancelScheduledNotificationAsync(TRIP_END_NUDGE_ID).catch(() => {});
}

// --- location updates lifecycle --------------------------------------------
async function startUpdates() {
  const already = await Location.hasStartedLocationUpdatesAsync(TRIP_TRACK_TASK).catch(() => false);
  if (already) return;
  // Only one location task should be live — stand down the low-power detector.
  await suspendAutoTripUpdates();
  await Location.startLocationUpdatesAsync(TRIP_TRACK_TASK, {
    accuracy: Location.Accuracy.BestForNavigation,
    activityType: Location.ActivityType.AutomotiveNavigation,
    distanceInterval: 15,             // metres between updates
    pausesUpdatesAutomatically: false, // keep logging the whole trip
    showsBackgroundLocationIndicator: true,
    foregroundService: {
      notificationTitle: 'Okkle — tracking your trip',
      notificationBody: 'GPS is logging your miles.',
    },
  });
}
async function stopUpdates() {
  const started = await Location.hasStartedLocationUpdatesAsync(TRIP_TRACK_TASK).catch(() => false);
  if (started) await Location.stopLocationUpdatesAsync(TRIP_TRACK_TASK).catch(() => {});
}

// If a trip is persisted as running but the OS isn't delivering updates (app was
// killed and relaunched), restart them so tracking resumes seamlessly.
export async function ensureUpdatesRunning(): Promise<void> {
  const t = readActive();
  if (t?.state === 'running') await startUpdates().catch(() => {});
}

// --- public control surface -------------------------------------------------
export async function trackerStart(vehicle: string): Promise<void> {
  const { status } = await Location.requestForegroundPermissionsAsync();
  if (status !== 'granted') throw new Error('Location permission denied');
  // Background permission lets tracking continue when the phone is locked.
  try { await Location.requestBackgroundPermissionsAsync(); } catch { /* ignore */ }

  const t: ActiveTrip = {
    state: 'running', vehicle, startedAt: Date.now(), pausedMs: 0, pausedAt: null,
    miles: 0, deduction: 0, speedMph: 0, points: [], lastPos: null, lastSample: null,
    lastMoveAt: Date.now(),
  };
  writeActive(t);
  setTripActive(true); // pause auto-trip suggestions while we track
  await startUpdates();
  showTripNotification();
  armEndNudge();
}

export async function trackerPause(): Promise<void> {
  const t = readActive();
  if (!t) return;
  t.state = 'paused';
  t.pausedAt = Date.now();
  t.speedMph = 0;
  t.lastPos = null; // so resume doesn't count the parked gap as distance
  writeActive(t);
  await stopUpdates();
  cancelEndNudge();
}

export async function trackerResume(): Promise<void> {
  const t = readActive();
  if (!t) return;
  if (t.pausedAt) { t.pausedMs += Date.now() - t.pausedAt; t.pausedAt = null; }
  t.state = 'running';
  writeActive(t);
  await startUpdates();
  armEndNudge();
}

// Read the live trip for rendering. Returns null when nothing is tracking.
export function readLiveTrip(): LiveTrip | null {
  const t = readActive();
  if (!t) return null;
  return {
    state: t.state,
    platform: '',
    vehicle: t.vehicle,
    miles: t.miles,
    deduction: t.deduction,
    elapsedSeconds: elapsedSeconds(t),
    speedMph: t.state === 'paused' ? 0 : t.speedMph,
    startedAt: new Date(t.startedAt),
    points: t.points,
  };
}

export async function trackerEnd(): Promise<LiveTrip | null> {
  const live = readLiveTrip();
  await stopUpdates();
  clearActive();
  setTripActive(false);
  clearTripNotification();
  cancelEndNudge();
  await resumeAutoTripUpdates(); // bring auto-detection back if it was on
  return live ? { ...live, state: 'idle' } : null;
}

// Called once on cold launch. Only clears stale notifications/flags when nothing
// is actually tracking — a genuinely in-progress trip is kept and resumed.
export async function clearStaleTripState(): Promise<void> {
  if (hasActiveTrip()) { await ensureUpdatesRunning(); return; }
  setTripActive(false);
  clearTripNotification();
  cancelEndNudge();
}
