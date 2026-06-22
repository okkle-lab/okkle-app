import React from 'react';
import { Feather, MaterialCommunityIcons } from '@expo/vector-icons';
import { colors } from '../theme';

type FeatherName = React.ComponentProps<typeof Feather>['name'];
type MciName = React.ComponentProps<typeof MaterialCommunityIcons>['name'];

// Flat UI icon (Feather) — minimal line style, matches the warm/clean theme.
export function Icon({ name, size = 20, color = colors.textPrimary }: {
  name: FeatherName; size?: number; color?: string;
}) {
  return <Feather name={name} size={size} color={color} />;
}

const VEHICLE_ICON: { [k: string]: MciName } = {
  car: 'car',
  motorbike: 'motorbike',
  bike: 'bike',
  van: 'van-utility',
};

export function VehicleIcon({ vehicle, size = 20, color = colors.textPrimary }: {
  vehicle: string; size?: number; color?: string;
}) {
  return <MaterialCommunityIcons name={VEHICLE_ICON[vehicle] ?? 'car'} size={size} color={color} />;
}
