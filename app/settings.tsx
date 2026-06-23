import React, { useState } from 'react';
import {
  View, Text, TextInput, ScrollView, StyleSheet, Switch, Pressable, Alert,
} from 'react-native';
import { useRouter } from 'expo-router';
import { colors, font, spacing, radius, type } from '../src/theme';
import { Card, Chip, SectionHeader, PrimaryButton, VehicleChip, IconBadge } from '../src/components';
import {
  VEHICLES, PLATFORMS, REGIONS, regionRate, regionLabel,
} from '../src/db/tax';
import { getUser, saveUser, resetAllData, kvGet, kvSet } from '../src/db';
import { syncReminders, WEEKDAYS } from '../src/notifications';
import { backupNow, restoreFromFile } from '../src/backup';
import { Feather } from '@expo/vector-icons';

const DAY_LABELS: { [k: string]: string } = {
  sun: 'Sun', mon: 'Mon', tue: 'Tue', wed: 'Wed', thu: 'Thu', fri: 'Fri', sat: 'Sat',
};

export default function Settings() {
  const router = useRouter();
  const u = getUser();

  const [name, setName] = useState(u?.name ?? '');
  const [vehicle, setVehicle] = useState(u?.vehicle ?? 'car');
  const [platforms, setPlatforms] = useState<string[]>(u?.platforms?.split(',').filter(Boolean) ?? ['Uber Eats']);
  const [region, setRegion] = useState(u?.region ?? 'ruk');
  const [band, setBand] = useState<'basic' | 'higher'>((u?.tax_rate ?? 0.2) >= 0.4 ? 'higher' : 'basic');
  const [reminderOn, setReminderOn] = useState((u?.reminder_enabled ?? 1) === 1);
  const [reminderDay, setReminderDay] = useState(u?.reminder_day ?? 'sun');
  const [frequency, setFrequency] = useState(u?.log_frequency ?? 'weekly');
  const [deadlinesOn, setDeadlinesOn] = useState((kvGet('deadline_reminders') ?? 'on') !== 'off');

  function togglePlatform(p: string) {
    setPlatforms(prev => (prev.includes(p) ? prev.filter(x => x !== p) : [...prev, p]));
  }

  async function save() {
    kvSet('deadline_reminders', deadlinesOn ? 'on' : 'off');
    saveUser({
      name,
      vehicle,
      platforms: platforms.join(','),
      region,
      tax_rate: regionRate(region, band),
      reminder_enabled: reminderOn ? 1 : 0,
      reminder_day: reminderDay,
      log_frequency: frequency,
    });
    const updated = getUser();
    if (updated) await syncReminders(updated);
    router.back();
  }

  const [busy, setBusy] = useState(false);

  async function doBackup() {
    setBusy(true);
    try { await backupNow(); }
    catch { Alert.alert('Backup failed', 'Could not create the backup file.'); }
    setBusy(false);
  }

  function doRestore() {
    Alert.alert(
      'Restore from backup?',
      'This replaces all current data on this phone with the contents of the backup file.',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Choose file', onPress: async () => {
            setBusy(true);
            try {
              const r = await restoreFromFile();
              if (r) Alert.alert('Restored', `${r.trips} trips and ${r.records} records restored.`, [
                { text: 'OK', onPress: () => router.replace('/(tabs)') },
              ]);
            } catch {
              Alert.alert('Restore failed', "That file isn't a valid Okkle backup.");
            }
            setBusy(false);
          },
        },
      ],
    );
  }

  function confirmReset() {
    Alert.alert(
      'Delete all data?',
      'This permanently removes every trip, record and your profile from this phone. This cannot be undone.',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Delete everything', style: 'destructive', onPress: () => {
            resetAllData();
            router.replace('/onboarding');
          },
        },
      ],
    );
  }

  return (
    <ScrollView style={s.screen} contentContainerStyle={s.content}>
      <View style={s.header}>
        <Text style={s.heading}>Settings</Text>
        <Pressable onPress={() => router.back()} hitSlop={12}><Text style={s.close}>Done</Text></Pressable>
      </View>

      <SectionHeader title="Your details" />
      <Card style={{ gap: spacing.lg }}>
        <View>
          <Text style={s.fieldLabel}>Name</Text>
          <TextInput style={s.input} value={name} onChangeText={setName} placeholder="Your name" placeholderTextColor={colors.textTertiary} />
        </View>
        <View>
          <Text style={s.fieldLabel}>Default vehicle</Text>
          <View style={s.chips}>
            {VEHICLES.map(v => (
              <VehicleChip key={v.key} vehicle={v.key} label={v.label} selected={vehicle === v.key} onPress={() => setVehicle(v.key)} />
            ))}
          </View>
        </View>
        <View>
          <Text style={s.fieldLabel}>Platforms</Text>
          <View style={s.chips}>
            {PLATFORMS.map(p => (
              <Chip key={p} label={p} selected={platforms.includes(p)} onPress={() => togglePlatform(p)} />
            ))}
          </View>
        </View>
      </Card>

      <SectionHeader title="Tax region" />
      <Card style={{ gap: spacing.lg }}>
        <View>
          <Text style={s.fieldLabel}>Where you live</Text>
          <View style={s.chips}>
            {REGIONS.map(r => (
              <Chip key={r.key} label={r.label} selected={region === r.key} onPress={() => setRegion(r.key)} />
            ))}
          </View>
        </View>
        <View>
          <Text style={s.fieldLabel}>Income tax band</Text>
          <View style={s.chips}>
            <Chip label="Basic rate" selected={band === 'basic'} onPress={() => setBand('basic')} />
            <Chip label="Higher rate" selected={band === 'higher'} onPress={() => setBand('higher')} />
          </View>
        </View>
        <Text style={s.note}>
          Estimating take-home at {(regionRate(region, band) * 100).toFixed(0)}% ({regionLabel(region)}).
        </Text>
      </Card>

      <SectionHeader title="Reminders" />
      <Card style={{ gap: spacing.md }}>
        <View style={s.rowBetween}>
          <View style={{ flex: 1 }}>
            <Text style={s.rowTitle}>Logging reminder</Text>
            <Text style={s.rowSub}>A nudge to log your miles and earnings</Text>
          </View>
          <Switch
            value={reminderOn}
            onValueChange={setReminderOn}
            trackColor={{ true: colors.brand, false: colors.borderStrong }}
          />
        </View>
        {reminderOn && (
          <>
            <View>
              <Text style={s.fieldLabel}>Frequency</Text>
              <View style={s.chips}>
                <Chip label="Weekly" selected={frequency === 'weekly'} onPress={() => setFrequency('weekly')} />
                <Chip label="Monthly" selected={frequency === 'monthly'} onPress={() => setFrequency('monthly')} />
              </View>
            </View>
            <View>
              <Text style={s.fieldLabel}>Reminder day</Text>
              <View style={s.chips}>
                {WEEKDAYS.map(d => (
                  <Chip key={d} label={DAY_LABELS[d]} selected={reminderDay === d} onPress={() => setReminderDay(d)} />
                ))}
              </View>
            </View>
          </>
        )}
        <View style={s.divider} />
        <View style={s.rowBetween}>
          <View style={{ flex: 1 }}>
            <Text style={s.rowTitle}>Tax deadline reminders</Text>
            <Text style={s.rowSub}>Self Assessment, payment & MTD dates</Text>
          </View>
          <Switch
            value={deadlinesOn}
            onValueChange={setDeadlinesOn}
            trackColor={{ true: colors.brand, false: colors.borderStrong }}
          />
        </View>
      </Card>

      <SectionHeader title="Help" />
      <Card style={{ gap: spacing.md }}>
        <Pressable onPress={() => { kvSet('coach_seen', ''); kvSet('coach_trip_seen', ''); router.back(); }} style={s.actionRow}>
          <IconBadge icon="help-circle" tone="mint" />
          <Text style={s.actionText}>Replay the app tour</Text>
          <Feather name="chevron-right" size={18} color={colors.textTertiary} />
        </Pressable>
      </Card>

      <SectionHeader title="About" />
      <Card style={{ gap: spacing.md }}>
        <Text style={s.aboutText}>
          Okkle keeps a record of your delivery mileage and earnings so you (or your accountant) have what you need at tax time.
        </Text>
        <Text style={s.aboutText}>
          Mileage deductions use HMRC's approved simplified rates: 45p/mile for cars and vans (25p after 10,000 miles in a tax year), 24p for motorbikes and 20p for bicycles. These rates are the same across the whole UK.
        </Text>
        <Text style={s.aboutText}>
          All your data is stored only on this phone — nothing is sent to a server. Okkle is a record-keeping tool and does not provide tax advice or file your return.
        </Text>
      </Card>

      <SectionHeader title="Backup & restore" />
      <Card style={{ gap: spacing.md }}>
        <Text style={s.aboutText}>
          Your data lives only on this phone. Back it up to your own iCloud or Files so you don't lose your records — HMRC expects records kept for at least 5 years.
        </Text>
        <Pressable onPress={doBackup} disabled={busy} style={s.actionRow}>
          <IconBadge icon="upload-cloud" tone="mint" />
          <Text style={s.actionText}>Back up my data</Text>
          <Feather name="chevron-right" size={18} color={colors.textTertiary} />
        </Pressable>
        <View style={s.divider} />
        <Pressable onPress={doRestore} disabled={busy} style={s.actionRow}>
          <IconBadge icon="download-cloud" tone="green" />
          <Text style={s.actionText}>Restore from a backup</Text>
          <Feather name="chevron-right" size={18} color={colors.textTertiary} />
        </Pressable>
      </Card>

      <PrimaryButton label="Save changes" onPress={save} style={{ marginTop: spacing.xl }} />

      <Pressable onPress={confirmReset} style={s.resetBtn}>
        <Text style={s.resetText}>Delete all my data</Text>
      </Pressable>
    </ScrollView>
  );
}

const s = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  content: { padding: spacing.xl, paddingTop: 60, paddingBottom: 60 },
  header: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: spacing.xl },
  heading: { ...type.screenTitle },
  close: { ...type.bodyMedium, color: colors.brandDeep },
  fieldLabel: { ...type.label, marginBottom: 8 },
  input: {
    borderWidth: 1.5, borderColor: colors.border, borderRadius: radius.md,
    padding: spacing.md, fontSize: 17, color: colors.textPrimary, backgroundColor: colors.bg,
  },
  chips: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm },
  note: { ...type.caption, color: colors.textTertiary },
  rowBetween: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  rowTitle: { ...type.bodyMedium, fontSize: 15 },
  rowSub: { ...type.caption, marginTop: 2 },
  aboutText: { ...type.caption, color: colors.textSecondary, lineHeight: 20 },
  actionRow: { flexDirection: 'row', alignItems: 'center', gap: 12, paddingVertical: 4 },
  actionText: { ...type.bodyMedium, fontSize: 15, flex: 1 },
  divider: { height: 1, backgroundColor: colors.border },
  resetBtn: { marginTop: spacing.xl, alignItems: 'center', paddingVertical: spacing.md },
  resetText: { ...type.label, color: colors.red },
});
