import React, { useState } from 'react';
import {
  View, Text, TextInput, ScrollView, StyleSheet, Pressable, Alert, Image,
  KeyboardAvoidingView, Platform,
} from 'react-native';
import { useRouter, useLocalSearchParams } from 'expo-router';
import Feather from '@expo/vector-icons/Feather';
import { colors, font, spacing, radius, type, tabular } from '../src/theme';
import { Chip, SectionHeader, PrimaryButton, VehicleChip, DatePickerField, RouteMap, KeyboardDoneAccessory, numberKeyboardDoneProps } from '../src/components';
import { VEHICLES, calcDeduction, fmtGbp, fmtMiles } from '../src/db/tax';
import {
  getTrip, updateTrip, deleteTrip, getRecord, updateRecord, deleteRecord, getVehicleKeys, getPlatforms,
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
  const [vehicle, setVehicle] = useState(trip?.vehicle ?? record?.vehicle ?? 'car');
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
  // Platform lives on earnings only now — trips and mileage are platform-agnostic.
  const showPlatform = recordType === 'income';
  const showVehicle = kind === 'trip' || recordType === 'mileage';
  // The user's chosen vehicles, plus this entry's own vehicle even if it's since
  // been removed in Settings — so an old bike/van entry still shows and is editable.
  const vehicleOptionKeys = Array.from(new Set([...getVehicleKeys(), ...(vehicle ? [vehicle] : [])]));
  const myVehicles = VEHICLES.filter(v => vehicleOptionKeys.includes(v.key));
  const platformOptions = Array.from(new Set([...getPlatforms(), ...(platform ? [platform] : [])]));
  const showDescription = recordType === 'expense';
  const milesNum = parseFloat(miles) || 0;
  const previewDeduction = showMiles ? calcDeduction(milesNum, vehicle) : 0;

  function commitSave() {
    if (kind === 'trip') {
      updateTrip(entryId, {
        platform: '', vehicle, // trips are platform-agnostic
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
        vehicle: showVehicle ? vehicle : record.vehicle,
        category: showDescription ? description : record.category,
        notes: showDescription ? description : record.notes,
        created_at: date.toISOString(),
      });
    }
    router.back();
  }

  function save() {
    // Editing changes figures HMRC could ask you to justify, so confirm first —
    // GPS-tracked trips especially carry the original recorded mileage.
    const isGps = kind === 'trip' && !!trip?.route_json;
    const msg = isGps
      ? 'This trip’s mileage was recorded by GPS. Editing it overwrites the original tracked figures used for your tax. Save anyway?'
      : 'This updates the figures used in your tax calculations. Save these changes?';
    Alert.alert('Save changes?', msg, [
      { text: 'Cancel', style: 'cancel' },
      { text: 'Save', onPress: commitSave },
    ]);
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
          <Pressable onPress={() => router.back()} hitSlop={12} style={s.closeBtn}>
            <Feather name="x" size={19} color={colors.textPrimary} />
          </Pressable>
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
              {platformOptions.map(p => (
                <Chip key={p} label={p} selected={platform === p} onPress={() => setPlatform(p)} />
              ))}
            </View>
          </>
        )}

        {showVehicle && (
          <>
            <SectionHeader title="Vehicle" />
            <View style={s.chips}>
              {myVehicles.map(v => (
                <VehicleChip key={v.key} vehicle={v.key} label={v.label} selected={vehicle === v.key} onPress={() => setVehicle(v.key)} />
              ))}
            </View>
          </>
        )}

        {showMiles && (
          <>
            <SectionHeader title="Miles" />
            <TextInput style={s.input} value={miles} onChangeText={setMiles} keyboardType="decimal-pad" placeholder="0" placeholderTextColor={colors.textTertiary} {...numberKeyboardDoneProps} />
            {milesNum > 0 ? <Text style={s.preview}>Deduction: {fmtGbp(previewDeduction)}</Text> : null}
            {vehicle === 'bike' && (
              <View style={s.reviewBox}>
                <Feather name="alert-triangle" size={16} color={colors.amber} />
                <View style={{ flex: 1 }}>
                  <Text style={s.reviewTitle}>Flagged for your accountant</Text>
                  <Text style={s.reviewText}>
                    HMRC’s simplified flat-rate mileage scheme officially covers cars, vans and motorcycles — not bicycles or e-bikes for the self-employed. The 20p/mile shown is the employee cycle rate, so Okkle keeps this as an estimate only. Your accountant should confirm whether to claim your actual cycle costs instead.
                  </Text>
                </View>
              </View>
            )}
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
            <TextInput style={s.input} value={amount} onChangeText={setAmount} keyboardType="decimal-pad" placeholder="0.00" placeholderTextColor={colors.textTertiary} {...numberKeyboardDoneProps} />
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
      <KeyboardDoneAccessory />
    </KeyboardAvoidingView>
  );
}

const s = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  content: { padding: spacing.xl, paddingTop: 60, paddingBottom: 60 },
  header: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: spacing.xl },
  heading: { ...type.screenTitle },
  closeBtn: { width: 34, height: 34, borderRadius: 17, alignItems: 'center', justifyContent: 'center', backgroundColor: 'rgba(34,48,44,0.10)' },
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
  reviewBox: { flexDirection: 'row', alignItems: 'flex-start', gap: 10, backgroundColor: colors.amberLight, borderRadius: radius.md, padding: spacing.lg, marginBottom: spacing.lg },
  reviewTitle: { ...type.label, color: colors.amberDark, marginBottom: 3 },
  reviewText: { ...type.caption, color: colors.amberDark, lineHeight: 19 },
  receipt: { width: '100%', height: 240, borderRadius: radius.md, backgroundColor: colors.bgSoft, marginBottom: spacing.lg },
  deleteBtn: { marginTop: spacing.lg, alignItems: 'center', paddingVertical: spacing.md },
  deleteText: { ...type.label, color: colors.red },
});
