import React, { useCallback } from 'react';
import { View, Text, ScrollView, StyleSheet, TextInput, Pressable } from 'react-native';
import { useFocusEffect, useRouter } from 'expo-router';
import { Feather } from '@expo/vector-icons';
import { colors, font, spacing, radius, type } from '../../src/theme';
import { Card, SectionHeader } from '../../src/components';
import {
  getTaxYearSummary, getTaxYearMiles, getTaxYearExpenses,
  getUser, getQuarterlySummaries, getHoursWorked, getPlatformStats,
  kvGet, kvGetNum, kvSet, type QuarterSummary, type PlatformStat,
} from '../../src/db';
import { fmtGbp, fmtMiles, taxYearLabel, fmtPerHour, fmtPerMile, fmtHours, fmtPct } from '../../src/db/tax';
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
  const [hours, setHours] = React.useState(0);
  const [platforms, setPlatforms] = React.useState<PlatformStat[]>([]);
  const user = getUser();

  function reload() {
    setYear(getTaxYearSummary());
    setBizMiles(getTaxYearMiles());
    setOtherExpenses(getTaxYearExpenses());
    setQuarters(getQuarterlySummaries());
    setHours(getHoursWorked());
    setPlatforms(getPlatformStats());
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

  const grossPerMile = bizMiles > 0 ? year.earnings / bizMiles : 0;

  return (
    <ScrollView style={s.screen} contentContainerStyle={s.content}>
      <Text style={s.heading}>Tax</Text>
      <Text style={s.sub}>Your estimated position for {taxYearLabel()}</Text>

      {/* Headline: what to set aside — the number that matters on this tab */}
      <View style={s.setAside}>
        <View style={s.setAsideIcon}><Feather name="shield" size={20} color="#fff" /></View>
        <View style={{ flex: 1 }}>
          <Text style={s.setAsideLabel}>Set aside for tax</Text>
          <Text style={s.setAsideSub}>Estimated bill for {taxYearLabel()} so far</Text>
        </View>
        <Text style={s.setAsideValue}>{fmtGbp(pos.totalDue)}</Text>
      </View>

      {/* Mileage method — clean summary, comparison lives in its own tool */}
      <SectionHeader icon="navigation" title="Mileage method" />
      <Card style={{ gap: spacing.md }}>
        <View style={s.methodRow}>
          <View style={{ flex: 1, paddingRight: spacing.md }}>
            <Text style={s.methodName}>
              {usingActual && method.recommended === 'actual' ? 'Actual costs' : 'Simplified (flat rate)'}
            </Text>
            <Text style={s.methodSub} numberOfLines={1}>{fmtMiles(bizMiles)} business miles this year</Text>
          </View>
          <Text style={s.methodValue} numberOfLines={1} adjustsFontSizeToFit minimumFontScale={0.5}>{fmtGbp(chosenDeduction)}</Text>
        </View>
        <Pressable onPress={() => router.push('/compare')} style={s.compareCta}>
          <Feather name="trending-up" size={16} color={colors.brandDeep} />
          <Text style={s.compareCtaText}>
            {usingActual ? 'Review method comparison' : 'Could actual costs save you more?'}
          </Text>
          <Feather name="chevron-right" size={18} color={colors.brandDeep} />
        </Pressable>
      </Card>

      {/* Self Assessment summary */}
      <SectionHeader icon="file-text" title="Self Assessment summary" />
      <Card>
        <Row label="Turnover (income)" value={fmtGbp(pos.turnover)} />
        <Row label="Allowable expenses" value={fmtGbp(pos.expenses)} />
        <Row label="Net profit" value={fmtGbp(pos.profit)} bold />
        {pos.usesTradingAllowance && (
          <Text style={s.smallNote}>Using the £1,000 trading allowance (more than your expenses).</Text>
        )}
      </Card>

      {/* Other income — for marginal-rate accuracy */}
      <SectionHeader icon="briefcase" title="Other income (for accuracy)" />
      <Card>
        <Text style={s.inputLabel}>Wages or other income this tax year</Text>
        <TextInput
          style={s.input}
          value={otherIncome}
          onChangeText={setOtherIncome}
          onBlur={() => kvSet('other_income', parseFloat(otherIncome) || 0)}
          keyboardType="decimal-pad"
          placeholder="£0 if courier work is your only income"
          placeholderTextColor={colors.textTertiary}
        />
        <Text style={s.smallNote}>
          If you have another job, your courier profit is taxed on top of it — so this makes your estimate accurate.
        </Text>
      </Card>

      {/* Tax & NIC */}
      <SectionHeader icon="percent" title="Estimated tax & National Insurance" />
      <Card>
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

      {/* Insights — your business as a P&L */}
      <SectionHeader icon="bar-chart-2" title="Business insights" />
      <Card>
        <Row label="Effective net pay / hour" value={hours > 0 ? fmtPerHour((pos.profit - pos.totalDue) / hours) : '—'} bold accent />
        <Row label="Gross pay / hour" value={hours > 0 ? fmtPerHour(year.earnings / hours) : '—'} />
        <Row label="Gross earnings / mile" value={fmtPerMile(grossPerMile)} />
        <Row label="Net margin (kept after tax)" value={year.earnings > 0 ? fmtPct((pos.profit - pos.totalDue) / year.earnings) : '—'} />
        <Row label="Hours tracked this year" value={fmtHours(hours)} />
        <Row label="Personal allowance left" value={fmtGbp(Math.max(0, PERSONAL_ALLOWANCE - pos.profit))} />
        {hours === 0 && (
          <Text style={s.smallNote}>Track trips and add earnings to unlock your hourly rate and margin.</Text>
        )}
      </Card>

      {/* Platform ROI by hour */}
      {platforms.some(p => p.perHour > 0) && (
        <>
          <SectionHeader icon="award" title="Which platform pays best?" />
          <Card style={{ padding: 0, overflow: 'hidden' }}>
            {platforms.filter(p => p.perHour > 0).sort((a, b) => b.perHour - a.perHour).map((p, i, arr) => (
              <View key={p.platform} style={[s.qRow, i < arr.length - 1 && s.qBorder]}>
                <View style={{ flex: 1 }}>
                  <Text style={s.qLabel}>{p.platform}</Text>
                  <Text style={s.qDates}>{fmtPerMile(p.perMile)} · {fmtHours(p.hours)}</Text>
                </View>
                <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6 }}>
                  {i === 0 && arr.length > 1 ? <Feather name="award" size={15} color={colors.green} /> : null}
                  <Text style={[s.qProfit, i === 0 && { color: colors.green }]}>{fmtPerHour(p.perHour)}</Text>
                </View>
              </View>
            ))}
          </Card>
        </>
      )}

      {/* MTD quarterly updates */}
      <SectionHeader icon="calendar" title="Making Tax Digital — quarterly updates" />
      <Card style={{ padding: 0, overflow: 'hidden' }}>
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

      {/* Year-end checklist */}
      <SectionHeader icon="check-square" title="Year-end checklist" />
      <Card style={{ gap: 10 }}>
        {[
          'Register for Self Assessment if you haven\'t (deadline 5 Oct after your first tax year)',
          'File online and pay by 31 January',
          'Second payment on account due 31 July',
          'Keep records for at least 5 years after the 31 Jan deadline',
          'MTD for Income Tax applies if your income is over £50,000 (quarterly updates)',
        ].map((item, i) => (
          <View key={i} style={s.checkItem}>
            <Feather name="check-circle" size={16} color={colors.brand} />
            <Text style={s.checkText}>{item}</Text>
          </View>
        ))}
      </Card>

      {/* Export — send everything to your accountant */}
      <SectionHeader icon="send" title="Send to your accountant" />
      <Pressable onPress={() => router.push('/export')} style={({ pressed }) => [s.exportCard, pressed && { opacity: 0.9 }]}>
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
    </ScrollView>
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

  methodRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  methodName: { ...type.bodyMedium, fontSize: 16 },
  methodSub: { ...type.caption, marginTop: 2 },
  methodValue: { ...tabular, fontSize: 22, fontWeight: font.bold, color: colors.brandDeep, letterSpacing: -0.5, flexShrink: 1, maxWidth: '55%', textAlign: 'right' },
  compareCta: { flexDirection: 'row', alignItems: 'center', gap: 8, backgroundColor: colors.brandLight, borderRadius: radius.md, padding: spacing.md },
  compareCtaText: { ...type.caption, color: colors.brandDeep, flex: 1, fontWeight: font.medium },
  inputLabel: { ...type.caption, color: colors.textSecondary, marginBottom: 8 },
  input: { borderWidth: 1.5, borderColor: colors.border, borderRadius: radius.md, padding: spacing.md, fontSize: 17, color: colors.textPrimary, backgroundColor: colors.bg },

  row: { flexDirection: 'row', justifyContent: 'space-between', paddingVertical: 9, borderBottomWidth: 1, borderBottomColor: colors.border },
  rowLabel: { fontSize: 15, color: colors.textSecondary, flex: 1, paddingRight: spacing.md },
  rowValue: { ...tabular, fontSize: 15, fontWeight: font.medium, color: colors.textPrimary, textAlign: 'right' },
  smallNote: { ...type.small, marginTop: 10, lineHeight: 17 },
  poaBox: { flexDirection: 'row', gap: 8, marginTop: 12, alignItems: 'flex-start' },
  poaText: { ...type.caption, color: colors.textSecondary, flex: 1, lineHeight: 19 },

  checkItem: { flexDirection: 'row', gap: 10, alignItems: 'flex-start' },
  checkText: { ...type.caption, color: colors.textSecondary, flex: 1, lineHeight: 20 },

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

  exportCard: { flexDirection: 'row', alignItems: 'center', gap: 14, backgroundColor: colors.brand, borderRadius: radius.lg, padding: spacing.lg },
  exportIcon: { width: 42, height: 42, borderRadius: 21, backgroundColor: 'rgba(255,255,255,0.22)', alignItems: 'center', justifyContent: 'center' },
  exportCardTitle: { color: '#fff', fontSize: 16, fontWeight: font.bold },
  exportCardSub: { color: 'rgba(255,255,255,0.85)', fontSize: 12, marginTop: 2 },

  disclaimer: { marginTop: spacing.xl, padding: spacing.lg, backgroundColor: colors.bgSoft, borderRadius: radius.md, flexDirection: 'row', gap: 8, alignItems: 'flex-start' },
  disclaimerText: { ...type.small, lineHeight: 18, flex: 1 },
});
