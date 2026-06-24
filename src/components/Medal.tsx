import React from 'react';
import { StyleSheet, View } from 'react-native';
import { Feather } from '@expo/vector-icons';
import Svg, { Defs, RadialGradient, LinearGradient, Stop, Circle, Polygon, Ellipse, G, Path } from 'react-native-svg';
import type { AchievementTier } from '../db';

type FeatherName = React.ComponentProps<typeof Feather>['name'];

// Glass-token palette: surface tint, saturated core, deep edge, icon tone and glow.
type Palette = {
  glass: [string, string, string];
  core: [string, string];
  edge: string;
  icon: string;
  glow: string;
};

const CATEGORY: { [c: string]: Palette } = {
  Trips:         { glass: ['#F7FBFF', '#DCEBFF', '#8DB7F1'], core: ['#BBD9FF', '#3B82E0'], edge: '#1E5BB0', icon: '#174786', glow: '#7FB0F0' },
  Miles:         { glass: ['#F6FFFD', '#CDF6EE', '#72DDCF'], core: ['#9FEDE0', '#14B8A6'], edge: '#0B7E70', icon: '#086A5E', glow: '#5FD0BB' },
  'Tax saved':   { glass: ['#F8FFF9', '#D9F6DF', '#8ED9A7'], core: ['#BBEFC4', '#2FA36B'], edge: '#1C7048', icon: '#15583A', glow: '#7FD6A0' },
  Earnings:      { glass: ['#FFFDF3', '#FDECB6', '#F2C85A'], core: ['#FCE9A6', '#E0A21F'], edge: '#9E5E08', icon: '#7A4A07', glow: '#FBD24B' },
  Streaks:       { glass: ['#FFF8F0', '#FFD8AE', '#FF9A63'], core: ['#FFD3A6', '#F2761F'], edge: '#B5450F', icon: '#85380D', glow: '#FFAE6B' },
  Hours:         { glass: ['#FBFAFF', '#DED9FF', '#9D91F2'], core: ['#C9C2FF', '#6C5CE7'], edge: '#4334B0', icon: '#33278C', glow: '#A99BFF' },
  'Active days': { glass: ['#FFF7FB', '#FFD6EA', '#F084BD'], core: ['#FFC2E0', '#E0469B'], edge: '#A81E6E', icon: '#7E1553', glow: '#FF8FC4' },
  'Big days':    { glass: ['#FFF7F5', '#FFD4CC', '#EF8A78'], core: ['#FFC0B5', '#E2604A'], edge: '#A8301E', icon: '#7F2418', glow: '#FF9080' },
  'Long trips':  { glass: ['#FFF9F2', '#EFD2B1', '#C58A4E'], core: ['#E9C39A', '#B87333'], edge: '#7E4D1E', icon: '#5D3714', glow: '#D8A06B' },
  Platforms:     { glass: ['#FCF8FF', '#E8D4FF', '#B780EE'], core: ['#E0C2FF', '#9B59E0'], edge: '#6A2EA8', icon: '#4F227F', glow: '#C99BFF' },
  Special:       { glass: ['#F2FFFC', '#BDF5EC', '#65E0CF'], core: ['#A9F0E2', '#15C2A6'], edge: '#0A7A68', icon: '#064F45', glow: '#5FE6CF' },
};
const FALLBACK = CATEGORY.Special;
const LOCKED: Palette = {
  glass: ['#FFFFFF', '#EEF2F0', '#CBD5D0'],
  core: ['#F4F6F5', '#CAD3CF'],
  edge: '#98A39D',
  icon: '#7C8781',
  glow: '#DCE4E0',
};

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

function ringDots(cx: number, cy: number, count: number, dist: number) {
  return Array.from({ length: count }).map((_, i) => {
    const a = (i / count) * Math.PI * 2;
    return { x: cx + Math.cos(a) * dist, y: cy + Math.sin(a) * dist };
  });
}

