import React, { useCallback } from 'react';
import { View, Text, ScrollView, StyleSheet, RefreshControl, Pressable, Modal, Dimensions, Animated, useColorScheme } from 'react-native';
import { useFocusEffect, useRouter } from 'expo-router';
import { Feather } from '@expo/vector-icons';
import { colors, font, spacing, radius, type } from '../../src/theme';
import { Card, SectionHeader, CountUp, Medal, IconBadge, GradientCard, CollapsingHeader, AnimatedDots, CoachMarks, SettingsGlassButton, GlassPanel, type CoachStep } from '../../src/components';
import {
  getUser,
  getTaxYearSummary,
  getStreak, getAchievements, popNewAchievements, getWeeklyChallenges,
  kvGet, kvSet,
  type Achievement,
  type Challenge,
} from '../../src/db';
import { fmtGbp, fmtMiles, taxYearLabel } from '../../src/db/tax';
import { tabular } from '../../src/theme';

type FeatherName = React.ComponentProps<typeof Feather>['name'];

function flatGoalTone(tone: string, isDark: boolean) {
  switch (tone) {
    case 'green':
      return { bg: colors.greenLight, fg: colors.green };
    case 'amber':
      return { bg: colors.amberLight, fg: colors.amberDark };
    case 'blue':
      return { bg: isDark ? '#14233A' : '#E8F1FF', fg: isDark ? '#8DB7F1' : '#2563EB' };
    case 'red':
      return { bg: colors.redLight, fg: colors.red };
    case 'violet':
      return { bg: isDark ? '#2B1D3F' : '#F1E8FF', fg: isDark ? '#C29CF0' : '#7C3AED' };
    case 'mint':
      return { bg: colors.brandLight, fg: colors.brandDeep };
    default:
      return { bg: colors.bgSoft, fg: colors.textSecondary };
  }
}

function FlatGoalIcon({ icon, tone, isDark, size = 36 }: { icon: FeatherName; tone: string; isDark: boolean; size?: number }) {
  const t = flatGoalTone(tone, isDark);
  return (
    <View style={[s.flatGoalIcon, { width: size, height: size, borderRadius: size / 2, backgroundColor: t.bg }]}>
      <Feather name={icon} size={size * 0.48} color={t.fg} />
    </View>
  );
}

