import React from 'react';
import { View, Text, ScrollView, StyleSheet, Pressable, Switch, Alert, Linking } from 'react-native';
import { useRouter } from 'expo-router';
import { Feather } from '@expo/vector-icons';
import { colors, font, spacing, radius, type } from '../src/theme';
import { Card, IconBadge, GradientCard } from '../src/components';
import { enableAutoTrip, disableAutoTrip, isAutoTripEnabled } from '../src/autoTrip';

export default function AutoTripSettings() {
  const router = useRouter();
  const [on, setOn] = React.useState(isAutoTripEnabled());
  const [busy, setBusy] = React.useState(false);

  async function toggle(next: boolean) {
    if (busy) return;
    setBusy(true);
    if (next) {
      const res = await enableAutoTrip();
      if (res.ok) {
        setOn(true);
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
        <Text style={s.title}>Auto-detect trips</Text>
        <View style={{ width: 26 }} />
      </View>

      <GradientCard colors={[colors.brand, colors.brandDeep, colors.dark]} radius={radius.xl} style={s.hero}>
        <Feather name="navigation" size={22} color="#fff" />
        <Text style={s.heroTitle}>Never forget to track a trip</Text>
        <Text style={s.heroSub}>
          When Okkle notices you’ve started driving, it’ll send a gentle nudge: “On the move — track this trip?”
          Tap it and you’re recording — so you don’t lose tax-free miles by forgetting to press Start.
        </Text>
      </GradientCard>

      {/* The toggle */}
      <Card style={s.toggleCard}>
        <View style={{ flex: 1 }}>
          <Text style={s.toggleTitle}>Suggest trips automatically</Text>
          <Text style={s.toggleSub}>{on ? 'On — we’ll nudge you when you start driving.' : 'Off — you start trips manually.'}</Text>
        </View>
        <Switch value={on} onValueChange={toggle} disabled={busy} trackColor={{ true: colors.brand }} />
      </Card>

      <Text style={s.sectionLabel}>Why “Always” location?</Text>
      <Card style={{ gap: spacing.lg }}>
        <Point icon="navigation" title="Only to spot the start of a trip" body="iOS wakes Okkle when you move a meaningful distance so it can check if you’re driving — that’s the only reason it needs background location." />
        <Point icon="battery-charging" title="Built to sip battery" body="It uses low-power location and pauses when you’re still. The precise GPS trail only runs once you actually start a trip." />
        <Point icon="check-circle" title="You’re always in control" body="It only ever suggests — nothing is recorded until you tap Start, and you can switch this off any time." />
        <Point icon="lock" title="Stays on your phone" body="Your location is used on-device to estimate mileage. Nothing is uploaded." />
      </Card>

      <Text style={s.footnote}>
        Detection isn’t perfect — a bus or train ride might trigger a nudge, and the odd short trip may be missed. It’s a helpful prompt, not a replacement for starting a trip yourself.
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
