import React, { useState, useEffect } from 'react';
import {
  View, Text, ScrollView, StyleSheet, Alert, Pressable, TextInput,
  KeyboardAvoidingView, Platform,
} from 'react-native';
import { Feather } from '@expo/vector-icons';
import { activateKeepAwakeAsync, deactivateKeepAwake } from 'expo-keep-awake';
import * as Location from 'expo-location';
import { colors, font, spacing, radius, type, tabular } from '../../src/theme';
import { useRouter } from 'expo-router';
import { Chip, PrimaryButton, SectionHeader, SlideToConfirm, VehicleChip, CollapsingHeader, Icon, Card, IconBadge, GradientCard } from '../../src/components';
import { PLATFORMS, VEHICLES, fmtGbp, fmtGbpRound, fmtMiles, fmtDuration, vehicleLabel } from '../../src/db/tax';
import { useTrip, type LiveTrip } from '../../src/hooks/useTrip';
import { saveTrip, saveRecord, getUser, getLastTrip, getTodayMiles, getDailyStats, type DailyStats } from '../../src/db';

type Phase = 'setup' | 'live' | 'summary' | 'logpay';

export default function TripScreen() {
  const router = useRouter();
  const user = getUser();
  const last = getLastTrip();
  // Remember the last platform/vehicle so starting is a single tap.
  const [platform, setPlatform] = useState(last?.platform ?? user?.platforms?.split(',')[0] ?? 'Uber Eats');
  const [vehicle, setVehicle] = useState(last?.vehicle ?? user?.vehicle ?? 'car');
  const [phase, setPhase] = useState<Phase>('setup');
  const [finished, setFinished] = useState<LiveTrip | null>(null);
  const [earnings, setEarnings] = useState('');
  const [todayBase, setTodayBase] = useState(0);
  const [today, setToday] = useState<DailyStats>({ miles: 0, deduction: 0, earnings: 0, trips: 0, hours: 0 });
  const [payAmount, setPayAmount] = useState('');
  const [payPlatform, setPayPlatform] = useState('');
  const { trip, start, pause, resume, end } = useTrip();

  useEffect(() => { setToday(getDailyStats()); }, [phase]);

  // Keep the screen awake only while a trip is running (phone is mounted).
  useEffect(() => {
    if (phase === 'live') { activateKeepAwakeAsync(); }
    else { deactivateKeepAwake(); }
    return () => { deactivateKeepAwake(); };
  }, [phase]);

  async function handleStart() {
    try {
      setTodayBase(getTodayMiles());
      await start(platform, vehicle);
      setPhase('live');
    } catch {
      Alert.alert('Location needed', 'Please allow location access to track your trip distance.');
    }
  }

  function handleEnd() {
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
        // Prefer the most *local* name (neighbourhood/district), then add the
        // town for context — "Shoreditch, London" beats a bare "London".
        const local = p?.district ?? p?.street ?? null;
        const town = p?.city ?? p?.subregion ?? p?.region ?? null;
        zone = local && town && local !== town ? `${local}, ${town}` : (local ?? town);
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

  // ---- Phase: log weekly pay -------------------------------------------------
  if (phase === 'logpay') {
    return (
      <KeyboardAvoidingView style={s.screen} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
        <ScrollView contentContainerStyle={s.content} keyboardShouldPersistTaps="handled">
          <Pressable onPress={() => setPhase('setup')} style={{ marginBottom: spacing.lg }}>
            <Feather name="arrow-left" size={22} color={colors.textSecondary} />
          </Pressable>
          <Text style={s.heading}>Log weekly pay</Text>
          <Text style={s.sub}>Uber Eats, Deliveroo and Just Eat all pay weekly by bank transfer. Log it here to keep your earnings accurate.</Text>

          <SectionHeader icon="grid" title="Platform" />
          <View style={s.chips}>
            {PLATFORMS.map(p => (
              <Chip key={p} label={p} selected={payPlatform === p} onPress={() => setPayPlatform(p)} size="lg" style={s.chip} />
            ))}
          </View>

          <SectionHeader icon="dollar-sign" title="Amount received" />
          <TextInput
            style={s.earningsInput}
            placeholder="£0.00"
            placeholderTextColor={colors.textTertiary}
            keyboardType="decimal-pad"
            value={payAmount}
            onChangeText={setPayAmount}
            autoFocus
          />
          <Text style={s.earningsNote}>This is your gross pay before any Uber Eats / Deliveroo deductions. Check your weekly statement for the exact figure.</Text>

          <PrimaryButton
            label="Save pay"
            disabled={!payAmount || !payPlatform}
            onPress={() => {
              saveRecord({
                record_type: 'income',
                platform: payPlatform,
                amount: parseFloat(payAmount),
                miles: null, deduction: null, category: null,
                period_start: null, period_end: null,
                receipt_uri: null, notes: 'Weekly pay',
              });
              setPayAmount('');
              setPayPlatform('');
              setPhase('setup');
            }}
            style={{ marginTop: spacing.lg }}
          />
          <Pressable onPress={() => { setPayAmount(''); setPayPlatform(''); setPhase('setup'); }} style={{ marginTop: 14, alignItems: 'center' }}>
            <Text style={s.skip}>Cancel</Text>
          </Pressable>
        </ScrollView>
      </KeyboardAvoidingView>
    );
  }

  // ---- Phase 2: live tracking ------------------------------------------------
  if (phase === 'live') {
    const isPaused = trip.state === 'paused';
    const waiting = !isPaused && trip.speedMph < 0.5;
    const dayMiles = todayBase + trip.miles;
    const avgMph = trip.elapsedSeconds > 0 ? trip.miles / (trip.elapsedSeconds / 3600) : 0;
    const statusText = isPaused ? 'Paused' : waiting ? 'Waiting for movement' : 'Recording';
    const statusColor = isPaused ? colors.amber : waiting ? colors.amber : colors.brand;
    return (
      <GradientCard colors={[colors.dark, '#103029']} radius={0} diagonal={false} style={{ flex: 1 }}>
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

        {/* Hero: distance — the thing being measured, big and satisfying */}
        <View style={s.ringWrap}>
          <Text style={s.bigMiles}>{trip.miles.toFixed(1)}</Text>
          <Text style={s.bigMilesUnit}>miles this trip</Text>
          <View style={s.moneyChip}>
            <Feather name="trending-up" size={15} color={colors.amber} />
            <Text style={s.moneyChipText}>{fmtGbp(trip.deduction)} tax deduction earned</Text>
          </View>
        </View>

        {/* Glass stat strip — time, pace, day total */}
        <View style={s.liveStats}>
          <View style={s.liveStat}>
            <Feather name="clock" size={16} color="rgba(255,255,255,0.5)" />
            <Text style={s.liveStatValue}>{fmtDuration(trip.elapsedSeconds)}</Text>
            <Text style={s.liveStatLabel}>time</Text>
          </View>
          <View style={[s.liveStat, s.liveStatBorder]}>
            <Feather name="zap" size={16} color="rgba(255,255,255,0.5)" />
            <Text style={s.liveStatValue}>{avgMph.toFixed(0)}</Text>
            <Text style={s.liveStatLabel}>avg mph</Text>
          </View>
          <View style={s.liveStat}>
            <Feather name="map" size={16} color="rgba(255,255,255,0.5)" />
            <Text style={s.liveStatValue}>{dayMiles.toFixed(1)}</Text>
            <Text style={s.liveStatLabel}>today</Text>
          </View>
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
      </GradientCard>
    );
  }

  // ---- Phase 3: quick earnings + save ---------------------------------------
  if (phase === 'summary' && finished) {
    return (
      <KeyboardAvoidingView style={s.screen} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
        <ScrollView contentContainerStyle={s.content} keyboardShouldPersistTaps="handled">
          <GradientCard colors={['#3BC07E', colors.green, '#1C7048']} radius={32} style={s.checkCircle}>
            <Feather name="check" size={36} color="#fff" />
          </GradientCard>
          <Text style={[s.heading, { textAlign: 'center' }]}>Trip saved</Text>
          <Text style={[s.sub, { textAlign: 'center' }]}>{fmtMiles(finished.miles)} · {fmtGbp(finished.deduction)} saved · {finished.platform}</Text>

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

          <SectionHeader icon="dollar-sign" title="Add earnings for this trip (optional)" />
          <TextInput
            style={s.earningsInput}
            placeholder="£0.00"
            placeholderTextColor={colors.textTertiary}
            keyboardType="decimal-pad"
            value={earnings}
            onChangeText={setEarnings}
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
        <Pressable onPress={() => router.push('/settings')} hitSlop={10}>
          <Icon name="settings" size={22} color={colors.textSecondary} />
        </Pressable>
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
            {PLATFORMS.map(p => (
              <Chip key={p} label={p} selected={platform === p} onPress={() => setPlatform(p)} style={s.chip} />
            ))}
          </View>
        </View>
        <View style={s.setupDivider} />
        <View style={s.setupSection}>
          <View style={s.setupLabelRow}>
            <IconBadge icon="truck" tone="blue" size={28} />
            <Text style={s.setupLabel}>Vehicle</Text>
          </View>
          <View style={[s.chips, { marginBottom: 0 }]}>
            {VEHICLES.map(v => (
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

      {/* Secondary actions — clean tiles, not loud buttons */}
      <View style={s.tileRow}>
        <Pressable onPress={() => { setPayPlatform(platform); setPhase('logpay'); }} style={({ pressed }) => [s.tile, pressed && { backgroundColor: colors.bgSoft }]}>
          <IconBadge icon="dollar-sign" tone="green" size={34} />
          <Text style={s.tileLabel}>Log weekly pay</Text>
        </Pressable>
        <Pressable onPress={() => router.push('/order-check')} style={({ pressed }) => [s.tile, pressed && { backgroundColor: colors.bgSoft }]}>
          <IconBadge icon="check-circle" tone="violet" size={34} />
          <Text style={s.tileLabel}>Accept or skip?</Text>
        </Pressable>
      </View>

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
  tileLabel: { ...type.bodyMedium, fontSize: 14, textAlign: 'center' },

  // live
  liveHeader: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center', paddingTop: 72 },
  statusPill: { flexDirection: 'row', alignItems: 'center', gap: 8, backgroundColor: 'rgba(255,255,255,0.10)', paddingHorizontal: 14, paddingVertical: 8, borderRadius: radius.full },
  statusPillText: { color: 'rgba(255,255,255,0.95)', fontSize: 14, fontWeight: font.medium },
  discardX: { position: 'absolute', top: 66, right: spacing.xl, padding: 4 },
  liveDot: { width: 9, height: 9, borderRadius: 5, backgroundColor: colors.green },
  ringWrap: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  bigMiles: { ...tabular, fontSize: 96, fontWeight: font.bold, color: '#fff', letterSpacing: -4, lineHeight: 100 },
  bigMilesUnit: { fontSize: 15, color: 'rgba(255,255,255,0.55)', marginTop: 2 },
  moneyChip: { flexDirection: 'row', alignItems: 'center', gap: 7, marginTop: spacing.lg, backgroundColor: 'rgba(224,150,31,0.16)', paddingHorizontal: 14, paddingVertical: 8, borderRadius: radius.full },
  moneyChipText: { ...tabular, color: '#F5C97A', fontSize: 14, fontWeight: font.semibold },
  liveStats: { flexDirection: 'row', marginHorizontal: spacing.xl, backgroundColor: 'rgba(255,255,255,0.08)', borderRadius: radius.lg, marginBottom: spacing.xl },
  liveStat: { flex: 1, alignItems: 'center', paddingVertical: spacing.lg, gap: 4 },
  liveStatBorder: { borderLeftWidth: 1, borderRightWidth: 1, borderColor: 'rgba(255,255,255,0.12)' },
  liveStatLabel: { fontSize: 12, color: 'rgba(255,255,255,0.5)' },
  liveStatValue: { ...tabular, fontSize: 19, fontWeight: font.semibold, color: '#fff' },
  liveActions: { paddingHorizontal: spacing.xl, paddingBottom: 44, gap: spacing.md },
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
