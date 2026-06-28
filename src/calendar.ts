import * as Calendar from 'expo-calendar';
import { Platform } from 'react-native';

export type CalendarResult = 'added' | 'denied' | 'error';

// Add a tax deadline to the user's device calendar, with a reminder a week ahead.
// Returns 'added' on success, 'denied' when calendar access isn't granted (so the
// caller can offer "Open Settings"), or 'error' for anything else. All on-device —
// we never see the calendar.
export async function addDeadlineToCalendar(title: string, date: Date, notes?: string): Promise<CalendarResult> {
  try {
    // Okkle only ever *writes* events, never reads. Prefer the lighter "write-only"
    // calendar access where the installed expo-calendar build exposes it (friendlier
    // iOS prompt); otherwise fall back to the standard request.
    const requestAccess = (Calendar as any).requestCalendarWriteOnlyAccessAsync
      ? (Calendar as any).requestCalendarWriteOnlyAccessAsync.bind(Calendar)
      : Calendar.requestCalendarPermissionsAsync.bind(Calendar);
    const { status } = await requestAccess();
    if (status !== 'granted') return 'denied';

    // Find a calendar we can write to. The default-for-new-events calendar is the
    // natural choice, but it can be missing (e.g. no account set up), so fall back
    // to the first modifiable calendar before giving up.
    let calendarId: string | undefined;
    if (Platform.OS === 'ios') {
      try {
        const def = await Calendar.getDefaultCalendarAsync();
        calendarId = def?.id;
      } catch {
        // getDefaultCalendarAsync can throw under limited access — fall through.
      }
    }
    if (!calendarId) {
      const cals = await Calendar.getCalendarsAsync(Calendar.EntityTypes.EVENT);
      calendarId = (cals.find(c => c.allowsModifications) ?? cals[0])?.id;
    }
    if (!calendarId) return 'error';

    const start = new Date(date); start.setHours(9, 0, 0, 0);
    const end = new Date(date); end.setHours(9, 30, 0, 0);
    await Calendar.createEventAsync(calendarId, {
      title,
      startDate: start,
      endDate: end,
      notes,
      alarms: [{ relativeOffset: -60 * 24 * 7 }], // remind 7 days before
    });
    return 'added';
  } catch {
    return 'error';
  }
}
