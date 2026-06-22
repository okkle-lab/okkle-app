import * as Notifications from 'expo-notifications';
import { Platform } from 'react-native';
import type { User } from './db';
import { kvGet } from './db';

const WEEKDAYS = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'];

// Key UK Self Assessment / MTD dates. We remind ~2 weeks ahead, yearly.
// month is 1-12.
const TAX_DEADLINES: { month: number; day: number; title: string; body: string }[] = [
  { month: 9, day: 21, title: 'Register for Self Assessment', body: 'If this was your first year self-employed, register with HMRC by 5 October.' },
  { month: 1, day: 17, title: 'Tax return & payment due soon', body: 'File your online Self Assessment and pay your tax by 31 January.' },
  { month: 7, day: 17, title: 'Second payment on account', body: 'Your 31 July payment on account is due in two weeks.' },
  { month: 7, day: 31, title: 'MTD quarterly update (Q1)', body: 'Your 6 Apr–5 Jul quarterly update is due 7 August.' },
  { month: 10, day: 31, title: 'MTD quarterly update (Q2)', body: 'Your 6 Jul–5 Oct quarterly update is due 7 November.' },
  { month: 1, day: 31, title: 'MTD quarterly update (Q3)', body: 'Your 6 Oct–5 Jan quarterly update is due 7 February.' },
  { month: 4, day: 30, title: 'MTD quarterly update (Q4)', body: 'Your 6 Jan–5 Apr quarterly update is due 7 May.' },
];
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

// Cancel everything and (re)schedule logging reminders + tax-deadline reminders.
export async function syncReminders(user: User): Promise<void> {
  await Notifications.cancelAllScheduledNotificationsAsync();
  const ok = await ensurePermission();
  if (!ok) return;

  if (Platform.OS === 'android') {
    await Notifications.setNotificationChannelAsync('reminders', {
      name: 'Reminders',
      importance: Notifications.AndroidImportance.DEFAULT,
    });
  }

  // Weekly/monthly logging reminder.
  if (user.reminder_enabled) {
    const monthly = user.log_frequency === 'monthly';
    const body = monthly
      ? 'Time to log this month’s delivery miles and earnings 🛵'
      : 'Quick check-in — log this week’s miles and earnings 🛵';
    await Notifications.scheduleNotificationAsync({
      content: { title: 'Okkle reminder', body },
      trigger: {
        type: Notifications.SchedulableTriggerInputTypes.WEEKLY,
        weekday: WEEKDAY_TO_NUM[user.reminder_day] ?? 1,
        hour: 18, minute: 0,
      },
    });
  }

  // Tax-deadline reminders (on by default; toggle stored in kv).
  if ((kvGet('deadline_reminders') ?? 'on') !== 'off') {
    for (const d of TAX_DEADLINES) {
      await Notifications.scheduleNotificationAsync({
        content: { title: d.title, body: d.body },
        trigger: {
          type: Notifications.SchedulableTriggerInputTypes.YEARLY,
          month: d.month, day: d.day, hour: 9, minute: 0,
        },
      });
    }
  }
}

export { WEEKDAYS };
