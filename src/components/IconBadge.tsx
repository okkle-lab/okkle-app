import React from 'react';
import { View } from 'react-native';
import { Feather } from '@expo/vector-icons';
import { colors } from '../theme';

type FeatherName = React.ComponentProps<typeof Feather>['name'];

// A soft tinted circle around an icon — brings colour and depth back to lists
// without clutter. Pick a tone per category.
const TONES = {
  mint: { bg: colors.brandLight, fg: colors.brandDeep },
  green: { bg: colors.greenLight, fg: colors.green },
  amber: { bg: colors.amberLight, fg: colors.amber },
  red: { bg: colors.redLight, fg: colors.red },
  neutral: { bg: colors.bgSoft, fg: colors.textSecondary },
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
      <Feather name={icon} size={size * 0.5} color={t.fg} />
    </View>
  );
}
