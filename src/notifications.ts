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

// Playful, Duolingo-style nudges. One is picked at random each time we
// (re)schedule, so the tone varies over time and never feels robotic.
const STREAK_NUDGES: { title: string; body: string }[] = [
  { title: 'Your streak misses you 🥺', body: 'One quick trip keeps it alive. Okkle is watching… in a friendly way.' },
  { title: "Don't break the chain! 🔗", body: 'Log a trip today and keep that streak glowing.' },
  { title: 'Psst… 🛵', body: 'Every mile you track is tax you keep. Open Okkle before bed?' },
  { title: 'Tax-free miles await ✨', body: "You've come too far to drop the streak now. Tap to log today." },
  { title: 'Your future self says thanks 🙏', body: 'Two taps to log today. January-you will be very grateful.' },
  { title: 'Keep the engine warm 🔥', body: 'A quick log today keeps your streak — and your tax savings — rolling.' },
];

const WEEKLY_NUDGES: string[] = [
  'Payday soon? Log this week’s earnings so nothing slips through 🛵',
  'Weekly check-in: a minute now saves a headache in January 📒',
  'Your miles = money back. Log this week’s trips and earnings ✨',
  'Quick one — how did the week go? Pop your miles and pay in 🚀',
];

function pick<T>(arr: T[]): T { return arr[Math.floor(Math.random() * arr.length)]; }

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

  // Weekly/monthly logging reminder — playful, varied copy.
  if (user.reminder_enabled) {
    const monthly = user.log_frequency === 'monthly';
    const body = monthly
      ? 'New month, fresh miles 🛵 Log last month’s trips and earnings.'
      : pick(WEEKLY_NUDGES);
    await Notifications.scheduleNotificationAsync({
      content: { title: 'Okkle', body },
      trigger: {
        type: Notifications.SchedulableTriggerInputTypes.WEEKLY,
        weekday: WEEKDAY_TO_NUM[user.reminder_day] ?? 1,
        hour: 18, minute: 0,
      },
    });

    // Daily streak-keeper — the Duolingo-style "don't lose your streak" nudge.
    // (Only when logging weekly; monthly users don't get a daily ping.)
    if (!monthly) {
      const nudge = pick(STREAK_NUDGES);
      await Notifications.scheduleNotificationAsync({
        content: { title: nudge.title, body: nudge.body },
        trigger: {
          type: Notifications.SchedulableTriggerInputTypes.DAILY,
          hour: 19, minute: 30,
        },
      });
    }
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
