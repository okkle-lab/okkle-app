import React from 'react';
import { Alert, Linking, Switch, View, Text, ScrollView, StyleSheet, Pressable } from 'react-native';
import { useFocusEffect, useRouter } from 'expo-router';
import { Feather } from '@expo/vector-icons';
import { colors, font, spacing, radius, type, tabular } from '../../src/theme';
import { AiGlowPanel, Card, Chip, SectionHeader, HeatMapView, IconBadge, CollapsingHeader, SettingsGlassButton } from '../../src/components';
import { disableAutoTrip, enableAutoTrip, isAutoTripEnabled } from '../../src/autoTrip';
import { getUser, saveUser, kvGet, kvSet, getZoneStats, getHeatPoints, getEarningsByTimeOfDay, getBestSpot, getYearPnL, getPlatformStats, TIME_FILTERS, type ZoneStat, type TimeBucket, type HeatPoint, type TimeFilter, type BestSpot, type YearPnL, type PlatformStat } from '../../src/db';
import { fmtGbp, fmtMiles, fmtPerHour, fmtPerMile, fmtHours, fmtPct } from '../../src/db/tax';
import { syncReminders, WEEKDAYS } from '../../src/notifications';

type InsightsTab = 'where' | 'when' | 'money';
const TABS: { key: InsightsTab; label: string; icon: React.ComponentProps<typeof Feather>['name'] }[] = [
  { key: 'where', label: 'Where', icon: 'map-pin' },
  { key: 'when', label: 'When', icon: 'clock' },
  { key: 'money', label: 'Money', icon: 'trending-up' },
];

type LogFrequency = 'weekly' | 'monthly';
const DAY_LABELS: { [key: string]: string } = { sun: 'Sun', mon: 'Mon', tue: 'Tue', wed: 'Wed', thu: 'Thu', fri: 'Fri', sat: 'Sat' };

function userFrequency(): LogFrequency {
  return getUser()?.log_frequency === 'monthly' ? 'monthly' : 'weekly';
}

