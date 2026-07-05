import * as Location from 'expo-location';
import * as TaskManager from 'expo-task-manager';
import { Alert } from 'react-native';
import { kvGet, kvGetNum, kvSet, getUser, getLastTrip, getVehicleKeys, isWorkingDay } from './db';
import { recentActivity, hasMotionModule, type MotionActivity } from '../modules/okkle-motion';
import { trackerStart } from './tripTracker';
import { logEvent } from './diagnostics';

// Automatic trip tracking (Feature 1).
//
// On a dev/TestFlight build with "Always" location, iOS wakes the app on big
// location changes. When we see you moving at driving speed, aren't already
// tracking, and it's a working day, we start tracking straight away — no tap
// needed. If the user hasn't set any working days, every day counts.
//
// NOTE: true automotive/cycling classification needs CMMotionActivityManager
// (native). This v1 uses a GPS speed heuristic via expo-location only — see
// docs/ios-motion-capture.md for the native upgrade path.

export const AUTO_TRIP_TASK = 'okkle-auto-trip-detect';
const DRIVING_MPS = 6.7;          // ~15 mph — clearly moving, not walking
const START_COOLDOWN_MS = 5 * 60 * 1000; // guard against a burst of duplicate starts

function pickVehicle(): string {
  const keys = getVehicleKeys();
  const last = getLastTrip();
  const user = getUser();
  return last?.vehicle ?? user?.vehicle ?? keys[0] ?? 'car';
}

// Defined at module load so the headless background context can run it too.
// Every invocation logs exactly one summary line (via src/diagnostics.ts) —
// this is the only real evidence on a physical device of whether iOS is even
// waking the task at all, since neither the Simulator nor static analysis can
// exercise background location delivery. Check Settings → Automatic tracking
// → Recent activity after a real drive.
TaskManager.defineTask(AUTO_TRIP_TASK, async ({ data, error }: any) => {
  if (error) { logEvent('auto-trip', `task error: ${error.message ?? error}`); return; }
  const locations: Location.LocationObject[] = data?.locations ?? [];
  if (!locations.length) { logEvent('auto-trip', 'task fired with 0 locations'); return; }

  const topSpeed = locations.reduce((m, l) => Math.max(m, l.coords.speed ?? 0), 0);
  const base = `fired, ${locations.length} loc(s), top speed ${topSpeed.toFixed(1)} m/s`;

  if (kvGet('trip_active') === '1') { logEvent('auto-trip', `${base} — skipped: trip already active`); return; }
  if (kvGet('auto_trip') !== '1') { logEvent('auto-trip', `${base} — skipped: feature off`); return; }
  if (!isWorkingDay()) { logEvent('auto-trip', `${base} — skipped: not a working day`); return; }
  if (Date.now() - kvGetNum('auto_trip_last_start', 0) < START_COOLDOWN_MS) {
    logEvent('auto-trip', `${base} — skipped: cooldown`);
    return;
  }

  // Decide if this is really a *drive*. Prefer Core Motion (accurate — won't fire
  // for a bus/train/passenger); fall back to a GPS-speed heuristic when the native
  // module isn't present (Expo Go / pre-dev-build).
  let driving = topSpeed >= DRIVING_MPS;
  const act = await recentActivity(180).catch((): MotionActivity => ({ available: false }));
  const motionInfo = act.available
    ? `motion: automotive=${act.automotive} cycling=${act.cycling} confidence=${act.confidence}`
    : 'motion: unavailable, using GPS-speed only';
  if (act.available) {
    driving = (act.automotive === true || act.cycling === true) && (act.confidence ?? 0) >= 1;
  }
  if (!driving) { logEvent('auto-trip', `${base} — ${motionInfo} — not driving, no start`); return; }

  kvSet('auto_trip_last_start', Date.now());
  logEvent('auto-trip', `${base} — ${motionInfo} — starting trip`);
  await trackerStart(pickVehicle()).catch(err => logEvent('auto-trip', `trackerStart failed: ${err}`));
});

