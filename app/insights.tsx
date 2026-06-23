import React from 'react';
import { View, Text, ScrollView, StyleSheet, Pressable } from 'react-native';
import { useRouter } from 'expo-router';
import { Feather } from '@expo/vector-icons';
import { colors, font, spacing, radius, type, tabular } from '../src/theme';
import { Card, SectionHeader, HeatMapView, IconBadge } from '../src/components';
import { getZoneStats, getHeatPoints, getEarningsByTimeOfDay, getBestSpot, getYearPnL, getPlatformStats, TIME_FILTERS, type ZoneStat, type TimeBucket, type HeatPoint, type TimeFilter, type BestSpot, type YearPnL, type PlatformStat } from '../src/db';
import { fmtGbp, fmtMiles, fmtPerHour, fmtPerMile, fmtHours, fmtPct } from '../src/db/tax';

type InsightTab = 'where' | 'when' | 'money';
const TABS: { key: InsightTab; label: string; icon: React.ComponentProps<typeof Feather>['name'] }[] = [
  { key: 'where', label: 'Where', icon: 'map-pin' },
  { key: 'when', label: 'When', icon: 'clock' },
  { key: 'money', label: 'Money', icon: 'trending-up' },
];

export default function InsightsScreen() {
  const router = useRouter();
  const [tab, setTab] = React.useState<InsightTab>('where');
  const [filter, setFilter] = React.useState<TimeFilter>('all');
  const [zones, setZones] = React.useState<ZoneStat[]>([]);
  const [points, setPoints] = React.useState<HeatPoint[]>([]);
  const [buckets, setBuckets] = React.useState<TimeBucket[]>([]);
  const [best, setBest] = React.useState<BestSpot | null>(null);
  const [pnl, setPnl] = React.useState<YearPnL | null>(null);
  const [platforms, setPlatforms] = React.useState<PlatformStat[]>([]);

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

  const anyEarnings = zones.some(z => z.earnings > 0);
  const anyPerHour = zones.some(z => z.perHour > 0);
  const maxPer = Math.max(...buckets.map(b => b.perHour), 1);
  const anyBucketEarnings = buckets.some(b => b.earnings > 0);
  const hasData = zones.length > 0 || buckets.some(b => b.trips > 0) || platforms.some(p => p.perHour > 0) || !!pnl?.hasData;

  return (
    <View style={s.screen}>
      <ScrollView contentContainerStyle={s.content}>
        <View style={s.header}>
          <Pressable onPress={() => router.back()} hitSlop={12}><Feather name="chevron-left" size={26} color={colors.textPrimary} /></Pressable>
          <Text style={s.title}>Insights</Text>
          <View style={{ width: 26 }} />
        </View>
        <Text style={s.sub}>Where and when your work pays off best.</Text>

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
            {buckets.some(b => b.trips > 0) && (
              <ScrollView horizontal showsHorizontalScrollIndicator={false} style={s.filterScroll} contentContainerStyle={{ gap: 8, paddingRight: spacing.xl }}>
                {TIME_FILTERS.map(f => (
                  <Pressable key={f.key} onPress={() => setFilter(f.key)} style={[s.filterChip, filter === f.key && s.filterChipOn]}>
                    <Text style={[s.filterText, filter === f.key && s.filterTextOn]}>{f.label}</Text>
                  </Pressable>
                ))}
              </ScrollView>
            )}
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
            <View style={{ marginTop: spacing.lg }}>
              <SectionHeader icon="map" title="Hotspot map" />
              <Card style={{ padding: spacing.sm }}>
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
                <Text style={s.note}>Built on-device from your GPS trips. Nothing leaves your phone.</Text>
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

        {/* MONEY — platform ranking + business P&L */}
        {hasData && tab === 'money' && (
          <>
            {platforms.some(p => p.perHour > 0) && (
              <View>
                <SectionHeader icon="award" title="Which platform pays best?" />
                <Card style={{ padding: 0, overflow: 'hidden' }}>
                  {platforms.filter(p => p.perHour > 0).sort((a, b) => b.perHour - a.perHour).map((p, i, arr) => (
                    <View key={p.platform} style={[s.row, i < arr.length - 1 && s.rowBorder]}>
                      <View style={[s.rank, i === 0 && { backgroundColor: colors.brand }]}>
                        <Text style={[s.rankText, i === 0 && { color: '#fff' }]}>{i + 1}</Text>
                      </View>
                      <View style={{ flex: 1 }}>
                        <Text style={s.zoneName}>{p.platform}</Text>
                        <Text style={s.zoneSub}>{fmtPerMile(p.perMile)} · {fmtHours(p.hours)}</Text>
                      </View>
                      <Text style={[s.zoneVal, i === 0 && { color: colors.green }]}>{fmtPerHour(p.perHour)}</Text>
                    </View>
                  ))}
                </Card>
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
            {!platforms.some(p => p.perHour > 0) && !pnl?.hasData && (
              <Card><Text style={s.emptyInline}>Log your pay against trips to see which platform pays best and your business stats.</Text></Card>
            )}
          </>
        )}

        {!hasData && (
          <Card style={{ marginTop: spacing.xl, alignItems: 'center', paddingVertical: spacing.xxl }}>
            <View style={{ marginBottom: 10 }}><IconBadge icon="map-pin" tone="mint" size={48} /></View>
            <Text style={[type.bodyMedium, { textAlign: 'center' }]}>No data yet</Text>
            <Text style={[type.caption, { textAlign: 'center', marginTop: 4, lineHeight: 19 }]}>
              Track trips with GPS and log your pay — your hotspots, best hours and business stats will appear here.
            </Text>
          </Card>
        )}
      </ScrollView>
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
  content: { padding: spacing.xl, paddingTop: 60, paddingBottom: 40 },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginBottom: 6 },
  title: { ...type.screenTitle },
  sub: { ...type.body, color: colors.textSecondary, marginBottom: spacing.lg },

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
