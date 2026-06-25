import React, { useState, useEffect } from 'react';
import {
  View, Text, ScrollView, StyleSheet, Alert, Pressable, TextInput,
  KeyboardAvoidingView, Platform, Dimensions, Modal,
} from 'react-native';
import { StatusBar } from 'expo-status-bar';
import { Feather } from '@expo/vector-icons';
import { activateKeepAwakeAsync, deactivateKeepAwake } from 'expo-keep-awake';
import * as Location from 'expo-location';
import * as Haptics from 'expo-haptics';
import { colors, font, spacing, radius, type, tabular } from '../../src/theme';
import { useRouter } from 'expo-router';
import { Chip, PrimaryButton, SectionHeader, SlideToConfirm, VehicleChip, CollapsingHeader, Card, IconBadge, GradientCard, RouteMap, SettingsGlassButton, KeyboardDoneAccessory, numberKeyboardDoneProps } from '../../src/components';
import { VEHICLES, fmtGbp, fmtGbpRound, fmtMiles, fmtDuration, vehicleLabel } from '../../src/db/tax';
import { useTrip, type LiveTrip } from '../../src/hooks/useTrip';
import { saveTrip, getUser, getLastTrip, getTodayMiles, getDailyStats, getLongestTrip, getStreak, getPlatforms, addPlatform, getVehicleKeys, type DailyStats } from '../../src/db';

type LiveMetric = 'miles' | 'time' | 'speed' | 'today' | 'map';

type Phase = 'setup' | 'live' | 'summary';

