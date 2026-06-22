import React from 'react';
import { View, Text } from 'react-native';
import Svg, { Defs, RadialGradient, LinearGradient, Stop, Circle, Polygon, Ellipse, G } from 'react-native-svg';
import type { AchievementTier } from '../db';

// Metallic gradient stops per tier: [highlight, mid, shadow].
const TIER_GRAD: { [k in AchievementTier]: [string, string, string] } = {
  bronze:  ['#E9C39A', '#B87333', '#7E4D1E'],
  silver:  ['#F7F9FC', '#C7CDD6', '#868F9C'],
  gold:    ['#FFF3B0', '#E8A81C', '#9E5E08'],
  special: ['#A9F0E2', '#15C2A6', '#0A7A68'],
};
const RIBBON: { [k in AchievementTier]: [string, string] } = {
  bronze:  ['#5BA86F', '#3C7A4E'],
  silver:  ['#4F77C4', '#33508F'],
  gold:    ['#E2604A', '#B23A28'],
  special: ['#7C5CFF', '#5634D6'],
};
const BURST: { [k in AchievementTier]: string } = {
  bronze: '#CD8A4E', silver: '#D7DCE3', gold: '#FBD24B', special: '#5FE6CF',
};
const LOCKED: [string, string, string] = ['#E4E2DC', '#C4C2BA', '#9C9A92'];

type Props = { emoji: string; tier: AchievementTier; unlocked: boolean; size?: number };

// Build an N-point star polygon (for the gold/special burst behind the disc).
function starPoints(cx: number, cy: number, spikes: number, outer: number, inner: number): string {
  const pts: string[] = [];
  let rot = -Math.PI / 2;
  const step = Math.PI / spikes;
  for (let i = 0; i < spikes; i++) {
    pts.push(`${(cx + Math.cos(rot) * outer).toFixed(1)},${(cy + Math.sin(rot) * outer).toFixed(1)}`); rot += step;
    pts.push(`${(cx + Math.cos(rot) * inner).toFixed(1)},${(cy + Math.sin(rot) * inner).toFixed(1)}`); rot += step;
  }
  return pts.join(' ');
}

export function Medal({ emoji, tier, unlocked, size = 64 }: Props) {
  const h = size * 1.3;
  const [hi, mid, lo] = unlocked ? TIER_GRAD[tier] : LOCKED;
  const [rib1, rib2] = unlocked ? RIBBON[tier] : ['#CFCDC6', '#B4B2AA'];
  const burst = unlocked ? BURST[tier] : '#D7D5CE';
  const id = `${tier}-${unlocked ? 'on' : 'off'}`;

  const cx = 50, cy = 84, r = 36;
  // Fancier tiers get a starburst behind the disc; gold = 16 points, special = 12.
  const hasBurst = unlocked && (tier === 'gold' || tier === 'special');
  const spikes = tier === 'special' ? 12 : 16;
  const sparkle = unlocked && (tier === 'gold' || tier === 'special');

  return (
    <View style={{ width: size, height: h }}>
      <Svg width={size} height={h} viewBox="0 0 100 132">
        <Defs>
          <RadialGradient id={`disc-${id}`} cx="38%" cy="30%" r="78%">
            <Stop offset="0" stopColor={hi} />
            <Stop offset="0.5" stopColor={mid} />
            <Stop offset="1" stopColor={lo} />
          </RadialGradient>
          <LinearGradient id={`rib-${id}`} x1="0" y1="0" x2="0" y2="1">
            <Stop offset="0" stopColor={rib1} />
            <Stop offset="1" stopColor={rib2} />
          </LinearGradient>
        </Defs>

        {/* Ribbon — two crossing strips behind the disc */}
        <Polygon points="32,4 50,4 60,68 42,68" fill={`url(#rib-${id})`} opacity={unlocked ? 1 : 0.6} />
        <Polygon points="68,4 50,4 40,68 58,68" fill={`url(#rib-${id})`} opacity={unlocked ? 0.85 : 0.5} />

        {/* Starburst behind disc for top tiers */}
        {hasBurst && (
          <>
            <Polygon points={starPoints(cx, cy, spikes, r + 14, r + 3)} fill={burst} opacity={0.55} />
            <Polygon points={starPoints(cx, cy, spikes, r + 9, r + 2)} fill={burst} opacity={0.9} />
          </>
        )}

        {/* Disc base + face */}
        <Circle cx={cx} cy={cy + 2} r={r} fill={lo} />
        <Circle cx={cx} cy={cy} r={r} fill={`url(#disc-${id})`} />
        {/* Outer rim */}
        <Circle cx={cx} cy={cy} r={r} fill="none" stroke={lo} strokeWidth="2.5" />
        {/* Silver/gold get an inner engraved ring */}
        <Circle cx={cx} cy={cy} r={r - 7} fill="none" stroke={hi} strokeWidth={tier === 'gold' ? 2 : 1.4} opacity="0.55" />

        {/* Silver studs around the rim */}
        {unlocked && tier === 'silver' && Array.from({ length: 12 }).map((_, i) => {
          const a = (i / 12) * Math.PI * 2;
          return <Circle key={i} cx={cx + Math.cos(a) * (r - 3.5)} cy={cy + Math.sin(a) * (r - 3.5)} r="1.3" fill={lo} opacity="0.6" />;
        })}

        {/* Specular gloss */}
        <Ellipse cx={cx - 8} cy={cy - 16} rx="20" ry="11" fill="#ffffff" opacity={unlocked ? 0.34 : 0.15} />

        {/* Sparkles for gold/special */}
        {sparkle && (
          <G opacity="0.95">
            <Polygon points={starPoints(30, 52, 4, 4.5, 1.6)} fill="#ffffff" />
            <Polygon points={starPoints(72, 60, 4, 3.4, 1.2)} fill="#ffffff" />
            <Polygon points={starPoints(64, 40, 4, 2.6, 1)} fill="#ffffff" />
          </G>
        )}
      </Svg>

      {/* Emoji sits on the disc */}
      <Text
        style={{
          position: 'absolute',
          top: size * 0.52,
          left: 0,
          right: 0,
          textAlign: 'center',
          fontSize: size * 0.4,
          opacity: unlocked ? 1 : 0.35,
        }}
      >
        {emoji}
      </Text>
    </View>
  );
}
