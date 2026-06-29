import { useState } from 'react';
import { View, Text, TextInput, ScrollView, StyleSheet, Pressable } from 'react-native';
import Feather from '@expo/vector-icons/Feather';
import { useRouter } from 'expo-router';
import { colors, spacing, radius, type, font } from '../src/theme';
import { Card, Chip, PrimaryButton, ModalHeader } from '../src/components';
import { REGIONS, regionRate, regionLabel } from '../src/db/tax';
import { getUser, saveUser, kvGetNum, kvSet } from '../src/db';

// One place for everything that changes the tax estimate — region, band, other
// income, and the mileage-method choice — reachable from the Tax tab.
export default function TaxSetup() {
  const router = useRouter();
  const u = getUser();
  const [region, setRegion] = useState(u?.region ?? 'ruk');
  const [band, setBand] = useState<'basic' | 'higher'>((u?.tax_rate ?? 0.2) >= 0.4 ? 'higher' : 'basic');
  const [otherIncome, setOtherIncome] = useState(String(kvGetNum('other_income') || ''));

  function save() {
    saveUser({ region, tax_rate: regionRate(region, band) });
    kvSet('other_income', parseFloat(otherIncome) || 0);
    router.back();
  }

  return (
    <View style={s.screen}>
      <ScrollView contentContainerStyle={s.content} keyboardShouldPersistTaps="handled">
        <ModalHeader title="Tax settings" />
        <Text style={s.intro}>These adjust your tax estimate — set them once and the Tax tab stays accurate.</Text>

        <Card style={{ gap: spacing.lg }}>
          <View>
            <Text style={s.label}>Where you live</Text>
            <View style={s.chips}>
              {REGIONS.map(r => <Chip key={r.key} label={r.label} selected={region === r.key} onPress={() => setRegion(r.key)} />)}
            </View>
          </View>
          <View>
            <Text style={s.label}>Income tax band</Text>
            <View style={s.chips}>
              <Chip label="Basic rate" selected={band === 'basic'} onPress={() => setBand('basic')} />
              <Chip label="Higher rate" selected={band === 'higher'} onPress={() => setBand('higher')} />
            </View>
          </View>
          <Text style={s.note}>Estimating take-home at {(regionRate(region, band) * 100).toFixed(0)}% ({regionLabel(region)}).</Text>
        </Card>

        <Card style={{ gap: spacing.sm, marginTop: spacing.lg }}>
          <Text style={s.label}>Other income this tax year</Text>
          <TextInput style={s.input} value={otherIncome} onChangeText={setOtherIncome} keyboardType="decimal-pad" placeholder="£0 if courier work is your only income" placeholderTextColor={colors.textTertiary} />
          <Text style={s.note}>Wages or other income (e.g. a PAYE job). Your courier profit is taxed on top of it, so this keeps the estimate accurate.</Text>
        </Card>

        <PrimaryButton label="Save" onPress={save} style={{ marginTop: spacing.lg }} />
      </ScrollView>
    </View>
  );
}

const s = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  content: { padding: spacing.xl, paddingTop: 60, paddingBottom: 48 },
  intro: { ...type.caption, lineHeight: 19, marginBottom: spacing.lg },
  label: { ...type.label, marginBottom: 8 },
  input: { borderWidth: 1.5, borderColor: colors.border, borderRadius: radius.md, padding: spacing.md, fontSize: 17, color: colors.textPrimary, backgroundColor: colors.bg },
  chips: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm },
  note: { ...type.caption, color: colors.textTertiary, lineHeight: 18 },
  linkRow: { flexDirection: 'row', alignItems: 'center', gap: 10, paddingVertical: spacing.md, marginTop: spacing.sm },
  linkText: { ...type.bodyMedium, fontSize: 15, color: colors.textPrimary, flex: 1 },
});
