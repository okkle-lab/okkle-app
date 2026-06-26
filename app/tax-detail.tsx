import React, { useCallback } from 'react';
import { View, Text, ScrollView, StyleSheet, Pressable } from 'react-native';
import { useFocusEffect, useLocalSearchParams, useRouter } from 'expo-router';
import { Feather } from '@expo/vector-icons';
import { colors, font, spacing, radius, type, tabular } from '../src/theme';
import { Card, SectionHeader, ModalHeader } from '../src/components';
import {
  getTaxYearSummary, getTaxYearMiles, getTaxYearExpenses,
  getUser, getQuarterlySummaries, kvGet, kvGetNum, type QuarterSummary,
} from '../src/db';
import { fmtGbp, fmtMiles, fmtPct, taxYearLabel } from '../src/db/tax';
import { compareMethods, taxPosition, class2Note, caRate, RATES_YEAR } from '../src/db/taxcalc';

type Which = 'bill' | 'saved' | 'year' | 'deadlines';
const TITLES: Record<Which, string> = {
  bill: 'Estimated bill',
  saved: 'Tax saved',
  year: 'This year',
  deadlines: 'Deadlines',
};

export default function TaxDetail() {
  const router = useRouter();
  const params = useLocalSearchParams<{ which?: string }>();
  const which: Which = (['bill', 'saved', 'year', 'deadlines'] as const).includes(params.which as Which) ? (params.which as Which) : 'bill';

  const [year, setYear] = React.useState(getTaxYearSummary());
  const [bizMiles, setBizMiles] = React.useState(0);
  const [otherExpenses, setOtherExpenses] = React.useState(0);
  const [quarters, setQuarters] = React.useState<QuarterSummary[]>([]);
  const [methodInputs, setMethodInputs] = React.useState({ personalMiles: 0, runningCosts: 0, vehicleValue: 0, caBasis: 'low' });
  const [otherIncome, setOtherIncome] = React.useState(0);
  const user = getUser();

  useFocusEffect(useCallback(() => {
    setYear(getTaxYearSummary());
    setBizMiles(getTaxYearMiles());
    setOtherExpenses(getTaxYearExpenses());
    setQuarters(getQuarterlySummaries());
    setOtherIncome(kvGetNum('other_income'));
    setMethodInputs({
      personalMiles: kvGetNum('personal_miles'),
      runningCosts: kvGetNum('running_costs'),
      vehicleValue: kvGetNum('vehicle_value'),
      caBasis: kvGet('ca_basis') || 'low',
    });
  }, []));

  const region = user?.region ?? 'ruk';
  const usingActual = methodInputs.runningCosts > 0;
  const method = compareMethods({
    businessMiles: bizMiles,
    personalMiles: methodInputs.personalMiles,
    runningCosts: methodInputs.runningCosts,
    vehicleValue: methodInputs.vehicleValue,
    capitalAllowanceRate: caRate(methodInputs.caBasis),
    simplifiedDeduction: year.deduction,
  });
  const chosenDeduction = usingActual && method.recommended === 'actual' ? method.actual : method.simplified;
  const pos = taxPosition(year.earnings, chosenDeduction + otherExpenses, region, otherIncome);
  const isCarVan = user?.vehicle === 'car' || user?.vehicle === 'van';

  return (
    <View style={s.screen}>
      <ScrollView contentContainerStyle={s.content}>
        <ModalHeader title={TITLES[which]} />

        {which === 'bill' && (
          <>
            <SectionHeader icon="percent" title="Income tax & National Insurance" />
            <Card style={{ marginBottom: spacing.lg }}>
              <Row label="Income Tax" value={fmtGbp(pos.incomeTax)} />
              <Row label="Class 4 NIC" value={fmtGbp(pos.class4)} />
              <Row label="Total estimated due" value={fmtGbp(pos.totalDue)} bold accent />
              <Row label="Effective rate" value={fmtPct(pos.effectiveRate)} last />
            </Card>
            <Text style={s.note}>{class2Note(pos.profit)}</Text>
            {pos.paymentOnAccount > 0 && (
              <View style={s.poaBox}>
                <Feather name="calendar" size={15} color={colors.textSecondary} />
                <Text style={s.poaText}>Payments on account likely: {fmtGbp(pos.paymentOnAccount)} due 31 Jan and another 31 Jul.</Text>
              </View>
            )}
          </>
        )}

        {which === 'saved' && (
          <>
            <SectionHeader icon="trending-up" title="How your tax saved is worked out" />
            <Card style={{ padding: spacing.lg }}>
              <View style={s.flow}>
                <Cell value={fmtMiles(year.miles)} label="miles tracked" />
                <Feather name="chevron-right" size={16} color={colors.textTertiary} />
                <Cell value={fmtGbp(year.deduction)} label="deduction" />
                <Feather name="chevron-right" size={16} color={colors.textTertiary} />
                <Cell value={fmtGbp(year.taxSaved)} label="tax saved" accent />
              </View>
              <Text style={s.note}>The HMRC mileage rate turns your miles into an allowable deduction; at your ~{Math.round((year.taxRate ?? 0.2) * 100)}% tax + NIC band that deduction is money you don’t pay.</Text>
            </Card>

            <SectionHeader icon="navigation" title="Mileage method" />
            <Card style={{ gap: spacing.md }}>
              <View style={s.methodRow}>
                <View style={{ flex: 1, paddingRight: spacing.md }}>
                  <Text style={s.methodName}>{usingActual && method.recommended === 'actual' ? 'Actual costs' : 'Simplified (flat rate)'}</Text>
                  <Text style={s.rowSub}>{fmtMiles(bizMiles)} business miles this year</Text>
                </View>
                <Text style={s.methodValue}>{fmtGbp(chosenDeduction)}</Text>
              </View>
              <Pressable onPress={() => router.push('/compare')} style={s.compareCta}>
                <Feather name="trending-up" size={16} color={colors.brandDeep} />
                <Text style={s.compareText}>{usingActual ? 'Review method comparison' : 'Could actual costs save you more?'}</Text>
                <Feather name="chevron-right" size={18} color={colors.brandDeep} />
              </Pressable>
            </Card>

            {isCarVan && bizMiles > 0 && (
              <>
                <SectionHeader icon="alert-circle" title="10,000-mile threshold" />
                <Card>
                  <View style={s.row}>
                    <Text style={s.rowLabel}>{fmtMiles(bizMiles)} this tax year</Text>
                    <Text style={s.rowValue}>{Math.round(Math.min(100, (bizMiles / 10000) * 100))}%</Text>
                  </View>
                  <View style={s.track}><View style={[s.fill, { width: `${Math.min(100, (bizMiles / 10000) * 100)}%`, backgroundColor: bizMiles >= 10000 ? colors.amber : colors.brand }]} /></View>
                  <Text style={s.note}>{bizMiles < 10000 ? `${fmtMiles(10000 - bizMiles)} left before your rate drops at 10,000 miles.` : 'Past 10,000 miles — extra car/van miles are claimed at the lower rate.'}</Text>
                </Card>
              </>
            )}
          </>
        )}

        {which === 'year' && (
          <>
            <SectionHeader icon="bar-chart-2" title="Self Assessment summary" />
            <Card>
              <Row label="Turnover (income)" value={fmtGbp(pos.turnover)} />
              <Row label="Allowable expenses" value={fmtGbp(pos.expenses)} />
              <Row label="Net profit" value={fmtGbp(pos.profit)} bold last />
            </Card>
            {pos.usesTradingAllowance && <Text style={s.note}>Using the £1,000 trading allowance (more than your expenses).</Text>}
          </>
        )}

        {which === 'deadlines' && (
          <>
            <SectionHeader icon="calendar" title="Making Tax Digital — quarterly updates" />
            <Card style={{ padding: 0, overflow: 'hidden', marginBottom: spacing.lg }}>
              {quarters.map((q, i) => (
                <View key={q.label} style={[s.qRow, i < quarters.length - 1 && s.rowBorder, q.isCurrent && s.qCurrent]}>
                  <View style={{ flex: 1 }}>
                    <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
                      <Text style={s.qLabel}>{q.label}</Text>
                      {q.isCurrent && <View style={s.qNowTag}><Text style={s.qNowText}>now</Text></View>}
                    </View>
                    <Text style={s.qDates}>{fmtShort(q.start)} – {fmtShort(q.end)} · due {q.deadline}</Text>
                  </View>
                  <View style={{ alignItems: 'flex-end' }}>
                    <Text style={s.qProfit}>{fmtGbp(q.profit)}</Text>
                    <Text style={s.qProfitLabel}>profit</Text>
                  </View>
                </View>
              ))}
            </Card>
            <Pressable onPress={() => router.push('/key-dates')} style={({ pressed }) => [s.linkRow, pressed && { opacity: 0.65 }]}>
              <Feather name="calendar" size={18} color={colors.brandDeep} />
              <Text style={s.linkText}>Key tax dates & HMRC deadlines</Text>
              <Feather name="chevron-right" size={18} color={colors.textTertiary} />
            </Pressable>
            <Text style={s.note}>MTD for Income Tax is mandatory if your self-employment income is over £50,000 (from April 2026), or over £30,000 (from April 2027). You’ll submit these four updates digitally each year.</Text>
          </>
        )}

        <Text style={s.foot}>Estimated using {RATES_YEAR} HMRC rates and what you’ve logged for {taxYearLabel()} — not tax advice.</Text>
      </ScrollView>
    </View>
  );
}

