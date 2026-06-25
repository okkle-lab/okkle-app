import React from 'react';
import { BlurView } from 'expo-blur';
import {
  Platform, StyleSheet, useColorScheme, View,
  type StyleProp, type ViewStyle,
} from 'react-native';
import { colors, radius as radii, spacing } from '../theme';

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

type GlassTone = 'green' | 'deepGreen' | 'red' | 'blue' | 'amber' | 'neutral';

type Props = {
  children: React.ReactNode;
  tone?: GlassTone;
  radius?: number;
  minHeight?: number;
  isInteractive?: boolean;
  style?: StyleProp<ViewStyle>;
  clipStyle?: StyleProp<ViewStyle>;
  contentStyle?: StyleProp<ViewStyle>;
};

const LIGHT_TINT: Record<GlassTone, string> = {
  green: 'rgba(226,246,241,0.58)',
  deepGreen: 'rgba(14,142,120,0.32)',
  red: 'rgba(251,234,229,0.54)',
  blue: 'rgba(218,234,255,0.58)',
  amber: 'rgba(251,239,214,0.58)',
  neutral: 'rgba(255,255,255,0.48)',
};

const DARK_TINT: Record<GlassTone, string> = {
  green: 'rgba(31,184,154,0.18)',
  deepGreen: 'rgba(31,184,154,0.24)',
  red: 'rgba(226,96,74,0.18)',
  blue: 'rgba(67,139,226,0.18)',
  amber: 'rgba(224,150,31,0.18)',
  neutral: 'rgba(255,255,255,0.12)',
};

const LIGHT_WASH: Record<GlassTone, string> = {
  green: 'rgba(31,184,154,0.16)',
  deepGreen: 'rgba(14,142,120,0.74)',
  red: 'rgba(226,96,74,0.14)',
  blue: 'rgba(47,128,237,0.14)',
  amber: 'rgba(224,150,31,0.14)',
  neutral: 'rgba(242,244,241,0.52)',
};

const DARK_WASH: Record<GlassTone, string> = {
  green: 'rgba(31,184,154,0.09)',
  deepGreen: 'rgba(14,142,120,0.64)',
  red: 'rgba(226,96,74,0.08)',
  blue: 'rgba(47,128,237,0.08)',
  amber: 'rgba(224,150,31,0.08)',
  neutral: 'rgba(58,66,62,0.28)',
};

export function GlassPanel({
  children,
  tone = 'green',
  radius = radii.xl,
  minHeight,
  isInteractive,
  style,
  clipStyle,
  contentStyle,
}: Props) {
  const isDark = useColorScheme() === 'dark';
  const glassEffect = getGlassEffectModule();
  const GlassView = glassEffect?.GlassView;
  const useLiquidGlass = canUseLiquidGlass() && GlassView;

  return (
    <View style={[s.shell, { borderRadius: radius }, style]}>
      <View style={[s.clip, { borderRadius: radius, minHeight }, clipStyle]}>
        {useLiquidGlass ? (
          <GlassView
            pointerEvents="none"
            glassEffectStyle="regular"
            colorScheme={isDark ? 'dark' : 'light'}
            isInteractive={isInteractive}
            tintColor={isDark ? DARK_TINT[tone] : LIGHT_TINT[tone]}
            style={s.material}
          />
        ) : (
          <BlurView
            pointerEvents="none"
            intensity={86}
            tint={Platform.OS === 'ios' ? 'systemMaterial' : isDark ? 'dark' : 'light'}
            style={s.material}
          />
        )}
        <View pointerEvents="none" style={[s.wash, { backgroundColor: isDark ? DARK_WASH[tone] : LIGHT_WASH[tone] }]} />
        <View style={[s.content, contentStyle]}>{children}</View>
      </View>
    </View>
  );
}

const s = StyleSheet.create({
  shell: {
    boxShadow: '0 16px 34px rgba(31,184,154,0.14), 0 3px 10px rgba(27,38,33,0.08)',
  },
  clip: {
    overflow: 'hidden',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.58)',
    backgroundColor: colors.bgCard,
  },
  material: { ...StyleSheet.absoluteFill, overflow: 'hidden' },
  wash: { ...StyleSheet.absoluteFill },
  content: { padding: spacing.lg },
});
