import { useState, useRef, useEffect } from 'react';
import * as Location from 'expo-location';
import * as Notifications from 'expo-notifications';
import { calcDeduction } from '../db/tax';
import { setTripActive } from '../autoTrip';

const TRIP_NOTIF_ID = 'okkle-trip-active';
const TRIP_END_NUDGE_ID = 'okkle-trip-end-nudge';
const END_NUDGE_AFTER_S = 18 * 60; // ask "finished?" ~18 min after last movement

// Live trip state lives only in memory, so on a cold app launch there is never a
// trip actually running. If the app was killed mid-trip, iOS keeps the sticky
// "tracking" notification, the scheduled "finished this trip?" nudge, and a stuck
// trip_active='1' flag (which would silently suppress every future "start a trip?"
// prompt). Call this once at startup to clear all of that stale state — fixes
// being nudged to stop a trip that isn't running, and never being nudged to start.
export async function clearStaleTripState(): Promise<void> {
  setTripActive(false);
  Notifications.dismissNotificationAsync(TRIP_NOTIF_ID).catch(() => {});
  Notifications.cancelScheduledNotificationAsync(TRIP_NOTIF_ID).catch(() => {});
  Notifications.cancelScheduledNotificationAsync(TRIP_END_NUDGE_ID).catch(() => {});
}
const MAX_GPS_ACCURACY_M = 45;
const MAX_REASONABLE_SPEED_MPS = 45; // ~100mph; anything above is almost certainly a GPS jump for courier use.

// A lock-screen notification while a trip is tracking, so it's visible when the
// phone is locked and one tap brings you back to the live screen.
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

