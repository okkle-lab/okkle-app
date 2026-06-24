import React from 'react';
import { Pressable, Text, ViewStyle } from 'react-native';
import { colors, radius, font } from '../theme';

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
      style={[{
        paddingHorizontal: sz.paddingH,
        paddingVertical: sz.paddingV,
        borderRadius: radius.full,
        borderWidth: 1.5,
        borderColor: selected ? colors.brand : colors.borderStrong,
        backgroundColor: selected ? colors.brandLight : colors.bgCard,
      }, style]}
    >
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
