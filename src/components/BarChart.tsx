import React from 'react';
import { View, Text } from 'react-native';
import Svg, { Rect } from 'react-native-svg';
import { colors, font, type } from '../theme';
import type { SeriesPoint } from '../db';
import { fmtGbp } from '../db/tax';

// A clean earnings bar chart for the period view. Tallest bar is brand-coloured
// and labelled; the rest are muted. Pure SVG — works in Expo Go.
export function BarChart({ data, height = 150 }: { data: SeriesPoint[]; height?: number }) {
  if (data.length === 0) return null;
  const max = Math.max(...data.map(d => d.value), 1);
  const total = data.reduce((s, d) => s + d.value, 0);
  const maxIdx = data.reduce((mi, d, i) => (d.value > data[mi].value ? i : mi), 0);

  const W = 100, H = 100; // viewBox units; SVG scales to container
  const n = data.length;
  const gap = n > 10 ? 1.5 : 3;
  const bw = (W - gap * (n - 1)) / n;
  const barsH = 80; // leave headroom

  if (total <= 0) {
    return (
      <View style={{ height, alignItems: 'center', justifyContent: 'center' }}>
        <Text style={{ ...type.caption, textAlign: 'center' }}>No earnings logged in this period yet.</Text>
      </View>
    );
  }

  return (
    <View>
      <View style={{ height }}>
        <Svg width="100%" height="100%" viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="none">
          {data.map((d, i) => {
            const h = max > 0 ? (d.value / max) * barsH : 0;
            const x = i * (bw + gap);
            const y = barsH - h;
            return (
              <Rect
                key={i}
                x={x}
                y={Math.max(0, y)}
                width={bw}
                height={Math.max(0.6, h)}
                rx={Math.min(bw / 2, 1.5)}
                fill={i === maxIdx ? colors.brand : colors.brandMid}
                opacity={i === maxIdx ? 1 : 0.5}
              />
            );
          })}
        </Svg>
      </View>
      <View style={{ flexDirection: 'row', marginTop: 6 }}>
        {data.map((d, i) => (
          <Text
            key={i}
            numberOfLines={1}
            style={{
              flex: 1, textAlign: 'center', fontSize: 10,
              fontWeight: i === maxIdx ? font.semibold : font.regular,
              color: i === maxIdx ? colors.brandDeep : colors.textTertiary,
            }}
          >
            {d.label}
          </Text>
        ))}
      </View>
      <Text style={{ ...type.caption, textAlign: 'center', marginTop: 8 }}>
        Best: {data[maxIdx].label} · {fmtGbp(data[maxIdx].value)}
      </Text>
    </View>
  );
}