export default function TripScreen() {
  const router = useRouter();
  const user = getUser();
  const last = getLastTrip();
  // Remember the last platform/vehicle so starting is a single tap.
  const [platformList, setPlatformList] = useState(getPlatforms);
  const [platform, setPlatform] = useState(last?.platform ?? getPlatforms()[0]);
  // Only the vehicles the user picked at onboarding / in Settings.
  const myVehicles = VEHICLES.filter(v => getVehicleKeys().includes(v.key));
  const [vehicle, setVehicle] = useState(last?.vehicle ?? user?.vehicle ?? myVehicles[0]?.key ?? 'car');

  function addCustomPlatform() {
    Alert.prompt('Add platform', 'Name of the delivery platform you work for', [
      { text: 'Cancel', style: 'cancel' },
      { text: 'Add', onPress: (name?: string) => {
        const n = (name ?? '').trim();
        if (!n) return;
        setPlatformList(addPlatform(n));
        setPlatform(n);
      } },
    ], 'plain-text');
  }
  const [phase, setPhase] = useState<Phase>('setup');
  const [finished, setFinished] = useState<LiveTrip | null>(null);
  const [earnings, setEarnings] = useState('');
  const [todayBase, setTodayBase] = useState(0);
  const [today, setToday] = useState<DailyStats>({ miles: 0, deduction: 0, earnings: 0, trips: 0, hours: 0 });
  const [flash, setFlash] = useState<string | null>(null); // milestone celebration
  const [heroMetric, setHeroMetric] = useState<LiveMetric>('miles');
  const [prevBestTrip, setPrevBestTrip] = useState(0);
  const milestoneRef = React.useRef(0);
  const { trip, points, start, pause, resume, end } = useTrip();

  useEffect(() => { setToday(getDailyStats()); }, [phase]);

  // Gamified "earn it back" milestones — every £5 of mileage deduction earned
  // mid-trip fires a haptic + a brief celebration, so progress feels rewarding.
  const MILESTONE = 5;
  useEffect(() => {
    if (phase !== 'live') return;
    const reached = Math.floor(trip.deduction / MILESTONE);
    if (reached > milestoneRef.current && trip.deduction >= MILESTONE) {
      Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success).catch(() => {});
      setFlash(`${fmtGbp(reached * MILESTONE)} earned back!`);
      setTimeout(() => setFlash(null), 2600);
    }
    milestoneRef.current = reached;
  }, [trip.deduction, phase]);

  // Keep the screen awake only while a trip is running (phone is mounted).
  useEffect(() => {
    if (phase === 'live') { activateKeepAwakeAsync(); }
    else { deactivateKeepAwake(); }
    return () => { deactivateKeepAwake(); };
  }, [phase]);

  async function handleStart() {
    try {
      setTodayBase(getTodayMiles());
      milestoneRef.current = 0;
      setFlash(null);
      await start(platform, vehicle);
      setPhase('live');
    } catch {
      Alert.alert('Location needed', 'Please allow location access to track your trip distance.');
    }
  }

  function handleEnd() {
    // Capture the previous best BEFORE saving, so we can celebrate a new record.
    setPrevBestTrip(getLongestTrip());
    const final = end();
    setFinished(final);
    setEarnings('');
    setPhase('summary');
  }

  function handleDiscard() {
    Alert.alert(
      'Discard this trip?',
      "The miles tracked so far won't be saved.",
      [
        { text: 'Keep tracking', style: 'cancel' },
        { text: 'Discard', style: 'destructive', onPress: () => { end(); setFinished(null); setEarnings(''); setPhase('setup'); } },
      ],
    );
  }

  async function handleSave() {
    if (!finished) return;
    const pts = finished.points ?? [];

    // Reverse-geocode a representative point to a friendly "zone" name, so the
    // Insights map can rank where you earn. One lookup per trip; best-effort.
    let zone: string | null = null;
    if (pts.length > 0) {
      const mid = pts[Math.floor(pts.length / 2)];
      try {
        const places = await Location.reverseGeocodeAsync({ latitude: mid.lat, longitude: mid.lng });
        const p = places[0];
        // Couriers think in streets & postcodes, so be specific: the road/area,
        // plus the outward postcode (e.g. "Kingston Road · SW19") — far more
        // useful than a whole borough like "Merton".
        const outward = p?.postalCode ? p.postalCode.split(' ')[0].trim() : null;
        const local = p?.street ?? p?.district ?? p?.subregion ?? p?.city ?? null;
        zone = [local, outward].filter(Boolean).join(' · ') || null;
      } catch { /* offline or denied — leave zone null */ }
    }

    saveTrip({
      platform: finished.platform,
      vehicle: finished.vehicle,
      miles: parseFloat(finished.miles.toFixed(2)),
      deduction: parseFloat(finished.deduction.toFixed(2)),
      earnings: earnings ? parseFloat(earnings) : null,
      started_at: finished.startedAt!.toISOString(),
      ended_at: new Date().toISOString(),
      route_json: pts.length > 0 ? JSON.stringify(pts) : null,
      zone,
    });
    setFinished(null);
    setEarnings('');
    setPhase('setup');
  }

  // ---- Phase 2: live tracking ------------------------------------------------
  if (phase === 'live') {
    const isPaused = trip.state === 'paused';
    const waiting = !isPaused && trip.speedMph < 0.5;
    const dayMiles = todayBase + trip.miles;
    const avgMph = trip.elapsedSeconds > 0 ? trip.miles / (trip.elapsedSeconds / 3600) : 0;
    const statusText = isPaused ? 'Paused' : waiting ? 'Waiting for movement' : 'Recording';
    const statusColor = isPaused ? colors.amber : waiting ? colors.amber : colors.brand;

    // Swappable live metrics — tap a stat to promote it to the big hero spot.
    const METRICS: Record<LiveMetric, { value: string; heroLabel: string; chip: string; label: string; icon: string }> = {
      miles: { value: trip.miles.toFixed(1), heroLabel: 'miles this trip', chip: trip.miles.toFixed(1), label: 'miles', icon: 'navigation' },
      time: { value: fmtDuration(trip.elapsedSeconds), heroLabel: 'on this trip', chip: fmtDuration(trip.elapsedSeconds), label: 'time', icon: 'clock' },
      speed: { value: avgMph.toFixed(0), heroLabel: 'average mph', chip: avgMph.toFixed(0), label: 'avg mph', icon: 'zap' },
      today: { value: dayMiles.toFixed(1), heroLabel: 'miles today', chip: dayMiles.toFixed(1), label: 'today', icon: 'sunrise' },
      map: { value: '', heroLabel: 'your route', chip: '', label: 'map', icon: 'map' },
    };
    const stripMetrics = (['miles', 'time', 'speed', 'today', 'map'] as LiveMetric[]).filter(m => m !== heroMetric);
    return (
      <Modal visible animationType="fade" statusBarTranslucent presentationStyle="overFullScreen">
        <StatusBar style="light" />
        <View style={s.liveScreen}>
          {/* Status pill (live/waiting/paused) + discard */}
          <View style={s.liveHeader}>
            <View style={s.statusPill}>
              <View style={[s.liveDot, { backgroundColor: statusColor }]} />
              <Text style={s.statusPillText}>{statusText} · {trip.platform}</Text>
            </View>
          </View>
          <Pressable onPress={handleDiscard} hitSlop={12} style={s.discardX}>
            <Feather name="x" size={24} color="rgba(255,255,255,0.7)" />
          </Pressable>

          {/* Hero — tap any stat below to make it the big number (or the map) */}
          <View style={s.ringWrap}>
            {heroMetric === 'map' ? (
              <View style={s.heroMap}>
                <RouteMap route={points ?? []} height={Math.round(Dimensions.get('window').height * 0.30)} />
                <Text style={s.bigMilesUnit}>your route so far</Text>
              </View>
            ) : (
              <>
                <Text style={[s.bigMiles, heroMetric === 'miles' && s.bigTripMiles]} numberOfLines={1} adjustsFontSizeToFit minimumFontScale={0.45}>{METRICS[heroMetric].value}</Text>
                <Text style={s.bigMilesUnit}>{METRICS[heroMetric].heroLabel}</Text>
              </>
            )}
            <View style={s.moneyChip}>
              <Feather name="trending-up" size={15} color={colors.amber} />
              <Text style={s.moneyChipText}>{fmtGbp(trip.deduction)} earned back so far</Text>
            </View>

            {/* "Earn it back" milestone bar — hidden in map view to avoid crowding */}
            {heroMetric !== 'map' && (() => {
              const nextTarget = (Math.floor(trip.deduction / MILESTONE) + 1) * MILESTONE;
              const into = trip.deduction - (nextTarget - MILESTONE);
              const pct = Math.max(0.02, Math.min(1, into / MILESTONE));
              return (
                <View style={s.mileWrap}>
                  {flash ? (
                    <Text style={s.flashText}>{flash}</Text>
                  ) : (
                    <Text style={s.mileLabel}>{fmtGbp(trip.deduction)} of {fmtGbp(nextTarget)} tax back</Text>
                  )}
                  <View style={s.mileTrack}>
                    <View style={[s.mileFill, { width: `${Math.round(pct * 100)}%`, backgroundColor: flash ? colors.green : colors.brand }]} />
                  </View>
                </View>
              );
            })()}
          </View>

          {/* Glass stat strip — tap a cell to swap it into the hero spot */}
          <View style={s.liveStats}>
            {stripMetrics.map((m, i) => (
              <Pressable key={m} onPress={() => setHeroMetric(m)} style={({ pressed }) => [s.liveStat, i > 0 && s.liveStatBorder, pressed && { opacity: 0.6 }]}>
                <Feather name={METRICS[m].icon as any} size={15} color="rgba(255,255,255,0.5)" />
                {m === 'map'
                  ? <Text style={[s.liveStatValue, { fontSize: 15, marginTop: 4 }]}>Map</Text>
                  : <Text style={s.liveStatValue} numberOfLines={1} adjustsFontSizeToFit minimumFontScale={0.6}>{METRICS[m].chip}</Text>}
                <Text style={s.liveStatLabel}>{METRICS[m].label}</Text>
              </Pressable>
            ))}
          </View>

          <View style={s.liveActions}>
            <Pressable
              onPress={isPaused ? resume : pause}
              style={({ pressed }) => [s.pauseBtn, pressed && { opacity: 0.7 }]}
            >
              <Feather name={isPaused ? 'play' : 'pause'} size={20} color="#fff" />
              <Text style={s.pauseBtnText}>{isPaused ? 'Resume tracking' : 'Pause'}</Text>
            </Pressable>

            <SlideToConfirm label="Slide to end trip" onConfirm={handleEnd} color={colors.red} />
          </View>
        </View>
      </Modal>
    );
  }

  // ---- Phase 3: celebratory scorecard + quick earnings + save ----------------
  if (phase === 'summary' && finished) {
    const isRecord = prevBestTrip > 0 && finished.miles > prevBestTrip;
    const streak = getStreak();
    const headline = isRecord ? 'New personal best!' : finished.miles >= 1 ? 'Nice ride!' : 'Trip saved';
    return (
      <KeyboardAvoidingView style={s.screen} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
        <ScrollView contentContainerStyle={s.content} keyboardShouldPersistTaps="handled">
          <GradientCard colors={isRecord ? ['#FCD34D', colors.amber, '#9E5E08'] : ['#3BC07E', colors.green, '#1C7048']} radius={36} style={s.checkCircle}>
            <Feather name={isRecord ? 'award' : 'check'} size={36} color="#fff" />
          </GradientCard>
          <Text style={[s.heading, { textAlign: 'center' }]}>{headline}</Text>
          <Text style={[s.sub, { textAlign: 'center', marginBottom: spacing.lg }]}>
            You earned {fmtGbp(finished.deduction)} back in tax relief · {fmtMiles(finished.miles)}
          </Text>

          <View style={s.summaryStats}>
            <View style={s.summaryStat}>
              <Text style={s.summaryStatValue}>{finished.miles.toFixed(1)}</Text>
              <Text style={s.summaryStatLabel}>miles</Text>
            </View>
            <View style={s.summaryStat}>
              <Text style={s.summaryStatValue}>{fmtGbp(finished.deduction)}</Text>
              <Text style={s.summaryStatLabel}>deduction</Text>
            </View>
            <View style={s.summaryStat}>
              <Text style={s.summaryStatValue}>{fmtDuration(finished.elapsedSeconds)}</Text>
              <Text style={s.summaryStatLabel}>time</Text>
            </View>
          </View>

          {/* Motivational hooks */}
          {isRecord && (
            <View style={[s.hookBanner, { backgroundColor: colors.amberLight }]}>
              <IconBadge icon="award" tone="amber" size={34} />
              <Text style={s.hookText}>Your longest trip yet — beat your old best of {fmtMiles(prevBestTrip)}.</Text>
            </View>
          )}
          {streak > 0 && (
            <View style={[s.hookBanner, { backgroundColor: colors.brandLight }]}>
              <IconBadge icon="zap" tone="green" size={34} />
              <Text style={s.hookText}>
                {streak === 1 ? 'Streak started — come back tomorrow to keep it going.' : `Day ${streak} streak — keep the run alive.`}
              </Text>
            </View>
          )}

          <SectionHeader icon="dollar-sign" title="Add earnings for this trip (optional)" />
          <TextInput
            style={s.earningsInput}
            placeholder="£0.00"
            placeholderTextColor={colors.textTertiary}
            keyboardType="decimal-pad"
            value={earnings}
            onChangeText={setEarnings}
            {...numberKeyboardDoneProps}
          />
          <Text style={s.earningsNote}>
            Most couriers are paid weekly, so you can skip this and log earnings in one go later from the Log tab.
          </Text>

          <PrimaryButton label="Save trip" onPress={handleSave} style={{ marginTop: spacing.lg }} />
          <Pressable onPress={handleSave} style={{ marginTop: 14, alignItems: 'center' }}>
            <Text style={s.skip}>Skip — add earnings later</Text>
          </Pressable>
          <Pressable onPress={() => { setFinished(null); setEarnings(''); setPhase('setup'); }} style={{ marginTop: 18, alignItems: 'center' }}>
            <Text style={s.discardText}>Discard this trip</Text>
          </Pressable>
        </ScrollView>
        <KeyboardDoneAccessory />
      </KeyboardAvoidingView>
    );
  }

  // ---- Phase 1: setup --------------------------------------------------------
  const todayHasData = today.trips > 0 || today.earnings > 0;
  return (
    <CollapsingHeader
      title="Start a trip"
      subtitle="Tap start and ride — GPS measures your distance for you."
      right={
        <SettingsGlassButton onPress={() => router.push('/settings')} />
      }
    >
      {/* Your setup — platform + vehicle in one calm card */}
      <Card style={s.setupCard}>
        <View style={s.setupSection}>
          <View style={s.setupLabelRow}>
            <IconBadge icon="grid" tone="mint" size={28} />
            <Text style={s.setupLabel}>Platform</Text>
          </View>
          <View style={s.chips}>
            {platformList.map(p => (
              <Chip key={p} label={p} selected={platform === p} onPress={() => setPlatform(p)} style={s.chip} />
            ))}
            <Pressable onPress={addCustomPlatform} style={s.addChip}>
              <Feather name="plus" size={14} color={colors.brandDeep} />
              <Text style={s.addChipText}>Add</Text>
            </Pressable>
          </View>
        </View>
        <View style={s.setupDivider} />
        <View style={s.setupSection}>
          <View style={s.setupLabelRow}>
            <IconBadge icon="truck" tone="blue" size={28} />
            <Text style={s.setupLabel}>Vehicle</Text>
          </View>
          <View style={[s.chips, { marginBottom: 0 }]}>
            {myVehicles.map(v => (
              <VehicleChip key={v.key} vehicle={v.key} label={v.label} selected={vehicle === v.key} onPress={() => setVehicle(v.key)} />
            ))}
          </View>
        </View>
      </Card>

      {/* Start — the hero action, gradient like Home */}
      <Pressable onPress={handleStart} style={({ pressed }) => pressed && { opacity: 0.9 }}>
        <GradientCard colors={[colors.brand, colors.brandDeep, colors.dark]} radius={radius.xl} style={s.startHero}>
          <View style={{ flex: 1 }}>
            <Text style={s.startKicker}>GPS TRIP</Text>
            <Text style={s.startTitle}>Start trip</Text>
            <Text style={s.startSub}>Tracking {vehicleLabel(vehicle)} miles on {platform}</Text>
          </View>
          <View style={s.startCircle}>
            <Feather name="navigation" size={26} color={colors.brandDeep} />
          </View>
        </GradientCard>
      </Pressable>

      {/* Secondary action — checking an offer is trip-relevant; pay logging lives in the Log tab */}
      <Pressable onPress={() => router.push('/order-check')} style={({ pressed }) => [s.tile, s.tileWide, pressed && { backgroundColor: colors.bgSoft }]}>
        <IconBadge icon="check-circle" tone="violet" size={34} />
        <Text style={s.tileLabel}>Accept or skip? — check an offer's £/mile</Text>
      </Pressable>

      {todayHasData && (
        <Text style={s.todayLine}>Today: {today.miles.toFixed(1)} mi · {fmtGbpRound(today.deduction)} tax saved</Text>
      )}
      <Text style={s.gpsNote}>Keep Okkle open during your ride — your screen stays awake automatically.</Text>
    </CollapsingHeader>
  );
}

