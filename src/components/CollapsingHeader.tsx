import React from 'react';
import { Animated, View, StyleSheet, type StyleProp, type ViewStyle } from 'react-native';
import { colors, font, spacing, type } from '../theme';

const STATUS = 54;        // space above the bar row (status bar / notch)
const ROW = 46;           // height of the pinned title/actions row
const HEADER = STATUS + ROW;
const THRESH = 40;        // px of scroll over which the large title hands off

type Props = {
  title: string;
  subtitle?: string;
  right?: React.ReactNode;        // actions pinned top-right (e.g. settings gear)
  children: React.ReactNode;
  refreshControl?: React.ComponentProps<typeof Animated.ScrollView>['refreshControl'];
  keyboardShouldPersistTaps?: 'always' | 'never' | 'handled';
  contentStyle?: StyleProp<ViewStyle>;
};

// Starling-style header: a big title sits in the scroll content and slides away
// as you scroll, while a compact pinned title + a solid bar fade in. Smooth,
// native-driven movement; right-hand actions stay put the whole time.
export function CollapsingHeader({ title, subtitle, right, children, refreshControl, keyboardShouldPersistTaps, contentStyle }: Props) {
  const scrollY = React.useRef(new Animated.Value(0)).current;

  const barOpacity = scrollY.interpolate({ inputRange: [THRESH * 0.4, THRESH], outputRange: [0, 1], extrapolate: 'clamp' });
  const smallOpacity = scrollY.interpolate({ inputRange: [THRESH * 0.5, THRESH], outputRange: [0, 1], extrapolate: 'clamp' });
  const smallTranslate = scrollY.interpolate({ inputRange: [0, THRESH], outputRange: [8, 0], extrapolate: 'clamp' });
  const bigOpacity = scrollY.interpolate({ inputRange: [0, THRESH * 0.8], outputRange: [1, 0], extrapolate: 'clamp' });
  const bigTranslate = scrollY.interpolate({ inputRange: [0, THRESH], outputRange: [0, -10], extrapolate: 'clamp' });

  return (
    <View style={s.screen}>
      <Animated.ScrollView
        refreshControl={refreshControl}
        keyboardShouldPersistTaps={keyboardShouldPersistTaps}
        scrollEventThrottle={16}
        showsVerticalScrollIndicator={false}
        onScroll={Animated.event([{ nativeEvent: { contentOffset: { y: scrollY } } }], { useNativeDriver: true })}
        contentContainerStyle={[{ paddingTop: HEADER, paddingHorizontal: spacing.xl, paddingBottom: 40 }, contentStyle]}
      >
        <Animated.Text style={[s.big, !subtitle && { marginBottom: spacing.lg }, { opacity: bigOpacity, transform: [{ translateY: bigTranslate }] }]}>{title}</Animated.Text>
        {subtitle ? <Animated.Text style={[s.sub, { opacity: bigOpacity }]}>{subtitle}</Animated.Text> : null}
        {children}
      </Animated.ScrollView>

      {/* Pinned bar — transparent until you scroll, then a solid masking bar. */}
      <View style={s.bar} pointerEvents="box-none">
        <Animated.View pointerEvents="none" style={[s.barBg, { opacity: barOpacity }]} />
        <View style={s.row} pointerEvents="box-none">
          <Animated.Text pointerEvents="none" numberOfLines={1} style={[s.small, { opacity: smallOpacity, transform: [{ translateY: smallTranslate }] }]}>{title}</Animated.Text>
          {right ? <View style={s.right}>{right}</View> : null}
        </View>
      </View>
    </View>
  );
}

const s = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  bar: { position: 'absolute', top: 0, left: 0, right: 0, height: HEADER },
  barBg: { ...StyleSheet.absoluteFillObject, backgroundColor: colors.bg, borderBottomWidth: 1, borderBottomColor: colors.border },
  row: { position: 'absolute', left: spacing.xl, right: spacing.xl, bottom: 0, height: ROW, flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  small: { ...type.heading, fontSize: 18, flex: 1, paddingRight: spacing.md },
  right: { flexDirection: 'row', alignItems: 'center', gap: 12 },
  big: { ...type.screenTitle },
  sub: { ...type.body, color: colors.textSecondary, marginTop: 6, marginBottom: spacing.lg },
});
