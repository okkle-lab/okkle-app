import React, { useCallback } from 'react';
import { View, Text, StyleSheet, Pressable } from 'react-native';
import { useFocusEffect, useRouter } from 'expo-router';
import { Feather } from '@expo/vector-icons';
import { colors, font, spacing, radius, type, tabular } from '../theme';
import { GlassPanel } from './GlassPanel';
import {
  getTaxYearSummary, getTaxYearMiles, getTaxYearExpenses,
  getUser, getQuarterlySummaries, kvGet, kvGetNum, type QuarterSummary,
} from '../db';
import { fmtGbp, fmtMiles, taxYearLabel } from '../db/tax';
import { compareMethods, taxPosition, caRate } from '../db/taxcalc';
import { upcomingDeadline } from '../taxDeadlines';

// Tax summary: a calm hero number + a few glanceable cards. The heavy detail
// (bill breakdown, SA summary, deadlines) lives one tap deeper on /tax-detail,
// so this screen reads like the rest of the app instead of one long scroll.
export function TaxPanel() {
  const router = useRouter();
  const [year, setYear] = React.useState(getTaxYearSummary());
  const [bizMiles, setBizMiles] = React.useState(0);
  const [otherExpenses, setOtherExpenses] = React.useState(0);
  const [quarters, setQuarters] = React.useState<QuarterSummary[]>([]);
  const [methodInputs, setMethodInputs] = React.useState({ personalMiles: 0, runningCosts: 0, vehicleValue: 0, caBasis: 'low' });
  const [otherIncome, setOtherIncome] = React.useState(0);
  const [due, setDue] = React.useState(upcomingDeadline(30));
  const user = getUser();

  useFocusEffect(useCallback(() => {
    setYear(getTaxYearSummary());
    setBizMiles(getTaxYearMiles());
    setOtherExpenses(getTaxYearExpenses());
    setQuarters(getQuarterlySummaries());
    setDue(upcomingDeadline(30));
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

  const open = (which: string) => () => router.push({ pathname: '/tax-detail', params: { which } });

  const isCarVan = user?.vehicle === 'car' || user?.vehicle === 'van';
  const showThreshold = isCarVan && bizMiles > 0 && bizMiles < 10000;
  const thresholdPct = Math.min(100, (bizMiles / 10000) * 100);
  const nextQuarter = quarters.find(q => q.isCurrent) ?? quarters[0];

  return (
    <>
      {/* In-app deadline reminder — a safety net for missed notifications */}
      {due && (
        <Pressable onPress={open('deadlines')} style={({ pressed }) => [s.dueBanner, pressed && { opacity: 0.9 }]}>
          <Feather name="bell" size={16} color={colors.amberDark} />
          <Text style={s.dueText}>
            <Text style={{ fontWeight: font.bold }}>{due.title}</Text> — {due.days === 0 ? 'due today' : due.days === 1 ? 'due tomorrow' : `due in ${due.days} days`}
          </Text>
          <Feather name="chevron-right" size={16} color={colors.amberDark} />
        </Pressable>
      )}

      {/* Hero — what to set aside; tap for the full bill breakdown */}
      <Pressable onPress={open('bill')} style={({ pressed }) => pressed && { opacity: 0.94 }}>
        <GlassPanel tone="amber" style={s.hero} contentStyle={s.heroContent}>
          <View style={s.heroIcon}><Feather name="shield" size={20} color={colors.amberDark} /></View>
          <View style={{ flex: 1 }}>
            <Text style={s.heroLabel}>Set aside for tax</Text>
            <Text style={s.heroValue}>{fmtGbp(pos.totalDue)}</Text>
            <Text style={s.heroSub}>You’re covered for {taxYearLabel()} so far · tap for the breakdown</Text>
          </View>
          <Feather name="chevron-right" size={20} color={colors.amberDark} />
        </GlassPanel>
      </Pressable>

      {/* Proactive nudge — the one thing to act on */}
      {showThreshold && (
        <View style={s.nudge}>
          <View style={s.nudgeHead}>
            <Feather name="trending-up" size={16} color={colors.brandDeep} />
            <Text style={s.nudgeText}>{fmtMiles(10000 - bizMiles)} before your rate drops at 10,000 miles</Text>
          </View>
          <View style={s.track}><View style={[s.fill, { width: `${thresholdPct}%` }]} /></View>
        </View>
      )}

      <Text style={s.tapHint}>Tap a card for the detail</Text>
      <View style={s.group}>
        <SummaryRow icon="trending-up" tone="mint" title="Tax saved this year"
          sub={`From ${fmtMiles(year.miles)} of mileage`} value={fmtGbp(year.taxSaved)} valueColor={colors.brandDeep} onPress={open('saved')} />
        <SummaryRow icon="bar-chart-2" tone="blue" title="This year"
          sub="Turnover, expenses & profit" value={fmtGbp(pos.profit)} onPress={open('year')} last />
      </View>

      <Pressable onPress={open('deadlines')} style={({ pressed }) => [s.deadline, pressed && { backgroundColor: colors.bgSoft }]}>
        <View style={s.rowIcon}><Feather name="calendar" size={18} color={colors.textSecondary} /></View>
        <View style={{ flex: 1 }}>
          <Text style={s.rowTitle}>Deadlines</Text>
          <Text style={s.rowSub}>{nextQuarter ? `Next update due ${nextQuarter.deadline}` : 'Self Assessment & MTD dates'}</Text>
        </View>
        <Feather name="chevron-right" size={18} color={colors.textTertiary} />
      </Pressable>

      <Pressable onPress={() => router.push('/export')} style={({ pressed }) => [s.export, pressed && { opacity: 0.92 }]}>
        <Feather name="send" size={18} color="#fff" />
        <Text style={s.exportText}>Share report</Text>
      </Pressable>

      <Text style={s.disclaimer}>
        Estimated from what you’ve logged at current HMRC rates — not tax advice. Your accountant confirms the final figures and files your return.
      </Text>
    </>
  );
}

function SummaryRow({ icon, tone, title, sub, value, valueColor, onPress, last }: {
  icon: any; tone: 'mint' | 'blue'; title: string; sub: string; value: string; valueColor?: string; onPress: () => void; last?: boolean;
}) {
  const bg = tone === 'mint' ? colors.brandLight : '#E0EBFF';
  const fg = tone === 'mint' ? colors.brandDeep : '#1E5BB0';
  return (
    <Pressable onPress={onPress} style={({ pressed }) => [s.row, !last && s.rowBorder, pressed && { backgroundColor: colors.bgSoft }]}>
      <View style={[s.rowIcon, { backgroundColor: bg }]}><Feather name={icon} size={18} color={fg} /></View>
      <View style={{ flex: 1 }}>
        <Text style={s.rowTitle}>{title}</Text>
        <Text style={s.rowSub}>{sub}</Text>
      </View>
      <Text style={[s.rowValue, valueColor ? { color: valueColor } : null]}>{value}</Text>
      <Feather name="chevron-right" size={18} color={colors.textTertiary} style={{ marginLeft: 4 }} />
    </Pressable>
  );
}

const s = StyleSheet.create({
  dueBanner: { flexDirection: 'row', alignItems: 'center', gap: 10, backgroundColor: colors.amberLight, borderRadius: radius.md, paddingVertical: spacing.md, paddingHorizontal: spacing.lg, marginBottom: spacing.md },
  dueText: { ...type.caption, color: colors.amberDark, flex: 1, lineHeight: 18 },
  hero: { marginBottom: spacing.md },
  heroContent: { flexDirection: 'row', alignItems: 'center', gap: 14 },
  heroIcon: { width: 42, height: 42, borderRadius: 21, backgroundColor: colors.amberLight, alignItems: 'center', justifyContent: 'center' },
  heroLabel: { ...type.caption, color: colors.amberDark, fontWeight: font.semibold },
  heroValue: { ...tabular, fontSize: 34, fontWeight: font.bold, color: colors.textPrimary, letterSpacing: -1, marginTop: 1 },
  heroSub: { ...type.small, color: colors.amberDark, marginTop: 2, lineHeight: 16 },

  nudge: { backgroundColor: colors.brandLight, borderRadius: radius.lg, padding: spacing.md, marginBottom: spacing.xl },
  nudgeHead: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  nudgeText: { ...type.caption, color: colors.brandDeep, flex: 1, fontWeight: font.medium },
  track: { height: 6, borderRadius: radius.full, backgroundColor: colors.brandMid, marginTop: 10, overflow: 'hidden' },
  fill: { height: '100%', borderRadius: radius.full, backgroundColor: colors.brandDeep },

  tapHint: { ...type.small, color: colors.textTertiary, marginLeft: spacing.xs, marginBottom: spacing.sm },
  group: { borderWidth: 1, borderColor: colors.border, borderRadius: radius.lg, overflow: 'hidden', marginBottom: spacing.md },
  row: { flexDirection: 'row', alignItems: 'center', gap: 12, padding: spacing.lg },
  rowBorder: { borderBottomWidth: 1, borderBottomColor: colors.border },
  rowIcon: { width: 34, height: 34, borderRadius: 17, backgroundColor: colors.bgSoft, alignItems: 'center', justifyContent: 'center' },
  rowTitle: { ...type.bodyMedium, fontSize: 15 },
  rowSub: { ...type.caption, marginTop: 2 },
  rowValue: { ...tabular, fontSize: 15, fontWeight: font.bold, color: colors.textPrimary },

  deadline: { flexDirection: 'row', alignItems: 'center', gap: 12, padding: spacing.lg, borderWidth: 1, borderColor: colors.border, borderRadius: radius.lg, marginBottom: spacing.lg },

  export: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 8, height: 52, borderRadius: radius.lg, backgroundColor: colors.brandDeep },
  exportText: { color: '#fff', fontSize: 15, fontWeight: font.semibold },
  disclaimer: { ...type.small, color: colors.textTertiary, lineHeight: 17, marginTop: spacing.lg },
});
