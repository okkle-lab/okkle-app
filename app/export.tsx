import React from 'react';
import { View, Text, ScrollView, StyleSheet, Pressable, Alert } from 'react-native';
import Feather from '@expo/vector-icons/Feather';
import { useRouter, useFocusEffect } from 'expo-router';
import { colors, font, spacing, radius, type } from '../src/theme';
import { Card, IconBadge, ModalHeader, SectionHeader } from '../src/components';
import {
  getTaxYearSummary, getTaxYearMiles, getTaxYearExpenses, getTripsForTaxYear, getRecordsForTaxYear, getUser,
} from '../src/db';
import { fmtGbp, fmtMiles, taxYearLabel, vehicleLabel } from '../src/db/tax';
import { compareMethods, taxPosition, caRate } from '../src/db/taxcalc';
import { kvGet, kvGetNum } from '../src/db';
import { shareAccountantPack } from '../src/accountantPack';
import { shareTextExport } from '../src/exportFile';

// Which pack-identity fields the user has filled (edited in Settings → Profile).
function readPackDetails() {
  const has = (k: string) => (kvGet(k) ?? '').trim().length > 0;
  return { utr: has('utr'), ni: has('ni_number'), address: has('address'), business: has('business_desc') };
}

export default function ExportScreen() {
  const router = useRouter();
  const [packBusy, setPackBusy] = React.useState(false);
  // Optional identity for the pack — edited in Settings → Profile, stored on-device.
  // Re-read on focus so completing it in Profile updates this screen.
  const [details, setDetails] = React.useState(() => readPackDetails());
  useFocusEffect(React.useCallback(() => { setDetails(readPackDetails()); }, []));
  const detailItems = [
    { label: 'UTR', done: details.utr },
    { label: 'NI number', done: details.ni },
    { label: 'Address', done: details.address },
    { label: 'Business', done: details.business },
  ];
  const detailCount = detailItems.filter(i => i.done).length;
  const detailsReady = detailCount === detailItems.length;

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

  async function runPack(format: 'pdf' | 'bundle') {
    setPackBusy(true);
    try { await shareAccountantPack(format); } catch { /* cancelled */ }
    setPackBusy(false);
  }
  function makePack() {
    Alert.alert(
      'Share Accountant Pack',
      'Choose how to send it. The bundle adds an importable transactions CSV your accountant can load into their software.',
      [
        { text: 'PDF + data (ZIP)', onPress: () => runPack('bundle') },
        { text: 'PDF only', onPress: () => runPack('pdf') },
        { text: 'Cancel', style: 'cancel' },
      ],
    );
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
    const trips = getTripsForTaxYear();
    const header = 'Date,Vehicle,Platform (purpose),Miles,Basis,Deduction (GBP)';
    const rows = trips.slice().sort((a, b) => a.started_at.localeCompare(b.started_at)).map(t =>
      `${t.started_at.slice(0, 10)},${vehicleLabel(t.vehicle)},${t.platform} delivery,${t.miles.toFixed(1)},GPS-measured (HMRC simplified),${t.deduction.toFixed(2)}`);
    shareTextExport('HMRC-Mileage-Log', 'csv', [header, ...rows].join('\n'));
  }
  function shareFreeAgentCsv() {
    const uk = (iso: string) => { const d = iso.slice(0, 10).split('-'); return `${d[2]}/${d[1]}/${d[0]}`; };
    const csvSafe = (s: string) => /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
    const lines: { date: string; amount: number; desc: string }[] = [];
    for (const t of getTripsForTaxYear()) if (t.earnings && t.earnings > 0) lines.push({ date: t.started_at, amount: t.earnings, desc: `${t.platform} earnings` });
    for (const r of getRecordsForTaxYear()) {
      if (r.record_type === 'income' && r.amount) lines.push({ date: r.created_at, amount: r.amount, desc: `${r.platform ?? 'Platform'} earnings` });
      if (r.record_type === 'expense' && r.amount) lines.push({ date: r.created_at, amount: -Math.abs(r.amount), desc: r.category ?? r.notes ?? 'Expense' });
    }
    lines.sort((a, b) => a.date.localeCompare(b.date));
    const rows = lines.map(l => `${uk(l.date)},${l.amount.toFixed(2)},${csvSafe(l.desc)}`);
    shareTextExport('FreeAgent-Import', 'csv', ['Date,Amount,Description', ...rows].join('\n'));
  }
  function shareCsv() {
    const trips = getTripsForTaxYear(); const records = getRecordsForTaxYear();
    const header = 'date,type,platform,vehicle,miles,deduction,earnings,amount,notes';
    const tr = trips.map(t => `${t.started_at.slice(0,10)},trip,${t.platform},${t.vehicle},${t.miles.toFixed(2)},${t.deduction.toFixed(2)},${t.earnings ?? ''},,`);
    const rr = records.map(r => `${r.created_at.slice(0,10)},${r.record_type},${r.platform ?? ''},,,${r.deduction ?? ''},,${r.amount ?? ''},${r.notes ?? ''}`);
    shareTextExport('All-Data', 'csv', [header, ...tr, ...rr].join('\n'));
  }

  return (
    <View style={s.screen}>
      <ScrollView contentContainerStyle={s.content}>
        <ModalHeader title="Export & share" />
        <Text style={s.sub}>Everything your accountant needs for {taxYearLabel()}, ready to send.</Text>

        <SectionHeader title="ACCOUNTANT PACK" icon="file-text" />
        <Pressable onPress={makePack} disabled={packBusy} style={({ pressed }) => [s.packBtn, pressed && { opacity: 0.9 }]}>
          <View style={s.packIcon}><Feather name="file-text" size={22} color="#fff" /></View>
          <View style={{ flex: 1 }}>
            <Text style={s.packTitle}>{packBusy ? 'Preparing…' : 'Accountant Pack'}</Text>
            <Text style={s.packSub}>Send as a PDF, or bundle it with an importable transactions CSV</Text>
          </View>
          <Feather name="share" size={18} color="#fff" />
        </Pressable>

        {!detailsReady && (
          <Pressable onPress={() => router.push('/settings-account')} style={({ pressed }) => [s.detailsCard, pressed && { opacity: 0.76 }]}>
            <View style={s.detailsIcon}>
              <Feather name="user-plus" size={18} color={colors.brandDeep} />
            </View>
            <View style={{ flex: 1 }}>
              <View style={s.detailsTitleRow}>
                <Text style={s.detailsTitle}>Add your details</Text>
                <View style={s.readyPill}>
                  <Text style={s.readyPillText}>{detailCount}/4</Text>
                </View>
              </View>
              <Text style={s.detailsSub}>
                Your UTR, NI number &amp; address make the pack filing-ready. Add them in Settings → Profile.
              </Text>
            </View>
            <Feather name="chevron-right" size={20} color={colors.textTertiary} />
          </Pressable>
        )}

        <View style={{ marginTop: spacing.xl }}>
          <SectionHeader title="INDIVIDUAL FILES" icon="download" />
        </View>
        <Card style={{ gap: spacing.lg }}>
          <Row icon="upload-cloud" tone="mint" title="FreeAgent bank-import CSV" subtitle="Income & expenses only — skip rows that already arrive via your bank feed" onPress={shareFreeAgentCsv} />
          <Row icon="map" tone="green" title="HMRC mileage log (CSV)" subtitle="Mileage claims only — keep these out of the bank-import file" onPress={shareMileageLog} />
          <Row icon="file-text" tone="mint" title="Self Assessment summary" subtitle="A plain-text overview of your figures for the year" onPress={shareSA} />
          <Row icon="database" tone="neutral" title="All data (CSV)" subtitle="A full backup of every trip and record" onPress={shareCsv} />
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
  packIcon: { width: 40, height: 40, borderRadius: 12, alignItems: 'center', justifyContent: 'center', backgroundColor: 'rgba(255,255,255,0.18)' },
  packTitle: { color: '#fff', fontSize: 16, fontWeight: font.bold },
  packSub: { color: 'rgba(255,255,255,0.85)', fontSize: 12, marginTop: 2 },
  exportBtn: { flexDirection: 'row', alignItems: 'center', gap: 12, paddingVertical: 4 },
  exportText: { ...type.bodyMedium, fontSize: 15 },
  exportSub: { ...type.caption, marginTop: 1 },
  disclaimer: { marginTop: spacing.xl, padding: spacing.lg, backgroundColor: colors.bgSoft, borderRadius: radius.md, flexDirection: 'row', gap: 8, alignItems: 'flex-start' },
  disclaimerText: { ...type.small, lineHeight: 18, flex: 1 },
  detailsCard: { flexDirection: 'row', alignItems: 'flex-start', gap: 12, padding: spacing.lg, marginTop: spacing.md, borderRadius: radius.lg, backgroundColor: colors.bgSoft, borderWidth: 1, borderColor: colors.border },
  detailsIcon: { width: 38, height: 38, borderRadius: 19, alignItems: 'center', justifyContent: 'center', backgroundColor: colors.brandLight },
  detailsTitleRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.sm },
  detailsTitle: { ...type.bodyMedium, fontSize: 16, flex: 1 },
  detailsSub: { ...type.caption, marginTop: 3, lineHeight: 18 },
  readyPill: { paddingHorizontal: 9, paddingVertical: 4, borderRadius: radius.full, backgroundColor: colors.bgCard, borderWidth: 1, borderColor: colors.border },
  readyPillOn: { backgroundColor: colors.brandDeep, borderColor: colors.brandDeep },
  readyPillText: { fontSize: 11, fontWeight: font.bold, color: colors.textSecondary },
  readyPillTextOn: { color: '#fff' },
  detailChecklist: { flexDirection: 'row', flexWrap: 'wrap', gap: 7, marginTop: spacing.md },
  detailCheck: { flexDirection: 'row', alignItems: 'center', gap: 4, paddingHorizontal: 8, paddingVertical: 5, borderRadius: radius.full, backgroundColor: colors.bgCard },
  detailCheckText: { fontSize: 11.5, fontWeight: font.medium, color: colors.textTertiary },
  detailCheckTextOn: { color: colors.brandDeep },
  detailsForm: { gap: spacing.md, marginTop: spacing.sm },
  formIntro: { ...type.caption, color: colors.textSecondary, lineHeight: 18 },
  detailsNoteBox: { flexDirection: 'row', alignItems: 'flex-start', gap: 8, padding: spacing.md, borderRadius: radius.md, backgroundColor: colors.brandLight },
  detailsNote: { ...type.small, color: colors.brandDeep, lineHeight: 17, flex: 1 },
  fieldLabel: { ...type.label, marginBottom: 6 },
  fieldInput: { minHeight: 48, borderWidth: 1.5, borderColor: colors.border, borderRadius: radius.md, padding: spacing.md, fontSize: 16, color: colors.textPrimary, backgroundColor: colors.bg },
  fieldInputMultiline: { minHeight: 88, paddingTop: spacing.md },
});
