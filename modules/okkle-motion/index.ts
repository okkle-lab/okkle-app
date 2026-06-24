import { requireOptionalNativeModule } from 'expo-modules-core';

// Result of a Core Motion activity query. `confidence`: 0 low / 1 medium / 2 high.
export type MotionActivity = {
  available: boolean;
  automotive?: boolean;
  cycling?: boolean;
  walking?: boolean;
  stationary?: boolean;
  confidence?: number;
};

// Optional native module — null in Expo Go / before a dev build, so the app
// keeps working and falls back to the GPS-speed heuristic.
const Native = requireOptionalNativeModule('OkkleMotion');

export const hasMotionModule = !!Native;

export function isActivityAvailable(): boolean {
  try { return Native?.isAvailable?.() ?? false; } catch { return false; }
}

// Dominant motion activity over the last `seconds` (default 3 min).
export async function recentActivity(seconds = 180): Promise<MotionActivity> {
  if (!Native) return { available: false };
  try { return await Native.recentActivity(seconds); } catch { return { available: false }; }
}
