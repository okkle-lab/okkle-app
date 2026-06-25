import * as Location from 'expo-location';
import * as Notifications from 'expo-notifications';
import { kvGet, kvGetNum, kvSet, saveRecord, SHIFT_DRAFT_NOTE } from './db';
import { calcDeduction, fmtGbp, fmtMiles } from './db/tax';
import { recentActivity, type MotionActivity } from '../modules/okkle-motion';

// ── Passive shift tracking ────────────────────────────────────────────────
//
// The correct model for a multi-app delivery courier (see RELEASE / UX notes):
// we do NOT track per-drop legs. For UK simplified-expenses mileage, every mile
// driven while on shift — to the restaurant, to the customer, and the "dead"
// miles cruising for the next offer — is the same thing: a business mile. So we
// track ONE continuous "shift" = total miles while moving, in the background,
// at low power, and never ask the driver to tap anything mid-delivery.
//
// This runs inside the existing background location task (autoTrip). The driver
// is in Deliveroo/Uber the whole time; Okkle stays invisible and surfaces only
// at the edges (a lock-screen line while tracking, a "review your shift" prompt
// when it ends).

const SHIFT_NOTIF_ID = 'okkle-shift-active';
const SHIFT_NUDGE_ID = 'okkle-shift-nudge';
const NUDGE_AFTER_S = 40 * 60;           // ask "done?" 40 min after last movement
const DRIVING_MPS = 6.7;                 // ~15 mph — clearly driving, not walking
// A shift does NOT end on a short stop. Lunch, a wait at a busy restaurant, a
// quick errand — those are just 0-mile gaps inside one shift (an idle gap adds no
// miles either way, so keeping the shift open costs nothing). We only *finalize*
// after a long idle, on manual End, or when a much later drive proves the old
// shift ended back when movement stopped.
const FINALIZE_AFTER_MS = 120 * 60 * 1000; // ~2h stationary → the shift is over
const MIN_SHIFT_MILES = 0.5;             // ignore trivial movement
const MIN_SEG_M = 8;                     // GPS jitter floor
const MAX_SEG_M = 6000;                  // reject teleports / bad fixes

export function isShiftModeEnabled(): boolean {
  return kvGet('shift_mode') === '1';
}
export function isShiftActive(): boolean {
  return kvGet('shift_active') === '1';
}
export function shiftVehicle(): string {
  return kvGet('shift_vehicle') || 'car';
}

function showShiftNotification(miles: number) {
  Notifications.scheduleNotificationAsync({
    identifier: SHIFT_NOTIF_ID,
    content: {
      title: 'On shift — counting your miles',
      body: `${fmtMiles(miles)} so far. Okkle is tracking in the background.`,
      data: { type: 'shiftActive' },
      sticky: true,
    },
    trigger: null,
  }).catch(() => {});
}
function clearShiftNotification() {
  Notifications.dismissNotificationAsync(SHIFT_NOTIF_ID).catch(() => {});
  Notifications.cancelScheduledNotificationAsync(SHIFT_NOTIF_ID).catch(() => {});
}

// Re-armed every time we see movement: a future "Done for the day?" prompt set to
// fire NUDGE_AFTER_S after your *last* movement. Keep driving → it keeps getting
// pushed back, so it never fires mid-shift. Fires via a scheduled trigger, so it
// works even if the app is suspended. Non-destructive: tapping it ends the shift;
// ignoring it (e.g. a long lunch) leaves the shift open and still counting.
function armEndNudge() {
  Notifications.cancelScheduledNotificationAsync(SHIFT_NUDGE_ID).catch(() => {});
  Notifications.scheduleNotificationAsync({
    identifier: SHIFT_NUDGE_ID,
    content: {
      title: 'Done for the day?',
      body: 'Tap to end your shift and log the miles — or ignore if you’re still out.',
      data: { type: 'shiftMaybeEnded' },
    },
    trigger: {
      type: Notifications.SchedulableTriggerInputTypes.TIME_INTERVAL,
      seconds: NUDGE_AFTER_S,
    },
  }).catch(() => {});
}
function cancelEndNudge() {
  Notifications.cancelScheduledNotificationAsync(SHIFT_NUDGE_ID).catch(() => {});
}

// Finalize the current shift right now (from the manual End tap or the "done?"
// prompt). Safe to call when no shift is active.
export function endShiftNow() {
  if (isShiftActive()) endShift();
}

function startShift(now: number) {
  const started = new Date(now).toISOString();
  kvSet('shift_active', '1');
  kvSet('shift_started_at', started);
  kvSet('shift_miles', 0);
  kvSet('shift_last_move_ms', now);
  kvSet('shift_last_lat', '');
  kvSet('shift_last_lng', '');
  showShiftNotification(0);
  armEndNudge();
}

