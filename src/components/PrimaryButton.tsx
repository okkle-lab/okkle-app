import React from 'react';
import { Pressable, Text, ViewStyle } from 'react-native';
import { colors, radius, font } from '../theme';

type Props = {
  label: string;
  onPress: () => void;
  variant?: 'primary' | 'danger' | 'ghost' | 'warning';
  disabled?: boolean;
  style?: ViewStyle;
};

const VARIANTS = {
  primary: { bg: colors.brand, text: '#fff', border: colors.brand },
  danger: { bg: colors.red, text: '#fff', border: colors.red },
  warning: { bg: colors.amber, text: '#fff', border: colors.amber },
  ghost: { bg: 'transparent', text: colors.brand, border: colors.brand },
};

export function PrimaryButton({ label, onPress, variant = 'primary', disabled, style }: Props) {
  const v = VARIANTS[variant];
  return (
    <Pressable
      onPress={onPress}
      disabled={disabled}
      style={({ pressed }) => [{
        backgroundColor: v.bg,
        borderRadius: radius.lg,
        borderWidth: 1.5,
        borderColor: v.border,
        paddingVertical: 15,
        alignItems: 'center',
        opacity: pressed || disabled ? 0.7 : 1,
      }, style]}
    >
      <Text style={{ color: v.text, fontSize: 15, fontWeight: font.semibold }}>
        {label}
      </Text>
    </Pressable>
  );
}
