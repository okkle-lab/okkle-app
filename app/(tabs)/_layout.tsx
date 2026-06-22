import { Tabs } from 'expo-router';
import { Text } from 'react-native';
import { colors } from '../../src/theme';

function Icon({ emoji, focused }: { emoji: string; focused: boolean }) {
  return <Text style={{ fontSize: 20, opacity: focused ? 1 : 0.45 }}>{emoji}</Text>;
}

export default function TabLayout() {
  return (
    <Tabs screenOptions={{
      headerShown: false,
      tabBarActiveTintColor: colors.brand,
      tabBarInactiveTintColor: colors.textTertiary,
      tabBarStyle: {
        borderTopColor: colors.border,
        borderTopWidth: 1,
        backgroundColor: colors.bg,
        height: 80,
        paddingBottom: 20,
        paddingTop: 8,
      },
      tabBarLabelStyle: { fontSize: 11 },
    }}>
      <Tabs.Screen name="index" options={{ title: 'Home', tabBarIcon: ({ focused }) => <Icon emoji="🏠" focused={focused} /> }} />
      <Tabs.Screen name="trip" options={{ title: 'Trip', tabBarIcon: ({ focused }) => <Icon emoji="📍" focused={focused} /> }} />
      <Tabs.Screen name="log" options={{ title: 'Log', tabBarIcon: ({ focused }) => <Icon emoji="✏️" focused={focused} /> }} />
      <Tabs.Screen name="records" options={{ title: 'Records', tabBarIcon: ({ focused }) => <Icon emoji="📋" focused={focused} /> }} />
      <Tabs.Screen name="export" options={{ title: 'Export', tabBarIcon: ({ focused }) => <Icon emoji="📤" focused={focused} /> }} />
    </Tabs>
  );
}