function Row({ label, value, bold, accent, last }: { label: string; value: string; bold?: boolean; accent?: boolean; last?: boolean }) {
  return (
    <View style={[s.row, !last && s.rowBorder]}>
      <Text style={[s.rowLabel, bold && { color: colors.textPrimary, fontWeight: font.medium }]}>{label}</Text>
      <Text style={[s.rowValue, bold && { fontWeight: font.bold }, accent && { color: colors.brandDeep }]}>{value}</Text>
    </View>
  );
}
function Cell({ value, label, accent }: { value: string; label: string; accent?: boolean }) {
  return (
    <View style={s.cell}>
      <Text style={[s.cellVal, accent && { color: colors.brandDeep }]} numberOfLines={1} adjustsFontSizeToFit minimumFontScale={0.6}>{value}</Text>
      <Text style={s.cellLbl}>{label}</Text>
    </View>
  );
}
function fmtShort(iso: string): string {
  return new Date(iso).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' });
}

const s = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  content: { padding: spacing.xl, paddingTop: 60, paddingBottom: 48 },
  row: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', paddingVertical: 10 },
  rowBorder: { borderBottomWidth: 1, borderBottomColor: colors.border },
  rowLabel: { fontSize: 15, color: colors.textSecondary, flex: 1, paddingRight: spacing.md },
  rowValue: { ...tabular, fontSize: 15, fontWeight: font.medium, color: colors.textPrimary, textAlign: 'right' },
  rowSub: { ...type.caption, marginTop: 2 },
  note: { ...type.small, lineHeight: 17, marginTop: 10, marginBottom: spacing.lg },
  poaBox: { flexDirection: 'row', gap: 8, alignItems: 'flex-start' },
  poaText: { ...type.caption, color: colors.textSecondary, flex: 1, lineHeight: 19 },

  flow: { flexDirection: 'row', alignItems: 'center' },
  cell: { flex: 1, alignItems: 'center' },
  cellVal: { ...tabular, fontSize: 17, fontWeight: font.bold, color: colors.textPrimary },
  cellLbl: { ...type.small, fontSize: 11, color: colors.textSecondary, marginTop: 2, textAlign: 'center' },

  methodRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  methodName: { ...type.bodyMedium, fontSize: 16 },
  methodValue: { ...tabular, fontSize: 22, fontWeight: font.bold, color: colors.brandDeep, letterSpacing: -0.5, maxWidth: '55%', textAlign: 'right' },
  compareCta: { flexDirection: 'row', alignItems: 'center', gap: 8, backgroundColor: colors.brandLight, borderRadius: radius.md, padding: spacing.md },
  compareText: { ...type.caption, color: colors.brandDeep, flex: 1, fontWeight: font.medium },

  track: { height: 8, borderRadius: radius.full, backgroundColor: colors.bgSoft, overflow: 'hidden', marginTop: 8 },
  fill: { height: '100%', borderRadius: radius.full },

  qRow: { flexDirection: 'row', alignItems: 'center', padding: spacing.lg },
  qCurrent: { backgroundColor: colors.brandLight },
  qLabel: { ...type.bodyMedium, fontSize: 16 },
  qNowTag: { backgroundColor: colors.brand, borderRadius: radius.full, paddingHorizontal: 8, paddingVertical: 2 },
  qNowText: { color: '#fff', fontSize: 11, fontWeight: font.semibold },
  qDates: { ...type.caption, ...tabular, marginTop: 2 },
  qProfit: { ...tabular, fontSize: 15, fontWeight: font.semibold, color: colors.brandDeep },
  qProfitLabel: { ...type.small },

  linkRow: { flexDirection: 'row', alignItems: 'center', gap: 10, paddingVertical: spacing.sm, marginBottom: spacing.sm },
  linkText: { ...type.bodyMedium, fontSize: 15, color: colors.textPrimary, flex: 1 },
  foot: { ...type.small, color: colors.textTertiary, lineHeight: 17, marginTop: spacing.lg },
});
