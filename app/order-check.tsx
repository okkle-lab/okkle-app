import React from 'react';
import { View, Text, ScrollView, StyleSheet, Pressable, TextInput, KeyboardAvoidingView, Platform } from 'react-native';
import { useRouter } from 'expo-router';
import Feather from '@expo/vector-icons/Feather';
import { colors, font, spacing, radius, type, tabular } from '../src/theme';
import { Card, IconBadge, KeyboardDoneAccessory, numberKeyboardDoneProps } from '../src/components';
import { getYearPnL, kvGetNum, kvSet } from '../src/db';

// "Accept or skip?" — the call couriers make on every offer. Enter the pay and
// the distance, and it tells you the £/mile (and £/hour) and whether it clears
// your target. The target defaults to your own historical average.
export default function OrderCheck() {
  const router = useRouter();
  const pnl = getYearPnL();
  const avgPerMile = pnl.hasData && pnl.perMile > 0 ? pnl.perMile : 0;
  const avgPerHour = pnl.hasData && pnl.grossPerHour > 0 ? pnl.grossPerHour : 0;

  const [pay, setPay] = React.useState('');
  const [miles, setMiles] = React.useState('');
  const [mins, setMins] = React.useState('');
  // Personal target £/mile — seeded from your average (or £1.00), then sticky.
  const [target, setTarget] = React.useState(() => {
    const saved = kvGetNum('target_per_mile', 0);
    if (saved > 0) return saved;
    return avgPerMile > 0 ? Math.round(avgPerMile * 100) / 100 : 1.0;
  });

  function setTargetPersist(v: number) {
    const t = Math.max(0.2, Math.round(v * 100) / 100);
    setTarget(t);
    kvSet('target_per_mile', t);
  }

  const payN = parseFloat(pay) || 0;
  const milesN = parseFloat(miles) || 0;
  const minsN = parseFloat(mins) || 0;
  const hasInput = payN > 0 && milesN > 0;
  const perMile = hasInput ? payN / milesN : 0;
  const perHour = payN > 0 && minsN > 0 ? payN / (minsN / 60) : 0;
  const accept = perMile >= target;

  return (
    <KeyboardAvoidingView style={s.screen} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <ScrollView contentContainerStyle={s.content} keyboardShouldPersistTaps="handled">
        <View style={s.header}>
          <Pressable onPress={() => router.back()} hitSlop={12}><Text style={s.close}>Done</Text></Pressable>
          <Text style={s.title}>Accept or skip?</Text>
          <View style={{ width: 44 }} />
        </View>
        <Text style={s.sub}>Check an offer before you tap accept.</Text>

        {/* The offer */}
        <Card style={{ gap: spacing.lg }}>
          <View style={s.inputRow}>
            <View style={{ flex: 1 }}>
              <Text style={s.fieldLabel}>Offer pay</Text>
              <View style={s.inputWrap}>
                <Text style={s.prefix}>£</Text>
                <TextInput style={s.input} value={pay} onChangeText={setPay} keyboardType="decimal-pad" placeholder="0.00" placeholderTextColor={colors.textTertiary} {...numberKeyboardDoneProps} />
              </View>
            </View>
            <View style={{ flex: 1 }}>
              <Text style={s.fieldLabel}>Distance</Text>
              <View style={s.inputWrap}>
                <TextInput style={s.input} value={miles} onChangeText={setMiles} keyboardType="decimal-pad" placeholder="0.0" placeholderTextColor={colors.textTertiary} {...numberKeyboardDoneProps} />
                <Text style={s.suffix}>mi</Text>
              </View>
            </View>
          </View>
          <View>
            <Text style={s.fieldLabel}>Time estimate (optional)</Text>
            <View style={s.inputWrap}>
              <TextInput style={s.input} value={mins} onChangeText={setMins} keyboardType="number-pad" placeholder="0" placeholderTextColor={colors.textTertiary} {...numberKeyboardDoneProps} />
              <Text style={s.suffix}>min</Text>
            </View>
          </View>
          <Text style={s.hint}>Use the total distance the order will cost you — including the drive to pickup.</Text>
        </Card>

        {/* Verdict */}
        {hasInput ? (
          <View style={[s.verdict, { backgroundColor: accept ? colors.green : colors.red }]}>
            <View style={s.verdictTop}>
              <Feather name={accept ? 'check-circle' : 'x-circle'} size={22} color="#fff" />
              <Text style={s.verdictWord}>{accept ? 'Worth it' : 'Skip it'}</Text>
            </View>
            <Text style={s.verdictBig}>{fmtPerMile(perMile)}</Text>
            <Text style={s.verdictSub}>
              vs your {target.toFixed(2)} target{avgPerMile > 0 ? ` · you average £${avgPerMile.toFixed(2)}/mi` : ''}
            </Text>
            {perHour > 0 && (
              <View style={s.verdictHr}>
                <Text style={s.verdictHrText}>
                  ≈ £{perHour.toFixed(2)}/hr{avgPerHour > 0 ? ` · your average is £${avgPerHour.toFixed(2)}/hr` : ''}
                </Text>
              </View>
            )}
          </View>
        ) : (
          <View style={s.placeholder}>
            <IconBadge icon="navigation" tone="mint" size={44} />
            <Text style={s.placeholderText}>Enter an offer to see its £/mile and whether it beats your target.</Text>
          </View>
        )}

        {/* Target setter */}
        <Card style={{ marginTop: spacing.xl }}>
          <Text style={s.fieldLabel}>Your minimum £/mile</Text>
          <Text style={s.targetNote}>Orders at or above this count as worth it. {avgPerMile > 0 ? `Your historical average is £${avgPerMile.toFixed(2)}/mi.` : 'A common rule of thumb is £1.00–£1.50 per mile.'}</Text>
          <View style={s.stepper}>
            <Pressable onPress={() => setTargetPersist(target - 0.1)} style={s.stepBtn} hitSlop={6}><Feather name="minus" size={20} color={colors.brandDeep} /></Pressable>
            <Text style={s.stepVal}>£{target.toFixed(2)}</Text>
            <Pressable onPress={() => setTargetPersist(target + 0.1)} style={s.stepBtn} hitSlop={6}><Feather name="plus" size={20} color={colors.brandDeep} /></Pressable>
          </View>
        </Card>

        <Text style={s.footnote}>A guide, not a rule — busy areas, stacked orders and tips can make a lower £/mile worth taking.</Text>

        {/* Big, glove-friendly close */}
        <Pressable onPress={() => router.back()} style={({ pressed }) => [s.doneBtn, pressed && { opacity: 0.9 }]}>
          <Feather name="check" size={20} color="#fff" />
          <Text style={s.doneBtnText}>Done</Text>
        </Pressable>
      </ScrollView>
      <KeyboardDoneAccessory />
    </KeyboardAvoidingView>
  );
}

