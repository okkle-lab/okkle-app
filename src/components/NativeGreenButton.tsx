import React from 'react';
import { BlurView } from 'expo-blur';
import {
  Platform, Pressable, StyleSheet, Text, useColorScheme, View,
  type StyleProp, type ViewStyle,
} from 'react-native';
import { colors, font, radius } from '../theme';

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

type Props = {
  label: string;
  onPress: () => void;
  disabled?: boolean;
  variant?: 'filled' | 'outlined' | 'neutral';
  style?: StyleProp<ViewStyle>;
  height?: number;
  leftIcon?: React.ReactNode;
};

export function NativeGreenButton({ label, onPress, disabled, variant = 'filled', style, height = 54, leftIcon }: Props) {
  const isDark = useColorScheme() === 'dark';
  const glassEffect = getGlassEffectModule();
  const GlassView = glassEffect?.GlassView;
  const useLiquidGlass = canUseLiquidGlass() && GlassView;
  const filled = variant === 'filled' || variant === 'neutral';
  const neutral = variant === 'neutral';
  const outlined = variant === 'outlined';

  return (
    <Pressable
      onPress={onPress}
      disabled={disabled}
      style={({ pressed }) => [
        s.outer,
        { height, opacity: disabled ? 0.62 : pressed ? 0.86 : 1 },
        neutral ? s.neutralOuter : filled ? s.filledOuter : s.outlinedOuter,
        isDark && neutral && s.neutralOuterDark,
        isDark && filled && !neutral && s.filledOuterDark,
        style,
      ]}
    >
      <View style={[s.clip, { borderRadius: height / 2 }, neutral && s.neutralClip, outlined && s.outlinedClip]}>
        {filled && useLiquidGlass ? (
          <GlassView
            pointerEvents="none"
            glassEffectStyle="regular"
            colorScheme={isDark ? 'dark' : 'light'}
            isInteractive
            tintColor={
              neutral
                ? isDark ? 'rgba(255,255,255,0.12)' : 'rgba(255,255,255,0.44)'
                : isDark ? 'rgba(31,184,154,0.24)' : 'rgba(154,245,216,0.36)'
            }
            style={s.material}
          />
        ) : filled ? (
          <BlurView
            pointerEvents="none"
            intensity={86}
            tint={Platform.OS === 'ios' ? 'systemMaterial' : isDark ? 'dark' : 'light'}
            style={s.material}
          />
        ) : null}
        {filled ? (
          <View
            pointerEvents="none"
            style={[
              s.colorWash,
              neutral ? s.neutralWash : s.greenWash,
              isDark && neutral && s.neutralWashDark,
              isDark && !neutral && s.greenWashDark,
            ]}
          />
        ) : null}
        <View style={s.content}>
          {leftIcon}
          <Text
            style={[
              s.label,
              neutral ? s.neutralLabel : filled ? s.filledLabel : s.outlinedLabel,
              disabled && s.disabledLabel,
            ]}
            numberOfLines={1}
          >
            {label}
          </Text>
        </View>
      </View>
    </Pressable>
  );
}

const s = StyleSheet.create({
  outer: { width: '100%', borderRadius: radius.full },
  filledOuter: {
    boxShadow: '0 15px 28px rgba(31,184,154,0.24), 0 4px 10px rgba(14,142,120,0.16)',
  },
  filledOuterDark: {
    boxShadow: '0 16px 30px rgba(31,184,154,0.18), 0 5px 12px rgba(0,0,0,0.22)',
  },
  neutralOuter: {
    boxShadow: '0 10px 22px rgba(27,38,33,0.08), 0 2px 8px rgba(27,38,33,0.06)',
  },
  neutralOuterDark: {
    boxShadow: '0 12px 24px rgba(0,0,0,0.18), 0 2px 8px rgba(0,0,0,0.16)',
  },
  outlinedOuter: {},
  clip: {
    flex: 1, overflow: 'hidden', alignItems: 'center', justifyContent: 'center',
    backgroundColor: colors.brand,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.54)',
  },
  outlinedClip: {
    backgroundColor: colors.bgCard,
    borderWidth: 1.5,
    borderColor: colors.border,
  },
  neutralClip: {
    backgroundColor: colors.bgSoft,
    borderColor: 'rgba(255,255,255,0.72)',
  },
  material: { ...StyleSheet.absoluteFill, overflow: 'hidden' },
  colorWash: {
    ...StyleSheet.absoluteFill,
  },
  greenWash: {
    backgroundColor: 'rgba(14,142,120,0.74)',
  },
  greenWashDark: {
    backgroundColor: 'rgba(31,184,154,0.58)',
  },
  neutralWash: {
    backgroundColor: 'rgba(242,244,241,0.82)',
  },
  neutralWashDark: {
    backgroundColor: 'rgba(58,66,62,0.74)',
  },
  content: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 8,
    paddingHorizontal: 18,
  },
  label: { fontSize: 16, fontWeight: font.semibold },
  filledLabel: { color: '#fff' },
  neutralLabel: { color: colors.textPrimary },
  outlinedLabel: { color: colors.brandDeep },
  disabledLabel: { color: colors.textTertiary },
});
