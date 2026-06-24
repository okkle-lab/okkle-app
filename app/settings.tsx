import React from 'react';
import { Platform, View, Text, ScrollView, StyleSheet, Pressable } from 'react-native';
import { useRouter } from 'expo-router';
import { colors, font, spacing, radius, type } from '../src/theme';
import { Card, IconBadge, VehicleIcon } from '../src/components';
import { getUser, kvSet } from '../src/db';
import { vehicleLabel } from '../src/db/tax';
import { Feather } from '@expo/vector-icons';

export default function Settings() {
  const router = useRouter();
  const u = getUser();

  const go = (path: any, params?: any) => () => router.push(params ? { pathname: path, params } : path);

  const Row = ({ icon, tone, title, sub, onPress, last }: { icon: any; tone: any; title: string; sub?: string; onPress: () => void; last?: boolean }) => (
    <Pressable onPress={onPress} style={({ pressed }) => [s.row, !last && s.rowBorder, pressed && { backgroundColor: colors.bgSoft }]}>
      <IconBadge icon={icon} tone={tone} size={38} />
      <View style={{ flex: 1 }}>
        <Text style={s.rowTitle}>{title}</Text>
        {sub ? <Text style={s.rowSub} numberOfLines={1}>{sub}</Text> : null}
      </View>
      <Feather name="chevron-right" size={20} color={colors.textTertiary} />
    </Pressable>
  );

  return (
    <ScrollView style={s.screen} contentContainerStyle={s.content}>
      <View style={s.header}>
        <Text style={s.heading}>Settings</Text>
        <Pressable onPress={() => router.back()} hitSlop={12}><Text style={s.close}>Done</Text></Pressable>
      </View>

      {/* Profile summary */}
      <View style={s.profile}>
        <View style={s.avatar}><VehicleIcon vehicle={u?.vehicle ?? 'car'} size={26} color={colors.brandDeep} /></View>
        <View style={{ flex: 1 }}>
          <Text style={s.profileName}>{u?.name || 'Your profile'}</Text>
          <Text style={s.profileSub}>{vehicleLabel(u?.vehicle ?? 'car')} · {u?.platforms?.split(',').filter(Boolean).length ?? 0} platforms</Text>
        </View>
      </View>

      <Card style={{ padding: 0, overflow: 'hidden', marginTop: spacing.lg }}>
        <Row icon="user" tone="mint" title="Profile & tax" sub="Name, vehicle, platforms, tax region" onPress={go('/settings-account')} />
        <Row icon="bell" tone="blue" title="Reminders" sub="Logging nudges & tax deadlines" onPress={go('/settings-reminders')} />
        <Row icon="calendar" tone="amber" title="Key tax dates" sub="HMRC deadlines & add to calendar" onPress={go('/key-dates')} />
        <Row icon="shield" tone="green" title="Data & backup" sub="Back up, restore or delete your data" onPress={go('/settings-data')} last />
      </Card>

      <Card style={{ padding: 0, overflow: 'hidden', marginTop: spacing.lg }}>
        <Row icon="alert-triangle" tone="amber" title="Report a problem" onPress={go('/feedback', { mode: 'problem', screen: 'Settings' })} />
        <Row icon="message-circle" tone="violet" title="Suggest an improvement" onPress={go('/feedback', { mode: 'suggestion', screen: 'Settings' })} />
        <Row icon="help-circle" tone="neutral" title="Replay the app tour" onPress={() => { kvSet('coach_seen', ''); router.back(); }} />
        <Row icon="info" tone="neutral" title="About Okkle" onPress={go('/settings-about')} last />
      </Card>
    </ScrollView>
  );
}

const s = StyleSheet.create({
  screen: { flex: 1, backgroundColor: Platform.OS === 'ios' ? 'transparent' : colors.bg },
  content: { padding: spacing.xl, paddingTop: 60, paddingBottom: 60 },
  header: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: spacing.xl },
  heading: { ...type.screenTitle },
  close: { ...type.bodyMedium, color: colors.brandDeep },
  profile: { flexDirection: 'row', alignItems: 'center', gap: 14 },
  avatar: { width: 52, height: 52, borderRadius: 26, backgroundColor: colors.brandLight, alignItems: 'center', justifyContent: 'center' },
  profileName: { ...type.heading, fontSize: 19 },
  profileSub: { ...type.caption, marginTop: 2 },
  row: { flexDirection: 'row', alignItems: 'center', gap: 12, padding: spacing.lg },
  rowBorder: { borderBottomWidth: 1, borderBottomColor: colors.border },
  rowTitle: { ...type.bodyMedium, fontSize: 15 },
  rowSub: { ...type.caption, marginTop: 2 },
});
