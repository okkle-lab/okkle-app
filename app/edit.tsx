import React, { useState } from 'react';
import {
  View, Text, TextInput, ScrollView, StyleSheet, Pressable, Alert,
  KeyboardAvoidingView, Platform,
} from 'react-native';
import { useRouter, useLocalSearchParams } from 'expo-router';
import { colors, font, spacing, radius, type } from '../src/theme';
import { Chip, SectionHeader, PrimaryButton, VehicleChip } from '../src/components';
import { PLATFORMS, VEHICLES, calcDeduction, fmtGbp } from '../src/db/tax';
import {
  getTrip, updateTrip, deleteTrip, getRecord, updateRecord, deleteRecord,
} from '../src/db';

export default function EditEntry() {
  const router = useRouter();
  const { kind, id } = useLocalSearchParams<{ kind: string; id: string }>();
  const entryId = parseInt(id ?? '0', 10);

  const trip = kind === 'trip' ? getTrip(entryId) : null;
  const record = kind === 'record' ? getRecord(entryId) : null;

  const [platform, setPlatform] = useState(trip?.platform ?? record?.platform ?? 'Uber Eats');
  const [vehicle, setVehicle] = useState(trip?.vehicle ?? 'car');
  const [miles, setMiles] = useState(String(trip?.miles ?? record?.miles ?? ''));
  const [amount, setAmount] = useState(String(record?.amount ?? trip?.earnings ?? ''));
  const [description, setDescription] = useState(record?.category ?? record?.notes ?? '');

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
      });
    } else if (record) {
      updateRecord(entryId, {
        platform: showPlatform ? platform : record.platform,
        amount: showAmount && amount ? parseFloat(amount) : record.amount,
        miles: showMiles ? milesNum : record.miles,
        deduction: showMiles ? parseFloat(previewDeduction.toFixed(2)) : record.deduction,
        category: showDescription ? description : record.category,
        notes: showDescription ? description : record.notes,
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
  sub: { ...type.body, color: colors.textSecondary },
  chips: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm, marginBottom: spacing.lg },
  input: {
    borderWidth: 1.5, borderColor: colors.border, borderRadius: radius.md,
    padding: spacing.md, fontSize: 18, color: colors.textPrimary, backgroundColor: colors.bgCard,
    marginBottom: spacing.sm,
  },
  preview: { ...type.caption, color: colors.brandDeep, marginBottom: spacing.lg },
  deleteBtn: { marginTop: spacing.lg, alignItems: 'center', paddingVertical: spacing.md },
  deleteText: { ...type.label, color: colors.red },
});
