import React from 'react';
import { View, Text, ScrollView, StyleSheet, Pressable, Switch, Alert, Linking } from 'react-native';
import { useRouter } from 'expo-router';
import { Feather } from '@expo/vector-icons';
import { colors, font, spacing, radius, type } from '../src/theme';
import { Card, IconBadge, GradientCard } from '../src/components';
import { enableAutoTrip, disableAutoTrip, isAutoTripEnabled, enableShiftMode, disableShiftMode } from '../src/autoTrip';
import { isShiftModeEnabled } from '../src/shift';

export default function AutoTripSettings() {
  const router = useRouter();
  const [on, setOn] = React.useState(isAutoTripEnabled());
  const [shiftOn, setShiftOn] = React.useState(isShiftModeEnabled());
  const [busy, setBusy] = React.useState(false);

  async function toggleShift(next: boolean) {
    if (busy) return;
    setBusy(true);
    if (next) {
      const res = await enableShiftMode();
      if (res.ok) {
        setShiftOn(true);
        setOn(false); // passive mode supersedes the nudge-only mode
      } else if (res.reason === 'background') {
        Alert.alert(
          'Allow “Always”',
          'To count your miles in the background while you work, iOS needs location set to “Always”. Open Settings to change it.',
          [{ text: 'Not now' }, { text: 'Open Settings', onPress: () => Linking.openSettings() }],
        );
      } else if (res.reason === 'foreground') {
        Alert.alert('Location needed', 'Allow location access to track your shift miles.');
      } else {
        Alert.alert('Couldn’t enable', 'Something went wrong turning this on. Please try again.');
      }
    } else {
      await disableShiftMode();
      setShiftOn(false);
    }
    setBusy(false);
  }

  async function toggle(next: boolean) {
    if (busy) return;
    setBusy(true);
    if (next) {
      const res = await enableAutoTrip();
      if (res.ok) {
        setOn(true);
        if (shiftOn) { await disableShiftMode(); setShiftOn(false); }
      } else if (res.reason === 'background') {
        Alert.alert(
          'Allow “Always”',
          'To suggest trips while Okkle is closed, iOS needs location set to “Always”. Open Settings to change it.',
          [{ text: 'Not now' }, { text: 'Open Settings', onPress: () => Linking.openSettings() }],
        );
      } else if (res.reason === 'foreground') {
        Alert.alert('Location needed', 'Allow location access to use automatic trip detection.');
      } else {
        Alert.alert('Couldn’t enable', 'Something went wrong turning this on. Please try again.');
      }
    } else {
      await disableAutoTrip();
      setOn(false);
    }
    setBusy(false);
  }

  const Point = ({ icon, title, body }: { icon: any; title: string; body: string }) => (
    <View style={s.point}>
      <IconBadge icon={icon} tone="mint" size={34} />
      <View style={{ flex: 1 }}>
        <Text style={s.pointTitle}>{title}</Text>
        <Text style={s.pointBody}>{body}</Text>
      </View>
    </View>
  );

  return (
    <ScrollView style={s.screen} contentContainerStyle={s.content}>
      <View style={s.header}>
        <Pressable onPress={() => router.back()} hitSlop={12} style={s.back}>
          <Feather name="chevron-left" size={26} color={colors.textPrimary} />
        </Pressable>
        <Text style={s.title}>Work mode</Text>
        <View style={{ width: 26 }} />
      </View>

      <GradientCard colors={[colors.brand, colors.brandDeep, colors.dark]} radius={radius.xl} style={s.hero}>
        <Feather name="navigation" size={22} color="#fff" />
        <Text style={s.heroTitle}>Track your shift in work mode</Text>
        <Text style={s.heroSub}>
          Turn this on when you are actively working deliveries. Okkle counts miles in the background when it thinks you are
          driving or cycling for work, then saves the shift as a draft for you to review.
        </Text>
      </GradientCard>

      {/* Passive whole-shift tracking — the recommended default */}
      <Card style={s.toggleCard}>
        <View style={{ flex: 1 }}>
          <Text style={s.toggleTitle}>Track my shift automatically</Text>
          <Text style={s.toggleSub}>{shiftOn ? 'On — use this while you are on shift. Miles are counted in the background and saved as a draft to review.' : 'Off — turn this on only during work hours. Personal driving can be picked up too.'}</Text>
        </View>
        <Switch value={shiftOn} onValueChange={toggleShift} disabled={busy} trackColor={{ true: colors.brand }} />
      </Card>

      {/* Nudge-only fallback */}
      <Card style={s.toggleCard}>
        <View style={{ flex: 1 }}>
          <Text style={s.toggleTitle}>Just nudge me instead</Text>
          <Text style={s.toggleSub}>{on ? 'On — we’ll nudge you when you start driving.' : 'Off — prefer a tap-to-start nudge over full tracking.'}</Text>
        </View>
        <Switch value={on} onValueChange={toggle} disabled={busy} trackColor={{ true: colors.brand }} />
      </Card>

      <Text style={s.sectionLabel}>What to expect</Text>
      <Card style={{ gap: spacing.lg }}>
        <Point icon="briefcase" title="Use this only while working" body="This mode is meant for delivery hours. If you leave it on for personal driving, Okkle may treat that movement as shift mileage." />
        <Point icon="navigation" title="It starts from movement, not intent" body="Okkle looks for driving or cycling patterns in the background. It cannot truly know whether you meant a journey to be for work." />
        <Point icon="check-circle" title="Auto-logged shifts are drafts" body="Nothing is silently finalized. When a shift ends, Okkle saves a draft mileage entry for you to review before relying on it." />
        <Point icon="battery-charging" title="Built to sip battery" body="It uses low-power location and pauses when you are still, so it stays lightweight during a work day." />
        <Point icon="lock" title="Stays on your phone" body="Your location is used on-device to estimate mileage. Nothing is uploaded." />
      </Card>

      <Text style={s.footnote}>
        Prefer more control? Leave work mode off and use “Just nudge me instead” so Okkle prompts you when it thinks a trip is starting.
      </Text>
    </ScrollView>
  );
}

const s = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  content: { padding: spacing.xl, paddingTop: 60, paddingBottom: 40 },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginBottom: spacing.lg },
  back: { padding: 2 },
  title: { ...type.screenTitle },

  hero: { padding: spacing.xl, gap: 6 },
  heroTitle: { color: '#fff', fontSize: 22, fontWeight: font.bold, letterSpacing: -0.4, marginTop: 4 },
  heroSub: { color: 'rgba(255,255,255,0.88)', fontSize: 14, lineHeight: 20 },

  toggleCard: { flexDirection: 'row', alignItems: 'center', gap: 12, marginTop: spacing.lg },
  toggleTitle: { ...type.bodyMedium, fontSize: 16 },
  toggleSub: { ...type.caption, marginTop: 2, lineHeight: 18 },

  sectionLabel: { ...type.label, color: colors.textSecondary, fontWeight: font.semibold, marginTop: spacing.xl, marginBottom: spacing.sm },
  point: { flexDirection: 'row', alignItems: 'flex-start', gap: 12 },
  pointTitle: { ...type.bodyMedium, fontSize: 15 },
  pointBody: { ...type.caption, lineHeight: 19, marginTop: 2 },

  footnote: { ...type.small, lineHeight: 18, marginTop: spacing.xl },
});
