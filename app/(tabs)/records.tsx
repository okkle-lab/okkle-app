import React, { useCallback } from 'react';
import { View, Text, ScrollView, StyleSheet, RefreshControl, Pressable, Alert } from 'react-native';
import { useFocusEffect, useRouter } from 'expo-router';
import { Feather } from '@expo/vector-icons';
import { colors, font, spacing, radius, type, tabular } from '../../src/theme';
import { Card, SectionHeader, VehicleIcon, ScreenHeader, IconBadge } from '../../src/components';
import { getTrips, getRecords, getVehicleStats, type VehicleStat } from '../../src/db';
import { fmtGbp, fmtMiles, vehicleLabel } from '../../src/db/tax';
import type { Trip, Record as OkkleRecord } from '../../src/db';

type Item = { kind: 'trip'; data: Trip } | { kind: 'record'; data: OkkleRecord };


export default function RecordsScreen() {
  const router = useRouter();
  const [items, setItems] = React.useState<Item[]>([]);
  const [vehicles, setVehicles] = React.useState<VehicleStat[]>([]);
  const [refreshing, setRefreshing] = React.useState(false);
  const [filter, setFilter] = React.useState<'all' | 'trips' | 'income' | 'expense'>('all');
  const [month, setMonth] = React.useState<string>('all'); // 'all' or 'YYYY-MM'

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
    setVehicles(getVehicleStats());
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
      c = { id: `t${t.id}`, edit: () => openEdit('trip', t.id), icon: 'navigation', tone: 'mint', title: t.platform, source: 'GPS', meta: `${fmtMiles(t.miles)} · ${fmtDate(t.started_at)}`, amount: fmtGbp(t.deduction), amountColor: colors.brandDeep, amountSub: t.earnings ? `${fmtGbp(t.earnings)} earned` : null };
    } else {
      const r = item.data;
      if (r.record_type === 'mileage') {
        c = { id: `r${r.id}`, edit: () => openEdit('record', r.id), icon: 'map', tone: 'neutral', title: r.platform ?? 'Mileage', source: 'Manual', meta: `${fmtMiles(r.miles ?? 0)} · ${fmtDate(r.created_at)}`, amount: fmtGbp(r.deduction ?? 0), amountColor: colors.brandDeep, amountSub: null };
      } else if (r.record_type === 'income') {
        c = { id: `r${r.id}`, edit: () => openEdit('record', r.id), icon: 'dollar-sign', tone: 'green', title: r.platform ?? 'Earnings', source: null, meta: `Earnings · ${fmtDate(r.created_at)}`, amount: fmtGbp(r.amount ?? 0), amountColor: colors.textPrimary, amountSub: null };
      } else {
        c = { id: `r${r.id}`, edit: () => openEdit('record', r.id), icon: 'file-text', tone: 'amber', title: r.category ?? r.notes ?? 'Expense', source: null, meta: fmtDate(r.created_at), amount: fmtGbp(r.amount ?? 0), amountColor: colors.textPrimary, amountSub: null };
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

  return (
    <ScrollView
      style={s.screen}
      contentContainerStyle={s.content}
      refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={colors.brand} />}
    >
      <ScreenHeader title="Records" />

      {vehicles.length > 0 && (
        <View style={{ marginBottom: spacing.xl }}>
          <SectionHeader icon="truck" title="By vehicle" />
          <Card style={{ padding: 0, overflow: 'hidden' }}>
            {vehicles.map((v, i) => (
              <View key={v.vehicle} style={[row.container, i < vehicles.length - 1 && row.border]}>
                <VehicleIcon vehicle={v.vehicle} size={22} color={colors.textSecondary} />
                <View style={row.mid}>
                  <Text style={row.title}>{vehicleLabel(v.vehicle)}</Text>
                  <Text style={[row.sub, { marginTop: 2 }]}>{v.trips} {v.trips === 1 ? 'trip' : 'trips'} · {fmtMiles(v.miles)}</Text>
                </View>
                <Text style={[row.amount, { color: colors.brandDeep }]}>{fmtGbp(v.deduction)}</Text>
              </View>
            ))}
          </Card>
        </View>
      )}

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
              <Pressable onPress={pickMonth} style={s.monthBtn} hitSlop={6}>
                <Feather name="calendar" size={14} color={colors.brandDeep} />
                <Text style={s.monthBtnText} numberOfLines={1}>{month === 'all' ? 'All time' : monthLabel(month)}</Text>
                <Feather name="chevron-down" size={14} color={colors.brandDeep} />
              </Pressable>
            )}
          </View>
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
    </ScrollView>
  );
}

function fmtDate(iso: string): string {
  return new Date(iso).toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short' });
}

const s = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  content: { padding: spacing.xl, paddingTop: 60, paddingBottom: 40 },
  heading: { ...type.screenTitle, marginBottom: spacing.lg },
  hint: { ...type.small, textAlign: 'center', marginTop: spacing.md },
  filterBar: { flexDirection: 'row', alignItems: 'center', gap: 8, marginBottom: spacing.md },
  segment: { flexDirection: 'row', flex: 1, backgroundColor: colors.bgSoft, borderRadius: radius.md, padding: 3 },
  segItem: { flex: 1, paddingVertical: 7, alignItems: 'center', borderRadius: radius.sm },
  segItemOn: { backgroundColor: colors.bgCard, shadowColor: '#000', shadowOpacity: 0.06, shadowRadius: 4, shadowOffset: { width: 0, height: 1 }, elevation: 1 },
  segText: { fontSize: 12.5, fontWeight: font.medium, color: colors.textSecondary },
  segTextOn: { color: colors.textPrimary, fontWeight: font.semibold },
  monthBtn: { flexDirection: 'row', alignItems: 'center', gap: 3, paddingHorizontal: 10, paddingVertical: 8, borderRadius: radius.md, backgroundColor: colors.brandLight },
  monthBtnText: { fontSize: 12.5, fontWeight: font.semibold, color: colors.brandDeep, maxWidth: 72 },
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
  amountSub: { ...tabular, fontSize: 11, color: colors.green, marginTop: 2 },
});
