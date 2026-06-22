import React, { useCallback } from 'react';
import { View, Text, ScrollView, StyleSheet, RefreshControl, Pressable } from 'react-native';
import { useFocusEffect, useRouter } from 'expo-router';
import { colors, font, spacing, radius, type } from '../../src/theme';
import { MetricCard, Card, SectionHeader } from '../../src/components';
import {
  getWeeklySummary, getTrips, getUser, getTaxYearMiles, getPlatformStats,
  type PlatformStat,
} from '../../src/db';
import { fmtGbp, fmtMiles, vehicleEmoji, taxYearLabel } from '../../src/db/tax';

const THRESHOLD = 10000; // HMRC: car/van rate drops 45p -> 25p after 10k miles/year

export default function HomeScreen() {
  const router = useRouter();
  const [summary, setSummary] = React.useState({ earnings: 0, miles: 0, deduction: 0, takeHome: 0, taxRate: 0.2 });
  const [trips, setTrips] = React.useState<ReturnType<typeof getTrips>>([]);
  const [user, setUser] = React.useState(getUser());
  const [yearMiles, setYearMiles] = React.useState(0);
  const [platformStats, setPlatformStats] = React.useState<PlatformStat[]>([]);
  const [refreshing, setRefreshing] = React.useState(false);

  function load() {
    setSummary(getWeeklySummary());
    setTrips(getTrips(5));
    setUser(getUser());
    setYearMiles(getTaxYearMiles());
    setPlatformStats(getPlatformStats());
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

  const isCarOrVan = (user?.vehicle ?? 'car') === 'car' || (user?.vehicle ?? 'car') === 'van';
  const thresholdPct = Math.min(100, (yearMiles / THRESHOLD) * 100);
  const milesLeft = Math.max(0, THRESHOLD - yearMiles);
  const earnerStats = platformStats.filter(p => p.perMile > 0);

  return (
    <ScrollView
      style={s.screen}
      contentContainerStyle={s.content}
      refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={colors.brand} />}
    >
      <View style={s.header}>
        <View style={{ flex: 1 }}>
          <Text style={s.greeting}>{greeting()}{user?.name ? `, ${user.name}` : ''} 👋</Text>
          <Text style={s.subheading}>This week · Tax year {taxYearLabel()}</Text>
        </View>
        <Pressable onPress={() => router.push('/settings')} hitSlop={12} style={s.gear}>
          <Text style={{ fontSize: 22 }}>⚙️</Text>
        </Pressable>
      </View>

      {/* Quick-start: the fastest path to the core action */}
      <Pressable onPress={() => router.push('/(tabs)/trip')} style={({ pressed }) => [s.quickStart, pressed && { opacity: 0.9 }]}>
        <View>
          <Text style={s.quickStartTitle}>Start a trip</Text>
          <Text style={s.quickStartSub}>Track your miles with GPS</Text>
        </View>
        <Text style={s.quickStartIcon}>📍</Text>
      </Pressable>

      <View style={s.metricsRow}>
        <MetricCard label="Est. take-home" value={fmtGbp(summary.takeHome)} sub="after mileage deduction" accent style={{ marginRight: 8 }} />
        <MetricCard label="Miles logged" value={fmtMiles(summary.miles)} sub={`${fmtGbp(summary.deduction)} deduction`} />
      </View>
      <View style={[s.metricsRow, { marginTop: 10 }]}>
        <MetricCard label="Earnings" value={fmtGbp(summary.earnings)} style={{ marginRight: 8 }} />
        <MetricCard label="Tax benefit" value={`~${fmtGbp(summary.deduction * summary.taxRate)}`} sub={`at ${(summary.taxRate * 100).toFixed(0)}% rate`} />
      </View>

      {/* 10,000-mile threshold tracker (car/van only) */}
      {isCarOrVan && yearMiles > 0 && (
        <View style={{ marginTop: spacing.xl }}>
          <SectionHeader title="10,000-mile threshold" />
          <Card>
            <View style={s.rowBetween}>
              <Text style={s.thresholdMiles}>{fmtMiles(yearMiles)} this tax year</Text>
              <Text style={s.thresholdPct}>{thresholdPct.toFixed(0)}%</Text>
            </View>
            <View style={s.progressTrack}>
              <View style={[s.progressFill, { width: `${thresholdPct}%`, backgroundColor: thresholdPct >= 100 ? colors.amber : colors.brand }]} />
            </View>
            <Text style={s.thresholdNote}>
              {milesLeft > 0
                ? `${fmtMiles(milesLeft)} left before your rate drops from 45p to 25p per mile.`
                : 'Past 10,000 miles — additional car/van miles are deducted at 25p.'}
            </Text>
          </Card>
        </View>
      )}

      {/* Earnings per mile by platform — the headline analytic */}
      {earnerStats.length > 0 && (
        <View style={{ marginTop: spacing.xl }}>
          <SectionHeader title="Earnings per mile" />
          <Card style={{ padding: 0, overflow: 'hidden' }}>
            {earnerStats.map((p, i) => (
              <View key={p.platform} style={[s.tripRow, i < earnerStats.length - 1 && s.tripBorder]}>
                <View style={s.tripLeft}>
                  <Text style={s.tripPlatform}>{p.platform}</Text>
                  <Text style={s.tripDate}>{fmtMiles(p.miles)} · {fmtGbp(p.earnings)} earned</Text>
                </View>
                <View style={s.tripRight}>
                  <Text style={[s.tripDeduction, i === 0 && { color: colors.green }]}>£{p.perMile.toFixed(2)}/mi</Text>
                  {i === 0 && earnerStats.length > 1 ? <Text style={s.bestTag}>best</Text> : null}
                </View>
              </View>
            ))}
          </Card>
        </View>
      )}

      <View style={{ marginTop: spacing.xl }}>
        <SectionHeader title="Recent trips" />
        {trips.length === 0 ? (
          <Card>
            <Text style={s.emptyText}>No trips yet — tap Start a trip above 📍</Text>
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
  header: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: spacing.lg },
  greeting: { ...type.screenTitle },
  subheading: { ...type.caption, marginTop: 4 },
  gear: { padding: 4 },

  quickStart: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    backgroundColor: colors.brand, borderRadius: radius.lg,
    paddingVertical: 18, paddingHorizontal: spacing.xl, marginBottom: spacing.lg,
  },
  quickStartTitle: { color: '#fff', fontSize: 19, fontWeight: font.bold },
  quickStartSub: { color: 'rgba(255,255,255,0.85)', fontSize: 13, marginTop: 2 },
  quickStartIcon: { fontSize: 28 },

  metricsRow: { flexDirection: 'row' },
  rowBetween: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 10 },
  thresholdMiles: { ...type.bodyMedium, fontSize: 15 },
  thresholdPct: { ...type.bodyMedium, fontSize: 15, color: colors.brandDeep },
  progressTrack: { height: 8, borderRadius: radius.full, backgroundColor: colors.bgSoft, overflow: 'hidden' },
  progressFill: { height: '100%', borderRadius: radius.full },
  thresholdNote: { ...type.caption, color: colors.textTertiary, marginTop: 10, lineHeight: 19 },

  tripRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', padding: spacing.lg },
  tripBorder: { borderBottomWidth: 1, borderBottomColor: colors.border },
  tripLeft: { flex: 1 },
  tripPlatform: { ...type.bodyMedium, fontSize: 15 },
  tripDate: { ...type.caption, marginTop: 2 },
  tripRight: { alignItems: 'flex-end' },
  tripDeduction: { fontSize: 15, fontWeight: font.semibold, color: colors.brandDeep },
  tripEarnings: { fontSize: 12, color: colors.green, marginTop: 2 },
  bestTag: { fontSize: 11, color: colors.green, fontWeight: font.semibold, marginTop: 2 },
  emptyText: { color: colors.textSecondary, fontSize: 14, textAlign: 'center', paddingVertical: 8 },

  disclaimer: { marginTop: spacing.xl, padding: spacing.lg, backgroundColor: colors.bgSoft, borderRadius: radius.md },
  disclaimerText: { ...type.small, lineHeight: 18, textAlign: 'center' },
});
