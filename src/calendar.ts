import * as Calendar from 'expo-calendar';
import { Platform } from 'react-native';

// Add a tax deadline to the user's device calendar, with a reminder a week
// ahead. Returns true on success. All on-device — we never see the calendar.
export async function addDeadlineToCalendar(title: string, date: Date, notes?: string): Promise<boolean> {
  const { status } = await Calendar.requestCalendarPermissionsAsync();
  if (status !== 'granted') return false;

  let calendarId: string | undefined;
  if (Platform.OS === 'ios') {
    const def = await Calendar.getDefaultCalendarAsync();
    calendarId = def?.id;
  } else {
    const cals = await Calendar.getCalendarsAsync(Calendar.EntityTypes.EVENT);
    calendarId = (cals.find(c => c.allowsModifications) ?? cals[0])?.id;
  }
  if (!calendarId) return false;

  const start = new Date(date); start.setHours(9, 0, 0, 0);
  const end = new Date(date); end.setHours(9, 30, 0, 0);
  await Calendar.createEventAsync(calendarId, {
    title,
    startDate: start,
    endDate: end,
    notes,
    alarms: [{ relativeOffset: -60 * 24 * 7 }], // remind 7 days before
  });
  return true;
}
