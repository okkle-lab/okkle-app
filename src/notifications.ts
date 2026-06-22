import * as Notifications from 'expo-notifications';
import { Platform } from 'react-native';
import type { User } from './db';

const WEEKDAYS = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'];
// expo-notifications weekday: 1 = Sunday … 7 = Saturday
const WEEKDAY_TO_NUM: { [k: string]: number } = {
  sun: 1, mon: 2, tue: 3, wed: 4, thu: 5, fri: 6, sat: 7,
};

export async function ensurePermission(): Promise<boolean> {
  const { status } = await Notifications.getPermissionsAsync();
  if (status === 'granted') return true;
  const req = await Notifications.requestPermissionsAsync();
  return req.status === 'granted';
}

// Cancel any existing reminders and (re)schedule based on the user's prefs.
export async function syncReminders(user: User): Promise<void> {
  await Notifications.cancelAllScheduledNotificationsAsync();
  if (!user.reminder_enabled) return;
  const ok = await ensurePermission();
  if (!ok) return;

  const monthly = user.log_frequency === 'monthly';
  const body = monthly
    ? 'Time to log this month’s delivery miles and earnings 🛵'
    : 'Quick check-in — log this week’s miles and earnings 🛵';

  if (Platform.OS === 'android') {
    await Notifications.setNotificationChannelAsync('reminders', {
      name: 'Logging reminders',
      importance: Notifications.AndroidImportance.DEFAULT,
    });
  }

  await Notifications.scheduleNotificationAsync({
    content: { title: 'Okkle reminder', body },
    trigger: {
      type: Notifications.SchedulableTriggerInputTypes.WEEKLY,
      weekday: WEEKDAY_TO_NUM[user.reminder_day] ?? 1,
      hour: 18,
      minute: 0,
    },
  });
}

export { WEEKDAYS };
