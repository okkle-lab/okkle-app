import React, { useCallback } from 'react';
import { View, Text, ScrollView, StyleSheet, TextInput, Pressable, Alert } from 'react-native';
import { useFocusEffect, useRouter } from 'expo-router';
import { Feather } from '@expo/vector-icons';
import { buttonDepth, colors, font, spacing, radius, type } from '../../src/theme';
import { Card, SectionHeader, CollapsingHeader, Icon, KeyboardDoneAccessory, numberKeyboardDoneProps } from '../../src/components';
import {
  getTaxYearSummary, getTaxYearMiles, getTaxYearExpenses,
  getUser, getQuarterlySummaries,
  kvGet, kvGetNum, kvSet, type QuarterSummary,
} from '../../src/db';
import { fmtGbp, fmtMiles, taxYearLabel, fmtPct } from '../../src/db/tax';
import { tabular } from '../../src/theme';
import {
  compareMethods, taxPosition, class2Note, caRate, PERSONAL_ALLOWANCE, RATES_YEAR,
} from '../../src/db/taxcalc';
export default function TaxScreen() {
  const router = useRouter();
  const [year, setYear] = React.useState(getTaxYearSummary());
  const [bizMiles, setBizMiles] = React.useState(0);
  const [otherExpenses, setOtherExpenses] = React.useState(0);
  const [methodInputs, setMethodInputs] = React.useState({ personalMiles: 0, runningCosts: 0, vehicleValue: 0, caBasis: 'low' });
  const [otherIncome, setOtherIncome] = React.useState(String(kvGetNum('other_income') || ''));
  const [quarters, setQuarters] = React.useState<QuarterSummary[]>([]);
  const user = getUser();

  function reload() {
    setYear(getTaxYearSummary());
    setBizMiles(getTaxYearMiles());
    setOtherExpenses(getTaxYearExpenses());
    setQuarters(getQuarterlySummaries());
    setMethodInputs({
      personalMiles: kvGetNum('personal_miles'),
      runningCosts: kvGetNum('running_costs'),
      vehicleValue: kvGetNum('vehicle_value'),
      caBasis: kvGet('ca_basis') || 'low',
    });
  }
  useFocusEffect(useCallback(() => { reload(); }, []));

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
  const totalExpenses = chosenDeduction + otherExpenses;
  const pos = taxPosition(year.earnings, totalExpenses, region, parseFloat(otherIncome) || 0);


  const gear = (
    <Pressable onPress={() => router.push('/settings')} hitSlop={10}>
      <Icon name="settings" size={22} color={colors.textSecondary} />
    </Pressable>
  );

  return (
    <View style={{ flex: 1 }}>
      <CollapsingHeader title="Tax" subtitle={`Your estimated position for ${taxYearLabel()}`} right={gear}>
      {/* Headline: what to set aside — the number that matters on this tab */}
      <View style={s.setAside}>
        <View style={s.setAsideIcon}><Feather name="shield" size={20} color="#fff" /></View>
        <View style={{ flex: 1 }}>
          <Text style={s.setAsideLabel}>Set aside for tax</Text>
          <Text style={s.setAsideSub}>Estimated bill for {taxYearLabel()} so far</Text>
        </View>
        <Text style={s.setAsideValue}>{fmtGbp(pos.totalDue)}</Text>
      </View>

      {/* How "tax saved" is worked out — the chain from miles to money back */}
      {year.miles > 0 && (
        <Card style={{ marginBottom: spacing.xl, padding: spacing.lg }}>
          <Text style={s.savedHead}>How your tax saved is worked out</Text>
          <View style={s.savedFlow}>
            <View style={s.savedCell}>
              <Text style={s.savedVal} numberOfLines={1} adjustsFontSizeToFit minimumFontScale={0.6}>{fmtMiles(year.miles)}</Text>
              <Text style={s.savedLbl}>miles tracked</Text>
            </View>
            <Feather name="chevron-right" size={16} color={colors.textTertiary} />
            <View style={s.savedCell}>
              <Text style={s.savedVal} numberOfLines={1} adjustsFontSizeToFit minimumFontScale={0.6}>{fmtGbp(year.deduction)}</Text>
              <Text style={s.savedLbl}>deduction</Text>
            </View>
            <Feather name="chevron-right" size={16} color={colors.textTertiary} />
            <View style={s.savedCell}>
              <Text style={[s.savedVal, { color: colors.brandDeep }]} numberOfLines={1} adjustsFontSizeToFit minimumFontScale={0.6}>{fmtGbp(year.taxSaved)}</Text>
              <Text style={s.savedLbl}>tax saved</Text>
            </View>
          </View>
          <Text style={s.savedNote}>HMRC mileage rate turns your miles into an allowable deduction; at your ~{Math.round((year.taxRate ?? 0.2) * 100)}% tax + NIC band that deduction is money you don't pay.</Text>
        </Card>
      )}

      {/* Mileage method — clean summary, comparison lives in its own tool */}
      <SectionHeader icon="navigation" title="Mileage method" />
      <Card style={{ gap: spacing.md, marginBottom: spacing.xl }}>
        <View style={s.methodRow}>
          <View style={{ flex: 1, paddingRight: spacing.md }}>
            <Text style={s.methodName}>
              {usingActual && method.recommended === 'actual' ? 'Actual costs' : 'Simplified (flat rate)'}
            </Text>
            <Text style={s.methodSub} numberOfLines={1}>{fmtMiles(bizMiles)} business miles this year</Text>
          </View>
          <Text style={s.methodValue} numberOfLines={1} adjustsFontSizeToFit minimumFontScale={0.5}>{fmtGbp(chosenDeduction)}</Text>
        </View>
        <Pressable onPress={() => router.push('/compare')} style={({ pressed }) => [s.compareCta, buttonDepth.raised, pressed && buttonDepth.pressed]}>
          <View pointerEvents="none" style={[s.buttonGloss, buttonDepth.gloss]} />
          <Feather name="trending-up" size={16} color={colors.brandDeep} />
          <Text style={s.compareCtaText}>
            {usingActual ? 'Review method comparison' : 'Could actual costs save you more?'}
          </Text>
          <Feather name="chevron-right" size={18} color={colors.brandDeep} />
        </Pressable>
      </Card>

      {/* 10,000-mile threshold — only relevant for cars/vans on the simplified rate */}
      {(user?.vehicle === 'car' || user?.vehicle === 'van') && bizMiles > 0 && (
        <>
          <SectionHeader icon="alert-circle" title="10,000-mile threshold" />
          <Card style={{ marginBottom: spacing.xl }}>
            <View style={s.row}>
              <Text style={s.rowLabel}>{fmtMiles(bizMiles)} this tax year</Text>
              <Text style={s.rowValue}>{Math.round(Math.min(100, (bizMiles / 10000) * 100))}%</Text>
            </View>
            <View style={s.thresholdTrack}>
              <View style={[s.thresholdFill, { width: `${Math.min(100, (bizMiles / 10000) * 100)}%`, backgroundColor: bizMiles >= 10000 ? colors.amber : colors.brand }]} />
            </View>
            <Text style={s.smallNote}>
              {bizMiles < 10000
                ? `${fmtMiles(10000 - bizMiles)} left before your rate drops from 45p to 25p per mile.`
                : 'Past 10,000 miles — extra car/van miles are claimed at 25p.'}
            </Text>
          </Card>
        </>
      )}

      {/* Self Assessment summary */}
      <SectionHeader icon="file-text" title="Self Assessment summary" />
      <Card style={{ marginBottom: spacing.xl }}>
        <Row label="Turnover (income)" value={fmtGbp(pos.turnover)} />
        <Row label="Allowable expenses" value={fmtGbp(pos.expenses)} />
        <Row label="Net profit" value={fmtGbp(pos.profit)} bold />
        {pos.usesTradingAllowance && (
          <Text style={s.smallNote}>Using the £1,000 trading allowance (more than your expenses).</Text>
        )}
      </Card>

      {/* Other income — for marginal-rate accuracy */}
      <SectionHeader icon="briefcase" title="Other income (for accuracy)" />
      <Card style={{ marginBottom: spacing.xl }}>
        <Text style={s.inputLabel}>Wages or other income this tax year</Text>
        <TextInput
          style={s.input}
          value={otherIncome}
          onChangeText={setOtherIncome}
          onBlur={() => kvSet('other_income', parseFloat(otherIncome) || 0)}
          keyboardType="decimal-pad"
          placeholder="£0 if courier work is your only income"
          placeholderTextColor={colors.textTertiary}
          {...numberKeyboardDoneProps}
        />
        <Text style={s.smallNote}>
          If you have another job, your courier profit is taxed on top of it — so this makes your estimate accurate.
        </Text>
      </Card>

      {/* Tax & NIC */}
      <SectionHeader icon="percent" title="Estimated tax & National Insurance" />
      <Card style={{ marginBottom: spacing.xl }}>
        <Row label="Income Tax" value={fmtGbp(pos.incomeTax)} />
        <Row label="Class 4 NIC" value={fmtGbp(pos.class4)} />
        <Row label="Total estimated due" value={fmtGbp(pos.totalDue)} bold accent />
        <Row label="Effective rate" value={fmtPct(pos.effectiveRate)} />
        <Text style={s.smallNote}>{class2Note(pos.profit)}</Text>
        {pos.paymentOnAccount > 0 && (
          <View style={s.poaBox}>
            <Feather name="calendar" size={15} color={colors.textSecondary} />
            <Text style={s.poaText}>
              Payments on account likely: {fmtGbp(pos.paymentOnAccount)} due 31 Jan and another 31 Jul.
            </Text>
          </View>
        )}
      </Card>


      {/* MTD quarterly updates */}
      <SectionHeader icon="calendar" title="Making Tax Digital — quarterly updates" />
      <Card style={{ padding: 0, overflow: 'hidden', marginBottom: spacing.xl }}>
        {quarters.map((q, i) => (
          <View key={q.label} style={[s.qRow, i < quarters.length - 1 && s.qBorder, q.isCurrent && s.qCurrent]}>
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
      <Text style={s.mtdNote}>
        MTD for Income Tax is mandatory if your self-employment income is over £50,000 (from April 2026), or over £30,000 (from April 2027). You'll submit these four updates digitally each year.
      </Text>

      {/* Export — send everything to your accountant */}
      <SectionHeader icon="send" title="Send to your accountant" />
      <Pressable onPress={() => router.push('/export')} style={({ pressed }) => [s.exportCard, buttonDepth.raisedStrong, pressed && buttonDepth.pressed]}>
        <View pointerEvents="none" style={[s.exportGloss, buttonDepth.gloss]} />
        <View style={s.exportIcon}><Feather name="file-text" size={22} color="#fff" /></View>
        <View style={{ flex: 1 }}>
          <Text style={s.exportCardTitle}>Export &amp; share</Text>
          <Text style={s.exportCardSub}>Accountant Pack, FreeAgent, mileage log, CSV</Text>
        </View>
        <Feather name="chevron-right" size={22} color="#fff" />
      </Pressable>

      <View style={s.disclaimer}>
        <Feather name="shield" size={14} color={colors.textTertiary} />
        <Text style={s.disclaimerText}>
          Estimated using {RATES_YEAR} HMRC rates (allowances frozen to 2027/28) and what you've logged — not tax advice. Your accountant confirms the final figures and files your return.
        </Text>
      </View>
      </CollapsingHeader>
      <KeyboardDoneAccessory />
    </View>
  );
}

function fmtShort(iso: string): string {
  return new Date(iso).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' });
}

function Row({ label, value, bold, accent }: { label: string; value: string; bold?: boolean; accent?: boolean }) {
  return (
    <View style={s.row}>
      <Text style={[s.rowLabel, bold && { color: colors.textPrimary, fontWeight: font.medium }]}>{label}</Text>
      <Text style={[s.rowValue, bold && { fontWeight: font.bold }, accent && { color: colors.brandDeep }]}>{value}</Text>
    </View>
  );
}

const s = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  content: { padding: spacing.xl, paddingTop: 60, paddingBottom: 40 },
  heading: { ...type.screenTitle, marginBottom: 6 },
  sub: { ...type.body, color: colors.textSecondary, marginBottom: spacing.xl },

  setAside: { flexDirection: 'row', alignItems: 'center', gap: 14, backgroundColor: colors.amber, borderRadius: radius.xl, padding: spacing.lg, marginBottom: spacing.xl },
  setAsideIcon: { width: 42, height: 42, borderRadius: 21, backgroundColor: 'rgba(255,255,255,0.25)', alignItems: 'center', justifyContent: 'center' },
  setAsideLabel: { ...type.bodyMedium, fontSize: 16, color: '#fff' },
  setAsideSub: { ...type.caption, color: 'rgba(255,255,255,0.9)', marginTop: 1 },
  setAsideValue: { ...tabular, fontSize: 26, fontWeight: font.bold, color: '#fff', letterSpacing: -0.5 },
  savedHead: { ...type.label, color: colors.textSecondary, fontWeight: font.semibold, marginBottom: spacing.md },
  savedFlow: { flexDirection: 'row', alignItems: 'center' },
  savedCell: { flex: 1, alignItems: 'center' },
  savedVal: { ...tabular, fontSize: 17, fontWeight: font.bold, color: colors.textPrimary },
  savedLbl: { ...type.small, fontSize: 11, color: colors.textSecondary, marginTop: 2, textAlign: 'center' },
  savedNote: { ...type.small, lineHeight: 17, marginTop: spacing.md },

  methodRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  methodName: { ...type.bodyMedium, fontSize: 16 },
  methodSub: { ...type.caption, marginTop: 2 },
  methodValue: { ...tabular, fontSize: 22, fontWeight: font.bold, color: colors.brandDeep, letterSpacing: -0.5, flexShrink: 1, maxWidth: '55%', textAlign: 'right' },
  compareCta: { flexDirection: 'row', alignItems: 'center', gap: 8, backgroundColor: colors.brandLight, borderRadius: radius.md, borderWidth: 1.5, borderColor: colors.brand, padding: spacing.md, borderCurve: 'continuous', overflow: 'hidden' },
  compareCtaText: { ...type.caption, color: colors.brandDeep, flex: 1, fontWeight: font.medium },
  inputLabel: { ...type.caption, color: colors.textSecondary, marginBottom: 8 },
  input: { borderWidth: 1.5, borderColor: colors.border, borderRadius: radius.md, padding: spacing.md, fontSize: 17, color: colors.textPrimary, backgroundColor: colors.bg },

  thresholdTrack: { height: 8, borderRadius: radius.full, backgroundColor: colors.bgSoft, overflow: 'hidden', marginTop: 8 },
  thresholdFill: { height: '100%', borderRadius: radius.full },
  row: { flexDirection: 'row', justifyContent: 'space-between', paddingVertical: 9, borderBottomWidth: 1, borderBottomColor: colors.border },
  rowLabel: { fontSize: 15, color: colors.textSecondary, flex: 1, paddingRight: spacing.md },
  rowValue: { ...tabular, fontSize: 15, fontWeight: font.medium, color: colors.textPrimary, textAlign: 'right' },
  smallNote: { ...type.small, marginTop: 10, lineHeight: 17 },
  poaBox: { flexDirection: 'row', gap: 8, marginTop: 12, alignItems: 'flex-start' },
  poaText: { ...type.caption, color: colors.textSecondary, flex: 1, lineHeight: 19 },


  qRow: { flexDirection: 'row', alignItems: 'center', padding: spacing.lg },
  qBorder: { borderBottomWidth: 1, borderBottomColor: colors.border },
  qCurrent: { backgroundColor: colors.brandLight },
  qLabel: { ...type.bodyMedium, fontSize: 16 },
  qNowTag: { backgroundColor: colors.brand, borderRadius: radius.full, paddingHorizontal: 8, paddingVertical: 2 },
  qNowText: { color: '#fff', fontSize: 11, fontWeight: font.semibold },
  qDates: { ...type.caption, ...tabular, marginTop: 2 },
  qProfit: { ...tabular, fontSize: 15, fontWeight: font.semibold, color: colors.brandDeep },
  qProfitLabel: { ...type.small },
  mtdNote: { ...type.small, lineHeight: 18, marginTop: spacing.md },

  exportCard: { flexDirection: 'row', alignItems: 'center', gap: 14, backgroundColor: colors.brand, borderRadius: radius.lg, borderWidth: 1, borderColor: 'rgba(255,255,255,0.24)', padding: spacing.lg, borderCurve: 'continuous', overflow: 'hidden' },
  exportIcon: { width: 42, height: 42, borderRadius: 21, backgroundColor: 'rgba(255,255,255,0.22)', alignItems: 'center', justifyContent: 'center' },
  exportCardTitle: { color: '#fff', fontSize: 16, fontWeight: font.bold },
  exportCardSub: { color: 'rgba(255,255,255,0.85)', fontSize: 12, marginTop: 2 },

  disclaimer: { marginTop: spacing.xl, padding: spacing.lg, backgroundColor: colors.bgSoft, borderRadius: radius.md, flexDirection: 'row', gap: 8, alignItems: 'flex-start' },
  disclaimerText: { ...type.small, lineHeight: 18, flex: 1 },
  buttonGloss: { borderRadius: radius.full, height: 1, left: 12, position: 'absolute', right: 12, top: 1 },
  exportGloss: { borderRadius: radius.full, height: 1.5, left: 16, position: 'absolute', right: 16, top: 1 },
});
