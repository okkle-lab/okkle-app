import React, { useCallback } from 'react';
import { View, Text, ScrollView, StyleSheet, RefreshControl } from 'react-native';
import { useFocusEffect } from 'expo-router';
import { colors, font, spacing, radius, type } from '../../src/theme';
import { MetricCard, Card, SectionHeader } from '../../src/components';
import { getWeeklySummary, getTrips, getUser } from '../../src/db';
import { fmtGbp, fmtMiles, vehicleEmoji, taxYearLabel } from '../../src/db/tax';

export default function HomeScreen() {
  const [summary, setSummary] = React.useState({ earnings: 0, miles: 0, deduction: 0, takeHome: 0, taxRate: 0.2 });
  const [trips, setTrips] = React.useState<ReturnType<typeof getTrips>>([]);
  const [user, setUser] = React.useState(getUser());
  const [refreshing, setRefreshing] = React.useState(false);

  function load() {
    setSummary(getWeeklySummary());
    setTrips(getTrips(5));
    setUser(getUser());
  }

  useFocusEffect(useCallback(() => { load(); }, []));

  function onRefresh() {
    setRefreshing(true);
    load();
    setRefreshing(false);
  }

  const greeting = () => {
    const h = new Date().getHours();
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  };

  return (
    <ScrollView
      style={s.screen}
      contentContainerStyle={s.content}
      refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={colors.brand} />}
    >
      <View style={s.header}>
        <View>
          <Text style={s.greeting}>{greeting()}{user?.name ? `, ${user.name}` : ''} 👋</Text>
          <Text style={s.subheading}>This week · Tax year {taxYearLabel()}</Text>
        </View>
        <Text style={{ fontSize: 28 }}>{vehicleEmoji(user?.vehicle ?? 'car')}</Text>
      </View>

      <View style={s.metricsRow}>
        <MetricCard label="Est. take-home" value={fmtGbp(summary.takeHome)} sub="after mileage deduction" accent style={{ marginRight: 8 }} />
        <MetricCard label="Miles logged" value={fmtMiles(summary.miles)} sub={`${fmtGbp(summary.deduction)} deduction`} />
      </View>
      <View style={[s.metricsRow, { marginTop: 10 }]}>
        <MetricCard label="Earnings" value={fmtGbp(summary.earnings)} style={{ marginRight: 8 }} />
        <MetricCard label="Tax benefit" value={`~${fmtGbp(summary.deduction * summary.taxRate)}`} sub={`at ${(summary.taxRate * 100).toFixed(0)}% rate`} />
      </View>

      <View style={{ marginTop: spacing.xl }}>
        <SectionHeader title="Recent trips" />
        {trips.length === 0 ? (
          <Card>
            <Text style={{ color: colors.textSecondary, fontSize: 14, textAlign: 'center', paddingVertical: 8 }}>
              No trips yet — tap Trip to start tracking 📍
            </Text>
          </Card>
        ) : (
          <Card style={{ padding: 0, overflow: 'hidden' }}>
            {trips.map((t, i) => (
              <View key={t.id} style={[s.tripRow, i < trips.length - 1 && s.tripBorder]}>
                <View style={s.tripLeft}>
                  <Text style={s.tripPlatform}>{t.platform}</Text>
                  <Text style={s.tripDate}>{vehicleEmoji(t.vehicle)} {fmtMiles(t.miles)} · {new Date(t.started_at).toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short' })}</Text>
                </View>
                <View style={s.tripRight}>
                  <Text style={s.tripDeduction}>{fmtGbp(t.deduction)}</Text>
                  {t.earnings ? <Text style={s.tripEarnings}>{fmtGbp(t.earnings)} earned</Text> : null}
                </View>
              </View>
            ))}
          </Card>
        )}
      </View>

      <View style={s.disclaimer}>
        <Text style={s.disclaimerText}>
          Estimates only — not tax advice. Share your export with an accountant for your official return.
        </Text>
      </View>
    </ScrollView>
  );
}

const s = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  content: { padding: spacing.xl, paddingTop: 60, paddingBottom: 40 },
  header: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: spacing.xl },
  greeting: { ...type.screenTitle },
  subheading: { ...type.caption, marginTop: 4 },
  metricsRow: { flexDirection: 'row' },
  tripRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', padding: spacing.lg },
  tripBorder: { borderBottomWidth: 1, borderBottomColor: colors.border },
  tripLeft: { flex: 1 },
  tripPlatform: { ...type.bodyMedium, fontSize: 15 },
  tripDate: { ...type.caption, marginTop: 2 },
  tripRight: { alignItems: 'flex-end' },
  tripDeduction: { fontSize: 15, fontWeight: font.semibold, color: colors.brandDeep },
  tripEarnings: { fontSize: 12, color: colors.green, marginTop: 2 },
  disclaimer: { marginTop: spacing.xl, padding: spacing.lg, backgroundColor: colors.bgSoft, borderRadius: radius.md },
  disclaimerText: { ...type.small, lineHeight: 18, textAlign: 'center' },
});
