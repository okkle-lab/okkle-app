import * as Calendar from 'expo-calendar';
import { Platform } from 'react-native';
import { kvSet } from './db';
import { logEvent } from './diagnostics';

export type CalendarResult = 'added' | 'denied' | 'error';

// Diagnostic: the reason the last calendar attempt failed, surfaced in the
// "couldn't add it" alert and persisted, so a real-device failure can be seen.
let lastReason = '';
export function getLastCalendarError(): string { return lastReason; }
function note(reason: string) {
  lastReason = reason;
  try { kvSet('last_calendar_error', `${new Date().toISOString()} ${reason}`); } catch { /* ignore */ }
  if (reason !== 'added ok') logEvent('calendar', reason);
}

// Add a tax deadline to the user's device calendar, with a reminder a week ahead.
// Returns 'added' on success, 'denied' when calendar access isn't granted (so the
// caller can offer "Open Settings"), or 'error' for anything else. All on-device —
// we never see the calendar.
export async function addDeadlineToCalendar(title: string, date: Date, notes?: string): Promise<CalendarResult> {
  try {
    const hasWriteOnly = typeof (Calendar as any).requestCalendarWriteOnlyAccessAsync === 'function';
    const requestAccess = hasWriteOnly
      ? (Calendar as any).requestCalendarWriteOnlyAccessAsync.bind(Calendar)
      : Calendar.requestCalendarPermissionsAsync.bind(Calendar);
    const res = await requestAccess();
    const status = res?.status;
    if (status !== 'granted') {
      note(`perm not granted (status=${status}, canAskAgain=${res?.canAskAgain}, writeOnlyApi=${hasWriteOnly})`);
      return 'denied';
    }

    // Find a calendar we can write to. The default-for-new-events calendar is the
    // natural choice, but it can be missing (e.g. no account set up), so fall back
    // to the first modifiable calendar before giving up.
    let calendarId: string | undefined;
    if (Platform.OS === 'ios') {
      try {
        const def = await Calendar.getDefaultCalendarAsync();
        calendarId = def?.id;
      } catch (e) {
        note(`getDefaultCalendar threw: ${String((e as any)?.message ?? e)}`);
      }
    }
    if (!calendarId) {
      try {
        const cals = await Calendar.getCalendarsAsync(Calendar.EntityTypes.EVENT);
        calendarId = (cals.find(c => c.allowsModifications) ?? cals[0])?.id;
      } catch (e) {
        note(`getCalendars threw: ${String((e as any)?.message ?? e)}`);
      }
    }
    if (!calendarId) { note('no writable calendar found'); return 'error'; }

    const start = new Date(date); start.setHours(9, 0, 0, 0);
    const end = new Date(date); end.setHours(9, 30, 0, 0);
    await Calendar.createEventAsync(calendarId, {
      title,
      startDate: start,
      endDate: end,
      notes,
      alarms: [{ relativeOffset: -60 * 24 * 7 }], // remind 7 days before
    });
    note('added ok');
    return 'added';
  } catch (e) {
    note(`exception: ${String((e as any)?.message ?? e)}`);
    return 'error';
  }
}
