import React from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
import { colors, spacing, type } from '../theme';
import { SettingsGlassButton } from './SettingsGlassButton';

// One consistent header for every screen: title (left), optional extras + the
// settings gear pinned top-right. Keeps navigation predictable (Trading 212 /
// most well-built apps always put account/settings in the same place).
export function ScreenHeader({ title, subtitle, right }: { title: string; subtitle?: string; right?: React.ReactNode }) {
  const router = useRouter();
  return (
    <View style={s.wrap}>
      <View style={s.row}>
        <Text style={s.title} numberOfLines={1}>{title}</Text>
        <View style={s.actions}>
          {right}
          <SettingsGlassButton onPress={() => router.push('/settings')} size={42} />
        </View>
      </View>
      {subtitle ? <Text style={s.sub}>{subtitle}</Text> : null}
    </View>
  );
}

const s = StyleSheet.create({
  wrap: { marginBottom: spacing.lg },
  row: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  title: { ...type.screenTitle, flex: 1 },
  actions: { flexDirection: 'row', alignItems: 'center', gap: 10 },
  sub: { ...type.body, color: colors.textSecondary, marginTop: 6 },
});
