import { Tabs } from 'expo-router';
import { Feather } from '@expo/vector-icons';
import { colors } from '../../src/theme';

type FeatherName = React.ComponentProps<typeof Feather>['name'];

function tabIcon(name: FeatherName) {
  return ({ color }: { color: string }) => <Feather name={name} size={22} color={color} />;
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
        height: 84,
        paddingBottom: 24,
        paddingTop: 8,
      },
      tabBarLabelStyle: { fontSize: 11 },
    }}>
      <Tabs.Screen name="index" options={{ title: 'Home', tabBarIcon: tabIcon('home') }} />
      <Tabs.Screen name="trip" options={{ title: 'Trip', tabBarIcon: tabIcon('navigation') }} />
      <Tabs.Screen name="log" options={{ title: 'Log', tabBarIcon: tabIcon('edit-3') }} />
      <Tabs.Screen name="records" options={{ title: 'Records', tabBarIcon: tabIcon('list') }} />
      <Tabs.Screen name="tax" options={{ title: 'Tax', tabBarIcon: tabIcon('pie-chart') }} />
    </Tabs>
  );
}
