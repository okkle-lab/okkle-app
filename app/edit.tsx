import React, { useState } from 'react';
import {
  View, Text, TextInput, ScrollView, StyleSheet, Pressable, Alert, Image,
  KeyboardAvoidingView, Platform,
} from 'react-native';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { colors, font, spacing, radius, type, tabular } from '../src/theme';
import { Chip, SectionHeader, PrimaryButton, VehicleChip, DatePickerField, RouteMap } from '../src/components';
import { PLATFORMS, VEHICLES, calcDeduction, fmtGbp, fmtMiles } from '../src/db/tax';
import {
  getTrip, updateTrip, deleteTrip, getRecord, updateRecord, deleteRecord,
} from '../src/db';

function tripDuration(start: string, end: string): string {
  const ms = new Date(end).getTime() - new Date(start).getTime();
  if (ms <= 0) return '—';
  const mins = Math.round(ms / 60000);
  return mins >= 60 ? `${Math.floor(mins / 60)}h ${mins % 60}m` : `${mins}m`;
}

export default function EditEntry() {
  const router = useRouter();
  const { kind, id } = useLocalSearchParams<{ kind: string; id: string }>();
  const entryId = parseInt(id ?? '0', 10);

  const trip = kind === 'trip' ? getTrip(entryId) : null;
  const record = kind === 'record' ? getRecord(entryId) : null;
  const routePts: { lat: number; lng: number }[] = React.useMemo(() => {
    try { return trip?.route_json ? JSON.parse(trip.route_json) : []; } catch { return []; }
  }, [trip?.route_json]);

  const [platform, setPlatform] = useState(trip?.platform ?? record?.platform ?? 'Uber Eats');
  const [vehicle, setVehicle] = useState(trip?.vehicle ?? 'car');
  const [miles, setMiles] = useState(String(trip?.miles ?? record?.miles ?? ''));
  const [amount, setAmount] = useState(String(record?.amount ?? trip?.earnings ?? ''));
  const [description, setDescription] = useState(record?.category ?? record?.notes ?? '');
  const [date, setDate] = useState(() => {
    const iso = trip?.started_at ?? record?.created_at;
    const d = iso ? new Date(iso) : new Date();
    return isNaN(d.getTime()) ? new Date() : d;
  });

  if (!trip && !record) {
    return (
      <View style={[s.screen, { justifyContent: 'center', alignItems: 'center' }]}>
        <Text style={s.sub}>Entry not found.</Text>
        <PrimaryButton label="Close" onPress={() => router.back()} style={{ marginTop: spacing.lg }} />
      </View>
    );
  }

  const recordType = record?.record_type;
  const showMiles = kind === 'trip' || recordType === 'mileage';
  const showAmount = kind === 'trip' || recordType === 'income' || recordType === 'expense';
  const showPlatform = kind === 'trip' || recordType === 'income' || recordType === 'mileage';
  const showVehicle = kind === 'trip';
  const showDescription = recordType === 'expense';
  const milesNum = parseFloat(miles) || 0;
  const previewDeduction = showMiles ? calcDeduction(milesNum, vehicle) : 0;

  function save() {
    if (kind === 'trip') {
      updateTrip(entryId, {
        platform, vehicle,
        miles: milesNum,
        deduction: parseFloat(previewDeduction.toFixed(2)),
        earnings: amount ? parseFloat(amount) : null,
        started_at: date.toISOString(),
      });
    } else if (record) {
      updateRecord(entryId, {
        platform: showPlatform ? platform : record.platform,
        amount: showAmount && amount ? parseFloat(amount) : record.amount,
        miles: showMiles ? milesNum : record.miles,
        deduction: showMiles ? parseFloat(previewDeduction.toFixed(2)) : record.deduction,
        category: showDescription ? description : record.category,
        notes: showDescription ? description : record.notes,
        created_at: date.toISOString(),
      });
    }
    router.back();
  }

  function confirmDelete() {
    Alert.alert('Delete this entry?', 'This permanently removes it from your records.', [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Delete', style: 'destructive', onPress: () => {
          if (kind === 'trip') deleteTrip(entryId); else deleteRecord(entryId);
          router.back();
        },
      },
    ]);
  }

  const title = kind === 'trip' ? 'Edit trip'
    : recordType === 'income' ? 'Edit earnings'
    : recordType === 'expense' ? 'Edit expense'
    : 'Edit mileage';

  return (
    <KeyboardAvoidingView style={s.screen} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <ScrollView contentContainerStyle={s.content} keyboardShouldPersistTaps="handled">
        <View style={s.header}>
          <Text style={s.heading}>{title}</Text>
          <Pressable onPress={() => router.back()} hitSlop={12}><Text style={s.close}>Cancel</Text></Pressable>
        </View>

        {/* Premium trip summary — route map + at-a-glance stats (GPS trips only) */}
        {trip && routePts.length > 0 && (
          <View style={s.tripCard}>
            <RouteMap route={routePts} height={170} />
            <View style={s.tripStats}>
              <View style={s.tripStat}>
                <Text style={s.tripStatValue}>{fmtMiles(trip.miles)}</Text>
                <Text style={s.tripStatLabel}>distance</Text>
              </View>
              <View style={s.tripStatDivider} />
              <View style={s.tripStat}>
                <Text style={s.tripStatValue}>{tripDuration(trip.started_at, trip.ended_at)}</Text>
                <Text style={s.tripStatLabel}>time</Text>
              </View>
              <View style={s.tripStatDivider} />
              <View style={s.tripStat}>
                <Text style={s.tripStatValue}>{fmtGbp(trip.deduction)}</Text>
                <Text style={s.tripStatLabel}>tax saved</Text>
              </View>
            </View>
            {trip.zone ? <Text style={s.tripZone}>📍 {trip.zone}</Text> : null}
          </View>
        )}

        <SectionHeader title="Date" />
        <DatePickerField value={date} onChange={setDate} />

        {showPlatform && (
          <>
            <SectionHeader title="Platform" />
            <View style={s.chips}>
              {PLATFORMS.map(p => (
                <Chip key={p} label={p} selected={platform === p} onPress={() => setPlatform(p)} />
              ))}
            </View>
          </>
        )}

        {showVehicle && (
          <>
            <SectionHeader title="Vehicle" />
            <View style={s.chips}>
              {VEHICLES.map(v => (
                <VehicleChip key={v.key} vehicle={v.key} label={v.label} selected={vehicle === v.key} onPress={() => setVehicle(v.key)} />
              ))}
            </View>
          </>
        )}

        {showMiles && (
          <>
            <SectionHeader title="Miles" />
            <TextInput style={s.input} value={miles} onChangeText={setMiles} keyboardType="decimal-pad" placeholder="0" placeholderTextColor={colors.textTertiary} />
            {milesNum > 0 ? <Text style={s.preview}>Deduction: {fmtGbp(previewDeduction)}</Text> : null}
          </>
        )}

        {showDescription && (
          <>
            <SectionHeader title="Description" />
            <TextInput style={s.input} value={description} onChangeText={setDescription} placeholder="Description" placeholderTextColor={colors.textTertiary} />
          </>
        )}

        {showAmount && (
          <>
            <SectionHeader title={kind === 'trip' ? 'Earnings (optional)' : 'Amount (£)'} />
            <TextInput style={s.input} value={amount} onChangeText={setAmount} keyboardType="decimal-pad" placeholder="0.00" placeholderTextColor={colors.textTertiary} />
          </>
        )}

        {record?.receipt_uri ? (
          <>
            <SectionHeader title="Receipt" />
            <Image source={{ uri: record.receipt_uri }} style={s.receipt} resizeMode="contain" />
          </>
        ) : null}

        <PrimaryButton label="Save changes" onPress={save} style={{ marginTop: spacing.xl }} />
        <Pressable onPress={confirmDelete} style={s.deleteBtn}>
          <Text style={s.deleteText}>Delete entry</Text>
        </Pressable>
      </ScrollView>
    </KeyboardAvoidingView>
  );
}

