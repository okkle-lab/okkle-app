import React from 'react';
import { Platform, View, Text, ScrollView, StyleSheet, Pressable, useColorScheme, type StyleProp, type ViewStyle } from 'react-native';
import { useRouter } from 'expo-router';
import { BlurView } from 'expo-blur';
import { colors, font, spacing, radius, type } from '../src/theme';
import { IconBadge, VehicleIcon } from '../src/components';
import { getUser, kvSet } from '../src/db';
import { vehicleLabel } from '../src/db/tax';
import { Feather } from '@expo/vector-icons';

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

function LiquidGlassPanel({ children, style }: { children: React.ReactNode; style?: StyleProp<ViewStyle> }) {
  const isDark = useColorScheme() === 'dark';
  const glassEffect = getGlassEffectModule();
  const GlassView = glassEffect?.GlassView;
  const useLiquidGlass = canUseLiquidGlass() && GlassView;
  const tint = Platform.OS === 'ios' ? 'systemMaterial' : isDark ? 'dark' : 'light';

  return (
    <View style={[s.glassPanel, isDark && s.glassPanelDark, !useLiquidGlass && s.fallbackPanel, style]}>
      {useLiquidGlass ? (
        <GlassView
          pointerEvents="none"
          glassEffectStyle="clear"
          colorScheme={isDark ? 'dark' : 'light'}
          tintColor={isDark ? 'rgba(20,31,28,0.14)' : 'rgba(255,255,255,0.04)'}
          style={StyleSheet.absoluteFill}
        />
      ) : (
        <BlurView pointerEvents="none" intensity={82} tint={tint} style={StyleSheet.absoluteFill} />
      )}
      <View pointerEvents="none" style={[StyleSheet.absoluteFill, s.panelHighlight, isDark && s.panelHighlightDark]} />
      <View pointerEvents="none" style={[s.panelTopSheen, isDark && s.panelTopSheenDark]} />
      <View pointerEvents="none" style={[s.panelBottomEdge, isDark && s.panelBottomEdgeDark]} />
      {children}
    </View>
  );
}

export default function Settings() {
  const router = useRouter();
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
      <ScrollView style={s.screen} contentContainerStyle={s.content}>
        <View style={s.header}>
          <Text style={s.heading}>Settings</Text>
          <Pressable onPress={() => router.back()} hitSlop={12}><Text style={s.close}>Done</Text></Pressable>
        </View>

        {/* Profile summary */}
        <LiquidGlassPanel style={s.profile}>
          <View style={s.avatar}><VehicleIcon vehicle={u?.vehicle ?? 'car'} size={26} color={colors.brandDeep} /></View>
          <View style={{ flex: 1 }}>
            <Text style={s.profileName}>{u?.name || 'Your profile'}</Text>
            <Text style={s.profileSub}>{vehicleLabel(u?.vehicle ?? 'car')} · {u?.platforms?.split(',').filter(Boolean).length ?? 0} platforms</Text>
          </View>
        </LiquidGlassPanel>

        <LiquidGlassPanel style={{ marginTop: spacing.lg }}>
          <Row icon="user" tone="mint" title="Profile & tax" sub="Name, vehicle, platforms, tax region" onPress={go('/settings-account')} />
          <Row icon="bell" tone="blue" title="Reminders" sub="Logging nudges & tax deadlines" onPress={go('/settings-reminders')} />
          <Row icon="calendar" tone="amber" title="Key tax dates" sub="HMRC deadlines & add to calendar" onPress={go('/key-dates')} />
          <Row icon="shield" tone="green" title="Data & backup" sub="Back up, restore or delete your data" onPress={go('/settings-data')} last />
        </LiquidGlassPanel>

        <LiquidGlassPanel style={{ marginTop: spacing.lg }}>
          <Row icon="alert-triangle" tone="amber" title="Report a problem" onPress={go('/feedback', { mode: 'problem', screen: 'Settings' })} />
          <Row icon="message-circle" tone="violet" title="Suggest an improvement" onPress={go('/feedback', { mode: 'suggestion', screen: 'Settings' })} />
          <Row icon="help-circle" tone="neutral" title="Replay the app tour" onPress={() => { kvSet('coach_seen', ''); router.back(); }} />
          <Row icon="info" tone="neutral" title="About Okkle" onPress={go('/settings-about')} last />
        </LiquidGlassPanel>
      </ScrollView>
    </View>
  );
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: Platform.OS === 'ios' ? 'transparent' : colors.bg },
  screen: { flex: 1, position: 'relative', zIndex: 1, backgroundColor: Platform.OS === 'ios' ? 'transparent' : colors.bg },
  content: { padding: spacing.xl, paddingTop: 60, paddingBottom: 60 },
  header: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: spacing.xl },
  heading: { ...type.screenTitle },
  close: { ...type.bodyMedium, color: colors.brandDeep },
  glassPanel: {
    borderRadius: radius.xl,
    overflow: 'hidden',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.76)',
    backgroundColor: 'rgba(247,255,252,0.42)',
    boxShadow: '0 18px 42px rgba(21,33,29,0.12), inset 0 1px 0 rgba(255,255,255,0.72), inset 0 -1px 0 rgba(20,33,29,0.05)',
  },
  glassPanelDark: {
    borderColor: 'rgba(255,255,255,0.18)',
    backgroundColor: 'rgba(255,255,255,0.045)',
    boxShadow: '0 18px 40px rgba(0,0,0,0.26), inset 0 1px 0 rgba(255,255,255,0.12), inset 0 -1px 0 rgba(0,0,0,0.20)',
  },
  panelHighlight: {
    borderRadius: radius.xl,
    borderTopWidth: 1,
    borderLeftWidth: 1,
    borderColor: 'rgba(255,255,255,0.46)',
    backgroundColor: 'rgba(255,255,255,0.08)',
  },
  panelHighlightDark: {
    borderColor: 'rgba(255,255,255,0.12)',
    backgroundColor: 'rgba(255,255,255,0.025)',
  },
  panelTopSheen: {
    position: 'absolute',
    top: 0,
    left: 12,
    right: 12,
    height: 36,
    borderRadius: 18,
    backgroundColor: 'rgba(255,255,255,0.24)',
  },
  panelTopSheenDark: {
    backgroundColor: 'rgba(255,255,255,0.045)',
  },
  panelBottomEdge: {
    position: 'absolute',
    left: 18,
    right: 18,
    bottom: 0,
    height: 1,
    backgroundColor: 'rgba(255,255,255,0.70)',
  },
  panelBottomEdgeDark: {
    backgroundColor: 'rgba(255,255,255,0.12)',
  },
  fallbackPanel: {
    backgroundColor: 'rgba(247,255,252,0.72)',
  },
  profile: { flexDirection: 'row', alignItems: 'center', gap: 14, padding: spacing.lg },
  avatar: { width: 52, height: 52, borderRadius: 26, backgroundColor: 'rgba(226,246,241,0.82)', alignItems: 'center', justifyContent: 'center' },
  profileName: { ...type.heading, fontSize: 19 },
  profileSub: { ...type.caption, marginTop: 2 },
  row: { flexDirection: 'row', alignItems: 'center', gap: 12, padding: spacing.lg },
  rowPressed: { backgroundColor: 'rgba(255,255,255,0.18)' },
  rowBorder: { borderBottomWidth: 1, borderBottomColor: colors.border },
  rowTitle: { ...type.bodyMedium, fontSize: 15 },
  rowSub: { ...type.caption, marginTop: 2 },
});
