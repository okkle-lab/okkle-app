import { requireOptionalNativeModule } from 'expo-modules-core';

// Optional native module — null in Expo Go / before a dev build, so the app
// keeps working (manual entry) and we just skip the scan.
const Native = requireOptionalNativeModule('OkkleVision');

export const hasVisionModule = !!Native;

// On-device OCR of a receipt image. Returns the recognised text lines.
export async function recognizeText(uri: string): Promise<{ available: boolean; lines: string[] }> {
  if (!Native) return { available: false, lines: [] };
  try {
    return await Native.recognizeText(uri);
  } catch {
    return { available: false, lines: [] };
  }
}