const s = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  content: { padding: spacing.xl, paddingTop: 60, paddingBottom: 60 },
  header: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: spacing.xl },
  heading: { ...type.screenTitle },
  close: { ...type.bodyMedium, color: colors.brandDeep },
  tripCard: { backgroundColor: colors.bgCard, borderRadius: radius.lg, borderWidth: 1, borderColor: colors.border, padding: spacing.sm, marginBottom: spacing.xl, overflow: 'hidden' },
  tripStats: { flexDirection: 'row', alignItems: 'center', paddingVertical: spacing.md },
  tripStat: { flex: 1, alignItems: 'center' },
  tripStatDivider: { width: 1, height: 28, backgroundColor: colors.border },
  tripStatValue: { ...tabular, fontSize: 17, fontWeight: font.bold, color: colors.textPrimary },
  tripStatLabel: { ...type.small, marginTop: 2 },
  tripZone: { ...type.caption, color: colors.textSecondary, textAlign: 'center', paddingBottom: spacing.sm },
  sub: { ...type.body, color: colors.textSecondary },
  chips: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm, marginBottom: spacing.lg },
  input: {
    borderWidth: 1.5, borderColor: colors.border, borderRadius: radius.md,
    padding: spacing.md, fontSize: 18, color: colors.textPrimary, backgroundColor: colors.bgCard,
    marginBottom: spacing.sm,
  },
  preview: { ...type.caption, color: colors.brandDeep, marginBottom: spacing.lg },
  receipt: { width: '100%', height: 240, borderRadius: radius.md, backgroundColor: colors.bgSoft, marginBottom: spacing.lg },
  deleteBtn: { marginTop: spacing.lg, alignItems: 'center', paddingVertical: spacing.md },
  deleteText: { ...type.label, color: colors.red },
});
