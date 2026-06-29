import React from 'react';
import { View, Text, StyleSheet, Switch, Alert, Linking } from 'react-native';
import Feather from '@expo/vector-icons/Feather';
import { colors, font, spacing, radius, type } from '../src/theme';
import { Card, GradientCard, ModalHeader } from '../src/components';
import { enableAutoTrip, disableAutoTrip, isAutoTripEnabled } from '../src/autoTrip';

export default function AutoTripSettings() {
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
          'To nudge you while Okkle is closed, iOS needs location set to “Always”. Open Settings to change it.',
          [{ text: 'Not now' }, { text: 'Open Settings', onPress: () => Linking.openSettings() }],
        );
      } else if (res.reason === 'foreground') {
        Alert.alert('Location needed', 'Allow location access to detect when you start driving.');
      } else {
        Alert.alert('Couldn’t enable', 'Something went wrong turning this on. Please try again.');
      }
    } else {
      await disableAutoTrip();
      setOn(false);
    }
    setBusy(false);
  }

  return (
    <View style={s.screen}>
      <View style={s.content}>
        <ModalHeader title="Trip nudges" />

        <GradientCard colors={[colors.brand, colors.brandDeep, colors.dark]} radius={radius.xl} style={s.hero}>
          <Feather name="navigation" size={22} color="#fff" />
          <Text style={s.heroTitle}>Never forget to track a trip</Text>
          <Text style={s.heroSub}>
            Okkle watches both ends of your trip for you. When it senses you’ve started driving it nudges you to start tracking — and after you’ve been parked a while it nudges you to end and save your miles. You decide each time; nothing is recorded without your tap.
          </Text>
        </GradientCard>

        <Card style={s.toggleCard}>
          <View style={{ flex: 1 }}>
            <Text style={s.toggleTitle}>Trip nudges</Text>
            <Text style={s.toggleDesc}>
              A two-way reminder: a “track this trip?” nudge when you start driving, and a “finished this trip?” nudge once you’ve stopped for a while. Tap either to act — ignore it on a personal drive.
            </Text>
            <Text style={s.toggleState}>{on ? 'On' : 'Off'}</Text>
          </View>
          <Switch value={on} onValueChange={toggle} disabled={busy} trackColor={{ true: colors.brand }} />
        </Card>

        <Card style={s.noteCard}>
          <Feather name="alert-circle" size={18} color={colors.amberDark} />
          <Text style={s.noteText}>
            Detection isn’t perfect — a bus or train ride might trigger a nudge. It’s a helpful prompt, not a replacement for starting a trip yourself, and nothing is logged until you confirm.
          </Text>
        </Card>
      </View>
    </View>
  );
}

const s = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  content: { flex: 1, padding: spacing.xl, paddingTop: 60, paddingBottom: 40 },
  hero: { padding: spacing.lg, gap: 6 },
  heroTitle: { color: '#fff', fontSize: 20, fontWeight: font.bold, letterSpacing: -0.2, marginTop: 4 },
  heroSub: { color: 'rgba(255,255,255,0.88)', fontSize: 14, lineHeight: 20 },
  toggleCard: { flexDirection: 'row', alignItems: 'center', gap: 12, marginTop: spacing.lg },
  toggleTitle: { ...type.bodyMedium, fontSize: 16 },
  toggleDesc: { ...type.caption, marginTop: 4, lineHeight: 18 },
  toggleState: { ...type.caption, marginTop: 6, fontWeight: font.semibold, color: colors.brandDeep },
  noteCard: { flexDirection: 'row', gap: 10, marginTop: spacing.lg, backgroundColor: colors.amberLight },
  noteText: { ...type.caption, color: colors.amberDark, lineHeight: 18, flex: 1 },
});