export default function InsightsScreen() {
  const router = useRouter();
  const [tab, setTab] = React.useState<InsightsTab>('where');
  const [filter, setFilter] = React.useState<TimeFilter>('all');
  const [zones, setZones] = React.useState<ZoneStat[]>([]);
  const [points, setPoints] = React.useState<HeatPoint[]>([]);
  const [buckets, setBuckets] = React.useState<TimeBucket[]>([]);
  const [best, setBest] = React.useState<BestSpot | null>(null);
  const [pnl, setPnl] = React.useState<YearPnL | null>(null);
  const [platforms, setPlatforms] = React.useState<PlatformStat[]>([]);
  const [autoTripOn, setAutoTripOn] = React.useState(isAutoTripEnabled);
  const [autoTripBusy, setAutoTripBusy] = React.useState(false);
  const [reminderOn, setReminderOn] = React.useState(() => (getUser()?.reminder_enabled ?? 1) === 1);
  const [reminderDay, setReminderDay] = React.useState(() => getUser()?.reminder_day ?? 'sun');
  const [frequency, setFrequency] = React.useState<LogFrequency>(userFrequency);
  const [deadlinesOn, setDeadlinesOn] = React.useState(() => (kvGet('deadline_reminders') ?? 'on') !== 'off');

  React.useEffect(() => {
    setZones(getZoneStats(filter));
    setPoints(getHeatPoints(filter));
  }, [filter]);

  React.useEffect(() => {
    setBuckets(getEarningsByTimeOfDay());
    setBest(getBestSpot());
    setPnl(getYearPnL());
    setPlatforms(getPlatformStats());
  }, []);

  useFocusEffect(React.useCallback(() => {
    const u = getUser();
    setAutoTripOn(isAutoTripEnabled());
    setReminderOn((u?.reminder_enabled ?? 1) === 1);
    setReminderDay(u?.reminder_day ?? 'sun');
    setFrequency(userFrequency());
    setDeadlinesOn((kvGet('deadline_reminders') ?? 'on') !== 'off');
  }, []));

  const anyEarnings = zones.some(z => z.earnings > 0);
  const anyPerHour = zones.some(z => z.perHour > 0);
  const maxPer = Math.max(...buckets.map(b => b.perHour), 1);
  const anyBucketEarnings = buckets.some(b => b.earnings > 0);
  const hasData = zones.length > 0 || buckets.some(b => b.trips > 0) || platforms.some(p => p.earnings > 0) || !!pnl?.hasData;

  async function persistReminders(next: Partial<{ reminderOn: boolean; reminderDay: string; frequency: LogFrequency; deadlinesOn: boolean }>) {
    const nextReminderOn = next.reminderOn ?? reminderOn;
    const nextReminderDay = next.reminderDay ?? reminderDay;
    const nextFrequency = next.frequency ?? frequency;
    const nextDeadlinesOn = next.deadlinesOn ?? deadlinesOn;
    kvSet('deadline_reminders', nextDeadlinesOn ? 'on' : 'off');
    saveUser({ reminder_enabled: nextReminderOn ? 1 : 0, reminder_day: nextReminderDay, log_frequency: nextFrequency });
    const updated = getUser();
    if (updated) await syncReminders(updated);
  }

  function updateReminderOn(next: boolean) {
    setReminderOn(next);
    persistReminders({ reminderOn: next }).catch(() => {});
  }

  function updateFrequency(next: LogFrequency) {
    setFrequency(next);
    persistReminders({ frequency: next }).catch(() => {});
  }

  function updateReminderDay(next: string) {
    setReminderDay(next);
    persistReminders({ reminderDay: next }).catch(() => {});
  }

  function updateDeadlinesOn(next: boolean) {
    setDeadlinesOn(next);
    persistReminders({ deadlinesOn: next }).catch(() => {});
  }

  async function toggleAutoTrip(next: boolean) {
    if (autoTripBusy) return;
    setAutoTripBusy(true);
    if (next) {
      const res = await enableAutoTrip();
      if (res.ok) {
        setAutoTripOn(true);
      } else if (res.reason === 'background') {
        Alert.alert(
          'Allow “Always”',
          'To nudge you while Okkle is closed, iOS needs location set to “Always”. Open Settings to change it.',
          [{ text: 'Not now' }, { text: 'Open Settings', onPress: () => Linking.openSettings() }],
        );
      } else if (res.reason === 'foreground') {
        Alert.alert('Location needed', 'Allow location access to detect when you start driving.');
      } else {
        Alert.alert('Couldn’t enable', 'Something went wrong turning this on. Please try again.');
      }
    } else {
      await disableAutoTrip();
      setAutoTripOn(false);
    }
    setAutoTripBusy(false);
  }

  return (
    <CollapsingHeader
      title="Insights"
      subtitle="AI guidance, smart nudges and patterns from your work."
      right={<SettingsGlassButton onPress={() => router.push('/settings')} />}
    >
        <AiGlowPanel style={[s.smartCard, s.hotspotTop]} contentStyle={s.smartContent}>
          <View style={s.smartHead}>
            <IconBadge icon="map" tone="mint" size={38} />
            <Text style={s.smartKicker}>Hotspot map</Text>
          </View>
          <Text style={s.smartTitle}>See where your work clusters</Text>
          <Text style={s.smartBody}>
            Okkle maps your saved GPS trips so you can spot the areas you keep returning to.
          </Text>
          {buckets.some(b => b.trips > 0) && (
            <ScrollView horizontal showsHorizontalScrollIndicator={false} style={s.filterScroll} contentContainerStyle={{ gap: 8, paddingRight: spacing.xl }}>
              {TIME_FILTERS.map(f => (
                <Pressable key={f.key} onPress={() => setFilter(f.key)} style={[s.filterChip, filter === f.key && s.filterChipOn]}>
                  <Text style={[s.filterText, filter === f.key && s.filterTextOn]}>{f.label}</Text>
                </Pressable>
              ))}
            </ScrollView>
          )}
          <View style={s.mapFrame}>
            <HeatMapView points={points} height={210} />
            <View style={s.legend}>
              <Text style={s.legendText}>Quieter</Text>
              <View style={s.legendBar}>
                {['#9BE3D2', '#5FD0BB', '#E7C66B', '#E0961F', '#E2604A'].map(c => (
                  <View key={c} style={[s.legendSwatch, { backgroundColor: c }]} />
                ))}
              </View>
              <Text style={s.legendText}>Busier</Text>
            </View>
            <Text style={s.note}>Where you drive, from your GPS trips. £ shading is estimated by spreading your logged pay across your trips. Built on-device — nothing leaves your phone.</Text>
          </View>
        </AiGlowPanel>

        <AiGlowPanel style={s.smartCard} contentStyle={s.smartContent}>
          <View style={s.smartHead}>
            <IconBadge icon="navigation" tone="blue" size={38} />
            <Text style={s.smartKicker}>Trip nudges</Text>
          </View>
          <Text style={s.smartTitle}>Never forget to track a trip</Text>
          <Text style={s.smartBody}>
            Okkle watches both ends of your trip. When it senses you’ve started driving it nudges you to start tracking, then reminds you to end and save your miles once you’ve stopped.
          </Text>
          <View style={s.toggleRow}>
            <View style={s.toggleCopy}>
              <Text style={s.toggleTitle}>Trip nudges</Text>
              <Text style={s.toggleSub}>{autoTripOn ? 'On' : 'Off'}</Text>
            </View>
            <Switch value={autoTripOn} onValueChange={toggleAutoTrip} disabled={autoTripBusy} trackColor={{ true: colors.brand, false: colors.borderStrong }} />
          </View>
          <View style={s.noticeRow}>
            <Feather name="alert-circle" size={16} color={colors.amberDark} />
            <Text style={s.noticeText}>Detection is a prompt, not auto-logging. Nothing is recorded until you confirm.</Text>
          </View>
        </AiGlowPanel>

        <AiGlowPanel style={s.smartCard} contentStyle={s.smartContent}>
          <View style={s.smartHead}>
            <IconBadge icon="bell" tone="violet" size={38} />
            <Text style={s.smartKicker}>Reminders</Text>
          </View>
          <Text style={s.smartTitle}>Keep your records fresh</Text>
          <View style={s.toggleRow}>
            <View style={s.toggleCopy}>
              <Text style={s.toggleTitle}>Logging reminder</Text>
              <Text style={s.toggleSub}>A nudge to log your miles and earnings</Text>
            </View>
            <Switch value={reminderOn} onValueChange={updateReminderOn} trackColor={{ true: colors.brand, false: colors.borderStrong }} />
          </View>
          {reminderOn && (
            <>
              <View style={s.fieldGroup}>
                <Text style={s.fieldLabel}>Frequency</Text>
                <View style={s.chips}>
                  <Chip label="Weekly" selected={frequency === 'weekly'} onPress={() => updateFrequency('weekly')} />
                  <Chip label="Monthly" selected={frequency === 'monthly'} onPress={() => updateFrequency('monthly')} />
                </View>
              </View>
              <View style={s.fieldGroup}>
                <Text style={s.fieldLabel}>Reminder day</Text>
                <View style={s.chips}>
                  {WEEKDAYS.map(day => (
                    <Chip key={day} label={DAY_LABELS[day]} selected={reminderDay === day} onPress={() => updateReminderDay(day)} />
                  ))}
                </View>
              </View>
            </>
          )}
          <View style={s.divider} />
          <View style={s.toggleRow}>
            <View style={s.toggleCopy}>
              <Text style={s.toggleTitle}>Tax deadline reminders</Text>
              <Text style={s.toggleSub}>Self Assessment, payment and MTD dates</Text>
            </View>
            <Switch value={deadlinesOn} onValueChange={updateDeadlinesOn} trackColor={{ true: colors.brand, false: colors.borderStrong }} />
          </View>
          <Pressable onPress={() => router.push('/key-dates')} style={({ pressed }) => [s.linkRow, pressed && { opacity: 0.65 }]}>
            <View style={s.toggleCopy}>
              <Text style={s.toggleTitle}>Key tax dates</Text>
              <Text style={s.toggleSub}>View HMRC deadlines and add to calendar</Text>
            </View>
            <Feather name="chevron-right" size={20} color={colors.textTertiary} />
          </Pressable>
        </AiGlowPanel>

        {/* Headline takeaway — always visible above the categories */}
        {best && (
          <View style={[s.tip, { marginBottom: spacing.lg }]}>
            <IconBadge icon="zap" tone="amber" size={38} />
            <View style={{ flex: 1 }}>
              <Text style={s.tipText}>
                You earn most around <Text style={s.tipStrong}>{best.zone}</Text> on <Text style={s.tipStrong}>{best.timeLabel}</Text>
              </Text>
              <Text style={s.tipRate}>
                {fmtPerHour(best.perHour)}
                {best.vsAverage >= 0.5 ? ` · £${best.vsAverage.toFixed(2)}/h above your average` : ` · ${best.trips} ${best.trips === 1 ? 'trip' : 'trips'}`}
              </Text>
            </View>
          </View>
        )}

        {/* Category switcher — one focused view at a time, not one long scroll */}
        {hasData && (
          <View style={s.tabs}>
            {TABS.map(t => (
              <Pressable key={t.key} onPress={() => setTab(t.key)} style={[s.tabItem, tab === t.key && s.tabItemOn]}>
                <Feather name={t.icon} size={14} color={tab === t.key ? colors.brandDeep : colors.textSecondary} />
                <Text style={[s.tabText, tab === t.key && s.tabTextOn]}>{t.label}</Text>
              </Pressable>
            ))}
          </View>
        )}

        {/* WHERE — hotspots + ranked areas */}
        {hasData && tab === 'where' && (
          <>
            {zones.length > 0 && (
              <Card style={{ padding: 0, overflow: 'hidden' }}>
                {zones.slice(0, 6).map((z, i, arr) => (
                  <View key={z.zone} style={[s.row, i < arr.length - 1 && s.rowBorder]}>
                    <View style={[s.rank, i === 0 && { backgroundColor: colors.brand }]}>
                      <Text style={[s.rankText, i === 0 && { color: '#fff' }]}>{i + 1}</Text>
                    </View>
                    <View style={{ flex: 1 }}>
                      <Text style={s.zoneName}>{z.zone}</Text>
                      <Text style={s.zoneSub}>
                        {z.trips} {z.trips === 1 ? 'trip' : 'trips'} · {fmtMiles(z.miles)}{z.earnings > 0 ? ` · ${fmtGbp(z.earnings)}` : ''}
                      </Text>
                    </View>
                    <Text style={s.zoneVal}>{anyPerHour ? fmtPerHour(z.perHour) : anyEarnings ? fmtGbp(z.earnings) : fmtMiles(z.miles)}</Text>
                  </View>
                ))}
              </Card>
            )}
          </>
        )}

        {/* WHEN — best times */}
        {hasData && tab === 'when' && (
          <Card>
            {buckets.some(b => b.trips > 0) ? buckets.map(b => {
              const ref = anyBucketEarnings ? b.perHour : b.trips;
              const max = anyBucketEarnings ? maxPer : Math.max(...buckets.map(x => x.trips), 1);
              const pct = max > 0 ? (ref / max) * 100 : 0;
              return (
                <View key={b.label} style={s.heatRow}>
                  <Text style={s.heatLabel}>{b.label}</Text>
                  <View style={s.heatTrack}><View style={[s.heatFill, { width: `${Math.max(4, pct)}%`, opacity: 0.35 + (pct / 100) * 0.65 }]} /></View>
                  <Text style={s.heatVal}>{anyBucketEarnings ? `£${b.perHour.toFixed(0)}/h` : `${b.trips}`}</Text>
                </View>
              );
            }) : <Text style={s.emptyInline}>Track a few trips and your best hours will appear here.</Text>}
          </Card>
        )}
        {hasData && tab === 'when' && anyBucketEarnings && (
          <Text style={s.note}>£/hour is estimated — your logged pay is credited to the hours you actually drove, and waiting time counts against them. Improves as you track more trips.</Text>
        )}

        {/* MONEY — platform ranking + business P&L */}
        {hasData && tab === 'money' && (
          <>
            {platforms.some(p => p.earnings > 0) && (
              <View>
                <SectionHeader icon="award" title="Which platform pays most?" />
                <Card style={{ padding: 0, overflow: 'hidden' }}>
                  {platforms.filter(p => p.earnings > 0).sort((a, b) => b.earnings - a.earnings).map((p, i, arr) => (
                    <View key={p.platform} style={[s.row, i < arr.length - 1 && s.rowBorder]}>
                      <View style={[s.rank, i === 0 && { backgroundColor: colors.brand }]}>
                        <Text style={[s.rankText, i === 0 && { color: '#fff' }]}>{i + 1}</Text>
                      </View>
                      <View style={{ flex: 1 }}>
                        <Text style={s.zoneName}>{p.platform}</Text>
                      </View>
                      <Text style={[s.zoneVal, i === 0 && { color: colors.green }]}>{fmtGbp(p.earnings)}</Text>
                    </View>
                  ))}
                </Card>
                <Text style={s.note}>Total pay you’ve logged per app. £/hour can’t be split per app when you multi-app, so it’s shown across all apps below.</Text>
              </View>
            )}
            {pnl?.hasData && (
              <View style={{ marginTop: spacing.lg }}>
                <SectionHeader icon="bar-chart-2" title="Your business this year" />
                <Card>
                  <PnlRow label="Net pay / hour (after tax)" value={pnl.hours > 0 ? fmtPerHour(pnl.netPerHour) : '—'} bold />
                  <PnlRow label="Gross pay / hour" value={pnl.hours > 0 ? fmtPerHour(pnl.grossPerHour) : '—'} />
                  <PnlRow label="Earnings / mile" value={fmtPerMile(pnl.perMile)} />
                  <PnlRow label="Margin kept after tax" value={fmtPct(pnl.marginPct)} />
                  <PnlRow label="Hours worked" value={fmtHours(pnl.hours)} last />
                </Card>
              </View>
            )}
            {!platforms.some(p => p.earnings > 0) && !pnl?.hasData && (
              <Card><Text style={s.emptyInline}>Log your pay per platform in the Log tab to see which app pays most and your business stats.</Text></Card>
            )}
          </>
        )}
    </CollapsingHeader>
  );
}

