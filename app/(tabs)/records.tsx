import React, { useCallback } from 'react';
import { View, Text, ScrollView, StyleSheet, RefreshControl, Pressable } from 'react-native';
import { useFocusEffect, useRouter } from 'expo-router';
import { Feather } from '@expo/vector-icons';
import { colors, font, spacing, radius, type, tabular } from '../../src/theme';
import { Card, SectionHeader, VehicleIcon } from '../../src/components';
import { getTrips, getRecords, getVehicleStats, type VehicleStat } from '../../src/db';
import { fmtGbp, fmtMiles, vehicleLabel } from '../../src/db/tax';
import type { Trip, Record as OkkleRecord } from '../../src/db';

type Item = { kind: 'trip'; data: Trip } | { kind: 'record'; data: OkkleRecord };

const TYPE_STYLE: { [key: string]: { bg: string; text: string; label: string } } = {
  mileage: { bg: colors.brandLight, text: colors.brandDeep, label: 'Miles' },
  income: { bg: colors.greenLight, text: colors.green, label: 'Income' },
  expense: { bg: colors.amberLight, text: colors.amber, label: 'Expense' },
  trip: { bg: colors.brandLight, text: colors.brandDeep, label: 'GPS trip' },
};

export default function RecordsScreen() {
  const router = useRouter();
  const [items, setItems] = React.useState<Item[]>([]);
  const [vehicles, setVehicles] = React.useState<VehicleStat[]>([]);
  const [refreshing, setRefreshing] = React.useState(false);

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
    if (item.kind === 'trip') {
      const t = item.data;
      const style = TYPE_STYLE.trip;
      return (
        <Pressable key={`t${t.id}`} onPress={() => openEdit('trip', t.id)} style={({ pressed }) => [row.container, !isLast && row.border, pressed && row.pressed]}>
          <View style={[row.badge, { backgroundColor: style.bg }]}>
            <Text style={[row.badgeText, { color: style.text }]}>{style.label}</Text>
          </View>
          <View style={row.mid}>
            <Text style={row.title}>{t.platform}</Text>
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 5, marginTop: 2 }}>
              <VehicleIcon vehicle={t.vehicle} size={13} color={colors.textTertiary} />
              <Text style={row.sub}>{fmtMiles(t.miles)} · {fmtDate(t.started_at)}</Text>
            </View>
          </View>
          <View style={row.right}>
            <Text style={[row.amount, { color: colors.brandDeep }]}>{fmtGbp(t.deduction)}</Text>
            {t.earnings ? <Text style={row.amountSub}>{fmtGbp(t.earnings)} earned</Text> : null}
          </View>
          <Feather name="chevron-right" size={18} color={colors.textTertiary} style={{ marginLeft: 6 }} />
        </Pressable>
      );
    }
    const r = item.data;
    const style = TYPE_STYLE[r.record_type] ?? TYPE_STYLE.expense;
    return (
      <Pressable key={`r${r.id}`} onPress={() => openEdit('record', r.id)} style={({ pressed }) => [row.container, !isLast && row.border, pressed && row.pressed]}>
        <View style={[row.badge, { backgroundColor: style.bg }]}>
          <Text style={[row.badgeText, { color: style.text }]}>{style.label}</Text>
        </View>
        <View style={row.mid}>
          <Text style={row.title}>{r.platform ?? r.category ?? r.record_type}</Text>
          <Text style={[row.sub, { marginTop: 2 }]}>{fmtDate(r.created_at)}</Text>
        </View>
        <View style={row.right}>
          <Text style={row.amount}>
            {r.record_type === 'mileage' ? fmtGbp(r.deduction ?? 0) : fmtGbp(r.amount ?? 0)}
          </Text>
          {r.record_type === 'mileage' && r.miles ? (
            <Text style={row.amountSub}>{fmtMiles(r.miles)}</Text>
          ) : null}
        </View>
        <Feather name="chevron-right" size={18} color={colors.textTertiary} style={{ marginLeft: 6 }} />
      </Pressable>
    );
  }

  return (
    <ScrollView
      style={s.screen}
      contentContainerStyle={s.content}
      refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={colors.brand} />}
    >
      <Text style={s.heading}>Records</Text>

      {vehicles.length > 0 && (
        <View style={{ marginBottom: spacing.xl }}>
          <SectionHeader title="By vehicle" />
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
          <SectionHeader title="All entries" />
          <Card style={{ padding: 0, overflow: 'hidden' }}>
            {items.map((item, i, arr) => renderItem(item, i, arr))}
          </Card>
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
});

const row = StyleSheet.create({
  container: { flexDirection: 'row', alignItems: 'center', padding: spacing.lg, gap: spacing.md },
  border: { borderBottomWidth: 1, borderBottomColor: colors.border },
  pressed: { backgroundColor: colors.bgSoft },
  badge: { paddingHorizontal: 10, paddingVertical: 5, borderRadius: radius.sm },
  badgeText: { fontSize: 12, fontWeight: font.semibold },
  mid: { flex: 1 },
  title: { fontSize: 15, fontWeight: font.medium, color: colors.textPrimary },
  sub: { fontSize: 13, color: colors.textSecondary, marginTop: 2 },
  right: { alignItems: 'flex-end' },
  amount: { ...tabular, fontSize: 15, fontWeight: font.semibold, color: colors.textPrimary },
  amountSub: { ...tabular, fontSize: 12, color: colors.textSecondary, marginTop: 2 },
});
