import React from 'react';
import { Platform, View, Text, ScrollView, StyleSheet, Pressable, useColorScheme } from 'react-native';
import { useRouter } from 'expo-router';
import { BlurView } from 'expo-blur';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Feather } from '@expo/vector-icons';
import { colors, spacing, radius, type } from '../src/theme';
import { IconBadge, VehicleIcon } from '../src/components';
import { getUser, kvSet } from '../src/db';
import { vehicleLabel } from '../src/db/tax';

declare const require: (moduleName: string) => any;

type GlassEffectModule = {
  GlassView?: React.ComponentType<any>;
  isGlassEffectAPIAvailable?: () => boolean;
};

let glassEffectModule: GlassEffectModule | null | undefined;

function getGlassEffectModule() {
  if (glassEffectModule !== undefined) return glassEffectModule;

  try {
    glassEffectModule = require('expo-glass-effect') as GlassEffectModule;
  } catch {
    glassEffectModule = null;
  }

  return glassEffectModule;
}

function canUseLiquidGlass() {
  const glassEffect = getGlassEffectModule();
  if (Platform.OS !== 'ios' || !glassEffect?.GlassView || !glassEffect.isGlassEffectAPIAvailable) return false;

  try {
    return glassEffect.isGlassEffectAPIAvailable();
  } catch {
    return false;
  }
}

function GlassSheetBackground() {
  const isDark = useColorScheme() === 'dark';
  const glassEffect = getGlassEffectModule();
  const GlassView = glassEffect?.GlassView;
  const useLiquidGlass = canUseLiquidGlass() && GlassView;
  const tint = Platform.OS === 'ios' ? 'systemUltraThinMaterial' : isDark ? 'dark' : 'light';

  return (
    <View pointerEvents="none" style={StyleSheet.absoluteFill}>
      {useLiquidGlass ? (
        <GlassView
          pointerEvents="none"
          glassEffectStyle="regular"
          colorScheme={isDark ? 'dark' : 'light'}
          tintColor={isDark ? 'rgba(16,24,22,0.18)' : 'rgba(255,255,255,0.08)'}
          style={StyleSheet.absoluteFill}
        />
      ) : (
        <BlurView pointerEvents="none" intensity={88} tint={tint} style={StyleSheet.absoluteFill} />
      )}
      <View style={[s.sheetTint, isDark && s.sheetTintDark]} />
      <View style={[s.sheetTopSheen, isDark && s.sheetTopSheenDark]} />
      <View style={[s.sheetInnerStroke, isDark && s.sheetInnerStrokeDark]} />
    </View>
  );
}

