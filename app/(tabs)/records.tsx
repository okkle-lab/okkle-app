import React, { useCallback } from 'react';
import { View, Text, StyleSheet, RefreshControl, Pressable, Alert } from 'react-native';
import { useFocusEffect, useLocalSearchParams, useRouter } from 'expo-router';
import { Feather } from '@expo/vector-icons';
import { colors, font, spacing, radius, type, tabular } from '../../src/theme';
import { Card, CollapsingHeader, IconBadge, KeyboardDoneAccessory, SettingsGlassButton } from '../../src/components';
import { getTrips, getRecords } from '../../src/db';
import { fmtGbp, fmtMiles, vehicleLabel } from '../../src/db/tax';
import type { Trip, Record as OkkleRecord } from '../../src/db';
import { TaxPanel } from '../../src/components/TaxPanel';

type Item = { kind: 'trip'; data: Trip } | { kind: 'record'; data: OkkleRecord };
type RecordsMode = 'records' | 'tax';


export default function RecordsScreen() {
  const router = useRouter();
  const params = useLocalSearchParams<{ view?: string }>();
  const [items, setItems] = React.useState<Item[]>([]);
  const [refreshing, setRefreshing] = React.useState(false);
  const [filter, setFilter] = React.useState<'all' | 'trips' | 'income' | 'expense'>('all');
  const [month, setMonth] = React.useState<string>('all'); // 'all' or 'YYYY-MM'
  const [mode, setMode] = React.useState<RecordsMode>(params.view === 'tax' ? 'tax' : 'records');

  React.useEffect(() => {
    if (params.view === 'tax') setMode('tax');
    if (params.view === 'records') setMode('records');
  }, [params.view]);

  // Four clear buckets. "Trips" covers driving (GPS + manual mileage) — each row
  // still carries a GPS / Manual tag so you can tell them apart at a glance.
  const FILTERS: { key: typeof filter; label: string }[] = [
    { key: 'all', label: 'All' },
    { key: 'trips', label: 'Trips' },
    { key: 'income', label: 'Earnings' },
    { key: 'expense', label: 'Expenses' },
  ];
  const itemDate = (it: Item) => (it.kind === 'trip' ? it.data.started_at : it.data.created_at).slice(0, 10);
  const months = Array.from(new Set(items.map(it => itemDate(it).slice(0, 7)))).sort().reverse();
  const monthLabel = (m: string) => new Date(m + '-01').toLocaleDateString('en-GB', { month: 'short', year: 'numeric' });

  const visible = items.filter(it => {
    const typeOk =
      filter === 'all' ? true :
      filter === 'trips' ? (it.kind === 'trip' || (it.kind === 'record' && it.data.record_type === 'mileage')) :
      it.kind === 'record' && it.data.record_type === filter;
    const monthOk = month === 'all' ? true : itemDate(it).slice(0, 7) === month;
    return typeOk && monthOk;
  });

  // A single total that reflects the current filter (and month). Records are just
  // records — this is the only number, and it changes with what you're looking at.
  const totals = visible.reduce((a, it) => {
    if (it.kind === 'trip') a.miles += it.data.miles;
    else {
      const r = it.data;
      if (r.record_type === 'mileage') a.miles += r.miles ?? 0;
      else if (r.record_type === 'income') a.income += r.amount ?? 0;
      else a.expense += r.amount ?? 0;
    }
    return a;
  }, { miles: 0, income: 0, expense: 0 });
  const totalView =
    filter === 'trips' ? { label: 'Total distance', value: fmtMiles(totals.miles) } :
    filter === 'income' ? { label: 'Total earnings', value: fmtGbp(totals.income) } :
    filter === 'expense' ? { label: 'Total expenses', value: fmtGbp(totals.expense) } :
    { label: `${visible.length} ${visible.length === 1 ? 'record' : 'records'}`, value: '' };

  function pickMonth() {
    Alert.alert('Show month', undefined, [
      { text: 'All time', onPress: () => setMonth('all') },
      ...months.slice(0, 8).map(m => ({ text: monthLabel(m), onPress: () => setMonth(m) })),
      { text: 'Cancel', style: 'cancel' as const },
    ]);
  }

  function load() {
    const trips = getTrips(50).map(t => ({ kind: 'trip' as const, data: t }));
    const records = getRecords(100).map(r => ({ kind: 'record' as const, data: r }));
    const all = [...trips, ...records].sort((a, b) => {
      const aDate = a.kind === 'trip' ? a.data.started_at : a.data.created_at;
      const bDate = b.kind === 'trip' ? b.data.started_at : b.data.created_at;
      return bDate.localeCompare(aDate);
    });
    setItems(all);
  }

  useFocusEffect(useCallback(() => { load(); }, []));

  function onRefresh() { setRefreshing(true); load(); setRefreshing(false); }

  function openEdit(kind: 'trip' | 'record', id: number) {
    router.push({ pathname: '/edit', params: { kind, id: String(id) } });
  }

  function renderItem(item: Item, i: number, arr: Item[]) {
    const isLast = i === arr.length - 1;
    type Cfg = { id: string; edit: () => void; icon: any; tone: any; title: string; source: 'GPS' | 'Manual' | null; meta: string; amount: string; amountColor: string; amountSub: string | null };
    let c: Cfg;
    if (item.kind === 'trip') {
      const t = item.data;
      c = { id: `t${t.id}`, edit: () => openEdit('trip', t.id), icon: 'navigation', tone: 'mint', title: `Trip · ${vehicleLabel(t.vehicle)}`, source: 'GPS', meta: fmtDate(t.started_at), amount: fmtMiles(t.miles), amountColor: colors.textPrimary, amountSub: `${fmtGbp(t.deduction)} tax` };
    } else {
      const r = item.data;
      const when = fmtWhen(r);
      if (r.record_type === 'mileage') {
        c = { id: `r${r.id}`, edit: () => openEdit('record', r.id), icon: 'map', tone: 'neutral', title: `Mileage · ${vehicleLabel(r.vehicle ?? 'car')}`, source: 'Manual', meta: when, amount: fmtMiles(r.miles ?? 0), amountColor: colors.textPrimary, amountSub: `${fmtGbp(r.deduction ?? 0)} tax` };
      } else if (r.record_type === 'income') {
        c = { id: `r${r.id}`, edit: () => openEdit('record', r.id), icon: 'dollar-sign', tone: 'green', title: r.platform ?? 'Earnings', source: null, meta: `Earnings · ${when}`, amount: fmtGbp(r.amount ?? 0), amountColor: colors.textPrimary, amountSub: null };
      } else {
        c = { id: `r${r.id}`, edit: () => openEdit('record', r.id), icon: 'file-text', tone: 'amber', title: r.category ?? r.notes ?? 'Expense', source: null, meta: when, amount: fmtGbp(r.amount ?? 0), amountColor: colors.textPrimary, amountSub: null };
      }
    }
    return (
      <Pressable key={c.id} onPress={c.edit} style={({ pressed }) => [row.container, !isLast && row.border, pressed && row.pressed]}>
        <IconBadge icon={c.icon} tone={c.tone} size={40} />
        <View style={row.mid}>
          <Text style={row.title} numberOfLines={1}>{c.title}</Text>
          <View style={row.metaRow}>
            {c.source && <Text style={[row.srcTag, c.source === 'GPS' ? row.srcGps : row.srcManual]}>{c.source}</Text>}
            <Text style={row.sub} numberOfLines={1}>{c.meta}</Text>
          </View>
        </View>
        <View style={row.right}>
          <Text style={[row.amount, { color: c.amountColor }]} numberOfLines={1}>{c.amount}</Text>
          {c.amountSub ? <Text style={row.amountSub} numberOfLines={1}>{c.amountSub}</Text> : null}
        </View>
        <Feather name="chevron-right" size={18} color={colors.textTertiary} style={{ marginLeft: 4 }} />
      </Pressable>
    );
  }

  const gear = (
    <SettingsGlassButton onPress={() => router.push('/settings')} />
  );

  function renderModeSwitch() {
    return (
      <View style={s.modeSeg}>
        {([
          ['records', 'History', 'list'] as const,
          ['tax', 'Tax', 'shield'] as const,
        ]).map(([key, label, icon]) => {
          const on = mode === key;
          return (
            <Pressable key={key} onPress={() => setMode(key)} style={[s.modeItem, on && s.modeItemOn]}>
              <Feather name={icon} size={14} color={on ? colors.brandDeep : colors.textSecondary} />
              <Text style={[s.modeText, on && s.modeTextOn]}>{label}</Text>
            </Pressable>
          );
        })}
      </View>
    );
  }

  function renderRecordsList() {
    return (
      <>
      {items.length === 0 ? (
        <Card>
          <Text style={{ color: colors.textSecondary, textAlign: 'center', paddingVertical: 8 }}>
            No records yet — start a trip or log an entry
          </Text>
        </Card>
      ) : (
        <>
          <View style={s.filterBar}>
            <View style={s.segment}>
              {FILTERS.map(f => (
                <Pressable key={f.key} onPress={() => setFilter(f.key)} style={[s.segItem, filter === f.key && s.segItemOn]}>
                  <Text style={[s.segText, filter === f.key && s.segTextOn]} numberOfLines={1}>{f.label}</Text>
                </Pressable>
              ))}
            </View>
            {months.length > 1 && (
              <Pressable onPress={pickMonth} style={[s.monthBtn, month !== 'all' && s.monthBtnOn]} hitSlop={6}>
                <Feather name="calendar" size={15} color={month !== 'all' ? '#fff' : colors.brandDeep} />
                {month !== 'all' && <Text style={s.monthBtnText} numberOfLines={1}>{monthLabel(month)}</Text>}
              </Pressable>
            )}
          </View>
          {totalView.value ? (
            <View style={s.totalRow}>
              <Text style={s.totalLabel}>{totalView.label}</Text>
              <Text style={s.totalValue}>{totalView.value}</Text>
            </View>
          ) : (
            <Text style={s.totalCount}>{totalView.label}</Text>
          )}
          {visible.length === 0 ? (
            <Card><Text style={{ color: colors.textSecondary, textAlign: 'center', paddingVertical: 8 }}>Nothing here yet.</Text></Card>
          ) : (
            <Card style={{ padding: 0, overflow: 'hidden' }}>
              {visible.map((item, i, arr) => renderItem(item, i, arr))}
            </Card>
          )}
          <Text style={s.hint}>Tap any entry to edit or delete it.</Text>
        </>
      )}
      </>
    );
  }

  return (
    <View style={s.screen}>
      <CollapsingHeader
        title="Records"
        subtitle="Your logs, tax estimate and exports in one place."
        right={gear}
        refreshControl={mode === 'records' ? <RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={colors.brand} /> : undefined}
        keyboardShouldPersistTaps="handled"
      >
        {renderModeSwitch()}
        {mode === 'tax' ? <TaxPanel /> : renderRecordsList()}
      </CollapsingHeader>
      <KeyboardDoneAccessory />
    </View>
  );
}