function endShift() {
  const miles = kvGetNum('shift_miles', 0);
  const startedAt = kvGet('shift_started_at') || new Date().toISOString();
  // Clear state first so a crash can't double-log.
  kvSet('shift_active', '');
  kvSet('shift_last_lat', '');
  kvSet('shift_last_lng', '');
  clearShiftNotification();
  cancelEndNudge();
  if (miles < MIN_SHIFT_MILES) return;

  const vehicle = shiftVehicle();
  const deduction = calcDeduction(miles, vehicle);
  const day = startedAt.slice(0, 10);
  // Logged as an unconfirmed draft the driver reviews — never silently final.
  saveRecord(
    {
      record_type: 'mileage',
      platform: null,
      amount: null,
      miles: +miles.toFixed(1),
      deduction: +deduction.toFixed(2),
      category: null,
      period_start: day,
      period_end: day,
      receipt_uri: null,
      notes: SHIFT_DRAFT_NOTE,
    },
    startedAt,
  );
  Notifications.scheduleNotificationAsync({
    content: {
      title: 'Shift logged ✓',
      body: `${fmtMiles(miles)} · about ${fmtGbp(deduction)} off your tax. Tap to review.`,
      data: { type: 'shiftEnded' },
    },
    trigger: null,
  }).catch(() => {});
}

// Called from the background location task with the batch of new fixes.
export async function processShiftLocations(locations: Location.LocationObject[]) {
  if (!locations.length) return;
  // A manual trip (the classic Start/End flow) is tracking these same miles in the
  // foreground — stand down so we never double-count.
  if (kvGet('trip_active') === '1') return;
  const now = Date.now();
  const lastSeen = kvGetNum('shift_last_seen_ms', 0);
  kvSet('shift_last_seen_ms', now);

  // If we were tracking but haven't heard from the OS in a while, the driver was
  // parked (iOS pauses updates when stationary) — the shift ended back then.
  if (isShiftActive() && lastSeen && now - lastSeen > FINALIZE_AFTER_MS) {
    endShift();
  }

  // Is this really a drive? Core Motion is accurate and nearly free; fall back to
  // GPS speed when the native module isn't present.
  const topSpeed = locations.reduce((m, l) => Math.max(m, l.coords.speed ?? 0), 0);
  let driving = topSpeed >= DRIVING_MPS;
  const act = await recentActivity(120).catch((): MotionActivity => ({ available: false }));
  if (act.available) {
    const moving = act.automotive === true || act.cycling === true;
    driving = moving && (act.confidence ?? 0) >= 1;
    // A confident "stationary" while tracking is a strong end signal.
    if (isShiftActive() && act.stationary === true && (act.confidence ?? 0) >= 1
        && now - kvGetNum('shift_last_move_ms', now) > FINALIZE_AFTER_MS) {
      endShift();
    }
  }

  if (driving && !isShiftActive()) startShift(now);
  if (!isShiftActive()) return;

  // Accumulate distance across the batch.
  let lat = parseFloat(kvGet('shift_last_lat') || '');
  let lng = parseFloat(kvGet('shift_last_lng') || '');
  let miles = kvGetNum('shift_miles', 0);
  let moved = false;
  for (const loc of locations) {
    const { latitude, longitude } = loc.coords;
    if (!Number.isNaN(lat) && !Number.isNaN(lng)) {
      const m = haversineKm({ latitude: lat, longitude: lng }, { latitude, longitude }) * 1000;
      if (m >= MIN_SEG_M && m <= MAX_SEG_M) {
        miles += (m / 1000) * 0.621371;
        moved = true;
      }
    }
    lat = latitude;
    lng = longitude;
  }
  kvSet('shift_last_lat', String(lat));
  kvSet('shift_last_lng', String(lng));
  kvSet('shift_miles', +miles.toFixed(3));
  if (moved) {
    kvSet('shift_last_move_ms', now);
    showShiftNotification(miles); // refresh the lock-screen line
    armEndNudge();                // push the "done?" prompt back to 40min from now
  }
}

function haversineKm(
  a: { latitude: number; longitude: number },
  b: { latitude: number; longitude: number },
): number {
  const R = 6371;
  const dLat = ((b.latitude - a.latitude) * Math.PI) / 180;
  const dLon = ((b.longitude - a.longitude) * Math.PI) / 180;
  const la1 = (a.latitude * Math.PI) / 180;
  const la2 = (b.latitude * Math.PI) / 180;
  const x =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(la1) * Math.cos(la2) * Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(x), Math.sqrt(1 - x));
}
