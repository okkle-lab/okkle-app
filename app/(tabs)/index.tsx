import React, { useCallback } from 'react';
import { View, Text, ScrollView, StyleSheet, RefreshControl, Pressable, Modal } from 'react-native';
import { useFocusEffect, useRouter } from 'expo-router';
import { Feather } from '@expo/vector-icons';
import { colors, font, spacing, radius, type } from '../../src/theme';
import { MetricCard, Card, SectionHeader, Icon, VehicleIcon, CountUp } from '../../src/components';
import {
  getWeeklySummary, getTrips, getUser, getTaxYearMiles, getPlatformStats,
  getTaxYearSummary, getTaxYearExpenses, getEarningsByTimeOfDay,
  kvGetNum, kvSet, type PlatformStat, type TimeBucket,
} from '../../src/db';
import { fmtGbp, fmtMiles, taxYearLabel } from '../../src/db/tax';
import { taxPosition } from '../../src/db/taxcalc';

const MILESTONES = [50, 100, 250, 500, 1000, 2000, 3000, 5000, 10000];

const THRESHOLD = 10000;

export default function HomeScreen() {
  const router = useRouter();
  const [summary, setSummary] = React.useState({ earnings: 0, miles: 0, deduction: 0, takeHome: 0, taxRate: 0.2 });
  const [year, setYear] = React.useState({ miles: 0, deduction: 0, taxSaved: 0, earnings: 0, taxRate: 0.2 });
  const [trips, setTrips] = React.useState<ReturnType<typeof getTrips>>([]);
  const [user, setUser] = React.useState(getUser());
  const [yearMiles, setYearMiles] = React.useState(0);
  const [platformStats, setPlatformStats] = React.useState<PlatformStat[]>([]);
  const [setAside, setSetAside] = React.useState(0);
  const [milestone, setMilestone] = React.useState<number | null>(null);
  const [buckets, setBuckets] = React.useState<TimeBucket[]>([]);
  const [refreshing, setRefreshing] = React.useState(false);

  function load() {
    const w = getWeeklySummary();
    const y = getTaxYearSummary();
    const u = getUser();
    setSummary(w);
    setYear(y);
    setTrips(getTrips(5));
    setUser(u);
    setYearMiles(getTaxYearMiles());
    setPlatformStats(getPlatformStats());
    setBuckets(getEarningsByTimeOfDay());

    // "Set aside for tax" estimate.
    const pos = taxPosition(y.earnings, y.deduction + getTaxYearExpenses(), u?.region ?? 'ruk', kvGetNum('other_income'));
    setSetAside(pos.totalDue);

    // Milestone celebration when tax saved crosses a new threshold.
    const reached = [...MILESTONES].reverse().find(m => y.taxSaved >= m) ?? 0;
    const seen = kvGetNum('milestone_seen');
    if (reached > seen) { setMilestone(reached); kvSet('milestone_seen', reached); }
  }

  useFocusEffect(useCallback(() => { load(); }, []));

  function onRefresh() { setRefreshing(true); load(); setRefreshing(false); }

  const isCarOrVan = (user?.vehicle ?? 'car') === 'car' || (user?.vehicle ?? 'car') === 'van';
  const thresholdPct = Math.min(100, (yearMiles / THRESHOLD) * 100);
  const milesLeft = Math.max(0, THRESHOLD - yearMiles);
  const earnerStats = platformStats.filter(p => p.perMile > 0);

  return (
    <>
    <Modal visible={milestone !== null} transparent animationType="fade" onRequestClose={() => setMilestone(null)}>
      <Pressable style={s.modalBg} onPress={() => setMilestone(null)}>
        <View style={s.modalCard}>
          <Text style={s.modalEmoji}>🎉</Text>
          <Text style={s.modalTitle}>Nice work!</Text>
          <Text style={s.modalBody}>You've saved over {fmtGbp(milestone ?? 0)} in tax this year through mileage tracking.</Text>
          <Pressable onPress={() => setMilestone(null)} style={s.modalBtn}><Text style={s.modalBtnText}>Keep it up</Text></Pressable>
        </View>
      </Pressable>
    </Modal>
    <ScrollView
      style={s.screen}
      contentContainerStyle={s.content}
      refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={colors.brand} />}
    >
      <View style={s.header}>
        <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8, flex: 1 }}>
          <VehicleIcon vehicle={user?.vehicle ?? 'car'} size={22} color={colors.textSecondary} />
          <Text style={s.hello}>{user?.name || 'Hi'}</Text>
        </View>
        <Pressable onPress={() => router.push('/settings')} hitSlop={12} style={s.gear}>
          <Icon name="settings" size={22} color={colors.textSecondary} />
        </Pressable>
      </View>

      {/* HERO: tax saved this year — the emotional centrepiece */}
      <View style={s.hero}>
        <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6 }}>
          <Feather name="trending-up" size={15} color="#fff" />
          <Text style={s.heroLabel}>Tax saved this year</Text>
        </View>
        <CountUp value={year.taxSaved} prefix="£" style={s.heroValue} />
        <Text style={s.heroSub}>
          from {fmtMiles(year.miles)} · {fmtGbp(year.deduction)} mileage deduction
        </Text>
        <View style={s.heroChip}>
          <Text style={s.heroChipText}>Tax year {taxYearLabel()}</Text>
        </View>
      </View>

      {/* Set aside for tax — practical money guidance */}
      <Card style={s.setAside}>
        <View style={{ flexDirection: 'row', alignItems: 'center', gap: 12 }}>
          <View style={s.piggy}><Feather name="shield" size={18} color={colors.amber} /></View>
          <View style={{ flex: 1 }}>
            <Text style={s.setAsideLabel}>Set aside for tax</Text>
            <Text style={s.setAsideSub}>Estimated bill so far this year</Text>
          </View>
          <Text style={s.setAsideValue}>{fmtGbp(setAside)}</Text>
        </View>
      </Card>

      {/* Quick-start */}
      <Pressable onPress={() => router.push('/(tabs)/trip')} style={({ pressed }) => [s.quickStart, pressed && { opacity: 0.9 }]}>
        <View style={{ flexDirection: 'row', alignItems: 'center', gap: 12 }}>
          <Feather name="navigation" size={22} color="#fff" />
          <View>
            <Text style={s.quickStartTitle}>Start a trip</Text>
            <Text style={s.quickStartSub}>Track miles with GPS</Text>
          </View>
        </View>
        <Feather name="arrow-right" size={22} color="#fff" />
      </Pressable>

      <Text style={s.weekLabel}>This week</Text>
      <View style={s.metricsRow}>
        <MetricCard icon="home" label="Take-home" value={fmtGbp(summary.takeHome)} accent style={{ marginRight: 8 }} />
        <MetricCard icon="map" label="Miles" value={fmtMiles(summary.miles)} sub={fmtGbp(summary.deduction)} />
      </View>
      <View style={[s.metricsRow, { marginTop: 10 }]}>
        <MetricCard icon="dollar-sign" label="Earnings" value={fmtGbp(summary.earnings)} style={{ marginRight: 8 }} />
        <MetricCard icon="percent" label="Tax benefit" value={`~${fmtGbp(summary.deduction * summary.taxRate)}`} />
      </View>

      {isCarOrVan && yearMiles > 0 && (
        <View style={{ marginTop: spacing.xl }}>
          <SectionHeader title="10,000-mile threshold" />
          <Card>
            <View style={s.rowBetween}>
              <Text style={s.thresholdMiles}>{fmtMiles(yearMiles)} this year</Text>
              <Text style={s.thresholdPct}>{thresholdPct.toFixed(0)}%</Text>
            </View>
            <View style={s.progressTrack}>
              <View style={[s.progressFill, { width: `${thresholdPct}%`, backgroundColor: thresholdPct >= 100 ? colors.amber : colors.brand }]} />
            </View>
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6, marginTop: 10 }}>
              <Feather name="info" size={13} color={colors.textTertiary} />
              <Text style={s.thresholdNote}>
                {milesLeft > 0
                  ? `${fmtMiles(milesLeft)} left before 45p drops to 25p/mile`
                  : 'Past 10,000 miles — extra car/van miles at 25p'}
              </Text>
            </View>
          </Card>
        </View>
      )}

      {earnerStats.length > 0 && (
        <View style={{ marginTop: spacing.xl }}>
          <SectionHeader title="Earnings per mile" />
          <Card style={{ padding: 0, overflow: 'hidden' }}>
            {earnerStats.map((p, i) => (
              <View key={p.platform} style={[s.row, i < earnerStats.length - 1 && s.rowBorder]}>
                <View style={{ flex: 1 }}>
                  <Text style={s.rowTitle}>{p.platform}</Text>
                  <Text style={s.rowSub}>{fmtMiles(p.miles)} · {fmtGbp(p.earnings)}</Text>
                </View>
                <View style={{ alignItems: 'flex-end', flexDirection: 'row', gap: 6 }}>
                  {i === 0 && earnerStats.length > 1 ? <Feather name="award" size={15} color={colors.green} /> : null}
                  <Text style={[s.rowAmount, i === 0 && { color: colors.green }]}>£{p.perMile.toFixed(2)}/mi</Text>
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
            <Text style={s.emptyText}>No trips yet — tap Start a trip above</Text>
          </Card>
        ) : (
          <Card style={{ padding: 0, overflow: 'hidden' }}>
            {trips.map((t, i) => (
              <View key={t.id} style={[s.row, i < trips.length - 1 && s.rowBorder]}>
                <VehicleIcon vehicle={t.vehicle} size={20} color={colors.textSecondary} />
                <View style={{ flex: 1, marginLeft: 10 }}>
                  <Text style={s.rowTitle}>{t.platform}</Text>
                  <Text style={s.rowSub}>{fmtMiles(t.miles)} · {new Date(t.started_at).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' })}</Text>
                </View>
                <View style={{ alignItems: 'flex-end' }}>
                  <Text style={s.rowAmount}>{fmtGbp(t.deduction)}</Text>
                  {t.earnings ? <Text style={s.rowEarn}>{fmtGbp(t.earnings)}</Text> : null}
                </View>
              </View>
            ))}
          </Card>
        )}
      </View>

      {/* Best hours heatmap */}
      {buckets.some(b => b.trips > 0) && (
        <View style={{ marginTop: spacing.xl }}>
          <SectionHeader title="Best times to work" />
          <Card>
            {(() => {
              const maxPer = Math.max(...buckets.map(b => b.perHour), 1);
              const anyEarnings = buckets.some(b => b.earnings > 0);
              return buckets.map(b => {
                const ref = anyEarnings ? b.perHour : b.trips;
                const max = anyEarnings ? maxPer : Math.max(...buckets.map(x => x.trips), 1);
                const pct = max > 0 ? (ref / max) * 100 : 0;
                return (
                  <View key={b.label} style={s.heatRow}>
                    <Text style={s.heatLabel}>{b.label}</Text>
                    <View style={s.heatTrack}>
                      <View style={[s.heatFill, { width: `${Math.max(4, pct)}%`, opacity: 0.35 + (pct / 100) * 0.65 }]} />
                    </View>
                    <Text style={s.heatVal}>{anyEarnings ? `£${b.perHour.toFixed(0)}/h` : `${b.trips}`}</Text>
                  </View>
                );
              });
            })()}
            <Text style={s.heatNote}>
              {buckets.some(b => b.earnings > 0)
                ? 'Based on your earnings per hour. Add earnings to trips for sharper insight.'
                : 'Based on trip count — add earnings to each trip to see £/hour.'}
            </Text>
          </Card>
        </View>
      )}

      <View style={s.disclaimer}>
        <Feather name="shield" size={14} color={colors.textTertiary} />
        <Text style={s.disclaimerText}>
          Estimates only — not tax advice. Share your export with an accountant.
        </Text>
      </View>
    </ScrollView>
    </>
  );
}

const s = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  content: { padding: spacing.xl, paddingTop: 60, paddingBottom: 40 },
  header: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: spacing.lg },
  hello: { ...type.heading, fontSize: 18 },
  gear: { padding: 4 },

  hero: {
    backgroundColor: colors.brandDeep, borderRadius: radius.xl,
    padding: spacing.xl, marginBottom: spacing.lg,
  },
  heroLabel: { color: 'rgba(255,255,255,0.85)', fontSize: 14, fontWeight: font.medium },
  heroValue: { color: '#fff', fontSize: 44, fontWeight: font.bold, letterSpacing: -1, marginTop: 8 },
  heroSub: { color: 'rgba(255,255,255,0.8)', fontSize: 13, marginTop: 4 },
  heroChip: {
    alignSelf: 'flex-start', backgroundColor: 'rgba(255,255,255,0.18)',
    paddingHorizontal: 12, paddingVertical: 5, borderRadius: radius.full, marginTop: spacing.md,
  },
  heroChipText: { color: '#fff', fontSize: 12, fontWeight: font.medium },

  quickStart: {
    flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between',
    backgroundColor: colors.brand, borderRadius: radius.lg,
    paddingVertical: 18, paddingHorizontal: spacing.xl, marginBottom: spacing.xl,
  },
  quickStartTitle: { color: '#fff', fontSize: 18, fontWeight: font.bold },
  quickStartSub: { color: 'rgba(255,255,255,0.85)', fontSize: 13, marginTop: 1 },

  weekLabel: { ...type.label, color: colors.textSecondary, marginBottom: spacing.sm, fontWeight: font.semibold },
  metricsRow: { flexDirection: 'row' },
  rowBetween: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 10 },
  thresholdMiles: { ...type.bodyMedium, fontSize: 15 },
  thresholdPct: { ...type.bodyMedium, fontSize: 15, color: colors.brandDeep },
  progressTrack: { height: 8, borderRadius: radius.full, backgroundColor: colors.bgSoft, overflow: 'hidden' },
  progressFill: { height: '100%', borderRadius: radius.full },
  thresholdNote: { ...type.caption, color: colors.textTertiary, flex: 1, lineHeight: 18 },

  row: { flexDirection: 'row', alignItems: 'center', padding: spacing.lg },
  rowBorder: { borderBottomWidth: 1, borderBottomColor: colors.border },
  rowTitle: { ...type.bodyMedium, fontSize: 15 },
  rowSub: { ...type.caption, marginTop: 2 },
  rowAmount: { fontSize: 15, fontWeight: font.semibold, color: colors.brandDeep },
  rowEarn: { fontSize: 12, color: colors.green, marginTop: 2 },
  emptyText: { color: colors.textSecondary, fontSize: 14, textAlign: 'center', paddingVertical: 8 },

  disclaimer: { marginTop: spacing.xl, padding: spacing.lg, backgroundColor: colors.bgSoft, borderRadius: radius.md, flexDirection: 'row', alignItems: 'center', gap: 8 },
  disclaimerText: { ...type.small, lineHeight: 18, flex: 1 },

  setAside: { marginBottom: spacing.lg },
  piggy: { width: 38, height: 38, borderRadius: 19, backgroundColor: colors.amberLight, alignItems: 'center', justifyContent: 'center' },
  setAsideLabel: { ...type.bodyMedium, fontSize: 15 },
  setAsideSub: { ...type.caption, marginTop: 1 },
  setAsideValue: { fontSize: 20, fontWeight: font.bold, color: colors.amber },

  heatRow: { flexDirection: 'row', alignItems: 'center', paddingVertical: 7, gap: 10 },
  heatLabel: { ...type.caption, color: colors.textSecondary, width: 70 },
  heatTrack: { flex: 1, height: 14, backgroundColor: colors.bgSoft, borderRadius: radius.full, overflow: 'hidden' },
  heatFill: { height: '100%', backgroundColor: colors.brand, borderRadius: radius.full },
  heatVal: { ...type.caption, color: colors.textPrimary, width: 48, textAlign: 'right', fontWeight: font.medium },
  heatNote: { ...type.small, marginTop: 10, lineHeight: 17 },

  modalBg: { flex: 1, backgroundColor: 'rgba(0,0,0,0.5)', alignItems: 'center', justifyContent: 'center', padding: spacing.xl },
  modalCard: { backgroundColor: colors.bgCard, borderRadius: radius.xl, padding: spacing.xl, alignItems: 'center', width: '100%', maxWidth: 340 },
  modalEmoji: { fontSize: 56, marginBottom: spacing.md },
  modalTitle: { ...type.screenTitle, marginBottom: spacing.sm },
  modalBody: { ...type.body, color: colors.textSecondary, textAlign: 'center', lineHeight: 23, marginBottom: spacing.xl },
  modalBtn: { backgroundColor: colors.brand, borderRadius: radius.lg, paddingVertical: 14, paddingHorizontal: spacing.xl, alignSelf: 'stretch', alignItems: 'center' },
  modalBtnText: { color: '#fff', fontSize: 16, fontWeight: font.semibold },
});
