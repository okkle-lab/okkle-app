import React from 'react';
import { View, Text } from 'react-native';
import Svg, { Line, Rect } from 'react-native-svg';
import { colors, radius, type } from '../theme';
import type { HeatPoint } from '../db';

// Heatmap of where you ride. This is intentionally rendered with app-owned SVG
// instead of react-native-maps Heatmap: the native AIRMapHeatmap view is not
// registered in every iOS map-provider build and can crash Insights at render.

const COLS = 24;
const MIN_ROWS = 8;
const MAX_ROWS = 28;
const VIEW_W = 100;

type HeatCell = {
  key: string;
  x: number;
  y: number;
  width: number;
  height: number;
  fill: string;
  opacity: number;
};

function clamp(n: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, n));
}

function heatColor(t: number): { fill: string; opacity: number } {
  const fill =
    t < 0.2 ? '#9BE3D2' :
    t < 0.4 ? '#5FD0BB' :
    t < 0.6 ? '#E7C66B' :
    t < 0.8 ? '#E0961F' : '#E2604A';
  return { fill, opacity: 0.35 + t * 0.6 };
}

function buildCells(points: HeatPoint[]): { height: number; cells: HeatCell[] } {
  let minLat = Infinity, maxLat = -Infinity, minLng = Infinity, maxLng = -Infinity;
  for (const p of points) {
    minLat = Math.min(minLat, p.lat); maxLat = Math.max(maxLat, p.lat);
    minLng = Math.min(minLng, p.lng); maxLng = Math.max(maxLng, p.lng);
  }

  // Pad the bbox a touch so points are not flush to the edge.
  const padLat = (maxLat - minLat) * 0.08 || 0.002;
  const padLng = (maxLng - minLng) * 0.08 || 0.002;
  minLat -= padLat; maxLat += padLat; minLng -= padLng; maxLng += padLng;

  // Correct longitude for latitude so the generated grid roughly preserves the
  // travelled area's shape before it is stretched into the fixed card.
  const cosLat = Math.cos(((minLat + maxLat) / 2) * Math.PI / 180);
  const spanLat = maxLat - minLat;
  const spanLng = (maxLng - minLng) * cosLat;
  const rows = clamp(Math.round(COLS * (spanLat / (spanLng || 1))), MIN_ROWS, MAX_ROWS);
  const grid = Array.from({ length: rows }, () => new Array(COLS).fill(0));

  const xOf = (lng: number) => ((lng - minLng) / (maxLng - minLng)) * (COLS - 1);
  const yOf = (lat: number) => ((maxLat - lat) / (maxLat - minLat)) * (rows - 1);

  for (const p of points) {
    const cx = xOf(p.lng);
    const cy = yOf(p.lat);
    const weight = Math.max(0.1, p.w);

    // Spread each point into neighbouring cells so the result reads as a heatmap
    // rather than a sparse GPS dot matrix.
    for (let r = Math.max(0, Math.floor(cy) - 2); r <= Math.min(rows - 1, Math.floor(cy) + 2); r++) {
      for (let c = Math.max(0, Math.floor(cx) - 2); c <= Math.min(COLS - 1, Math.floor(cx) + 2); c++) {
        const dx = cx - c;
        const dy = cy - r;
        const influence = Math.exp(-(dx * dx + dy * dy) / 2.2);
        grid[r][c] += weight * influence;
      }
    }
  }

  let max = 0;
  for (const row of grid) for (const v of row) max = Math.max(max, v);
  if (max <= 0) return { height: (rows / COLS) * VIEW_W, cells: [] };

  const height = (rows / COLS) * VIEW_W;
  const cellW = VIEW_W / COLS;
  const cellH = height / rows;
  const cells: HeatCell[] = [];

  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < COLS; c++) {
      const v = grid[r][c];
      if (v <= 0.02) continue;
      const t = Math.min(1, v / max);
      const { fill, opacity } = heatColor(t);
      cells.push({
        key: `${r}-${c}`,
        x: c * cellW,
        y: r * cellH,
        width: cellW + 0.35,
        height: cellH + 0.35,
        fill,
        opacity,
      });
    }
  }

  return { height, cells };
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

  const model = buildCells(points);

  return (
    <View style={{ borderRadius: radius.lg, overflow: 'hidden', backgroundColor: '#F3F6F4', height }}>
      <Svg width="100%" height="100%" viewBox={`0 0 ${VIEW_W} ${model.height}`} preserveAspectRatio="none">
        <Rect x={0} y={0} width={VIEW_W} height={model.height} fill="#F3F6F4" />
        <Rect x={6} y={model.height * 0.08} width={22} height={model.height * 0.22} rx={2} fill="#E7F0EA" />
        <Rect x={70} y={model.height * 0.6} width={20} height={model.height * 0.2} rx={2} fill="#E7F0EA" />
        {Array.from({ length: 5 }).map((_, i) => {
          const y = ((i + 1) / 6) * model.height;
          return <Line key={`h-${i}`} x1={0} y1={y} x2={VIEW_W} y2={y + (i % 2 ? 1.8 : -1.4)} stroke="#DDE7E0" strokeWidth={0.9} opacity={0.85} />;
        })}
        {Array.from({ length: 6 }).map((_, i) => {
          const x = ((i + 1) / 7) * VIEW_W;
          return <Line key={`v-${i}`} x1={x} y1={0} x2={x + (i % 2 ? 1.3 : -1.1)} y2={model.height} stroke="#E2EAE4" strokeWidth={0.8} opacity={0.8} />;
        })}
        {model.cells.map(cell => (
          <Rect
            key={cell.key}
            x={cell.x}
            y={cell.y}
            width={cell.width}
            height={cell.height}
            rx={cell.width * 0.36}
            fill={cell.fill}
            opacity={cell.opacity}
          />
        ))}
      </Svg>
    </View>
  );
}
