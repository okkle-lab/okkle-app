import { Tabs } from 'expo-router';
import { Feather } from '@expo/vector-icons';
import type { ComponentProps } from 'react';
import { colors, font } from '../../src/theme';

type FeatherName = ComponentProps<typeof Feather>['name'];

// Classic JS tab bar (SDK 54 / Expo Go compatible). The master branch uses the
// native tab bar; this branch keeps it simple so it runs in Expo Go.
const tabs: { name: string; label: string; icon: FeatherName }[] = [
  { name: 'index', label: 'Home', icon: 'home' },
  { name: 'trip', label: 'Trip', icon: 'navigation' },
  { name: 'log', label: 'Log', icon: 'edit-3' },
  { name: 'records', label: 'Records', icon: 'list' },
  { name: 'tax', label: 'Tax', icon: 'pie-chart' },
];

export default function TabLayout() {
  return (
    <Tabs
      screenOptions={{
        headerShown: false,
        tabBarActiveTintColor: colors.brandDeep,
        tabBarInactiveTintColor: colors.textTertiary,
        tabBarStyle: { backgroundColor: colors.bgCard, borderTopColor: colors.border },
        tabBarLabelStyle: { fontSize: 11, fontWeight: font.semibold },
      }}
    >
      {tabs.map(tab => (
        <Tabs.Screen
          key={tab.name}
          name={tab.name}
          options={{
            title: tab.label,
            tabBarIcon: ({ color, size }) => <Feather name={tab.icon} size={size ?? 22} color={color} />,
          }}
        />
      ))}
    </Tabs>
  );
}
