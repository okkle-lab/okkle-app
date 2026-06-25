import React, { useState } from 'react';
import { View, Text, TextInput, ScrollView, StyleSheet, Pressable, KeyboardAvoidingView, Platform } from 'react-native';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { Feather } from '@expo/vector-icons';
import { colors, font, spacing, radius, type, tabular } from '../src/theme';
import { Card, Chip, IconBadge, GradientCard, DatePickerField, KeyboardDoneAccessory, numberKeyboardDoneProps } from '../src/components';
import { PLATFORMS, fmtGbp } from '../src/db/tax';
import { saveRecord } from '../src/db';

// Confirm screen for the "screenshot → earnings" Shortcut. A Shortcut OCRs a
// delivery-app earnings screenshot on-device and opens:
//   okkle://log-earnings?amount=84.50&period=week&platform=Uber%20Eats
// Nothing is written until the user taps Save here — they always confirm.
export default function LogEarnings() {
  const router = useRouter();
  const params = useLocalSearchParams<{ amount?: string; period?: string; platform?: string; date?: string }>();

  // Clean the amount the Shortcut found (strip £, commas, stray text).
  const cleanAmount = (params.amount ?? '').replace(/[^0-9.]/g, '');
  const [amount, setAmount] = useState(cleanAmount);
  const [period, setPeriod] = useState<'day' | 'week'>(params.period === 'week' ? 'week' : 'day');
  const [platform, setPlatform] = useState(
    PLATFORMS.find(p => p.toLowerCase() === (params.platform ?? '').toLowerCase()) ?? PLATFORMS[0],
  );
  const [date, setDate] = useState(() => {
    const d = params.date ? new Date(params.date) : new Date();
    const safe = isNaN(d.getTime()) ? new Date() : d;
    safe.setHours(12, 0, 0, 0);
    return safe;
  });

  const weekBounds = (d: Date) => {
    const day = d.getDay(); const mondayOffset = day === 0 ? 6 : day - 1;
    const start = new Date(d); start.setDate(d.getDate() - mondayOffset); start.setHours(12, 0, 0, 0);
    const end = new Date(start); end.setDate(start.getDate() + 6); end.setHours(12, 0, 0, 0);
    return { start, end };
  };
  const wb = weekBounds(date);
  const fmtShort = (d: Date) => d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' });
  const amountN = parseFloat(amount) || 0;
  const canSave = amountN > 0;

  function save() {
    const ps = period === 'week' ? wb.start.toISOString() : null;
    const pe = period === 'week' ? wb.end.toISOString() : null;
    saveRecord({
      record_type: 'income', platform, amount: amountN,
      miles: null, deduction: null, category: null,
      period_start: ps, period_end: pe, receipt_uri: null, notes: 'From screenshot',
    }, date.toISOString());
    router.replace('/(tabs)/records');
  }

  return (
    <KeyboardAvoidingView style={s.screen} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <ScrollView contentContainerStyle={s.content} keyboardShouldPersistTaps="handled">
        <View style={s.header}>
          <Pressable onPress={() => router.back()} hitSlop={12}><Text style={s.close}>Cancel</Text></Pressable>
          <Text style={s.title}>Confirm earnings</Text>
          <View style={{ width: 52 }} />
        </View>

        <View style={s.fromRow}>
          <IconBadge icon="camera" tone="green" size={36} />
          <Text style={s.fromText}>From your {params.platform || 'delivery app'} screenshot — check it's right, then save.</Text>
        </View>

        {/* Amount hero (editable) */}
        <GradientCard colors={['#3BC07E', colors.green, '#1C7048']} radius={radius.lg} style={s.hero}>
          <Text style={s.heroLabel}>Amount received</Text>
          <View style={s.heroRow}>
            <Text style={s.heroPrefix}>£</Text>
            <TextInput
              style={s.heroInput}
              value={amount}
              onChangeText={t => setAmount(t.replace(/[^0-9.]/g, ''))}
              keyboardType="decimal-pad"
              placeholder="0.00"
              placeholderTextColor="rgba(255,255,255,0.5)"
              autoFocus={!canSave}
              {...numberKeyboardDoneProps}
            />
          </View>
          <Text style={s.heroSub}>Gross pay before platform deductions</Text>
        </GradientCard>

        <Card style={{ gap: spacing.lg, marginTop: spacing.md }}>
          {/* Day / Week */}
          <View>
            <Text style={s.fieldLabel}>Is this a day or a week?</Text>
            <View style={s.segRow}>
              {(['day', 'week'] as const).map(p => (
                <Pressable key={p} onPress={() => setPeriod(p)} style={[s.segItem, period === p && s.segItemOn]}>
                  <Text style={[s.segText, period === p && s.segTextOn]}>{p === 'day' ? 'A single day' : 'A whole week'}</Text>
                </Pressable>
              ))}
            </View>
            {period === 'week' && <Text style={s.weekCaption}>Covers {fmtShort(wb.start)} – {fmtShort(wb.end)} · spread across the 7 days</Text>}
          </View>

          {/* Platform */}
          <View>
            <Text style={s.fieldLabel}>Platform</Text>
            <View style={s.wrapRow}>
              {PLATFORMS.map(p => (
                <Chip key={p} label={p} selected={platform === p} onPress={() => setPlatform(p)} size="lg" />
              ))}
            </View>
          </View>

          {/* Date */}
          <View style={s.dateBlock}>
            <Text style={s.fieldLabel}>{period === 'week' ? 'Any day in the pay week' : 'Date'}</Text>
            <DatePickerField value={date} onChange={setDate} quickChips={period === 'day'} />
          </View>
        </Card>

        <Pressable onPress={save} disabled={!canSave} style={({ pressed }) => [pressed && { opacity: 0.9 }, { marginTop: spacing.lg }]}>
          <GradientCard colors={canSave ? [colors.brand, colors.brandDeep] : [colors.borderStrong, colors.borderStrong]} radius={radius.lg} style={s.saveBtn}>
            <Feather name="check" size={20} color="#fff" />
            <Text style={s.saveText}>Save {canSave ? fmtGbp(amountN) : 'earnings'}</Text>
          </GradientCard>
        </Pressable>

        <Text style={s.footnote}>Nothing is logged until you tap Save. You can edit the amount above if the scan got it wrong.</Text>
      </ScrollView>
      <KeyboardDoneAccessory />
    </KeyboardAvoidingView>
  );
}

