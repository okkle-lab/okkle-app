import React from 'react';
import { View, Text, ScrollView, StyleSheet, Pressable } from 'react-native';
import { useRouter } from 'expo-router';
import { Feather } from '@expo/vector-icons';
import { colors, font, spacing, radius, type } from '../src/theme';
import { Card, IconBadge } from '../src/components';
import {
  getTaxYearSummary, getTaxYearMiles, getTaxYearExpenses, getTrips, getRecords, getUser,
} from '../src/db';
import { fmtGbp, fmtMiles, taxYearLabel, vehicleLabel } from '../src/db/tax';
import { compareMethods, taxPosition, caRate } from '../src/db/taxcalc';
import { kvGet, kvGetNum } from '../src/db';
import { shareAccountantPack } from '../src/accountantPack';
import { shareTextExport } from '../src/exportFile';

export default function ExportScreen() {
  const router = useRouter();
  const [packBusy, setPackBusy] = React.useState(false);

  const year = getTaxYearSummary();
  const bizMiles = getTaxYearMiles();
  const user = getUser();
  const method = compareMethods({
    businessMiles: bizMiles,
    personalMiles: kvGetNum('personal_miles'),
    runningCosts: kvGetNum('running_costs'),
    vehicleValue: kvGetNum('vehicle_value'),
    capitalAllowanceRate: caRate(kvGet('ca_basis') || 'low'),
    simplifiedDeduction: year.deduction,
  });
  const usingActual = kvGetNum('running_costs') > 0 && method.recommended === 'actual';
  const chosenDeduction = usingActual ? method.actual : method.simplified;
  const pos = taxPosition(year.earnings, chosenDeduction + getTaxYearExpenses(), user?.region ?? 'ruk', kvGetNum('other_income'));

  async function makePack() {
    setPackBusy(true);
    try { await shareAccountantPack(); } catch { /* cancelled */ }
    setPackBusy(false);
  }
  function shareSA() {
    const lines = [
      `Okkle — Self Assessment summary ${taxYearLabel()}`, ``,
      `Turnover (income):        ${fmtGbp(pos.turnover)}`,
      `Allowable expenses:       ${fmtGbp(pos.expenses)}`,
      `Net profit:               ${fmtGbp(pos.profit)}`, ``,
      `Estimated Income Tax:     ${fmtGbp(pos.incomeTax)}`,
      `Estimated Class 4 NIC:    ${fmtGbp(pos.class4)}`,
      `Estimated total due:      ${fmtGbp(pos.totalDue)}`,
      pos.paymentOnAccount > 0 ? `Payment on account (x2):  ${fmtGbp(pos.paymentOnAccount)} each` : ``, ``,
      `Business miles: ${fmtMiles(bizMiles)}`, ``,
      `— Estimates only, not tax advice. Confirm with your accountant.`,
    ].filter(Boolean);
    shareTextExport('SelfAssessment-Summary', 'txt', lines.join('\n'));
  }
  function shareMileageLog() {
    const trips = getTrips(500);
    const header = 'Date,Vehicle,Platform (purpose),Miles,Basis,Deduction (GBP)';
    const rows = trips.slice().sort((a, b) => a.started_at.localeCompare(b.started_at)).map(t =>
      `${t.started_at.slice(0, 10)},${vehicleLabel(t.vehicle)},${t.platform} delivery,${t.miles.toFixed(1)},GPS-measured (HMRC simplified),${t.deduction.toFixed(2)}`);
    shareTextExport('HMRC-Mileage-Log', 'csv', [header, ...rows].join('\n'));
  }
  function shareFreeAgentCsv() {
    const uk = (iso: string) => { const d = iso.slice(0, 10).split('-'); return `${d[2]}/${d[1]}/${d[0]}`; };
    const csvSafe = (s: string) => /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
    const lines: { date: string; amount: number; desc: string }[] = [];
    for (const t of getTrips(1000)) if (t.earnings && t.earnings > 0) lines.push({ date: t.started_at, amount: t.earnings, desc: `${t.platform} earnings` });
    for (const r of getRecords(1000)) {
      if (r.record_type === 'income' && r.amount) lines.push({ date: r.created_at, amount: r.amount, desc: `${r.platform ?? 'Platform'} earnings` });
      if (r.record_type === 'expense' && r.amount) lines.push({ date: r.created_at, amount: -Math.abs(r.amount), desc: r.category ?? r.notes ?? 'Expense' });
    }
    lines.sort((a, b) => a.date.localeCompare(b.date));
    const rows = lines.map(l => `${uk(l.date)},${l.amount.toFixed(2)},${csvSafe(l.desc)}`);
    shareTextExport('FreeAgent-Import', 'csv', ['Date,Amount,Description', ...rows].join('\n'));
  }
  function shareCsv() {
    const trips = getTrips(500); const records = getRecords(500);
    const header = 'date,type,platform,vehicle,miles,deduction,earnings,amount,notes';
    const tr = trips.map(t => `${t.started_at.slice(0,10)},trip,${t.platform},${t.vehicle},${t.miles.toFixed(2)},${t.deduction.toFixed(2)},${t.earnings ?? ''},,`);
    const rr = records.map(r => `${r.created_at.slice(0,10)},${r.record_type},${r.platform ?? ''},,,${r.deduction ?? ''},,${r.amount ?? ''},${r.notes ?? ''}`);
    shareTextExport('All-Data', 'csv', [header, ...tr, ...rr].join('\n'));
  }

  return (
    <View style={s.screen}>
      <ScrollView contentContainerStyle={s.content}>
        <View style={s.header}>
          <Pressable onPress={() => router.back()} hitSlop={12}><Feather name="chevron-left" size={26} color={colors.textPrimary} /></Pressable>
          <Text style={s.title}>Export &amp; share</Text>
          <View style={{ width: 26 }} />
        </View>
        <Text style={s.sub}>Everything your accountant needs, {taxYearLabel()}.</Text>

        <Pressable onPress={makePack} disabled={packBusy} style={({ pressed }) => [s.packBtn, pressed && { opacity: 0.9 }]}>
          <Feather name="file-text" size={22} color="#fff" />
          <View style={{ flex: 1 }}>
            <Text style={s.packTitle}>{packBusy ? 'Preparing…' : 'Accountant Pack (PDF)'}</Text>
            <Text style={s.packSub}>SA summary, mileage log, expenses &amp; receipts in one file</Text>
          </View>
          <Feather name="share" size={18} color="#fff" />
        </Pressable>

        <Card style={{ gap: spacing.md, marginTop: spacing.md }}>
          <Row icon="upload-cloud" tone="mint" title="FreeAgent bank-import CSV" subtitle="Income & expenses only — skip rows that already arrive via your bank feed" onPress={shareFreeAgentCsv} />
          <Row icon="file-text" tone="mint" title="Self Assessment summary" onPress={shareSA} />
          <Row icon="map" tone="green" title="HMRC mileage log (CSV)" subtitle="Mileage claims only — keep these out of the bank-import file" onPress={shareMileageLog} />
          <Row icon="database" tone="neutral" title="All data (CSV)" onPress={shareCsv} />
        </Card>

        <View style={s.disclaimer}>
          <Feather name="shield" size={14} color={colors.textTertiary} />
          <Text style={s.disclaimerText}>Generated on-device. Nothing leaves your phone except what you choose to share.</Text>
        </View>
      </ScrollView>
    </View>
  );
}