export default function Settings() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const u = getUser();

  const go = (path: any, params?: any) => () => router.push(params ? { pathname: path, params } : path);

  const Row = ({ icon, tone, title, sub, onPress, last }: { icon: any; tone: any; title: string; sub?: string; onPress: () => void; last?: boolean }) => (
    <Pressable onPress={onPress} style={({ pressed }) => [s.row, !last && s.rowBorder, pressed && s.rowPressed]}>
      <IconBadge icon={icon} tone={tone} size={38} />
      <View style={{ flex: 1 }}>
        <Text style={s.rowTitle}>{title}</Text>
        {sub ? <Text style={s.rowSub} numberOfLines={1}>{sub}</Text> : null}
      </View>
      <Feather name="chevron-right" size={20} color={colors.textTertiary} />
    </Pressable>
  );

  return (
    <View style={s.root}>
      <Pressable accessibilityLabel="Close settings" onPress={() => router.back()} style={s.scrim} />
      <View style={[s.sheet, { top: Math.max(insets.top + 42, 82) }]}>
        <GlassSheetBackground />
        <View style={s.grabber} />
        <ScrollView style={s.screen} contentContainerStyle={[s.content, { paddingBottom: Math.max(insets.bottom + 28, 48) }]}>
          <View style={s.header}>
            <Text style={s.heading}>Settings</Text>
            <Pressable onPress={() => router.back()} hitSlop={12}>
              <Text style={s.close}>Done</Text>
            </Pressable>
          </View>

          <View style={s.profile}>
            <View style={s.avatar}>
              <VehicleIcon vehicle={u?.vehicle ?? 'car'} size={26} color={colors.brandDeep} />
            </View>
            <View style={{ flex: 1 }}>
              <Text style={s.profileName}>{u?.name || 'Your profile'}</Text>
              <Text style={s.profileSub}>
                {vehicleLabel(u?.vehicle ?? 'car')} · {u?.platforms?.split(',').filter(Boolean).length ?? 0} platforms
              </Text>
            </View>
          </View>

          <View style={s.group}>
            <Row icon="user" tone="mint" title="Profile & tax" sub="Name, vehicle, platforms, tax region" onPress={go('/settings-account')} />
            <Row icon="bell" tone="blue" title="Reminders" sub="Logging nudges & tax deadlines" onPress={go('/settings-reminders')} />
            <Row icon="calendar" tone="amber" title="Key tax dates" sub="HMRC deadlines & add to calendar" onPress={go('/key-dates')} />
            <Row icon="shield" tone="green" title="Data & backup" sub="Back up, restore or delete your data" onPress={go('/settings-data')} last />
          </View>

          <View style={s.group}>
            <Row icon="alert-triangle" tone="amber" title="Report a problem" onPress={go('/feedback', { mode: 'problem', screen: 'Settings' })} />
            <Row icon="message-circle" tone="violet" title="Suggest an improvement" onPress={go('/feedback', { mode: 'suggestion', screen: 'Settings' })} />
            <Row icon="help-circle" tone="neutral" title="Replay the app tour" onPress={() => { kvSet('coach_seen', ''); router.back(); }} />
            <Row icon="info" tone="neutral" title="About Okkle" onPress={go('/settings-about')} last />
          </View>
        </ScrollView>
      </View>
    </View>
      <Card style={{ padding: 0, overflow: 'hidden', marginTop: spacing.lg }}>
        <Row icon="user" tone="mint" title="Profile & tax" sub="Name, vehicle, platforms, tax region" onPress={go('/settings-account')} />
        <Row icon="bell" tone="blue" title="Reminders" sub="Logging nudges & tax deadlines" onPress={go('/settings-reminders')} />
        <Row icon="calendar" tone="amber" title="Key tax dates" sub="HMRC deadlines & add to calendar" onPress={go('/key-dates')} />
        <Row icon="navigation" tone="mint" title="Auto-detect trips" sub="Suggest tracking when you start driving" onPress={go('/settings-auto-trip')} />
        <Row icon="camera" tone="violet" title="Auto-log earnings" sub="Screenshot a pay screen → log it" onPress={go('/settings-earnings-shortcut')} />
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
  root: { flex: 1, backgroundColor: 'transparent', justifyContent: 'flex-end' },
  scrim: {
    ...StyleSheet.absoluteFill,
    backgroundColor: 'rgba(0,0,0,0.18)',
  },
  sheet: {
    position: 'absolute',
    right: 0,
    bottom: 0,
    left: 0,
    overflow: 'hidden',
    borderTopLeftRadius: 36,
    borderTopRightRadius: 36,
    borderWidth: 1,
    borderBottomWidth: 0,
    borderColor: 'rgba(255,255,255,0.52)',
    boxShadow: '0 -18px 42px rgba(21,33,29,0.20), inset 0 1px 0 rgba(255,255,255,0.55)',
  },
  sheetTint: {
    ...StyleSheet.absoluteFill,
    backgroundColor: 'rgba(255,255,255,0.22)',
  },
  sheetTintDark: {
    backgroundColor: 'rgba(10,16,14,0.28)',
  },
  sheetTopSheen: {
    position: 'absolute',
    top: 0,
    left: 20,
    right: 20,
    height: 74,
    borderRadius: 37,
    backgroundColor: 'rgba(255,255,255,0.28)',
  },
  sheetTopSheenDark: {
    backgroundColor: 'rgba(255,255,255,0.055)',
  },
  sheetInnerStroke: {
    ...StyleSheet.absoluteFill,
    borderTopLeftRadius: 36,
    borderTopRightRadius: 36,
    borderWidth: 1,
    borderBottomWidth: 0,
    borderColor: 'rgba(255,255,255,0.42)',
  },
  sheetInnerStrokeDark: {
    borderColor: 'rgba(255,255,255,0.10)',
  },
  grabber: {
    position: 'absolute',
    top: 10,
    alignSelf: 'center',
    width: 54,
    height: 5,
    borderRadius: 999,
    zIndex: 2,
    backgroundColor: 'rgba(34,48,44,0.22)',
  },
  screen: { flex: 1, position: 'relative', zIndex: 1, backgroundColor: 'transparent' },
  content: { padding: spacing.xl, paddingTop: 58, gap: spacing.lg },
  header: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  heading: { ...type.screenTitle },
  close: { ...type.bodyMedium, color: colors.brandDeep },
  profile: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 14,
    paddingVertical: spacing.md,
  },
  group: {
    overflow: 'hidden',
    borderRadius: radius.xl,
    backgroundColor: 'rgba(255,255,255,0.38)',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.42)',
  },
  avatar: {
    width: 52,
    height: 52,
    borderRadius: 26,
    backgroundColor: 'rgba(226,246,241,0.72)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  profileName: { ...type.heading, fontSize: 19 },
  profileSub: { ...type.caption, marginTop: 2 },
  row: { flexDirection: 'row', alignItems: 'center', gap: 12, padding: spacing.lg },
  rowPressed: { backgroundColor: 'rgba(255,255,255,0.24)' },
  rowBorder: { borderBottomWidth: 1, borderBottomColor: 'rgba(34,48,44,0.10)' },
  rowTitle: { ...type.bodyMedium, fontSize: 15 },
  rowSub: { ...type.caption, marginTop: 2 },
});
