import { Stack, useRouter } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useEffect } from 'react';
import * as Notifications from 'expo-notifications';
import { initDb } from '../src/db';
import '../src/autoTrip'; // registers the background trip-detection task at load

const glassSheetOptions = {
  presentation: 'transparentModal' as const,
  animation: 'slide_from_bottom' as const,
  contentStyle: { backgroundColor: 'transparent' },
};

const modalOptions = {
  presentation: 'modal' as const,
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
      if ((res.notification.request.content.data as any)?.type === 'autotrip') {
        router.push('/(tabs)/trip');
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
        <Stack.Screen name="settings-reminders" options={modalOptions} />
        <Stack.Screen name="settings-data" options={modalOptions} />
        <Stack.Screen name="settings-about" options={modalOptions} />
        <Stack.Screen name="edit" options={{ presentation: 'modal' }} />
        <Stack.Screen name="compare" options={{ presentation: 'modal' }} />
        <Stack.Screen name="medals" options={{ presentation: 'modal' }} />
        <Stack.Screen name="insights" options={{ presentation: 'modal' }} />
        <Stack.Screen name="export" options={{ presentation: 'modal' }} />
        <Stack.Screen name="feedback" options={{ presentation: 'modal' }} />
        <Stack.Screen name="key-dates" options={{ presentation: 'modal' }} />
        <Stack.Screen name="order-check" options={{ presentation: 'modal' }} />
        <Stack.Screen name="log-earnings" options={{ presentation: 'modal' }} />
        <Stack.Screen name="settings-earnings-shortcut" options={{ presentation: 'modal' }} />
        <Stack.Screen name="settings-auto-trip" options={{ presentation: 'modal' }} />
      </Stack>
    </>
  );
}