function fmtPerMile(v: number): string { return `£${v.toFixed(2)}/mi`; }

const s = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  content: { padding: spacing.xl, paddingTop: 60, paddingBottom: 60 },
  header: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 6 },
  title: { ...type.heading, fontSize: 18 },
  close: { ...type.bodyMedium, color: colors.brandDeep },
  sub: { ...type.body, color: colors.textSecondary, marginBottom: spacing.lg },

  inputRow: { flexDirection: 'row', gap: spacing.md },
  fieldLabel: { ...type.label, marginBottom: 8 },
  inputWrap: { flexDirection: 'row', alignItems: 'center', borderWidth: 1.5, borderColor: colors.border, borderRadius: radius.md, paddingHorizontal: spacing.md, backgroundColor: colors.bg },
  prefix: { ...type.heading, fontSize: 20, color: colors.textSecondary, marginRight: 4 },
  suffix: { ...type.bodyMedium, color: colors.textSecondary, marginLeft: 4 },
  input: { flex: 1, fontSize: 22, fontWeight: font.bold, color: colors.textPrimary, paddingVertical: 12, ...tabular },
  hint: { ...type.small, lineHeight: 17 },

  verdict: { borderRadius: radius.lg, padding: spacing.xl, marginTop: spacing.xl, alignItems: 'center' },
  verdictTop: { flexDirection: 'row', alignItems: 'center', gap: 8, marginBottom: 6 },
  verdictWord: { color: '#fff', fontSize: 18, fontWeight: font.bold },
  verdictBig: { ...tabular, color: '#fff', fontSize: 44, fontWeight: font.bold, letterSpacing: -1 },
  verdictSub: { color: 'rgba(255,255,255,0.9)', fontSize: 13, marginTop: 2, textAlign: 'center' },
  verdictHr: { backgroundColor: 'rgba(255,255,255,0.2)', borderRadius: radius.full, paddingHorizontal: 12, paddingVertical: 5, marginTop: spacing.md },
  verdictHrText: { ...tabular, color: '#fff', fontSize: 12, fontWeight: font.medium },

  placeholder: { alignItems: 'center', paddingVertical: spacing.xxl, marginTop: spacing.xl, gap: 10 },
  placeholderText: { ...type.caption, textAlign: 'center', lineHeight: 19, paddingHorizontal: spacing.xl },

  targetNote: { ...type.caption, lineHeight: 18, marginTop: 2, marginBottom: spacing.md },
  stepper: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  stepBtn: { width: 48, height: 48, borderRadius: radius.md, backgroundColor: colors.brandLight, alignItems: 'center', justifyContent: 'center' },
  stepVal: { ...tabular, fontSize: 26, fontWeight: font.bold, color: colors.textPrimary },

  footnote: { ...type.small, lineHeight: 18, textAlign: 'center', marginTop: spacing.xl },
  doneBtn: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 8, backgroundColor: colors.brand, borderRadius: radius.lg, paddingVertical: 18, marginTop: spacing.xl },
  doneBtnText: { color: '#fff', fontSize: 18, fontWeight: font.bold },
});
