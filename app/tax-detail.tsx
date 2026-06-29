import React, { useCallback } from 'react';
import { View, Text, ScrollView, StyleSheet, Pressable, Alert, Linking } from 'react-native';
import { useFocusEffect, useLocalSearchParams, useRouter } from 'expo-router';
import Feather from '@expo/vector-icons/Feather';
import { colors, font, spacing, radius, type, tabular } from '../src/theme';
import { Card, SectionHeader, ModalHeader } from '../src/components';
import { addDeadlineToCalendar } from '../src/calendar';
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

const MTD_INFO = 'Making Tax Digital (MTD) for Income Tax is HMRC’s new way of reporting. It’s mandatory if your self-employment income is over £50,000 (from April 2026) or over £30,000 (from April 2027) — you submit four digital updates a year through compatible software. Below the threshold you still file the usual annual Self Assessment.';
const HMRC_INFO = 'The key dates for filing your own Self Assessment:\n\n• Register for Self Assessment by 5 October after your first year of self-employment.\n• File your online return and pay any tax due by 31 January.\n• If HMRC asks you for payments on account, the second instalment is due 31 July.\n\nEach date shows the next time it falls due.';

const BILL_INFO = 'A breakdown of what you’ll owe on your courier profit:\n\n• Income Tax — tax on your profit above the £12,570 personal allowance.\n• Class 4 NIC — National Insurance for the self-employed: 6% of profit between £12,570 and £50,270, then 2% above.\n• Effective rate — your total tax + NIC as a share of your income (usually lower than your headline tax band).\n• Payments on account — if your bill is over £1,000, HMRC asks you to pre-pay next year’s tax in two instalments (31 Jan and 31 Jul).\n\nAll estimates — confirm with your accountant.';

const YEAR_INFO = 'Your Self Assessment figures for the year:\n\n• Turnover — your total income (all the pay you’ve logged).\n• Allowable expenses — what you can deduct, including your simplified mileage.\n• Net profit — turnover minus expenses; this is what you’re taxed on.\n• Trading allowance — instead of expenses you can deduct a flat £1,000; Okkle uses whichever is higher.';

