import React from 'react';
import { Platform, View, Text, StyleSheet, Pressable, useColorScheme } from 'react-native';
import { useRouter } from 'expo-router';
import { BlurView } from 'expo-blur';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { Feather } from '@expo/vector-icons';
import { colors, spacing, radius, type } from '../src/theme';
import { IconBadge } from '../src/components';

declare const require: (moduleName: string) => any;

type GlassEffectModule = {
  GlassView?: React.ComponentType<any>;
  isGlassEffectAPIAvailable?: () => boolean;
};

type Tone = React.ComponentProps<typeof IconBadge>['tone'];
type FeatherName = React.ComponentProps<typeof Feather>['name'];

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
  const tint = isDark ? 'dark' : 'light';

  return (
    <View pointerEvents="none" style={StyleSheet.absoluteFill}>
      {useLiquidGlass ? (
        <GlassView
          pointerEvents="none"
          glassEffectStyle="regular"
          colorScheme={isDark ? 'dark' : 'light'}
          isInteractive
          tintColor={isDark ? 'rgba(13,22,20,0.20)' : 'rgba(255,255,255,0.18)'}
          style={s.materialFill}
        />
      ) : (
        <BlurView pointerEvents="none" intensity={isDark ? 84 : 78} tint={tint} style={s.materialFill} />
      )}
      <View style={[s.sheetTint, isDark && s.sheetTintDark]} />
      <View style={[s.sheetTopSheen, isDark && s.sheetTopSheenDark]} />
      <View style={[s.sheetBottomShade, isDark && s.sheetBottomShadeDark]} />
      <View style={[s.sheetInnerStroke, isDark && s.sheetInnerStrokeDark]} />
    </View>
  );
}

export default function Settings() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const isDark = useColorScheme() === 'dark';

  const go = (path: any) => () => router.push(path);

  const Row = ({ icon, tone, title, sub, onPress, last }: { icon: FeatherName; tone: Tone; title: string; sub: string; onPress: () => void; last?: boolean }) => (
    <Pressable onPress={onPress} style={({ pressed }) => [s.row, !last && s.rowBorder, pressed && s.rowPressed]}>
      <IconBadge icon={icon} tone={tone} size={36} />
      <View style={s.rowText}>
        <Text style={s.rowTitle} numberOfLines={1}>{title}</Text>
        <Text style={s.rowSub} numberOfLines={1}>{sub}</Text>
      </View>
      <Feather name="chevron-right" size={20} color={colors.textTertiary} />
    </Pressable>
  );

  return (
    <View style={s.root}>
      <Pressable accessibilityLabel="Close settings" onPress={() => router.back()} style={s.scrim} />
      <View style={[s.sheet, isDark && s.sheetDark, { top: 0 }]}>
        <GlassSheetBackground />
        <View style={[s.content, { paddingTop: insets.top + 14, paddingBottom: Math.max(insets.bottom + 22, 38) }]}>
          <View style={s.header}>
            <Text style={s.heading}>Settings</Text>
            <Pressable onPress={() => router.back()} hitSlop={12} style={s.closeBtn}>
              <Feather name="x" size={19} color={colors.textPrimary} />
            </Pressable>
          </View>

          <View style={s.group}>
            <Row icon="user" tone="mint" title="Profile" sub="Name, vehicles, platforms & accountant details" onPress={go('/settings-account')} />
            <Row icon="percent" tone="amber" title="Tax settings" sub="Region, band, other income & method" onPress={go('/tax-setup')} />
            <Row icon="navigation" tone="blue" title="Trip nudges" sub="Reminders to start & end a trip" onPress={go('/settings-auto-trip')} />
            <Row icon="bell" tone="violet" title="Reminders" sub="Logging nudges & deadline alerts" onPress={go('/settings-reminders')} />
            <Row icon="upload" tone="green" title="Export & share" sub="Accountant pack & FreeAgent CSV" onPress={go('/export')} />
            <Row icon="database" tone="blue" title="Data & backup" sub="Back up, restore or delete" onPress={go('/settings-data')} />
            <Row icon="help-circle" tone="neutral" title="Help & feedback" sub="Support, tour & app info" onPress={go('/settings-help')} />
            <Row icon="activity" tone="amber" title="Diagnostics" sub="Capture & share issues if something breaks" onPress={go('/settings-diagnostics')} last />
          </View>
        </View>
      </View>
    </View>
  );
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: 'transparent', justifyContent: 'flex-end' },
  scrim: { ...StyleSheet.absoluteFill, backgroundColor: 'rgba(0,0,0,0.12)' },
  sheet: {
    position: 'absolute', right: 0, bottom: 0, left: 0, overflow: 'hidden',
    borderTopLeftRadius: 0, borderTopRightRadius: 0, borderWidth: 1, borderBottomWidth: 0,
    borderColor: 'rgba(255,255,255,0.58)', backgroundColor: 'transparent',
  },
  sheetDark: { borderColor: 'rgba(255,255,255,0.14)', backgroundColor: 'transparent' },
  materialFill: { ...StyleSheet.absoluteFill, borderTopLeftRadius: 0, borderTopRightRadius: 0 },
  sheetTint: { ...StyleSheet.absoluteFill, backgroundColor: 'rgba(255,255,255,0.18)' },
  sheetTintDark: { backgroundColor: 'rgba(8,15,13,0.22)' },
  sheetTopSheen: { position: 'absolute', top: 0, left: 0, right: 0, height: 96, backgroundColor: 'rgba(255,255,255,0.16)' },
  sheetTopSheenDark: { backgroundColor: 'rgba(255,255,255,0.035)' },
  sheetBottomShade: { position: 'absolute', left: 0, right: 0, bottom: 0, height: 180, backgroundColor: 'rgba(226,246,241,0.08)' },
  sheetBottomShadeDark: { backgroundColor: 'rgba(0,0,0,0.06)' },
  sheetInnerStroke: { ...StyleSheet.absoluteFill, borderTopLeftRadius: 0, borderTopRightRadius: 0, borderWidth: 1, borderBottomWidth: 0, borderColor: 'rgba(255,255,255,0.50)' },
  sheetInnerStrokeDark: { borderColor: 'rgba(255,255,255,0.10)' },
  grabber: { position: 'absolute', top: 10, alignSelf: 'center', width: 54, height: 5, borderRadius: 999, zIndex: 2, backgroundColor: 'rgba(34,48,44,0.22)' },
  content: { position: 'relative', zIndex: 1, paddingHorizontal: spacing.xl, paddingTop: 58, gap: spacing.lg },
  header: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  heading: { ...type.screenTitle },
  closeBtn: { width: 34, height: 34, borderRadius: 17, alignItems: 'center', justifyContent: 'center', backgroundColor: 'rgba(34,48,44,0.10)' },
  group: { overflow: 'hidden', borderRadius: radius.xl, backgroundColor: 'rgba(255,255,255,0.18)', borderWidth: 1, borderColor: 'rgba(255,255,255,0.30)' },
  row: { flexDirection: 'row', alignItems: 'center', gap: 12, minHeight: 64, paddingHorizontal: spacing.lg, paddingVertical: spacing.sm },
  rowText: { flex: 1, minWidth: 0 },
  rowPressed: { backgroundColor: 'rgba(255,255,255,0.24)' },
  rowBorder: { borderBottomWidth: 1, borderBottomColor: 'rgba(34,48,44,0.10)' },
  rowTitle: { ...type.bodyMedium, fontSize: 16 },
  rowSub: { ...type.caption, marginTop: 2 },
});
