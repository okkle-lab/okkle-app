import React from 'react';
import { View, Text, StyleSheet, Pressable, Switch, Alert, Linking } from 'react-native';
import { useRouter } from 'expo-router';
import { Feather } from '@expo/vector-icons';
import { colors, font, spacing, radius, type } from '../src/theme';
import { Card, GradientCard } from '../src/components';
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

  return (
    <View style={s.screen}>
      <View style={s.content}>
      <View style={s.header}>
        <Pressable onPress={() => router.back()} hitSlop={12} style={s.back}>
          <Feather name="chevron-left" size={26} color={colors.textPrimary} />
        </Pressable>
        <Text style={s.title}>Automatic shift tracking</Text>
        <View style={{ width: 26 }} />
      </View>

      <GradientCard colors={[colors.brand, colors.brandDeep, colors.dark]} radius={radius.xl} style={s.hero}>
        <Feather name="navigation" size={22} color="#fff" />
        <Text style={s.heroTitle}>Count delivery miles in the background</Text>
        <Text style={s.heroSub}>
          Turn this on only while working. Personal driving can be picked up, so auto-logged shifts are saved as drafts.
        </Text>
      </GradientCard>

      <Card style={s.toggleCard}>
        <View style={{ flex: 1 }}>
          <Text style={s.toggleTitle}>Automatic shift tracking</Text>
          <Text style={s.toggleDesc}>
            Okkle counts your delivery miles in the background while you drive — you never press start. When you finish, the shift is saved as a draft for you to confirm.
          </Text>
          <Text style={s.toggleState}>{shiftOn ? 'On' : 'Off'}</Text>
        </View>
        <Switch value={shiftOn} onValueChange={toggleShift} disabled={busy} trackColor={{ true: colors.brand }} />
      </Card>

      <Card style={s.toggleCard}>
        <View style={{ flex: 1 }}>
          <Text style={s.toggleTitle}>Trip start nudges</Text>
          <Text style={s.toggleDesc}>
            Prefer to start trips yourself? Instead of tracking automatically, Okkle sends a notification when it senses you’ve started driving, so you can tap to begin a trip. (This and automatic tracking can’t both be on.)
          </Text>
          <Text style={s.toggleState}>{on ? 'On' : 'Off'}</Text>
        </View>
        <Switch value={on} onValueChange={toggle} disabled={busy} trackColor={{ true: colors.brand }} />
      </Card>

      <Card style={s.noteCard}>
        <Feather name="alert-circle" size={18} color={colors.amberDark} />
        <Text style={s.noteText}>
          Okkle detects movement, not intent. Review every draft before relying on it for tax records.
        </Text>
      </Card>
      </View>
    </View>
  );
}

const s = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  content: { flex: 1, padding: spacing.xl, paddingTop: 60, paddingBottom: 40 },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginBottom: spacing.lg },
  back: { padding: 2 },
  title: { ...type.heading, fontSize: 18, textAlign: 'center', flex: 1 },

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