// Real HMRC Self Assessment deadlines (month is 1-12).
const KEY_DEADLINES: { title: string; month: number; day: number; note: string }[] = [
  { title: 'Register for Self Assessment', month: 10, day: 5, note: 'Only if this was your first year self-employed.' },
  { title: 'File your return & pay your tax', month: 1, day: 31, note: 'Online Self Assessment deadline for the previous tax year.' },
  { title: 'Second payment on account', month: 7, day: 31, note: 'Only if HMRC asked you for payments on account.' },
];
function nextOccurrence(month: number, day: number): Date {
  const now = new Date();
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  let d = new Date(now.getFullYear(), month - 1, day);
  if (d < today) d = new Date(now.getFullYear() + 1, month - 1, day);
  return d;
}

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

  function showCalendarResult(res: 'added' | 'denied' | 'error', successMsg: string) {
    if (res === 'added') {
      Alert.alert('Added to your calendar', successMsg);
    } else if (res === 'denied') {
      Alert.alert(
        'Allow calendar access',
        'Tap Open Settings, then turn on Calendars to add this deadline.',
        [{ text: 'Not now', style: 'cancel' }, { text: 'Open Settings', onPress: () => Linking.openSettings() }],
      );
    } else {
      Alert.alert(
        'Couldn’t add it',
        'Check calendar access in Settings, then try again. If it keeps happening, send a problem report from Settings.',
        [{ text: 'Not now', style: 'cancel' }, { text: 'Open Settings', onPress: () => Linking.openSettings() }],
      );
    }
  }

  async function addMtdReminder(label: string, deadlineISO: string, deadlineLabel: string) {
    const when = new Date(`${deadlineISO}T09:00:00`);
    const res = await addDeadlineToCalendar(`MTD: ${label} quarterly update`, when, 'Submit your Making Tax Digital quarterly update to HMRC.');
    showCalendarResult(res, `${label} update — due ${deadlineLabel}, with a reminder a week before.`);
  }

  async function addHmrcReminder(title: string, when: Date, note: string) {
    const res = await addDeadlineToCalendar(`HMRC: ${title}`, when, note);
    showCalendarResult(res, `${title} — ${when.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' })}, with a reminder a week before.`);
  }

  return (
    <View style={s.screen}>
      <ScrollView contentContainerStyle={s.content}>
        <ModalHeader title={TITLES[which]} />

        {which === 'bill' && (
          <>
            <View style={s.headRow}>
              <Feather name="percent" size={13} color={colors.brand} />
              <Text style={s.headTitle}>Income tax & National Insurance</Text>
              <Pressable onPress={() => Alert.alert('Your estimated bill', BILL_INFO)} hitSlop={8}>
                <Feather name="help-circle" size={17} color={colors.textTertiary} />
              </Pressable>
            </View>
            <Card style={{ marginBottom: spacing.lg }}>
              <Row label="Income Tax" value={fmtGbp(pos.incomeTax)} />
              <Row label="Class 4 NIC" value={fmtGbp(pos.class4)} />
              <Row label="Total estimated due" value={fmtGbp(pos.totalDue)} bold accent />
              <Row label="Effective rate" value={fmtPct(pos.effectiveRate)} last />
            </Card>
            {otherIncome > 0 && (
              <Text style={s.note}>Includes {fmtGbp(otherIncome)} of other income (e.g. a PAYE job): your courier profit is taxed on top of it at the marginal rate. That employment income is taxed separately through your payslip.</Text>
            )}
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
            <Card style={{ padding: spacing.lg, marginBottom: spacing.lg }}>
              <View style={s.flow}>
                <Cell value={fmtMiles(year.miles)} label="miles tracked" />
                <Feather name="chevron-right" size={16} color={colors.textTertiary} />
                <Cell value={fmtGbp(year.deduction)} label="deduction" />
                <Feather name="chevron-right" size={16} color={colors.textTertiary} />
                <Cell value={fmtGbp(year.taxSaved)} label="tax saved" accent />
              </View>
              <Text style={s.cardNote}>The HMRC mileage rate turns your miles into an allowable deduction; at your ~{Math.round((year.taxRate ?? 0.2) * 100)}% tax + NIC band that deduction is money you don’t pay.</Text>
            </Card>

            <SectionHeader icon="navigation" title="Mileage method" />
            <Card style={{ gap: spacing.md, marginBottom: spacing.lg }}>
              <View style={s.methodRow}>
                <View style={{ flex: 1, paddingRight: spacing.md }}>
                  <Text style={s.methodName}>{usingActual && method.recommended === 'actual' ? 'Actual costs' : 'Simplified (flat rate)'}</Text>
                  <Text style={s.rowSub}>{fmtMiles(bizMiles)} business miles this year</Text>
                </View>
                <Text style={s.methodValue}>{fmtGbp(chosenDeduction)}</Text>
              </View>
              <Text style={s.cardNote}>Okkle uses HMRC’s simplified flat-rate mileage — the easiest method and the best fit for most couriers. If you think actual vehicle costs might save more, ask your accountant.</Text>
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
                  <Text style={s.cardNote}>{bizMiles < 10000 ? `${fmtMiles(10000 - bizMiles)} left before your rate drops at 10,000 miles.` : 'Past 10,000 miles — extra car/van miles are claimed at the lower rate.'}</Text>
                </Card>
              </>
            )}
          </>
        )}

        {which === 'year' && (
          <>
            <View style={s.headRow}>
              <Feather name="bar-chart-2" size={13} color={colors.brand} />
              <Text style={s.headTitle}>Self Assessment summary</Text>
              <Pressable onPress={() => Alert.alert('This year', YEAR_INFO)} hitSlop={8}>
                <Feather name="help-circle" size={17} color={colors.textTertiary} />
              </Pressable>
            </View>
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
            <View style={s.headRow}>
              <Feather name="calendar" size={13} color={colors.brand} />
              <Text style={s.headTitle}>Making Tax Digital — quarterly updates</Text>
              <Pressable onPress={() => Alert.alert('Making Tax Digital', MTD_INFO)} hitSlop={8}>
                <Feather name="help-circle" size={17} color={colors.textTertiary} />
              </Pressable>
            </View>
            <Card style={{ padding: 0, overflow: 'hidden', marginBottom: spacing.lg }}>
              {quarters.map((q, i) => (
                <View key={q.label} style={[s.qRow, i < quarters.length - 1 && s.rowBorder]}>
                  <View style={{ flex: 1 }}>
                    <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
                      <Text style={s.qLabel}>{q.label}</Text>
                      {q.isCurrent && <View style={s.qNowTag}><Text style={s.qNowText}>now</Text></View>}
                    </View>
                    <Text style={s.qDates}>due {q.deadline} · {fmtGbp(q.profit)} profit</Text>
                  </View>
                  <Pressable onPress={() => addMtdReminder(q.label, q.deadlineISO, q.deadline)} style={s.calBtn} hitSlop={6}>
                    <Feather name="calendar" size={14} color={colors.brandDeep} />
                    <Text style={s.calBtnText}>Add</Text>
                  </Pressable>
                </View>
              ))}
            </Card>

            <View style={s.headRow}>
              <Feather name="flag" size={13} color={colors.brand} />
              <Text style={s.headTitle}>HMRC Self Assessment dates</Text>
              <Pressable onPress={() => Alert.alert('Self Assessment dates', HMRC_INFO)} hitSlop={8}>
                <Feather name="help-circle" size={17} color={colors.textTertiary} />
              </Pressable>
            </View>
            <Card style={{ padding: 0, overflow: 'hidden' }}>
              {KEY_DEADLINES.map((d, i) => {
                const next = nextOccurrence(d.month, d.day);
                return (
                  <View key={d.title} style={[s.qRow, i < KEY_DEADLINES.length - 1 && s.rowBorder]}>
                    <View style={{ flex: 1, paddingRight: spacing.md }}>
                      <Text style={s.qLabel}>{d.title}</Text>
                      <Text style={s.qDates}>{next.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' })}</Text>
                    </View>
                    <Pressable onPress={() => addHmrcReminder(d.title, next, d.note)} style={s.calBtn} hitSlop={6}>
                      <Feather name="calendar" size={14} color={colors.brandDeep} />
                      <Text style={s.calBtnText}>Add</Text>
                    </Pressable>
                  </View>
                );
              })}
            </Card>
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
  // A note that sits as the last element inside a Card — no bottom margin, so the
  // card's own padding provides the spacing (keeps the vertical rhythm even).
  cardNote: { ...type.small, lineHeight: 17, marginTop: spacing.sm },
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
  headRow: { flexDirection: 'row', alignItems: 'center', gap: 6, marginBottom: 10, marginTop: 4 },
  headTitle: { flex: 1, fontSize: 13, fontWeight: font.semibold, color: colors.textSecondary, letterSpacing: 0.3 },
  calBtn: { flexDirection: 'row', alignItems: 'center', gap: 5, paddingHorizontal: 12, paddingVertical: 8, borderRadius: radius.full, backgroundColor: colors.brandLight },
  calBtnText: { ...type.caption, color: colors.brandDeep, fontWeight: font.semibold },

  linkRow: { flexDirection: 'row', alignItems: 'center', gap: 10, paddingVertical: spacing.sm, marginBottom: spacing.sm },
  linkIcon: { width: 30, height: 30, borderRadius: 15, alignItems: 'center', justifyContent: 'center', backgroundColor: colors.brandLight },
  linkText: { ...type.bodyMedium, fontSize: 15, color: colors.textPrimary, flex: 1 },
  foot: { ...type.small, color: colors.textTertiary, lineHeight: 17, marginTop: spacing.lg },
});
