import React from 'react';
import { Pressable, Text, ViewStyle } from 'react-native';
import { colors, radius, font } from '../theme';
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
      style={[{
        flexDirection: 'row', alignItems: 'center', gap: 8,
        paddingHorizontal: 16, paddingVertical: 12, borderRadius: radius.full,
        borderWidth: 1.5,
        borderColor: selected ? colors.brand : colors.borderStrong,
        backgroundColor: selected ? colors.brandLight : colors.bgCard,
      }, style]}
    >
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
