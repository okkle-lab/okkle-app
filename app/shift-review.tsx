import React from 'react';
import { View, Text, ScrollView, StyleSheet, Pressable, TextInput, Alert } from 'react-native';
import { useRouter } from 'expo-router';
import { Feather } from '@expo/vector-icons';
import { colors, font, spacing, radius, type } from '../src/theme';
import { Card, GradientCard, Chip, PrimaryButton, numberKeyboardDoneProps } from '../src/components';
import { fmtGbp, fmtMiles } from '../src/db/tax';
import {
  getLatestDraftShift, getPlatforms, updateRecord, deleteRecord, saveRecord,
  kvGet, kvSet, type Record as Rec,
} from '../src/db';

// On-device learning: remember the app(s) tagged last time and pre-select them, so
// a regular Deliveroo-only driver just taps Confirm. Stays entirely on the phone.
function recallLastPlatforms(valid: string[]): string[] {
  try {
    const saved = JSON.parse(kvGet('shift_last_platforms') || '[]') as string[];
    return saved.filter(p => valid.includes(p));
  } catch { return []; }
}

// End-of-shift review. The passive tracker logs a *draft* mileage record; here the
// driver confirms it (one tap), optionally tags which app(s) the shift was on, and
// — only for a single-app shift — optionally records what they earned. Multi-app
// earnings can't be honestly split per mile, so we ask them to log those weekly.
export default function ShiftReview() {
  const router = useRouter();
  const [rec] = React.useState<Rec | null>(() => getLatestDraftShift());
  const platforms = React.useMemo(() => getPlatforms(), []);
  const [tagged, setTagged] = React.useState<string[]>(() => recallLastPlatforms(getPlatforms()));
  const [earned, setEarned] = React.useState('');

  if (!rec) {
    return (
      <View style={[s.screen, s.center]}>
        <Text style={s.empty}>No shift to review right now.</Text>
        <PrimaryButton label="Done" onPress={() => router.back()} style={{ marginTop: spacing.lg }} />
      </View>
    );
  }

  const miles = rec.miles ?? 0;
  const deduction = rec.deduction ?? 0;
  const singleApp = tagged.length === 1;

  function toggle(p: string) {
    setTagged(t => (t.includes(p) ? t.filter(x => x !== p) : [...t, p]));
  }

  function confirm() {
    // Tag the platform(s) onto the mileage record and clear the draft marker so
    // it stops appearing for review. Multi-app shifts are joined with " + ".
    const platform = tagged.length ? tagged.join(' + ') : null;
    // notes:'' clears the draft marker so this stops showing as unreviewed.
    updateRecord(rec!.id, { platform, notes: '' });
    if (tagged.length) kvSet('shift_last_platforms', JSON.stringify(tagged)); // learn for next time

    // Optional earnings — only meaningful (and honest) for a single-app shift.
    if (singleApp && earned.trim()) {
      const amt = parseFloat(earned);
      if (!Number.isNaN(amt) && amt > 0) {
        const day = (rec!.created_at ?? new Date().toISOString()).slice(0, 10);
        saveRecord({
          record_type: 'income', platform: tagged[0], amount: amt, miles: null,
          deduction: null, category: null, period_start: day, period_end: day,
          receipt_uri: null, notes: null,
        }, rec!.created_at);
      }
    }
    router.back();
  }

  function discard() {
    Alert.alert('Discard this shift?', 'The tracked miles won’t be saved. Use this if it was a personal drive.', [
      { text: 'Keep' },
      { text: 'Discard', style: 'destructive', onPress: () => { deleteRecord(rec!.id); router.back(); } },
    ]);
  }

  return (
    <ScrollView style={s.screen} contentContainerStyle={s.content} keyboardShouldPersistTaps="handled">
      <View style={s.header}>
        <Pressable onPress={() => router.back()} hitSlop={12}>
          <Feather name="chevron-down" size={26} color={colors.textPrimary} />
        </Pressable>
        <Text style={s.title}>Review your shift</Text>
        <View style={{ width: 26 }} />
      </View>

      <GradientCard colors={[colors.brand, colors.brandDeep, colors.dark]} radius={radius.xl} style={s.hero}>
        <Text style={s.heroLabel}>Auto-tracked miles</Text>
        <Text style={s.heroMiles}>{fmtMiles(miles)}</Text>
        <Text style={s.heroSub}>About {fmtGbp(deduction)} off your tax bill. Tap confirm and it’s saved.</Text>
      </GradientCard>

      <Text style={s.section}>Which app were you on?</Text>
      <Text style={s.hint}>Optional — helps us show which platform pays best. Pick more than one if you were multi-apping.</Text>
      <View style={s.chips}>
        {platforms.map(p => (
          <Chip key={p} label={p} selected={tagged.includes(p)} onPress={() => toggle(p)} />
        ))}
      </View>

      {singleApp && (
        <Card style={s.earnCard}>
          <Text style={s.section}>Earned on this shift?</Text>
          <Text style={s.hint}>Optional — what {tagged[0]} paid you for it.</Text>
          <View style={s.amountRow}>
            <Text style={s.pound}>£</Text>
            <TextInput
              value={earned}
              onChangeText={setEarned}
              keyboardType="decimal-pad"
              placeholder="0.00"
              placeholderTextColor={colors.textTertiary}
              style={s.amount}
              {...numberKeyboardDoneProps}
            />
          </View>
        </Card>
      )}
      {tagged.length > 1 && (
        <Text style={s.note}>
          Mixed-app shift — earnings can’t be split per mile, so log each app’s pay weekly from its statement. The miles are still saved.
        </Text>
      )}

      <View style={{ height: spacing.xl }} />
      <PrimaryButton label="Confirm shift" onPress={confirm} />
      <Pressable onPress={discard} style={s.discard} hitSlop={8}>
        <Text style={s.discardText}>Discard — this was a personal drive</Text>
      </Pressable>
    </ScrollView>
  );
}

const s = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  content: { padding: spacing.xl, paddingTop: 24, paddingBottom: 48 },
  center: { justifyContent: 'center', alignItems: 'center', padding: spacing.xl },
  empty: { ...type.body, color: colors.textSecondary },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginBottom: spacing.lg },
  title: { ...type.screenTitle },

  hero: { padding: spacing.xl, gap: 4 },
  heroLabel: { color: 'rgba(255,255,255,0.85)', fontSize: 13, fontWeight: font.semibold, letterSpacing: 0.3, textTransform: 'uppercase' },
  heroMiles: { color: '#fff', fontSize: 44, fontWeight: font.bold, letterSpacing: -1 },
  heroSub: { color: 'rgba(255,255,255,0.88)', fontSize: 14, lineHeight: 20, marginTop: 2 },

  section: { ...type.bodyMedium, fontSize: 16, marginTop: spacing.xl },
  hint: { ...type.caption, lineHeight: 18, marginTop: 2, marginBottom: spacing.sm },
  chips: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm },

  earnCard: { marginTop: spacing.lg, gap: 2 },
  amountRow: { flexDirection: 'row', alignItems: 'center', gap: 6, marginTop: spacing.sm },
  pound: { fontSize: 28, fontWeight: font.semibold, color: colors.textSecondary },
  amount: { flex: 1, fontSize: 32, fontWeight: font.bold, color: colors.textPrimary, padding: 0 },

  note: { ...type.small, lineHeight: 18, marginTop: spacing.md },
  discard: { alignSelf: 'center', marginTop: spacing.lg, padding: spacing.sm },
  discardText: { ...type.caption, color: colors.textTertiary },
});
