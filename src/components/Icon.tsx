import React from 'react';
import Feather from '@expo/vector-icons/Feather';
import { colors } from '../theme';

type FeatherName = React.ComponentProps<typeof Feather>['name'];

// Flat UI icon (Feather) — minimal line style, matches the warm/clean theme.
export function Icon({ name, size = 20, color = colors.textPrimary }: {
  name: FeatherName; size?: number; color?: string;
}) {
  return <Feather name={name} size={size} color={color} />;
}

const VEHICLE_ICON: { [k: string]: FeatherName } = {
  car: 'navigation',
  motorbike: 'zap',
  bike: 'activity',
  van: 'truck',
};

export function VehicleIcon({ vehicle, size = 20, color = colors.textPrimary }: {
  vehicle: string; size?: number; color?: string;
}) {
  return <Feather name={VEHICLE_ICON[vehicle] ?? 'navigation'} size={size} color={color} />;
}
