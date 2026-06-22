import { Stack } from 'expo-router';
import { useEffect } from 'react';
import { initDb } from '../src/db';

export default function RootLayout() {
  useEffect(() => { initDb(); }, []);
  return (
    <Stack screenOptions={{ headerShown: false }}>
      <Stack.Screen name="onboarding" />
      <Stack.Screen name="(tabs)" />
    </Stack>
  );
}
