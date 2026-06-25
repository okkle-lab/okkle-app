import React from 'react';
import { View } from 'react-native';
import { Feather } from '@expo/vector-icons';
import { colors } from '../theme';

type FeatherName = React.ComponentProps<typeof Feather>['name'];

// Flat tinted circle with the icon — no gradient, shadow or gloss. Clean and
// modern (Google/iOS-settings style) rather than skeuomorphic 3D discs.
// [flat background, icon colour].
const TONES = {
  mint:    { bg: '#E2F6F1', fg: colors.brandDeep },
  green:   { bg: '#DCF2E4', fg: '#1C7048' },
  amber:   { bg: '#FBEECB', fg: '#9A6510' },
  red:     { bg: '#FBDDD4', fg: '#A8301E' },
  blue:    { bg: '#E0EBFF', fg: '#1E5BB0' },
  violet:  { bg: '#EEE2FF', fg: '#6A2EA8' },
  neutral: { bg: '#ECEBE5', fg: colors.textSecondary },
};

export function IconBadge({ icon, tone = 'mint', size = 38 }: {
  icon: FeatherName;
  tone?: keyof typeof TONES;
  size?: number;
}) {
  const t = TONES[tone];
  return (
    <View style={{
      width: size, height: size, borderRadius: size / 2,
      backgroundColor: t.bg, alignItems: 'center', justifyContent: 'center',
    }}>
      <Feather name={icon} size={size * 0.46} color={t.fg} />
    </View>
  );
}
