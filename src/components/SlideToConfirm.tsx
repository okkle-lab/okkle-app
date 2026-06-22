import React, { useRef, useState } from 'react';
import {
  View, Text, Animated, PanResponder, StyleSheet, LayoutChangeEvent,
} from 'react-native';
import { colors, font, radius } from '../theme';

type Props = {
  label: string;
  onConfirm: () => void;
  color?: string;
};

const THUMB = 64;

// A big "slide to confirm" track — easy with one thumb, gloves on, and
// impossible to trigger by an accidental tap. Modelled on Lime/Uber's
// slide-to-end controls.
export function SlideToConfirm({ label, onConfirm, color = colors.red }: Props) {
  const [trackW, setTrackW] = useState(0);
  const x = useRef(new Animated.Value(0)).current;
  const maxX = Math.max(0, trackW - THUMB - 8);

  const responder = useRef(
    PanResponder.create({
      onStartShouldSetPanResponder: () => true,
      onMoveShouldSetPanResponder: () => true,
      onPanResponderMove: (_, g) => {
        const nx = Math.min(Math.max(0, g.dx), maxX);
        x.setValue(nx);
      },
      onPanResponderRelease: (_, g) => {
        if (g.dx >= maxX * 0.85) {
          Animated.timing(x, { toValue: maxX, duration: 120, useNativeDriver: false }).start(() => {
            onConfirm();
            x.setValue(0);
          });
        } else {
          Animated.spring(x, { toValue: 0, useNativeDriver: false }).start();
        }
      },
    }),
  ).current;

  function onLayout(e: LayoutChangeEvent) {
    setTrackW(e.nativeEvent.layout.width);
  }

  const labelOpacity = x.interpolate({
    inputRange: [0, Math.max(1, maxX)],
    outputRange: [1, 0],
  });

  return (
    <View style={s.track} onLayout={onLayout}>
      <Animated.Text style={[s.label, { opacity: labelOpacity }]}>{label}</Animated.Text>
      <Animated.View
        {...responder.panHandlers}
        style={[s.thumb, { backgroundColor: color, transform: [{ translateX: x }] }]}
      >
        <Text style={s.arrow}>→</Text>
      </Animated.View>
    </View>
  );
}

const s = StyleSheet.create({
  track: {
    height: THUMB + 8,
    borderRadius: radius.full,
    backgroundColor: 'rgba(255,255,255,0.10)',
    justifyContent: 'center',
    paddingHorizontal: 4,
  },
  label: {
    position: 'absolute',
    alignSelf: 'center',
    color: 'rgba(255,255,255,0.85)',
    fontSize: 17,
    fontWeight: font.semibold,
  },
  thumb: {
    width: THUMB,
    height: THUMB,
    borderRadius: THUMB / 2,
    alignItems: 'center',
    justifyContent: 'center',
  },
  arrow: { color: '#fff', fontSize: 28, fontWeight: font.bold },
});
