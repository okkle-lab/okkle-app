import React from 'react';
import { View, Text, ScrollView, StyleSheet, Pressable } from 'react-native';
import { useRouter } from 'expo-router';
import { Feather } from '@expo/vector-icons';
import { colors, font, spacing, radius, type, tabular } from '../src/theme';
import { Card, SectionHeader, HeatMapView } from '../src/components';
import { getZoneStats, getHeatPoints, getEarningsByTimeOfDay, type ZoneStat, type TimeBucket, type HeatPoint } from '../src/db';
import { fmtGbp, fmtMiles } from '../src/db/tax';

export default function InsightsScreen() {
  const router = useRouter();
  const [zones, setZones] = React.useState<ZoneStat[]>([]);
  const [points, setPoints] = React.useState<HeatPoint[]>([]);
  const [buckets, setBuckets] = React.useState<TimeBucket[]>([]);

  React.useEffect(() => {
    setZones(getZoneStats());
    setPoints(getHeatPoints());
    setBuckets(getEarningsByTimeOfDay());
  }, []);

  const anyEarnings = zones.some(z => z.earnings > 0);
  const maxPer = Math.max(...buckets.map(b => b.perHour), 1);
  const anyBucketEarnings = buckets.some(b => b.earnings > 0);

  return (
    <View style={s.screen}>
      <ScrollView contentContainerStyle={s.content}>
        <View style={s.header}>
          <Pressable onPress={() => router.back()} hitSlop={12}><Feather name="chevron-left" size={26} color={colors.textPrimary} /></Pressable>
          <Text style={s.title}>Insights</Text>
          <View style={{ width: 26 }} />
        </View>
        <Text style={s.sub}>Where and when your work pays off best.</Text>

        {/* WHERE — location heatmap */}
        <SectionHeader icon="map" title="Your hotspots" />
        <Card style={{ padding: spacing.sm }}>
          <HeatMapView points={points} height={230} />
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

        {/* WHERE — ranked zones */}
        {zones.length > 0 && (
          <View style={{ marginTop: spacing.xl }}>
            <SectionHeader icon="award" title={anyEarnings ? 'Top earning areas' : 'Busiest areas'} />
            <Card style={{ padding: 0, overflow: 'hidden' }}>
              {zones.slice(0, 6).map((z, i, arr) => (
                <View key={z.zone} style={[s.row, i < arr.length - 1 && s.rowBorder]}>
                  <View style={[s.rank, i === 0 && { backgroundColor: colors.brand }]}>
                    <Text style={[s.rankText, i === 0 && { color: '#fff' }]}>{i + 1}</Text>
                  </View>
                  <View style={{ flex: 1 }}>
                    <Text style={s.zoneName}>{z.zone}</Text>
                    <Text style={s.zoneSub}>{z.trips} {z.trips === 1 ? 'trip' : 'trips'} · {fmtMiles(z.miles)}</Text>
                  </View>
                  <Text style={s.zoneVal}>{anyEarnings ? fmtGbp(z.earnings) : fmtMiles(z.miles)}</Text>
                </View>
              ))}
            </Card>
            {!anyEarnings && <Text style={s.note}>Add earnings to your trips to rank areas by what they actually pay.</Text>}
          </View>
        )}

        {/* WHEN — best times */}
        {buckets.some(b => b.trips > 0) && (
          <View style={{ marginTop: spacing.xl }}>
            <SectionHeader icon="clock" title="Best times to work" />
            <Card>
              {buckets.map(b => {
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
              })}
            </Card>
          </View>
        )}

        {zones.length === 0 && !buckets.some(b => b.trips > 0) && (
          <Card style={{ marginTop: spacing.xl, alignItems: 'center', paddingVertical: spacing.xxl }}>
            <Text style={{ fontSize: 34, marginBottom: 8 }}>📍</Text>
            <Text style={[type.bodyMedium, { textAlign: 'center' }]}>No location data yet</Text>
            <Text style={[type.caption, { textAlign: 'center', marginTop: 4, lineHeight: 19 }]}>
              Track trips with GPS for a week — your hotspots and best hours will appear here.
            </Text>
          </Card>
        )}
      </ScrollView>
    </View>
  );
}

const s = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  content: { padding: spacing.xl, paddingTop: 60, paddingBottom: 40 },
  header: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', marginBottom: 6 },
  title: { ...type.screenTitle },
  sub: { ...type.body, color: colors.textSecondary, marginBottom: spacing.xl },

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
