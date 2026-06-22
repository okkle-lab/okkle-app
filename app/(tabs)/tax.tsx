import React, { useCallback } from 'react';
import { View, Text, ScrollView, StyleSheet, TextInput, Share, Pressable } from 'react-native';
import { useFocusEffect, useRouter } from 'expo-router';
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
import { shareAccountantPack } from '../../src/accountantPack';

export default function TaxScreen() {
  const router = useRouter();
  const [year, setYear] = React.useState(getTaxYearSummary());
  const [bizMiles, setBizMiles] = React.useState(0);
  const [otherExpenses, setOtherExpenses] = React.useState(0);
  const [methodInputs, setMethodInputs] = React.useState({ personalMiles: 0, runningCosts: 0, vehicleValue: 0 });
  const [otherIncome, setOtherIncome] = React.useState(String(kvGetNum('other_income') || ''));
  const user = getUser();

  function reload() {
    setYear(getTaxYearSummary());
    setBizMiles(getTaxYearMiles());
    setOtherExpenses(getTaxYearExpenses());
    setMethodInputs({
      personalMiles: kvGetNum('personal_miles'),
      runningCosts: kvGetNum('running_costs'),
      vehicleValue: kvGetNum('vehicle_value'),
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
    simplifiedDeduction: year.deduction,
  });

  const chosenDeduction = usingActual && method.recommended === 'actual' ? method.actual : method.simplified;
  const totalExpenses = chosenDeduction + otherExpenses;
  const pos = taxPosition(year.earnings, totalExpenses, region, parseFloat(otherIncome) || 0);

  const grossPerMile = bizMiles > 0 ? year.earnings / bizMiles : 0;
  const [packBusy, setPackBusy] = React.useState(false);

  async function makePack() {
    setPackBusy(true);
    try { await shareAccountantPack(); }
    catch { /* user cancelled or sharing unavailable */ }
    setPackBusy(false);
  }

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

      {/* Mileage method — clean summary, comparison lives in its own tool */}
      <SectionHeader title="Mileage method" />
      <Card style={{ gap: spacing.md }}>
        <View style={s.methodRow}>
          <View>
            <Text style={s.methodName}>
              {usingActual && method.recommended === 'actual' ? 'Actual costs' : 'Simplified (flat rate)'}
            </Text>
            <Text style={s.methodSub}>{fmtMiles(bizMiles)} business miles this year</Text>
          </View>
          <Text style={s.methodValue}>{fmtGbp(chosenDeduction)}</Text>
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
      <SectionHeader title="Self Assessment summary" />
      <Card>
        <Row label="Turnover (income)" value={fmtGbp(pos.turnover)} />
        <Row label="Allowable expenses" value={fmtGbp(pos.expenses)} />
        <Row label="Net profit" value={fmtGbp(pos.profit)} bold />
        {pos.usesTradingAllowance && (
          <Text style={s.smallNote}>Using the £1,000 trading allowance (more than your expenses).</Text>
        )}
      </Card>

      {/* Other income — for marginal-rate accuracy */}
      <SectionHeader title="Other income (for accuracy)" />
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
      <SectionHeader title="Send to your accountant" />
      <Pressable onPress={makePack} disabled={packBusy} style={({ pressed }) => [s.packBtn, pressed && { opacity: 0.9 }]}>
        <Feather name="file-text" size={22} color="#fff" />
        <View style={{ flex: 1 }}>
          <Text style={s.packTitle}>{packBusy ? 'Preparing…' : 'Accountant Pack (PDF)'}</Text>
          <Text style={s.packSub}>SA summary, mileage log, expenses & receipts in one file</Text>
        </View>
        <Feather name="share" size={18} color="#fff" />
      </Pressable>

      <Card style={{ gap: spacing.md, marginTop: spacing.md }}>
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

  methodRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  methodName: { ...type.bodyMedium, fontSize: 16 },
  methodSub: { ...type.caption, marginTop: 2 },
  methodValue: { fontSize: 22, fontWeight: font.bold, color: colors.brandDeep, letterSpacing: -0.5 },
  compareCta: { flexDirection: 'row', alignItems: 'center', gap: 8, backgroundColor: colors.brandLight, borderRadius: radius.md, padding: spacing.md },
  compareCtaText: { ...type.caption, color: colors.brandDeep, flex: 1, fontWeight: font.medium },
  inputLabel: { ...type.caption, color: colors.textSecondary, marginBottom: 8 },
  input: { borderWidth: 1.5, borderColor: colors.border, borderRadius: radius.md, padding: spacing.md, fontSize: 17, color: colors.textPrimary, backgroundColor: colors.bg },

  row: { flexDirection: 'row', justifyContent: 'space-between', paddingVertical: 9, borderBottomWidth: 1, borderBottomColor: colors.border },
  rowLabel: { fontSize: 15, color: colors.textSecondary },
  rowValue: { fontSize: 15, fontWeight: font.medium, color: colors.textPrimary },
  smallNote: { ...type.small, marginTop: 10, lineHeight: 17 },
  poaBox: { flexDirection: 'row', gap: 8, marginTop: 12, alignItems: 'flex-start' },
  poaText: { ...type.caption, color: colors.textSecondary, flex: 1, lineHeight: 19 },

  checkItem: { flexDirection: 'row', gap: 10, alignItems: 'flex-start' },
  checkText: { ...type.caption, color: colors.textSecondary, flex: 1, lineHeight: 20 },

  packBtn: { flexDirection: 'row', alignItems: 'center', gap: 14, backgroundColor: colors.brand, borderRadius: radius.lg, padding: spacing.lg },
  packTitle: { color: '#fff', fontSize: 16, fontWeight: font.bold },
  packSub: { color: 'rgba(255,255,255,0.85)', fontSize: 12, marginTop: 2 },
  exportBtn: { flexDirection: 'row', alignItems: 'center', gap: 12, paddingVertical: 4 },
  exportText: { ...type.bodyMedium, fontSize: 15, flex: 1 },

  disclaimer: { marginTop: spacing.xl, padding: spacing.lg, backgroundColor: colors.bgSoft, borderRadius: radius.md, flexDirection: 'row', gap: 8, alignItems: 'flex-start' },
  disclaimerText: { ...type.small, lineHeight: 18, flex: 1 },
});