const s = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  content: { padding: spacing.xl, paddingTop: 60, paddingBottom: 40 },
  heading: { ...type.screenTitle, marginBottom: 6 },
  sub: { ...type.body, color: colors.textSecondary, marginBottom: spacing.xl },
  chips: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm, marginBottom: spacing.lg },
  chip: { marginBottom: 0 },
  addChip: { flexDirection: 'row', alignItems: 'center', gap: 5, paddingHorizontal: 16, paddingVertical: 12, borderRadius: radius.full, borderWidth: 1.5, borderStyle: 'dashed', borderColor: colors.brandMid, backgroundColor: colors.bgCard },
  addChipText: { ...type.bodyMedium, fontSize: 15, color: colors.brandDeep },
  gpsNote: { ...type.caption, color: colors.textTertiary, textAlign: 'center', marginTop: 14, lineHeight: 20 },
  todayLine: { ...type.caption, color: colors.textSecondary, textAlign: 'center', marginTop: spacing.lg, fontWeight: font.medium },

  // setup
  setupCard: { padding: 0, overflow: 'hidden' },
  setupSection: { padding: spacing.lg },
  setupDivider: { height: 1, backgroundColor: colors.border },
  setupLabelRow: { flexDirection: 'row', alignItems: 'center', gap: 10, marginBottom: spacing.md },
  setupLabel: { ...type.bodyMedium, fontSize: 15 },
  startHero: { flexDirection: 'row', alignItems: 'center', padding: spacing.xl, marginTop: spacing.lg },
  startKicker: { color: 'rgba(255,255,255,0.8)', fontSize: 12, fontWeight: font.semibold, letterSpacing: 1 },
  startTitle: { color: '#fff', fontSize: 28, fontWeight: font.bold, letterSpacing: -0.5, marginTop: 2 },
  startSub: { color: 'rgba(255,255,255,0.85)', fontSize: 13, marginTop: 4 },
  startCircle: { width: 60, height: 60, borderRadius: 30, backgroundColor: '#fff', alignItems: 'center', justifyContent: 'center', shadowColor: '#000', shadowOpacity: 0.18, shadowRadius: 8, shadowOffset: { width: 0, height: 3 } },
  tileRow: { flexDirection: 'row', gap: spacing.md, marginTop: spacing.lg },
  tile: { flex: 1, backgroundColor: colors.bgCard, borderRadius: radius.lg, borderWidth: 1, borderColor: colors.border, paddingVertical: spacing.lg, paddingHorizontal: spacing.md, alignItems: 'center', gap: 8 },
  tileWide: { flexDirection: 'row', marginTop: spacing.lg, paddingVertical: spacing.md, justifyContent: 'flex-start' },
  tileLabel: { ...type.bodyMedium, fontSize: 14, textAlign: 'center' },

  // live
  liveScreen: { flex: 1, backgroundColor: '#000' },
  liveHeader: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', paddingTop: 72 },
  statusPill: { flexDirection: 'row', alignItems: 'center', gap: 8, backgroundColor: 'rgba(255,255,255,0.10)', paddingHorizontal: 14, paddingVertical: 8, borderRadius: radius.full },
  statusPillText: { color: 'rgba(255,255,255,0.95)', fontSize: 14, fontWeight: font.medium },
  discardX: { position: 'absolute', top: 66, right: spacing.xl, padding: 4 },
  liveDot: { width: 9, height: 9, borderRadius: 5, backgroundColor: colors.green },
  ringWrap: { flex: 1, alignItems: 'center', justifyContent: 'center', overflow: 'hidden' },
  bigMiles: { ...tabular, alignSelf: 'stretch', textAlign: 'center', paddingHorizontal: spacing.lg, fontSize: 108, fontWeight: font.bold, color: '#fff', letterSpacing: -4, lineHeight: 114 },
  bigTripMiles: { fontSize: 148, lineHeight: 154, letterSpacing: -5 },
  bigMilesUnit: { fontSize: 15, color: 'rgba(255,255,255,0.55)', marginTop: 2, textAlign: 'center' },
  moneyChip: { flexDirection: 'row', alignItems: 'center', gap: 7, marginTop: spacing.lg, backgroundColor: 'rgba(224,150,31,0.16)', paddingHorizontal: 14, paddingVertical: 8, borderRadius: radius.full },
  moneyChipText: { ...tabular, color: '#F5C97A', fontSize: 14, fontWeight: font.semibold },
  mileWrap: { width: 240, marginTop: spacing.xl, alignItems: 'center', gap: 8 },
  mileLabel: { color: 'rgba(255,255,255,0.7)', fontSize: 13, fontWeight: font.medium },
  flashText: { color: colors.green, fontSize: 15, fontWeight: font.bold },
  mileTrack: { width: '100%', height: 8, borderRadius: radius.full, backgroundColor: 'rgba(255,255,255,0.14)', overflow: 'hidden' },
  mileFill: { height: '100%', borderRadius: radius.full },
  liveStats: { flexDirection: 'row', marginHorizontal: spacing.xl, backgroundColor: 'rgba(255,255,255,0.08)', borderRadius: radius.lg, marginBottom: spacing.xl },
  liveStat: { flex: 1, alignItems: 'center', paddingVertical: spacing.lg, gap: 4 },
  liveStatBorder: { borderLeftWidth: 1, borderColor: 'rgba(255,255,255,0.12)' },
  heroMap: { width: '100%', paddingHorizontal: spacing.sm, alignItems: 'stretch', gap: 10 },
  liveStatLabel: { fontSize: 12, color: 'rgba(255,255,255,0.5)' },
  liveStatValue: { ...tabular, fontSize: 19, fontWeight: font.semibold, color: '#fff' },
  liveActions: { paddingHorizontal: spacing.xl, paddingBottom: Platform.OS === 'ios' ? 132 : 44, gap: spacing.md },
  pauseBtn: {
    borderWidth: 1.5, borderColor: 'rgba(255,255,255,0.3)', borderRadius: radius.full,
    paddingVertical: 18, alignItems: 'center', flexDirection: 'row', justifyContent: 'center', gap: 8,
  },
  pauseBtnText: { color: '#fff', fontSize: 17, fontWeight: font.semibold },

  // summary
  checkCircle: {
    width: 64, height: 64, borderRadius: 32,
    alignItems: 'center', justifyContent: 'center', alignSelf: 'center', marginBottom: spacing.lg,
  },
  summaryStats: {
    flexDirection: 'row', backgroundColor: colors.bgCard, borderRadius: radius.lg,
    borderWidth: 1, borderColor: colors.border, marginVertical: spacing.xl,
  },
  hookBanner: { flexDirection: 'row', alignItems: 'center', gap: 12, borderRadius: radius.lg, padding: spacing.md, marginBottom: spacing.md },
  hookText: { ...type.bodyMedium, fontSize: 14, flex: 1, lineHeight: 19 },
  summaryStat: { flex: 1, alignItems: 'center', paddingVertical: spacing.lg },
  summaryStatValue: { ...tabular, fontSize: 20, fontWeight: font.bold, color: colors.textPrimary },
  summaryStatLabel: { fontSize: 13, color: colors.textSecondary, marginTop: 4 },
  earningsInput: {
    borderWidth: 1.5, borderColor: colors.border, borderRadius: radius.md,
    padding: spacing.lg, fontSize: 22, fontWeight: font.semibold,
    color: colors.textPrimary, backgroundColor: colors.bgCard,
  },
  earningsNote: { ...type.caption, color: colors.textTertiary, marginTop: 8, lineHeight: 19 },
  skip: { ...type.label, color: colors.textSecondary },
  discardText: { ...type.caption, color: colors.red },
});
