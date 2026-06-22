import React from 'react';
import { View, Text } from 'react-native';
import Svg, { Defs, RadialGradient, LinearGradient, Stop, Circle, Polygon, Ellipse } from 'react-native-svg';
import type { AchievementTier } from '../db';

// Metallic gradient stops per tier: [highlight, mid, shadow].
const TIER_GRAD: { [k in AchievementTier]: [string, string, string] } = {
  gold:    ['#FCE9A6', '#E0A21F', '#A9690B'],
  silver:  ['#F4F6F9', '#C7CDD6', '#8C95A2'],
  bronze:  ['#E9C39A', '#B87333', '#7E4D1E'],
  special: ['#9BEBDB', '#1FB89A', '#0B7E6A'],
};
const RIBBON: { [k in AchievementTier]: [string, string] } = {
  gold:    ['#E2604A', '#B23A28'],
  silver:  ['#4F77C4', '#33508F'],
  bronze:  ['#5BA86F', '#3C7A4E'],
  special: ['#16998A', '#0E8E78'],
};
const LOCKED: [string, string, string] = ['#E4E2DC', '#C4C2BA', '#9C9A92'];

type Props = { emoji: string; tier: AchievementTier; unlocked: boolean; size?: number };

export function Medal({ emoji, tier, unlocked, size = 64 }: Props) {
  const h = size * 1.28;
  const [hi, mid, lo] = unlocked ? TIER_GRAD[tier] : LOCKED;
  const [rib1, rib2] = unlocked ? RIBBON[tier] : ['#CFCDC6', '#B4B2AA'];
  const id = `${tier}-${unlocked ? 'on' : 'off'}`;

  return (
    <View style={{ width: size, height: h }}>
      <Svg width={size} height={h} viewBox="0 0 100 128">
        <Defs>
          <RadialGradient id={`disc-${id}`} cx="38%" cy="32%" r="75%">
            <Stop offset="0" stopColor={hi} />
            <Stop offset="0.55" stopColor={mid} />
            <Stop offset="1" stopColor={lo} />
          </RadialGradient>
          <LinearGradient id={`rib-${id}`} x1="0" y1="0" x2="0" y2="1">
            <Stop offset="0" stopColor={rib1} />
            <Stop offset="1" stopColor={rib2} />
          </LinearGradient>
        </Defs>

        {/* Ribbon — two crossing strips behind the disc */}
        <Polygon points="32,4 50,4 60,66 42,66" fill={`url(#rib-${id})`} opacity={unlocked ? 1 : 0.6} />
        <Polygon points="68,4 50,4 40,66 58,66" fill={`url(#rib-${id})`} opacity={unlocked ? 0.85 : 0.5} />

        {/* Disc */}
        <Circle cx="50" cy="84" r="40" fill={lo} />
        <Circle cx="50" cy="82" r="40" fill={`url(#disc-${id})`} />
        {/* Rim + inner ring */}
        <Circle cx="50" cy="82" r="40" fill="none" stroke={lo} strokeWidth="2" />
        <Circle cx="50" cy="82" r="32" fill="none" stroke={hi} strokeWidth="1.5" opacity="0.5" />
        {/* Gloss highlight */}
        <Ellipse cx="42" cy="66" rx="22" ry="12" fill="#ffffff" opacity={unlocked ? 0.28 : 0.15} />
      </Svg>

      {/* Emoji sits on the disc */}
      <Text
        style={{
          position: 'absolute',
          top: size * 0.5,
          left: 0,
          right: 0,
          textAlign: 'center',
          fontSize: size * 0.42,
          opacity: unlocked ? 1 : 0.35,
        }}
      >
        {emoji}
      </Text>
    </View>
  );
}