export default function HomeScreen() {
  const router = useRouter();
  const win = Dimensions.get('window');
  const isDark = useColorScheme() === 'dark';
  const heroColors: [string, string, string] = isDark
    ? ['#1A2420', '#123B34', '#071310']
    : ['#FFFFFF', '#E9FAF6', '#BDEFE5'];
  const heroAccent = isDark ? colors.brandMid : colors.brandDeep;
  const [year, setYear] = React.useState({ miles: 0, deduction: 0, taxSaved: 0, earnings: 0, taxRate: 0.2 });
  const [user, setUser] = React.useState(getUser());
  const [streak, setStreak] = React.useState(0);
  const [achievements, setAchievements] = React.useState<Achievement[]>([]);
  const [newAch, setNewAch] = React.useState<Achievement | null>(null);
  const [challenges, setChallenges] = React.useState<Challenge[]>([]);
  const [refreshing, setRefreshing] = React.useState(false);
  const gameScrollX = React.useRef(new Animated.Value(0)).current;

  // First-run tour — centred cards, one per bottom tab. We don't spotlight the
  // native tab bar: the tour renders as a Modal over it, so a highlight there
  // would show an empty box rather than the tab. Cards keep it clean.
  const [showCoach, setShowCoach] = React.useState(false);
  useFocusEffect(useCallback(() => {
    if (getUser()?.onboarded && !kvGet('coach_seen')) {
      const t = setTimeout(() => setShowCoach(true), 650);
      return () => clearTimeout(t);
    }
  }, []));
  const coachSteps: CoachStep[] = [
    { title: 'Welcome to Okkle 👋', body: 'Track your delivery miles and money in one place — and see exactly what you keep after tax. Here’s the 20-second tour of the five tabs along the bottom.' },
    { title: '👤  Home', body: 'Your tax saved this year and your progress live here — simple, focused and easy to check at a glance.' },
    { title: '💡  Insights', body: 'Okkle spots your best zones, hours and platforms from your own trips as your data grows.' },
    { title: '🧭  Trip', body: 'Tap Start before you set off. GPS turns your distance into a tax-free mileage deduction — automatically, nothing to write down.' },
    { title: '✍️  Log', body: 'Add your weekly pay and any costs — fuel, parking, phone. Snap a receipt and Okkle reads the amount for you.' },
    { title: '🗄  Records', body: 'Everything you’ve logged, plus your tax estimate and accountant exports, in one place.' },
  ];
  function dismissCoach() { kvSet('coach_seen', 1); setShowCoach(false); }

  function load() {
    setYear(getTaxYearSummary());
    setUser(getUser());

    // Gamification: streak, badges, and a celebration for anything new.
    setStreak(getStreak());
    setAchievements(getAchievements());
    setChallenges(getWeeklyChallenges());
    const fresh = popNewAchievements();
    if (fresh.length) setNewAch(fresh[0]);
  }

  useFocusEffect(useCallback(() => { load(); }, []));

  function onRefresh() { setRefreshing(true); load(); setRefreshing(false); }

  // Home preview: show unlocked first, then those closest to unlocking.
  const achievementPreview = [...achievements]
    .sort((a, b) => (Number(b.unlocked) - Number(a.unlocked)) || (b.progress - a.progress))
    .slice(0, 12);
  // The next medals you're closest to earning — fills the medals card with a goal.
  const nextLocked = [...achievements]
    .filter(a => !a.unlocked && a.progress > 0)
    .sort((a, b) => b.progress - a.progress)
    .slice(0, 2);

  return (
    <>
    <CoachMarks steps={coachSteps} visible={showCoach} onDone={dismissCoach} />
    <Modal visible={newAch !== null} transparent animationType="fade" onRequestClose={() => setNewAch(null)}>
      <Pressable style={s.modalBg} onPress={() => setNewAch(null)}>
        <GlassPanel
          tone="amber"
          radius={32}
          isInteractive
          style={s.modalCard}
          clipStyle={s.modalCardClip}
          contentStyle={s.modalCardContent}
        >
          {newAch && <Medal icon={newAch.icon as any} category={newAch.category} tier={newAch.tier} unlocked size={104} />}
          <Text style={s.achKicker}>Medal unlocked</Text>
          <Text style={s.modalTitle}>{newAch?.label}</Text>
          <Text style={s.modalBody}>{newAch?.desc}</Text>
          <Pressable onPress={() => setNewAch(null)} style={s.modalBtn}><Text style={s.modalBtnText}>Nice!</Text></Pressable>
        </GlassPanel>
      </Pressable>
    </Modal>
    <CollapsingHeader
      title={user?.name || 'Hi'}
      right={
        <SettingsGlassButton onPress={() => router.push('/settings')} />
      }
      refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={colors.brand} />}
    >
      {/* HERO: tax saved — tap through to the full Tax breakdown */}
      <Pressable onPress={() => router.push({ pathname: '/(tabs)/records', params: { view: 'tax' } })} style={({ pressed }) => [s.heroPressable, isDark && s.heroPressableDark, pressed && { opacity: 0.94 }]}>
        <GradientCard colors={heroColors} radius={radius.xl} style={[s.hero, isDark && s.heroDark]}>
          <View style={s.heroTop}>
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 6 }}>
              <Feather name="trending-up" size={15} color={heroAccent} />
              <Text style={[s.heroLabel, isDark && s.heroLabelDark]}>Tax saved this year</Text>
            </View>
          </View>
          <CountUp value={year.taxSaved} prefix="£" style={s.heroValue} />
          <Text style={s.heroSub}>
            from {fmtMiles(year.miles)} · {fmtGbp(year.deduction)} mileage deduction
          </Text>
          <View style={[s.heroChip, isDark && s.heroChipDark]}>
            <Text style={[s.heroChipText, isDark && s.heroChipTextDark]}>Tax year {taxYearLabel()} · see breakdown</Text>
          </View>
        </GradientCard>
      </Pressable>

      {/* Progress — goals + medals combined into one swipeable card */}
      {(achievements.length > 0 || challenges.length > 0) && (
        <View style={s.progressSection}>
          <View style={s.progressHead}>
            <SectionHeader icon="zap" title="Progress" />
            <Pressable onPress={() => router.push('/medals')} hitSlop={8} style={{ flexDirection: 'row', alignItems: 'center', gap: 2 }}>
              <Text style={s.seeAll}>See all</Text>
              <Feather name="chevron-right" size={15} color={colors.brandDeep} />
            </Pressable>
          </View>
          <Animated.ScrollView
            horizontal pagingEnabled showsHorizontalScrollIndicator={false}
            scrollEventThrottle={16}
            onScroll={Animated.event([{ nativeEvent: { contentOffset: { x: gameScrollX } } }], { useNativeDriver: true })}
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
                    <FlatGoalIcon icon={c.done ? 'check' : (c.icon as FeatherName)} tone={c.done ? 'green' : c.tone} isDark={isDark} />
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
                  {nextLocked.length > 0 && (
                    <View style={s.nextWrap}>
                      <Text style={s.nextHead}>Closest to unlocking</Text>
                      {nextLocked.map(a => (
                        <View key={a.key} style={s.nextRow}>
                          <Medal icon={a.icon as any} category={a.category} tier={a.tier} unlocked={false} size={30} />
                          <View style={{ flex: 1, gap: 6 }}>
                            <View style={s.challTop}>
                              <Text style={s.nextLabel} numberOfLines={1}>{a.label}</Text>
                              <Text style={s.challProg}>{Math.round(a.progress * 100)}%</Text>
                            </View>
                            <View style={s.challTrack}>
                              <View style={[s.challFill, { width: `${Math.round(a.progress * 100)}%`, backgroundColor: colors.brandMid }]} />
                            </View>
                          </View>
                        </View>
                      ))}
                    </View>
                  )}
                </Card>
              </Pressable>
            </View>
          </Animated.ScrollView>
          <AnimatedDots scrollX={gameScrollX} count={2} pageWidth={win.width} />
        </View>
      )}

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
  streakChip: { flexDirection: 'row', alignItems: 'center', gap: 4, paddingHorizontal: 10, paddingVertical: 5, borderRadius: radius.full, marginRight: 6 },
  streakChipOn: { backgroundColor: colors.amberLight },
  streakChipOff: { backgroundColor: colors.bgSoft },
  streakChipText: { ...tabular, fontSize: 14, fontWeight: font.bold, color: colors.amber },

  heroPressable: {
    marginBottom: spacing.lg,
    borderRadius: radius.xl,
    boxShadow: '0 18px 34px rgba(14,142,120,0.14), 0 7px 14px rgba(21,33,29,0.08), -8px -8px 18px rgba(255,255,255,0.92)',
  },
  heroPressableDark: {
    boxShadow: '0 18px 34px rgba(0,0,0,0.34), 0 7px 14px rgba(0,0,0,0.26)',
  },
  hero: { padding: spacing.xl, borderWidth: 1, borderColor: 'rgba(255,255,255,0.9)' },
  heroDark: { borderColor: 'rgba(127,214,197,0.28)' },
  heroTop: { flexDirection: 'row', alignItems: 'center' },
  heroLabel: { color: colors.brandDeep, fontSize: 14, fontWeight: font.semibold },
  heroLabelDark: { color: colors.brandMid },
  heroValue: { ...tabular, color: colors.textPrimary, fontSize: 44, fontWeight: font.bold, letterSpacing: 0, marginTop: 8 },
  heroSub: { color: colors.textSecondary, fontSize: 13, marginTop: 4 },
  heroChip: {
    alignSelf: 'flex-start', backgroundColor: 'rgba(255,255,255,0.64)', borderWidth: 1, borderColor: 'rgba(255,255,255,0.86)',
    paddingHorizontal: 12, paddingVertical: 5, borderRadius: radius.full, marginTop: spacing.md,
  },
  heroChipDark: { backgroundColor: 'rgba(127,214,197,0.12)', borderColor: 'rgba(127,214,197,0.24)' },
  heroChipText: { color: colors.brandDeep, fontSize: 12, fontWeight: font.semibold },
  heroChipTextDark: { color: colors.brandMid },

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

  modalBg: { flex: 1, backgroundColor: 'rgba(15,28,25,0.32)', alignItems: 'center', justifyContent: 'center', padding: spacing.xl },
  modalCard: { width: '100%', maxWidth: 340, borderCurve: 'continuous' },
  modalCardClip: { backgroundColor: 'transparent', borderCurve: 'continuous' },
  modalCardContent: { padding: spacing.xl, alignItems: 'center' },
  modalEmoji: { fontSize: 56, marginBottom: spacing.md },
  modalTitle: { ...type.screenTitle, marginBottom: spacing.sm },
  modalBody: { ...type.body, color: colors.textSecondary, textAlign: 'center', lineHeight: 23, marginBottom: spacing.xl },
  modalBtn: { backgroundColor: colors.brand, borderRadius: radius.lg, paddingVertical: 14, paddingHorizontal: spacing.xl, alignSelf: 'stretch', alignItems: 'center' },
  modalBtnText: { color: '#fff', fontSize: 16, fontWeight: font.semibold },
  achBurst: { width: 72, height: 72, borderRadius: 36, backgroundColor: colors.brand, alignItems: 'center', justifyContent: 'center', marginBottom: spacing.md },
  achKicker: { ...type.label, color: colors.brandDeep, textTransform: 'uppercase', letterSpacing: 0.5, fontSize: 12, marginBottom: 4 },

  progressHead: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  progressSection: { marginTop: spacing.md },
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
  flatGoalIcon: { alignItems: 'center', justifyContent: 'center' },
  challEmoji: { width: 38, height: 38, borderRadius: 19, backgroundColor: colors.bgSoft, alignItems: 'center', justifyContent: 'center' },
  challTop: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', gap: 8 },
  challLabel: { ...type.bodyMedium, fontSize: 14, flex: 1 },
  challProg: { ...type.small, ...tabular },
  challTrack: { height: 6, borderRadius: radius.full, backgroundColor: colors.bgSoft, overflow: 'hidden' },
  challFill: { height: '100%', backgroundColor: colors.brand, borderRadius: radius.full },
  nextWrap: { marginTop: spacing.lg, borderTopWidth: 1, borderTopColor: colors.border, paddingTop: spacing.md, gap: spacing.sm },
  nextHead: { ...type.label, color: colors.textSecondary, fontWeight: font.semibold },
  nextRow: { flexDirection: 'row', alignItems: 'center', gap: 10 },
  nextLabel: { ...type.bodyMedium, fontSize: 14, flex: 1 },
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
