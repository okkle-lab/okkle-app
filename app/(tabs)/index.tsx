import React, { useCallback } from 'react';
import { View, Text, ScrollView, StyleSheet, RefreshControl, Pressable, Modal, Dimensions } from 'react-native';
import { useFocusEffect, useRouter } from 'expo-router';
import { Feather } from '@expo/vector-icons';
import { colors, font, spacing, radius, type } from '../../src/theme';
import { MetricCard, Card, SectionHeader, Icon, VehicleIcon, CountUp, Medal, HeatMapView, BarChart, CoachMarks, type CoachStep } from '../../src/components';
import {
  getTrips, getUser, getTaxYearMiles,
  getTaxYearSummary, getEarningsByTimeOfDay,
  getPeriodSummary, getPlatformStatsForPeriod,
  getStreak, getAchievements, popNewAchievements, getXp, getWeeklyChallenges, creditCompletedChallenges,
  getHeatPoints, getBestSpot, getPeriodSeries, kvGet, kvSet,
  type PlatformStat, type TimeBucket, type Period, type PeriodSummary, type Achievement,
  type XpInfo, type Challenge, type HeatPoint, type BestSpot, type SeriesPoint,
} from '../../src/db';
import { fmtGbp, fmtMiles, taxYearLabel, fmtPerHour, fmtPerMile, fmtHours } from '../../src/db/tax';
import { tabular } from '../../src/theme';

const THRESHOLD = 10000;

// A reference date inside the *previous* comparable period, for the trend.
function prevRef(period: Period): Date {
  const d = new Date();
  if (period === 'today') d.setDate(d.getDate() - 1);
  else if (period === 'week') d.setDate(d.getDate() - 7);
  else if (period === 'month') d.setMonth(d.getMonth() - 1, 15);
  else d.setFullYear(d.getFullYear() - 1);
  return d;
}
const PREV_WORD: { [k in Period]: string } = { today: 'yesterday', week: 'last week', month: 'last month', year: 'last year' };

// Named rank for a level — status/identity, so the number means something.
function rankFor(level: number): string {
  if (level >= 15) return `Legend · Level ${level}`;
  if (level >= 10) return `Veteran · Level ${level}`;
  if (level >= 6) return `Pro · Level ${level}`;
  if (level >= 3) return `Regular · Level ${level}`;
  return `Rookie · Level ${level}`;
}

// A clear date range under the period switcher (e.g. "Mon 17 – Sun 23 Jun").
function fmtPeriodRange(period: Period, startIso: string, endIso: string): string {
  const opts: Intl.DateTimeFormatOptions = { weekday: 'short', day: 'numeric', month: 'short' };
  const start = new Date(startIso);
  const end = new Date(endIso);
  if (period === 'today') return start.toLocaleDateString('en-GB', { weekday: 'long', day: 'numeric', month: 'long' });
  if (period === 'month') return start.toLocaleDateString('en-GB', { month: 'long', year: 'numeric' });
  if (period === 'year') {
    const y = (d: Date) => d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' });
    return `${y(start)} – ${y(end)}`;
  }
  return `${start.toLocaleDateString('en-GB', opts)} – ${end.toLocaleDateString('en-GB', opts)}`;
}

