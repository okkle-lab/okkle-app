import React from 'react';
import { View, StyleSheet } from 'react-native';
import { Feather } from '@expo/vector-icons';
import Svg, { Defs, RadialGradient, Stop, Circle, Ellipse } from 'react-native-svg';
import { colors } from '../theme';

type FeatherName = React.ComponentProps<typeof Feather>['name'];

// Soft gradient discs with a top highlight and a coloured glow — gives icons
// depth and warmth (Starling-style) instead of flat tinted circles.
// [light, deep], icon colour, glow colour.
const TONES = {
  mint:    { grad: ['#CFF5EE', '#74D2C0'] as const, fg: colors.brandDeep, glow: colors.brand },
  green:   { grad: ['#D6F2DE', '#82CC9C'] as const, fg: '#1C7048', glow: colors.green },
  amber:   { grad: ['#FBEFCB', '#F0C45F'] as const, fg: '#9A6510', glow: colors.amber },
  red:     { grad: ['#FBD8CF', '#F0A092'] as const, fg: '#A8301E', glow: colors.red },
  blue:    { grad: ['#D9E8FF', '#8DB7F1'] as const, fg: '#1E5BB0', glow: '#3B82E0' },
  violet:  { grad: ['#ECDCFF', '#C29CF0'] as const, fg: '#6A2EA8', glow: '#9B59E0' },
  neutral: { grad: ['#EEEDE7', '#CDCBC3'] as const, fg: colors.textSecondary, glow: '#9CA3A0' },
};

export function IconBadge({ icon, tone = 'mint', size = 38 }: {
  icon: FeatherName;
  tone?: keyof typeof TONES;
  size?: number;
}) {
  const t = TONES[tone];
  const id = `ib-${tone}`;
  return (
    <View style={{
      width: size, height: size,
      shadowColor: t.glow, shadowOpacity: 0.35, shadowRadius: 5, shadowOffset: { width: 0, height: 2 }, elevation: 3,
    }}>
      <Svg width={size} height={size} viewBox="0 0 40 40">
        <Defs>
          <RadialGradient id={id} cx="35%" cy="28%" r="80%">
            <Stop offset="0%" stopColor={t.grad[0]} />
            <Stop offset="100%" stopColor={t.grad[1]} />
          </RadialGradient>
        </Defs>
        <Circle cx="20" cy="20" r="20" fill={`url(#${id})`} />
        <Ellipse cx="14" cy="12" rx="9" ry="5" fill="#ffffff" opacity="0.3" />
      </Svg>
      <View style={[StyleSheet.absoluteFill, s.center]}>
        <Feather name={icon} size={size * 0.46} color={t.fg} />
      </View>
    </View>
  );
}

const s = StyleSheet.create({ center: { alignItems: 'center', justifyContent: 'center' } });
