import React, { useState } from 'react';
import { View, Text, ScrollView, StyleSheet, Alert } from 'react-native';
import { colors, font, spacing, radius, type } from '../../src/theme';
import { Chip, PrimaryButton, Card, SectionHeader } from '../../src/components';
import { PLATFORMS, VEHICLES, fmtGbp, fmtMiles, fmtDuration, vehicleEmoji } from '../../src/db/tax';
import { useTrip } from '../../src/hooks/useTrip';
import { saveTrip, getUser } from '../../src/db';

export default function TripScreen() {
  const user = getUser();
  const [platform, setPlatform] = useState(user?.platforms?.split(',')[0] ?? 'Uber Eats');
  const [vehicle, setVehicle] = useState(user?.vehicle ?? 'car');
  const [earnings, setEarnings] = useState('');
  const [saved, setSaved] = useState(false);
  const { trip, start, pause, resume, end } = useTrip();

  async function handleStart() {
    try {
      await start(platform, vehicle);
    } catch {
      Alert.alert('Location needed', 'Please allow location access to track your trip.');
    }
  }

  function handleEnd() {
    Alert.alert('End trip?', `${fmtMiles(trip.miles)} tracked so far.`, [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'End trip', style: 'destructive', onPress: () => {
          const final = end();
          setSaved(false);
          setEarnings('');
        },
      },
    ]);
  }

  function handleSave(final: typeof trip) {
    saveTrip({
      platform: final.platform,
      vehicle: final.vehicle,
      miles: parseFloat(final.miles.toFixed(2)),
      deduction: parseFloat(final.deduction.toFixed(2)),
      earnings: earnings ? parseFloat(earnings) : null,
      started_at: final.startedAt!.toISOString(),
      ended_at: new Date().toISOString(),
    });
    setSaved(true);
  }

  const isRunning = trip.state === 'running';
  const isPaused = trip.state === 'paused';
  const isActive = isRunning || isPaused;

  if (isActive) {
    return (
      <View style={[s.screen, { backgroundColor: colors.dark }]}>
        <View style={s.liveHeader}>
          <View style={s.liveDot} />
          <Text style={{ color: '#fff', fontSize: 13, fontWeight: font.medium, marginLeft: 6 }}>
            {isPaused ? 'Paused' : 'Live tracking'}
          </Text>
        </View>

        <View style={s.liveBig}>
          <Text style={s.liveMiles}>{trip.miles.toFixed(1)}</Text>
          <Text style={s.liveMilesUnit}>miles</Text>
        </View>

        <View style={s.liveStats}>
          <View style={s.liveStat}>
            <Text style={s.liveStatLabel}>Deduction</Text>
            <Text style={s.liveStatValue}>{fmtGbp(trip.deduction)}</Text>
          </View>
          <View style={[s.liveStat, s.liveStatBorder]}>
            <Text style={s.liveStatLabel}>Time</Text>
            <Text style={s.liveStatValue}>{fmtDuration(trip.elapsedSeconds)}</Text>
          </View>
          <View style={s.liveStat}>
            <Text style={s.liveStatLabel}>Platform</Text>
            <Text style={s.liveStatValue}>{trip.platform.split(' ')[0]}</Text>
          </View>
        </View>

        <View style={s.liveActions}>
          <PrimaryButton
            label={isPaused ? 'Resume' : 'Pause'}
            onPress={isPaused ? resume : pause}
            variant="ghost"
            style={{ flex: 1, marginRight: 8, borderColor: 'rgba(255,255,255,0.3)' }}
          />
          <PrimaryButton
            label="End trip"
            onPress={handleEnd}
            variant="danger"
            style={{ flex: 1 }}
          />
        </View>
      </View>
    );
  }

  return (
    <ScrollView style={s.screen} contentContainerStyle={s.content}>
      <Text style={s.heading}>New trip</Text>
      <Text style={s.sub}>GPS will measure your distance automatically</Text>

      <SectionHeader title="Platform" />
      <View style={s.chips}>
        {PLATFORMS.map(p => (
          <Chip key={p} label={p} selected={platform === p} onPress={() => setPlatform(p)} size="lg" style={s.chip} />
        ))}
      </View>

      <SectionHeader title="Vehicle" />
      <View style={s.chips}>
        {VEHICLES.map(v => (
          <Chip
            key={v.key}
            label={`${v.icon}  ${v.label}`}
            selected={vehicle === v.key}
            onPress={() => setVehicle(v.key)}
            size="lg"
            style={s.chip}
          />
        ))}
      </View>

      <View style={{ marginTop: spacing.xl }}>
        <PrimaryButton label="Start trip 📍" onPress={handleStart} />
        <Text style={s.gpsNote}>Your phone's GPS will track distance. Keep the app open during your trip.</Text>
      </View>
    </ScrollView>
  );
}

const s = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  content: { padding: spacing.xl, paddingTop: 60, paddingBottom: 40 },
  heading: { ...type.screenTitle, marginBottom: 6 },
  sub: { ...type.body, color: colors.textSecondary, marginBottom: spacing.xl },
  chips: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm, marginBottom: spacing.lg },
  chip: { marginBottom: 0 },
  gpsNote: { ...type.caption, color: colors.textTertiary, textAlign: 'center', marginTop: 12, lineHeight: 20 },

  liveHeader: { flexDirection: 'row', alignItems: 'center', paddingTop: 60, paddingHorizontal: spacing.xl },
  liveDot: { width: 8, height: 8, borderRadius: 4, backgroundColor: '#4ade80' },
  liveBig: { flex: 1, alignItems: 'center', justifyContent: 'center' },
  liveMiles: { fontSize: 80, fontWeight: font.bold, color: '#fff', letterSpacing: -3 },
  liveMilesUnit: { fontSize: 20, color: 'rgba(255,255,255,0.5)', marginTop: -10 },
  liveStats: { flexDirection: 'row', marginHorizontal: spacing.xl, backgroundColor: 'rgba(255,255,255,0.08)', borderRadius: radius.lg, marginBottom: spacing.xl },
  liveStat: { flex: 1, alignItems: 'center', padding: spacing.lg },
  liveStatBorder: { borderLeftWidth: 1, borderRightWidth: 1, borderColor: 'rgba(255,255,255,0.12)' },
  liveStatLabel: { fontSize: 11, color: 'rgba(255,255,255,0.5)', marginBottom: 4 },
  liveStatValue: { fontSize: 16, fontWeight: font.semibold, color: '#fff' },
  liveActions: { flexDirection: 'row', paddingHorizontal: spacing.xl, paddingBottom: 40 },
});
