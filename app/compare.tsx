import React, { useState } from 'react';
import {
  View, Text, TextInput, ScrollView, StyleSheet, Pressable,
  KeyboardAvoidingView, Platform,
} from 'react-native';
import { useRouter } from 'expo-router';
import { Feather } from '@expo/vector-icons';
import { colors, font, spacing, radius, type } from '../src/theme';
import { Card, PrimaryButton } from '../src/components';
import { Chip } from '../src/components';
import { getTaxYearSummary, getTaxYearMiles, kvGet, kvGetNum, kvSet } from '../src/db';
import { compareMethods, caRate, CAPITAL_ALLOWANCE_BASES } from '../src/db/taxcalc';
import { fmtGbp, fmtMiles, calcDeduction, VEHICLES } from '../src/db/tax';

export default function Compare() {
  const router = useRouter();
  const trackedMiles = getTaxYearMiles();

  const [mode, setMode] = useState<'tracked' | 'manual'>('tracked');
  const [vehicle, setVehicle] = useState('car');
  const [businessMiles, setBusinessMiles] = useState(String(Math.round(trackedMiles) || ''));
  const [personalMiles, setPersonalMiles] = useState(String(kvGetNum('personal_miles') || ''));
  const [runningCosts, setRunningCosts] = useState(String(kvGetNum('running_costs') || ''));
  const [vehicleValue, setVehicleValue] = useState(String(kvGetNum('vehicle_value') || ''));
  const [caBasis, setCaBasis] = useState(kvGet('ca_basis') || 'low');

  // Business miles + simplified deduction either from tracked data or manual entry.
  const bizMiles = mode === 'tracked' ? trackedMiles : (parseFloat(businessMiles) || 0);
  const simplifiedDeduction = mode === 'tracked'
    ? getTaxYearSummary().deduction
    : calcDeduction(bizMiles, vehicle);

  const hasInputs = (parseFloat(runningCosts) || 0) > 0;
  const method = compareMethods({
    businessMiles: bizMiles,
    personalMiles: parseFloat(personalMiles) || 0,
    runningCosts: parseFloat(runningCosts) || 0,
    vehicleValue: parseFloat(vehicleValue) || 0,
    capitalAllowanceRate: caRate(caBasis),
    simplifiedDeduction,
  });

  function save() {
    kvSet('personal_miles', parseFloat(personalMiles) || 0);
    kvSet('running_costs', parseFloat(runningCosts) || 0);
    kvSet('vehicle_value', parseFloat(vehicleValue) || 0);
    kvSet('ca_basis', caBasis);
    router.back();
  }

  return (
    <KeyboardAvoidingView style={s.screen} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <ScrollView contentContainerStyle={s.content} keyboardShouldPersistTaps="handled">
        <View style={s.header}>
          <Text style={s.heading}>Compare methods</Text>
          <Pressable onPress={() => router.back()} hitSlop={12}><Text style={s.close}>Cancel</Text></Pressable>
        </View>
        <Text style={s.intro}>
          Most couriers use the simple flat-rate method. If you drive an expensive
          car with high running costs, the actual-cost method can sometimes save more.
          Enter a few numbers to check.
        </Text>

        <Text style={s.label}>Business miles</Text>
        <View style={[s.basisGrid, { flexDirection: 'row', marginBottom: 8 }]}>
          <Chip label="Use my tracked data" selected={mode === 'tracked'} onPress={() => setMode('tracked')} />
          <Chip label="Enter manually" selected={mode === 'manual'} onPress={() => setMode('manual')} />
        </View>
        {mode === 'tracked' ? (
          <Text style={s.hint}>Using your {fmtMiles(trackedMiles)} of tracked business miles.</Text>
        ) : (
          <>
            <TextInput style={s.input} value={businessMiles} onChangeText={setBusinessMiles} keyboardType="decimal-pad" placeholder="e.g. 9000 (try last year's total)" placeholderTextColor={colors.textTertiary} />
            <Text style={s.label}>Vehicle</Text>
            <View style={[s.basisGrid, { flexDirection: 'row', flexWrap: 'wrap' }]}>
              {VEHICLES.map(v => (
                <Chip key={v.key} label={v.label} selected={vehicle === v.key} onPress={() => setVehicle(v.key)} />
              ))}
            </View>
          </>
        )}

        <Text style={s.label}>Total personal (non-work) miles</Text>
        <TextInput style={s.input} value={personalMiles} onChangeText={setPersonalMiles} keyboardType="decimal-pad" placeholder="e.g. 3000" placeholderTextColor={colors.textTertiary} />

        <Text style={s.label}>Annual running costs</Text>
        <TextInput style={s.input} value={runningCosts} onChangeText={setRunningCosts} keyboardType="decimal-pad" placeholder="Fuel, insurance, tax, repairs…" placeholderTextColor={colors.textTertiary} />

        <Text style={s.label}>Vehicle value (for capital allowances)</Text>
        <TextInput style={s.input} value={vehicleValue} onChangeText={setVehicleValue} keyboardType="decimal-pad" placeholder="What the car is worth" placeholderTextColor={colors.textTertiary} />

        <Text style={s.label}>Vehicle type (sets the allowance rate)</Text>
        <View style={s.basisGrid}>
          {CAPITAL_ALLOWANCE_BASES.map(b => {
            const on = caBasis === b.key;
            return (
              <Pressable key={b.key} onPress={() => setCaBasis(b.key)} style={[s.basis, on && s.basisOn]}>
                <Text style={[s.basisLabel, on && { color: colors.brandDeep }]}>{b.label}</Text>
                <Text style={[s.basisSub, on && { color: colors.brandDeep }]}>{b.sub}</Text>
              </Pressable>
            );
          })}
        </View>

        {hasInputs && (
          <Card style={{ marginTop: spacing.xl, gap: spacing.md }}>
            <View style={s.compareRow}>
              <View style={[s.box, method.recommended === 'simplified' && s.boxWin]}>
                <Text style={s.boxLabel}>Simplified</Text>
                <Text style={s.boxValue}>{fmtGbp(method.simplified)}</Text>
                {method.recommended === 'simplified' && <Text style={s.winTag}>Best for you</Text>}
              </View>
              <View style={[s.box, method.recommended === 'actual' && s.boxWin]}>
                <Text style={s.boxLabel}>Actual costs</Text>
                <Text style={s.boxValue}>{fmtGbp(method.actual)}</Text>
                {method.recommended === 'actual' && <Text style={s.winTag}>Best for you</Text>}
              </View>
            </View>
            <View style={s.resultBanner}>
              <Feather name="award" size={16} color={colors.brandDeep} />
              <Text style={s.resultText}>
                {method.recommended === 'actual'
                  ? `Actual costs gives ${fmtGbp(method.difference)} more deduction (${(method.businessUsePct * 100).toFixed(0)}% business use).`
                  : `Simplified wins by ${fmtGbp(method.difference)} — and it's far less paperwork.`}
              </Text>
            </View>
          </Card>
        )}

        <View style={s.warnBox}>
          <Feather name="alert-triangle" size={15} color={colors.amber} />
          <Text style={s.warnText}>
            Important: once you claim actual costs and capital allowances on a vehicle,
            you can't switch back to the simplified method for it. This choice is
            effectively permanent per vehicle — confirm with your accountant first.
          </Text>
        </View>

        <PrimaryButton label="Save" onPress={save} style={{ marginTop: spacing.lg }} />
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

const s = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  content: { padding: spacing.xl, paddingTop: 60, paddingBottom: 60 },
  header: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: spacing.md },
  heading: { ...type.screenTitle },
  close: { ...type.bodyMedium, color: colors.brandDeep },
  intro: { ...type.body, color: colors.textSecondary, lineHeight: 23, marginBottom: spacing.xl },
  label: { ...type.label, marginBottom: 8, marginTop: spacing.md },
  input: { borderWidth: 1.5, borderColor: colors.border, borderRadius: radius.md, padding: spacing.md, fontSize: 17, color: colors.textPrimary, backgroundColor: colors.bgCard },
  hint: { ...type.small, marginTop: 6 },
  basisGrid: { gap: spacing.sm },
  basis: { borderWidth: 1.5, borderColor: colors.borderStrong, borderRadius: radius.md, padding: spacing.md, backgroundColor: colors.bgCard },
  basisOn: { borderColor: colors.brand, backgroundColor: colors.brandLight },
  basisLabel: { ...type.bodyMedium, fontSize: 15, color: colors.textSecondary },
  basisSub: { ...type.small, color: colors.textTertiary, marginTop: 2 },
  compareRow: { flexDirection: 'row', gap: spacing.md },
  box: { flex: 1, borderWidth: 1.5, borderColor: colors.border, borderRadius: radius.md, padding: spacing.lg, alignItems: 'center' },
  boxWin: { borderColor: colors.brand, backgroundColor: colors.brandLight },
  boxLabel: { ...type.label, marginBottom: 4 },
  boxValue: { fontSize: 24, fontWeight: font.bold, color: colors.textPrimary, letterSpacing: -0.5 },
  winTag: { ...type.small, color: colors.brandDeep, fontWeight: font.semibold, marginTop: 4 },
  resultBanner: { flexDirection: 'row', alignItems: 'center', gap: 8, backgroundColor: colors.brandLight, borderRadius: radius.md, padding: spacing.md },
  resultText: { ...type.caption, color: colors.brandDeep, flex: 1, fontWeight: font.medium, lineHeight: 19 },
  warnBox: { flexDirection: 'row', gap: 8, backgroundColor: colors.amberLight, borderRadius: radius.md, padding: spacing.md, marginTop: spacing.xl },
  warnText: { ...type.caption, color: colors.amber, flex: 1, lineHeight: 19 },
});