// The other half of the two-way nudge: re-armed on every movement to fire
// END_NUDGE_AFTER_S after the *last* movement, so it only goes off once you've
// been parked a while. Tapping it opens the live screen to end & save the trip.
// Fires via a scheduled trigger, so it works even if the app is suspended.
function armTripEndNudge() {
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
function cancelTripEndNudge() {
  Notifications.cancelScheduledNotificationAsync(TRIP_END_NUDGE_ID).catch(() => {});
}

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

const INITIAL: LiveTrip = {
  state: 'idle',
  platform: '',
  vehicle: 'car',
  miles: 0,
  deduction: 0,
  elapsedSeconds: 0,
  speedMph: 0,
  startedAt: null,
};

export function useTrip() {
  const [trip, setTrip] = useState<LiveTrip>(INITIAL);
  const watchRef = useRef<Location.LocationSubscription | null>(null);
  const lastPosRef = useRef<Location.LocationObject | null>(null);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  // Downsampled GPS breadcrumb for the location heatmap (kept off render state).
  const pointsRef = useRef<GeoPoint[]>([]);
  const lastSampleRef = useRef<Location.LocationObject | null>(null);

  function usableLocation(loc: Location.LocationObject): boolean {
    const { latitude, longitude, accuracy, speed } = loc.coords;
    if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return false;
    if (accuracy != null && accuracy > MAX_GPS_ACCURACY_M) return false;
    if (speed != null && speed > MAX_REASONABLE_SPEED_MPS) return false;
    return true;
  }

  function samplePoint(loc: Location.LocationObject) {
    if (!usableLocation(loc)) return;
    const prev = lastSampleRef.current;
    // Keep a point roughly every 40m, capped so storage stays tiny.
    if (prev) {
      const m = haversineKm(prev.coords, loc.coords) * 1000;
      if (m < 40) return;
    }
    if (pointsRef.current.length < 400) {
      pointsRef.current.push({
        lat: +loc.coords.latitude.toFixed(5),
        lng: +loc.coords.longitude.toFixed(5),
        t: loc.timestamp || Date.now(), // ms — lets Insights bucket by real hour
      });
      lastSampleRef.current = loc;
    }
  }

  useEffect(() => {
    return () => {
      watchRef.current?.remove();
      if (timerRef.current) clearInterval(timerRef.current);
    };
  }, []);

  async function start(vehicle: string) {
    const { status } = await Location.requestForegroundPermissionsAsync();
    if (status !== 'granted') throw new Error('Location permission denied');
    // Ask for background permission so tracking continues when the phone is
    // locked. Harmless in Expo Go (returns undetermined); real in a dev build.
    try { await Location.requestBackgroundPermissionsAsync(); } catch { /* ignore */ }

    const startedAt = new Date();
    pointsRef.current = [];
    lastSampleRef.current = null;
    lastPosRef.current = null;
    setTripActive(true); // pause auto-trip suggestions while we're tracking
    showTripNotification();
    armTripEndNudge();   // arm the "finished this trip?" half of the nudge
    setTrip({ state: 'running', platform: '', vehicle, miles: 0, deduction: 0, elapsedSeconds: 0, speedMph: 0, startedAt });

    timerRef.current = setInterval(() => {
      setTrip(t => ({ ...t, elapsedSeconds: t.elapsedSeconds + 1 }));
    }, 1000);

    watchRef.current = await Location.watchPositionAsync(
      {
        accuracy: Location.Accuracy.BestForNavigation,
        distanceInterval: 20,
        // Background continuation comes from UIBackgroundModes "location" +
        // the "Always" permission (configured in app.json) — dev build only.
      },
      (loc) => {
        if (!usableLocation(loc)) return;
        const spd = loc.coords.speed; // m/s; -1 or null when unknown
        const mph = spd != null && spd > 0 ? spd * 2.236936 : 0;
        if (lastPosRef.current) {
          const d = haversineKm(lastPosRef.current.coords, loc.coords);
          const meters = d * 1000;
          const seconds = Math.max(1, ((loc.timestamp || Date.now()) - (lastPosRef.current.timestamp || Date.now())) / 1000);
          const jumpy = meters / seconds > MAX_REASONABLE_SPEED_MPS;
          if (jumpy) return;
          const noiseFloor = Math.max(8, Math.min(30, ((lastPosRef.current.coords.accuracy ?? 12) + (loc.coords.accuracy ?? 12)) / 2));
          const stationary = (spd != null && spd >= 0 && spd < 0.5) || meters < noiseFloor;
          if (!stationary) armTripEndNudge(); // moving → push the "finished?" nudge back
          setTrip(t => {
            const miles = stationary ? t.miles : t.miles + d * 0.621371;
            return { ...t, miles, deduction: calcDeduction(miles, t.vehicle), speedMph: mph };
          });
        } else {
          setTrip(t => ({ ...t, speedMph: mph }));
        }
        samplePoint(loc);
        lastPosRef.current = loc;
      },
    );
  }

  function pause() {
    watchRef.current?.remove();
    watchRef.current = null;
    if (timerRef.current) clearInterval(timerRef.current);
    cancelTripEndNudge();
    setTrip(t => ({ ...t, state: 'paused' }));
  }

  async function resume() {
    if (timerRef.current) clearInterval(timerRef.current);
    armTripEndNudge();
    timerRef.current = setInterval(() => {
      setTrip(t => ({ ...t, elapsedSeconds: t.elapsedSeconds + 1 }));
    }, 1000);

    watchRef.current = await Location.watchPositionAsync(
      {
        accuracy: Location.Accuracy.BestForNavigation,
        distanceInterval: 20,
        // Background continuation comes from UIBackgroundModes "location" +
        // the "Always" permission (configured in app.json) — dev build only.
      },
      (loc) => {
        if (!usableLocation(loc)) return;
        const spd = loc.coords.speed; // m/s; -1 or null when unknown
        const mph = spd != null && spd > 0 ? spd * 2.236936 : 0;
        if (lastPosRef.current) {
          const d = haversineKm(lastPosRef.current.coords, loc.coords);
          const meters = d * 1000;
          const seconds = Math.max(1, ((loc.timestamp || Date.now()) - (lastPosRef.current.timestamp || Date.now())) / 1000);
          const jumpy = meters / seconds > MAX_REASONABLE_SPEED_MPS;
          if (jumpy) return;
          const noiseFloor = Math.max(8, Math.min(30, ((lastPosRef.current.coords.accuracy ?? 12) + (loc.coords.accuracy ?? 12)) / 2));
          const stationary = (spd != null && spd >= 0 && spd < 0.5) || meters < noiseFloor;
          if (!stationary) armTripEndNudge(); // moving → push the "finished?" nudge back
          setTrip(t => {
            const miles = stationary ? t.miles : t.miles + d * 0.621371;
            return { ...t, miles, deduction: calcDeduction(miles, t.vehicle), speedMph: mph };
          });
        } else {
          setTrip(t => ({ ...t, speedMph: mph }));
        }
        samplePoint(loc);
        lastPosRef.current = loc;
      },
    );
    setTrip(t => ({ ...t, state: 'running' }));
  }

  function end(): LiveTrip {
    watchRef.current?.remove();
    watchRef.current = null;
    if (timerRef.current) clearInterval(timerRef.current);
    lastPosRef.current = null;
    setTripActive(false); // re-enable auto-trip suggestions
    clearTripNotification();
    cancelTripEndNudge();
    const final = { ...trip, state: 'idle' as TripState, points: pointsRef.current.slice() };
    setTrip(INITIAL);
    return final;
  }

  // pointsRef is the live breadcrumb (kept off render state for perf). Expose it
  // for the live map — the trip re-renders ~1/sec so it stays current enough.
  return { trip, points: pointsRef.current, start, pause, resume, end };
}

function haversineKm(
  a: { latitude: number; longitude: number },
  b: { latitude: number; longitude: number },
): number {
  const R = 6371;
  const dLat = deg2rad(b.latitude - a.latitude);
  const dLon = deg2rad(b.longitude - a.longitude);
  const x =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(deg2rad(a.latitude)) * Math.cos(deg2rad(b.latitude)) * Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(x), Math.sqrt(1 - x));
}

function deg2rad(d: number) { return d * (Math.PI / 180); }
