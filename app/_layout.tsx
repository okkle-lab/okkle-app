import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useEffect } from 'react';
import * as Notifications from 'expo-notifications';
import { initDb } from '../src/db';

const glassSheetOptions = {
  presentation: 'formSheet' as const,
  sheetGrabberVisible: true,
  contentStyle: { backgroundColor: 'transparent' },
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
  useEffect(() => { initDb(); }, []);
  return (
    <>
      <StatusBar style="auto" />
      <Stack screenOptions={{ headerShown: false }}>
        <Stack.Screen name="onboarding" />
        <Stack.Screen name="(tabs)" />
        <Stack.Screen name="settings" options={glassSheetOptions} />
        <Stack.Screen name="settings-account" options={glassSheetOptions} />
        <Stack.Screen name="settings-reminders" options={glassSheetOptions} />
        <Stack.Screen name="settings-data" options={glassSheetOptions} />
        <Stack.Screen name="settings-about" options={glassSheetOptions} />
        <Stack.Screen name="edit" options={{ presentation: 'modal' }} />
        <Stack.Screen name="compare" options={{ presentation: 'modal' }} />
        <Stack.Screen name="medals" options={{ presentation: 'modal' }} />
        <Stack.Screen name="insights" options={{ presentation: 'modal' }} />
        <Stack.Screen name="export" options={{ presentation: 'modal' }} />
        <Stack.Screen name="feedback" options={{ presentation: 'modal' }} />
        <Stack.Screen name="key-dates" options={{ presentation: 'modal' }} />
        <Stack.Screen name="order-check" options={{ presentation: 'modal' }} />
      </Stack>
    </>
  );
}