const s = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  content: { padding: spacing.xl, paddingTop: 60, paddingBottom: 60 },
  header: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: spacing.lg },
  title: { ...type.heading, fontSize: 18 },
  close: { ...type.bodyMedium, color: colors.textSecondary },

  fromRow: { flexDirection: 'row', alignItems: 'center', gap: 12, marginBottom: spacing.md },
  fromText: { ...type.caption, flex: 1, lineHeight: 18 },

  hero: { padding: spacing.lg },
  heroLabel: { color: 'rgba(255,255,255,0.85)', fontSize: 13, fontWeight: font.medium },
  heroRow: { flexDirection: 'row', alignItems: 'center', marginTop: 4 },
  heroPrefix: { ...tabular, color: '#fff', fontSize: 34, fontWeight: font.bold, marginRight: 4 },
  heroInput: { ...tabular, flex: 1, color: '#fff', fontSize: 40, fontWeight: font.bold, letterSpacing: -1, paddingVertical: 4 },
  heroSub: { color: 'rgba(255,255,255,0.85)', fontSize: 13, marginTop: 2 },

  fieldLabel: { ...type.label, marginBottom: 8 },
  segRow: { flexDirection: 'row', gap: spacing.sm },
  segItem: { flex: 1, paddingVertical: 12, borderRadius: radius.md, borderWidth: 1.5, borderColor: colors.border, backgroundColor: colors.bg, alignItems: 'center' },
  segItemOn: { borderColor: colors.brand, backgroundColor: colors.brandLight },
  segText: { ...type.bodyMedium, fontSize: 14, color: colors.textSecondary },
  segTextOn: { color: colors.brandDeep },
  weekCaption: { ...type.caption, color: colors.brandDeep, fontWeight: font.medium, marginTop: spacing.sm },
  wrapRow: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm },
  dateBlock: { borderTopWidth: 1, borderTopColor: colors.border, paddingTop: spacing.lg, gap: spacing.md },

  saveBtn: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 8, paddingVertical: 18 },
  saveText: { color: '#fff', fontSize: 17, fontWeight: font.bold },
  footnote: { ...type.small, lineHeight: 18, textAlign: 'center', marginTop: spacing.lg },
});
