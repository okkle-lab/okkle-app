import React from 'react';
import { View, Text, ScrollView, StyleSheet, Pressable, Alert, Linking } from 'react-native';
import { useFocusEffect, useRouter } from 'expo-router';
import { Feather } from '@expo/vector-icons';
import { colors, font, spacing, radius, type, tabular } from '../../src/theme';
import { Card, SectionHeader, HeatMapView, IconBadge, CollapsingHeader, SettingsGlassButton } from '../../src/components';
import * as Location from 'expo-location';
import { getZoneStats, getHeatPoints, getEarningsByTimeOfDay, getBestSpot, getYearPnL, getPlatformStats, getHotspotCells, getUser, saveUser, kvGet, kvSet, TIME_FILTERS, type ZoneStat, type TimeBucket, type HeatPoint, type TimeFilter, type BestSpot, type YearPnL, type PlatformStat, type HotspotCell } from '../../src/db';
import { fmtGbp, fmtMiles, fmtPerHour, fmtPerMile, fmtHours, fmtPct } from '../../src/db/tax';
import { enableAutoTrip, isAutoTripEnabled } from '../../src/autoTrip';
import { syncReminders } from '../../src/notifications';

type InsightsTab = 'where' | 'when' | 'money';
const TABS: { key: InsightsTab; label: string; icon: React.ComponentProps<typeof Feather>['name'] }[] = [
  { key: 'where', label: 'Where', icon: 'map-pin' },
  { key: 'when', label: 'When', icon: 'clock' },
  { key: 'money', label: 'Money', icon: 'trending-up' },
];

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
  const [hotspots, setHotspots] = React.useState<HotspotCell[]>([]);
  const [cellNames, setCellNames] = React.useState<Record<string, string>>({});
  // Optional automations the user can switch on right here. Hidden once enabled.
  const [nudgesOn, setNudgesOn] = React.useState(isAutoTripEnabled());
  const [remindersOn, setRemindersOn] = React.useState((getUser()?.reminder_enabled ?? 1) === 1);
  const [setupBusy, setSetupBusy] = React.useState(false);
  // Bumped each time the tab regains focus so the view scrolls back to the top.
  const [scrollResetKey, setScrollResetKey] = React.useState(0);

  React.useEffect(() => {
    setZones(getZoneStats(filter));
    setPoints(getHeatPoints(filter));
    setHotspots(getHotspotCells(filter));
  }, [filter]);

  // Reverse-geocode each hotspot cell's centroid to a friendly name, cached in
  // kv so it's a one-time lookup per area (no repeated geocoding).
  React.useEffect(() => {
    let cancelled = false;
    (async () => {
      const names: Record<string, string> = {};
      for (const c of hotspots) {
        const cached = kvGet(`cellname_${c.key}`);
        if (cached) { names[c.key] = cached; continue; }
        try {
          const places = await Location.reverseGeocodeAsync({ latitude: c.lat, longitude: c.lng });
          const pl: any = places[0] ?? {};
          const local = pl.subLocality || pl.district || pl.city || pl.name;
          const outward = pl.postalCode ? String(pl.postalCode).split(' ')[0] : '';
          const label = [local, outward].filter(Boolean).join(' · ') || 'Busy area';
          kvSet(`cellname_${c.key}`, label);
          names[c.key] = label;
        } catch { names[c.key] = 'Busy area'; }
      }
      if (!cancelled) setCellNames(prev => ({ ...prev, ...names }));
    })();
    return () => { cancelled = true; };
  }, [hotspots]);

  useFocusEffect(React.useCallback(() => {
    setBuckets(getEarningsByTimeOfDay());
    setBest(getBestSpot());
    setPnl(getYearPnL());
    setPlatforms(getPlatformStats());
    setZones(getZoneStats(filter));
    setPoints(getHeatPoints(filter));
    setHotspots(getHotspotCells(filter));
    setNudgesOn(isAutoTripEnabled());
    setRemindersOn((getUser()?.reminder_enabled ?? 1) === 1);
    setScrollResetKey(k => k + 1);
  }, [filter]));

  async function enableNudges() {
    if (setupBusy) return;
    setSetupBusy(true);
    const res = await enableAutoTrip();
    if (res.ok) {
      setNudgesOn(true);
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
    setSetupBusy(false);
  }

  async function enableReminders() {
    if (setupBusy) return;
    setSetupBusy(true);
    try {
      saveUser({ reminder_enabled: 1 });
      const u = getUser();
      if (u) await syncReminders(u);
      setRemindersOn(true);
    } catch {
      Alert.alert('Couldn’t enable', 'Something went wrong turning this on. Please try again.');
    }
    setSetupBusy(false);
  }

  const anyEarnings = zones.some(z => z.earnings > 0);
  const anyPerHour = zones.some(z => z.perHour > 0);
  const anyHotspotEarnings = hotspots.some(c => c.earnings > 0);
  const maxPer = Math.max(...buckets.map(b => b.perHour), 1);
  const anyBucketEarnings = buckets.some(b => b.earnings > 0);
  const hasData = zones.length > 0 || hotspots.length > 0 || buckets.some(b => b.trips > 0) || platforms.some(p => p.earnings > 0) || !!pnl?.hasData;

  return (
    <CollapsingHeader
      title="Insights"
      subtitle="Where, when and what pays — patterns from your work."
      right={<SettingsGlassButton onPress={() => router.push('/settings')} />}
      resetScrollKey={scrollResetKey}
    >
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

        {/* Category switcher — one focused view at a time, not one long scroll.
            Always shown so the live hotspot map is reachable before any trips. */}
        {(
          <View style={s.tabs}>
            {TABS.map(t => (
              <Pressable key={t.key} onPress={() => setTab(t.key)} style={[s.tabItem, tab === t.key && s.tabItemOn]}>
                <Feather name={t.icon} size={14} color={tab === t.key ? colors.brandDeep : colors.textSecondary} />
                <Text style={[s.tabText, tab === t.key && s.tabTextOn]}>{t.label}</Text>
              </Pressable>
            ))}
          </View>
        )}

        {/* WHERE — live hotspot map (always), plus ranked areas once there's data */}
        {tab === 'where' && (
          <>
            {buckets.some(b => b.trips > 0) && (
              <ScrollView horizontal showsHorizontalScrollIndicator={false} style={s.filterScroll} contentContainerStyle={{ gap: 8, paddingRight: spacing.xl }}>
                {TIME_FILTERS.map(f => (
                  <Pressable key={f.key} onPress={() => setFilter(f.key)} style={[s.filterChip, filter === f.key && s.filterChipOn]}>
                    <Text style={[s.filterText, filter === f.key && s.filterTextOn]}>{f.label}</Text>
                  </Pressable>
                ))}
              </ScrollView>
            )}
            {hotspots.length > 0 && (
              <>
                <Card style={{ padding: 0, overflow: 'hidden' }}>
                  {hotspots.map((c, i, arr) => (
                    <View key={c.key} style={[s.row, i < arr.length - 1 && s.rowBorder]}>
                      <View style={[s.rank, i === 0 && { backgroundColor: colors.brand }]}>
                        <Text style={[s.rankText, i === 0 && { color: '#fff' }]}>{i + 1}</Text>
                      </View>
                      <View style={{ flex: 1 }}>
                        <Text style={s.zoneName}>{cellNames[c.key] ?? 'Finding area…'}</Text>
                        <Text style={s.zoneSub}>{anyHotspotEarnings ? 'estimated earnings here' : 'where you drive most'}</Text>
                      </View>
                      <Text style={s.zoneVal}>{anyHotspotEarnings ? fmtGbp(c.earnings) : `#${i + 1}`}</Text>
                    </View>
                  ))}
                </Card>
                <Text style={s.note}>Your busiest areas, clustered from your GPS trail — so it stays accurate even when you track a whole shift as one trip. The £ is only a rough guide: your logged pay is split across that period’s trips, since pay logged at the end of a day or week can’t be tied to an exact spot.</Text>
              </>
            )}
            <View style={{ marginTop: spacing.lg }}>
              <SectionHeader icon="map" title="Hotspot map" />
              <Card style={{ padding: spacing.sm }}>
                {hotspots.length === 0 && (
                  <Text style={[s.note, { marginTop: 0, marginBottom: spacing.sm }]}>Here’s where you are now — start a trip and your hotspots build on the map as you drive.</Text>
                )}
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
                <Text style={s.note}>Where you drive, from your GPS trips. The £ shading is only a rough guide — your logged pay is spread across that day or week’s trips, so it hints at where your money came from rather than measuring it spot by spot.</Text>
              </Card>
            </View>
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

        {!hasData && tab !== 'where' && (
          <Card style={{ alignItems: 'center', paddingVertical: spacing.xxl, gap: 10 }}>
            <IconBadge icon="bar-chart-2" tone="mint" size={48} />
            <Text style={[type.bodyMedium, { textAlign: 'center' }]}>No insights yet</Text>
            <Text style={[type.caption, { textAlign: 'center', lineHeight: 19 }]}>
              Track a few trips with GPS and log your pay — your hotspots, best hours and best-paying apps will appear here.
            </Text>
          </Card>
        )}

        {/* Optional automations — only shown while they're still off, gone once on. */}
        {(!nudgesOn || !remindersOn) && (
          <View style={{ marginTop: spacing.xl }}>
            <SectionHeader icon="zap" title="Get more from Okkle" />
            <Card style={{ gap: 0 }}>
              {!nudgesOn && (
                <SetupPrompt
                  icon="navigation" tone="blue" title="Trip nudges"
                  sub="Get a tap-to-track reminder when you start driving, so you never miss your miles."
                  busy={setupBusy} onEnable={enableNudges}
                />
              )}
              {!nudgesOn && !remindersOn && <View style={s.setupDivider} />}
              {!remindersOn && (
                <SetupPrompt
                  icon="bell" tone="amber" title="Logging reminders"
                  sub="A regular nudge to log your pay and miles, so your tax stays up to date."
                  busy={setupBusy} onEnable={enableReminders}
                />
              )}
            </Card>
            <Text style={s.note}>Turn these on here, or fine-tune them anytime in Settings.</Text>
          </View>
        )}
    </CollapsingHeader>
  );
}

function SetupPrompt({ icon, tone, title, sub, busy, onEnable }: {
  icon: React.ComponentProps<typeof Feather>['name']; tone: any; title: string; sub: string; busy: boolean; onEnable: () => void;
}) {
  return (
    <View style={s.setupRow}>
      <IconBadge icon={icon} tone={tone} size={38} />
      <View style={{ flex: 1 }}>
        <Text style={s.setupTitle}>{title}</Text>
        <Text style={s.setupSub}>{sub}</Text>
      </View>
      <Pressable onPress={onEnable} disabled={busy} style={({ pressed }) => [s.enableBtn, (pressed || busy) && { opacity: 0.6 }]}>
        <Text style={s.enableText}>Turn on</Text>
      </Pressable>
    </View>
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

  setupRow: { flexDirection: 'row', alignItems: 'center', gap: 12, paddingVertical: spacing.sm },
  setupDivider: { height: 1, backgroundColor: colors.border, marginVertical: spacing.sm },
  setupTitle: { ...type.bodyMedium, fontSize: 15 },
  setupSub: { ...type.caption, marginTop: 2, lineHeight: 18 },
  enableBtn: { paddingHorizontal: 16, paddingVertical: 9, borderRadius: radius.full, backgroundColor: colors.brand },
  enableText: { color: '#fff', fontSize: 13, fontWeight: font.bold },
});
