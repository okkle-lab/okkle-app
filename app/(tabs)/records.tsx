import React, { useCallback } from 'react';
import { View, Text, ScrollView, StyleSheet, RefreshControl } from 'react-native';
import { useFocusEffect } from 'expo-router';
import { colors, font, spacing, radius, type } from '../../src/theme';
import { Card } from '../../src/components';
import { getTrips, getRecords } from '../../src/db';
import { fmtGbp, fmtMiles, vehicleEmoji } from '../../src/db/tax';
import type { Trip, Record as OkkleRecord } from '../../src/db';

type Item = { kind: 'trip'; data: Trip } | { kind: 'record'; data: OkkleRecord };

const TYPE_STYLE: { [key: string]: { bg: string; text: string; label: string } } = {
  mileage: { bg: colors.brandLight, text: colors.brandDeep, label: 'Miles' },
  income: { bg: colors.greenLight, text: colors.green, label: 'Income' },
  expense: { bg: colors.amberLight, text: colors.amber, label: 'Expense' },
  trip: { bg: colors.brandLight, text: colors.brandDeep, label: 'GPS trip' },
};

export default function RecordsScreen() {
  const [items, setItems] = React.useState<Item[]>([]);
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
  }

  useFocusEffect(useCallback(() => { load(); }, []));

  function onRefresh() { setRefreshing(true); load(); setRefreshing(false); }

  function renderItem(item: Item, i: number, arr: Item[]) {
    const isLast = i === arr.length - 1;
    if (item.kind === 'trip') {
      const t = item.data;
      const style = TYPE_STYLE.trip;
      return (
        <View key={`t${t.id}`} style={[row.container, !isLast && row.border]}>
          <View style={[row.badge, { backgroundColor: style.bg }]}>
            <Text style={[row.badgeText, { color: style.text }]}>{style.label}</Text>
          </View>
          <View style={row.mid}>
            <Text style={row.title}>{t.platform}</Text>
            <Text style={row.sub}>{vehicleEmoji(t.vehicle)} {fmtMiles(t.miles)} · {fmtDate(t.started_at)}</Text>
          </View>
          <View style={row.right}>
            <Text style={[row.amount, { color: colors.brand }]}>{fmtGbp(t.deduction)}</Text>
            {t.earnings ? <Text style={row.amountSub}>{fmtGbp(t.earnings)} earned</Text> : null}
          </View>
        </View>
      );
    }
    const r = item.data;
    const style = TYPE_STYLE[r.record_type] ?? TYPE_STYLE.expense;
    return (
      <View key={`r${r.id}`} style={[row.container, !isLast && row.border]}>
        <View style={[row.badge, { backgroundColor: style.bg }]}>
          <Text style={[row.badgeText, { color: style.text }]}>{style.label}</Text>
        </View>
        <View style={row.mid}>
          <Text style={row.title}>{r.platform ?? r.category ?? r.record_type}</Text>
          <Text style={row.sub}>{fmtDate(r.created_at)}</Text>
        </View>
        <View style={row.right}>
          <Text style={row.amount}>
            {r.record_type === 'mileage' ? fmtGbp(r.deduction ?? 0) : fmtGbp(r.amount ?? 0)}
          </Text>
          {r.record_type === 'mileage' && r.miles ? (
            <Text style={row.amountSub}>{fmtMiles(r.miles)}</Text>
          ) : null}
        </View>
      </View>
    );
  }

  return (
    <ScrollView
      style={s.screen}
      contentContainerStyle={s.content}
      refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={colors.brand} />}
    >
      <Text style={s.heading}>Records</Text>
      {items.length === 0 ? (
        <Card>
          <Text style={{ color: colors.textSecondary, textAlign: 'center', paddingVertical: 8 }}>
            No records yet — start a trip or log an entry
          </Text>
        </Card>
      ) : (
        <Card style={{ padding: 0, overflow: 'hidden' }}>
          {items.map((item, i, arr) => renderItem(item, i, arr))}
        </Card>
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
});

const row = StyleSheet.create({
  container: { flexDirection: 'row', alignItems: 'center', padding: spacing.lg, gap: spacing.md },
  border: { borderBottomWidth: 1, borderBottomColor: colors.border },
  badge: { paddingHorizontal: 10, paddingVertical: 5, borderRadius: radius.sm },
  badgeText: { fontSize: 12, fontWeight: font.semibold },
  mid: { flex: 1 },
  title: { fontSize: 15, fontWeight: font.medium, color: colors.textPrimary },
  sub: { fontSize: 13, color: colors.textSecondary, marginTop: 2 },
  right: { alignItems: 'flex-end' },
  amount: { fontSize: 15, fontWeight: font.semibold, color: colors.textPrimary },
  amountSub: { fontSize: 12, color: colors.textSecondary, marginTop: 2 },
});
