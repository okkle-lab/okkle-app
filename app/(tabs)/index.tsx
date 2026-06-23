import React, { useCallback } from 'react';
import { View, Text, ScrollView, StyleSheet, RefreshControl, Pressable, Modal, Dimensions, Animated } from 'react-native';
import { useFocusEffect, useRouter } from 'expo-router';
import { Feather } from '@expo/vector-icons';
import { colors, font, spacing, radius, type } from '../../src/theme';
import { Card, SectionHeader, Icon, CountUp, Medal, BarChart, IconBadge, GradientCard, CollapsingHeader, CoachMarks, type CoachStep } from '../../src/components';
import {
  getUser,
  getTaxYearSummary,
  getPeriodSummary, getPlatformStatsForPeriod,
  getStreak, getAchievements, popNewAchievements, getWeeklyChallenges,
  getBestSpot, getZoneStats, getEarningsByTimeOfDay, getPlatformStats, getPeriodSeries, kvGet, kvSet,
  type PlatformStat, type Period, type PeriodSummary, type Achievement,
  type Challenge, type BestSpot, type SeriesPoint, type ZoneStat, type TimeBucket,
} from '../../src/db';
import { fmtGbp, fmtMiles, taxYearLabel, fmtPerHour, fmtPerMile, fmtHours } from '../../src/db/tax';
import { tabular } from '../../src/theme';


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
const PERIODS: Period[] = ['today', 'week', 'month', 'year'];
const PERIOD_LABELS = ['Today', 'Week', 'Month', 'Year'];
type Bundle = { data: PeriodSummary; platforms: PlatformStat[]; prev: PeriodSummary; series: SeriesPoint[] };

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
  const win = Dimensions.get('window');
  const [periodIndex, setPeriodIndex] = React.useState(1); // default: Week
  const [bundles, setBundles] = React.useState<Bundle[] | null>(null);
  const period = PERIODS[periodIndex];
  const scrollX = React.useRef(new Animated.Value(win.width)).current; // start on Week
  const pagerRef = React.useRef<ScrollView>(null);
  const didInitPager = React.useRef(false);
  const [gamePage, setGamePage] = React.useState(0);
  const [year, setYear] = React.useState({ miles: 0, deduction: 0, taxSaved: 0, earnings: 0, taxRate: 0.2 });
  const [user, setUser] = React.useState(getUser());
  const [streak, setStreak] = React.useState(0);
  const [achievements, setAchievements] = React.useState<Achievement[]>([]);
  const [newAch, setNewAch] = React.useState<Achievement | null>(null);
  const [challenges, setChallenges] = React.useState<Challenge[]>([]);
  const [zones, setZones] = React.useState<ZoneStat[]>([]);
  const [buckets, setBuckets] = React.useState<TimeBucket[]>([]);
  const [platformsAll, setPlatformsAll] = React.useState<PlatformStat[]>([]);
  const [bestSpot, setBestSpot] = React.useState<BestSpot | null>(null);
  const [insightPage, setInsightPage] = React.useState(0);
  const [refreshing, setRefreshing] = React.useState(false);

  // First-run tour — a quick walk across the five tabs so people know what each does.
  const [showCoach, setShowCoach] = React.useState(false);
  useFocusEffect(useCallback(() => {
    if (getUser()?.onboarded && !kvGet('coach_seen')) {
      const t = setTimeout(() => setShowCoach(true), 650);
      return () => clearTimeout(t);
    }
  }, []));
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

  function load() {
    setYear(getTaxYearSummary());
    setUser(getUser());
    setBestSpot(getBestSpot());
    setZones(getZoneStats('all'));
    setBuckets(getEarningsByTimeOfDay());
    setPlatformsAll(getPlatformStats());

    // Preload all four periods so swiping between them is instant & smooth.
    setBundles(PERIODS.map(p => ({
      data: getPeriodSummary(p),
      platforms: getPlatformStatsForPeriod(p),
      prev: getPeriodSummary(p, prevRef(p)),
      series: getPeriodSeries(p, 'earnings'),
    })));

    // Gamification: streak, badges, and a celebration for anything new.
    setStreak(getStreak());
    setAchievements(getAchievements());
    setChallenges(getWeeklyChallenges());
    const fresh = popNewAchievements();
    if (fresh.length) setNewAch(fresh[0]);
  }

  useFocusEffect(useCallback(() => { load(); }, []));

  function goToPeriod(i: number) {
    setPeriodIndex(i);
    pagerRef.current?.scrollTo({ x: i * win.width, animated: true });
  }

  function onRefresh() { setRefreshing(true); load(); setRefreshing(false); }

  // Home preview: show unlocked first, then those closest to unlocking.
  const achievementPreview = [...achievements]
    .sort((a, b) => (Number(b.unlocked) - Number(a.unlocked)) || (b.progress - a.progress))
    .slice(0, 12);

  // Animated sliding pill for the period switcher, driven by the earnings pager.
  const SEG_W = win.width - spacing.xl * 2;
  const SEG_PAD = 4;
  const ITEM_W = (SEG_W - SEG_PAD * 2) / PERIODS.length;
  const indicatorX = scrollX.interpolate({
    inputRange: [0, win.width * (PERIODS.length - 1)],
    outputRange: [SEG_PAD, SEG_PAD + ITEM_W * (PERIODS.length - 1)],
    extrapolate: 'clamp',
  });

  // One earnings card, rendered per period so users can swipe between them.
  function renderEarnings(b: Bundle, p: Period) {
    const earnings = b.data.earnings;
    const hrs = b.data.hours;
    const miles = b.data.miles;
    const hasHours = hrs >= 0.25;
    const perHour = hasHours ? earnings / hrs : 0;
    const netPerHour = hasHours ? Math.max(0, b.data.takeHome - b.data.expenses) / hrs : 0;
    const earnDelta = b.prev && b.prev.earnings > 0 ? earnings - b.prev.earnings : null;
    const hasTrend = earnDelta != null && Math.abs(earnDelta) >= 1;
    const tops = [...b.platforms].sort((x, y) => y.earnings - x.earnings).slice(0, 3);
    return (
      <Card style={{ padding: spacing.lg }}>
        <View style={s.earnHead}>
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
            <IconBadge icon="dollar-sign" tone="green" size={32} />
            <Text style={s.earnLabel}>Earnings</Text>
          </View>
          {hasTrend && (
            <View style={[s.mcTrend, { backgroundColor: earnDelta! >= 0 ? colors.greenLight : colors.redLight, marginTop: 0, flexShrink: 1 }]}>
              <Feather name={earnDelta! >= 0 ? 'arrow-up-right' : 'arrow-down-right'} size={13} color={earnDelta! >= 0 ? colors.green : colors.red} />
              <Text numberOfLines={1} style={[s.mcTrendText, { color: earnDelta! >= 0 ? colors.green : colors.red }]}>{fmtGbp(Math.abs(earnDelta!))} vs {PREV_WORD[p]}</Text>
            </View>
          )}
        </View>
        <Text style={s.earnValue} numberOfLines={1} adjustsFontSizeToFit minimumFontScale={0.5}>{fmtGbp(earnings)}</Text>

        <View style={s.statRow}>
          <View style={s.statCell}>
            <Text style={s.statVal} numberOfLines={1} adjustsFontSizeToFit minimumFontScale={0.6}>{hasHours ? `£${perHour.toFixed(2)}` : '—'}</Text>
            <Text style={s.statLbl}>per hour</Text>
          </View>
          <View style={s.statDivider} />
          <View style={s.statCell}>
            <Text style={s.statVal} numberOfLines={1} adjustsFontSizeToFit minimumFontScale={0.6}>{fmtMiles(miles)}</Text>
            <Text style={s.statLbl} numberOfLines={1}>{fmtGbp(b.data.deduction)} back</Text>
          </View>
          <View style={s.statDivider} />
          <View style={s.statCell}>
            <Text style={s.statVal} numberOfLines={1} adjustsFontSizeToFit minimumFontScale={0.6}>{p === 'today' ? b.data.trips : fmtHours(hrs)}</Text>
            <Text style={s.statLbl}>{p === 'today' ? 'trips' : 'hours'}</Text>
          </View>
        </View>

        {hasHours && (
          <Text style={s.earnNet}>£{netPerHour.toFixed(2)}/hr after tax &amp; costs · take-home {fmtGbp(b.data.takeHome)}</Text>
        )}

        <View style={{ marginTop: spacing.lg }}>
          {p === 'today' && <Text style={s.chartCaption}>When you earned today</Text>}
          <BarChart data={b.series} format={fmtGbp} emptyLabel={p === 'today' ? 'No earnings logged yet today.' : 'No earnings logged in this period.'} height={120} />
        </View>

        {tops.length > 0 && (
          <View style={s.platWrap}>
            <Text style={s.platHead}>By platform</Text>
            {tops.map((pl, i) => (
              <View key={pl.platform} style={s.platRow}>
                <View style={[s.rankBadge, i === 0 && s.rankBadgeTop]}>
                  <Text style={[s.rankText, i === 0 && { color: '#fff' }]}>{i + 1}</Text>
                </View>
                <Text style={s.platName} numberOfLines={1}>{pl.platform}</Text>
                <Text style={s.platMiles}>{fmtMiles(pl.miles)}</Text>
                <Text style={[s.platVal, i === 0 && { color: colors.green }]}>{fmtGbp(pl.earnings)}</Text>
              </View>
            ))}
          </View>
        )}
      </Card>
    );
  }

  return (
    <>
    <CoachMarks steps={coachSteps} visible={showCoach} onDone={dismissCoach} />
    <Modal visible={newAch !== null} transparent animationType="fade" onRequestClose={() => setNewAch(null)}>
      <Pressable style={s.modalBg} onPress={() => setNewAch(null)}>
        <View style={s.modalCard}>
          {newAch && <Medal icon={newAch.icon as any} category={newAch.category} tier={newAch.tier} unlocked size={104} />}
          <Text style={s.achKicker}>Medal unlocked</Text>
          <Text style={s.modalTitle}>{newAch?.label}</Text>
          <Text style={s.modalBody}>{newAch?.desc}</Text>
          <Pressable onPress={() => setNewAch(null)} style={s.modalBtn}><Text style={s.modalBtnText}>Nice!</Text></Pressable>
        </View>
      </Pressable>
    </Modal>
    <CollapsingHeader
      title={user?.name || 'Hi'}
      right={
        <Pressable onPress={() => router.push('/settings')} hitSlop={12} style={s.gear}>
          <Icon name="settings" size={22} color={colors.textSecondary} />
        </Pressable>
      }
      refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={colors.brand} />}
    >
      {/* HERO: tax saved — tap through to the full Tax breakdown */}
      <Pressable onPress={() => router.push('/(tabs)/tax')}>
        <GradientCard colors={[colors.brand, colors.brandDeep, colors.dark]} radius={radius.xl} style={s.hero}>
          <View style={s.heroTop}>
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6 }}>
              <Feather name="trending-up" size={15} color="#fff" />
              <Text style={s.heroLabel}>Tax saved this year</Text>
            </View>
            <Feather name="chevron-right" size={20} color="rgba(255,255,255,0.85)" />
          </View>
          <CountUp value={year.taxSaved} prefix="£" style={s.heroValue} />
          <Text style={s.heroSub}>
            from {fmtMiles(year.miles)} · {fmtGbp(year.deduction)} mileage deduction
          </Text>
          <View style={s.heroChip}>
            <Text style={s.heroChipText}>Tax year {taxYearLabel()} · see breakdown</Text>
          </View>
        </GradientCard>
      </Pressable>

      {/* Period switcher with an animated sliding pill, synced to the pager */}
      <View style={s.segment}>
        <Animated.View style={[s.segIndicator, { width: ITEM_W, transform: [{ translateX: indicatorX }] }]} />
        {PERIOD_LABELS.map((label, i) => (
          <Pressable key={label} onPress={() => goToPeriod(i)} style={s.segItem}>
            <Text style={[s.segText, periodIndex === i && s.segTextActive]}>{label}</Text>
          </Pressable>
        ))}
      </View>
      <Text style={s.periodLabel}>{bundles ? fmtPeriodRange(period, bundles[periodIndex].data.rangeStart, bundles[periodIndex].data.rangeEnd) : ''}</Text>

      {/* Swipe sideways to move between Today · Week · Month · Year */}
      {bundles && (
        <>
          <Animated.ScrollView
            ref={pagerRef as any}
            horizontal pagingEnabled showsHorizontalScrollIndicator={false}
            scrollEventThrottle={16}
            onLayout={() => { if (!didInitPager.current) { pagerRef.current?.scrollTo({ x: periodIndex * win.width, animated: false }); didInitPager.current = true; } }}
            onScroll={Animated.event([{ nativeEvent: { contentOffset: { x: scrollX } } }], { useNativeDriver: true })}
            onMomentumScrollEnd={e => setPeriodIndex(Math.round(e.nativeEvent.contentOffset.x / win.width))}
            style={{ marginHorizontal: -spacing.xl, marginTop: spacing.md }}
          >
            {bundles.map((b, i) => (
              <View key={i} style={{ width: win.width, paddingHorizontal: spacing.xl }}>
                {renderEarnings(b, PERIODS[i])}
              </View>
            ))}
          </Animated.ScrollView>
          <View style={s.dots}>
            {PERIODS.map((_, i) => <View key={i} style={[s.cdot, i === periodIndex && s.cdotOn]} />)}
          </View>
        </>
      )}

      {/* Progress — goals + medals combined into one swipeable card */}
      {(achievements.length > 0 || challenges.length > 0) && (
        <View style={{ marginTop: spacing.xl }}>
          <View style={s.progressHead}>
            <SectionHeader icon="zap" title="Progress" />
            <Pressable onPress={() => router.push('/medals')} hitSlop={8} style={{ flexDirection: 'row', alignItems: 'center', gap: 2 }}>
              <Text style={s.seeAll}>See all</Text>
              <Feather name="chevron-right" size={15} color={colors.brandDeep} />
            </Pressable>
          </View>
          <ScrollView
            horizontal pagingEnabled showsHorizontalScrollIndicator={false}
            onMomentumScrollEnd={e => setGamePage(Math.round(e.nativeEvent.contentOffset.x / win.width))}
            style={{ marginHorizontal: -spacing.xl }}
          >
            {/* Page 1: weekly goals */}
            <View style={{ width: win.width, paddingHorizontal: spacing.xl }}>
              <Card style={{ minHeight: 230 }}>
                <View style={s.challHead}>
                  <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6 }}>
                    <Feather name="target" size={15} color={colors.brand} />
                    <Text style={s.challTitle}>This week's goals</Text>
                  </View>
                  <Text style={s.challXp}>{challenges.filter(c => c.done).length}/{challenges.length} done</Text>
                </View>
                {challenges.map((c, i) => (
                  <View key={c.key} style={[s.challRow, i < challenges.length - 1 && s.challRowBorder]}>
                    <IconBadge icon={c.done ? 'check' : (c.icon as any)} tone={c.done ? 'green' : (c.tone as any)} size={36} />
                    <View style={{ flex: 1, gap: 7 }}>
                      <View style={s.challTop}>
                        <Text style={[s.challLabel, c.done && { color: colors.textTertiary }]} numberOfLines={1}>{c.label}</Text>
                        <Text style={s.challProg}>{Math.min(c.value, c.target)} / {c.target}</Text>
                      </View>
                      <View style={s.challTrack}>
                        <View style={[s.challFill, { width: `${Math.round(c.progress * 100)}%` }, c.done && { backgroundColor: colors.green }]} />
                      </View>
                    </View>
                  </View>
                ))}
              </Card>
            </View>
            {/* Page 2: medals */}
            <View style={{ width: win.width, paddingHorizontal: spacing.xl }}>
              <Pressable onPress={() => router.push('/medals')}>
                <Card style={{ minHeight: 230 }}>
                  <View style={s.streakRow}>
                    <IconBadge icon="zap" tone={streak > 0 ? 'amber' : 'neutral'} size={40} />
                    <View style={{ flex: 1 }}>
                      <Text style={s.streakValue}>{streak > 0 ? `${streak}-day streak` : 'No streak yet'}</Text>
                      <Text style={s.streakSub}>{achievements.filter(a => a.unlocked).length} of {achievements.length} medals earned</Text>
                    </View>
                    <Feather name="chevron-right" size={20} color={colors.textTertiary} />
                  </View>
                  <ScrollView horizontal showsHorizontalScrollIndicator={false} style={{ marginTop: spacing.lg, marginHorizontal: -4 }} contentContainerStyle={{ paddingHorizontal: 4, gap: 14 }}>
                    {achievementPreview.map(a => (
                      <View key={a.key} style={s.badge}>
                        <Medal icon={a.icon as any} category={a.category} tier={a.tier} unlocked={a.unlocked} size={54} />
                        <Text style={[s.badgeLabel, !a.unlocked && { color: colors.textTertiary }]} numberOfLines={2}>{a.label}</Text>
                      </View>
                    ))}
                  </ScrollView>
                </Card>
              </Pressable>
            </View>
          </ScrollView>
          <View style={s.dots}>
            {[0, 1].map(i => <View key={i} style={[s.cdot, i === gamePage && s.cdotOn]} />)}
          </View>
        </View>
      )}

      {/* Where & when you earn — a swipeable carousel: Areas · Times · Platforms */}
      {(zones.length > 0 || buckets.some(b => b.trips > 0) || platformsAll.length > 0) && (() => {
        const anyPerHour = zones.some(z => z.perHour > 0);
        const rankedZones = [...zones].sort((a, b) => (anyPerHour ? b.perHour - a.perHour : b.miles - a.miles)).slice(0, 4);
        const anyBucketEarn = buckets.some(b => b.earnings > 0);
        const rankedTimes = [...buckets].filter(b => b.trips > 0).sort((a, b) => (anyBucketEarn ? b.perHour - a.perHour : b.trips - a.trips)).slice(0, 4);
        const anyPlatPerHour = platformsAll.some(p => p.perHour > 0);
        const rankedPlats = [...platformsAll].sort((a, b) => (anyPlatPerHour ? b.perHour - a.perHour : b.earnings - a.earnings)).slice(0, 4);

        const RankList = ({ rows }: { rows: { key: string; name: string; sub: string; val: string }[] }) => (
          <>
            {rows.map((r, i) => (
              <View key={r.key} style={[s.platRow, i > 0 && s.zoneBorder]}>
                <View style={[s.rankBadge, i === 0 && s.rankBadgeTop]}>
                  <Text style={[s.rankText, i === 0 && { color: '#fff' }]}>{i + 1}</Text>
                </View>
                <View style={{ flex: 1 }}>
                  <Text style={s.platName} numberOfLines={1}>{r.name}</Text>
                  <Text style={s.zoneSub}>{r.sub}</Text>
                </View>
                <Text style={[s.platVal, i === 0 && { color: colors.green }]}>{r.val}</Text>
              </View>
            ))}
          </>
        );

        const pages: { title: string; node: React.ReactNode }[] = [];
        if (rankedZones.length) pages.push({ title: 'Top areas', node: (
          <RankList rows={rankedZones.map(z => ({ key: z.zone, name: z.zone, sub: `${z.trips} ${z.trips === 1 ? 'trip' : 'trips'} · ${fmtMiles(z.miles)}`, val: anyPerHour ? fmtPerHour(z.perHour) : z.earnings > 0 ? fmtGbp(z.earnings) : fmtMiles(z.miles) }))} />
        ) });
        if (rankedTimes.length) pages.push({ title: 'Best times', node: (
          <RankList rows={rankedTimes.map(b => ({ key: b.label, name: b.label, sub: `${b.trips} ${b.trips === 1 ? 'trip' : 'trips'}`, val: anyBucketEarn ? fmtPerHour(b.perHour) : `${b.trips}` }))} />
        ) });
        if (rankedPlats.length) pages.push({ title: 'Best platforms', node: (
          <RankList rows={rankedPlats.map(p => ({ key: p.platform, name: p.platform, sub: `${fmtMiles(p.miles)}${p.perMile > 0 ? ` · ${fmtPerMile(p.perMile)}` : ''}`, val: anyPlatPerHour ? fmtPerHour(p.perHour) : fmtGbp(p.earnings) }))} />
        ) });

        return (
          <View style={{ marginTop: spacing.xl }}>
            <View style={s.progressHead}>
              <SectionHeader icon="bar-chart-2" title="Where & when you earn" />
              <Pressable onPress={() => router.push('/insights')} hitSlop={8} style={{ flexDirection: 'row', alignItems: 'center', gap: 2 }}>
                <Text style={s.seeAll}>Insights</Text>
                <Feather name="chevron-right" size={15} color={colors.brandDeep} />
              </Pressable>
            </View>
            {bestSpot && (
              <Pressable onPress={() => router.push('/insights')}>
                <View style={s.bestBanner}>
                  <IconBadge icon="award" tone="amber" size={34} />
                  <View style={{ flex: 1 }}>
                    <Text style={s.bestLabel} numberOfLines={1}>Best: {bestSpot.zone} · {bestSpot.timeLabel}</Text>
                    <Text style={s.bestSub}>your most lucrative spot &amp; time</Text>
                  </View>
                  <Text style={s.bestVal}>{fmtPerHour(bestSpot.perHour)}</Text>
                </View>
              </Pressable>
            )}
            <ScrollView
              horizontal pagingEnabled showsHorizontalScrollIndicator={false}
              onMomentumScrollEnd={e => setInsightPage(Math.round(e.nativeEvent.contentOffset.x / win.width))}
              style={{ marginHorizontal: -spacing.xl, marginTop: spacing.md }}
            >
              {pages.map((pg, i) => (
                <View key={i} style={{ width: win.width, paddingHorizontal: spacing.xl }}>
                  <Pressable onPress={() => router.push('/insights')}>
                    <Card style={{ padding: spacing.lg, minHeight: 232 }}>
                      <Text style={s.platHead}>{pg.title}</Text>
                      {pg.node}
                    </Card>
                  </Pressable>
                </View>
              ))}
            </ScrollView>
            {pages.length > 1 && (
              <View style={s.dots}>
                {pages.map((_, i) => <View key={i} style={[s.cdot, i === insightPage && s.cdotOn]} />)}
              </View>
            )}
          </View>
        );
      })()}

      <View style={s.disclaimer}>
        <Feather name="shield" size={14} color={colors.textTertiary} />
        <Text style={s.disclaimerText}>
          Estimates only — not tax advice. Share your export with an accountant.
        </Text>
      </View>
    </CollapsingHeader>
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

  hero: { padding: spacing.xl, marginBottom: spacing.lg },
  heroTop: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
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
  segIndicator: { position: 'absolute', top: 4, bottom: 4, left: 0, backgroundColor: colors.bgCard, borderRadius: radius.md, shadowColor: '#000', shadowOpacity: 0.08, shadowRadius: 4, shadowOffset: { width: 0, height: 1 }, elevation: 1 },
  segItem: { flex: 1, paddingVertical: 9, alignItems: 'center', borderRadius: radius.md },
  segText: { fontSize: 14, fontWeight: font.medium, color: colors.textSecondary },
  segTextActive: { color: colors.textPrimary, fontWeight: font.semibold },
  periodLabel: { ...type.label, color: colors.textSecondary, marginBottom: spacing.md, fontWeight: font.semibold },
  kpi: { backgroundColor: colors.brandDeep, borderRadius: radius.lg, padding: spacing.lg },
  kpiHead: { flexDirection: 'row', alignItems: 'center', gap: 6, marginBottom: 6 },
  kpiLabel: { color: 'rgba(255,255,255,0.9)', fontSize: 14, fontWeight: font.medium },
  kpiValue: { ...tabular, color: '#fff', fontSize: 38, fontWeight: font.bold, letterSpacing: -1 },
  kpiUnit: { color: 'rgba(255,255,255,0.85)', fontSize: 17, fontWeight: font.semibold },
  kpiNet: { ...tabular, color: 'rgba(255,255,255,0.85)', fontSize: 13, marginTop: 2 },
  kpiTrend: { flexDirection: 'row', alignItems: 'center', gap: 4, alignSelf: 'flex-start', paddingHorizontal: 10, paddingVertical: 4, borderRadius: radius.full, marginTop: spacing.md },
  kpiTrendText: { ...tabular, color: '#fff', fontSize: 12, fontWeight: font.semibold },
  kpiEmpty: { color: 'rgba(255,255,255,0.85)', fontSize: 14, lineHeight: 20, marginTop: 2 },
  mc: { backgroundColor: colors.bgCard, borderRadius: radius.lg, borderWidth: 1, borderColor: colors.border, padding: spacing.lg, minHeight: 124 },
  mcHead: { flexDirection: 'row', alignItems: 'center', gap: 8, marginBottom: 10 },
  mcIcon: { width: 28, height: 28, borderRadius: 14, backgroundColor: colors.brandLight, alignItems: 'center', justifyContent: 'center' },
  mcLabel: { ...type.label, fontSize: 14, color: colors.textSecondary, fontWeight: font.medium },
  mcValue: { ...tabular, fontSize: 36, fontWeight: font.bold, color: colors.textPrimary, letterSpacing: -1 },
  mcSub: { ...tabular, ...type.caption, marginTop: 4 },
  mcTrend: { flexDirection: 'row', alignItems: 'center', gap: 4, alignSelf: 'flex-start', paddingHorizontal: 10, paddingVertical: 4, borderRadius: radius.full, marginTop: spacing.sm },
  mcTrendText: { ...tabular, fontSize: 12, fontWeight: font.semibold },

  earnHead: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: 6 },
  earnLabel: { ...type.label, fontSize: 14, color: colors.textSecondary, fontWeight: font.medium },
  earnValue: { ...tabular, fontSize: 40, fontWeight: font.bold, color: colors.textPrimary, letterSpacing: -1 },
  earnNet: { ...tabular, ...type.caption, color: colors.textSecondary, marginTop: spacing.sm },
  chartCaption: { ...type.label, color: colors.textSecondary, fontWeight: font.semibold, marginBottom: spacing.sm },
  statRow: { flexDirection: 'row', alignItems: 'center', marginTop: spacing.md, backgroundColor: colors.bgSoft, borderRadius: radius.md, paddingVertical: 12 },
  statCell: { flex: 1, alignItems: 'center' },
  statDivider: { width: 1, alignSelf: 'stretch', marginVertical: 6, backgroundColor: colors.border },
  statVal: { ...tabular, fontSize: 17, fontWeight: font.bold, color: colors.textPrimary },
  statLbl: { ...type.small, fontSize: 11, color: colors.textSecondary, marginTop: 2, textAlign: 'center' },
  platWrap: { marginTop: spacing.lg, borderTopWidth: 1, borderTopColor: colors.border, paddingTop: spacing.md },
  platHead: { ...type.label, color: colors.textSecondary, fontWeight: font.semibold, marginBottom: 8 },
  platRow: { flexDirection: 'row', alignItems: 'center', gap: 10, paddingVertical: 7 },
  platName: { ...type.bodyMedium, fontSize: 14, flex: 1 },
  platMiles: { ...tabular, ...type.caption, color: colors.textTertiary },
  platVal: { ...tabular, fontSize: 14, fontWeight: font.bold, color: colors.textPrimary, minWidth: 64, textAlign: 'right' },
  rankBadge: { width: 22, height: 22, borderRadius: 11, backgroundColor: colors.bgSoft, alignItems: 'center', justifyContent: 'center' },
  rankBadgeTop: { backgroundColor: colors.brand },
  rankText: { ...tabular, fontSize: 12, fontWeight: font.bold, color: colors.textSecondary },
  zoneBorder: { borderTopWidth: 1, borderTopColor: colors.border },
  zoneSub: { ...type.caption, color: colors.textTertiary, marginTop: 1 },
  bestRow: { flexDirection: 'row', alignItems: 'center', gap: 12, paddingBottom: spacing.sm },
  bestBanner: { flexDirection: 'row', alignItems: 'center', gap: 12, backgroundColor: colors.amberLight, borderRadius: radius.md, padding: spacing.md, marginTop: spacing.sm },
  bestLabel: { ...type.bodyMedium, fontSize: 15 },
  bestSub: { ...type.caption, color: colors.textTertiary, marginTop: 1 },
  bestVal: { ...tabular, fontSize: 17, fontWeight: font.bold, color: colors.amberDark },
  dots: { flexDirection: 'row', justifyContent: 'center', gap: 5, marginTop: spacing.md },
  cdot: { width: 6, height: 6, borderRadius: 3, backgroundColor: colors.border },
  cdotOn: { backgroundColor: colors.brand, width: 18 },
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

  recGrid: { flexDirection: 'row', flexWrap: 'wrap' },
  recCell: { width: '33.33%', alignItems: 'center', paddingVertical: spacing.md, paddingHorizontal: 4 },
  recValue: { ...tabular, fontSize: 18, fontWeight: font.bold, color: colors.textPrimary, marginTop: 4, letterSpacing: -0.3 },
  recLabel: { ...type.small, color: colors.textSecondary, fontWeight: font.medium, textAlign: 'center', marginTop: 3, lineHeight: 14 },
  recSub: { ...type.small, fontSize: 10, color: colors.textTertiary, textAlign: 'center', marginTop: 1 },

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