function PnlRow({ label, value, bold, last }: { label: string; value: string; bold?: boolean; last?: boolean }) {
  return (
    <View style={[s.pnlRow, !last && s.rowBorder]}>
      <Text style={[s.pnlLabel, bold && { color: colors.textPrimary, fontWeight: font.medium }]}>{label}</Text>
      <Text style={[s.pnlValue, bold && { fontWeight: font.bold, color: colors.brandDeep }]}>{value}</Text>
    </View>
  );
}

const s = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  pnlRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', paddingVertical: 10 },
  pnlLabel: { fontSize: 15, color: colors.textSecondary, flex: 1, paddingRight: spacing.md },
  pnlValue: { ...tabular, fontSize: 15, fontWeight: font.medium, color: colors.textPrimary },
  smartCard: { marginBottom: spacing.lg, borderCurve: 'continuous' },
  smartContent: { gap: spacing.md },
  smartHead: { flexDirection: 'row', alignItems: 'center', gap: 10 },
  smartKicker: { ...type.label, color: '#6D5DF6', fontWeight: font.bold, textTransform: 'uppercase', letterSpacing: 0.5 },
  smartTitle: { ...type.heading, fontSize: 20, lineHeight: 25 },
  smartBody: { ...type.caption, color: colors.textSecondary, lineHeight: 19 },
  toggleRow: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: spacing.md },
  toggleCopy: { flex: 1, minWidth: 0 },
  toggleTitle: { ...type.bodyMedium, fontSize: 15 },
  toggleSub: { ...type.caption, marginTop: 2, lineHeight: 18 },
  noticeRow: { flexDirection: 'row', alignItems: 'flex-start', gap: 8, padding: spacing.md, borderRadius: radius.md, backgroundColor: colors.amberLight },
  noticeText: { ...type.caption, color: colors.amberDark, lineHeight: 18, flex: 1 },
  fieldGroup: { gap: spacing.sm },
  fieldLabel: { ...type.label },
  chips: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm },
  divider: { height: 1, backgroundColor: colors.border },
  linkRow: { flexDirection: 'row', alignItems: 'center', gap: spacing.md, paddingVertical: spacing.xs },
  hotspotTop: { marginBottom: spacing.lg },
  mapFrame: { padding: spacing.sm, borderRadius: radius.lg, backgroundColor: colors.bgCard, borderWidth: 1, borderColor: colors.border },

  tip: { flexDirection: 'row', gap: 12, alignItems: 'center', backgroundColor: colors.brandLight, borderRadius: radius.md, padding: spacing.md, marginBottom: spacing.sm },
  tipText: { ...type.body, fontSize: 15, color: colors.textPrimary, lineHeight: 21 },
  tipStrong: { fontWeight: font.bold, color: colors.brandDeep },
  tipRate: { ...type.bodyMedium, ...tabular, color: colors.brandDeep, marginTop: 3 },

  tabs: { flexDirection: 'row', backgroundColor: colors.bgSoft, borderRadius: radius.lg, padding: 4, marginBottom: spacing.lg },
  tabItem: { flex: 1, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', gap: 4, paddingVertical: 9, paddingHorizontal: 2, borderRadius: radius.md },
  tabItemOn: { backgroundColor: colors.bgCard, shadowColor: '#000', shadowOpacity: 0.06, shadowRadius: 4, shadowOffset: { width: 0, height: 1 }, elevation: 1 },
  tabText: { fontSize: 13, fontWeight: font.medium, color: colors.textSecondary },
  tabTextOn: { color: colors.textPrimary, fontWeight: font.semibold },
  emptyInline: { ...type.caption, textAlign: 'center', paddingVertical: spacing.md, lineHeight: 19 },

  filterScroll: { marginBottom: spacing.lg, marginHorizontal: -spacing.xl, paddingHorizontal: spacing.xl },
  filterChip: { paddingHorizontal: 16, paddingVertical: 9, borderRadius: radius.full, borderWidth: 1.5, borderColor: colors.border, backgroundColor: colors.bgCard },
  filterChipOn: { backgroundColor: colors.brand, borderColor: colors.brand },
  filterText: { fontSize: 14, fontWeight: font.medium, color: colors.textSecondary },
  filterTextOn: { color: '#fff' },

  legend: { flexDirection: 'row', alignItems: 'center', gap: 8, marginTop: spacing.md, paddingHorizontal: spacing.sm },
  legendText: { ...type.small },
  legendBar: { flexDirection: 'row', flex: 1, height: 8, borderRadius: radius.full, overflow: 'hidden' },
  legendSwatch: { flex: 1, height: '100%' },
  note: { ...type.small, lineHeight: 17, marginTop: 10, paddingHorizontal: spacing.sm },

  row: { flexDirection: 'row', alignItems: 'center', padding: spacing.lg, gap: spacing.md },
  rowBorder: { borderBottomWidth: 1, borderBottomColor: colors.border },
  rank: { width: 26, height: 26, borderRadius: 13, backgroundColor: colors.bgSoft, alignItems: 'center', justifyContent: 'center' },
  rankText: { ...tabular, fontSize: 13, fontWeight: font.bold, color: colors.textSecondary },
  zoneName: { ...type.bodyMedium, fontSize: 15 },
  zoneSub: { ...type.caption, marginTop: 2 },
  zoneVal: { ...tabular, fontSize: 15, fontWeight: font.semibold, color: colors.brandDeep },

  heatRow: { flexDirection: 'row', alignItems: 'center', paddingVertical: 7, gap: 10 },
  heatLabel: { ...type.caption, color: colors.textSecondary, width: 70 },
  heatTrack: { flex: 1, height: 14, backgroundColor: colors.bgSoft, borderRadius: radius.full, overflow: 'hidden' },
  heatFill: { height: '100%', backgroundColor: colors.brand, borderRadius: radius.full },
  heatVal: { ...type.caption, ...tabular, color: colors.textPrimary, width: 56, textAlign: 'right', fontWeight: font.medium },
});