function Row({ icon, tone, title, subtitle, onPress }: { icon: any; tone: any; title: string; subtitle?: string; onPress: () => void }) {
  return (
    <Pressable onPress={onPress} style={s.exportBtn}>
      <IconBadge icon={icon} tone={tone} size={34} />
      <View style={{ flex: 1 }}>
        <Text style={s.exportText}>{title}</Text>
        {subtitle ? <Text style={s.exportSub}>{subtitle}</Text> : null}
      </View>
      <Feather name="share" size={16} color={colors.textTertiary} />
    </Pressable>
  );
}

const s = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  content: { padding: spacing.xl, paddingTop: 60, paddingBottom: 40 },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginBottom: 6 },
  title: { ...type.screenTitle },
  sub: { ...type.body, color: colors.textSecondary, marginBottom: spacing.xl },
  packBtn: { flexDirection: 'row', alignItems: 'center', gap: 14, backgroundColor: colors.brand, borderRadius: radius.lg, padding: spacing.lg },
  packTitle: { color: '#fff', fontSize: 16, fontWeight: font.bold },
  packSub: { color: 'rgba(255,255,255,0.85)', fontSize: 12, marginTop: 2 },
  exportBtn: { flexDirection: 'row', alignItems: 'center', gap: 12, paddingVertical: 4 },
  exportText: { ...type.bodyMedium, fontSize: 15 },
  exportSub: { ...type.caption, marginTop: 1 },
  disclaimer: { marginTop: spacing.xl, padding: spacing.lg, backgroundColor: colors.bgSoft, borderRadius: radius.md, flexDirection: 'row', gap: 8, alignItems: 'flex-start' },
  disclaimerText: { ...type.small, lineHeight: 18, flex: 1 },
});
