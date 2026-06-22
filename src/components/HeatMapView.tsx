import React from 'react';
import { View, Text } from 'react-native';
import Svg, { Rect, Polyline } from 'react-native-svg';
import { colors, radius, type } from '../theme';
import type { HeatPoint } from '../db';

// A self-contained density heatmap that works in Expo Go (no native maps).
// Points are binned into a grid over their bounding box and coloured by
// intensity. It shows the SHAPE of where you ride and the hot zones relative
// to each other — a real street map can drop in later (needs a dev build).

const COLS = 22;
function heatColor(t: number): { fill: string; opacity: number } {
  const fill =
    t < 0.2 ? '#9BE3D2' :
    t < 0.4 ? '#5FD0BB' :
    t < 0.6 ? '#E7C66B' :
    t < 0.8 ? '#E0961F' : '#E2604A';
  return { fill, opacity: 0.35 + t * 0.6 };
}

export function HeatMapView({ points, height = 220 }: { points: HeatPoint[]; height?: number }) {
  const distinct = new Set(points.map(p => `${p.lat.toFixed(3)},${p.lng.toFixed(3)}`)).size;
  if (points.length === 0 || distinct < 2) {
    return (
      <View style={{ height, borderRadius: radius.lg, backgroundColor: colors.bgSoft, alignItems: 'center', justifyContent: 'center', padding: 24 }}>
        <Text style={{ fontSize: 30, marginBottom: 8 }}>🗺️</Text>
        <Text style={[type.caption, { textAlign: 'center', lineHeight: 19 }]}>
          Track a few trips with GPS this week and your hotspots will appear here.
        </Text>
      </View>
    );
  }

  let minLat = Infinity, maxLat = -Infinity, minLng = Infinity, maxLng = -Infinity;
  for (const p of points) {
    minLat = Math.min(minLat, p.lat); maxLat = Math.max(maxLat, p.lat);
    minLng = Math.min(minLng, p.lng); maxLng = Math.max(maxLng, p.lng);
  }
  // Pad the bbox a touch so points aren't flush to the edge.
  const padLat = (maxLat - minLat) * 0.08 || 0.002;
  const padLng = (maxLng - minLng) * 0.08 || 0.002;
  minLat -= padLat; maxLat += padLat; minLng -= padLng; maxLng += padLng;

  // Correct longitude for latitude so the aspect ratio isn't distorted.
  const cosLat = Math.cos(((minLat + maxLat) / 2) * Math.PI / 180);
  const spanLat = maxLat - minLat;
  const spanLng = (maxLng - minLng) * cosLat;
  const rows = Math.max(6, Math.min(28, Math.round(COLS * (spanLat / (spanLng || 1)))));

  const grid = Array.from({ length: rows }, () => new Array(COLS).fill(0));
  const xOf = (lng: number) => ((lng - minLng) / (maxLng - minLng)) * COLS;
  const yOf = (lat: number) => ((maxLat - lat) / (maxLat - minLat)) * rows;

  for (const p of points) {
    const c = Math.min(COLS - 1, Math.max(0, Math.floor(xOf(p.lng))));
    const r = Math.min(rows - 1, Math.max(0, Math.floor(yOf(p.lat))));
    grid[r][c] += p.w;
  }
  let max = 0;
  for (const row of grid) for (const v of row) max = Math.max(max, v);

  const W = 100, H = (rows / COLS) * 100;
  const cw = W / COLS, ch = H / rows;
  const cells: React.ReactNode[] = [];
  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < COLS; c++) {
      const v = grid[r][c];
      if (v <= 0) continue;
      const t = Math.min(1, v / max);
      const { fill, opacity } = heatColor(t);
      cells.push(
        <Rect key={`${r}-${c}`} x={c * cw} y={r * ch} width={cw + 0.4} height={ch + 0.4} rx={cw * 0.28} fill={fill} opacity={opacity} />,
      );
    }
  }

  return (
    <View style={{ borderRadius: radius.lg, overflow: 'hidden', backgroundColor: '#F3F6F4', height }}>
      <Svg width="100%" height="100%" viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="xMidYMid meet">
        {cells}
      </Svg>
    </View>
  );
}
