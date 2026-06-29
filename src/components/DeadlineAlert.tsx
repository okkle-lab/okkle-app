import React from 'react';
import { Animated, AppState, Pressable, StyleSheet, Text, View } from 'react-native';
import { useRouter } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import Feather from '@expo/vector-icons/Feather';
import { colors, font, spacing, radius, type } from '../theme';
import { kvGet, kvSet } from '../db';
import { upcomingDeadline } from '../taxDeadlines';

// A top banner that drops in over ANY screen when a tax deadline is close (≤14
// days), so the reminder is unmissable regardless of which tab is open. Dismiss
// (×) is remembered per-deadline so it won't keep popping for the same one.
const ALERT_WITHIN_DAYS = 14;

export function DeadlineAlert() {
  const router = useRouter();
  const insets = useSafeAreaInsets();
  const [due, setDue] = React.useState<{ title: string; date: Date; days: number } | null>(null);
  const slide = React.useRef(new Animated.Value(-160)).current;

  const evaluate = React.useCallback(() => {
    try {
      const next = upcomingDeadline(ALERT_WITHIN_DAYS);
      const dismissedFor = kvGet('deadline_alert_dismissed');
      setDue(next && next.date.toISOString().slice(0, 10) !== dismissedFor ? next : null);
    } catch {
      setDue(null); // never let the banner take down the app
    }
  }, []);

  React.useEffect(() => {
    evaluate();
    const sub = AppState.addEventListener('change', s => { if (s === 'active') evaluate(); });
    return () => sub.remove();
  }, [evaluate]);

  React.useEffect(() => {
    Animated.timing(slide, { toValue: due ? 0 : -160, duration: 280, useNativeDriver: true }).start();
  }, [due, slide]);

  if (!due) return null;

  const when = due.days === 0 ? 'due today' : due.days === 1 ? 'due tomorrow' : `due in ${due.days} days`;
  const dismiss = () => { kvSet('deadline_alert_dismissed', due.date.toISOString().slice(0, 10)); setDue(null); };
  const openIt = () => { dismiss(); router.push({ pathname: '/tax-detail', params: { which: 'deadlines' } }); };

  return (
    <Animated.View style={[s.wrap, { paddingTop: insets.top + 6, transform: [{ translateY: slide }] }]}>
      <Pressable onPress={openIt} style={({ pressed }) => [s.card, pressed && { opacity: 0.92 }]}>
        <View style={s.icon}><Feather name="bell" size={18} color={colors.amberDark} /></View>
        <View style={{ flex: 1 }}>
          <Text style={s.title} numberOfLines={1}>{due.title}</Text>
          <Text style={s.sub}>Tax deadline {when} · tap to view</Text>
        </View>
        <Pressable onPress={dismiss} hitSlop={10} style={s.close}>
          <Feather name="x" size={18} color={colors.amberDark} />
        </Pressable>
      </Pressable>
    </Animated.View>
  );
}

const s = StyleSheet.create({
  wrap: { position: 'absolute', top: 0, left: 0, right: 0, paddingHorizontal: spacing.md, paddingBottom: 6, backgroundColor: colors.amberLight },
  card: { flexDirection: 'row', alignItems: 'center', gap: 12, paddingVertical: 4 },
  icon: { width: 38, height: 38, borderRadius: 19, backgroundColor: 'rgba(224,150,31,0.18)', alignItems: 'center', justifyContent: 'center' },
  title: { ...type.bodyMedium, fontSize: 15, color: colors.amberDark, fontWeight: font.bold },
  sub: { ...type.small, color: colors.amberDark, marginTop: 1 },
  close: { width: 30, height: 30, alignItems: 'center', justifyContent: 'center', borderRadius: 15 },
});
