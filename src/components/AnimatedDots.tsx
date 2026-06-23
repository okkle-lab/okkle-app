import React from 'react';
import { View, Animated, StyleSheet } from 'react-native';
import { colors, spacing } from '../theme';

const DOT = 7;
const GAP = 7;
const PILL = 18;

// Page-indicator dots with a brand pill that slides smoothly as you swipe —
// driven by the carousel's scroll position (the same feel as the period switcher).
export function AnimatedDots({ scrollX, count, pageWidth }: { scrollX: Animated.Value; count: number; pageWidth: number }) {
  if (count <= 1) return null;
  const slot = DOT + GAP;
  const rowWidth = count * DOT + (count - 1) * GAP;
  const base = DOT / 2 - PILL / 2;
  const translateX = scrollX.interpolate({
    inputRange: [0, pageWidth * (count - 1)],
    outputRange: [base, base + slot * (count - 1)],
    extrapolate: 'clamp',
  });
  return (
    <View style={[s.row, { width: rowWidth }]}>
      {Array.from({ length: count }).map((_, i) => <View key={i} style={s.dot} />)}
      <Animated.View style={[s.pill, { transform: [{ translateX }] }]} />
    </View>
  );
}

const s = StyleSheet.create({
  row: { height: DOT, alignSelf: 'center', marginTop: spacing.md, flexDirection: 'row', justifyContent: 'space-between' },
  dot: { width: DOT, height: DOT, borderRadius: DOT / 2, backgroundColor: colors.border },
  pill: { position: 'absolute', left: 0, top: 0, width: PILL, height: DOT, borderRadius: DOT / 2, backgroundColor: colors.brand },
});
