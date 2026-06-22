import React, { useCallback } from 'react';
import { View, Text, ScrollView, StyleSheet, TextInput, Share, Pressable } from 'react-native';
import { useFocusEffect } from 'expo-router';
import { Feather } from '@expo/vector-icons';
import { colors, font, spacing, radius, type } from '../../src/theme';
import { Card, SectionHeader, PrimaryButton } from '../../src/components';
import {
  getTaxYearSummary, getTaxYearMiles, getTaxYearExpenses, getTrips, getRecords,
  getUser, kvGetNum, kvSet,
} from '../../src/db';
import { fmtGbp, fmtMiles, taxYearLabel, vehicleLabel } from '../../src/db/tax';
import {
  compareMethods, taxPosition, class2Note, PERSONAL_ALLOWANCE,
} from '../../src/db/taxcalc';

export default function TaxScreen() {
  const [year, setYear] = React.useState(getTaxYearSummary());
  const [bizMiles, setBizMiles] = React.useState(0);
  const [otherExpenses, setOtherExpenses] = React.useState(0);
  const user = getUser();

  // Actual-cost inputs (persisted).
  const [personalMiles, setPersonalMiles] = React.useState(String(kvGetNum('personal_miles')));
  const [runningCosts, setRunningCosts] = React.useState(String(kvGetNum('running_costs')));
  const [vehicleValue, setVehicleValue] = React.useState(String(kvGetNum('vehicle_value')));

  function reload() {
    setYear(getTaxYearSummary());
    setBizMiles(getTaxYearMiles());
    setOtherExpenses(getTaxYearExpenses());
  }
  useFocusEffect(useCallback(() => { reload(); }, []));

  const region = user?.region ?? 'ruk';

  const method = compareMethods({
    businessMiles: bizMiles,
    personalMiles: parseFloat(personalMiles) || 0,
    runningCosts: parseFloat(runningCosts) || 0,
    vehicleValue: parseFloat(vehicleValue) || 0,
    simplifiedDeduction: year.deduction,
  });

  const chosenDeduction = method.recommended === 'actual' ? method.actual : method.simplified;
  const totalExpenses = chosenDeduction + otherExpenses;
  const pos = taxPosition(year.earnings, totalExpenses, region);

  const grossPerMile = bizMiles > 0 ? year.earnings / bizMiles : 0;

  function persist(key: string, val: string) { kvSet(key, parseFloat(val) || 0); }

  // --- exports --------------------------------------------------------------
  function shareSA() {
    const lines = [
      `Okkle — Self Assessment summary ${taxYearLabel()}`,
      ``,
      `Turnover (income):        ${fmtGbp(pos.turnover)}`,
      `Allowable expenses:       ${fmtGbp(pos.expenses)}`,
      `Net profit:               ${fmtGbp(pos.profit)}`,
      ``,
      `Estimated Income Tax:     ${fmtGbp(pos.incomeTax)}`,
      `Estimated Class 4 NIC:    ${fmtGbp(pos.class4)}`,
      `Estimated total due:      ${fmtGbp(pos.totalDue)}`,
      pos.paymentOnAccount > 0 ? `Payment on account (x2):  ${fmtGbp(pos.paymentOnAccount)} each` : ``,
      ``,
      `Mileage method: ${method.recommended}`,
      `Business miles: ${fmtMiles(bizMiles)}`,
      ``,
      `— Estimates only, not tax advice. Confirm with your accountant.`,
    ].filter(Boolean);
    Share.share({ message: lines.join('\n'), title: `Okkle SA summary ${taxYearLabel()}` });
  }

  function shareMileageLog() {
    const trips = getTrips(500);
    const header = 'Date,Vehicle,Platform (purpose),Miles,Rate note,Deduction (GBP)';
    const rows = trips.slice().sort((a, b) => a.started_at.localeCompare(b.started_at)).map(t =>
      `${t.started_at.slice(0, 10)},${vehicleLabel(t.vehicle)},${t.platform} delivery,${t.miles.toFixed(1)},HMRC simplified,${t.deduction.toFixed(2)}`);
    Share.share({ message: [header, ...rows].join('\n'), title: `Okkle mileage log ${taxYearLabel()}.csv` });
  }

  function shareCsv() {
    const trips = getTrips(500); const records = getRecords(500);
    const header = 'date,type,platform,vehicle,miles,deduction,earnings,amount,notes';
    const tr = trips.map(t => `${t.started_at.slice(0,10)},trip,${t.platform},${t.vehicle},${t.miles.toFixed(2)},${t.deduction.toFixed(2)},${t.earnings ?? ''},,`);
    const rr = records.map(r => `${r.created_at.slice(0,10)},${r.record_type},${r.platform ?? ''},,,${r.deduction ?? ''},,${r.amount ?? ''},${r.notes ?? ''}`);
    Share.share({ message: [header, ...tr, ...rr].join('\n'), title: `Okkle data ${taxYearLabel()}.csv` });
  }

  return (
    <ScrollView style={s.screen} contentContainerStyle={s.content}>
      <Text style={s.heading}>Tax</Text>
      <Text style={s.sub}>Your estimated position for {taxYearLabel()}</Text>

      {/* KILLER FEATURE: method comparison */}
      <SectionHeader title="Mileage method — which saves more?" />
      <Card style={{ gap: spacing.md }}>
        <View style={s.compareRow}>
          <View style={[s.compareBox, method.recommended === 'simplified' && s.compareWin]}>
            <Text style={s.compareLabel}>Simplified</Text>
            <Text style={s.compareValue}>{fmtGbp(method.simplified)}</Text>
            <Text style={s.compareNote}>45p/25p flat rate</Text>
          </View>
          <View style={[s.compareBox, method.recommended === 'actual' && s.compareWin]}>
            <Text style={s.compareLabel}>Actual costs</Text>
            <Text style={s.compareValue}>{fmtGbp(method.actual)}</Text>
            <Text style={s.compareNote}>{(method.businessUsePct * 100).toFixed(0)}% business use</Text>
          </View>
        </View>

        {(parseFloat(runningCosts) > 0 || parseFloat(vehicleValue) > 0) && (
          <View style={s.recommendBanner}>
            <Feather name="award" size={16} color={colors.brandDeep} />
            <Text style={s.recommendText}>
              {method.recommended === 'actual'
                ? `Actual costs could save you ${fmtGbp(method.difference)} more in deductions.`
                : `Simplified is better for you by ${fmtGbp(method.difference)}.`}
            </Text>
          </View>
        )}

        <Text style={s.inputLabel}>Total personal (non-work) miles this year</Text>
        <TextInput style={s.input} value={personalMiles} onChangeText={setPersonalMiles} onBlur={() => persist('personal_miles', personalMiles)} keyboardType="decimal-pad" placeholder="0" placeholderTextColor={colors.textTertiary} />

        <Text style={s.inputLabel}>Annual running costs (fuel, insurance, repairs…)</Text>
        <TextInput style={s.input} value={runningCosts} onChangeText={setRunningCosts} onBlur={() => persist('running_costs', runningCosts)} keyboardType="decimal-pad" placeholder="£0" placeholderTextColor={colors.textTertiary} />

        <Text style={s.inputLabel}>Vehicle value (for capital allowances)</Text>
        <TextInput style={s.input} value={vehicleValue} onChangeText={setVehicleValue} onBlur={() => persist('vehicle_value', vehicleValue)} keyboardType="decimal-pad" placeholder="£0" placeholderTextColor={colors.textTertiary} />

        <View style={s.warnBox}>
          <Feather name="alert-triangle" size={15} color={colors.amber} />
          <Text style={s.warnText}>
            You usually must stick with one method per vehicle. Once you claim actual costs and capital allowances on a vehicle, you can't switch back to simplified for it. Choose with your accountant.
          </Text>
        </View>
      </Card>

      {/* Self Assessment summary */}
      <SectionHeader title="Self Assessment summary" />
      <Card>
        <Row label="Turnover (income)" value={fmtGbp(pos.turnover)} />
        <Row label="Allowable expenses" value={fmtGbp(pos.expenses)} />
        <Row label="Net profit" value={fmtGbp(pos.profit)} bold />
        {pos.usesTradingAllowance && (
          <Text style={s.smallNote}>Using the £1,000 trading allowance (more than your expenses).</Text>
        )}
      </Card>

      {/* Tax & NIC */}
      <SectionHeader title="Estimated tax & National Insurance" />
      <Card>
        <Row label="Income Tax" value={fmtGbp(pos.incomeTax)} />
        <Row label="Class 4 NIC" value={fmtGbp(pos.class4)} />
        <Row label="Total estimated due" value={fmtGbp(pos.totalDue)} bold accent />
        <Row label="Effective rate" value={`${(pos.effectiveRate * 100).toFixed(1)}%`} />
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

      {/* Insights */}
      <SectionHeader title="Insights" />
      <Card>
        <Row label="Gross earnings per mile" value={`£${grossPerMile.toFixed(2)}`} />
        <Row label="Personal allowance left" value={fmtGbp(Math.max(0, PERSONAL_ALLOWANCE - pos.profit))} />
        <Row label="Profit after tax" value={fmtGbp(pos.profit - pos.totalDue)} bold />
      </Card>

      {/* Year-end checklist */}
      <SectionHeader title="Year-end checklist" />
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

      {/* Export */}
      <SectionHeader title="Export for your accountant" />
      <Card style={{ gap: spacing.md }}>
        <Pressable onPress={shareSA} style={s.exportBtn}>
          <Feather name="file-text" size={18} color={colors.textPrimary} />
          <Text style={s.exportText}>Self Assessment summary</Text>
          <Feather name="share" size={16} color={colors.textTertiary} />
        </Pressable>
        <Pressable onPress={shareMileageLog} style={s.exportBtn}>
          <Feather name="map" size={18} color={colors.textPrimary} />
          <Text style={s.exportText}>HMRC mileage log</Text>
          <Feather name="share" size={16} color={colors.textTertiary} />
        </Pressable>
        <Pressable onPress={shareCsv} style={s.exportBtn}>
          <Feather name="database" size={18} color={colors.textPrimary} />
          <Text style={s.exportText}>All data (CSV)</Text>
          <Feather name="share" size={16} color={colors.textTertiary} />
        </Pressable>
      </Card>

      <View style={s.disclaimer}>
        <Feather name="shield" size={14} color={colors.textTertiary} />
        <Text style={s.disclaimerText}>
          Estimates based on 2025/26 rates and what you've logged — not tax advice. Your accountant confirms the final figures and files your return.
        </Text>
      </View>
    </ScrollView>
  );
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

  compareRow: { flexDirection: 'row', gap: spacing.md },
  compareBox: { flex: 1, borderWidth: 1.5, borderColor: colors.border, borderRadius: radius.md, padding: spacing.lg, alignItems: 'center' },
  compareWin: { borderColor: colors.brand, backgroundColor: colors.brandLight },
  compareLabel: { ...type.label, marginBottom: 4 },
  compareValue: { fontSize: 22, fontWeight: font.bold, color: colors.textPrimary, letterSpacing: -0.5 },
  compareNote: { ...type.small, marginTop: 2 },
  recommendBanner: { flexDirection: 'row', alignItems: 'center', gap: 8, backgroundColor: colors.brandLight, borderRadius: radius.md, padding: spacing.md },
  recommendText: { ...type.caption, color: colors.brandDeep, flex: 1, fontWeight: font.medium },
  inputLabel: { ...type.caption, color: colors.textSecondary, marginTop: 4 },
  input: { borderWidth: 1.5, borderColor: colors.border, borderRadius: radius.md, padding: spacing.md, fontSize: 17, color: colors.textPrimary, backgroundColor: colors.bg },
  warnBox: { flexDirection: 'row', gap: 8, backgroundColor: colors.amberLight, borderRadius: radius.md, padding: spacing.md, marginTop: 4 },
  warnText: { ...type.caption, color: colors.amber, flex: 1, lineHeight: 19 },

  row: { flexDirection: 'row', justifyContent: 'space-between', paddingVertical: 9, borderBottomWidth: 1, borderBottomColor: colors.border },
  rowLabel: { fontSize: 15, color: colors.textSecondary },
  rowValue: { fontSize: 15, fontWeight: font.medium, color: colors.textPrimary },
  smallNote: { ...type.small, marginTop: 10, lineHeight: 17 },
  poaBox: { flexDirection: 'row', gap: 8, marginTop: 12, alignItems: 'flex-start' },
  poaText: { ...type.caption, color: colors.textSecondary, flex: 1, lineHeight: 19 },

  checkItem: { flexDirection: 'row', gap: 10, alignItems: 'flex-start' },
  checkText: { ...type.caption, color: colors.textSecondary, flex: 1, lineHeight: 20 },

  exportBtn: { flexDirection: 'row', alignItems: 'center', gap: 12, paddingVertical: 4 },
  exportText: { ...type.bodyMedium, fontSize: 15, flex: 1 },

  disclaimer: { marginTop: spacing.xl, padding: spacing.lg, backgroundColor: colors.bgSoft, borderRadius: radius.md, flexDirection: 'row', gap: 8, alignItems: 'flex-start' },
  disclaimerText: { ...type.small, lineHeight: 18, flex: 1 },
});