// Low-power background updates that watch for the *start* of a drive.
//
// activityType is deliberately `Other`, not `AutomotiveNavigation` — that type
// tells iOS "this is an active, already-confirmed drive", which makes iOS pause
// aggressively the moment it looks parked and gives no guarantee of a prompt
// resume from that fully-paused state. That's backwards for a task whose only
// job is noticing the *first* movement after being parked for hours — it's the
// live in-trip tracker (TRIP_TRACK_TASK, tripTracker.ts) that should claim
// AutomotiveNavigation, since by then a drive is genuinely underway.
const AUTO_TRIP_OPTIONS: Location.LocationTaskOptions = {
  accuracy: Location.Accuracy.Balanced,
  activityType: Location.ActivityType.Other,
  deferredUpdatesInterval: 60_000,
  pausesUpdatesAutomatically: true,   // iOS pauses when stationary → saves battery
  showsBackgroundLocationIndicator: false,
  foregroundService: {
    notificationTitle: 'Okkle',
    notificationBody: 'Watching for the start of a trip',
  },
};

export function isAutoTripEnabled(): boolean {
  return kvGet('auto_trip') === '1';
}

// While a real trip is being tracked we stop the low-power detection stream so
// only one location task is active; we bring it back when the trip ends (iff the
// user still has the feature on).
export async function suspendAutoTripUpdates(): Promise<void> {
  try {
    const started = await Location.hasStartedLocationUpdatesAsync(AUTO_TRIP_TASK).catch(() => false);
    if (started) await Location.stopLocationUpdatesAsync(AUTO_TRIP_TASK);
  } catch { /* ignore */ }
}
export async function resumeAutoTripUpdates(): Promise<void> {
  if (kvGet('auto_trip') !== '1') return;
  try {
    const started = await Location.hasStartedLocationUpdatesAsync(AUTO_TRIP_TASK).catch(() => false);
    if (!started) await Location.startLocationUpdatesAsync(AUTO_TRIP_TASK, AUTO_TRIP_OPTIONS);
  } catch { /* ignore */ }
}

// Request Always location + start low-power background updates.
export async function enableAutoTrip(): Promise<{ ok: boolean; reason?: 'foreground' | 'background' | 'error' }> {
  try {
    // iOS only ever offers "Always Allow" the first time it's asked — once
    // someone picks "While Using" or "Don't Allow", the system won't re-offer
    // it and only Settings can change it. So prime them right before the real
    // prompts appear, while there's still a system dialog to answer.
    const fgBefore = await Location.getForegroundPermissionsAsync();
    const bgBefore = await Location.getBackgroundPermissionsAsync();
    if (fgBefore.status === 'undetermined' || bgBefore.status === 'undetermined') {
      await new Promise<void>(resolve => {
        Alert.alert(
          'One more step',
          'iOS will ask for location access twice — choose “Allow While Using App”, then “Change to Always Allow” — so a drive still gets tracked with Okkle closed.',
          [{ text: 'Continue', onPress: () => resolve() }],
        );
      });
    }

    const fg = await Location.requestForegroundPermissionsAsync();
    if (fg.status !== 'granted') {
      logEvent('auto-trip', `enable failed: foreground permission = ${fg.status}`);
      return { ok: false, reason: 'foreground' };
    }
    const bg = await Location.requestBackgroundPermissionsAsync();
    if (bg.status !== 'granted') {
      logEvent('auto-trip', `enable failed: background permission = ${bg.status}`);
      return { ok: false, reason: 'background' };
    }
    // Trigger the Motion & Fitness permission prompt now (in context), so Core
    // Motion detection is ready. Harmless if the native module isn't present.
    if (hasMotionModule) { await recentActivity(60).catch(() => {}); }

    const already = await Location.hasStartedLocationUpdatesAsync(AUTO_TRIP_TASK).catch(() => false);
    if (!already) {
      await Location.startLocationUpdatesAsync(AUTO_TRIP_TASK, AUTO_TRIP_OPTIONS);
    }
    kvSet('auto_trip', '1');
    logEvent('auto-trip', `enabled — watching task ${already ? 'already running' : 'started'}, motion module ${hasMotionModule ? 'present' : 'absent'}`);
    return { ok: true };
  } catch (e) {
    logEvent('auto-trip', `enable threw: ${e}`);
    return { ok: false, reason: 'error' };
  }
}

export async function disableAutoTrip(): Promise<void> {
  kvSet('auto_trip', '');
  try {
    const started = await Location.hasStartedLocationUpdatesAsync(AUTO_TRIP_TASK).catch(() => false);
    if (started) await Location.stopLocationUpdatesAsync(AUTO_TRIP_TASK);
  } catch { /* ignore */ }
}

// Called by the trip hook so we don't prompt while a trip is already running.
export function setTripActive(active: boolean) {
  kvSet('trip_active', active ? '1' : '');
}
