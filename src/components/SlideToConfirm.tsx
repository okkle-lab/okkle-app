import React, { useRef, useState } from 'react';
import {
  View, Text, Animated, PanResponder, StyleSheet, LayoutChangeEvent,
} from 'react-native';
import * as Haptics from 'expo-haptics';
import { colors, font, radius } from '../theme';

type Props = {
  label: string;
  onConfirm: () => void;
  color?: string;
};

const THUMB = 64;

// A big "slide to confirm" track — easy with one thumb, gloves on, and
// impossible to trigger by an accidental tap. The track fills as you slide,
// snaps with a haptic, and shows a tick on completion.
export function SlideToConfirm({ label, onConfirm, color = colors.red }: Props) {
  const [trackW, setTrackW] = useState(0);
  const [done, setDone] = useState(false);
  const x = useRef(new Animated.Value(0)).current;
  const maxX = Math.max(0, trackW - THUMB - 8);

  const responder = useRef(
    PanResponder.create({
      onStartShouldSetPanResponder: () => true,
      onMoveShouldSetPanResponder: () => true,
      onPanResponderGrant: () => { Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light).catch(() => {}); },
      onPanResponderMove: (_, g) => {
        const nx = Math.min(Math.max(0, g.dx), maxX);
        x.setValue(nx);
      },
      onPanResponderRelease: (_, g) => {
        if (g.dx >= maxX * 0.85) {
          Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success).catch(() => {});
          setDone(true);
          Animated.timing(x, { toValue: maxX, duration: 140, useNativeDriver: false }).start(() => {
            setTimeout(() => {
              onConfirm();
              x.setValue(0);
              setDone(false);
            }, 220);
          });
        } else {
          Animated.spring(x, { toValue: 0, useNativeDriver: false, bounciness: 8 }).start();
        }
      },
    }),
  ).current;

  function onLayout(e: LayoutChangeEvent) {
    setTrackW(e.nativeEvent.layout.width);
  }

  const labelOpacity = x.interpolate({ inputRange: [0, Math.max(1, maxX * 0.6)], outputRange: [1, 0] });
  // Coloured fill that follows the thumb.
  const fillW = Animated.add(x, new Animated.Value(THUMB + 8));

  return (
    <View style={s.track} onLayout={onLayout}>
      <Animated.View style={[s.fill, { width: fillW, backgroundColor: color, opacity: 0.28 }]} pointerEvents="none" />
      {done ? (
        <Text style={s.doneLabel}>Ending…</Text>
      ) : (
        <Animated.Text style={[s.label, { opacity: labelOpacity }]}>{label}</Animated.Text>
      )}
      <Animated.View
        {...responder.panHandlers}
        style={[s.thumb, { backgroundColor: color, transform: [{ translateX: x }] }]}
      >
        <Text style={s.arrow}>{done ? '✓' : '→'}</Text>
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
    overflow: 'hidden',
  },
  fill: { position: 'absolute', left: 0, top: 0, bottom: 0, borderRadius: radius.full },
  label: {
    position: 'absolute', alignSelf: 'center',
    color: 'rgba(255,255,255,0.85)', fontSize: 17, fontWeight: font.semibold,
  },
  doneLabel: { position: 'absolute', alignSelf: 'center', color: '#fff', fontSize: 17, fontWeight: font.bold },
  thumb: {
    width: THUMB, height: THUMB, borderRadius: THUMB / 2,
    alignItems: 'center', justifyContent: 'center',
  },
  arrow: { color: '#fff', fontSize: 28, fontWeight: font.bold },
});
