import React from 'react';
import { View, Text } from 'react-native';
import { Feather } from '@expo/vector-icons';
import Svg, { Defs, LinearGradient, Stop, Polyline, Circle, Rect } from 'react-native-svg';
import { colors, radius, type } from '../theme';

type Pt = { lat: number; lng: number };

// A premium-looking trip route, drawn on-device from the GPS breadcrumb.
// No street map (that needs a native maps SDK / dev build), but it shows the
// shape of the journey with start/finish markers — the architecture is ready
// to swap in Google Maps later.
export function RouteMap({ route, height = 180 }: { route: Pt[]; height?: number }) {
  const pts = (route ?? []).filter(p => typeof p?.lat === 'number' && typeof p?.lng === 'number');
  const distinct = new Set(pts.map(p => `${p.lat.toFixed(4)},${p.lng.toFixed(4)}`)).size;

  if (distinct < 2) {
    return (
      <View style={{ height, borderRadius: radius.lg, borderWidth: 1, borderColor: 'rgba(128,128,128,0.25)', alignItems: 'center', justifyContent: 'center', gap: 8 }}>
        <Feather name="navigation" size={26} color={colors.textTertiary} />
        <Text style={[type.caption, { textAlign: 'center' }]}>Move a little to start your route…</Text>
      </View>
    );
  }

  let minLat = Infinity, maxLat = -Infinity, minLng = Infinity, maxLng = -Infinity;
  for (const p of pts) {
    minLat = Math.min(minLat, p.lat); maxLat = Math.max(maxLat, p.lat);
    minLng = Math.min(minLng, p.lng); maxLng = Math.max(maxLng, p.lng);
  }
  const padLat = (maxLat - minLat) * 0.12 || 0.002;
  const padLng = (maxLng - minLng) * 0.12 || 0.002;
  minLat -= padLat; maxLat += padLat; minLng -= padLng; maxLng += padLng;

  const cosLat = Math.cos(((minLat + maxLat) / 2) * Math.PI / 180);
  const spanLat = maxLat - minLat;
  const spanLng = (maxLng - minLng) * cosLat || spanLat;
  const W = 100, H = Math.max(50, Math.min(120, (spanLat / spanLng) * 100));

  const x = (lng: number) => ((lng - minLng) / (maxLng - minLng)) * W;
  const y = (lat: number) => ((maxLat - lat) / (maxLat - minLat)) * H;
  const line = pts.map(p => `${x(p.lng).toFixed(2)},${y(p.lat).toFixed(2)}`).join(' ');
  const a = pts[0], b = pts[pts.length - 1];

  return (
    <View style={{ borderRadius: radius.lg, overflow: 'hidden', backgroundColor: '#EEF3F1', height }}>
      <Svg width="100%" height="100%" viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="xMidYMid meet">
        <Defs>
          <LinearGradient id="route" x1="0" y1="0" x2="1" y2="1">
            <Stop offset="0%" stopColor={colors.brandMid} />
            <Stop offset="100%" stopColor={colors.brandDeep} />
          </LinearGradient>
        </Defs>
        <Rect x="0" y="0" width={W} height={H} fill="#EEF3F1" />
        <Polyline points={line} fill="none" stroke="url(#route)" strokeWidth={2.4} strokeLinejoin="round" strokeLinecap="round" />
        {/* start (green) and finish (brand) markers */}
        <Circle cx={x(a.lng)} cy={y(a.lat)} r={3.4} fill="#fff" />
        <Circle cx={x(a.lng)} cy={y(a.lat)} r={2.2} fill={colors.green} />
        <Circle cx={x(b.lng)} cy={y(b.lat)} r={3.6} fill="#fff" />
        <Circle cx={x(b.lng)} cy={y(b.lat)} r={2.4} fill={colors.brandDeep} />
      </Svg>
    </View>
  );
}
