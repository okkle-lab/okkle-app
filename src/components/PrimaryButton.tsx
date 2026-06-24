import React from 'react';
import { Pressable, StyleSheet, Text, View, ViewStyle } from 'react-native';
import { buttonDepth, colors, radius, font } from '../theme';

type Props = {
  label: string;
  onPress: () => void;
  variant?: 'primary' | 'danger' | 'ghost' | 'warning';
  disabled?: boolean;
  style?: ViewStyle;
};

const VARIANTS = {
  primary: { bg: colors.brand, text: '#fff', border: colors.brand, gloss: buttonDepth.gloss },
  danger: { bg: colors.red, text: '#fff', border: colors.red, gloss: buttonDepth.gloss },
  warning: { bg: colors.amber, text: '#fff', border: colors.amber, gloss: buttonDepth.gloss },
  ghost: { bg: colors.bgCard, text: colors.brandDeep, border: colors.brand, gloss: buttonDepth.glossMuted },
};

export function PrimaryButton({ label, onPress, variant = 'primary', disabled, style }: Props) {
  const v = VARIANTS[variant];
  return (
    <Pressable
      onPress={onPress}
      disabled={disabled}
      style={({ pressed }) => [
        s.button,
        buttonDepth.raisedStrong,
        {
          backgroundColor: v.bg,
          borderColor: v.border,
          opacity: disabled ? 0.55 : 1,
        },
        pressed && !disabled && buttonDepth.pressed,
        style,
      ]}
    >
      <View pointerEvents="none" style={[s.gloss, v.gloss]} />
      <Text style={{ color: v.text, fontSize: 15, fontWeight: font.semibold }}>
        {label}
      </Text>
    </Pressable>
  );
}

const s = StyleSheet.create({
  button: {
    alignItems: 'center',
    borderCurve: 'continuous',
    borderRadius: radius.lg,
    borderWidth: 1.5,
    overflow: 'hidden',
    paddingVertical: 15,
  },
  gloss: {
    borderRadius: radius.full,
    height: 1.5,
    left: 16,
    position: 'absolute',
    right: 16,
    top: 1,
  },
});
