import * as Location from 'expo-location';
import * as TaskManager from 'expo-task-manager';
import * as Notifications from 'expo-notifications';
import { calcDeduction, fmtGbp } from './db/tax';
import { kvGet, kvSet, saveTrip, pickZoneRepresentativePoint } from './db';
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
const AUTO_END_AFTER_S = 18 * 60; // auto-finish ~18 min after last movement
const MIN_AUTO_SAVE_MILES = 0.1;  // drop obvious false-positive blips rather than log them

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
  lastNotifAt: number; // throttle live-miles notification refreshes
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
  ingest(t, locations);
  maybeRefreshNotification(t); // keep the live-miles notification current
  writeActive(t);
  await checkAutoEnd(); // opportunistic — catches most stops since GPS drift alone usually nudges a fix through
});

// --- lock-screen notification + end nudge ----------------------------------
function postTripNotification(body: string) {
  Notifications.scheduleNotificationAsync({
    identifier: TRIP_NOTIF_ID,
    content: {
      title: 'Tracking your trip',
      body,
      data: { type: 'tripActive' },
      sticky: true,
      interruptionLevel: 'passive', // update quietly — no sound or screen wake
    },
    trigger: null,
  }).catch(() => {});
}
function showTripNotification() {
  postTripNotification('GPS is logging your miles. Tap to view.');
}
// Refresh the live-miles notification at most once a minute, so the lock screen
// shows the trip is still working without spamming alerts.
function maybeRefreshNotification(t: ActiveTrip) {
  const now = Date.now();
  if (now - (t.lastNotifAt || 0) < 60_000) return;
  t.lastNotifAt = now;
  postTripNotification(`${t.miles.toFixed(1)} mi · ${fmtGbp(t.deduction)} so far · tap to view`);
}
function clearTripNotification() {
  Notifications.dismissNotificationAsync(TRIP_NOTIF_ID).catch(() => {});
  Notifications.cancelScheduledNotificationAsync(TRIP_NOTIF_ID).catch(() => {});
}

// Reverse-geocode a representative point to a friendly "zone" name, so the
// Insights map can rank where you earn. Skips home/excluded places — otherwise
// a shift that loops back through home mid-route could get named after home.
async function resolveZone(points: GeoPoint[]): Promise<string | null> {
  const repPoint = pickZoneRepresentativePoint(points);
  if (!repPoint) return null;
  try {
    const places = await Location.reverseGeocodeAsync({ latitude: repPoint.lat, longitude: repPoint.lng });
    const p = places[0];
    const outward = p?.postalCode ? p.postalCode.split(' ')[0].trim() : null;
    const local = p?.street ?? p?.district ?? p?.subregion ?? p?.city ?? null;
    return [local, outward].filter(Boolean).join(' · ') || null;
  } catch {
    return null;
  }
}

// No user is necessarily present to review a summary screen, so a trip that's
// been sitting stationary long enough gets ended and written straight to
// records — the same shape the manual "Save" flow on the Trip screen produces.
async function autoFinishTrip(): Promise<void> {
  const live = readLiveTrip();
  if (!live) { await trackerEnd(); return; }
  const points = live.points ?? [];
  if (live.miles < MIN_AUTO_SAVE_MILES) { await trackerEnd(); return; }
  const zone = await resolveZone(points);
  await trackerEnd();
  saveTrip({
    platform: '',
    vehicle: live.vehicle,
    miles: parseFloat(live.miles.toFixed(2)),
    deduction: parseFloat(live.deduction.toFixed(2)),
    earnings: null,
    started_at: live.startedAt!.toISOString(),
    ended_at: new Date().toISOString(),
    route_json: points.length > 0 ? JSON.stringify(points) : null,
    zone,
  });
  Notifications.scheduleNotificationAsync({
    content: {
      title: 'Shift logged',
      body: `${live.miles.toFixed(1)} mi · ${fmtGbp(live.deduction)} saved automatically.`,
      data: { type: 'tripEnd' },
    },
    trigger: null,
  }).catch(() => {});
}

// There's no reliable iOS callback for "time has passed while parked" — we
// piggyback this check on whatever already wakes the app (a GPS update from
// the trip task, or the user reopening it) rather than depending on one.
export async function checkAutoEnd(): Promise<boolean> {
  const t = readActive();
  if (!t || t.state !== 'running') return false;
  if ((Date.now() - t.lastMoveAt) / 1000 < AUTO_END_AFTER_S) return false;
  await autoFinishTrip();
  return true;
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
    lastMoveAt: Date.now(), lastNotifAt: Date.now(),
  };
  writeActive(t);
  setTripActive(true); // pause auto-trip suggestions while we track
  await startUpdates();
  showTripNotification();
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
}

export async function trackerResume(): Promise<void> {
  const t = readActive();
  if (!t) return;
  if (t.pausedAt) { t.pausedMs += Date.now() - t.pausedAt; t.pausedAt = null; }
  t.state = 'running';
  t.lastMoveAt = Date.now(); // resuming counts as fresh movement, not still-parked
  writeActive(t);
  await startUpdates();
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
  await resumeAutoTripUpdates(); // bring auto-detection back if it was on
  return live ? { ...live, state: 'idle' } : null;
}

// Called once on cold launch. A genuinely in-progress trip is either resumed,
// or — if it's been stationary long enough while the app was closed — auto-
// finished right here, so reopening the app is one more chance to catch it.
export async function clearStaleTripState(): Promise<void> {
  if (hasActiveTrip()) {
    const ended = await checkAutoEnd();
    if (!ended) await ensureUpdatesRunning();
    return;
  }
  setTripActive(false);
  clearTripNotification();
}
