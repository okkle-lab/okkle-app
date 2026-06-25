import { Stack, useRouter } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useEffect } from 'react';
import * as Notifications from 'expo-notifications';
import { initDb } from '../src/db';
import '../src/autoTrip'; // registers the background trip-detection task at load
import { endShiftNow } from '../src/shift';

const glassSheetOptions = {
  presentation: 'transparentModal' as const,
  animation: 'slide_from_bottom' as const,
  contentStyle: { backgroundColor: 'transparent' },
};

// Full-screen (not the iOS half-sheet that peeks the parent and wastes ~180px of
// height) so content-heavy settings/forms fit without scrolling.
const modalOptions = {
  presentation: 'fullScreenModal' as const,
};

Notifications.setNotificationHandler({
  handleNotification: async () => ({
    shouldShowBanner: true,
    shouldShowList: true,
    shouldPlaySound: false,
    shouldSetBadge: false,
  }),
});

export default function RootLayout() {
  const router = useRouter();
  useEffect(() => { initDb(); }, []);

  // Tapping the "On the move — track this trip?" suggestion opens the Trip tab,
  // where the user confirms by hitting Start (we never auto-record).
  useEffect(() => {
    const sub = Notifications.addNotificationResponseReceivedListener(res => {
      const type = (res.notification.request.content.data as any)?.type;
      if (type === 'autotrip' || type === 'tripActive' || type === 'shiftActive') {
        router.push('/(tabs)/trip');
      } else if (type === 'shiftEnded') {
        router.push('/shift-review');
      } else if (type === 'shiftMaybeEnded') {
        // "Done for the day?" — finalize the shift now, then open the review.
        endShiftNow();
        router.push('/shift-review');
      }
    });
    return () => sub.remove();
  }, []);

  return (
    <>
      <StatusBar style="auto" />
      <Stack screenOptions={{ headerShown: false }}>
        <Stack.Screen name="onboarding" />
        <Stack.Screen name="(tabs)" />
        <Stack.Screen name="settings" options={glassSheetOptions} />
        <Stack.Screen name="settings-account" options={modalOptions} />
        <Stack.Screen name="settings-help" options={modalOptions} />
        <Stack.Screen name="settings-reminders" options={modalOptions} />
        <Stack.Screen name="settings-data" options={modalOptions} />
        <Stack.Screen name="settings-about" options={modalOptions} />
        <Stack.Screen name="edit" options={modalOptions} />
        <Stack.Screen name="compare" options={modalOptions} />
        <Stack.Screen name="medals" options={modalOptions} />
        <Stack.Screen name="insights" options={modalOptions} />
        <Stack.Screen name="export" options={modalOptions} />
        <Stack.Screen name="feedback" options={modalOptions} />
        <Stack.Screen name="key-dates" options={modalOptions} />
        <Stack.Screen name="order-check" options={modalOptions} />
        <Stack.Screen name="log-earnings" options={modalOptions} />
        <Stack.Screen name="settings-earnings-shortcut" options={modalOptions} />
        <Stack.Screen name="settings-auto-trip" options={modalOptions} />
        <Stack.Screen name="shift-review" options={modalOptions} />
      </Stack>
    </>
  );
}
