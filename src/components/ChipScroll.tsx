import React from 'react';
import { View, ScrollView, StyleSheet } from 'react-native';
import Svg, { Defs, LinearGradient, Stop, Rect } from 'react-native-svg';
import { colors, spacing } from '../theme';

// A horizontal chip row that makes its scrollability obvious: a soft fade on the
// right edge hints "there's more →", and it disappears once you reach the end.
export function ChipScroll({ children, fadeColor = colors.bgCard }: { children: React.ReactNode; fadeColor?: string }) {
  const [h, setH] = React.useState(0);
  const [atEnd, setAtEnd] = React.useState(false);
  return (
    <View onLayout={e => setH(e.nativeEvent.layout.height)}>
      <ScrollView
        horizontal
        showsHorizontalScrollIndicator={false}
        contentContainerStyle={s.row}
        scrollEventThrottle={16}
        onScroll={e => {
          const { contentOffset, contentSize, layoutMeasurement } = e.nativeEvent;
          setAtEnd(contentOffset.x + layoutMeasurement.width >= contentSize.width - 4);
        }}
      >
        {children}
      </ScrollView>
      {h > 0 && !atEnd && (
        <Svg pointerEvents="none" width={36} height={h} style={s.fade}>
          <Defs>
            <LinearGradient id="cf" x1="0" y1="0" x2="1" y2="0">
              <Stop offset="0" stopColor={fadeColor} stopOpacity={0} />
              <Stop offset="1" stopColor={fadeColor} stopOpacity={1} />
            </LinearGradient>
          </Defs>
          <Rect x="0" y="0" width={36} height={h} fill="url(#cf)" />
        </Svg>
      )}
    </View>
  );
}

const s = StyleSheet.create({
  row: { flexDirection: 'row', gap: spacing.sm, paddingRight: 36 },
  fade: { position: 'absolute', right: 0, top: 0 },
});