function fmtDate(iso: string): string {
  return new Date(iso).toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short' });
}

// Weekly entries show their Mon–Sun range; single-day entries show the date.
function fmtWhen(r: OkkleRecord): string {
  if (r.period_start && r.period_end) {
    const f = (s: string) => new Date(s).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' });
    return `Week of ${f(r.period_start)}–${f(r.period_end)}`;
  }
  return fmtDate(r.created_at);
}

const s = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  modeSeg: { flexDirection: 'row', backgroundColor: colors.bgSoft, borderRadius: radius.lg, padding: 4, marginBottom: spacing.lg },
  modeItem: { flex: 1, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 6, paddingVertical: 10, borderRadius: radius.md },
  modeItemOn: { backgroundColor: colors.bgCard, shadowColor: '#000', shadowOpacity: 0.06, shadowRadius: 4, shadowOffset: { width: 0, height: 1 }, elevation: 1 },
  modeText: { fontSize: 14, fontWeight: font.medium, color: colors.textSecondary },
  modeTextOn: { color: colors.textPrimary, fontWeight: font.semibold },
  hint: { ...type.small, textAlign: 'center', marginTop: spacing.md },
  filterBar: { flexDirection: 'row', alignItems: 'center', gap: 8, marginBottom: spacing.md },
  segment: { flexDirection: 'row', flex: 1, backgroundColor: colors.bgSoft, borderRadius: radius.md, padding: 3 },
  segItem: { flex: 1, paddingVertical: 7, paddingHorizontal: 2, alignItems: 'center', justifyContent: 'center', borderRadius: radius.sm },
  segItemOn: { backgroundColor: colors.bgCard, shadowColor: '#000', shadowOpacity: 0.06, shadowRadius: 4, shadowOffset: { width: 0, height: 1 }, elevation: 1 },
  segText: { fontSize: 12, fontWeight: font.medium, color: colors.textSecondary },
  segTextOn: { color: colors.textPrimary, fontWeight: font.semibold },
  monthBtn: { flexDirection: 'row', alignItems: 'center', gap: 4, paddingHorizontal: 11, height: 36, borderRadius: radius.md, backgroundColor: colors.brandLight },
  monthBtnOn: { backgroundColor: colors.brandDeep },
  monthBtnText: { fontSize: 12.5, fontWeight: font.semibold, color: '#fff', maxWidth: 72 },
  totalRow: { flexDirection: 'row', alignItems: 'baseline', justifyContent: 'space-between', paddingHorizontal: spacing.xs, marginBottom: spacing.md },
  totalLabel: { ...type.label, color: colors.textSecondary },
  totalValue: { ...tabular, fontSize: 24, fontWeight: font.bold, color: colors.textPrimary, letterSpacing: -0.5 },
  totalCount: { ...type.caption, color: colors.textSecondary, marginBottom: spacing.md, paddingHorizontal: spacing.xs },
});

const row = StyleSheet.create({
  container: { flexDirection: 'row', alignItems: 'center', padding: spacing.lg, gap: spacing.md },
  border: { borderBottomWidth: 1, borderBottomColor: colors.border },
  pressed: { backgroundColor: colors.bgSoft },
  mid: { flex: 1 },
  title: { fontSize: 15, fontWeight: font.semibold, color: colors.textPrimary },
  metaRow: { flexDirection: 'row', alignItems: 'center', gap: 6, marginTop: 3 },
  srcTag: { fontSize: 10, fontWeight: font.bold, paddingHorizontal: 6, paddingVertical: 1, borderRadius: radius.sm, overflow: 'hidden', letterSpacing: 0.2 },
  srcGps: { backgroundColor: colors.brandLight, color: colors.brandDeep },
  srcManual: { backgroundColor: colors.bgSoft, color: colors.textSecondary },
  sub: { fontSize: 13, color: colors.textSecondary, flexShrink: 1 },
  right: { alignItems: 'flex-end', marginLeft: 8, maxWidth: 120 },
  amount: { ...tabular, fontSize: 15, fontWeight: font.bold, color: colors.textPrimary },
  amountSub: { ...tabular, fontSize: 11, color: colors.textTertiary, marginTop: 2 },
});
