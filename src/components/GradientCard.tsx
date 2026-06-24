import React from 'react';
import { View, StyleSheet, type ViewStyle, type StyleProp } from 'react-native';
import Svg, { Defs, LinearGradient, Stop, Rect } from 'react-native-svg';

type Props = {
  colors: [string, string] | [string, string, string];
  style?: StyleProp<ViewStyle>;
  radius?: number;
  // gradient direction, 0 = top→bottom, 1 = diagonal top-left→bottom-right
  diagonal?: boolean;
  children?: React.ReactNode;
};

// A card whose background is a real linear gradient (via react-native-svg, so it
// works in Expo Go without a native build). Adds depth instead of flat fills.
export function GradientCard({ colors, style, radius = 20, diagonal = true, children }: Props) {
  const [size, setSize] = React.useState({ w: 0, h: 0 });
  const stops = colors.length === 3 ? colors : [colors[0], colors[1]];
  const offsets = stops.length === 3 ? ['0%', '55%', '100%'] : ['0%', '100%'];
  return (
    <View
      style={[{ borderRadius: radius, overflow: 'hidden' }, style]}
      onLayout={e => setSize({ w: e.nativeEvent.layout.width, h: e.nativeEvent.layout.height })}
    >
      {size.w > 0 && (
        <Svg width={size.w} height={size.h} style={StyleSheet.absoluteFill} pointerEvents="none">
          <Defs>
            <LinearGradient id="gc" x1="0" y1="0" x2={diagonal ? '1' : '0'} y2="1">
              {stops.map((c, i) => <Stop key={i} offset={offsets[i]} stopColor={c} />)}
            </LinearGradient>
          </Defs>
          <Rect x="0" y="0" width={size.w} height={size.h} fill="url(#gc)" />
        </Svg>
      )}
      {children}
    </View>
  );
}
