import * as Location from 'expo-location';
import * as TaskManager from 'expo-task-manager';
import * as Notifications from 'expo-notifications';
import { kvGet, kvGetNum, kvSet } from './db';
import { recentActivity, hasMotionModule, type MotionActivity } from '../modules/okkle-motion';

// Movement-based trip *suggestion* (Feature 1).
//
// On a dev/TestFlight build with "Always" location, iOS wakes the app on big
// location changes. When we see you moving at driving speed and you're not
// already tracking, we fire a gentle "On the move — track this trip?" prompt.
// We never auto-record: tapping the prompt opens the Trip screen where the user
// confirms by hitting Start. This keeps the user in control.
//
// NOTE: true automotive/cycling classification needs CMMotionActivityManager
// (native). This v1 uses a GPS speed heuristic via expo-location only — see
// docs/ios-motion-capture.md for the native upgrade path.

export const AUTO_TRIP_TASK = 'okkle-auto-trip-detect';
const DRIVING_MPS = 6.7;          // ~15 mph — clearly moving, not walking
const PROMPT_COOLDOWN_MS = 30 * 60 * 1000; // don't nag more than every 30 min

// Defined at module load so the headless background context can run it too.
TaskManager.defineTask(AUTO_TRIP_TASK, async ({ data, error }: any) => {
  if (error) return;
  const locations: Location.LocationObject[] = data?.locations ?? [];
  if (!locations.length) return;

  if (kvGet('trip_active') === '1') return;           // already tracking a trip
  if (kvGet('auto_trip') !== '1') return;             // feature turned off
  if (Date.now() - kvGetNum('auto_trip_last_prompt', 0) < PROMPT_COOLDOWN_MS) return;

  // Decide if this is really a *drive*. Prefer Core Motion (accurate — won't fire
  // for a bus/train/passenger); fall back to a GPS-speed heuristic when the native
  // module isn't present (Expo Go / pre-dev-build).
  const topSpeed = locations.reduce((m, l) => Math.max(m, l.coords.speed ?? 0), 0);
  let driving = topSpeed >= DRIVING_MPS;
  const act = await recentActivity(180).catch((): MotionActivity => ({ available: false }));
  if (act.available) {
    driving = (act.automotive === true || act.cycling === true) && (act.confidence ?? 0) >= 1;
  }
  if (!driving) return;

  // Quiet hours: this fires the moment we detect driving speed, with no idea
  // whether it's a work shift or a late drive home — don't interrupt sleep
  // over it. Skip 22:00–07:00 local; the next daytime drive will still prompt.
  const hour = new Date().getHours();
  if (hour >= 22 || hour < 7) return;

  kvSet('auto_trip_last_prompt', Date.now());
  await Notifications.scheduleNotificationAsync({
    content: {
      title: 'Looks like you’re driving',
      // An observation, not an instruction — the user decides whether this
      // drive is worth tracking, Okkle just flags that it noticed.
      body: 'If this is a work trip, tracking it now keeps the tax-free miles.',
      data: { type: 'autotrip' },
    },
    trigger: null, // deliver now
  }).catch(() => {});
});

// Low-power background updates that watch for the *start* of a drive.
const AUTO_TRIP_OPTIONS: Location.LocationTaskOptions = {
  accuracy: Location.Accuracy.Balanced,
  activityType: Location.ActivityType.AutomotiveNavigation,
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
    const fg = await Location.requestForegroundPermissionsAsync();
    if (fg.status !== 'granted') return { ok: false, reason: 'foreground' };
    const bg = await Location.requestBackgroundPermissionsAsync();
    if (bg.status !== 'granted') return { ok: false, reason: 'background' };
    // Trigger the Motion & Fitness permission prompt now (in context), so Core
    // Motion detection is ready. Harmless if the native module isn't present.
    if (hasMotionModule) { await recentActivity(60).catch(() => {}); }

    const already = await Location.hasStartedLocationUpdatesAsync(AUTO_TRIP_TASK).catch(() => false);
    if (!already) {
      await Location.startLocationUpdatesAsync(AUTO_TRIP_TASK, AUTO_TRIP_OPTIONS);
    }
    kvSet('auto_trip', '1');
    return { ok: true };
  } catch {
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
