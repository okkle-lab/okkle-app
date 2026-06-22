import { useState, useRef, useEffect } from 'react';
import * as Location from 'expo-location';
import { mileageRate, calcDeduction } from '../db/tax';

export type TripState = 'idle' | 'running' | 'paused';

export type LiveTrip = {
  state: TripState;
  platform: string;
  vehicle: string;
  miles: number;
  deduction: number;
  elapsedSeconds: number;
  speedMph: number;
  startedAt: Date | null;
};

const INITIAL: LiveTrip = {
  state: 'idle',
  platform: 'Uber Eats',
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

  useEffect(() => {
    return () => {
      watchRef.current?.remove();
      if (timerRef.current) clearInterval(timerRef.current);
    };
  }, []);

  async function start(platform: string, vehicle: string) {
    const { status } = await Location.requestForegroundPermissionsAsync();
    if (status !== 'granted') throw new Error('Location permission denied');

    const startedAt = new Date();
    setTrip({ state: 'running', platform, vehicle, miles: 0, deduction: 0, elapsedSeconds: 0, speedMph: 0, startedAt });

    timerRef.current = setInterval(() => {
      setTrip(t => ({ ...t, elapsedSeconds: t.elapsedSeconds + 1 }));
    }, 1000);

    watchRef.current = await Location.watchPositionAsync(
      { accuracy: Location.Accuracy.High, distanceInterval: 20 },
      (loc) => {
        const spd = loc.coords.speed; // m/s; -1 or null when unknown
        const mph = spd != null && spd > 0 ? spd * 2.236936 : 0;
        if (lastPosRef.current) {
          const d = haversineKm(lastPosRef.current.coords, loc.coords);
          const meters = d * 1000;
          const stationary = (spd != null && spd >= 0 && spd < 0.5) || meters < 8;
          setTrip(t => {
            const miles = stationary ? t.miles : t.miles + d * 0.621371;
            return { ...t, miles, deduction: calcDeduction(miles, t.vehicle), speedMph: mph };
          });
        } else {
          setTrip(t => ({ ...t, speedMph: mph }));
        }
        lastPosRef.current = loc;
      },
    );
  }

  function pause() {
    watchRef.current?.remove();
    watchRef.current = null;
    if (timerRef.current) clearInterval(timerRef.current);
    setTrip(t => ({ ...t, state: 'paused' }));
  }

  async function resume() {
    if (timerRef.current) clearInterval(timerRef.current);
    timerRef.current = setInterval(() => {
      setTrip(t => ({ ...t, elapsedSeconds: t.elapsedSeconds + 1 }));
    }, 1000);

    watchRef.current = await Location.watchPositionAsync(
      { accuracy: Location.Accuracy.High, distanceInterval: 20 },
      (loc) => {
        const spd = loc.coords.speed; // m/s; -1 or null when unknown
        const mph = spd != null && spd > 0 ? spd * 2.236936 : 0;
        if (lastPosRef.current) {
          const d = haversineKm(lastPosRef.current.coords, loc.coords);
          const meters = d * 1000;
          const stationary = (spd != null && spd >= 0 && spd < 0.5) || meters < 8;
          setTrip(t => {
            const miles = stationary ? t.miles : t.miles + d * 0.621371;
            return { ...t, miles, deduction: calcDeduction(miles, t.vehicle), speedMph: mph };
          });
        } else {
          setTrip(t => ({ ...t, speedMph: mph }));
        }
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
    const final = { ...trip, state: 'idle' as TripState };
    setTrip(INITIAL);
    return final;
  }

  return { trip, start, pause, resume, end };
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
