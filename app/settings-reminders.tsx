import React, { useState } from 'react';
import { Platform, View, Text, ScrollView, StyleSheet, Switch, Pressable } from 'react-native';
import { useRouter } from 'expo-router';
import { Feather } from '@expo/vector-icons';
import { colors, font, spacing, radius, type } from '../src/theme';
import { Card, Chip, SectionHeader, PrimaryButton, ModalHeader } from '../src/components';
import { getUser, saveUser, kvGet, kvSet } from '../src/db';
import { syncReminders, WEEKDAYS } from '../src/notifications';

const DAY_LABELS: { [k: string]: string } = { sun: 'Sun', mon: 'Mon', tue: 'Tue', wed: 'Wed', thu: 'Thu', fri: 'Fri', sat: 'Sat' };

export default function SettingsReminders() {
  const router = useRouter();
  const u = getUser();
  const [reminderOn, setReminderOn] = useState((u?.reminder_enabled ?? 1) === 1);
  const [reminderDay, setReminderDay] = useState(u?.reminder_day ?? 'sun');
  const [frequency, setFrequency] = useState(u?.log_frequency ?? 'weekly');
  const [deadlinesOn, setDeadlinesOn] = useState((kvGet('deadline_reminders') ?? 'on') !== 'off');

  async function save() {
    kvSet('deadline_reminders', deadlinesOn ? 'on' : 'off');
    saveUser({ reminder_enabled: reminderOn ? 1 : 0, reminder_day: reminderDay, log_frequency: frequency });
    const updated = getUser();
    if (updated) await syncReminders(updated);
    router.back();
  }

  return (
    <ScrollView style={s.screen} contentContainerStyle={s.content}>
      <ModalHeader title="Reminders" />

      <Card style={{ gap: spacing.md }}>
        <View style={s.rowBetween}>
          <View style={{ flex: 1 }}>
            <Text style={s.rowTitle}>Logging reminder</Text>
            <Text style={s.rowSub}>A nudge to log your miles and earnings</Text>
          </View>
          <Switch value={reminderOn} onValueChange={setReminderOn} trackColor={{ true: colors.brand, false: colors.borderStrong }} />
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
                {WEEKDAYS.map(d => <Chip key={d} label={DAY_LABELS[d]} selected={reminderDay === d} onPress={() => setReminderDay(d)} />)}
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
          <Switch value={deadlinesOn} onValueChange={setDeadlinesOn} trackColor={{ true: colors.brand, false: colors.borderStrong }} />
        </View>
      </Card>

      <Pressable onPress={() => router.push('/key-dates')} style={({ pressed }) => [s.linkRow, pressed && { opacity: 0.6 }]}>
        <Feather name="calendar" size={18} color={colors.brandDeep} />
        <Text style={s.linkText}>Key tax dates & HMRC deadlines</Text>
        <Feather name="chevron-right" size={18} color={colors.textTertiary} />
      </Pressable>

      <PrimaryButton label="Save changes" onPress={save} style={{ marginTop: spacing.lg }} />
    </ScrollView>
  );
}

const s = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.bg },
  content: { padding: spacing.xl, paddingTop: 60, paddingBottom: 60 },
  header: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center', marginBottom: spacing.xl },
  heading: { ...type.heading, fontSize: 18 },
  close: { ...type.bodyMedium, color: colors.textSecondary },
  fieldLabel: { ...type.label, marginBottom: 8 },
  chips: { flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm },
  rowBetween: { flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between' },
  rowTitle: { ...type.bodyMedium, fontSize: 15 },
  rowSub: { ...type.caption, marginTop: 2 },
  divider: { height: 1, backgroundColor: colors.border },
  linkRow: { flexDirection: 'row', alignItems: 'center', gap: 10, marginTop: spacing.lg, paddingVertical: spacing.sm },
  linkText: { ...type.bodyMedium, fontSize: 15, color: colors.textPrimary, flex: 1 },
});
