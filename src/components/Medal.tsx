import React from 'react';
import { View } from 'react-native';
import { Feather } from '@expo/vector-icons';
import Svg, { Defs, RadialGradient, LinearGradient, Stop, Circle, Polygon, Ellipse, G } from 'react-native-svg';
import type { AchievementTier } from '../db';

type FeatherName = React.ComponentProps<typeof Feather>['name'];

// Each category has its OWN colour identity (disc gradient + ribbon + burst),
// so medals look distinct at a glance. Tier drives the "fancy" ornamentation:
// bronze = plain, silver = studded rim, gold = starburst + sparkles,
// special = bigger burst + sparkles. [highlight, mid, shadow], [ribbon a, b], burst.
type Palette = { disc: [string, string, string]; ribbon: [string, string]; burst: string };

const CATEGORY: { [c: string]: Palette } = {
  Trips:         { disc: ['#BBD9FF', '#3B82E0', '#1E5BB0'], ribbon: ['#2C4C8A', '#1C3460'], burst: '#7FB0F0' },
  Miles:         { disc: ['#9FEDE0', '#14B8A6', '#0B7E70'], ribbon: ['#0E8E78', '#0B6E5E'], burst: '#5FD0BB' },
  'Tax saved':   { disc: ['#BBEFC4', '#2FA36B', '#1C7048'], ribbon: ['#1C7048', '#124F32'], burst: '#7FD6A0' },
  Earnings:      { disc: ['#FCE9A6', '#E0A21F', '#9E5E08'], ribbon: ['#B5740F', '#8A5510'], burst: '#FBD24B' },
  Streaks:       { disc: ['#FFD3A6', '#F2761F', '#B5450F'], ribbon: ['#E2604A', '#B23A28'], burst: '#FFAE6B' },
  Hours:         { disc: ['#C9C2FF', '#6C5CE7', '#4334B0'], ribbon: ['#5634D6', '#3A2399'], burst: '#A99BFF' },
  'Active days': { disc: ['#FFC2E0', '#E0469B', '#A81E6E'], ribbon: ['#C2316E', '#8A1E4E'], burst: '#FF8FC4' },
  'Big days':    { disc: ['#FFC0B5', '#E2604A', '#A8301E'], ribbon: ['#B23A28', '#7E1E12'], burst: '#FF9080' },
  'Long trips':  { disc: ['#E9C39A', '#B87333', '#7E4D1E'], ribbon: ['#7E4D1E', '#5A3614'], burst: '#D8A06B' },
  Platforms:     { disc: ['#E0C2FF', '#9B59E0', '#6A2EA8'], ribbon: ['#7C4DB8', '#56308A'], burst: '#C99BFF' },
  Special:       { disc: ['#A9F0E2', '#15C2A6', '#0A7A68'], ribbon: ['#7C5CFF', '#5634D6'], burst: '#5FE6CF' },
};
const FALLBACK = CATEGORY.Special;
const LOCKED: Palette = { disc: ['#E4E2DC', '#C4C2BA', '#9C9A92'], ribbon: ['#CFCDC6', '#B4B2AA'], burst: '#D7D5CE' };

type Props = { icon: FeatherName; category: string; tier: AchievementTier; unlocked: boolean; size?: number };

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

export function Medal({ icon, category, tier, unlocked, size = 64 }: Props) {
  const h = size * 1.3;
  const pal = unlocked ? (CATEGORY[category] ?? FALLBACK) : LOCKED;
  const [hi, mid, lo] = pal.disc;
  const [rib1, rib2] = pal.ribbon;
  const id = `${category}-${tier}-${unlocked ? 'on' : 'off'}`.replace(/\s/g, '');

  const cx = 50, cy = 84, r = 36;
  const hasBurst = unlocked && (tier === 'gold' || tier === 'special');
  const spikes = tier === 'special' ? 12 : 16;
  const sparkle = hasBurst;

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

        <Polygon points="32,4 50,4 60,68 42,68" fill={`url(#rib-${id})`} opacity={unlocked ? 1 : 0.6} />
        <Polygon points="68,4 50,4 40,68 58,68" fill={`url(#rib-${id})`} opacity={unlocked ? 0.85 : 0.5} />

        {hasBurst && (
          <>
            <Polygon points={starPoints(cx, cy, spikes, r + 14, r + 3)} fill={pal.burst} opacity={0.55} />
            <Polygon points={starPoints(cx, cy, spikes, r + 9, r + 2)} fill={pal.burst} opacity={0.9} />
          </>
        )}

        {/* Soft glow halo so the medal lifts off the surface */}
        {unlocked && <Circle cx={cx} cy={cy} r={r + 4} fill={pal.disc[1]} opacity={0.22} />}
        <Circle cx={cx} cy={cy + 2} r={r} fill={lo} />
        <Circle cx={cx} cy={cy} r={r} fill={`url(#disc-${id})`} />
        <Circle cx={cx} cy={cy} r={r} fill="none" stroke={lo} strokeWidth="2.5" />
        <Circle cx={cx} cy={cy} r={r - 7} fill="none" stroke={hi} strokeWidth={tier === 'gold' ? 2 : 1.4} opacity="0.55" />

        {unlocked && tier === 'silver' && Array.from({ length: 12 }).map((_, i) => {
          const a = (i / 12) * Math.PI * 2;
          return <Circle key={i} cx={cx + Math.cos(a) * (r - 3.5)} cy={cy + Math.sin(a) * (r - 3.5)} r="1.3" fill={lo} opacity="0.6" />;
        })}

        <Ellipse cx={cx - 8} cy={cy - 16} rx="20" ry="11" fill="#ffffff" opacity={unlocked ? 0.34 : 0.15} />

        {sparkle && (
          <G opacity="0.95">
            <Polygon points={starPoints(30, 52, 4, 4.5, 1.6)} fill="#ffffff" />
            <Polygon points={starPoints(72, 60, 4, 3.4, 1.2)} fill="#ffffff" />
            <Polygon points={starPoints(64, 40, 4, 2.6, 1)} fill="#ffffff" />
          </G>
        )}
      </Svg>

      <View style={{ position: 'absolute', top: size * 0.5, left: 0, right: 0, alignItems: 'center', opacity: unlocked ? 1 : 0.4 }}>
        <Feather name={icon} size={size * 0.34} color={unlocked ? '#ffffff' : '#7E7C76'} />
      </View>
    </View>
  );
}
