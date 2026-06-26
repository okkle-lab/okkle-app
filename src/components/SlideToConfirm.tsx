import { useRef, useState } from 'react';
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

// A big "slide to confirm" track — grab anywhere, easy with gloves on, impossible
// to trigger by accident. The PanResponder is created ONCE (stable) and reads the
// latest values through refs, so the per-second re-renders of the live trip screen
// never disrupt or lag the gesture.
export function SlideToConfirm({ label, onConfirm, color = colors.red }: Props) {
  const [trackW, setTrackW] = useState(0);
  const [done, setDone] = useState(false);
  const x = useRef(new Animated.Value(0)).current;

  const maxX = Math.max(0, trackW - THUMB - 8);
  // Live values the stable responder reads from (kept fresh each render).
  const maxXRef = useRef(maxX); maxXRef.current = maxX;
  const onConfirmRef = useRef(onConfirm); onConfirmRef.current = onConfirm;
  const doneRef = useRef(false);

  const dragStart = useRef(0);
  const latestX = useRef(0);
  const didDrag = useRef(false);

  const responder = useRef(
    PanResponder.create({
      onStartShouldSetPanResponder: () => !doneRef.current,
      onMoveShouldSetPanResponder: () => !doneRef.current,
      onPanResponderGrant: e => {
        const clamp = (v: number) => Math.min(Math.max(0, v), maxXRef.current);
        didDrag.current = false;
        const start = clamp(e.nativeEvent.locationX - THUMB / 2);
        dragStart.current = start;
        latestX.current = start;
        x.setValue(start);
        Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light).catch(() => {});
      },
      onPanResponderMove: (_, g) => {
        const clamp = (v: number) => Math.min(Math.max(0, v), maxXRef.current);
        didDrag.current = didDrag.current || Math.abs(g.dx) > 6;
        const next = clamp(dragStart.current + g.dx);
        latestX.current = next;
        x.setValue(next);
      },
      onPanResponderRelease: () => {
        const max = maxXRef.current;
        if (didDrag.current && latestX.current >= max * 0.8) {
          Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success).catch(() => {});
          doneRef.current = true;
          setDone(true);
          Animated.timing(x, { toValue: max, duration: 120, useNativeDriver: false }).start(() => {
            setTimeout(() => {
              onConfirmRef.current();
              latestX.current = 0;
              x.setValue(0);
              doneRef.current = false;
              setDone(false);
            }, 200);
          });
        } else {
          latestX.current = 0;
          Animated.spring(x, { toValue: 0, useNativeDriver: false, bounciness: 6, speed: 16 }).start();
        }
      },
      onPanResponderTerminate: () => {
        latestX.current = 0;
        Animated.spring(x, { toValue: 0, useNativeDriver: false, bounciness: 6, speed: 16 }).start();
      },
    }),
  ).current;

  function onLayout(e: LayoutChangeEvent) {
    setTrackW(e.nativeEvent.layout.width);
  }

  const labelOpacity = x.interpolate({ inputRange: [0, Math.max(1, maxX * 0.55)], outputRange: [1, 0] });
  const fillW = Animated.add(x, new Animated.Value(THUMB + 8));

  return (
    <View style={s.track} onLayout={onLayout} {...responder.panHandlers}>
      <Animated.View style={[s.fill, { width: fillW, backgroundColor: color, opacity: 0.28 }]} pointerEvents="none" />
      {done ? (
        <Text pointerEvents="none" style={s.doneLabel}>Ending…</Text>
      ) : (
        <Animated.Text pointerEvents="none" style={[s.label, { opacity: labelOpacity }]}>{label}</Animated.Text>
      )}
      <Animated.View
        pointerEvents="none"
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