export function Medal({ icon, category, tier, unlocked, size = 64 }: Props) {
  const h = size;
  const pal = unlocked ? (CATEGORY[category] ?? FALLBACK) : LOCKED;
  const [glassHi, glassMid, glassLow] = pal.glass;
  const [coreHi, coreLow] = pal.core;
  const id = `${category}-${tier}-${unlocked ? 'on' : 'off'}`.replace(/[^a-zA-Z0-9_-]/g, '');

  const cx = 60, cy = 60;
  const hasBurst = unlocked && (tier === 'gold' || tier === 'special');
  const spikes = tier === 'special' ? 12 : 16;
  const dots = unlocked && (tier === 'silver' || tier === 'gold' || tier === 'special');
  const iconSize = size * (tier === 'special' ? 0.34 : 0.32);

  return (
    <View
      style={[
        s.wrap,
        {
          width: size,
          height: h,
          opacity: unlocked ? 1 : 0.74,
          boxShadow: unlocked
            ? '0 12px 24px rgba(21,33,29,0.16), -5px -5px 12px rgba(255,255,255,0.9), inset 0 1px 0 rgba(255,255,255,0.72)'
            : 'inset 4px 4px 10px rgba(21,33,29,0.08), inset -4px -4px 10px rgba(255,255,255,0.9)',
        },
      ]}
    >
      <Svg width={size} height={h} viewBox="0 0 120 120">
        <Defs>
          <RadialGradient id={`halo-${id}`} cx="50%" cy="52%" r="54%">
            <Stop offset="0%" stopColor={pal.glow} stopOpacity={unlocked ? 0.52 : 0.18} />
            <Stop offset="100%" stopColor={pal.glow} stopOpacity="0" />
          </RadialGradient>
          <LinearGradient id={`shell-${id}`} x1="18%" y1="10%" x2="84%" y2="92%">
            <Stop offset="0%" stopColor="#FFFFFF" />
            <Stop offset="34%" stopColor={glassHi} />
            <Stop offset="68%" stopColor={glassMid} />
            <Stop offset="100%" stopColor={glassLow} />
          </LinearGradient>
          <RadialGradient id={`well-${id}`} cx="34%" cy="28%" r="78%">
            <Stop offset="0%" stopColor="#FFFFFF" stopOpacity="0.95" />
            <Stop offset="40%" stopColor={coreHi} stopOpacity="0.9" />
            <Stop offset="100%" stopColor={coreLow} stopOpacity="0.82" />
          </RadialGradient>
          <LinearGradient id={`glass-${id}`} x1="24%" y1="12%" x2="80%" y2="74%">
            <Stop offset="0%" stopColor="#FFFFFF" stopOpacity="0.82" />
            <Stop offset="52%" stopColor="#FFFFFF" stopOpacity="0.18" />
            <Stop offset="100%" stopColor="#FFFFFF" stopOpacity="0.04" />
          </LinearGradient>
          <LinearGradient id={`rim-${id}`} x1="20%" y1="14%" x2="86%" y2="84%">
            <Stop offset="0%" stopColor="#FFFFFF" stopOpacity="0.95" />
            <Stop offset="48%" stopColor={pal.edge} stopOpacity="0.16" />
            <Stop offset="100%" stopColor={pal.edge} stopOpacity="0.38" />
          </LinearGradient>
        </Defs>

        <Circle cx={cx} cy={cy} r="56" fill={`url(#halo-${id})`} />
        <Ellipse cx={cx} cy="101" rx="38" ry="10" fill="#15211D" opacity={unlocked ? 0.12 : 0.06} />

        {hasBurst && (
          <>
            <Polygon points={starPoints(cx, cy, spikes, 55, 46)} fill={pal.glow} opacity={tier === 'special' ? 0.38 : 0.24} />
            <Polygon points={starPoints(cx, cy, spikes, 49, 42)} fill="#FFFFFF" opacity={tier === 'special' ? 0.2 : 0.12} />
          </>
        )}

        <Circle cx={cx} cy={cy} r="45" fill={`url(#shell-${id})`} />
        <Circle cx={cx} cy={cy} r="45" fill="none" stroke={`url(#rim-${id})`} strokeWidth="5" />
        <Circle cx={cx} cy={cy} r="35" fill={`url(#well-${id})`} />
        <Circle cx="62" cy="63" r="30" fill="none" stroke={pal.edge} strokeWidth="7" opacity={unlocked ? 0.16 : 0.08} />
        <Circle cx="56" cy="54" r="32" fill="none" stroke="#FFFFFF" strokeWidth="4" opacity={unlocked ? 0.58 : 0.44} />
        <Path d="M25 48 C35 23 80 18 96 45 C78 37 49 36 25 48 Z" fill={`url(#glass-${id})`} opacity={unlocked ? 0.88 : 0.58} />
        <Path d="M34 78 C47 92 76 94 89 75" fill="none" stroke="#FFFFFF" strokeWidth="3" strokeLinecap="round" opacity={unlocked ? 0.28 : 0.16} />
        <Circle cx={cx} cy={cy} r="43" fill="none" stroke="#FFFFFF" strokeWidth="1.6" opacity="0.74" />

        {dots && ringDots(cx, cy, tier === 'special' ? 16 : 12, 40).map((p, i) => (
          <Circle key={i} cx={p.x} cy={p.y} r={tier === 'silver' ? 1.4 : 1.8} fill={tier === 'silver' ? '#FFFFFF' : pal.glow} opacity={tier === 'silver' ? 0.72 : 0.9} />
        ))}

        {hasBurst && (
          <G opacity={tier === 'special' ? 0.96 : 0.78}>
            <Polygon points={starPoints(30, 40, 4, 4.6, 1.4)} fill="#FFFFFF" />
            <Polygon points={starPoints(91, 48, 4, 3.8, 1.2)} fill="#FFFFFF" />
            <Polygon points={starPoints(78, 27, 4, 2.8, 0.9)} fill="#FFFFFF" />
          </G>
        )}
      </Svg>

      <View style={s.iconLayer}>
        <Feather name={icon} size={iconSize} color={pal.icon} />
      </View>
    </View>
  );
}

const s = StyleSheet.create({
  wrap: {
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: 999,
  },
  iconLayer: {
    ...StyleSheet.absoluteFillObject,
    alignItems: 'center',
    justifyContent: 'center',
  },
});