export default function HomeScreen() {
  const router = useRouter();
  const [period, setPeriod] = React.useState<Period>('week');
  const [periodData, setPeriodData] = React.useState<PeriodSummary | null>(null);
  const [periodPlatforms, setPeriodPlatforms] = React.useState<PlatformStat[]>([]);
  const [prevData, setPrevData] = React.useState<PeriodSummary | null>(null);
  const [series, setSeries] = React.useState<SeriesPoint[]>([]);
  const [year, setYear] = React.useState({ miles: 0, deduction: 0, taxSaved: 0, earnings: 0, taxRate: 0.2 });
  const [trips, setTrips] = React.useState<ReturnType<typeof getTrips>>([]);
  const [user, setUser] = React.useState(getUser());
  const [yearMiles, setYearMiles] = React.useState(0);
  const [streak, setStreak] = React.useState(0);
  const [achievements, setAchievements] = React.useState<Achievement[]>([]);
  const [newAch, setNewAch] = React.useState<Achievement | null>(null);
  const [xp, setXp] = React.useState<XpInfo | null>(null);
  const [challenges, setChallenges] = React.useState<Challenge[]>([]);
  const [buckets, setBuckets] = React.useState<TimeBucket[]>([]);
  const [heatPoints, setHeatPoints] = React.useState<HeatPoint[]>([]);
  const [bestSpot, setBestSpot] = React.useState<BestSpot | null>(null);
  const [refreshing, setRefreshing] = React.useState(false);

  // First-run tour — a quick walk across the five tabs so people know what each does.
  const [showCoach, setShowCoach] = React.useState(false);
  useFocusEffect(useCallback(() => {
    if (getUser()?.onboarded && !kvGet('coach_seen')) {
      const t = setTimeout(() => setShowCoach(true), 650);
      return () => clearTimeout(t);
    }
  }, []));
  const win = Dimensions.get('window');
  const TAB_H = 84;
  const tabRect = (i: number) => ({ x: (win.width / 5) * i + 4, y: win.height - TAB_H + 2, w: win.width / 5 - 8, h: 50 });
  const coachSteps: CoachStep[] = [
    { rect: tabRect(0), title: 'Home', body: 'Your earnings, your £/hour, and where you earn most — at a glance.' },
    { rect: tabRect(1), title: 'Track a trip', body: 'Tap Trip, then Start. GPS logs every mile as tax-free money back — automatically, no notes.' },
    { rect: tabRect(2), title: 'Log', body: 'Add expenses (snap the receipt) and your weekly pay so your numbers stay accurate.' },
    { rect: tabRect(3), title: 'Records', body: 'Everything you’ve logged — tap any entry to edit or delete it.' },
    { rect: tabRect(4), title: 'Tax', body: 'Your estimated bill, what to set aside, and a one-tap summary for your accountant.' },
  ];
  function dismissCoach() { kvSet('coach_seen', 1); setShowCoach(false); }

  function loadPeriod(p: Period) {
    setPeriodData(getPeriodSummary(p));
    setPeriodPlatforms(getPlatformStatsForPeriod(p));
    setPrevData(getPeriodSummary(p, prevRef(p)));
    setSeries(getPeriodSeries(p));
  }

  function load() {
    const y = getTaxYearSummary();
    const u = getUser();
    setYear(y);
    setTrips(getTrips(5));
    setUser(u);
    setYearMiles(getTaxYearMiles());
    setBuckets(getEarningsByTimeOfDay());
    setHeatPoints(getHeatPoints());
    setBestSpot(getBestSpot());
    loadPeriod(period);

    // Gamification: streak, badges, and a celebration for anything new.
    setStreak(getStreak());
    setAchievements(getAchievements());
    setChallenges(getWeeklyChallenges());
    creditCompletedChallenges();   // award XP for any challenge finished since last open
    setXp(getXp());
    const fresh = popNewAchievements();
    if (fresh.length) setNewAch(fresh[0]);
  }

  useFocusEffect(useCallback(() => { load(); }, [period]));

  function selectPeriod(p: Period) { setPeriod(p); loadPeriod(p); }

  function onRefresh() { setRefreshing(true); load(); setRefreshing(false); }

  const isCarOrVan = (user?.vehicle ?? 'car') === 'car' || (user?.vehicle ?? 'car') === 'van';
  const thresholdPct = Math.min(100, (yearMiles / THRESHOLD) * 100);
  const milesLeft = Math.max(0, THRESHOLD - yearMiles);
  // Home preview: show unlocked first, then those closest to unlocking.
  const achievementPreview = [...achievements]
    .sort((a, b) => (Number(b.unlocked) - Number(a.unlocked)) || (b.progress - a.progress))
    .slice(0, 12);

  return (
    <>
    <CoachMarks steps={coachSteps} visible={showCoach} onDone={dismissCoach} />
    <Modal visible={newAch !== null} transparent animationType="fade" onRequestClose={() => setNewAch(null)}>
      <Pressable style={s.modalBg} onPress={() => setNewAch(null)}>
        <View style={s.modalCard}>
          {newAch && <Medal emoji={newAch.emoji} category={newAch.category} tier={newAch.tier} unlocked size={104} />}
          <Text style={s.achKicker}>Medal unlocked</Text>
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
        {/* Streak chip — the daily-return hook, kept glanceable up top */}
        <Pressable onPress={() => router.push('/medals')} hitSlop={8} style={[s.streakChip, streak > 0 ? s.streakChipOn : s.streakChipOff]}>
          <Text style={{ fontSize: 14 }}>{streak > 0 ? '🔥' : '✨'}</Text>
          <Text style={[s.streakChipText, streak === 0 && { color: colors.textSecondary }]}>{streak > 0 ? streak : 'Start'}</Text>
        </Pressable>
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

      {/* Quick-start — primary action right under the hero */}
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

      {/* Play block — level + weekly challenges, kept high so it feels like a game */}
      {xp && (
        <Card style={{ marginTop: spacing.lg }}>
          <View style={s.levelRow}>
            <View style={s.levelBadge}><Text style={s.levelBadgeText}>Lv {xp.level}</Text></View>
            <View style={{ flex: 1 }}>
              <View style={s.levelTop}>
                <Text style={s.levelTitle}>{rankFor(xp.level)}</Text>
                <Text style={s.levelXp}>{xp.into} / {xp.span} XP</Text>
              </View>
              <View style={s.xpTrack}><View style={[s.xpFill, { width: `${Math.round(xp.progress * 100)}%` }]} /></View>
            </View>
          </View>
          <Text style={s.levelHint}>You climb ranks by staying consistent — every trip, expense and streak day earns XP.</Text>
        </Card>
      )}
      {challenges.length > 0 && (
        <Card style={{ marginTop: spacing.md }}>
          <View style={s.challHead}>
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6 }}>
              <Feather name="target" size={15} color={colors.brand} />
              <Text style={s.challTitle}>This week's challenges</Text>
            </View>
            <Text style={s.challXp}>{challenges.reduce((n, c) => n + (c.done ? 0 : c.xp), 0)} XP to go</Text>
          </View>
          {challenges.map((c, i) => (
            <View key={c.key} style={[s.challRow, i < challenges.length - 1 && s.challRowBorder]}>
              <View style={[s.challEmoji, c.done && { backgroundColor: colors.greenLight }]}>
                <Text style={{ fontSize: 18 }}>{c.done ? '✅' : c.emoji}</Text>
              </View>
              <View style={{ flex: 1, gap: 7 }}>
                <View style={s.challTop}>
                  <Text style={[s.challLabel, c.done && { color: colors.textTertiary }]} numberOfLines={1}>{c.label}</Text>
                  <View style={[s.xpPill, c.done && { backgroundColor: colors.greenLight }]}>
                    <Text style={[s.xpPillText, c.done && { color: colors.green }]} numberOfLines={1}>{c.done ? 'Done' : `+${c.xp} XP`}</Text>
                  </View>
                </View>
                <View style={s.challTrack}>
                  <View style={[s.challFill, { width: `${Math.round(c.progress * 100)}%` }, c.done && { backgroundColor: colors.green }]} />
                </View>
                <Text style={s.challProg}>{Math.min(c.value, c.target)} / {c.target}</Text>
              </View>
            </View>
          ))}
        </Card>
      )}

      {/* Period switcher — Today · Week · Month · Year */}
      <View style={s.segment}>
        {([['today', 'Today'], ['week', 'Week'], ['month', 'Month'], ['year', 'Year']] as [Period, string][]).map(([p, label]) => (
          <Pressable key={p} onPress={() => selectPeriod(p)} style={[s.segItem, period === p && s.segItemActive]}>
            <Text style={[s.segText, period === p && s.segTextActive]}>{label}</Text>
          </Pressable>
        ))}
      </View>
      <Text style={s.periodLabel}>{periodData ? fmtPeriodRange(period, periodData.rangeStart, periodData.rangeEnd) : ''}</Text>

      {/* THE number couriers care about: take-home per hour worked. */}
      {(() => {
        const hrs = periodData?.hours ?? 0;
        const perHour = hrs > 0 ? (periodData!.earnings / hrs) : 0;
        // After tax AND real costs: take-home (earnings - tax) minus actual expenses spent.
        const netPerHour = hrs > 0 ? Math.max(0, periodData!.takeHome - periodData!.expenses) / hrs : 0;
        const prevHrs = prevData?.hours ?? 0;
        const prevPerHour = prevHrs > 0 ? (prevData!.earnings / prevHrs) : null;
        const delta = prevPerHour != null && hrs > 0 ? perHour - prevPerHour : null;
        return (
          <View style={s.kpi}>
            <View style={s.kpiHead}>
              <Feather name="clock" size={15} color="#fff" />
              <Text style={s.kpiLabel}>Earned per hour</Text>
            </View>
            {hrs > 0 ? (
              <>
                <View style={{ flexDirection: 'row', alignItems: 'baseline', gap: 6 }}>
                  <Text style={s.kpiValue}>£{perHour.toFixed(2)}</Text>
                  <Text style={s.kpiUnit}>/hr</Text>
                </View>
                <Text style={s.kpiNet}>£{netPerHour.toFixed(2)}/hr after tax &amp; costs</Text>
                {delta != null && Math.abs(delta) >= 0.05 && (
                  <View style={[s.kpiTrend, { backgroundColor: delta >= 0 ? 'rgba(255,255,255,0.22)' : 'rgba(226,96,74,0.30)' }]}>
                    <Feather name={delta >= 0 ? 'arrow-up-right' : 'arrow-down-right'} size={13} color="#fff" />
                    <Text style={s.kpiTrendText}>£{Math.abs(delta).toFixed(2)}/hr vs {PREV_WORD[period]}</Text>
                  </View>
                )}
              </>
            ) : (
              <Text style={s.kpiEmpty}>Track a trip with GPS and log your pay to see what you really make per hour.</Text>
            )}
          </View>
        );
      })()}

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
        />
      </View>

      {/* Earnings over time — week (daily), month (weekly), year (monthly) */}
      {period !== 'today' && series.length > 0 && (
        <View style={{ marginTop: spacing.lg }}>
          <SectionHeader icon="bar-chart-2" title={`Earnings · ${period === 'week' ? 'by day' : period === 'month' ? 'by week' : 'by month'}`} />
          <Card>
            <BarChart data={series} height={150} />
          </Card>
        </View>
      )}

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

      {/* Gamification — medal collection */}
      {achievements.length > 0 && (
        <View style={{ marginTop: spacing.xl }}>
          <View style={s.progressHead}>
            <SectionHeader icon="zap" title="Your progress" />
            <Pressable onPress={() => router.push('/medals')} hitSlop={8} style={{ flexDirection: 'row', alignItems: 'center', gap: 2 }}>
              <Text style={s.seeAll}>See all medals</Text>
              <Feather name="chevron-right" size={15} color={colors.brandDeep} />
            </Pressable>
          </View>
          <Pressable onPress={() => router.push('/medals')}>
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
                {achievementPreview.map(a => (
                  <View key={a.key} style={s.badge}>
                    <Medal emoji={a.emoji} category={a.category} tier={a.tier} unlocked={a.unlocked} size={54} />
                    <Text style={[s.badgeLabel, !a.unlocked && { color: colors.textTertiary }]} numberOfLines={2}>{a.label}</Text>
                    {!a.unlocked && a.progress > 0 && (
                      <View style={s.badgeTrack}><View style={[s.badgeFill, { width: `${Math.round(a.progress * 100)}%` }]} /></View>
                    )}
                  </View>
                ))}
              </ScrollView>
            </Card>
          </Pressable>
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

      {/* Insights preview — promoted to Home (hotspots + best times inside) */}
      <View style={{ marginTop: spacing.xl }}>
        <View style={s.progressHead}>
          <SectionHeader icon="map" title="Where you earn most" />
          <Pressable onPress={() => router.push('/insights')} hitSlop={8} style={{ flexDirection: 'row', alignItems: 'center', gap: 2 }}>
            <Text style={s.seeAll}>Insights</Text>
            <Feather name="chevron-right" size={15} color={colors.brandDeep} />
          </Pressable>
        </View>
        <Pressable onPress={() => router.push('/insights')}>
          <Card style={{ padding: spacing.sm }}>
            <HeatMapView points={heatPoints} height={160} />
            <View style={s.insightsCaptionRow}>
              <Text style={s.insightsCaption} numberOfLines={1}>
                {bestSpot ? `Best: ${bestSpot.zone}, ${bestSpot.timeLabel} · ${fmtPerHour(bestSpot.perHour)}` : 'Your hotspots, top areas & best hours'}
              </Text>
              <Feather name="arrow-right" size={16} color={colors.brandDeep} />
            </View>
          </Card>
        </Pressable>
      </View>

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
  hello: { ...type.heading, fontSize: 22, letterSpacing: -0.4 },
  gear: { padding: 4 },
  streakChip: { flexDirection: 'row', alignItems: 'center', gap: 4, paddingHorizontal: 10, paddingVertical: 5, borderRadius: radius.full, marginRight: 6 },
  streakChipOn: { backgroundColor: colors.amberLight },
  streakChipOff: { backgroundColor: colors.bgSoft },
  streakChipText: { ...tabular, fontSize: 14, fontWeight: font.bold, color: colors.amber },

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
    paddingVertical: 18, paddingHorizontal: spacing.xl,
  },
  quickStartTitle: { color: '#fff', fontSize: 18, fontWeight: font.bold },
  quickStartSub: { color: 'rgba(255,255,255,0.85)', fontSize: 13, marginTop: 1 },

  segment: { flexDirection: 'row', backgroundColor: colors.bgSoft, borderRadius: radius.lg, padding: 4, marginBottom: spacing.sm, marginTop: spacing.xl },
  segItem: { flex: 1, paddingVertical: 9, alignItems: 'center', borderRadius: radius.md },
  segItemActive: { backgroundColor: colors.bgCard, shadowColor: '#000', shadowOpacity: 0.06, shadowRadius: 4, shadowOffset: { width: 0, height: 1 }, elevation: 1 },
  segText: { fontSize: 14, fontWeight: font.medium, color: colors.textSecondary },
  segTextActive: { color: colors.textPrimary, fontWeight: font.semibold },
  periodLabel: { ...type.label, color: colors.textSecondary, marginBottom: spacing.md, fontWeight: font.semibold },
  kpi: { backgroundColor: colors.brandDeep, borderRadius: radius.lg, padding: spacing.lg, marginBottom: 10 },
  kpiHead: { flexDirection: 'row', alignItems: 'center', gap: 6, marginBottom: 6 },
  kpiLabel: { color: 'rgba(255,255,255,0.9)', fontSize: 14, fontWeight: font.medium },
  kpiValue: { ...tabular, color: '#fff', fontSize: 38, fontWeight: font.bold, letterSpacing: -1 },
  kpiUnit: { color: 'rgba(255,255,255,0.85)', fontSize: 17, fontWeight: font.semibold },
  kpiNet: { ...tabular, color: 'rgba(255,255,255,0.85)', fontSize: 13, marginTop: 2 },
  kpiTrend: { flexDirection: 'row', alignItems: 'center', gap: 4, alignSelf: 'flex-start', paddingHorizontal: 10, paddingVertical: 4, borderRadius: radius.full, marginTop: spacing.md },
  kpiTrendText: { ...tabular, color: '#fff', fontSize: 12, fontWeight: font.semibold },
  kpiEmpty: { color: 'rgba(255,255,255,0.85)', fontSize: 14, lineHeight: 20, marginTop: 2 },
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

  progressHead: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  seeAll: { ...type.caption, color: colors.brandDeep, fontWeight: font.medium },
  insightsCaptionRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', paddingHorizontal: spacing.sm, paddingTop: spacing.md, paddingBottom: 4 },
  insightsCaption: { ...type.caption, color: colors.brandDeep, fontWeight: font.medium },

  levelRow: { flexDirection: 'row', alignItems: 'center', gap: 12 },
  levelBadge: { width: 46, height: 46, borderRadius: 23, backgroundColor: colors.brand, alignItems: 'center', justifyContent: 'center' },
  levelBadgeText: { color: '#fff', fontSize: 14, fontWeight: font.bold },
  levelTop: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 6 },
  levelTitle: { ...type.bodyMedium, fontSize: 15 },
  levelXp: { ...type.caption, ...tabular },
  levelHint: { ...type.small, lineHeight: 17, marginTop: spacing.md },
  xpTrack: { height: 8, borderRadius: radius.full, backgroundColor: colors.bgSoft, overflow: 'hidden' },
  xpFill: { height: '100%', backgroundColor: colors.brand, borderRadius: radius.full },

  challHead: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: spacing.md },
  challTitle: { ...type.bodyMedium, fontSize: 15 },
  challXp: { ...type.caption, ...tabular, color: colors.brandDeep, fontWeight: font.semibold },
  challRow: { flexDirection: 'row', alignItems: 'center', gap: 12, paddingVertical: 12 },
  challRowBorder: { borderBottomWidth: 1, borderBottomColor: colors.border },
  challEmoji: { width: 38, height: 38, borderRadius: 19, backgroundColor: colors.bgSoft, alignItems: 'center', justifyContent: 'center' },
  challTop: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', gap: 8 },
  challLabel: { ...type.bodyMedium, fontSize: 14, flex: 1 },
  challProg: { ...type.small, ...tabular },
  challTrack: { height: 6, borderRadius: radius.full, backgroundColor: colors.bgSoft, overflow: 'hidden' },
  challFill: { height: '100%', backgroundColor: colors.brand, borderRadius: radius.full },
  xpPill: { backgroundColor: colors.amberLight, paddingHorizontal: 9, paddingVertical: 3, borderRadius: radius.full },
  xpPillText: { ...tabular, fontSize: 12, fontWeight: font.bold, color: colors.amber },
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
