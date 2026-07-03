import { useState, useRef, useEffect } from 'react';
import {
  readLiveTrip, ensureUpdatesRunning, hasActiveTrip,
  trackerStart, trackerPause, trackerResume, trackerEnd,
  type LiveTrip, type TripState, type GeoPoint,
} from '../tripTracker';
import { trackEvent } from '../analytics';

// Re-export types so existing consumers keep importing them from here.
export type { LiveTrip, TripState, GeoPoint };
// Re-export so the root layout's cold-launch cleanup keeps working unchanged.
export { clearStaleTripState } from '../tripTracker';

const INITIAL: LiveTrip = {
  state: 'idle', platform: '', vehicle: 'car', miles: 0, deduction: 0,
  elapsedSeconds: 0, speedMph: 0, startedAt: null, points: [],
};

// Thin React layer over the persistent tracker. All trip state lives in storage
// (so it survives navigation, backgrounding, lock and app kills); this hook just
// mirrors it into render state once a second and exposes the controls.
export function useTrip() {
  const [trip, setTrip] = useState<LiveTrip>(INITIAL);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);

  function sync() {
    const live = readLiveTrip();
    setTrip(live ?? INITIAL);
  }
  function startTimer() {
    if (timerRef.current) clearInterval(timerRef.current);
    timerRef.current = setInterval(sync, 1000);
  }
  function stopTimer() {
    if (timerRef.current) { clearInterval(timerRef.current); timerRef.current = null; }
  }

  // On mount: if a trip is already in progress (returned to the screen, reopened
  // the app, or relaunched after a kill), restore it and resume the live ticker.
  // We deliberately do NOT stop tracking on unmount — leaving the screen keeps
  // the trip running in the background.
  useEffect(() => {
    if (hasActiveTrip()) {
      sync();
      ensureUpdatesRunning().catch(() => {});
      startTimer();
    }
    return () => stopTimer();
  }, []);

  async function start(vehicle: string) {
    await trackerStart(vehicle);
    sync();
    startTimer();
    trackEvent('trip_start', { vehicle });
  }
  async function pause() {
    await trackerPause();
    sync();
  }
  async function resume() {
    await trackerResume();
    sync();
    startTimer();
  }
  function end(): LiveTrip {
    stopTimer();
    let final: LiveTrip = { ...trip, state: 'idle' };
    // Snapshot before the async clear so the caller gets the final numbers.
    const live = readLiveTrip();
    if (live) final = { ...live, state: 'idle' };
    trackerEnd().catch(() => {});
    setTrip(INITIAL);
    trackEvent('trip_end', { miles: final.miles, vehicle: final.vehicle });
    return final;
  }

  return { trip, points: trip.points ?? [], start, pause, resume, end };
}
