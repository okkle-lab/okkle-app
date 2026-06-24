import React from 'react';
import { Pressable, StyleSheet, Text, View, ViewStyle } from 'react-native';
import { buttonDepth, colors, radius, font } from '../theme';

type Props = {
  label: string;
  selected?: boolean;
  onPress?: () => void;
  size?: 'md' | 'lg';
  style?: ViewStyle;
};

const SIZES = {
  md: { paddingH: 14, paddingV: 9, fontSize: 14 },
  lg: { paddingH: 18, paddingV: 13, fontSize: 16 },
};

export function Chip({ label, selected, onPress, size = 'md', style }: Props) {
  const sz = SIZES[size];
  return (
    <Pressable
      onPress={onPress}
      style={({ pressed }) => [
        s.chip,
        buttonDepth.raised,
        {
          paddingHorizontal: sz.paddingH,
          paddingVertical: sz.paddingV,
          borderColor: selected ? colors.brand : colors.borderStrong,
          backgroundColor: selected ? colors.brandLight : colors.bgCard,
        },
        pressed && buttonDepth.pressed,
        style,
      ]}
    >
      <View pointerEvents="none" style={[s.gloss, selected ? buttonDepth.gloss : buttonDepth.glossMuted]} />
      <Text style={{
        fontSize: sz.fontSize,
        fontWeight: selected ? font.semibold : font.medium,
        color: selected ? colors.brandDeep : colors.textSecondary,
      }}>
        {label}
      </Text>
    </Pressable>
  );
}

const s = StyleSheet.create({
  chip: {
    borderCurve: 'continuous',
    borderRadius: radius.full,
    borderWidth: 1.5,
    overflow: 'hidden',
  },
  gloss: {
    borderRadius: radius.full,
    height: 1,
    left: 12,
    position: 'absolute',
    right: 12,
    top: 1,
  },
});
