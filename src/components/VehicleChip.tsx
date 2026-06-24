import React from 'react';
import { Pressable, StyleSheet, Text, View, ViewStyle } from 'react-native';
import { buttonDepth, colors, radius, font } from '../theme';
import { VehicleIcon } from './Icon';

type Props = {
  vehicle: string;
  label: string;
  selected?: boolean;
  onPress?: () => void;
  suffix?: string;
  style?: ViewStyle;
};

export function VehicleChip({ vehicle, label, selected, onPress, suffix, style }: Props) {
  return (
    <Pressable
      onPress={onPress}
      style={({ pressed }) => [
        s.chip,
        buttonDepth.raised,
        {
          borderColor: selected ? colors.brand : colors.borderStrong,
          backgroundColor: selected ? colors.brandLight : colors.bgCard,
        },
        pressed && buttonDepth.pressed,
        style,
      ]}
    >
      <View pointerEvents="none" style={[s.gloss, selected ? buttonDepth.gloss : buttonDepth.glossMuted]} />
      <VehicleIcon vehicle={vehicle} size={20} color={selected ? colors.brandDeep : colors.textSecondary} />
      <Text style={{
        fontSize: 15,
        fontWeight: selected ? font.semibold : font.medium,
        color: selected ? colors.brandDeep : colors.textSecondary,
      }}>
        {label}{suffix ? ` · ${suffix}` : ''}
      </Text>
    </Pressable>
  );
}

const s = StyleSheet.create({
  chip: {
    alignItems: 'center',
    borderCurve: 'continuous',
    borderRadius: radius.full,
    borderWidth: 1.5,
    flexDirection: 'row',
    gap: 8,
    overflow: 'hidden',
    paddingHorizontal: 16,
    paddingVertical: 12,
  },
  gloss: {
    borderRadius: radius.full,
    height: 1,
    left: 14,
    position: 'absolute',
    right: 14,
    top: 1,
  },
});
