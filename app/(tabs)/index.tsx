import React, { useCallback } from 'react';
import { View, Text, ScrollView, StyleSheet, RefreshControl, Pressable, Modal } from 'react-native';
import { useFocusEffect, useRouter } from 'expo-router';
import { Feather } from '@expo/vector-icons';
import { colors, font, spacing, radius, type } from '../../src/theme';
import { MetricCard, Card, SectionHeader, Icon, VehicleIcon, CountUp } from '../../src/components';
import {
  getTrips, getUser, getTaxYearMiles,
  getTaxYearSummary, getTaxYearExpenses, getEarningsByTimeOfDay,
  getPeriodSummary, getPlatformStatsForPeriod,
  getStreak, getAchievements, popNewAchievements,
  kvGetNum, type PlatformStat, type TimeBucket, type Period, type PeriodSummary, type Achievement,
} from '../../src/db';
import { fmtGbp, fmtMiles, taxYearLabel, fmtPerHour, fmtPerMile, fmtHours, fmtPct } from '../../src/db/tax';
import { tabular } from '../../src/theme';
import { taxPosition } from '../../src/db/taxcalc';

const THRESHOLD = 10000;

export default function HomeScreen() {
  const router = useRouter();
  const [period, setPeriod] = React.useState<Period>('week');
  const [periodData, setPeriodData] = React.useState<PeriodSummary | null>(null);
  const [periodPlatforms, setPeriodPlatforms] = React.useState<PlatformStat[]>([]);
  const [year, setYear] = React.useState({ miles: 0, deduction: 0, taxSaved: 0, earnings: 0, taxRate: 0.2 });
  const [trips, setTrips] = React.useState<ReturnType<typeof getTrips>>([]);
  const [user, setUser] = React.useState(getUser());
  const [yearMiles, setYearMiles] = React.useState(0);
  const [setAside, setSetAside] = React.useState(0);
  const [streak, setStreak] = React.useState(0);
  const [achievements, setAchievements] = React.useState<Achievement[]>([]);
  const [newAch, setNewAch] = React.useState<Achievement | null>(null);
  const [buckets, setBuckets] = React.useState<TimeBucket[]>([]);
  const [refreshing, setRefreshing] = React.useState(false);

  function loadPeriod(p: Period) {
    setPeriodData(getPeriodSummary(p));
    setPeriodPlatforms(getPlatformStatsForPeriod(p));
  }

  function load() {
    const y = getTaxYearSummary();
    const u = getUser();
    setYear(y);
    setTrips(getTrips(5));
    setUser(u);
    setYearMiles(getTaxYearMiles());
    setBuckets(getEarningsByTimeOfDay());
    loadPeriod(period);

    // "Set aside for tax" estimate.
    const pos = taxPosition(y.earnings, y.deduction + getTaxYearExpenses(), u?.region ?? 'ruk', kvGetNum('other_income'));
    setSetAside(pos.totalDue);

    // Gamification: streak, badges, and a celebration for anything new.
    setStreak(getStreak());
    setAchievements(getAchievements());
    const fresh = popNewAchievements();
    if (fresh.length) setNewAch(fresh[0]);
  }

  useFocusEffect(useCallback(() => { load(); }, [period]));

  function selectPeriod(p: Period) { setPeriod(p); loadPeriod(p); }

  function onRefresh() { setRefreshing(true); load(); setRefreshing(false); }

  const isCarOrVan = (user?.vehicle ?? 'car') === 'car' || (user?.vehicle ?? 'car') === 'van';
  const thresholdPct = Math.min(100, (yearMiles / THRESHOLD) * 100);
  const milesLeft = Math.max(0, THRESHOLD - yearMiles);

  return (
    <>
    <Modal visible={newAch !== null} transparent animationType="fade" onRequestClose={() => setNewAch(null)}>
      <Pressable style={s.modalBg} onPress={() => setNewAch(null)}>
        <View style={s.modalCard}>
          <View style={s.achBurst}>
            <Feather name={(newAch?.icon ?? 'award') as any} size={34} color="#fff" />
          </View>
          <Text style={s.achKicker}>Achievement unlocked</Text>
          <Text style={s.modalTitle}>{newAch?.label}</Text>
          <Text style={s.modalBody}>{newAch?.desc}</Text>
          <Pressable onPress={() => setNewAch(null)} style={s.modalBtn}><Text style={s.modalBtnText}>Nice!</Text></Pressable>
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

      {/* Period switcher — Today · Week · Month · Year */}
      <View style={s.segment}>
        {([['today', 'Today'], ['week', 'Week'], ['month', 'Month'], ['year', 'Year']] as [Period, string][]).map(([p, label]) => (
          <Pressable key={p} onPress={() => selectPeriod(p)} style={[s.segItem, period === p && s.segItemActive]}>
            <Text style={[s.segText, period === p && s.segTextActive]}>{label}</Text>
          </Pressable>
        ))}
      </View>
      <Text style={s.periodLabel}>{periodData?.label ?? ''}</Text>
      <View style={s.metricsRow}>
        <MetricCard icon="home" label="Take-home" value={fmtGbp(periodData?.takeHome ?? 0)} accent style={{ marginRight: 8 }} />
        <MetricCard icon="map" label="Miles" value={fmtMiles(periodData?.miles ?? 0)} sub={fmtGbp(periodData?.deduction ?? 0)} />
      </View>
      <View style={[s.metricsRow, { marginTop: 10 }]}>
        <MetricCard icon="dollar-sign" label="Earnings" value={fmtGbp(periodData?.earnings ?? 0)} style={{ marginRight: 8 }} />
        <MetricCard
          icon="clock"
          label={period === 'today' ? 'Trips' : 'Hours'}
          value={period === 'today' ? String(periodData?.trips ?? 0) : fmtHours(periodData?.hours ?? 0)}
          sub={(periodData?.hours ?? 0) > 0 ? fmtPerHour((periodData?.earnings ?? 0) / (periodData?.hours || 1)) : undefined}
        />
      </View>

      {/* Per-platform breakdown for the selected period — multi-platform couriers */}
      {periodPlatforms.length > 0 && (
        <View style={{ marginTop: spacing.lg }}>
          <SectionHeader icon="grid" title={`By platform · ${periodData?.label ?? ''}`} />
          <Card style={{ padding: 0, overflow: 'hidden' }}>
            {periodPlatforms.map((p, i, arr) => (
              <View key={p.platform} style={[s.row, i < arr.length - 1 && s.rowBorder]}>
                <View style={{ flex: 1 }}>
                  <Text style={s.rowTitle}>{p.platform}</Text>
                  <Text style={s.rowSub}>
                    {fmtMiles(p.miles)}{p.perMile > 0 ? ` · ${fmtPerMile(p.perMile)}` : ''}
                  </Text>
                </View>
                <View style={{ alignItems: 'flex-end', flexDirection: 'row', gap: 6 }}>
                  {i === 0 && arr.length > 1 ? <Feather name="award" size={15} color={colors.green} /> : null}
                  <Text style={[s.rowAmount, { color: colors.textPrimary }, i === 0 && { color: colors.green }]}>{fmtGbp(p.earnings)}</Text>
                </View>
              </View>
            ))}
          </Card>
        </View>
      )}

      {/* Gamification — streak + achievement badges */}
      {achievements.length > 0 && (
        <View style={{ marginTop: spacing.xl }}>
          <SectionHeader icon="zap" title="Your progress" />
          <Card>
            <View style={s.streakRow}>
              <View style={[s.streakIcon, streak > 0 ? { backgroundColor: colors.amberLight } : { backgroundColor: colors.bgSoft }]}>
                <Feather name="zap" size={18} color={streak > 0 ? colors.amber : colors.textTertiary} />
              </View>
              <View style={{ flex: 1 }}>
                <Text style={s.streakValue}>{streak > 0 ? `${streak}-day streak` : 'No streak yet'}</Text>
                <Text style={s.streakSub}>{streak > 0 ? 'Keep logging daily to grow it' : 'Track a trip today to start one'}</Text>
              </View>
              <Text style={s.achCount}>{achievements.filter(a => a.unlocked).length}/{achievements.length}</Text>
            </View>
            <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ marginTop: spacing.lg, marginHorizontal: -4 }} contentContainerStyle={{ paddingHorizontal: 4, gap: 14 }}>
              {achievements.map(a => (
                <View key={a.key} style={s.badge}>
                  <View style={[s.badgeCircle, a.unlocked ? s.badgeOn : s.badgeOff]}>
                    <Feather name={a.icon as any} size={20} color={a.unlocked ? '#fff' : colors.textTertiary} />
                  </View>
                  <Text style={[s.badgeLabel, !a.unlocked && { color: colors.textTertiary }]} numberOfLines={2}>{a.label}</Text>
                  {!a.unlocked && a.progress > 0 && (
                    <View style={s.badgeTrack}><View style={[s.badgeFill, { width: `${Math.round(a.progress * 100)}%` }]} /></View>
                  )}
                </View>
              ))}
            </ScrollView>
          </Card>
        </View>
      )}

      {isCarOrVan && yearMiles > 0 && (
        <View style={{ marginTop: spacing.xl }}>
          <SectionHeader icon="alert-circle" title="10,000-mile threshold" />
          <Card>
            <View style={s.rowBetween}>
              <Text style={s.thresholdMiles}>{fmtMiles(yearMiles)} this year</Text>
              <Text style={s.thresholdPct}>{Math.round(thresholdPct)}%</Text>
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

      <View style={{ marginTop: spacing.xl }}>
        <SectionHeader icon="clock" title="Recent trips" />
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
          <SectionHeader icon="sunrise" title="Best times to work" />
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
                    <Text style={s.heatVal}>{anyEarnings ? fmtPerHour(b.perHour) : `${b.trips}`}</Text>
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
  heroValue: { ...tabular, color: '#fff', fontSize: 44, fontWeight: font.bold, letterSpacing: -1, marginTop: 8 },
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

  segment: { flexDirection: 'row', backgroundColor: colors.bgSoft, borderRadius: radius.lg, padding: 4, marginBottom: spacing.sm },
  segItem: { flex: 1, paddingVertical: 9, alignItems: 'center', borderRadius: radius.md },
  segItemActive: { backgroundColor: colors.bgCard, shadowColor: '#000', shadowOpacity: 0.06, shadowRadius: 4, shadowOffset: { width: 0, height: 1 }, elevation: 1 },
  segText: { fontSize: 14, fontWeight: font.medium, color: colors.textSecondary },
  segTextActive: { color: colors.textPrimary, fontWeight: font.semibold },
  periodLabel: { ...type.label, color: colors.textSecondary, marginBottom: spacing.sm, fontWeight: font.semibold },
  metricsRow: { flexDirection: 'row' },
  rowBetween: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 10 },
  thresholdMiles: { ...type.bodyMedium, ...tabular, fontSize: 15 },
  thresholdPct: { ...type.bodyMedium, ...tabular, fontSize: 15, color: colors.brandDeep },
  progressTrack: { height: 8, borderRadius: radius.full, backgroundColor: colors.bgSoft, overflow: 'hidden' },
  progressFill: { height: '100%', borderRadius: radius.full },
  thresholdNote: { ...type.caption, color: colors.textTertiary, flex: 1, lineHeight: 18 },

  row: { flexDirection: 'row', alignItems: 'center', padding: spacing.lg },
  rowBorder: { borderBottomWidth: 1, borderBottomColor: colors.border },
  rowTitle: { ...type.bodyMedium, fontSize: 15 },
  rowSub: { ...type.caption, marginTop: 2 },
  rowAmount: { ...tabular, fontSize: 15, fontWeight: font.semibold, color: colors.brandDeep },
  rowEarn: { ...tabular, fontSize: 12, color: colors.green, marginTop: 2 },
  emptyText: { color: colors.textSecondary, fontSize: 14, textAlign: 'center', paddingVertical: 8 },

  disclaimer: { marginTop: spacing.xl, padding: spacing.lg, backgroundColor: colors.bgSoft, borderRadius: radius.md, flexDirection: 'row', alignItems: 'center', gap: 8 },
  disclaimerText: { ...type.small, lineHeight: 18, flex: 1 },

  setAside: { marginBottom: spacing.lg },
  piggy: { width: 38, height: 38, borderRadius: 19, backgroundColor: colors.amberLight, alignItems: 'center', justifyContent: 'center' },
  setAsideLabel: { ...type.bodyMedium, fontSize: 15 },
  setAsideSub: { ...type.caption, marginTop: 1 },
  setAsideValue: { ...tabular, fontSize: 20, fontWeight: font.bold, color: colors.amber },

  heatRow: { flexDirection: 'row', alignItems: 'center', paddingVertical: 7, gap: 10 },
  heatLabel: { ...type.caption, color: colors.textSecondary, width: 70 },
  heatTrack: { flex: 1, height: 14, backgroundColor: colors.bgSoft, borderRadius: radius.full, overflow: 'hidden' },
  heatFill: { height: '100%', backgroundColor: colors.brand, borderRadius: radius.full },
  heatVal: { ...type.caption, ...tabular, color: colors.textPrimary, width: 62, textAlign: 'right', fontWeight: font.medium },
  heatNote: { ...type.small, marginTop: 10, lineHeight: 17 },

  modalBg: { flex: 1, backgroundColor: 'rgba(0,0,0,0.5)', alignItems: 'center', justifyContent: 'center', padding: spacing.xl },
  modalCard: { backgroundColor: colors.bgCard, borderRadius: radius.xl, padding: spacing.xl, alignItems: 'center', width: '100%', maxWidth: 340 },
  modalEmoji: { fontSize: 56, marginBottom: spacing.md },
  modalTitle: { ...type.screenTitle, marginBottom: spacing.sm },
  modalBody: { ...type.body, color: colors.textSecondary, textAlign: 'center', lineHeight: 23, marginBottom: spacing.xl },
  modalBtn: { backgroundColor: colors.brand, borderRadius: radius.lg, paddingVertical: 14, paddingHorizontal: spacing.xl, alignSelf: 'stretch', alignItems: 'center' },
  modalBtnText: { color: '#fff', fontSize: 16, fontWeight: font.semibold },
  achBurst: { width: 72, height: 72, borderRadius: 36, backgroundColor: colors.brand, alignItems: 'center', justifyContent: 'center', marginBottom: spacing.md },
  achKicker: { ...type.label, color: colors.brandDeep, textTransform: 'uppercase', letterSpacing: 0.5, fontSize: 12, marginBottom: 4 },

  streakRow: { flexDirection: 'row', alignItems: 'center', gap: 12 },
  streakIcon: { width: 40, height: 40, borderRadius: 20, alignItems: 'center', justifyContent: 'center' },
  streakValue: { ...type.bodyMedium, fontSize: 16 },
  streakSub: { ...type.caption, marginTop: 1 },
  achCount: { ...type.bodyMedium, ...tabular, color: colors.brandDeep },

  badge: { width: 72, alignItems: 'center' },
  badgeCircle: { width: 52, height: 52, borderRadius: 26, alignItems: 'center', justifyContent: 'center', marginBottom: 6 },
  badgeOn: { backgroundColor: colors.brand },
  badgeOff: { backgroundColor: colors.bgSoft, borderWidth: 1, borderColor: colors.border },
  badgeLabel: { fontSize: 11, color: colors.textSecondary, textAlign: 'center', lineHeight: 14, fontWeight: font.medium },
  badgeTrack: { height: 4, width: 44, borderRadius: radius.full, backgroundColor: colors.bgSoft, overflow: 'hidden', marginTop: 4 },
  badgeFill: { height: '100%', backgroundColor: colors.brandMid, borderRadius: radius.full },
});
